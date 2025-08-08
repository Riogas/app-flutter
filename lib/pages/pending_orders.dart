import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../services/persistent_stream_manager.dart';
import '../services/pending_orders_diagnostic.dart'; // Add diagnostic import
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'order_detail_page.dart'; // Importa la nueva página de detalles
import 'dart:async';
import '../services/riogas_service.dart'; // Import the RioGasService
import 'package:geolocator/geolocator.dart'; // Import Geolocator for getting current location
import '../services/location_service.dart'; // Import your location service

class PendingOrdersPage extends StatefulWidget {
  @override
  _PendingOrdersPageState createState() => _PendingOrdersPageState();
}

class _PendingOrdersPageState extends State<PendingOrdersPage> {
  final FirebaseService _firebaseService = FirebaseService();
  final PersistentStreamManager _streamManager = PersistentStreamManager();
  List<String> _readOrderIds = [];
  int _orderCount = 0;
  int _newOrderCount = 0;
  late Stream<List<DocumentSnapshot>> _ordersStream;
  late Box constantBox;
  Box? pedidosBox;
  late String username = '';
  late String deviceId = '';
  late Box sesionBox; // Declare the sesionBox variable
  late int movilId = 0;
  late String textoPermisosGPS = '';
  final LocationService locationService =
      LocationService(); // Initialize locationService
  Timer? _hiveStateChecker; // Make it nullable
  Timer? _gpsPermissionChecker; // Timer para chequear permisos de GPS
  // Notificador para el estado del GPS
  final ValueNotifier<bool> _gpsEnabledNotifier = ValueNotifier(false);
  bool _descargaEnDebounce = false;

  bool _lecturaEnCurso = false; // 👈 Acá lo agregás
  bool _descargaEnCurso = false;
  final Set<int> _descargados = {}; // NUEVO: fuera del build, al nivel de clase
  final Set<int> _pedidosParaDescargar = {};

  @override
  void initState() {
    super.initState();
    print('🔧 PendingOrdersPage: initState() called - Instance: ${hashCode}');
    _initializeFirebase();
    _initializeHive().then((_) {
      print('🔧 PendingOrdersPage: Hive initialization completed');
      username = constantBox.get('username', defaultValue: '');
      deviceId = constantBox.get('DeviceID', defaultValue: '');
      movilId = constantBox.get('MovilID', defaultValue: 0);
    });
    _initPersistentStreams();
    _initGpsListener();

    // Microtask: chequea cada 5 segundos si los permisos de GPS están en "always"
    _gpsPermissionChecker = Timer.periodic(Duration(seconds: 5), (timer) async {
      LocationPermission permission = await Geolocator.checkPermission();
      bool hasAlways = permission == LocationPermission.always;
      // Si el estado de permisos cambió, actualiza el notifier para forzar rebuild
      if (sesionBox.isOpen) {
        bool lastPerm =
            sesionBox.get('_locationPermissionAlways', defaultValue: false);
        if (lastPerm != hasAlways) {
          sesionBox.put('_locationPermissionAlways', hasAlways);
          print(
              '[GPS_PERMISSION] Permiso de ubicación "always" cambiado a: $hasAlways');
          setState(() {}); // Fuerza rebuild para actualizar tarjetas
        }
      }
    });
  }

  void _initGpsListener() {
    // Estado inicial
    Geolocator.isLocationServiceEnabled().then((enabled) {
      _gpsEnabledNotifier.value = enabled;
    });
    // Escucha cambios en el servicio de ubicación
    Geolocator.getServiceStatusStream().listen((status) async {
      bool enabled = status == ServiceStatus.enabled;
      _gpsEnabledNotifier.value = enabled;
    });
  }

  Future<void> _initPersistentStreams() async {
    await _streamManager.initialize();
    print('🔄 [PendingOrdersPage] PersistentStreamManager initialized');
    // No need to add a listener here, as the stream manager handles it);
  }

  @override
  void dispose() {
    print('🔴 PendingOrdersPage: dispose() called - Instance: ${hashCode}');
    // Cancel the Timer if it is not null
    _hiveStateChecker?.cancel();
    _gpsPermissionChecker?.cancel();
    // Decrementa el contador de listeners de pedidos
    _streamManager.removeListener('pedidos');
    super.dispose();
  }

  Future<void> _initializeFirebase() async {
    await _firebaseService.initializeFirebase();
  }

