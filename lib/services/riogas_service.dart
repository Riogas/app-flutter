import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io'; // Import for SocketException
import 'package:hive/hive.dart';
import '../utils/error_event.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import 'dart:async'; // Import for Timer
import '../utils/constantes.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../services/auth_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/debug_config_manager.dart';
import 'package:flutter/services.dart';

class RioGasService {
  // 🔓 HTTP Client que ignora certificados SSL
  static http.Client? _httpClient;

  // ⏱️ Control de throttling para connectivity check
  static DateTime? _lastConnectivityCheck;
  static bool? _lastConnectivityResult;
  static const Duration _connectivityCheckInterval = Duration(seconds: 5);

  // � Lock para evitar ejecuciones concurrentes de processPendingRequests
  static bool _isProcessingPendingRequests = false;

  // �🔄 Método para resetear el cliente HTTP (útil al cambiar de ambiente)
  static void resetHttpClient() {
    if (_httpClient != null) {
      _httpClient!.close();
      _httpClient = null;
      print('🔄 [HTTP_CLIENT] Cliente HTTP reseteado');
    }
  }

  static http.Client get _client {
    if (_httpClient == null) {
      print('🔍 [HTTP_CLIENT] Creando nuevo cliente HTTP');

      // ✅ SIEMPRE validar SSL (tanto desarrollo como producción)
      _httpClient = http.Client();
      print(
          '✅ [HTTP_CLIENT] Cliente HTTP creado con validación SSL habilitada');
    }
    return _httpClient!;
  }

  /// Llama al servicio DescargaPedidosV2 con el body especificado.
  /// [sdtPedidos] debe ser una lista de mapas con la clave 'PedidoId'.
  static Future<Map<String, dynamic>?> descargaPedidos(
    int escenarioId,
    List<Map<String, dynamic>> sdtPedidos,
    String pedidoTpo,
    String usuario,
    String nroSesion,
    String termMobileEquipo,
    String lectDesc,
    String fechaHoraCmbEst,
    String inAux1,
    String inAux2,
    String latitud,
    String longitud,
    String utmX,
    String utmY,
    double velocidad,
    double distanciaRecorrida,
  ) async {
    velocidad = double.parse(velocidad.toStringAsFixed(2));
    distanciaRecorrida = double.parse(distanciaRecorrida.toStringAsFixed(2));

    // 🚩 Obtener flag 'services_need_restart' desde SharedPreferences nativo
    bool despertar = false;
    try {
      final servicesNeedRestart = await getServicesNeedRestart();
      despertar = servicesNeedRestart ?? false;
      print('🚩 [DescargaPedidosV2] Despertar servicios: $despertar');
    } catch (e) {
      print('❌ [DescargaPedidosV2] Error obteniendo flag despertar: $e');
    }

    return _post('DescargaPedidosV2', {
      'token': token,
      'escenarioid': escenarioId,
      'sdtPedidos': sdtPedidos,
      'PedidoTpo': pedidoTpo,
      'usuario': usuario,
      'NroSesion': nroSesion,
      'TermMobileEquipo': termMobileEquipo,
      'LectDesc': lectDesc,
      'FechaHoraCmbEst': fechaHoraCmbEst,
      'INAux1': inAux1,
      'INAux2': inAux2,
      'Latitud': latitud,
      'longitud': longitud,
      'utmX': utmX,
      'utmY': utmY,
      'Velocidad': velocidad,
      'DistanciaRecorrida': distanciaRecorrida,
      'Despertar': despertar // 🆕 Flag para despertar servicios
    });
  }

  static late final String _baseUrlProduction;
  static bool _isInitialized =
      false; // 🆕 Flag para prevenir doble inicialización

  // 🌍 Getter dinámico que devuelve la URL según el ambiente
  static String get baseUrl {
    // Si está en desarrollo, usar URL de constante 611
    if (AppEnvironment.isDevelopment) {
      return AppEnvironment.devUrl;
    }
    // Si está en producción, usar la URL configurada desde constantes 600+601
    return _baseUrlProduction;
  }

  /* aca la constante */
  static const Map<String, String> headers = {
    'accept': 'application/json',
    'Content-Type': 'application/json',
    'Cookie': 'GX_CLIENT_ID=3fc38cab-575b-44c7-af56-339c14d664f0',
  };
  static const String token = 'IcA.FwL.1710.!';

  static DateTime? _lastErrorTime; // Track the last error time
  static const int errorThresholdMinutes =
      5; // Threshold in minutes - CONSTANTE
  static late int retryIntervalSeconds;

  static Future<void> initializeRetryInterval() async {
    String? value = await getConstantValue('110');
    retryIntervalSeconds = int.tryParse(value ?? '0') ?? 0;
  }

  static Timer? _retryTimer;

  static Future<void> startRetryTimer() async {
    // print('🔄 Iniciando el temporizador de reintentos.');
    if (_retryTimer != null && _retryTimer!.isActive) {
      print('🔄 Timer ya está activo, no iniciando otro.');
      return;
    }

    var failedRequestsBox = await Hive.openBox('failedRequestsBox');
    print(
        "📦 failedRequestsBox contiene ${failedRequestsBox.length} elementos");

    if (failedRequestsBox.isNotEmpty) {
      print('📦 Requests pendientes encontrados: ${failedRequestsBox.length}');
      print(
          '⏱️ Configurando retry timer con intervalo: $retryIntervalSeconds segundos.');

      _retryTimer = Timer.periodic(Duration(seconds: retryIntervalSeconds),
          (timer) async {
        // print('🔄 Timer ejecutándose. Procesando requests pendientes...');
        try {
          await processPendingRequests();

          // Verificar si el box está vacío después del procesamiento
          var updatedBox = await Hive.openBox('failedRequestsBox');
          if (updatedBox.isEmpty) {
            print('✅ Todos los pendientes procesados. Deteniendo timer.');
            timer.cancel();
            _retryTimer = null;
          }
          // else {
          //   print('📦 Aún quedan ${updatedBox.length} requests pendientes.');
          // }
        } catch (e) {
          print('❌ Error en el callback del retry timer: $e');
        }
      });

      print('🔄 Retry timer iniciado correctamente.');
    } else {
      print('⚠️ No hay requests pendientes en failedRequestsBox.');
    }
  }

  // Ensure the timer starts at least once during initialization
  static Future<void> initializeService() async {
    // 🆕 PROTECCIÓN: Evitar doble inicialización
    if (_isInitialized) {
      print('⚠️ [INIT] RioGasService ya está inicializado, saltando...');
      return;
    }

    // 👇 NUEVO: inicializar baseUrl dinámico con 600 (base) + 601 (appservices)
    print('🔧 [INIT] Inicializando configuración de URLs...');
    final baseRootConst = (await getConstantValue('600'))?.trim();
    final servicesPathConst = (await getConstantValue('601'))?.trim();

    print('🔧 [INIT] Constante 600 (base): "$baseRootConst"');
    print('🔧 [INIT] Constante 601 (services): "$servicesPathConst"');

    var baseRoot = (baseRootConst != null && baseRootConst.isNotEmpty)
        ? baseRootConst
        : 'https://www.riogas.uy/ica_geos_/';

    var servicesPath =
        (servicesPathConst != null && servicesPathConst.isNotEmpty)
            ? servicesPathConst
            : 'appservices/';

    print('🔧 [INIT] Base root inicial: "$baseRoot"');
    print('🔧 [INIT] Services path inicial: "$servicesPath"');

    // Normalizaciones: quitar 'appservices/' del base por si viene duplicado, slashes correctos
    baseRoot = baseRoot.replaceAll(
        RegExp(r'appservices/?$', caseSensitive: false), '');
    if (!baseRoot.endsWith('/')) baseRoot += '/';
    if (servicesPath.startsWith('/')) servicesPath = servicesPath.substring(1);
    if (!servicesPath.endsWith('/')) servicesPath += '/';

    _baseUrlProduction = '$baseRoot$servicesPath';

    print('🔧 [INIT] Base root normalizado: "$baseRoot"');
    print('🔧 [INIT] Services path normalizado: "$servicesPath"');
    print('🔧 [INIT] ===== URL FINAL CONFIGURADA =====');
    print('🔧 [INIT] baseUrl PRODUCCIÓN (600+601) = "$_baseUrlProduction"');
    print('🔧 [INIT] baseUrl DESARROLLO (611) = "${AppEnvironment.devUrl}"');
    print('🌍 [INIT] Ambiente actual: ${AppEnvironment.environmentName}');
    print('🔧 [INIT] =====================================');

    await initializeRetryInterval();

    _isInitialized = true; // 🆕 Marcar como inicializado
    print('✅ [INIT] RioGasService inicializado correctamente');
    await deleteOldRequests();
    await _setupFailedRequestsListener(); // Configurar listener separado

    // Verificar si ya hay requests pendientes e iniciar timer inmediatamente
    var failedRequestsBox = await Hive.openBox('failedRequestsBox');
    if (failedRequestsBox.isNotEmpty) {
      print(
          '🔄 Hay ${failedRequestsBox.length} requests pendientes. Iniciando timer inmediatamente.');
      await startRetryTimer();
    }
  }

