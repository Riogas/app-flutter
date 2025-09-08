import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io'; // Import for SocketException
import 'package:hive/hive.dart';
import '../utils/error_event.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart'; // Add this line to import LocationService
import 'dart:async'; // Import for Timer
import '../utils/constantes.dart';
import 'package:url_launcher/url_launcher.dart'; // Add this import for opening URLs
import 'package:path_provider/path_provider.dart'; // Add this import for file handling
import 'package:open_file/open_file.dart'; // Ensure this import is present
import '../services/auth_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // Import FirebaseMessaging

class RioGasService {
  /// Llama al servicio DescargaPedidos con el body especificado.
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
  ) {
    velocidad = double.parse(velocidad.toStringAsFixed(2));
    distanciaRecorrida = double.parse(distanciaRecorrida.toStringAsFixed(2));
    return _post('DescargaPedidos', {
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
    });
  }

  static late final String baseUrl;
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
      // Ya hay un timer activo, no iniciar otro
      return;
    }

    var failedRequestsBox = await Hive.openBox('failedRequestsBox');
    print("📦 requestbox values: ${failedRequestsBox.values}");
    if (failedRequestsBox.isNotEmpty) {
      // print('📦 Pending requests found: ${failedRequestsBox.length}');
      //_retryTimer?.cancel(); // Cancel any existing timer
      // print('⏱️ Existing retry timer canceled.');
      // print('⏱️ Setting retry interval to: $retryIntervalSeconds seconds.');
      _retryTimer = Timer.periodic(Duration(seconds: retryIntervalSeconds), (
        timer,
      ) async {
        // print('🔄 Timer triggered. Executing retry timer callback.');
        try {
          await processPendingRequests();
          if (failedRequestsBox.isEmpty) {
            timer.cancel();
            _retryTimer =
                null; // 🔁 opcional, para saber que ya no hay timer activo
            print('✅ Todos los pendientes procesados. Timer detenido.');
          }
        } catch (e) {
          // print('❌ Error in retry timer callback: $e');
        }
      });
      // print(
      //   '🔄 Retry timer started with interval: $retryIntervalSeconds seconds.',
      // );
    } else {
      // print('⚠️ No pending requests in failedRequestsBox.');
      // print('⚠️ Retry timer will not be started.');
    }
  }

  // Ensure the timer starts at least once during initialization
  static Future<void> initializeService() async {
    // 👇 NUEVO: inicializar baseUrl dinámico con 600 (base) + 601 (appservices)
    final baseRootConst = (await getConstantValue('600'))?.trim();
    final servicesPathConst = (await getConstantValue('601'))?.trim();

    var baseRoot = (baseRootConst != null && baseRootConst.isNotEmpty)
        ? baseRootConst
        : 'https://www.riogas.uy/ica_geos_/';

    var servicesPath =
        (servicesPathConst != null && servicesPathConst.isNotEmpty)
            ? servicesPathConst
            : 'appservices/';

    // Normalizaciones: quitar 'appservices/' del base por si viene duplicado, slashes correctos
    baseRoot = baseRoot.replaceAll(
        RegExp(r'appservices/?$', caseSensitive: false), '');
    if (!baseRoot.endsWith('/')) baseRoot += '/';
    if (servicesPath.startsWith('/')) servicesPath = servicesPath.substring(1);
    if (!servicesPath.endsWith('/')) servicesPath += '/';

    baseUrl = '$baseRoot$servicesPath';

    await initializeRetryInterval();
    await deleteOldRequests(); // Call the method to delete old requests
    var failedRequestsBox = await Hive.openBox('failedRequestsBox');

    // Listen for changes in the failedRequestsBox
    failedRequestsBox.watch().listen((event) async {
      if (failedRequestsBox.isNotEmpty) {
        print(
          '📦 Detected new data in failedRequestsBox. Starting retry timer.',
        );
        await startRetryTimer();
      } else {
        // print('📦 failedRequestsBox is empty. No retry timer will be started.');
      }
    });
  }

  static Future<void> _saveFailedRequest(
    String? endpoint,
    Map<String, dynamic>? payload,
  ) async {
    if (endpoint == null || payload == null) return;

    final failedRequestsBox = await Hive.openBox('failedRequestsBox');

    // Para FinalizarPedidoV2 deduplicamos por firma JSON del payload
    if (endpoint == 'FinalizarPedidoV2') {
      final newSignature = jsonEncode(payload); // firma simple y suficiente

      final exists = failedRequestsBox.values.any((request) {
        try {
          final map = Map<String, dynamic>.from(request as Map);
          return map['endpoint'] == 'FinalizarPedidoV2' &&
              map['signature'] == newSignature;
        } catch (_) {
          return false;
        }
      });

      if (exists) {
        // print('⚠️ Duplicate FinalizarPedidoV2 detected, not saving again.');
        return;
      }

      await failedRequestsBox.add({
        'endpoint': endpoint,
        'payload': payload,
        'signature': newSignature,
        'timestamp': DateTime.now().toIso8601String(),
      });
      return;
    }

    // Resto de endpoints (salvo los prohibidos que ya filtramos antes)
    final exists = failedRequestsBox.values.any((request) {
      try {
        final map = Map<String, dynamic>.from(request as Map);
        // dedupe básico por endpoint+payload textual
        return map['endpoint'] == endpoint &&
            Map<String, dynamic>.from(map['payload'] as Map).toString() ==
                payload.toString();
      } catch (_) {
        return false;
      }
    });

    if (exists) return;

    await failedRequestsBox.add({
      'endpoint': endpoint,
      'payload': payload,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> processPendingRequests() async {
    const tag = '📦[FAILED_SYNC]';

    print('$tag ▶️ Iniciando procesamiento de requests pendientes...');

    final failedRequestsBox = await Hive.openBox('failedRequestsBox');
    final conexionBox = await Hive.openBox('conexionBox');
    var isConnected = conexionBox.get('conexionRioGas', defaultValue: false);

    // Si no hay conexión, intentamos validar el dispositivo para reestablecerla
    if (!isConnected) {
      print('$tag ⚠️ Sin conexión a RioGas. Intentando validar dispositivo...');

      final sessionBox = await Hive.openBox('sessionBox');
      final deviceId = sessionBox.get('deviceId');

      if (deviceId == null || (deviceId is String && deviceId.isEmpty)) {
        print(
            '$tag ❌ deviceId no encontrado en sessionBox. Abortando procesamiento.');
        return;
      }

      try {
        final response = await validarDispositivo(deviceId);
        final success = response != null &&
            (response['Existe'] == true ||
                response['success'] == true ||
                response['OK'] == 0 ||
                response['ok'] == 0);

        if (success) {
          print(
              '$tag ✅ Dispositivo validado. Marcando conexionRioGas=true y continuando.');
          await conexionBox.put('conexionRioGas', true);
          await conexionBox.put(
              'conexionRioGasTimestamp', DateTime.now().toIso8601String());
          isConnected = true;
        } else {
          print('$tag ❌ Validación de dispositivo fallida. No se continuará.');
          return;
        }
      } catch (e, st) {
        print('$tag ❌ Error validando dispositivo: $e');
        print(st);
        return;
      }
    }

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
            endpoint == 'RegistrarCoordenadas') {
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
          await failedRequestsBox.put(key, {...request, 'processed': true});
          print('$tag 📝 Request con key $key marcado como procesado.');
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
        }
      } catch (e, st) {
        print('$tag ❌ Error al procesar request con key $key: $e');
        print(st);

        // (Opcional) Mantener rollback de estado si falla FinalizarPedido/FinalizarPedidoV2
        if ((request['endpoint'] == 'FinalizarPedidoV2' ||
                request['endpoint'] == 'FinalizarPedido') &&
            request['payload'] is Map &&
            request['payload'].containsKey('PedidoId')) {
          final pedidoId = request['payload']['PedidoId'];
          final pedidosBox = await Hive.openBox('pedidosBox');
          if (pedidosBox.containsKey(pedidoId)) {
            await pedidosBox.put(pedidoId, 'Enviando');
            print('$tag ↩️ Pedido $pedidoId marcado como "Enviando" por error');
          }
        }
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

      if (endpoint == 'RegistrarCoordenadas') {
        /*print('📦 Processing RegistrarCoordenadas...');
        print('📦 RegistrarCoordenadas Body: $body');*/
      }

      if (endpoint == 'RegistrarCoordenadasBatch') {
        // Ensure Latitud, longitud, and FechaHora are inside "data"
        var failedRequestsBox = await Hive.openBox('failedRequestsBox');

        // Filter pending requests for 'RegistrarCoordenadas'
        List<Map<String, dynamic>> pendingRequests = failedRequestsBox.values
            .where((request) => request['endpoint'] == 'RegistrarCoordenadas')
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

        // Remove all 'RegistrarCoordenadas' entries from the failedRequestsBox
        final keysToRemove = failedRequestsBox.keys.where((key) {
          var request = failedRequestsBox.get(key);
          return request != null &&
              request['endpoint'] == 'RegistrarCoordenadas';
        }).toList();

        for (var key in keysToRemove) {
          await failedRequestsBox.delete(key);
        }
      }

      try {
        print('🌐 Sending request to endpoint: $endpoint with payload: $body');
        final response = await http.post(
          Uri.parse('$baseUrl$endpoint'),
          headers: headers,
          body: jsonEncode({...body, 'token': token}),
        );

        print('📦 Response endpoint: $endpoint | $response.body ');

        if (response.statusCode == 200) {
          print('? Response endpoint: $endpoint | ${response.body}');
          _lastErrorTime = null; // Reset error tracking on success
          await _updateConnectionStatus(true); // Update connection status
          return jsonDecode(response.body);
        } else {
          print(
              '? Error response endpoint: $endpoint | Status Code: ${response.statusCode} | Body: ${response.body}');
          if (!_shouldSkipFailedSave(endpoint)) {
            await _saveFailedRequest(endpoint, body);
          }

          await _logError(
            'HTTP Error',
            'Código de respuesta: ${response.statusCode}',
            response.body,
            endpoint,
            jsonEncode({...body}),
          );
          print(
              '? Error response endpoint: $endpoint | Status Code: ${response.statusCode} | Body: ${response.body}');
        }
      } catch (e) {
        print('? Exception occurred while sending request to $endpoint: $e');
        if (!_shouldSkipFailedSave(endpoint)) {
          await _saveFailedRequest(endpoint, body);
        }
        await _updateConnectionStatus(false);
      }
      return null;
    } catch (e) {
      // 👇 No guardamos solicitudes fallidas de estos endpoints
      if (!_shouldSkipFailedSave(endpoint)) {
        await _saveFailedRequest(endpoint, body);
      }

      await _logError(
        'Exception',
        e.toString(),
        e is SocketException ? 'Network issue' : null,
        endpoint,
        jsonEncode({...body, 'token': token}),
      );

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
      ) {
    velocidad = double.parse(velocidad.toStringAsFixed(2));
    distanciaRecorrida = double.parse(distanciaRecorrida.toStringAsFixed(2));
    return _post('DescargaLecturaMensajes', {
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
      'DistanciaRecorrida': distanciaRecorrida // Added to body
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
      ) {
    velocidad = double.parse(velocidad.toStringAsFixed(2));
    distanciaRecorrida = double.parse(distanciaRecorrida.toStringAsFixed(2));
    return _post('DescargaLecturaPedidos', {
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
      'DistanciaRecorrida': distanciaRecorrida // Added to body
    });
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
      ) {
    velocidad = double.parse(velocidad.toStringAsFixed(2));
    distanciaRecorrida = double.parse(distanciaRecorrida.toStringAsFixed(2));
    return _post('FinalizarPedidoV2', {
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
      'Velocidad': velocidad, // Added to body
      'DistanciaRecorrida': distanciaRecorrida // Added to body
    });
  }

  static bool _shouldSkipFailedSave(String endpoint) {
    return endpoint == 'DescargaLecturaPedidos' ||
        endpoint == 'RegistrarCoordenadas' ||
        endpoint == 'RegistrarCoordenadasBatch' ||
        endpoint == 'RegistrarCierre' ||
        endpoint == 'DescargaPedidos';
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

  static Future<Map<String, dynamic>?> registrarCoordenadas(
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
      return await _post('RegistrarCoordenadas', {
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
            request['endpoint'] == 'RegistrarCoordenadasBatch' &&
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
          'endpoint': 'RegistrarCoordenadasBatch',
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
      var response = await _post('RegistrarUltLog', payload);

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
}