  Future<void> _initializeHive() async {
    constantBox = await Hive.openBox('constantBox');
    final box = await Hive.openBox('pedidosBox');
    setState(() {
      pedidosBox = box;
    });
    sesionBox = await Hive.openBox('sessionBox');
    // Ya no es necesario inicializar ni sincronizar pedidosBox aquí, la lógica está centralizada en PersistentStreamManager
  }

  Map<String, Color> colorMap = {
    "Red": Colors.red,
    "Pink": Colors.pink,
    "Green": Colors.green,
    "Yellow": Colors.orange,
    // Agrega más colores según sea necesario
  };

  Color getColorFromName(String colorName) {
    return colorMap[colorName] ??
        Colors.white; // Devuelve blanco si el color no se encuentra
  }

  Map<String, dynamic>? getDelayInfo(int delayMinutes) {
    for (int id in [40, 41, 42, 43]) {
      if (constantBox.isOpen) {
        var data = constantBox.get(id.toString());
        // print("🔍 Leyendo constante con ID $id: $data");
        if (data != null && data['Estado'] == 'A') {
          // print("✅ Estado es 'A' para ID $id");
          // print(
          //   "🔢 Comparando delayMinutes: $delayMinutes con ValorMin: ${data['ValorMin']} y ValorMax: ${data['ValorMax']}",
          // );
          if ((delayMinutes >= data['ValorMin'] &&
                  delayMinutes <= data['ValorMax']) ||
              (delayMinutes <= data['ValorMin'] &&
                  delayMinutes >= data['ValorMax'])) {
            // print(
            //   "⏳ Delay $delayMinutes está entre ${data['ValorMin']} y ${data['ValorMax']} para ID $id",
            // );
            return {
              "Color": getColorFromName(data['Color']),
              "Etiqueta": data['Etiqueta'],
            };
          } else {
            // print(
            //   "❌ Delay $delayMinutes no está entre ${data['ValorMin']} y ${data['ValorMax']} para ID $id",
            // );
          }
        } else {
          // print("❌ Estado no es 'A' para ID $id o data es null");
        }
      } else {
        // print("⚠️ constantBox is closed. Skipping data retrieval for ID $id.");
      }
    }
    // print("❌ No se encontró un rango válido para delay $delayMinutes");
    return null;
  }