  static Future<void> _setupFailedRequestsListener() async {
    var failedRequestsBox = await Hive.openBox('failedRequestsBox');

    failedRequestsBox.watch().listen((BoxEvent event) async {
      print(
          '📦 Cambio detectado en failedRequestsBox: ${event.key} - ${event.value != null ? "AGREGADO" : "ELIMINADO"}');

      if (event.value != null) {
        // Se agregó un nuevo item
        print(
            '📦 Nuevo request agregado. Total en box: ${failedRequestsBox.length}');
        await startRetryTimer();
      } else {
        // Se eliminó un item
        print(
            '📦 Request eliminado. Total en box: ${failedRequestsBox.length}');
        if (failedRequestsBox.isEmpty) {
          print('📦 Box vacío, deteniendo timer si existe.');
          _retryTimer?.cancel();
          _retryTimer = null;
        }
      }
    });
  }

  /// Envía el error a n8n para monitoreo centralizado
  static Future<void> _sendErrorToN8n(
    String endpoint,
    Map<String, dynamic> payload,
    String errorMessage,
  ) async {
    try {
      print('📤 [N8N_ERROR] Enviando error a n8n: $endpoint');

      final sessionBox = await Hive.openBox('sessionBox');
      final String? movil = sessionBox.get('movil');
      final String? username = sessionBox.get('username');
      final String? deviceId = sessionBox.get('deviceId');
      final String? escenario = sessionBox.get('escenario');

      // Construir payload para n8n
      final n8nPayload = {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'endpoint': endpoint,
        'errorMessage': errorMessage,
        'payload': payload,
        'movilId': movil,
        'username': username,
        'deviceId': deviceId,
        'escenarioId': escenario,
        'appVersion': '1.0.0', // Puedes obtenerlo de package_info si lo tienes
      };

      final response = await http
          .post(
            Uri.parse('https://n8n.riogas.com.uy/webhook/ProcesarErrores'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(n8nPayload),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✅ [N8N_ERROR] Error enviado exitosamente a n8n');
        print('✅ [N8N_ERROR] Response: ${response.body}');
      } else {
        print(
            '⚠️ [N8N_ERROR] n8n respondió con código: ${response.statusCode}');
        print('⚠️ [N8N_ERROR] Response: ${response.body}');
      }
    } on TimeoutException {
      print('⏰ [N8N_ERROR] Timeout enviando error a n8n (10s)');
    } on SocketException {
      print('❌ [N8N_ERROR] Sin conexión a internet para enviar a n8n');
    } catch (e) {
      print('❌ [N8N_ERROR] Error enviando a n8n: $e');
      // No lanzamos excepción para no interrumpir el guardado en failedRequestsBox
    }
  }

  static Future<void> _saveFailedRequest(
    String? endpoint,
    Map<String, dynamic>? payload, {
    String? errorMessage, // 🆕 Mensaje de error opcional
  }) async {
    if (endpoint == null || payload == null) return;

    final failedRequestsBox = await Hive.openBox('failedRequestsBox');
    print('📦 [SAVE_FAILED] Intentando guardar request fallido: $endpoint');
    print('📦 [SAVE_FAILED] Total actual en box: ${failedRequestsBox.length}');
    if (errorMessage != null) {
      print('📦 [SAVE_FAILED] Error: $errorMessage');
    }

    // Para endpoints V3 (y V2 legacy) deduplicamos por firma JSON del payload
    final v3Endpoints = [
      'FinalizarPedidoV3',
      'FinalizarPedidoV2',
      'DescargaPedidosV2',
      'DescargaPedidos',
      'DescargaLecturaMensajesV2',
      'DescargaLecturaMensajes',
      'DescargaLecturaPedidosV2',
      'DescargaLecturaPedidos'
    ];

    if (v3Endpoints.contains(endpoint)) {
      // 🎯 Deduplicación por LÓGICA DE NEGOCIO (ID del recurso)
      // En lugar de comparar todo el payload, solo comparamos el identificador único

      // 1️⃣ Extraer el ID relevante según el endpoint
      String? businessKey;
      String businessKeyName = '';

      if (endpoint.contains('FinalizarPedido')) {
        businessKey = payload['PedidoId']?.toString();
        businessKeyName = 'PedidoId';
      } else if (endpoint.contains('DescargaPedidos') ||
          endpoint.contains('DescargaLecturaPedidos')) {
        businessKey = payload['PedidoId']?.toString();
        businessKeyName = 'PedidoId';
      } else if (endpoint.contains('DescargaLecturaMensajes')) {
        businessKey = payload['MessageId']?.toString();
        businessKeyName = 'MessageId';
      }

      if (businessKey == null) {
        print('⚠️ [DEDUP_CHECK] No se pudo extraer ID de negocio del payload');
        // Si no hay ID, no podemos deduplicar, guardamos el request
      } else {
        print('🔍 [DEDUP_CHECK] Endpoint V3 detectado: $endpoint');
        print(
            '🔍 [DEDUP_CHECK] Clave de negocio: $businessKeyName = $businessKey');
        print(
            '🔍 [DEDUP_CHECK] Buscando duplicados en ${failedRequestsBox.length} requests...');

        // 2️⃣ Buscar duplicados comparando endpoint + ID de negocio
        final exists = failedRequestsBox.values.any((request) {
          try {
            final map = Map<String, dynamic>.from(request as Map);

            // Debe ser el mismo endpoint (o su versión V2/V3)
            final savedEndpoint = map['endpoint'] as String;
            final isSameEndpointFamily =
                (endpoint.contains('FinalizarPedido') &&
                        savedEndpoint.contains('FinalizarPedido')) ||
                    (endpoint.contains('DescargaPedidos') &&
                        savedEndpoint.contains('DescargaPedidos')) ||
                    (endpoint.contains('DescargaLecturaPedidos') &&
                        savedEndpoint.contains('DescargaLecturaPedidos')) ||
                    (endpoint.contains('DescargaLecturaMensajes') &&
                        savedEndpoint.contains('DescargaLecturaMensajes'));

            if (!isSameEndpointFamily) {
              return false; // Diferente familia de endpoint, no es duplicado
            }

            // Extraer el ID del request guardado
            final savedPayload =
                Map<String, dynamic>.from(map['payload'] as Map);
            final savedBusinessKey = savedPayload[businessKeyName]?.toString();

            final isDuplicate = savedBusinessKey == businessKey;

            if (isDuplicate) {
              print('🔍 [DEDUP_CHECK] ⚠️ DUPLICADO ENCONTRADO!');
              print('🔍 [DEDUP_CHECK]    - Endpoint guardado: $savedEndpoint');
              print(
                  '🔍 [DEDUP_CHECK]    - $businessKeyName guardado: $savedBusinessKey');
              print(
                  '🔍 [DEDUP_CHECK]    - Timestamp guardado: ${map['timestamp']}');
              print(
                  '🔍 [DEDUP_CHECK]    - ✅ Mismo recurso, NO se debe duplicar');
            }

            return isDuplicate;
          } catch (e) {
            print('🔍 [DEDUP_CHECK] ⚠️ Error comparando request: $e');
            return false;
          }
        });

        if (exists) {
          print(
              '⚠️ [DEDUP_BLOCKED] Request duplicado detectado para $endpoint');
          print(
              '⚠️ [DEDUP_BLOCKED] $businessKeyName: $businessKey ya está en cola de reintentos');
          print(
              '⚠️ [DEDUP_BLOCKED] ✅ Control de duplicados funcionando correctamente!');
          return;
        }
      }

      // 3️⃣ No es duplicado, guardar el request
      await failedRequestsBox.add({
        'endpoint': endpoint,
        'payload': payload,
        'businessKey': businessKey, // 🆕 Guardar el ID para referencia
        'businessKeyName': businessKeyName, // 🆕 Guardar el nombre del campo
        'timestamp': DateTime.now().toIso8601String(),
      });
      print('✅ [SAVED] Request $endpoint guardado exitosamente');
      print('✅ [SAVED] $businessKeyName: $businessKey');
      print('✅ [SAVED] Total en box: ${failedRequestsBox.length}');

      // 🆕 Enviar error a n8n después de guardar exitosamente
      await _sendErrorToN8n(
        endpoint,
        payload,
        errorMessage ?? 'Error desconocido - request fallido',
      );

      return;
    }

    // Resto de endpoints (salvo los prohibidos que ya filtramos antes)
    print('🔍 [DEDUP_CHECK] Endpoint no-V3: $endpoint');
    print(
        '🔍 [DEDUP_CHECK] Buscando duplicados en ${failedRequestsBox.length} requests...');

    final exists = failedRequestsBox.values.any((request) {
      try {
        final map = Map<String, dynamic>.from(request as Map);
        // dedupe básico por endpoint+payload textual
        final isDuplicate = map['endpoint'] == endpoint &&
            Map<String, dynamic>.from(map['payload'] as Map).toString() ==
                payload.toString();

        if (isDuplicate) {
          print('🔍 [DEDUP_CHECK] ⚠️ DUPLICADO ENCONTRADO!');
          print('🔍 [DEDUP_CHECK]    - Endpoint guardado: ${map['endpoint']}');
          print(
              '🔍 [DEDUP_CHECK]    - Timestamp guardado: ${map['timestamp']}');
        }

        return isDuplicate;
      } catch (_) {
        return false;
      }
    });

    if (exists) {
      print(
          '⚠️ [DEDUP_BLOCKED] Request duplicado detectado para $endpoint, NO se guarda.');
      print(
          '⚠️ [DEDUP_BLOCKED] ✅ Control de duplicados funcionando correctamente!');
      return;
    }

    await failedRequestsBox.add({
      'endpoint': endpoint,
      'payload': payload,
      'timestamp': DateTime.now().toIso8601String(),
    });

    print('✅ [SAVED] Request $endpoint guardado exitosamente');
    print('✅ [SAVED] Total en box: ${failedRequestsBox.length}');

    // 🆕 Enviar error a n8n después de guardar exitosamente
    await _sendErrorToN8n(
      endpoint,
      payload,
      errorMessage ?? 'Error desconocido - request fallido',
    );
  }

  // Método para verificar conectividad RioGas en tiempo real
  static Future<bool> _checkRioGasConnectivity() async {
    try {
      // ⏱️ Throttling: Si ya se verificó hace menos de 5 segundos, retornar resultado cacheado
      if (_lastConnectivityCheck != null) {
        final timeSinceLastCheck =
            DateTime.now().difference(_lastConnectivityCheck!);
        if (timeSinceLastCheck < _connectivityCheckInterval) {
          // print('⏱️ [RioGasService] Usando resultado cacheado (último check hace ${timeSinceLastCheck.inSeconds}s)');
          return _lastConnectivityResult ?? false;
        }
      }

      // print('🔍 [RioGasService] Chequeando conectividad RioGas...');
      var sessionBox = await Hive.openBox('sessionBox');
      var deviceId = sessionBox.get('deviceId');

      if (deviceId == null || (deviceId is String && deviceId.isEmpty)) {
        print(
            '❌ [RioGasService] No deviceId found for RioGas connectivity check');
        _lastConnectivityCheck = DateTime.now();
        _lastConnectivityResult = false;
        return false;
      }

      // print('📱 [RioGasService] Usando deviceId: $deviceId');

      // Crear el body que se va a enviar
      // Map<String, dynamic> requestBody = {'DeviceId': deviceId, 'token': token};
      // print(
      //     '📤 [RioGasService] Body completo a enviar: ${jsonEncode(requestBody)}');
      // print('🌐 [RioGasService] URL completa: ${baseUrl}ValidarDispositivo');

      var response = await validarDispositivo(deviceId);

      // print(
      //     '📥 [RioGasService] Respuesta COMPLETA del servicio: ${response != null ? jsonEncode(response) : 'NULL'}');

      if (response == null) {
        print('❌ [RioGasService] RioGas response is null');
        _lastConnectivityCheck = DateTime.now();
        _lastConnectivityResult = false;
        return false;
      }

      bool isConnected = response['Existe'] == true ||
          response['success'] == true ||
          response['OK'] == 0 ||
          response['ok'] == 0;

      print('🔍 [RioGasService] Evaluando respuesta:');
      print('   - response["Existe"]: ${response['Existe']}');
      print('   - response["success"]: ${response['success']}');
      print('   - response["OK"]: ${response['OK']}');
      print('   - response["ok"]: ${response['ok']}');
      print('   - Resultado final isConnected: $isConnected');

      print(
          '🌐 [RioGasService] RioGas connectivity result: ${isConnected ? "✅ Connected" : "❌ Disconnected"}');

      // 💾 Guardar resultado y timestamp
      _lastConnectivityCheck = DateTime.now();
      _lastConnectivityResult = isConnected;

      return isConnected;
    } catch (e) {
      print('❌ [RioGasService] RioGas connectivity error: $e');
      await _logError('RioGasService Connectivity Error', e.toString());

      // 💾 Guardar resultado de error
      _lastConnectivityCheck = DateTime.now();
      _lastConnectivityResult = false;

      return false;
    }
  }

  static Future<void> processPendingRequests() async {
    const tag = '📦[FAILED_SYNC]';

    // 🔒 Lock: Si ya está procesando, salir inmediatamente
    if (_isProcessingPendingRequests) {
      // print('$tag ⏭️ Ya hay un procesamiento en curso. Saliendo...');
      return;
    }

    // 🔒 Marcar como procesando
    _isProcessingPendingRequests = true;

    try {
      // print('$tag ▶️ Iniciando procesamiento de requests pendientes...');

      final failedRequestsBox = await Hive.openBox('failedRequestsBox');
      final conexionBox = await Hive.openBox('conexionBox');

      // ✅ SIEMPRE asumir que RioGas está conectado
      // No hacer verificación de conectividad aquí - esto se maneja en otro lado
      await conexionBox.put('conexionRioGas', true);
      await conexionBox.put(
          'conexionRioGasTimestamp', DateTime.now().toIso8601String());

      print('$tag 🔍 Recuperando requests pendientes...');
      final rawMap = failedRequestsBox.toMap();
      List<MapEntry<dynamic, Map<String, dynamic>>> pendingRequests =
          rawMap.entries
              .map((entry) {
                try {
                  final map = Map<String, dynamic>.from(entry.value as Map);
                  return MapEntry(entry.key, map);
                } catch (error) {
                  print(
                      '$tag ❌ Error parseando request con key ${entry.key}: $error');
                  return null;
                }
              })
              .whereType<MapEntry<dynamic, Map<String, dynamic>>>()
              .toList();

      print(
          '$tag 📋 Se encontraron ${pendingRequests.length} requests pendientes.');

      if (pendingRequests.isEmpty) {
        print('$tag ✅ No hay requests pendientes para procesar.');
        return;
      }

      for (var entry in pendingRequests) {
        // delay defensivo para no saturar el backend
        await Future.delayed(const Duration(seconds: 1));

        final key = entry.key;
        final request = entry.value;

        try {
          final endpoint = request['endpoint'] ?? 'UNKNOWN';
          final payload = Map<String, dynamic>.from(request['payload'] ?? {});
          final timestamp = request['timestamp'];

          if (request['processed'] == true) {
            print(
                '$tag ⏩ Request con key $key ya estaba marcada como procesada. Se omite.');
            continue;
          }

          // Endpoints que no reintentamos desde failedRequestsBox
          if (endpoint == 'RegistrarErrores' ||
              endpoint == 'RegistrarCoordenadasV2' ||
              endpoint == 'ValidarDispositivo') {
            print('$tag ⛔ Endpoint $endpoint ignorado. No se reintenta.');
            continue;
          }

          print(
              '$tag 🌐 Enviando [$endpoint] con payload: ${jsonEncode(payload)}');
          if (timestamp != null) {
            print('$tag 🕒 Timestamp original: $timestamp');
          }

          final response = await _post(endpoint, payload);

          if (response != null) {
            print('$tag ✅ [$endpoint] procesado correctamente.');
            await failedRequestsBox.delete(key);
            print('$tag 🗑️ Eliminado request con key $key');

            // 🔁 CHANGE: actualizar estado en Hive cuando FinalizarPedidoV2 (o FinalizarPedido) fue OK
            if ((endpoint == 'FinalizarPedidoV2' ||
                    endpoint == 'FinalizarPedido') &&
                payload.containsKey('PedidoId')) {
              final pedidosBox = await Hive.openBox('pedidosBox');
              final pedidoId = payload['PedidoId'];
              if (pedidosBox.containsKey(pedidoId)) {
                await pedidosBox.put(pedidoId, 'Procesando');
                print("📥 [HIVE] Pedido $pedidoId marcado como 'Procesando'");
              } else {
                print(
                    "ℹ️ [HIVE] pedidosBox no contiene la clave $pedidoId (no se actualiza).");
              }
            }
          } else {
            print(
                '$tag ⚠️ Error al procesar [$endpoint] con key $key. Se mantiene en box.');
            print('$tag 📦 Payload: ${jsonEncode(payload)}');

            // Si falla, marcar conexión como perdida para que ConnectionCheck tome control
            await conexionBox.put('conexionRioGas', false);
            print(
                '$tag ❌ Marcando conexionRioGas=false debido a fallo en request.');
            break; // Salir del bucle para que ConnectionCheck maneje la reconexión
          }
        } catch (e, st) {
          print('$tag ❌ Error al procesar request con key $key: $e');
          print(st);

          // Marcar conexión como perdida en caso de excepción
          await conexionBox.put('conexionRioGas', false);
          print('$tag ❌ Marcando conexionRioGas=false debido a excepción.');

          // (Opcional) Mantener rollback de estado si falla FinalizarPedido/FinalizarPedidoV2
          if ((request['endpoint'] == 'FinalizarPedidoV2' ||
                  request['endpoint'] == 'FinalizarPedido') &&
              request['payload'] is Map &&
              request['payload'].containsKey('PedidoId')) {
            final pedidoId = request['payload']['PedidoId'];
            final pedidosBox = await Hive.openBox('pedidosBox');
            if (pedidosBox.containsKey(pedidoId)) {
              await pedidosBox.put(pedidoId, 'Enviando');
              print(
                  '$tag ↩️ Pedido $pedidoId marcado como "Enviando" por error');
            }
          }
          break; // Salir del bucle
        }
      }

      print('$tag 🏁 Procesamiento finalizado.');
      final restantes = failedRequestsBox.length;
      print('$tag 📦 Requests restantes en box: $restantes');

      if (restantes > 0) {
        failedRequestsBox.toMap().forEach((key, value) {
          print(
              '$tag 🧾 Pendiente -> Key: $key | Endpoint: ${value['endpoint']}');
        });
      } else {
        print('$tag ✅ No quedan requests pendientes.');
      }
    } finally {
      // 🔓 Liberar lock siempre
      _isProcessingPendingRequests = false;
    }
  }

  static Future<Map<String, dynamic>?> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      // Process the version value to include only the number
      if (body.containsKey('version')) {
        body['version'] = body['version'].replaceAll(RegExp(r'[^0-9.]'), '');
      }

      if (endpoint == 'RegistrarCoordenadasV2') {
        /*print('📦 Processing RegistrarCoordenadasV2...');
        print('📦 RegistrarCoordenadasV2 Body: $body');*/
      }

      if (endpoint == 'RegistrarCoordenadasV2Batch') {
        // Ensure Latitud, longitud, and FechaHora are inside "data"
        var failedRequestsBox = await Hive.openBox('failedRequestsBox');

        // Filter pending requests for 'RegistrarCoordenadasV2'
        List<Map<String, dynamic>> pendingRequests = failedRequestsBox.values
            .where((request) => request['endpoint'] == 'RegistrarCoordenadasV2')
            .map((request) => Map<String, dynamic>.from(request['payload']))
            .toList();

        // Sort by FechaHora to ensure chronological order
        pendingRequests
            .sort((a, b) => a['FechaHora'].compareTo(b['FechaHora']));

        // Keep only the last 30 requests
        if (pendingRequests.length > 30) {
          pendingRequests =
              pendingRequests.sublist(pendingRequests.length - 30);
        }

        // Add the current request to the batch
        pendingRequests.add({
          'Latitud': body['Latitud'],
          'longitud': body['longitud'],
          'FechaHora': body['FechaHora'],
        });

        // Ensure the batch size is still 30
        if (pendingRequests.length > 30) {
          pendingRequests.removeAt(0); // Remove the oldest entry
        }

        // Update the body with the batch data
        body = {
          ...body,
          'data': jsonEncode(pendingRequests),
        };
        body.remove('Latitud');
        body.remove('longitud');
        body.remove('FechaHora');

        // Remove all 'RegistrarCoordenadasV2' entries from the failedRequestsBox
        final keysToRemove = failedRequestsBox.keys.where((key) {
          var request = failedRequestsBox.get(key);
          return request != null &&
              request['endpoint'] == 'RegistrarCoordenadasV2';
        }).toList();

        for (var key in keysToRemove) {
          await failedRequestsBox.delete(key);
        }
      }

      try {
        // Construir la URL completa
        final fullUrl = '$baseUrl$endpoint';
        final finalBody = {...body, 'token': token};
        final bodyJson = jsonEncode(finalBody);

        print('🌐 [HTTP_POST] ===== DETALLES COMPLETOS DEL REQUEST =====');
        print('🌐 [HTTP_POST] Endpoint solicitado: $endpoint');
        print('🌐 [HTTP_POST] baseUrl configurado: $baseUrl');
        print('🌐 [HTTP_POST] URL COMPLETA: $fullUrl');
        print('🌐 [HTTP_POST] Headers: ${jsonEncode(headers)}');
        print('🌐 [HTTP_POST] Body original recibido: ${jsonEncode(body)}');
        print('🌐 [HTTP_POST] Body final con token: $bodyJson');
        print('🌐 [HTTP_POST] Enviando request con timeout de 30s...');

        final response = await _client
            .post(
          Uri.parse(fullUrl),
          headers: headers,
          body: bodyJson,
        )
            .timeout(
          Duration(seconds: 30),
          onTimeout: () {
            print('⏱️ [HTTP_POST] TIMEOUT de 30s alcanzado para $endpoint');
            throw TimeoutException('Request timeout después de 30 segundos');
          },
        );

        print('📦 [HTTP_POST] ===== RESPUESTA RECIBIDA =====');
        print('📦 [HTTP_POST] Status Code: ${response.statusCode}');
        print('📦 [HTTP_POST] Response Headers: ${response.headers}');
        print('📦 [HTTP_POST] Response Body: ${response.body}');

        if (response.statusCode == 200) {
          print('✅ [HTTP_POST] Request exitoso para $endpoint');
          _lastErrorTime = null; // Reset error tracking on success
          await _updateConnectionStatus(true); // Update connection status
          return jsonDecode(response.body);
        } else {
          print('❌ [HTTP_POST] Error HTTP para $endpoint');
          print('❌ [HTTP_POST] Status Code: ${response.statusCode}');
          print('❌ [HTTP_POST] Response Body: ${response.body}');
          if (!_shouldSkipFailedSave(endpoint)) {
            await _saveFailedRequest(
              endpoint,
              body,
              errorMessage: 'HTTP ${response.statusCode}: ${response.body}',
            );
          }

          await _logError(
            'HTTP Error',
            'Código de respuesta: ${response.statusCode}',
            response.body,
            endpoint,
            bodyJson,
          );

          // Marcar conexión como perdida en errores HTTP
          await _updateConnectionStatus(false);
        }
      } catch (e) {
        print('❌ Exception occurred while sending request to $endpoint: $e');
        if (!_shouldSkipFailedSave(endpoint)) {
          await _saveFailedRequest(
            endpoint,
            body,
            errorMessage: 'Exception: $e',
          );
        }
        await _updateConnectionStatus(false);
      }
      return null;
    } catch (e) {
      // 👇 No guardamos solicitudes fallidas de estos endpoints
      if (!_shouldSkipFailedSave(endpoint)) {
        await _saveFailedRequest(
          endpoint,
          body,
          errorMessage: e is SocketException
              ? 'Network issue: Sin conexión a internet'
              : 'Exception: $e',
        );
      }

      await _logError(
        'Exception',
        e.toString(),
        e is SocketException ? 'Network issue' : null,
        endpoint,
        jsonEncode({...body, 'token': token}),
      );

      // Marcar conexión como perdida en excepciones
      await _updateConnectionStatus(false);
      return null;
    }
  }

  static Future<void> _updateConnectionStatus(bool isConnected) async {
    var conexionBox = await Hive.openBox('conexionBox');
    DateTime now = DateTime.now();

    if (isConnected) {
      await conexionBox.put('conexionRioGas', true);
      await conexionBox.put('conexionRioGasTimestamp', now.toIso8601String());
      // print('✅ Connection successful: conexionRioGas set to true.');
    } else {
      await conexionBox.put('conexionRioGas', false);
      // print('❌ Connection failed: conexionRioGas set to false.');
    }
  }

  static Future<void> _logError(
    String type,
    String message, [
    String? additionalInfo,
    String? endpoint,
    String? payload,
  ]) async {
    var errorBox = await Hive.openBox<ErrorEvent>('errorBox');
    var errorEvent = ErrorEvent(
      type: type,
      message: message,
      timestamp: DateTime.now(),
      additionalInfo: additionalInfo,
      endpoint: endpoint ?? 'Unknown endpoint',
      payload: payload ?? 'No payload',
    );
    await errorBox.add(errorEvent);
    // print(
    //   '📋 Error logged: ${errorEvent.toString()}',
    // ); // Log full details of errorEvent

    // Track persistent errors
    await _handlePersistentErrors();
  }

  static Future<void> _handlePersistentErrors() async {
    DateTime now = DateTime.now();
    if (_lastErrorTime == null) {
      _lastErrorTime = now; // Set the first error time
    } else {
      Duration difference = now.difference(_lastErrorTime!);
      if (difference.inMinutes >= errorThresholdMinutes) {
        await _updateConnectionStatus(
          false,
        ); // Update connection status on persistent error
      }
    }
  }

  static Future<Map<String, dynamic>?> validarUsuario(
    String usuario,
    String password,
    String deviceId,
    String Version,
  ) async {
    String? token = await FirebaseMessaging.instance.getToken();
    print('🪙 Token: $token');
    return _post('ValidarUsuario', {
      'usuario': usuario,
      'password': password,
      'DeviceId': deviceId,
      'tokenFCM': token,
      'INAux1': Version,
    });
  }

  static Future<Map<String, dynamic>?> validarDispositivo(String deviceId) {
    return _post('ValidarDispositivo', {'DeviceId': deviceId});
  }

  static Future<Map<String, dynamic>?> registrarDispositivo(
    String deviceId,
    String documento,
    String version,
    String number,
    String marca,
    String modelo,
    String info,
  ) async {
    return _post('RegistrarDispositivo', {
      'DeviceId': deviceId,
      'Documento': documento,
      'version': version,
      'numero': number,
      'Marca': marca,
      'Modelo': modelo,
      'Info': info,
    });
  }

  // Nuevo método para validar la versión
  static Future<Map<String, dynamic>?> validarVersion(
    String version,
    String deviceId,
  ) {
    return _post('ValidarVersion', {'version': version, 'DeviceId': deviceId});
  }

  // Nuevo método para obtener datos de la versión
  static Future<Map<String, dynamic>?> DatosVersionActual(
    String version,
    String deviceId,
  ) {
    return _post('DatosVersionActual', {
      'version': version,
      'DeviceId': deviceId,
    });
  }

  static Future<Map<String, dynamic>?> cambioPassword(
    String usuMobileLogin,
    String currentPassword,
    String newPassword,
  ) {
    return _post('CambioPassword', {
      'UsuMobileLogin': usuMobileLogin,
      'CurrentPassword': currentPassword,
      'UsuMobilePassword': newPassword,
    });
  }

  static Future<Map<String, dynamic>?> descargaLecturaMensajes(
      int escenarioId,
      int movilId,
      int messageId,
      String usuario,
      String nroSesion,
      String termMobileEquipo,
      String lectDesc,
      String fechaHoraCmbEst,
      String inAux1,
      String inAux2,
      String latitud,
      String longitud,
      String utmX,
      String utmY,
      double velocidad, // Added parameter
      double distanciaRecorrida // Added parameter
      ) async {
    velocidad = double.parse(velocidad.toStringAsFixed(2));
    distanciaRecorrida = double.parse(distanciaRecorrida.toStringAsFixed(2));

    // 🚩 Obtener flag 'services_need_restart' desde SharedPreferences nativo
    bool despertar = false;
    try {
      final servicesNeedRestart = await getServicesNeedRestart();
      despertar = servicesNeedRestart ?? false;
      print('🚩 [DescargaLecturaMensajesV2] Despertar servicios: $despertar');
    } catch (e) {
      print(
          '❌ [DescargaLecturaMensajesV2] Error obteniendo flag despertar: $e');
    }

    return _post('DescargaLecturaMensajesV2', {
      'escenarioid': escenarioId,
      'MovilId': movilId,
      'MessageId': messageId,
      'usuario': usuario,
      'NroSesion': nroSesion,
      'TermMobileEquipo': termMobileEquipo,
      'LectDesc': lectDesc,
      'FechaHoraCmbEst': fechaHoraCmbEst,
      'INAux1': inAux1,
      'INAux2': inAux2,
      'Latitud': latitud,
      'longitud': longitud,
      'utmX': utmX,
      'utmY': utmY,
      'Velocidad': velocidad, // Added to body
      'DistanciaRecorrida': distanciaRecorrida, // Added to body
      'Despertar': despertar // 🆕 Flag para despertar servicios
    });
  }

  static Future<Map<String, dynamic>?> descargaLecturaPedidos(
      int escenarioId,
      int pedidoId,
      String pedidoTpo,
      String usuario,
      String nroSesion,
      String termMobileEquipo,
      String lectDesc,
      String fechaHoraCmbEst,
      String inAux1,
      String inAux2,
      String latitud,
      String longitud,
      String utmX,
      String utmY,
      double velocidad, // Added parameter
      double distanciaRecorrida // Added parameter
      ) async {
    velocidad = double.parse(velocidad.toStringAsFixed(2));
    distanciaRecorrida = double.parse(distanciaRecorrida.toStringAsFixed(2));

    // 🚩 Obtener flag 'services_need_restart' desde SharedPreferences nativo
    bool despertar = false;
    try {
      final servicesNeedRestart = await getServicesNeedRestart();
      despertar = servicesNeedRestart ?? false;
      print('🚩 [DescargaLecturaPedidosV2] Despertar servicios: $despertar');
    } catch (e) {
      print('❌ [DescargaLecturaPedidosV2] Error obteniendo flag despertar: $e');
    }

    final result = await _post('DescargaLecturaPedidosV2', {
      'escenarioid': escenarioId,
      'PedidoId': pedidoId,
      'PedidoTpo': pedidoTpo,
      'usuario': usuario,
      'NroSesion': nroSesion,
      'TermMobileEquipo': termMobileEquipo,
      'LectDesc': lectDesc,
      'FechaHoraCmbEst': fechaHoraCmbEst,
      'INAux1': inAux1,
      'INAux2': inAux2,
      'Latitud': latitud,
      'longitud': longitud,
      'utmX': utmX,
      'utmY': utmY,
      'Velocidad': velocidad, // Added to body
      'DistanciaRecorrida': distanciaRecorrida, // Added to body
      'Despertar': despertar // 🆕 Flag para despertar servicios
    });

    // 🆕 Enviar logs remotamente después de descarga de pedido
    DebugConfigManager.uploadLogsNow();

    return result;
  }

  static Future<Map<String, dynamic>?> finalizarPedido(
      int escenarioId,
      int pedidoId,
      String pedidoTpo,
      String usuario,
      String nroSesion,
      String termMobileEquipo,
      int estado,
      int subEstado,
      String formaPago,
      String motCancel,
      String fechaHoraCmbEst,
      String movil,
      double DistanciaEnMetros,
      String inAux1,
      String inAux2,
      String latitud,
      String longitud,
      String utmX,
      String utmY,
      double velocidad, // Added parameter
      double distanciaRecorrida // Added parameter
      ) async {
    velocidad = double.parse(velocidad.toStringAsFixed(2));
    distanciaRecorrida = double.parse(distanciaRecorrida.toStringAsFixed(2));

    // 🚩 Obtener flag 'services_need_restart' desde SharedPreferences nativo
    bool despertar = false;
    try {
      final servicesNeedRestart = await getServicesNeedRestart();
      despertar = servicesNeedRestart ?? false;
      print('🚩 [FinalizarPedidoV3] Despertar servicios: $despertar');
    } catch (e) {
      print('❌ [FinalizarPedidoV3] Error obteniendo flag despertar: $e');
    }

    final result = await _post('FinalizarPedidoV3', {
      'escenarioid': escenarioId,
      'PedidoId': pedidoId,
      'PedidoTpo': pedidoTpo,
      'usuario': usuario,
      'NroSesion': nroSesion,
      'TermMobileEquipo': termMobileEquipo,
      'Estado': estado,
      'SubEstado': subEstado,
      'FormaPago': formaPago,
      'MotCancel': motCancel,
      'FechaHoraCmbEst': fechaHoraCmbEst,
      'movil': movil,
      'DistanciaEnMetros': DistanciaEnMetros,
      'INAux1': inAux1,
      'INAux2': inAux2,
      'Latitud': latitud,
      'longitud': longitud,
      'utmX': utmX,
      'utmY': utmY,
      'Velocidad': velocidad,
      'DistanciaRecorrida': distanciaRecorrida,
      'Despertar': despertar // 🆕 Flag para despertar servicios
    });

    // 🆕 Enviar logs remotamente después de finalizar pedido
    DebugConfigManager.uploadLogsNow();

    return result;
  }

  static bool _shouldSkipFailedSave(String endpoint) {
    return endpoint == 'DescargaLecturaPedidos' ||
        endpoint == 'DescargaLecturaPedidosV2' ||
        endpoint == 'RegistrarCoordenadasV2' ||
        endpoint == 'RegistrarCoordenadasV2Batch' ||
        endpoint == 'RegistrarCierre' ||
        endpoint == 'DescargaPedidos' ||
        endpoint == 'DescargaPedidosV2' ||
        endpoint == 'ValidarDispositivo' ||
        endpoint == 'promociones/ValidarPromo';
  }

  /// 🎁 Valida un beneficio de promoción (promociones/ValidarPromo).
  /// Devuelve el JSON crudo o null si no hubo 200. SIN retry offline a
  /// propósito: re-disparar una validación vieja desde la cola no tiene
  /// sentido de negocio (está en _shouldSkipFailedSave).
  static Future<Map<String, dynamic>?> validarPromo(
      Map<String, dynamic> body) {
    return _post('promociones/ValidarPromo', body);
  }

  static Future<Map<String, dynamic>?> actualizarMoviles(
      int escenarioId,
      int movilId,
      String usuario,
      String nroSesion,
      String termMobileEquipo,
      String estadoStr,
      String latitud,
      String longitud,
      String utmX,
      String utmY,
      String fechaHoraCmbEst,
      String inAux1,
      String inAux2,
      double velocidad, // Added parameter
      double distanciaRecorrida // Added parameter
      ) {
    velocidad = double.parse(velocidad.toStringAsFixed(2));
    distanciaRecorrida = double.parse(distanciaRecorrida.toStringAsFixed(2));
    return _post('ActualizarMoviles', {
      'escenarioid': escenarioId,
      'MovilId': movilId,
      'usuario': usuario,
      'NroSesion': nroSesion,
      'TermMobileEquipo': termMobileEquipo,
      'EstadoStr': estadoStr,
      'Latitud': latitud,
      'longitud': longitud,
      'utmX': utmX,
      'utmY': utmY,
      'FechaHoraCmbEst': fechaHoraCmbEst,
      'INAux1': inAux1,
      'INAux2': inAux2,
      'Velocidad': velocidad, // Added to body
      'DistanciaRecorrida': distanciaRecorrida // Added to body
    });
  }

  static Future<Map<String, dynamic>?> actualizarMovilesEstado(
    int movilId,
    int estado,
  ) async {
    var box = await Hive.openBox('sessionBox');
    String? escenarioId = box.get('escenario');
    String? usuario = box.get('username');
    String? deviceId = box.get('deviceId');

    if (escenarioId == null || usuario == null || deviceId == null) {
      // print('❌ No se pudo obtener el escenario, usuario o deviceId de Hive.');
      return null;
    }

    var locationData = await LocationService().getCurrentLocation();
    if (locationData != null) {
      double latitude = locationData['latitude'];
      double longitude = locationData['longitude'];
      double utmX = locationData['utmX'];
      double utmY = locationData['utmY'];

      print('Latitud: $latitude, Longitud: $longitude');
      print('UTM Este (X): $utmX, UTM Norte (Y): $utmY');

      DateTime now = DateTime.now();
      String fechaHoraCmbEst = now.toIso8601String();

      return _post('ActualizarMoviles', {
        'escenarioid': int.parse(escenarioId),
        'MovilId': movilId,
        'usuario': usuario,
        'NroSesion': '',
        'TermMobileEquipo': deviceId,
        'EstadoStr': 'ACTIVO',
        'Latitud': latitude.toString(),
        'longitud': longitude.toString(),
        'utmX': utmX.toString(),
        'utmY': utmY.toString(),
        'FechaHoraCmbEst': fechaHoraCmbEst,
        'INAux1': '',
        'INAux2': '',
      });
    } else {
      print('❌ No se pudo obtener la ubicación actual.');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> enviarOTP(
    int nroTelefono,
    int codigoOTP,
    String hash,
  ) {
    return _post('EnviarOTP', {
      'token': token,
      'nroTelefono': nroTelefono,
      'codigoOTP': codigoOTP,
      'hash': hash,
    });
  }

  static Future<Map<String, dynamic>?> RegistrarCoordenadasV2(
      int movil,
      String latitud,
      String longitud,
      String utmX,
      String utmY,
      String deviceId,
      String fechaHora,
      double distanciaRecorrida, // Add distance parameter
      double velocidad // Add speed parameter
      ) async {
    velocidad = double.parse(velocidad.toStringAsFixed(2));
    distanciaRecorrida = double.parse(distanciaRecorrida.toStringAsFixed(2));
    try {
      var box = await Hive.openBox('sessionBox');
      String? escenarioId = box.get('escenario');
      String? username = box.get('username');
      int? escenarioIdInt =
          escenarioId != null ? int.tryParse(escenarioId) : null;
      if (escenarioIdInt == null) {
        throw Exception('Invalid escenarioId: $escenarioId');
      }
      // Use the specified structure for the REST service request
      return await _post('RegistrarCoordenadasV2', {
        'token': token,
        'movil': movil,
        'Latitud': latitud,
        'longitud': longitud,
        'utmX': utmX,
        'utmY': utmY,
        'DeviceId': deviceId,
        'FechaHora': fechaHora,
        'DistanciaRecorrida': distanciaRecorrida, // Pass distance to service
        'Velocidad': velocidad, // Pass speed to service
        'escenarioid': escenarioIdInt,
        'usuario': username
      });
    } catch (e) {
      // Save the failed request in the specified Hive structure
      var failedRequestsBox = await Hive.openBox('failedRequestsBox');
      var existingRequest = failedRequestsBox.values.firstWhere(
        (request) =>
            request['endpoint'] == 'RegistrarCoordenadasV2Batch' &&
            request['payload']['movil'] == movil &&
            request['payload']['DeviceId'] == deviceId,
        orElse: () => null,
      );

      if (existingRequest != null) {
        // Add new data to the existing collection if it's not already present
        List<dynamic> data = existingRequest['payload']['data'];
        if (!data.any((entry) =>
            entry['Latitud'] == latitud && entry['longitud'] == longitud)) {
          if (data.length >= 30) {
            data.removeAt(
                0); // Remove the oldest entry to maintain a limit of 30
          }
          data.add({
            'Latitud': latitud,
            'longitud': longitud,
            'FechaHora': fechaHora,
            'DistanciaRecorrida': distanciaRecorrida, // Add distance to batch
            'Velocidad': velocidad // Add speed to batch
          });
          await failedRequestsBox.put(existingRequest['key'], existingRequest);
          print('📝 Updated existing failed request: $existingRequest');
        }
      } else {
        // Save a new failed request
        var newRequest = {
          'endpoint': 'RegistrarCoordenadasV2Batch',
          'payload': {
            'token': token,
            'movil': movil,
            'DeviceId': deviceId,
            'data': [
              {
                'Latitud': latitud,
                'longitud': longitud,
                'FechaHora': fechaHora,
                'DistanciaRecorrida': distanciaRecorrida, // Add distance
                'Velocidad': velocidad // Add speed
              }
            ],
          },
        };
        await failedRequestsBox.add(newRequest);
        print('📝 Saved new failed request: $newRequest');
      }
      return null;
    }
  }

  static Future<void> downloadAndOpenPDF({
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minutes,
    required int seconds,
    required String usuMobileLogin,
    required String termMobileEquipo,
    required int agenciaId,
    required int escenarioId,
    required int movilId,
  }) async {
    // print('📋 Parameters:');
    // print('Year: $year, Month: $month, Day: $day');
    // print('Hour: $hour, Minutes: $minutes, Seconds: $seconds');
    // print(
    //   'UsuMobileLogin: $usuMobileLogin, TermMobileEquipo: $termMobileEquipo',
    // );
    // print('AgenciaId: $agenciaId, EscenarioId: $escenarioId');
    // print('MovilId: $movilId');

    final DateTime fechaDesdeDate = DateTime(year, month, day);
    final DateTime fechaHastaDate = fechaDesdeDate.add(Duration(days: 1));

    final String fechaDesde =
        '${fechaDesdeDate.year}${fechaDesdeDate.month.toString().padLeft(2, '0')}${fechaDesdeDate.day.toString().padLeft(2, '0')}000000';
    final String fechaHasta =
        '${fechaHastaDate.year}${fechaHastaDate.month.toString().padLeft(2, '0')}${fechaHastaDate.day.toString().padLeft(2, '0')}000000';

    // Construcción de URL usando constantes 600 (base) y 602 (path)
    final baseUrlFromConst = (await getConstantValue('600'))?.trim() ?? '';
    final reportPathFromConst =
        (await getConstantValue('602'))?.trim() ?? 'com.icageos.urlhttprpt2sgm';

    // Normalizar base: quitar sufijo appservices/, asegurar slash final
    var base = baseUrlFromConst.isEmpty
        ? 'https://sgm.riogas.com.uy/'
        : baseUrlFromConst;
    base = base.replaceAll(RegExp(r'appservices/?$', caseSensitive: false), '');
    if (!base.endsWith('/')) base += '/';

    // Normalizar path: quitar slash inicial si lo tiene
    var path = reportPathFromConst;
    if (path.startsWith('/')) {
      path = path.substring(1);
    }

    final url =
        '${base}${path}?FechaDesde=$fechaDesde&FechaHasta=$fechaHasta&UsuMobileLogin=$usuMobileLogin&TermMobileEquipo=$termMobileEquipo&AgenciaId=$agenciaId&EscenarioId=$escenarioId&Movid=$movilId&Tipo=RESUMIDO';

    print('🌐 Downloading PDF from: $url');

    try {
      // print('🌐 Downloading PDF from: $url');
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/report.pdf';
        final file = File(filePath);

        await file.writeAsBytes(response.bodyBytes);
        // print('✅ PDF downloaded to: $filePath');

        await OpenFile.open(filePath);
        // print('📂 Opened PDF with result: $result');
      } else {
        // print('❌ Failed to download PDF. Status code: ${response.statusCode}');
      }
    } catch (e) {
      // print('❌ Error downloading or opening PDF: $e');
    }
  }

  static Future<void> deleteOldRequests() async {
    // print('🗑️ Checking for old requests to delete.');
    var failedRequestsBox = await Hive.openBox('failedRequestsBox');

    // Check if the box contains more than 500 records
    if (failedRequestsBox.length > 50) {
      // print('⚠️ More than 500 records found. Clearing the box.');
      await failedRequestsBox.clear(); // Clear all records
      // print('✅ All records cleared from failedRequestsBox.');
      return;
    }

    DateTime today = DateTime.now();

    List<dynamic> keysToDelete = failedRequestsBox.keys.where((key) {
      var request = failedRequestsBox.get(key);
      if (request != null && request is Map) {
        DateTime? timestamp = DateTime.tryParse(request['timestamp'] ?? '');
        if (timestamp != null) {
          return timestamp.isBefore(
            DateTime(today.year, today.month, today.day),
          );
        }
      }
      return false;
    }).toList();

    for (var key in keysToDelete) {
      await failedRequestsBox.delete(key);
      // print('🗑️ Deleted old request with key: $key');
    }

    // print('✅ Finished deleting old requests.');
  }

  static Future<void> registrarErrores() async {
    var errorBox = await Hive.openBox('errorBox');

    String? constantValue = await getConstantValue('200');
    if (constantValue != null) {
      return;
    }
    // Check if there are errors without the "enviadoARioGas" mark
    List<dynamic> errorsToSend = errorBox.keys.where((key) {
      var error = errorBox.get(key);
      return error != null && error is Map && error['enviadoARioGas'] != true;
    }).toList();

    if (errorsToSend.isEmpty) {
      print('⚠️ No errors to send. Waiting for new errors.');
      return;
    }

    for (var key in errorsToSend) {
      var error = errorBox.get(key);
      if (error != null && error is Map) {
        try {
          // Clean additionalInfo by removing quotes
          if (error['additionalInfo'] != null) {
            error['additionalInfo'] =
                error['additionalInfo'].replaceAll('"', '').replaceAll("'", '');
          }

          // Prepare the payload
          Map<String, dynamic> payload = {
            'token': token,
            'movil': error['movil'] ?? 0,
            'DeviceId': error['DeviceId'] ?? '',
            'usuario': error['usuario'] ?? '',
            'data': jsonEncode(error),
          };

          // Send the error to RioGas
          var response = await _post('RegistrarErrores', payload);

          if (response != null) {
            print('✅ Error sent successfully to RioGas: $key');
            // Mark the error as sent
            error['enviadoARioGas'] = true;
            await errorBox.put(key, error);
          } else {
            print('❌ Failed to send error to RioGas: $key');
          }
        } catch (e) {
          print('❌ Error while sending error to RioGas: $e');
        }
      }
    }

    // Listen for new errors being added to the box
    errorBox.watch().listen((event) async {
      String? constantValue = await getConstantValue('200');
      if (constantValue != null) {
        var newErrorsToSend = errorBox.keys.where((key) {
          var error = errorBox.get(key);
          return error != null &&
              error is Map &&
              error['enviadoARioGas'] != true;
        }).toList();

        if (newErrorsToSend.isNotEmpty) {
          print('📦 New errors detected. Sending to RioGas.');
          await registrarErrores();
        }
      }
    });
  }

  static Future<void> registrarUltLog(
      int movil, String deviceId, String usuario) async {
    try {
      String appVersion = await AuthService.getAppVersion();

      // Prepare the payload
      Map<String, dynamic> payload = {
        'token': token,
        'movil': movil,
        'DeviceId': deviceId,
        'usuario': usuario,
        'version': appVersion,
      };

      // Send the request to RioGas
      var response = await _post('RegistrarSesion', payload);

      if (response != null) {
        print('✅ Último log registrado exitosamente en RioGas.');
      } else {
        print('❌ Falló el registro del último log en RioGas.');
      }
    } catch (e) {
      print('❌ Error al registrar el último log en RioGas: $e');
    }
  }

  static Future<Map<String, dynamic>?> recepcionFCM(
    String fcmIdentificador,
    String fcmEstado,
  ) async {
    return _post('RecepcionFCM', {
      'FCMIdentificador': fcmIdentificador,
      'FCMEStado': fcmEstado,
    });
  }

  /// � ActualizarTokenFCM - Actualizar token FCM en el backend
  ///
  /// Sincroniza el token FCM cuando:
  /// - Firebase rota el token automáticamente
  /// - Se detecta que el token fue invalidado
  /// - Se fuerza renovación manual
  ///
  /// Parámetros:
  /// - deviceId: ID único del dispositivo
  /// - token: Nuevo token FCM
  static Future<Map<String, dynamic>?> actualizarTokenFCM({
    required String deviceId,
    required String token,
  }) async {
    print('🔑 [RIOGAS_SERVICE] Actualizando token FCM para device: $deviceId');
    print('🔑 [RIOGAS_SERVICE] Token: ${token.substring(0, 20)}...');

    return _post('ActualizarTokenFCM', {
      'DeviceId': deviceId,
      'tokenFCM': token,
    });
  }

  /// �🚨 FCMActions - Invocar acción remota via FCM
  ///
  /// Permite enviar comandos FCM desde los servicios cuando detectan problemas:
  /// - force_gps_execution: Forzar ejecución GPS inmediata
  /// - restart_gps_service: Reiniciar servicio GPS completo
  /// - stop_gps_service: Detener servicio GPS
  /// - get_status: Consultar estado del servicio
  ///
  /// Usado por ForegroundLocationService y CriticalLogger cuando detectan
  /// que el servicio GPS no responde o no puede auto-recuperarse
  static Future<Map<String, dynamic>?> fcmActions({
    required int escenarioId,
    required String movil,
    required String accion,
  }) async {
    return _post('FCMActions', {
      'escenarioid': escenarioId,
      'movil': movil,
      'Accion': accion,
    });
  }

  static Future<void> monitorAndSendErrors() async {
    var errorBox = await Hive.openBox<ErrorEvent>('errorBox');
    var conexionBox = await Hive.openBox('conexionBox');

    // Monitorear constantemente los errores
    Timer.periodic(Duration(seconds: 60), (timer) async {
      bool isConnected = conexionBox.get('conexionRioGas', defaultValue: false);

      print('⚠️ timer Conexion riogas.');

      if (!isConnected) {
        print('⚠️ No hay conectividad con RioGas. Esperando conexión...');
        return;
      }

      // Filtrar errores que no han sido enviados
      List<dynamic> errorsToSend = errorBox.keys.where((key) {
        var error = errorBox.get(key);
        return error != null && error.additionalInfo != 'enviadoARioGas';
      }).toList();

      if (errorsToSend.isEmpty) {
        print('⚠️ No hay errores pendientes para enviar.');
        return;
      }

      for (var key in errorsToSend) {
        var error = errorBox.get(key);
        if (error != null) {
          try {
            var sessionBox = await Hive.openBox('sessionBox');
            // Preparar el payload
            Map<String, dynamic> payload = {
              'token': token,
              'type': error.type,
              'message': error.message,
              'timestamp': error.timestamp.toIso8601String(),
              'additionalInfo': error.additionalInfo,
              'endpoint': error.endpoint,
              'payload': error.payload,
              'username': sessionBox.get('username'),
              'DeviceId': sessionBox.get('deviceId'),
              'movil': sessionBox.get('movil'),
            };

            // Enviar el error a RioGas
            var response = await _post('RegistrarErrores', payload);

            if (response != null && response['ok'] == 0) {
              print('✅ Error enviado exitosamente a RioGas: $key');
              // Marcar el error como enviado
              var updatedError = ErrorEvent(
                type: error.type,
                message: error.message,
                timestamp: error.timestamp,
                additionalInfo: 'enviadoARioGas',
                endpoint: error.endpoint,
                payload: error.payload,
              );
              await errorBox.put(key, updatedError);
            } else {
              print('❌ Falló el envío del error a RioGas: $key');
              timer.cancel(); // Cancelar el timer en caso de error
              Future.delayed(Duration(minutes: 30), () {
                monitorAndSendErrors(); // Reintentar después de 30 minutos
              });
              return;
            }
          } catch (e) {
            print('❌ Error al enviar el error a RioGas: $e');
            timer.cancel(); // Cancelar el timer en caso de error
            Future.delayed(Duration(minutes: 30), () {
              monitorAndSendErrors(); // Reintentar después de 30 minutos
            });
            return;
          }
        }
      }
    });
  }

  static Future<Map<String, dynamic>?> registrarCierre(
      int movil,
      String deviceId,
      String usuario,
      String fechaHora,
      String tipoCierre) async {
    String appVersion = await AuthService.getAppVersion();
    var box = await Hive.openBox('sessionBox');
    String? usuarioNombre = box.get('NombreUsuario');
    return _post('RegistrarCierre', {
      'token': token,
      'movil': movil,
      'DeviceId': deviceId,
      'usuario': usuario,
      'TipoCierre': tipoCierre,
      'FechaHora': fechaHora,
      'version': appVersion,
      'origen': 'MoveIT',
      'usuarioCierre': usuarioNombre,
      'aplicaFirestore': false,
    });
  }

  static Future<Map<String, dynamic>?> limpiarSesiones(
    int movil,
    int escenarioId,
    String device,
    String usuario,
  ) {
    return _post('LimpiarSesiones', {
      'movil': movil,
      'escenarioid': escenarioId,
      'device': device,
      'usuario': usuario,
    });
  }

  // =========================================================================
  // 🚩 MÉTODOS PARA ACCEDER A FLAGS DE ESTADO DE SERVICIOS (KOTLIN)
  // =========================================================================

  /// MethodChannel para comunicación con código nativo (Android)
  static const _serviceStatusChannel =
      MethodChannel('com.riogas.appmovil/service_status');

  /// Obtiene el estado de la flag 'services_need_restart' desde SharedPreferences de Android
  ///
  /// Esta flag es actualizada por los servicios de Kotlin (GPS y CriticalLog) cuando
  /// detectan que algún servicio está apagado.
  ///
  /// Returns:
  /// - true: Algún servicio está apagado y necesita reiniciarse
  /// - false: Todos los servicios están activos y funcionando correctamente
  /// - null: Error al obtener el valor
  ///
  /// La flag respeta el cierre de sesión FCM (watchdog_disabled), por lo que
  /// si el usuario cerró sesión, esta flag no se modificará.
  static Future<bool?> getServicesNeedRestart() async {
    try {
      final bool result =
          await _serviceStatusChannel.invokeMethod('getServicesNeedRestart');
      print('🚩 [FLAGS] services_need_restart = $result');
      return result;
    } catch (e) {
      print('❌ [FLAGS] Error obteniendo services_need_restart: $e');
      return null;
    }
  }

  /// Obtiene el estado completo de todos los servicios desde SharedPreferences de Android
  ///
  /// Returns un Map con la siguiente información:
  /// - services_need_restart: bool - Flag principal
  /// - last_check_timestamp: int - Timestamp de última verificación
  /// - checked_by: String - Servicio que hizo la última verificación
  /// - check_reason: String - Razón de la última verificación
  /// - gps_service_status: bool - Estado del GPS Service
  /// - gps_status_timestamp: int - Timestamp del estado GPS
  /// - gps_checked_by: String - Quién verificó el GPS
  /// - critical_log_status: bool - Estado del CriticalLog Service
  /// - critical_log_timestamp: int - Timestamp del estado CriticalLog
  /// - critical_log_checked_by: String - Quién verificó CriticalLog
  /// - watchdog_disabled: bool - Si el watchdog está deshabilitado (cierre sesión)
  static Future<Map<String, dynamic>?> getFullServiceStatus() async {
    try {
      final Map<dynamic, dynamic> result =
          await _serviceStatusChannel.invokeMethod('getFullServiceStatus');
      final Map<String, dynamic> status = Map<String, dynamic>.from(result);

      print('🚩 [FLAGS] Estado completo de servicios:');
      print('   - services_need_restart: ${status['services_need_restart']}');
      print('   - gps_service_status: ${status['gps_service_status']}');
      print('   - critical_log_status: ${status['critical_log_status']}');
      print('   - watchdog_disabled: ${status['watchdog_disabled']}');
      print('   - checked_by: ${status['checked_by']}');

      return status;
    } catch (e) {
      print('❌ [FLAGS] Error obteniendo estado completo de servicios: $e');
      return null;
    }
  }

  /// Limpia todas las flags de estado de servicios
  /// Útil al iniciar sesión o reiniciar la aplicación
  static Future<bool> clearAllServiceFlags() async {
    try {
      await _serviceStatusChannel.invokeMethod('clearAllServiceFlags');
      print('🚩 [FLAGS] Todas las flags de servicios limpiadas');
      return true;
    } catch (e) {
      print('❌ [FLAGS] Error limpiando flags de servicios: $e');
      return false;
    }
  }
}