  Future<void> _markAsReadAndNavigate(
    Map<String, dynamic> pedido,
    int pedidoId,
  ) async {
    print("🟢 [_markAsReadAndNavigate] Inicio. Pedido ID: $pedidoId");

    // 1. Verificar si el GPS está activado
    print("🔍 Verificando si el GPS está activado...");
    bool isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationServiceEnabled) {
      print("❌ GPS desactivado. Mostrando SnackBar.");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Por favor, active el GPS para continuar.')),
      );
      return;
    }
    print("✅ GPS activado.");

    // 2. Marcar como leído en Hive
    if (pedidosBox != null) {
      await pedidosBox!.put(pedidoId, 'Leído');
      final estadoActual = pedidosBox!.get(pedidoId);
      print(
          "📦 Hive actualizado. Pedido $pedidoId marcado como 'Leído'. Estado actual: $estadoActual");
    } else {
      print("⚠️ pedidosBox es null. No se pudo marcar como leído.");
    }

    // 3. Preparar navegación
    print("➡️ Preparando navegación a OrderDetailPage...");

    final detalleHtml = pedido['DetalleHTML'];
    final estadoNro = pedido['EstadoNro'];
    final precio = pedido['Precio'] ?? 0;
    final tipo = pedido['Tipo'];
    final ubicacion =
        (pedido.containsKey('ubicacion') && pedido['ubicacion'] is GeoPoint)
            ? pedido['ubicacion'] as GeoPoint
            : null;

    print("""
🧭 Datos de navegación:
- EstadoNro: $estadoNro
- TotalPedido: $precio
- Tipo: $tipo
- Ubicación: ${ubicacion != null ? 'lat=${ubicacion.latitude}, lng=${ubicacion.longitude}' : 'null'}
""");

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderDetailPage(
          detalleHtml: detalleHtml,
          estadoNro: estadoNro,
          totalPedido: (pedido['Precio'] is double)
              ? pedido['Precio']
              : (pedido['Precio'] is int)
                  ? (pedido['Precio'] as int).toDouble()
                  : (pedido['Precio'] is String)
                      ? double.tryParse(pedido['Precio']) ?? 0.0
                      : 0.0,
          codPedido: pedidoId,
          pedidoTipo: tipo,
          ubicacion: ubicacion,
        ),
      ),
    );

    print("🚀 Navegación ejecutada con éxito hacia OrderDetailPage.");
  }

  Future<Box?> _openBoxSafe(String boxName) async {
    try {
      return await Hive.openBox(boxName);
    } catch (e) {
      print('❌ Error opening Hive box "$boxName": $e');
      return null;
    }
  }

  Future<void> verificarSoloDescargaPedidos({BuildContext? context}) async {
    const tag = '📦[DESCARGA_SYNC]';

    if (_descargaEnCurso) {
      print('$tag ⏳ Ya hay una sincronización en curso, se omite');
      return;
    }
    _descargaEnCurso = true;
    final startedAt = DateTime.now();

    try {
      final pedidos = PersistentStreamManager().pedidos;
      print('$tag ▶️ Iniciando DESCARGA de pedidos (${pedidos.length})...');

      if (pedidos.isEmpty) {
        print('$tag ℹ️ No hay pedidos para procesar.');
        return;
      }

      final Box? box = await _openBoxSafe('descargaLecturaPedidosBox');
      if (box == null) {
        print('$tag ❌ No se pudo abrir "descargaLecturaPedidosBox"');
        return;
      }

      int countDescarga = 0, countOmisos = 0, countErrores = 0;

      for (final doc in pedidos) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) {
          print('$tag ⚠️ Documento ${doc.id} sin data(), se omite');
          countErrores++;
          continue;
        }

        final dynamic rawId = data['id'];
        final int? pedidoId =
            rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
        if (pedidoId == null) {
          print('$tag ⚠️ Documento ${doc.id} con "id" inválido: $rawId');
          countErrores++;
          continue;
        }

        final estadoActual = box.get(pedidoId); // null | 'DESCARGA' | 'LECTURA'
        print('$tag 🔍 Pedido $pedidoId - Estado actual: $estadoActual');

        if (estadoActual == null) {
          try {
            print('$tag 📥 Enviando DESCARGA para $pedidoId...');
            await _callDescargaLecturaPedidos(
              data,
              pedidoId,
              lectDesc: 'DESCARGA',
              context: context,
            );
            await box.put(pedidoId, 'DESCARGA');
            // await box.flush();
            countDescarga++;
            print('$tag ✅ DESCARGA registrada para $pedidoId');
          } catch (e, st) {
            countErrores++;
            print('$tag ❌ Error DESCARGA $pedidoId: $e');
            print(st);
          }
        } else {
          countOmisos++;
          print(
              '$tag ⏭️ Pedido $pedidoId no requiere DESCARGA (estado=$estadoActual)');
        }
      }

      final elapsed = DateTime.now().difference(startedAt);
      print(
          '$tag 🏁 Finalizada en ${elapsed.inMilliseconds} ms (DESCARGA: $countDescarga, OMISOS: $countOmisos, ERRORES: $countErrores).');
    } catch (e, st) {
      print('$tag ❌ Error inesperado: $e');
      print(st);
    } finally {
      _descargaEnCurso = false;
    }
  }

  Future<void> marcarLecturaSiCorresponde({
    required Map<String, dynamic> pedido,
    required int pedidoId,
    BuildContext? context,
  }) async {
    const tag = '📦[LECTURA_ON_TAP_BG]';

    if (_lecturaEnCurso) {
      print('$tag ⏳ Hay otra LECTURA en curso, se omite');
      return; // retorna inmediato, nada bloquea la UI
    }
    _lecturaEnCurso = true;

    // Fire-and-forget: ejecuta en el próximo ciclo del event loop
    // y retornamos sin esperar.
    Future<void>(() async {
      try {
        final Box? box = await _openBoxSafe('descargaLecturaPedidosBox');
        if (box == null) {
          print('$tag ❌ No se pudo abrir "descargaLecturaPedidosBox"');
          return;
        }

        final estadoActual = box.get(pedidoId); // null | DESCARGA | LECTURA
        print('$tag 🔍 Pedido $pedidoId - Estado actual: $estadoActual');

        if (estadoActual == 'DESCARGA') {
          print('$tag 📖 Enviando LECTURA para $pedidoId (BG)...');
          await _callDescargaLecturaPedidos(
            pedido,
            pedidoId,
            lectDesc: 'LECTURA',
            context: context,
          );
          await box.put(pedidoId, 'LECTURA');
          // await box.flush();
          print('$tag ✅ LECTURA registrada para $pedidoId');
        } else if (estadoActual == null) {
          // Robustez: si no hubo DESCARGA previa, la hacemos rápido en BG y luego LECTURA
          print(
              '$tag ℹ️ Sin DESCARGA previa. Ejecutando DESCARGA+LECTURA para $pedidoId (BG)...');

          await _callDescargaLecturaPedidos(
            pedido,
            pedidoId,
            lectDesc: 'DESCARGA',
            context: context,
          );
          await box.put(pedidoId, 'DESCARGA');

          await _callDescargaLecturaPedidos(
            pedido,
            pedidoId,
            lectDesc: 'LECTURA',
            context: context,
          );
          await box.put(pedidoId, 'LECTURA');

          print('$tag ✅ DESCARGA+LECTURA registradas para $pedidoId');
        } else {
          print(
              '$tag ⏭️ Pedido $pedidoId ya estaba en LECTURA. No se vuelve a llamar.');
        }
      } catch (e, st) {
        print('$tag ❌ Error en marcarLecturaSiCorresponde($pedidoId): $e');
        print(st);
        // Si quisieras notificar en UI:
        // if (context != null && context.mounted) {
        //   ScaffoldMessenger.of(context).showSnackBar(
        //     SnackBar(content: Text('Error al marcar lectura del pedido $pedidoId')),
        //   );
        // }
      } finally {
        _lecturaEnCurso = false;
      }
    });

    // Retorna sin esperar
    print('$tag 🚀 Tarea de lectura lanzada en segundo plano para $pedidoId');
  }

  Future<void> _callDescargaLecturaPedidos(
    Map<String, dynamic> pedido,
    int pedidoId, {
    required String lectDesc,
    BuildContext? context, // <- Opcional para mostrar mensajes
  }) async {
    print(
        "🟠 [_callDescargaLecturaPedidos] Iniciando para pedidoId: $pedidoId");

    final String pedidoTpo =
        pedido['Tipo'] == 'Pedidos' ? 'PEDIDOS' : 'SERVICES';
    final String fechaHoraCmbEst = DateTime.now().toUtc().toIso8601String();

    try {
      final box = await Hive.openBox('sessionBox');

      final String? deviceId = box.get('deviceId');
      final String? movilid = box.get('movil');
      final int escenarioId =
          int.tryParse(box.get('escenario')?.toString() ?? '') ?? 0;
      final String? username = box.get('username');

      if ([deviceId, movilid, username].contains(null)) {
        print("❌ Faltan datos en sessionBox (deviceId, movilid o username)");
        if (context != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error de sesión: faltan datos del usuario.')),
          );
        }
        return;
      }

      String inAux1 = movilid!;
      String inAux2 = '';
      String latitud = '0.0', longitud = '0.0', utmx = '0.0', utmy = '0.0';

      print("🛰️ Obteniendo ubicación GPS...");
      try {
        final locationData = await locationService
            .getCurrentLocation()
            .timeout(const Duration(seconds: 5));

        if (locationData != null) {
          latitud = locationData['latitude'].toString();
          longitud = locationData['longitude'].toString();
          utmx = locationData['utmX'].toString();
          utmy = locationData['utmY'].toString();
          print("✅ Ubicación obtenida: $latitud, $longitud");
        } else {
          print("⚠️ No se obtuvo ubicación GPS.");
        }
      } on TimeoutException {
        print("⏰ Timeout al obtener la ubicación GPS.");
      } catch (e) {
        print("❌ Error al obtener ubicación GPS: $e");
      }

      double velocidad = 0.0;
      double distanciaRecorrida = 0.0;

      try {
        final locationBox = await Hive.openBox('locationBox');
        velocidad = double.parse(
          locationBox.get('lastSpeed', defaultValue: 0.0).toStringAsFixed(2),
        );
        distanciaRecorrida =
            locationBox.get('totalDistance', defaultValue: 0.0);
      } catch (e) {
        print("⚠️ Error leyendo datos de velocidad/distancia en Hive: $e");
      }

      print("📤 Enviando datos a RioGasService...");

      var data = constantBox.get('400');
      String llamarws = 'N';
      print("🔍 Leyendo constante con ID 400 para días de cache: $data");
      if (data != null && data['Estado'] == 'A') {
        print("✅ Estado es 'A' para ID 400");
        llamarws = data['Valor'] ??
            'N'; // Usar el valor de la constante o 'N' por defecto
      } else {
        print("❌ Estado no es 'A' para ID 400 o data es null");
        llamarws = 'N';
      }

      if (llamarws == 'S')
        try {
          await RioGasService.descargaLecturaPedidos(
            escenarioId,
            pedidoId,
            pedidoTpo,
            username!,
            'NroSesion', // TODO: usar real si se tiene
            deviceId!,
            lectDesc,
            fechaHoraCmbEst,
            movilid,
            inAux2,
            latitud,
            longitud,
            utmx,
            utmy,
            velocidad,
            distanciaRecorrida,
          ).timeout(const Duration(seconds: 8));

          print("✅ Petición completada con éxito para pedido $pedidoId");
        } on TimeoutException {
          print("⏰ Timeout esperando respuesta de RioGasService");
          if (context != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('La conexión con el servidor ha expirado.')),
            );
          }
        } catch (e) {
          print("❌ Error inesperado al llamar a RioGasService: $e");
          if (context != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al enviar datos al servidor.')),
            );
          }
        }
      else {
        print("ℹ️ No se llamará a RioGasService, 'llamarws' es 'N'");
        if (context != null) {
          //ScaffoldMessenger.of(context).showSnackBar(
          //SnackBar(content: Text('No se requiere llamada al servidor.')),
          //);
        }
      }
    } catch (e, st) {
      print("❌ Excepción general: $e");
      print(st);
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ocurrió un error inesperado.')),
        );
      }
    }
  }

  Future<void> _callDescargaPedidos(
    List<Map<String, dynamic>> pedidos,
    BuildContext context,
  ) async {
    const tag = '📥[_callDescargaPedidos]';
    print('$tag Iniciando con ${pedidos.length} pedidos');

    final String fechaHoraCmbEst = DateTime.now().toUtc().toIso8601String();

    try {
      final sessionBox = await Hive.openBox('sessionBox');
      final String? deviceId = sessionBox.get('deviceId');
      final String? movilid = sessionBox.get('movil');
      final int escenarioId =
          int.tryParse(sessionBox.get('escenario')?.toString() ?? '') ?? 0;
      final String? username = sessionBox.get('username');

      if ([deviceId, movilid, username].contains(null)) {
        print(
            "$tag ❌ Faltan datos en sessionBox (deviceId, movilid o username)");
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error de sesión: faltan datos del usuario.')),
          );
        }
        return;
      }

      String latitud = '0.0', longitud = '0.0', utmx = '0.0', utmy = '0.0';
      try {
        final locationData = await locationService
            .getCurrentLocation()
            .timeout(const Duration(seconds: 5));
        if (locationData != null) {
          latitud = locationData['latitude'].toString();
          longitud = locationData['longitude'].toString();
          utmx = locationData['utmX'].toString();
          utmy = locationData['utmY'].toString();
          print("$tag ✅ Ubicación obtenida: $latitud, $longitud");
        }
      } catch (e) {
        print("$tag ⚠️ Error obteniendo ubicación: $e");
      }

      double velocidad = 0.0;
      double distanciaRecorrida = 0.0;
      try {
        final locationBox = await Hive.openBox('locationBox');
        velocidad = double.parse(
          locationBox.get('lastSpeed', defaultValue: 0.0).toStringAsFixed(2),
        );
        distanciaRecorrida =
            locationBox.get('totalDistance', defaultValue: 0.0);
      } catch (e) {
        print("$tag ⚠️ Error leyendo velocidad/distancia: $e");
      }

      // Verificar si todos los pedidos tienen el mismo tipo
      final tiposUnicos = pedidos.map((p) {
        return p['Tipo'] == 'Pedidos' ? 'PEDIDOS' : 'SERVICES';
      }).toSet();

      if (tiposUnicos.length > 1) {
        print(
            '$tag ⚠️ Atención: hay más de un tipo de pedido en el lote: $tiposUnicos');
      }

      final pedidoTpo = tiposUnicos.first;

      var data = constantBox.get('401');
      String llamarws = data?['Estado'] == 'A' ? data['Valor'] ?? 'N' : 'N';
      print("$tag 🔍 Constante 401 => llamarws: $llamarws");

      if (llamarws != 'S') {
        print(
            "$tag ℹ️ No se ejecutará servicio porque llamarws es '$llamarws'");
        return;
      }

      final List<Map<String, dynamic>> sdtPedidos = pedidos.map((p) {
        final idRaw = p['id'];
        final id =
            idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '0') ?? 0;
        final tipo = p['Tipo'] == 'Pedidos' ? 'PEDIDOS' : 'SERVICES';
        return {
          "PedidoId": id,
          "PedidoTpo": tipo,
        };
      }).toList();

      await RioGasService.descargaPedidos(
        escenarioId,
        sdtPedidos,
        pedidoTpo,
        username!,
        'NroSesion', // TODO: reemplazar si hay sesión real
        deviceId!,
        'DESCARGA',
        fechaHoraCmbEst,
        movilid!,
        '',
        latitud,
        longitud,
        utmx,
        utmy,
        velocidad,
        distanciaRecorrida,
      ).timeout(const Duration(seconds: 10));

      print(
          "$tag ✅ Descarga enviada con éxito para ${sdtPedidos.length} pedidos");
    } catch (e, st) {
      print("$tag ❌ Error inesperado: $e");
      print(st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar descarga de pedidos')),
        );
      }
    }
  }

  Future<void> _procesarPedidosPendientes(
    List<DocumentSnapshot> pedidos,
    BuildContext context,
  ) async {
    const tag = '📦[DESCARGA_STREAM_UPDATE]';
    print('$tag Analizando ${pedidos.length} pedidos...');

    final Box? box = await _openBoxSafe('descargaLecturaPedidosBox');
    if (box == null) {
      print('$tag ❌ No se pudo abrir la box');
      return;
    }

    final List<Map<String, dynamic>> pedidosParaEnviar = [];

    for (final doc in pedidos) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      final rawId = data['id'];
      final int? pedidoId =
          rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
      if (pedidoId == null) continue;

      final estadoActual = box.get(pedidoId);
      if (estadoActual == null) {
        await box.put(pedidoId, 'EN_PROCESO'); // Evita reentradas
        _descargados.add(pedidoId);
        pedidosParaEnviar.add(data);
      } else {
        _descargados.add(pedidoId);
      }
    }

    if (pedidosParaEnviar.isNotEmpty) {
      print(
          '$tag 📥 Enviando ${pedidosParaEnviar.length} pedidos a descarga...');
      for (final p in pedidosParaEnviar) {
        final id = p['id'] is int
            ? p['id']
            : int.tryParse(p['id']?.toString() ?? '') ?? -1;
        await box.put(id, 'DESCARGA');
      }
      await _callDescargaPedidos(pedidosParaEnviar, context);
    } else {
      print('$tag ℹ️ No hay nuevos pedidos para descargar');
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🔧 PendingOrdersPage: build() called - Instance: ${hashCode}');

    if (pedidosBox == null) {
      print(
          '🔧 PendingOrdersPage: pedidosBox not initialized, showing loading');
      return Scaffold(
        appBar: AppBar(title: Text('Pedidos Pendientes (Cargando...)')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    print('🔧 PendingOrdersPage: Building main scaffold');

    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<List<DocumentSnapshot>>(
          valueListenable: _streamManager.pedidosNotifier,
          builder: (context, pedidos, child) {
            final count = pedidos.where((order) {
              var orderData = order.data() as Map<String, dynamic>?;
              int pedidoId = orderData?['id'] ?? -1;
              var pedidoEstado = pedidosBox!.get(pedidoId);
              return pedidoEstado != 'Procesando';
            }).length;
            return Text('Visitas ($count)');
          },
        ),
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box('sessionBox').listenable(
            keys: ['_locationPermissionAlways', '_locationPermissionDenied']),
        builder: (context, sessionBox, _) {
          bool locationPermissionAlways =
              sessionBox.get('_locationPermissionAlways', defaultValue: false);
          bool locationPermissionDenied =
              sessionBox.get('_locationPermissionDenied', defaultValue: true);

          return ValueListenableBuilder(
            valueListenable:
                (Hive.box('pedidosBox') as Box<dynamic>).listenable(),
            builder: (context, box, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: _gpsEnabledNotifier,
                builder: (context, isLocationServiceEnabled, _) {
                  return ValueListenableBuilder<List<DocumentSnapshot>>(
                    valueListenable: _streamManager.pedidosNotifier,
                    builder: (context, pedidos, child) {
                      print('🔍 PendingOrders pedidosNotifier state:');
                      print('   Widget Instance: ${hashCode}');
                      print('   Has data: ${pedidos.isNotEmpty}');
                      if (pedidos.isNotEmpty) {
                        print('   Data length: ${pedidos.length}');
                        print('   Sample data: ${pedidos.first.id}');
                      }

                      // Acumula pedidos que aún no fueron descargados
                      for (var order in pedidos) {
                        final pedidoData = order.data() as Map<String, dynamic>;
                        final int pedidoId = pedidoData['id'] ?? -1;

                        // Si nunca fue descargado, lo agregamos al set temporal
                        if (!_descargados.contains(pedidoId)) {
                          _pedidosParaDescargar.add(pedidoId);
                        }
                      }

                      // Lanza procesamiento luego del frame para no bloquear el build
                      // Dentro del ValueListenableBuilder o build()
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_pedidosParaDescargar.isEmpty) {
                          print(
                              '🟡 [PostFrame] No hay pedidos pendientes para procesar.');
                          return;
                        }

                        if (_descargaEnDebounce) {
                          print(
                              '⏳ [PostFrame] Ya hay un procesamiento en espera, se ignora este frame.');
                          return;
                        }

                        _descargaEnDebounce = true;

                        print(
                            '🟢 [PostFrame] Iniciando debounce para ${_pedidosParaDescargar.length} pedidos...');

                        Future.delayed(const Duration(milliseconds: 150),
                            () async {
                          final pedidosFiltrados = pedidos.where((order) {
                            final pedidoData =
                                order.data() as Map<String, dynamic>;
                            final pedidoId = pedidoData['id'] ?? -1;
                            return _pedidosParaDescargar.contains(pedidoId);
                          }).toList();

                          if (pedidosFiltrados.isNotEmpty) {
                            print(
                                '✅ [DebouncedCall] Procesando ${pedidosFiltrados.length} pedidos filtrados...');
                            await _procesarPedidosPendientes(
                                pedidosFiltrados, context);
                          } else {
                            print(
                                '⚠️ [DebouncedCall] No hay pedidos válidos tras filtrar.');
                          }

                          _pedidosParaDescargar.clear();
                          _descargaEnDebounce = false;
                          print(
                              '🔁 [DebouncedCall] Procesamiento completado. Flags reseteados.');
                        });
                      });

                      if (pedidos.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('No hay pedidos pendientes.'),
                              SizedBox(height: 16),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: pedidos.length,
                        itemBuilder: (context, index) {
                          var pedido =
                              pedidos[index].data() as Map<String, dynamic>;
                          int pedidoId = pedido['id'] ?? -1;

                          if (_getPedidoEstado(pedidoId) == 'Procesando') {
                            return SizedBox.shrink();
                          }

                          String tipo = pedido['Tipo'] ?? 'Pedidos';
                          String direccion =
                              pedido['ClienteDireccion'] ?? 'Desconocida';
                          String direccionCorta = direccion.length > 20
                              ? direccion.substring(0, 20) + '...'
                              : direccion;

                          String etiquetaTexto = _getPedidoEstado(pedidoId);
                          Color etiquetaColor = _getPedidoEstadoColor(pedidoId);

                          bool mostrarEtiqueta = etiquetaTexto != 'Leído' &&
                              etiquetaTexto != 'No Leído' &&
                              etiquetaTexto.isNotEmpty;

                          bool cardBlocked = !isLocationServiceEnabled ||
                              locationPermissionDenied ||
                              !locationPermissionAlways;

                          String textoPermisosGPS = '';
                          if (cardBlocked) {
                            if (!locationPermissionAlways) {
                              textoPermisosGPS =
                                  'Bloqueado - Sin permisos de GPS.';
                            } else if (locationPermissionDenied) {
                              textoPermisosGPS =
                                  'Bloqueado - Sin Permisos de GPS activos.';
                            } else {
                              textoPermisosGPS = 'Bloqueado - Sin GPS Activado';
                            }
                          }

                          return GestureDetector(
                            onTap: () async {
                              print(
                                  "🟢 [TAP] Tap detectado en tarjeta con pedidoId: $pedidoId");

                              if (cardBlocked) {
                                print(
                                    "🔴 [BLOQUEADO] cardBlocked = true. Mostrando mensaje de permisos GPS");
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Por favor, active el GPS y los permisos.'),
                                  ),
                                );
                                return;
                              }

                              print(
                                  "🟡 [CHECK] cardBlocked = false. Verificando DetalleHTML...");

                              if (pedido.containsKey('DetalleHTML') &&
                                  pedido['DetalleHTML'].isNotEmpty) {
                                print(
                                    "🔵 [DETALLE OK] DetalleHTML presente, llamando descargaLectura...");
                                await marcarLecturaSiCorresponde(
                                  pedido: pedido,
                                  pedidoId: pedidoId,
                                  context: context,
                                );
                                print("🟣 [NAVIGATE] Navegando a detalle...");
                                await _markAsReadAndNavigate(pedido, pedidoId);
                              } else {
                                print(
                                    "⚠️ [SIN DETALLE] pedido['DetalleHTML'] no está presente o está vacío.");
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('No hay detalles disponibles')),
                                );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0, vertical: 4.0),
                              child: Card(
                                color: cardBlocked
                                    ? Colors.grey
                                    : (_getPedidoEstado(pedidoId) == 'No Leído'
                                        ? (tipo == 'Services'
                                            ? Colors.deepPurpleAccent
                                            : Colors.lightBlue)
                                        : (tipo == 'Services'
                                            ? Colors.deepPurple.withOpacity(0.7)
                                            : Colors.blueGrey)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10.0),
                                ),
                                elevation: 5,
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(height: 4.0),
                                      Row(
                                        children: [
                                          Text(
                                            'Número: $pedidoId',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              fontSize: 14.0,
                                            ),
                                          ),
                                          SizedBox(width: 8.0),
                                          if (!cardBlocked && mostrarEtiqueta)
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 6.0,
                                                  vertical: 2.0),
                                              decoration: BoxDecoration(
                                                color: etiquetaColor,
                                                borderRadius:
                                                    BorderRadius.circular(8.0),
                                              ),
                                              child: Text(
                                                etiquetaTexto,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12.0,
                                                ),
                                              ),
                                            ),
                                          Spacer(),
                                          Icon(
                                            tipo == 'Services'
                                                ? Icons.build
                                                : Icons.local_shipping,
                                            color: Colors.white,
                                            size: 20.0,
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 4.0),
                                      Row(
                                        children: [
                                          Text(
                                            'Dirección: ${cardBlocked ? textoPermisosGPS : direccionCorta}',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12.0,
                                            ),
                                          ),
                                          Spacer(),
                                          if (!cardBlocked &&
                                              pedido.containsKey('WazeURL'))
                                            Icon(Icons.location_on,
                                                color: Colors.white,
                                                size: 20.0),
                                        ],
                                      ),
                                      SizedBox(height: 4.0),
                                      Row(
                                        children: [
                                          Text(
                                            tipo == 'Pedidos'
                                                ? 'Servicio: ${cardBlocked ? textoPermisosGPS : (pedido['ServicioNombre'] ?? 'Desconocido')}'
                                                : 'Defecto: ${cardBlocked ? textoPermisosGPS : (pedido['Defecto'] ?? 'Desconocido')}',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12.0,
                                            ),
                                          ),
                                          Spacer(),
                                          if (!cardBlocked &&
                                              pedido.containsKey('Precio'))
                                            Text(
                                              'Importe: ${pedido['Precio']}',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12.0,
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (!cardBlocked &&
                                          pedido.containsKey('PedidoObs') &&
                                          pedido['PedidoObs'].isNotEmpty)
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            SizedBox(height: 4.0),
                                            Text(
                                              'Observaciones: ${pedido['PedidoObs']}',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12.0,
                                              ),
                                            ),
                                          ],
                                        ),
                                      SizedBox(height: 4.0),
                                      if (!cardBlocked)
                                        Row(
                                          children: [
                                            _buildMinutesLeftStream(pedido),
                                            SizedBox(width: 8.0),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMinutesLeftStream(Map<String, dynamic> pedido) {
    final StreamController<int> controller = StreamController<int>();
    DateTime now = DateTime.now();
    DateTime fchHoraPara = (pedido['FchHoraMaxEntComp'] as Timestamp).toDate();
    controller.add(fchHoraPara.difference(now).inMinutes);

    Timer.periodic(Duration(minutes: 1), (_) {
      now = DateTime.now();
      controller.add(fchHoraPara.difference(now).inMinutes);
    });

    return StreamBuilder<int>(
      stream: controller.stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Text(
            'Calculando...',
            style: TextStyle(color: Colors.white, fontSize: 12.0),
          );
        } else {
          int minutesLeft = snapshot.data!;
          var delayInfo = getDelayInfo(minutesLeft);
          return Row(
            children: [
              Text(
                'Min restantes: $minutesLeft',
                style: TextStyle(color: Colors.white, fontSize: 12.0),
              ),
              SizedBox(width: 8.0),
              if (delayInfo != null)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: delayInfo["Color"],
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Text(
                    delayInfo["Etiqueta"],
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.0,
                    ),
                  ),
                ),
            ],
          );
        }
      },
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate();
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
  }

  String _getPedidoEstado(int pedidoId) {
    if (pedidosBox == null) return '';
    var pedidoEstado = pedidosBox!.get(pedidoId);
    if (pedidoEstado == null) {
      return 'No Leído';
    }
    return pedidoEstado.toString();
  }

  Color _getPedidoEstadoColor(int pedidoId) {
    if (pedidosBox == null) return Colors.transparent;
    var pedidoEstado = pedidosBox!.get(pedidoId);
    if (pedidoEstado == null) {
      return Colors.black;
    } else if (pedidoEstado == 'Procesando') {
      return Colors.lightBlue;
    } else if (pedidoEstado == 'Enviando') {
      return Colors.orange;
    }
    return Colors.transparent;
  }
}
