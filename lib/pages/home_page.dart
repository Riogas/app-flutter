import 'package:MoveIT/main.dart';
import 'package:flutter/material.dart';
import 'pending_orders.dart';
import 'map_page.dart';
import 'settings_page.dart';
import 'message_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'dart:async';
import '../services/session_service.dart';
import '../services/firebase_service.dart';
import '../services/location_service.dart'; // ðŸ”¹ Importamos LocationService
import '../services/riogas_service.dart'; // ðŸ”¹ Importamos LocationService
import '../services/logout_service.dart'; // ðŸ”¥ Servicio de logout (forced logout)
import '../services/debug_config_manager.dart'; // ðŸ†• Sistema de logging remoto
import '../services/modo_restringido.dart'; // 🏪 Perfil comercio (escenario 9998)
import 'v2/promos_shell.dart'; // 🏪 Shell del modo restringido
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart'; // Import Geolocator for Position
import 'package:MoveIT/pages/login_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // Importa firebase_messaging
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Importa flutter_local_notifications
import 'package:connectivity_plus/connectivity_plus.dart'; // Importa connectivity_plus
import 'package:internet_connection_checker/internet_connection_checker.dart'; // Importa internet_connection_checker
import '../services/counter_service.dart'; // Import the new CounterService
import '../utils/connection_check.dart';
import '../utils/screenBlock.dart'; // Import secureScreen
import '../utils/constantes.dart';
import 'v2/promociones_page.dart';
import 'package:android_intent_plus/android_intent.dart'; // Import AndroidIntent
import 'package:android_intent_plus/flag.dart'; // Import Flag for AndroidIntent
import 'package:flutter/services.dart'; // Import SystemNavigator
import '../utils/stream_manager.dart'; // o el path correcto
import '../services/persistent_stream_manager.dart';
import '../services/ui_prefs.dart'; // 🎨 Toggle de diseño nuevo/clásico
import '../services/nuevo_pedido_notification_service.dart'; // 🔔 Notif. pedidos nuevos
import 'v2/v2_header.dart'; // 🎨 Navbar nuevo (también en el diseño clásico)
import 'v2/home_v2_scaffold.dart'; // 🎨 Rediseño Home V2

// FunciÃ³n utilitaria para abrir cajas Hive de forma segura
dynamic openBoxSafe(String boxName) async {
  try {
    if (!Hive.isBoxOpen(boxName)) {
      return await Hive.openBox(boxName);
    }
    return Hive.box(boxName);
  } catch (e) {
    print('âŒ Error abriendo la caja $boxName: $e');
    return null;
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final FirebaseService _firebaseService = FirebaseService();
  final PersistentStreamManager _streamManager = PersistentStreamManager();
  StreamSubscription<LatLng>?
      _locationSubscription; // ðŸ”¹ Guardamos la suscripciÃ³n
  final LocationService _locationService =
      LocationService(); // ðŸ”¹ Definimos _locationService
  int _selectedIndex = 0;
  // ðŸ”¹ Use ValueNotifier for message counter to avoid UI rebuilds
  late ValueNotifier<int> _messageCountNotifier;
  // ðŸ”¹ Use ValueNotifier for pending orders counter
  late ValueNotifier<int> _pendingOrdersCountNotifier;
  bool _constantsLoaded = false;
  StreamSubscription? _ordersSubscription;
  final Completer<void> _locationServiceCompleter = Completer<void>();
  String _movil = '0';
  StreamSubscription? _connectivitySubscription;
  final CounterService _counterService =
      CounterService(); // Initialize CounterService
  late AnimationController _blinkController;
  late Timer _connectivityCheckTimer; // Add a Timer for periodic checks
  final ConnectionCheck _connectionCheck = ConnectionCheck();
  final ValueNotifier<Map<String, dynamic>> _connectionStatusNotifier =
      ValueNotifier({'network': true, 'firestore': true, 'riogas': true});
  bool showPopup = false; // Add a flag for showing the popup
  Box? pedidosBox;
  bool _isFirstLoad = true; // Flag to suppress notifications on first load
  StreamSubscription<bool>? _gpsSubscription;
  final StreamController<bool> _gpsStreamController =
      StreamController<bool>.broadcast();
  bool _isDialogVisible =
      false; // Flag to track if the dialog is already visible

  // ðŸ”¹ FIX: Create stable stream for session management to prevent child widget rebuilds
  late Stream<Map<String, dynamic>?> _sesionesStream;

  // ðŸš¨ Flag para bloquear UI mientras se verifica sesiÃ³n
  bool _isVerifyingSession = true;

  // ðŸ†• Variables para cooldown de cambio de estado
  DateTime? _lastEstadoChangeAttempt;
  bool _isEstadoChanging = false;
  int _estadoCooldownSeconds = 90;
  Timer? _estadoCooldownTimer; // Timer para actualizar countdown visual

  static final List<Widget> _widgetOptions = [
    PendingOrdersPage(), // Back to normal page for testing
    MapPage(),
    MessagePage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    //secureScreen();
    UiPrefs.init(); // 🎨 Cargar preferencia de diseño (nuevo/clásico)
    NuevoPedidoNotificationService().init(); // 🔔 Aviso de pedidos nuevos

    final streamManager = PersistentStreamManager();

    if (!streamManager.isProperlyInitialized) {
      streamManager.initialize().then((_) {
        print('âœ… [HomePage] StreamManager inicializado correctamente');
        setState(
            () {}); // Para asegurar reconstrucciÃ³n si usÃ¡s ValueListenableBuilder
      });
    }

    // ðŸ†• Inicializar sistema de logging remoto (en caso de que app se haya cerrado y reabierto)
    _initDebugConfigListener();

    // ðŸ”¹ Initialize message counter notifier
    _messageCountNotifier = ValueNotifier<int>(0);
    // ðŸ”¹ Initialize pending orders counter notifier
    _pendingOrdersCountNotifier = ValueNotifier<int>(0);

    _blinkController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true); // Blinking effect

    // ðŸ”¹ FIX: Initialize stable session stream to prevent child widget rebuilds
    _sesionesStream = _firebaseService.getSesionesStream();

    _initializeHomePage();
    //_initPedidosBoxListener(); // Reemplazado por el nuevo mÃ©todo reactivo
    _setupPedidosBoxReactiveCounter(); // <-- Nuevo mÃ©todo reactivo
    _initMensajesBoxListener(); // Add this to initialize the listener

    // ðŸ”¹ Resetear la bandera para futuros chequeos de sesiÃ³n
    Future.delayed(Duration(seconds: 10), () async {
      var box = await Hive.openBox('sessionBox');
      await box.put('firstLoginDone', false);
      // print(
      //   "ðŸ”„ Reset de la bandera firstLoginDone, futuras sesiones serÃ¡n chequeadas normalmente.",
      // );
    });

    // ðŸ”¹ Inicializar el servicio de ubicaciÃ³n
    // 🏪 El comercio no trackea: el LocationService legado dispara el intent
    // de exención de batería en cada init, sin motivo para este perfil.
    if (!ModoRestringido.activo.value) {
      _initializeLocationService();
    }

    // ðŸ”¹ Escuchar cambios en Firestore para pedidos y mensajes
    // REMOVED: _listenToFirestoreChangesWithDelay(); // This was creating duplicate direct Firestore subscriptions
    // The required streams are already handled by _listenToMessages() and _listenToPendingOrders()

    // ðŸ”¹ Inicializar la verificaciÃ³n de conectividad
    _checkInternetConnectivity();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      // Handle connectivity changes
    });

    connectivitySubscription =
        _connectivitySubscription; // ðŸ”¹ Asignar a la global

    /*// Start the counter for periodic connectivity checks
    _counterService.startCounter(
      intervalSeconds: 10,
      onTick: _checkConnectivityAndPerformAction,
    );*/

    // ðŸ”¹ Inicializar la verificaciÃ³n de conectividad periÃ³dica
    _connectivityCheckTimer = Timer.periodic(
      Duration(seconds: 90),
      (timer) => _checkInternetConnectivity(),
    );

    connectivityCheckTimer =
        _connectivityCheckTimer; // ðŸ”¹ Asignar a la global

    // Obtener el valor de la constante 200
    //_initializeRetryInterval();

    _initGpsListener();

    // ðŸ†• Listener para resetear cooldown cuando cambia el estado desde Firestore
    _streamManager.movilNotifier.addListener(_onMovilStateChanged);
  }

  /// ðŸ†• Resetea el cooldown cuando el estado del mÃ³vil cambia desde Firestore
  void _onMovilStateChanged() {
    if (_lastEstadoChangeAttempt != null) {
      // Si hay un cooldown activo, resetearlo porque el estado cambiÃ³
      _stopEstadoCooldownTimer();
      setState(() {
        _lastEstadoChangeAttempt = null;
      });
      print(
          'âœ… [ESTADO_COOLDOWN] Cooldown reseteado por cambio de estado desde Firestore');
    }
  }

  /// ðŸ†• Inicia el timer de cooldown que actualiza la UI cada segundo
  void _startEstadoCooldownTimer() {
    _estadoCooldownTimer?.cancel(); // Cancelar timer previo si existe

    _estadoCooldownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_lastEstadoChangeAttempt == null) {
        // Ya no hay cooldown, detener timer
        timer.cancel();
        return;
      }

      final elapsed = DateTime.now().difference(_lastEstadoChangeAttempt!);

      if (elapsed.inSeconds >= _estadoCooldownSeconds) {
        // Cooldown expirÃ³, resetear
        _stopEstadoCooldownTimer();
        setState(() {
          _lastEstadoChangeAttempt = null;
        });
        print('âœ… [ESTADO_COOLDOWN] Cooldown expirado automÃ¡ticamente');
      } else {
        // Actualizar UI para mostrar countdown actualizado
        setState(() {});
      }
    });
  }

  /// ðŸ†• Detiene el timer de cooldown
  void _stopEstadoCooldownTimer() {
    _estadoCooldownTimer?.cancel();
    _estadoCooldownTimer = null;
  }

  /// ðŸ†• Inicializa el listener de debug config desde Firestore
  /// Se ejecuta en initState de HomePage para detectar cambios de debugMode
  /// incluso si la app fue cerrada y reabierta sin hacer login de nuevo
  Future<void> _initDebugConfigListener() async {
    try {
      final sessionBox = await Hive.openBox('sessionBox');
      final movil = sessionBox.get('movil');

      if (movil == null || movil == "0") {
        print(
            'âš ï¸ [DEBUG_CONFIG] No hay mÃ³vil en sesiÃ³n, saltando inicializaciÃ³n');
        return;
      }

      // Forzar reinicio del listener (en caso de que app se cerrÃ³ y reabriÃ³)
      await DebugConfigManager.startListening(movil);
      print(
          'âœ… [DEBUG_CONFIG] Listener reiniciado en HomePage para mÃ³vil $movil');
    } catch (e) {
      print('âš ï¸ [DEBUG_CONFIG] Error reiniciando listener en HomePage: $e');
      // No bloqueamos la inicializaciÃ³n de HomePage si falla esto
    }
  }

  Future<void> _initializeRetryInterval() async {
    final retryIntervalString = await getConstantValue('200');
    final retryInterval = int.tryParse(retryIntervalString ?? '');

    print("valor de la constante 200: $retryIntervalString");

    if (retryInterval != null && retryInterval > 0) {
      // Llamar periÃ³dicamente a monitorAndSendErrors solo si el valor es vÃ¡lido
      Timer.periodic(Duration(seconds: retryInterval), (timer) async {
        print("Monitor de errores activado.");
        await RioGasService.monitorAndSendErrors();
      });
    } else {
      print(
          "âŒ No se pudo iniciar el monitor de errores: valor de la constante 200 no vÃ¡lido.");
    }

    _connectionCheck.startMonitoring();
    _connectionCheck.connectionStatusStream.listen((status) {
      _updateConnectionStatus(status); // Update only the notifier
      if (status['showPopup'] == true) {
        _showRioGasConnectivityModal();
      }
    });
  }

  @override
  void dispose() {
    _blinkController.dispose(); // Dispose the animation controller
    _messageCountNotifier.dispose(); // ðŸ”¹ Dispose message counter notifier
    _pendingOrdersCountNotifier
        .dispose(); // ðŸ”¹ Dispose pending orders counter notifier
    _counterService.stopCounter(); // Stop the counter when disposing
    _ordersSubscription?.cancel();
    _locationServiceCompleter.future.then((_) {
      _locationSubscription
          ?.cancel(); // ðŸ”¹ Cancelamos el stream de ubicaciÃ³n
      _locationService
          .stopLocationUpdates(); // ðŸ”¹ Detenemos el servicio correctamente
    });
    _connectivitySubscription
        ?.cancel(); // ðŸ”¹ Cancelar la suscripciÃ³n de conectividad
    _connectivityCheckTimer.cancel(); // Cancel the timer when disposing
    _connectionCheck.stopMonitoring();
    _connectionStatusNotifier.dispose(); // Dispose the notifier
    _gpsSubscription?.cancel();
    _gpsStreamController.close();

    // ðŸ†• Detener timer de cooldown y remover listener del estado del mÃ³vil
    _stopEstadoCooldownTimer();
    _streamManager.movilNotifier.removeListener(_onMovilStateChanged);

    super.dispose();
  }

  Future<void> _initializeHomePage() async {
    print('ðŸ  [HOME_PAGE] _initializeHomePage() iniciando...');
    print(
        'â„¹ï¸ [HOME_PAGE] SIMPLIFICADO: Deslogueo forzado manejado exclusivamente por FCM');
    print(
        'â„¹ï¸ [HOME_PAGE] No se verifica sesiÃ³n aquÃ­ para evitar race conditions');

    // ðŸ”“ Desbloquear UI inmediatamente
    setState(() {
      _isVerifyingSession = false;
    });

    // Cargar datos de sesiÃ³n e inicializar servicios
    await _loadSessionData();
    await RioGasService.initializeService();

    var box = await openBoxSafe('sessionBox');
    if (box == null) return;

    bool firstLoginDone = box.get('firstLoginDone', defaultValue: false);
    setState(() {
      _isFirstLoad = !firstLoginDone;
    });

    _listenToMessages();
    _listenToPendingOrders();
    _printConstantDocumentNames();

    setState(() {
      _isFirstLoad = false;
    });

    print('âœ… [HomePage] _initializeHomePage() completado exitosamente');
  }

  Future<void> _initializeLocationService() async {
    try {
      await _locationService.initializeLocationUpdates(context);
      _locationSubscription =
          _locationService.locationStream.listen((location) {});
      _locationServiceCompleter.complete();

      locationSubscription =
          _locationSubscription; // ðŸ”¹ Guardamos la suscripciÃ³n
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Error al inicializar el servicio de ubicaciÃ³n: $e')),
      );
      _locationServiceCompleter.completeError(e);
    }
  }

  Future<void> _loadSessionData() async {
    var box = await openBoxSafe('sessionBox');
    if (box == null) return;
    box.toMap().forEach((key, value) => null);
    setState(() {
      _movil = box.get('movil', defaultValue: '0');
    });
  }

  Future<void> _printConstantDocumentNames() async {
    if (!_constantsLoaded) {
      try {
        var box = await openBoxSafe('sessionBox');
        if (box == null) return;
        String escenario = box.get('escenario', defaultValue: '1000');
        QuerySnapshot querySnapshot = await FirebaseFirestore.instance
            .collection('Constantes-1000')
            .get();
        querySnapshot.docs.forEach((doc) => null);
        setState(() {
          _constantsLoaded = true;
        });
      } catch (e) {
        // print("âŒ Error al obtener documentos de 'Constantes-1000': $e");
      }
    }
  }

  void _initPedidosBoxListener() async {
    final box = await openBoxSafe('pedidosBox');
    if (box == null) return;
    setState(() {
      pedidosBox = box;
    });
    // ðŸ”¹ Initialize pending orders counter from existing data (No LeÃ­do)
    int initialCount = _countPedidosNoLeidos(box);
    _pendingOrdersCountNotifier.value = initialCount;

    // ðŸ”¹ Listen for changes in pedidosBox and update the notifier
    box.watch().listen((event) {
      int pendingCount = _countPedidosNoLeidos(box);
      _pendingOrdersCountNotifier.value = pendingCount;
    });
    // Ya no es necesario agregar listeners manuales aquÃ­, la lÃ³gica de sincronizaciÃ³n estÃ¡ centralizada en PersistentStreamManager
  }

// Helper to count pedidos "No LeÃ­do" (same logic as PendingOrdersPage)
  int _countPedidosNoLeidos(Box box) {
    int count = 0;
    print('[PEDIDOS] Recorriendo ${box.keys.length} pedidos en pedidosBox...');
    for (var key in box.keys) {
      var pedidoEstado = box.get(key);
      print('[PEDIDOS] Pedido $key â†’ Estado: $pedidoEstado');
      if (pedidoEstado == null || pedidoEstado == 'No LeÃ­do') {
        count++;
        print('[PEDIDOS] Pedido $key estÃ¡ sin leer (null o "No LeÃ­do")');
      }
    }
    print('[PEDIDOS] Total de pedidos no leÃ­dos: $count');
    return count;
  }

  // Refresca el contador de pedidos no leÃ­dos basado en los pedidos actuales del stream y su estado en Hive
  void _setupPedidosBoxReactiveCounter() async {
    final box = await openBoxSafe('pedidosBox');
    if (box == null) {
      print('[PEDIDOS] No se pudo abrir pedidosBox');
      return;
    }
    setState(() {
      pedidosBox = box;
    });
    print('[PEDIDOS] pedidosBox inicializado para contador reactivo');

    // Escucha cambios en el stream de pedidos y en Hive
    void updatePedidosCount() async {
      // Solo cuentan los pedidos que estÃ¡n en el stream y NO estÃ¡n en Hive como 'Procesando'
      final pedidos = _streamManager.pedidos;
      print('[PEDIDOS][DEBUG] pedidos en stream: ${pedidos.length}');
      int count = 0;
      for (var pedido in pedidos) {
        var pedidoIdStr = pedido.id.toString();
        int? pedidoIdNum =
            int.tryParse(pedidoIdStr.replaceAll(RegExp(r'[^0-9]'), ''));
        var estado = box.get(pedidoIdNum ?? pedidoIdStr);
        print(
            '[PEDIDOS][DEBUG] pedido.id: ${pedido.id} â†’ clave Hive: ${pedidoIdNum ?? pedidoIdStr}, estado: $estado');
        // Solo NO cuenta los que estÃ¡n en Hive como 'Procesando'
        if (estado != 'Procesando') {
          count++;
          print(
              '[PEDIDOS][DEBUG] pedido.id: ${pedido.id} cuenta como PENDIENTE (estado: $estado)');
        } else {
          print(
              '[PEDIDOS][DEBUG] pedido.id: ${pedido.id} NO cuenta (estado: Procesando)');
        }
      }
      print('[PEDIDOS][SMART COUNT] Total de pedidos pendientes: $count');
      _pendingOrdersCountNotifier.value = count;
    }

    // Inicializa el contador con el valor actual
    updatePedidosCount();

    // Escucha cambios en Hive (incluye cualquier actualizaciÃ³n de estado de un pedido)
    box.watch().listen((event) {
      print(
          '[PEDIDOS][WATCH] Evento en pedidosBox: key=${event.key}, value=${event.value}, deleted=${event.deleted}');
      // Espera un microtask para asegurar que el cambio se refleje en el box antes de contar
      Future.microtask(() => updatePedidosCount());
    });

    // Escucha cambios en el stream de pedidos
    _streamManager.pedidosNotifier.addListener(() {
      updatePedidosCount();
    });

    // Refuerza la actualizaciÃ³n del contador al volver de una pantalla (por ejemplo, OrderDetail)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      updatePedidosCount();
    });
  }

  // Refresca el contador de mensajes no leÃ­dos basado en los mensajes actuales del stream y su estado en Hive
  void _initMensajesBoxListener() async {
    var mensajesBox = await openBoxSafe('mensajesBox');
    if (mensajesBox == null) return;

    void updateMensajesCount() async {
      final mensajes = _streamManager.mensajes;
      int count = 0;
      for (var mensaje in mensajes) {
        var estado = mensajesBox.get(mensaje.id);
        if (estado == null || estado == 'Descargado') {
          count++;
        }
      }
      print('[MENSAJES][SMART COUNT] Total de mensajes no leÃ­dos: $count');
      _messageCountNotifier.value = count;
    }

    // Inicializa el contador con el valor actual
    updateMensajesCount();

    // Escucha cambios en Hive
    mensajesBox.watch().listen((event) {
      updateMensajesCount();
    });

    // Escucha cambios en el stream de mensajes
    _streamManager.mensajesNotifier.addListener(() {
      updateMensajesCount();
    });
  }

  void _initGpsListener() {
    _gpsSubscription = _gpsSubscription = Geolocator.getServiceStatusStream()
        .map((ServiceStatus status) => status == ServiceStatus.enabled)
        .listen((bool isEnabled) {
      _gpsStreamController.add(isEnabled);
    });

    gpsSubscription = _gpsSubscription; // ðŸ”¹ Asignar a la global
  }

  void _listenToMessages() async {
    // Ya no se agrega manualmente ningÃºn listener aquÃ­. El ValueListenableBuilder en el build() se encarga de reaccionar a los cambios.
    // Si necesitas inicializar datos de Hive, hazlo aquÃ­ una sola vez si es necesario.
    // La lÃ³gica de actualizaciÃ³n de Hive y procesamiento de mensajes debe estar en PersistentStreamManager o en los listeners de Hive.
    var mensajesBox = await openBoxSafe('mensajesBox');
    if (mensajesBox == null) return;
    // LÃ³gica de inicializaciÃ³n si es necesaria, pero sin listeners manuales.
  }

  // ðŸ”¹ Separate method for expensive operations that run in background
  void _processNewMessagesInBackground(
      List<DocumentSnapshot> newMessages) async {
    // Run expensive operations without blocking the UI
    Future.microtask(() async {
      try {
        var box = await openBoxSafe('sessionBox');
        if (box == null) return;

        String escenario = box.get('escenario', defaultValue: '1000');
        String movil = box.get('movil') ?? '';
        String username = box.get('username') ?? '';
        String deviceId = box.get('deviceId') ?? '';

        final locationService = LocationService();
        var locationBox = await openBoxSafe('locationBox');
        if (locationBox == null) return;

        // Get location and speed data once for all messages
        final locationData = await locationService.getCurrentLocation();
        double velocidad = double.parse(
            locationBox.get('lastSpeed', defaultValue: 0.0).toStringAsFixed(2));
        double distanciaRecorrida =
            locationBox.get('totalDistance', defaultValue: 0.0);

        // Process each new message
        for (var message in newMessages) {
          try {
            final numericIdMatch = RegExp(r'\d+').firstMatch(message.id);
            if (numericIdMatch == null) continue;

            int messageId = int.parse(numericIdMatch.group(0)!);

            String latitude = '0.0';
            String longitude = '0.0';
            String utmX = '0.0';
            String utmY = '0.0';

            if (locationData != null) {
              latitude = locationData['latitude'].toString();
              longitude = locationData['longitude'].toString();
              utmX = locationData['utmX'].toString();
              utmY = locationData['utmY'].toString();
            }

            // Call RioGasService in background
            await RioGasService.descargaLecturaMensajes(
                int.parse(escenario),
                int.parse(movil),
                messageId,
                username,
                '',
                deviceId,
                'DESCARGA',
                DateTime.now().toUtc().toIso8601String(),
                '',
                '',
                latitude,
                longitude,
                utmX,
                utmY,
                velocidad,
                distanciaRecorrida);
          } catch (e) {
            print('âŒ Error processing message ${message.id}: $e');
          }
        }
      } catch (e) {
        print('âŒ Error in background message processing: $e');
      }
    });
  }

  void _listenToPendingOrders() {
    // Ya no se agrega manualmente ningÃºn listener aquÃ­. El ValueListenableBuilder en el build() se encarga de reaccionar a los cambios.
    // Si necesitas inicializar datos de Hive, hazlo aquÃ­ una sola vez si es necesario.
  }

  Future<void> _callDescargaLecturaPedidos(
    Map<String, dynamic> pedido,
    int pedidoId,
  ) async {
    String pedidoTpo = pedido['Tipo'] == 'Pedidos' ? 'PEDIDOS' : 'SERVICES';
    String lectDesc = 'DESCARGA';
    String fechaHoraCmbEst = DateTime.now().toUtc().toIso8601String();

    String inAux2 = '';

    final locationService = LocationService();

    // Invoca el mÃ©todo para obtener la ubicaciÃ³n
    final locationData = await locationService.getCurrentLocation();

    if (locationData != null) {
      final latitude = locationData['latitude'];
      final longitude = locationData['longitude'];
      final utmX = locationData['utmX'];
      final utmY = locationData['utmY'];

      print('Latitud: $latitude, Longitud: $longitude');
      print('UTMX: $utmX, UTMY: $utmY');
    } else {
      print('No se pudo obtener la ubicaciÃ³n.');
    }

    String latitud = locationData?['latitude'].toString() ?? '';
    String longitud = locationData?['longitude'].toString() ?? '';

    var box = await openBoxSafe('sessionBox');
    if (box == null) return;
    int escenarioId = int.tryParse(box.get('escenario').toString()) ?? 0;
    String movil = box.get('movil');
    String username = box.get('username');
    String deviceId = box.get('deviceId');
    String inAux1 = movil;

    // Retrieve speed and distance from Hive
    var locationBox = await openBoxSafe('locationBox');
    if (locationBox == null) return;
    double velocidad = double.parse(
        locationBox.get('lastSpeed', defaultValue: 0.0).toStringAsFixed(2));
    double distanciaRecorrida =
        locationBox.get('totalDistance', defaultValue: 0.0);

    await RioGasService.descargaLecturaPedidos(
        escenarioId,
        pedidoId,
        pedidoTpo,
        username,
        'NroSesion', // Replace with actual session number if available
        deviceId,
        lectDesc,
        fechaHoraCmbEst,
        inAux1,
        inAux2,
        latitud,
        longitud,
        locationData?['utmX']?.toString() ?? '',
        locationData?['utmY']?.toString() ?? '',
        velocidad, // velocidad
        distanciaRecorrida // distanciaRecorrida
        );
  }

  // REMOVED: _listenToFirestoreChanges() and _listenToFirestoreChangesWithDelay()
  // These methods were creating duplicate direct Firestore subscriptions
  // Stream management is now handled by the StreamManager singleton

  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'This channel is used for important notifications.',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: false,
      sound: RawResourceAndroidNotificationSound(
        'iphone_notification',
      ), // Archivo en res/raw
      //vibrationPattern: Int64List.fromList([0, 500, 100, 1500]), // VibraciÃ³n prolongada
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
      payload: 'item x',
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void forzarDeslogueoYRedirigir(
    BuildContext context,
    String nomUsuario,
    String movil,
  ) async {
    final mensaje =
        'Se ha conectado el usuario $nomUsuario con el mÃ³vil $movil en otro dispositivo.';
    print(
        '[HOME_SESSION] forzarDeslogueoYRedirigir llamado con nomUsuario: $nomUsuario, movil: $movil');
    print('[HOME_SESSION] Mensaje de deslogueo: $mensaje');

    // ðŸ”¥ EJECUTAR LIMPIEZA INMEDIATAMENTE (antes de mostrar diÃ¡logo o navegar)
    print('[HOME_SESSION] ðŸ§¹ Ejecutando limpieza ANTES de navegar...');
    try {
      await LogoutService.executeLogout(
        isRemoteLogout: true, // Es un logout forzado por otro dispositivo
      );
      print('[HOME_SESSION] âœ… Limpieza completada exitosamente');
    } catch (e) {
      print('[HOME_SESSION] âŒ Error durante limpieza: $e');
      // Continuar con navegaciÃ³n de todas formas
    }

    // Esperar brevemente para permitir que el build actual finalice
    Future.delayed(Duration(milliseconds: 100), () {
      if (!context.mounted) {
        print(
            '[HOME_SESSION] ðŸš« Contexto desmontado. Cancelando navegaciÃ³n.');
        return;
      }

      try {
        Navigator.of(context).pushReplacementNamed('/login', arguments: {
          'forcedLogout': true,
          'mensaje': mensaje,
        });
        print('[HOME_SESSION] Navegando a LoginPage con forcedLogout');
      } catch (e) {
        print('[HOME_SESSION] âŒ Error navegando a LoginPage: $e');
      }
    });
  }

  Widget _showForcedLogoutDialog(
    BuildContext context,
    String nomUsuario,
    String movil,
  ) {
    return AlertDialog(
      title: Text('Deslogueo forzado'),
      content: Text(
        (nomUsuario == 'Desconocido' || movil == 'Desconocido')
            ? 'Se ha terminado su tiempo de sesiÃ³n, por favor ingrese nuevamente.'
            : 'Se ha conectado el usuario $nomUsuario con el mÃ³vil $movil en otro dispositivo.',
      ),
      actions: [
        TextButton(
          onPressed: () async {
            if (Hive.isBoxOpen('sessionBox')) {
              var box = Hive.box('sessionBox');
              String? deviceId = box.get('deviceId');
              String? idUsuario = box.get('username');
              await RioGasService.registrarCierre(
                int.tryParse(movil ?? '0') ?? 0,
                deviceId ?? '',
                idUsuario ?? '',
                DateTime.now().toIso8601String(),
                'DeslogueoForzado',
              );
              await box.clear();
              await Hive.openBox(
                'mensajesBox',
              ).then((box) => box.clear()); // Clear mensajesBox

              // ðŸ†• Detener sistema de logging remoto
              try {
                await DebugConfigManager.stopListening();
                print('âœ… [DEBUG_CONFIG] Sistema de logging remoto detenido');
              } catch (e) {
                print(
                    'âš ï¸ [DEBUG_CONFIG] Error deteniendo logging remoto: $e');
              }

              // Cancel all active streams and listeners
              _ordersSubscription?.cancel();
              _locationSubscription?.cancel();
              _gpsSubscription?.cancel();
              _connectivitySubscription?.cancel();
              _connectivityCheckTimer.cancel();

              box.deleteFromDisk();
              // Navigate to HomePage after clearing sessionBox
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => LoginPage()),
              );
            }
          },
          child: Text('Aceptar'),
        ),
      ],
    );
  }

  Future<void> _checkInternetConnectivity() async {
    // print('ðŸ” Verificando conectividad a Internet...');
    var conexionBox = await Hive.openBox('conexionBox');
    var connectivityResult =
        await InternetConnectionChecker.createInstance().hasConnection;

    if (!connectivityResult) {
      // print('âŒ No hay conexiÃ³n a Internet.');
      await conexionBox.put('network', false);
      final mostrarDesconexion = await getConstantValue('230');
      if (mostrarDesconexion != null && mostrarDesconexion == 'S') {
        if (!showPopup) _showNoInternetDialog(); // entra a modo "bloqueo"
      }
    } else {
      // print('âœ… ConexiÃ³n a Internet disponible.');
      await conexionBox.put('network', true);
      showPopup = false;
    }
  }

  void _showNoInternetDialog() {
    if (_isDialogVisible) return; // Prevent showing multiple dialogs

    _isDialogVisible = true; // Set the flag to true

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final sinConexString = await getConstantValue('220');
      showDialog(
        context: navigatorKey.currentContext!,
        barrierDismissible: false, // No puede cerrarse tocando fuera del dialog
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Sin ConexiÃ³n a Internet'),
            content: Text(
              sinConexString ??
                  'No tienes conexiÃ³n a Internet. Por favor, verifica tu conexiÃ³n.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop(); // Cierra el diÃ¡logo actual
                  _isDialogVisible = false; // Reset the flag
                  showPopup = true;
                },
                child: Text('Confirmar'),
              ),
            ],
          );
        },
      );
    });
  }

  Future<void> _retryInternetConnectivity() async {
    // print('ðŸ” Reintento de conexiÃ³n iniciado...');
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none ||
        (connectivityResult is List &&
            connectivityResult.contains(ConnectivityResult.none))) {
      // print('ðŸš« AÃºn sin conexiÃ³n. Mostrando diÃ¡logo nuevamente.');
      final mostrarDesconexion = await getConstantValue('230');
      if (mostrarDesconexion != null && mostrarDesconexion == 'S') {
        _showNoInternetDialog(); // vuelve a mostrar el diÃ¡logo si sigue sin internet
      }
    } else {
      // print('âœ… ConexiÃ³n restaurada.');
      // AquÃ­ podÃ©s continuar con el flujo normal de tu app
    }
  }

  void _checkConnectivityAndPerformAction() async {
    // print('ðŸ”„ Checking connectivity...');
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      // print('âŒ No connectivity detected. Performing fallback action...');
      // Placeholder for future action when no connectivity is detected
    } else {
      // print('âœ… Connectivity available.');
      // Placeholder for future action when connectivity is available
    }
  }

  Future<void> _markMessageAsRead(String messageId) async {
    var mensajesBox = await openBoxSafe('mensajesBox');
    if (mensajesBox == null) return;
    await mensajesBox.put(messageId, 'Leido'); // Mark as read
    // print('ðŸ“¨ Mensaje $messageId marcado como "Leido" en Hive.');
  }

  void _showRioGasConnectivityModal() {
    // print('âš ï¸ Showing RioGas connectivity modal...');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Conectividad con RioGas'),
          content: Text(
            'Actualmente no hay conectividad con RioGas. Por favor, verifica tu conexiÃ³n.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Aceptar'),
            ),
          ],
        );
      },
    );
  }

  Color _getAntennaColor(Map<String, dynamic> connectionStatus) {
    if (!connectionStatus['network']) {
      return Colors.grey;
    }
    if (!connectionStatus['firestore'] && !connectionStatus['riogas']) {
      return Colors.red;
    }
    if (!connectionStatus['firestore'] || !connectionStatus['riogas']) {
      return Colors.yellow;
    }
    return Colors.green;
  }

  Future<void> _updateConnectionStatus(Map<String, dynamic> status) async {
    // Log the incoming status for debugging
    print('ðŸ”„ Actualizando estado de conexiÃ³n: $status');

    //String? token = await FirebaseMessaging.instance.getToken();
    //print('token: $token');
    // Only update the notifier if the status has changed
    if (_connectionStatusNotifier.value['network'] != status['network'] ||
        _connectionStatusNotifier.value['firestore'] != status['firestore'] ||
        _connectionStatusNotifier.value['riogas'] != status['riogas']) {
      print('ðŸ”” Cambio detectado en el estado de conexiÃ³n. Actualizando...');
      _connectionStatusNotifier.value = status;
    } else {
      print('âœ… No hay cambios en el estado de conexiÃ³n.');
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    // ðŸš¨ BLOQUEO TOTAL: Si estamos verificando sesiÃ³n, mostrar solo loader
    if (_isVerifyingSession) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              SizedBox(height: 20),
              Text(
                'Verificando sesiÃ³n...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // âœ… SesiÃ³n verificada - Mostrar UI normal
    // 🏪 Modo restringido (comercio 9998): shell dedicado de Promociones.
    // Va ANTES del toggle de diseño a propósito: la preferencia V2/clásico
    // vive en usuarioBox y sobrevive al logout, así que un dispositivo puede
    // llegar en shell clásico y le mostraría Pedidos y Mapa al comercio.
    // Va DESPUÉS del loader de _isVerifyingSession, también a propósito: si
    // se pusiera arriba, el comercio saltearía la verificación de sesión.
    if (ModoRestringido.activo.value) {
      return const PromosShell();
    }

    // 🎨 Toggle de diseño: nuevo (Home V2) o clásico, conmutable en runtime
    return ValueListenableBuilder<bool>(
      valueListenable: UiPrefs.homeV2,
      builder: (context, isV2, _) {
        // Con el rediseño apagado va SIEMPRE el clásico, sin mirar la
        // preferencia guardada ni el ambiente. Cuando se prenda, vuelve la
        // regla de antes: en producción no se ofrece el clásico (ni aparece
        // el switch en Configuración), así que tampoco se respeta lo
        // guardado — si no, alguien que lo apagó en desarrollo quedaría
        // atrapado ahí.
        if (UiPrefs.disenoNuevoHabilitado &&
            (isV2 || !AppEnvironment.isDevelopment)) {
          return HomeV2Scaffold(
            messageCountNotifier: _messageCountNotifier,
            onEstadoTap: _handleEstadoTapV2,
          );
        }
        return _buildLegacyScaffold(context);
      },
    );
  }

  // 🧱 Diseño clásico (pre-rediseño 2026), intacto
  Widget _buildLegacyScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 🎨 Navbar nuevo (V2) también en el diseño clásico.
          //
          // Promos NO lleva el del shell: PromocionesPage dibuja el suyo (el
          // scaffold V2 no pone ninguno, cada solapa trae el propio) y acá
          // quedaban los dos apilados.
          if (_legacyIndex != 2)
            V2Header(
              messageCountNotifier: _messageCountNotifier,
              onEstadoTap: _handleEstadoTapV2,
              height: 112,
              bottomSpace: 12,
            ),
          Expanded(child: _buildLegacyBody()),
        ],
      ),
      bottomNavigationBar: _buildLegacyBottomNavV2(),
    );
  }

  /// Índice acotado a los 3 tabs del clásico (Pedidos/Mapa/Promos); mensajes
  /// y configuración viven ahora en el navbar superior
  int get _legacyIndex => _selectedIndex > 2 ? 0 : _selectedIndex;

  /// Promociones en el diseño clásico. El shell clásico monta UNA solapa por
  /// vez (a diferencia del `IndexedStack` de V2), así que trae su propio
  /// navbar y pide el anti-captura solo mientras está a la vista.
  late final Widget _promosTabLegacy = PromocionesPage(
    messageCountNotifier: _messageCountNotifier,
    onEstadoTap: _handleEstadoTapV2,
  );

  Widget _legacyTab() {
    if (_legacyIndex == 2) return _promosTabLegacy;
    return _widgetOptions.elementAt(_legacyIndex);
  }

  Widget _buildLegacyBody() {
    return Hive.isBoxOpen('sessionBox')
        ? ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: _streamManager.sesionesNotifier,
            builder: (context, data, _) {
              return _legacyTab();
            },
          )
        : FutureBuilder(
            future: Hive.openBox('sessionBox'),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Center(child: CircularProgressIndicator());
              }
              return ValueListenableBuilder<Map<String, dynamic>?>(
                valueListenable: _streamManager.sesionesNotifier,
                builder: (context, data, _) {
                  return _legacyTab();
                },
              );
            },
          );
  }

  Widget _buildLegacyBottomNavV2() {
    return ValueListenableBuilder<int>(
      valueListenable: _pendingOrdersCountNotifier,
      builder: (context, pendingOrdersCount, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color(0xFF0D2B4E).withOpacity(0.10),
                blurRadius: 16,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: BottomNavigationBar(
            items: [
              _navItemV2(Icons.local_shipping_outlined, Icons.local_shipping,
                  'Pedidos', pendingOrdersCount),
              _navItemV2(Icons.map_outlined, Icons.map, 'Mapa', 0),
              _navItemV2(Icons.card_giftcard_outlined, Icons.card_giftcard,
                  'Promos', 0),
            ],
            currentIndex: _legacyIndex,
            onTap: _onItemTapped,
            backgroundColor: Colors.white,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: Color(0xFF1E88E5),
            unselectedItemColor: Color(0xFF5A7184),
            selectedLabelStyle:
                TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5),
            unselectedLabelStyle:
                TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
            showUnselectedLabels: true,
          ),
        );
      },
    );
  }

  BottomNavigationBarItem _navItemV2(
      IconData icon, IconData activeIcon, String label, int badge) {
    Widget conBadge(Widget child) {
      if (badge <= 0) return child;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            right: -8,
            top: -4,
            child: Container(
              padding: EdgeInsets.all(3.5),
              decoration: BoxDecoration(
                color: Color(0xFFE53935),
                shape: BoxShape.circle,
              ),
              constraints: BoxConstraints(minWidth: 17, minHeight: 17),
              child: Text(
                '$badge',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return BottomNavigationBarItem(
      icon: conBadge(Icon(icon, size: 24)),
      activeIcon: conBadge(Icon(activeIcon, size: 24)),
      label: label,
    );
  }

  // 🗄️ Scaffold clásico ANTERIOR (AppBar con chip + 4 tabs). Ya no se usa:
  // el navbar V2 y el menú de 2 tabs lo reemplazan. Se conserva de referencia.
  // ignore: unused_element
  Widget _buildLegacyScaffoldAnterior(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '',
          style: TextStyle(fontSize: 14.0), // Reduced font size
        ),
        toolbarHeight:
            64.0, // ðŸ†• Aumentado de 40 a 64 para mejor visualizaciÃ³n del chip
        backgroundColor: Colors.lightBlueAccent,
        actions: [
          // 🔇 ICONO DE ANTENA OCULTO (antiguamente mostraba conectividades)
          // Padding(
          //   padding: const EdgeInsets.all(8.0),
          //   child: GestureDetector(
          //     onTap: () => _showConnectivityDialog(context),
          //     child: ValueListenableBuilder<Map<String, dynamic>>(
          //       valueListenable: _connectionStatusNotifier,
          //       builder: (context, connectionStatus, child) {
          //         Color antennaColor = _getAntennaColor(connectionStatus);
          //         bool shouldBlink = !connectionStatus['network'] ||
          //             !connectionStatus['firestore'] ||
          //             !connectionStatus['riogas'];
          //         return Stack(
          //           children: [
          //             AnimatedBuilder(
          //               animation: _blinkController,
          //               builder: (context, child) {
          //                 return Opacity(
          //                   opacity: shouldBlink
          //                       ? (_blinkController.value > 0.5 ? 1.0 : 0.0)
          //                       : 1.0,
          //                   child: Icon(
          //                     Icons.network_cell,
          //                     color: antennaColor,
          //                   ),
          //                 );
          //               },
          //             ),
          //           ],
          //         );
          //       },
          //     ),
          //   ),
          // ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ValueListenableBuilder<DocumentSnapshot?>(
              valueListenable: _streamManager.movilNotifier,
              builder: (context, movilSnapshot, child) {
                if (movilSnapshot == null) {
                  return Center(child: CircularProgressIndicator());
                }
                try {
                  var movilData = movilSnapshot.data() as Map<String, dynamic>;
                  int estadoNro = movilData['EstadoNro'];
                  return ValueListenableBuilder<List<Map<String, dynamic>>>(
                    valueListenable: _streamManager.subEstadoMovilesNotifier,
                    builder: (context, subEstados, child) {
                      if (subEstados.isEmpty) {
                        return Center(child: CircularProgressIndicator());
                      }
                      var subEstado = subEstados.firstWhere(
                        (element) =>
                            int.tryParse(element['SubEstadoCod'].toString()) ==
                            estadoNro,
                        orElse: () => {
                          'SubEstadoDesc': 'Desconocido',
                          'CodColor': '000000',
                        },
                      );
                      String estadoText = subEstado['SubEstadoDesc'];
                      String codColor = subEstado['CodColor'];
                      List<String> rgb = codColor.split(',');
                      String hexColor = rgb.length == 3
                          ? rgb
                              .map(
                                (c) => int.parse(
                                  c,
                                ).toRadixString(16).padLeft(2, '0'),
                              )
                              .join()
                          : '000000';
                      Color estadoColor = Color(int.parse('0xff$hexColor'));

                      // ðŸ”’ Verificar si estÃ¡ en cooldown
                      bool isInCooldown = _lastEstadoChangeAttempt != null;
                      int cooldownRemaining = 0;

                      if (isInCooldown) {
                        final elapsed = DateTime.now()
                            .difference(_lastEstadoChangeAttempt!);
                        cooldownRemaining =
                            _estadoCooldownSeconds - elapsed.inSeconds;
                        if (cooldownRemaining < 0) cooldownRemaining = 0;
                      }

                      return GestureDetector(
                        onTap: isInCooldown
                            ? () {
                                // ðŸš« Mostrar warning cuando estÃ¡ en cooldown
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Debe esperar $cooldownRemaining segundos para cambiar el estado nuevamente',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    backgroundColor: Colors.orange,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            : () {
                                _handleEstadoClick(
                                  context,
                                  _movil,
                                  movilData,
                                  subEstados,
                                );
                              },
                        child: Opacity(
                          opacity: isInCooldown ? 0.5 : 1.0,
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6), // ðŸ†• Aumentado padding
                                decoration: BoxDecoration(
                                  color:
                                      isInCooldown ? Colors.grey : estadoColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: isInCooldown
                                      ? Border.all(color: Colors.red, width: 2)
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Movil:$_movil - ${isInCooldown ? "ðŸ”’" : estadoText}',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        decoration: isInCooldown
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                    if (isInCooldown) ...[
                                      SizedBox(width: 6),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${cooldownRemaining}s',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                } catch (e) {
                  return Text('Error al cargar el estado del mÃ³vil.');
                }
              },
            ),
          ),
        ],
      ),
      body: Hive.isBoxOpen('sessionBox')
          ? ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: _streamManager.sesionesNotifier,
              builder: (context, data, _) {
                // ðŸ”¹ SIMPLIFICADO: Solo mostrar UI, el deslogueo forzado se maneja por FCM
                print('[HOME_SESSION] (LIVE) Data de sesionesNotifier: $data');

                // â„¹ï¸ El listener del stream de sesiones estÃ¡ activo pero NO dispara logout automÃ¡tico
                // El logout forzado se maneja exclusivamente por FCM en firebase_messaging_handler.dart

                return _widgetOptions.elementAt(_selectedIndex);
              },
            )
          : FutureBuilder(
              future: Hive.openBox('sessionBox'),
              builder: (context, snapshot) {
                print('[HOME_SESSION] future: Hive.openBox(sessionBox)');
                if (!snapshot.hasData) {
                  print(
                      '[HOME_SESSION] No hay datos en snapshot, mostrando loader');
                  return Center(child: CircularProgressIndicator());
                }

                return ValueListenableBuilder<Map<String, dynamic>?>(
                  valueListenable: _streamManager.sesionesNotifier,
                  builder: (context, data, _) {
                    // ðŸ”¹ SIMPLIFICADO: Solo mostrar UI, el deslogueo forzado se maneja por FCM
                    print(
                        '[HOME_SESSION] (POST-FUTURE) Data de sesionesNotifier: $data');

                    // â„¹ï¸ El listener del stream de sesiones estÃ¡ activo pero NO dispara logout automÃ¡tico
                    // El logout forzado se maneja exclusivamente por FCM en firebase_messaging_handler.dart

                    return _widgetOptions.elementAt(_selectedIndex);
                  },
                );
              },
            ),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: _pendingOrdersCountNotifier,
        builder: (context, pendingOrdersCount, child) {
          return ValueListenableBuilder<int>(
            valueListenable: _messageCountNotifier,
            builder: (context, messageCount, child) {
              return BottomNavigationBar(
                items: [
                  _buildBottomNavigationBarItem(
                      Icons.list, 'Pendientes', pendingOrdersCount),
                  //_buildBottomNavigationBarItem(Icons.check_circle, 'Finalizados', 0),
                  _buildBottomNavigationBarItem(Icons.map, 'Mapa', 0),
                  _buildBottomNavigationBarItem(
                    Icons.message,
                    'Mensajes',
                    messageCount, // ðŸ”¹ Use ValueNotifier value instead of _unreadMessages
                  ),
                  _buildBottomNavigationBarItem(
                      Icons.settings, 'Configuración', 0),
                ],
                currentIndex: _selectedIndex,
                selectedItemColor: Colors.blue,
                unselectedItemColor: Colors.grey,
                onTap: _onItemTapped,
                backgroundColor: Colors.white,
                type: BottomNavigationBarType.fixed,
                elevation: 10,
                selectedLabelStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
                unselectedLabelStyle: TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 10,
                ),
                showSelectedLabels: true,
                showUnselectedLabels: false,
              );
            },
          );
        },
      ),
    );
  }

  BottomNavigationBarItem _buildBottomNavigationBarItem(
    IconData icon,
    String label,
    int badgeCount,
  ) {
    return BottomNavigationBarItem(
      icon: Stack(
        children: [
          Icon(icon, size: 20),
          if (badgeCount > 0)
            Positioned(right: 0, child: _buildBadge(badgeCount)),
        ],
      ),
      label: label,
    );
  }

  Future<Map<String, String>> obtenerUsuarioLogueadoActual() async {
    const tag = '[ðŸ” OBTENER_USUARIO_LOGUEADO_ACTUAL]';
    const int maxReintentos = 3;
    const Duration esperaEntreIntentos = Duration(seconds: 2);

    try {
      print(
          '$tag ðŸŸ¢ INICIO del proceso de obtenciÃ³n de usuario logueado actual');

      final box = await openBoxSafe('sessionBox');
      if (box == null) {
        print('$tag âŒ No se pudo abrir la caja Hive: sessionBox');
        return {
          'nomUsuario': 'Desconocido',
          'movil': 'Desconocido',
        };
      }

      final movilActual = box.get('movil', defaultValue: '0').toString();
      final escenarioId = box.get('escenario', defaultValue: '0').toString();
      final username = box.get('username', defaultValue: '0').toString();

      print('$tag ðŸ“¦ Datos leÃ­dos desde Hive:');
      print('$tag    - movil: $movilActual');
      print('$tag    - escenarioId: $escenarioId');
      print('$tag    - username: $username');

      final collectionName = 'sessions-$escenarioId';
      final now = DateTime.now();
      final fechaActual =
          now.toIso8601String().split('T')[0].replaceAll('-', '');
      final activeSessionsRef = FirebaseFirestore.instance
          .collection(collectionName)
          .doc(fechaActual)
          .collection('activeSessions');

      print('$tag ðŸ“‚ ColecciÃ³n: $collectionName');
      print('$tag ðŸ“… Fecha actual formateada: $fechaActual');
      print(
          '$tag ðŸ“¡ Consultando Firestore: $collectionName/$fechaActual/activeSessions');

      for (int intento = 1; intento <= maxReintentos; intento++) {
        print('$tag ðŸ” Intento $intento de $maxReintentos');

        final querySnapshot = await activeSessionsRef.get(
          const GetOptions(source: Source.server),
        );

        print(
            '$tag ðŸ”„ Documentos encontrados en activeSessions: ${querySnapshot.docs.length}');

        for (final doc in querySnapshot.docs) {
          final data = doc.data();
          final docId = doc.id;
          final docMovil = data['movil']?.toString() ?? 'null';

          print('$tag    âž¤ Documento ID: $docId');
          print('$tag       - movil: $docMovil');

          if (docMovil == movilActual) {
            print('$tag âœ… Documento coincidente encontrado: $docId');
            print('$tag    â†ªï¸ nomUsuario: ${data['nomUsuario'] ?? 'null'}');
            return {
              'nomUsuario': data['nomUsuario']?.toString() ?? 'Desconocido',
              'movil': data['movil']?.toString() ?? 'Desconocido',
            };
          }
        }

        if (intento < maxReintentos) {
          print(
              '$tag â³ Documento no encontrado aÃºn. Esperando ${esperaEntreIntentos.inSeconds}s antes de reintentar...');
          await Future.delayed(esperaEntreIntentos);
        }
      }

      print(
          '$tag âš ï¸ No se encontrÃ³ ningÃºn documento con mÃ³vil = $movilActual luego de $maxReintentos intentos');
      return {
        'nomUsuario': 'Desconocido',
        'movil': movilActual,
      };
    } catch (e, st) {
      print('$tag âŒ Error inesperado al obtener usuario logueado: $e');
      print('$tag ðŸ§µ StackTrace:\n$st');
      return {
        'nomUsuario': 'Desconocido',
        'movil': 'Desconocido',
      };
    }
  }

  Widget _buildBadge(int count) {
    return Container(
      padding: EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(6),
      ),
      constraints: BoxConstraints(minWidth: 12, minHeight: 12),
      child: Text(
        '$count',
        style: TextStyle(color: Colors.white, fontSize: 8),
        textAlign: TextAlign.center,
      ),
    );
  }

  void _showEstadoDropdown(
    BuildContext context,
    String movilId,
    int currentEstado,
    List<Map<String, dynamic>> subEstados,
  ) {
    String? selectedEstadoDesc;
    String observacion = '';
    bool permiteObservacion = false;

    String currentEstadoDesc = subEstados.firstWhere(
      (element) =>
          int.tryParse(element['SubEstadoCod'].toString()) == currentEstado,
      orElse: () => {'TipoEstado': 'Desconocido'},
    )['TipoEstado'];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Cambiar Estado'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    value: selectedEstadoDesc,
                    hint: Text('Selecciona un estado'),
                    isExpanded: true,
                    items: subEstados
                        .where(
                      (subEstado) =>
                          subEstado['VisibleEnCombo'] == true &&
                          subEstado['TipoEstado'] != currentEstadoDesc,
                    )
                        .map((subEstado) {
                      return DropdownMenuItem<String>(
                        value: subEstado['SubEstadoDesc'] as String,
                        child: Text(subEstado['SubEstadoDesc'] as String),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        selectedEstadoDesc = newValue;

                        final subEstado = subEstados.firstWhere(
                          (s) => s['SubEstadoDesc'] == newValue,
                          orElse: () => {},
                        );
                        permiteObservacion = subEstado['PermiteObs'] == true;
                      });
                    },
                  ),
                  if (permiteObservacion)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: TextField(
                        onChanged: (value) {
                          observacion = value;
                        },
                        //limitar cantidad de caracteres a 100
                        maxLength: 100,
                        maxLines: 3,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'ObservaciÃ³n',
                          hintText:
                              'Ingrese una observaciÃ³n (mÃ­n. 5 caracteres)',
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancelar'),
                ),
                TextButton(
                  onPressed: _isEstadoChanging
                      ? null
                      : () async {
                          if (selectedEstadoDesc != null) {
                            // 1ï¸âƒ£ VERIFICAR COOLDOWN
                            if (_lastEstadoChangeAttempt != null) {
                              final elapsed = DateTime.now()
                                  .difference(_lastEstadoChangeAttempt!);
                              if (elapsed.inSeconds < _estadoCooldownSeconds) {
                                final remaining =
                                    _estadoCooldownSeconds - elapsed.inSeconds;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Debe esperar $remaining segundos para reintentar cambiar el estado',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    backgroundColor: Colors.orange,
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                                return;
                              }
                            }

                            // 2ï¸âƒ£ VALIDAR OBSERVACIÃ“N
                            if (permiteObservacion &&
                                observacion.trim().length < 5) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'La observación debe tener al menos 5 caracteres.',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              );
                              return;
                            }

                            // 3ï¸âƒ£ CALCULAR NUEVO ESTADO
                            final selectedSubEstado = subEstados.firstWhere(
                              (s) => s['SubEstadoDesc'] == selectedEstadoDesc,
                              orElse: () => {'SubEstadoCod': currentEstado},
                            );
                            final newEstadoNro = int.tryParse(
                                    selectedSubEstado['SubEstadoCod']
                                        .toString()) ??
                                currentEstado;

                            // 4ï¸âƒ£ MOSTRAR LOADING
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => AlertDialog(
                                content: Row(
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(width: 16),
                                    Text('Cambiando estado...'),
                                  ],
                                ),
                              ),
                            );

                            setState(() => _isEstadoChanging = true);

                            // 5ï¸âƒ£ OBTENER DATOS DE UBICACIÃ“N
                            // 🛡️ try: ninguna excepción (GPS/parse/red) debe
                            // dejar colgado el diálogo "Cambiando estado..." ni
                            // _isEstadoChanging trabado en true.
                            try {
                            var locationBox = await openBoxSafe('locationBox');
                            if (locationBox == null) {
                              Navigator.of(context, rootNavigator: true).pop();
                              setState(() => _isEstadoChanging = false);
                              return;
                            }

                            double velocidad = double.parse(locationBox
                                .get('lastSpeed', defaultValue: 0.0)
                                .toStringAsFixed(2));
                            double distanciaRecorrida = locationBox
                                .get('totalDistance', defaultValue: 0.0);

                            String latitude = '0.0';
                            String longitude = '0.0';
                            String utmX = '0.0';
                            String utmY = '0.0';

                            final locationData =
                                await _locationService.getCurrentLocation();

                            if (locationData != null) {
                              latitude = locationData['latitude'].toString();
                              longitude = locationData['longitude'].toString();
                              utmX = locationData['utmX'].toString();
                              utmY = locationData['utmY'].toString();
                            }

                            // 6ï¸âƒ£ LLAMAR A RIOGAS PRIMERO âœ…
                            final result =
                                await RioGasService.actualizarMoviles(
                              int.parse(await Hive.box('sessionBox')
                                  .get('escenario', defaultValue: '0')),
                              // 🐛 FIX: movilId es el ID del documento
                              // ("Moviles-336"), no un número → int.parse lo
                              // reventaba con FormatException y colgaba el
                              // diálogo de carga. Extraemos solo los dígitos.
                              int.parse(
                                  movilId.replaceAll(RegExp(r'[^0-9]'), '')),
                              await Hive.box('sessionBox')
                                  .get('username', defaultValue: ''),
                              '',
                              await Hive.box('sessionBox')
                                  .get('deviceId', defaultValue: ''),
                              newEstadoNro.toString(),
                              latitude,
                              longitude,
                              utmX,
                              utmY,
                              DateTime.now().toUtc().toIso8601String(),
                              '', // inAux1
                              observacion, // âœ… Se pasa aquÃ­ la observaciÃ³n
                              velocidad,
                              distanciaRecorrida,
                            );

                            // 7ï¸âƒ£ VALIDAR RESULTADO Y ACTUALIZAR FIRESTORE CONDICIONALMENTE
                            if (result != null && result['error'] == null) {
                              // âœ… Ã‰XITO: Actualizar Firestore
                              await _firebaseService
                                  .updateMovilEstado(newEstadoNro);

                              setState(() {
                                _isEstadoChanging = false;
                                _lastEstadoChangeAttempt =
                                    null; // Reset cooldown
                              });

                              Navigator.of(context, rootNavigator: true).pop();
                              Navigator.of(context).pop();

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '✅ Estado actualizado correctamente',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            } else {
                              // âŒ ERROR: NO actualizar Firestore, iniciar cooldown
                              setState(() {
                                _isEstadoChanging = false;
                                _lastEstadoChangeAttempt = DateTime.now();
                              });

                              // ðŸ†• Iniciar timer de cooldown para actualizar UI cada segundo
                              _startEstadoCooldownTimer();

                              // âŒ Cerrar TODOS los diÃ¡logos (loading + selecciÃ³n de estado)
                              Navigator.of(context, rootNavigator: true)
                                  .pop(); // Cierra loading
                              Navigator.of(context)
                                  .pop(); // Cierra diÃ¡logo de selecciÃ³n

                              final errorMsg = result?['error']?.toString() ??
                                  'Error desconocido';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '❌ Error al actualizar estado: $errorMsg\n⏳ El botón de estado estará deshabilitado por $_estadoCooldownSeconds segundos',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  backgroundColor: Colors.red,
                                  duration: Duration(seconds: 5),
                                ),
                              );
                            }
                            } catch (e, st) {
                              print('❌ [ESTADO] Excepción no manejada: $e');
                              if (mounted) {
                                setState(() => _isEstadoChanging = false);
                              }
                              // Cerrar loading + selección si siguen abiertos
                              try {
                                Navigator.of(context, rootNavigator: true).pop();
                              } catch (_) {}
                              try {
                                Navigator.of(context).pop();
                              } catch (_) {}
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'No se pudo cambiar el estado. Intentá nuevamente.'),
                                    backgroundColor: Colors.red,
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                              }
                            }
                          }
                        },
                  child: Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 🎨 Punto de entrada del cambio de estado desde el diseño nuevo (Home V2).
  /// Aplica el mismo guard de cooldown que el chip clásico y delega en
  /// _handleEstadoClick con los datos actuales del stream manager.
  Future<void> _handleEstadoTapV2(BuildContext context) async {
    // Guard de cooldown (idéntico criterio que el chip del diseño clásico)
    if (_lastEstadoChangeAttempt != null) {
      final elapsed = DateTime.now().difference(_lastEstadoChangeAttempt!);
      final remaining = _estadoCooldownSeconds - elapsed.inSeconds;
      if (remaining > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Debe esperar $remaining segundos para cambiar el estado nuevamente'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
    }
    if (_isEstadoChanging) return;

    final movilSnapshot = _streamManager.movilNotifier.value;
    final subEstados = _streamManager.subEstadoMovilesNotifier.value;
    if (movilSnapshot == null || subEstados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Estado del móvil aún no disponible.')),
      );
      return;
    }

    try {
      final movilData = movilSnapshot.data() as Map<String, dynamic>;
      await _handleEstadoClick(
          context, movilSnapshot.id, movilData, subEstados);
    } catch (e) {
      print('❌ [V2] Error abriendo cambio de estado: $e');
    }
  }

  Future<void> _handleEstadoClick(
    BuildContext context,
    String movilId,
    Map<String, dynamic> movilData,
    List<Map<String, dynamic>> subEstados,
  ) async {
    final puedeActivar = movilData['SePuedeActivarDesdeLaApp'] ?? 'N';
    final puedeDesactivar = movilData['SePuedeDesactivarDesdeLaApp'] ?? 'N';
    final permiteBaja = movilData['PermiteBajaMomentanea'] ?? 'N';
    final estadoActual = movilData['EstadoNro'];

    print('ðŸ” Manejo de estado del mÃ³vil:');
    print('MÃ³vil ID: $movilId');
    print('Estado actual: $estadoActual');

    print('Subestados: $subEstados');

    // Obtener el TipoEstado actual del mÃ³vil
    final subEstadoActual = subEstados.firstWhere(
      (s) => s['SubEstadoCod'].toString() == estadoActual.toString(),
      orElse: () => <String, dynamic>{},
    );
    final tipoEstadoActual = subEstadoActual['TipoEstado'];

    print('TipoEstado actual: $tipoEstadoActual');

    // âœ… Verificar que tipoEstadoActual no sea null o vacÃ­o
    if (tipoEstadoActual == null ||
        tipoEstadoActual.toString().trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No hay acciones disponibles para el estado actual.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    // Filtrar subestados vÃ¡lidos
    final subEstadosValidos = subEstados.where((subEstado) {
      final visible = subEstado['VisibleEnCombo'] ?? true;
      if (!visible) return false;

      final tipoEstado = subEstado['TipoEstado'];
      if (tipoEstado == tipoEstadoActual) return false;

      final requiereActivacion = subEstado['RequierePermActivacion'] ?? 'N';
      final requiereDesactivacion =
          subEstado['RequierePermDesactivacion'] ?? 'N';
      final requiereBaja = subEstado['RequierePermBajaMomentanea'] ?? 'N';

      if (requiereActivacion == 'S' && puedeActivar == 'N') return false;
      if (requiereDesactivacion == 'S' && puedeDesactivar == 'N') return false;
      if (requiereBaja == 'S' && permiteBaja == 'N') return false;

      return true;
    }).toList();

    print('Estado actual: $tipoEstadoActual');
    print('Subestados vÃ¡lidos: $subEstadosValidos');

    if (subEstadosValidos.isNotEmpty) {
      _showEstadoDropdown(
        context,
        movilId,
        estadoActual,
        subEstadosValidos,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No hay acciones disponibles para el estado actual.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  void _showConnectivityDialog(BuildContext context) async {
    var box = await openBoxSafe('conexionBox');
    if (box == null) return;
    box.toMap().forEach((key, value) => null);
    bool conexionFirestore = box.get('conexionFirestore', defaultValue: true);
    bool conexionRioGas = box.get('conexionRioGas', defaultValue: false);
    String lastConnectivityDateFirestore = _formatTime(
      box.get('lastSuccessfulConnection', defaultValue: 'N/A'),
    );
    String lastConnectivityDateRiogas = _formatTime(
      box.get('conexionRioGasTimestamp', defaultValue: 'N/A'),
    );
    var connectivityResult = await Connectivity().checkConnectivity();

    Color firestoreColor = conexionFirestore ? Colors.green : Colors.red;
    Color rioGasColor = conexionRioGas ? Colors.green : Colors.red;

    Color networkColor;
    if (connectivityResult == ConnectivityResult.none ||
        (connectivityResult is List &&
            connectivityResult.contains(ConnectivityResult.none))) {
      networkColor = Colors.grey;
    } else {
      networkColor = Colors.green;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Conectividad'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildConnectivityRow(
                'Nube',
                firestoreColor,
                lastConnectivityDateFirestore,
              ),
              _buildConnectivityRow(
                'RioGas',
                rioGasColor,
                lastConnectivityDateRiogas,
              ),
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: networkColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text('Red'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConnectivityRow(String label, Color color, String date) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 8),
        Text('$label - ult. Hora: $date'),
      ],
    );
  }

  String _formatTime(String dateTimeString) {
    try {
      DateTime dateTime = DateTime.parse(dateTimeString);
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'N/A'; // Return 'N/A' if parsing fails
    }
  }

  Future<bool> _showGpsPermissionDialog() async {
    final bool? granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // ❌ No se puede cerrar tocando fuera
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async =>
              false, // ❌ No permitir cerrar con botón de atrás
          child: AlertDialog(
            title: Row(
              children: [
                Icon(Icons.location_off, color: Colors.red, size: 30),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '📍 Permiso de Ubicación Requerido',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: 'La app ',
                    style: TextStyle(fontSize: 16),
                    children: <TextSpan>[
                      TextSpan(
                        text: 'REQUIERE',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                          fontSize: 16,
                        ),
                      ),
                      TextSpan(
                        text:
                            ' que se habilite el permiso de acceso a la ubicación ',
                        style: TextStyle(fontSize: 16),
                      ),
                      TextSpan(
                        text: 'TODO EL TIEMPO',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                          fontSize: 16,
                        ),
                      ),
                      TextSpan(
                        text: ' para poder funcionar correctamente.',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 15),
                Text(
                  '🚫 Sin este permiso, la aplicación no podrá rastrear tu ubicación en segundo plano.',
                  style: TextStyle(fontSize: 14, color: Colors.red),
                ),
                SizedBox(height: 15),
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📋 Pasos para habilitar:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        '1. Tap en "Abrir Configuración"',
                        style: TextStyle(fontSize: 13),
                      ),
                      Text(
                        '2. Ve a "Permisos" → "Ubicación"',
                        style: TextStyle(fontSize: 13),
                      ),
                      Text(
                        '3. Selecciona "Permitir todo el tiempo"',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton.icon(
                icon: Icon(Icons.settings, color: Colors.white),
                label: Text('Abrir Configuración',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () async {
                  // ❌ NO cerrar el diálogo - mantenerlo abierto

                  // Abrir configuración de la app para permisos
                  await Geolocator.openAppSettings();

                  // Esperar a que el usuario regrese de configuración
                  await Future.delayed(Duration(seconds: 2));

                  // 🔄 Re-verificar permisos en loop hasta que se concedan
                  while (true) {
                    LocationPermission permission =
                        await Geolocator.checkPermission();
                    if (permission == LocationPermission.always) {
                      // ✅ Permiso concedido - cerrar diálogo
                      if (!context.mounted) break;
                      Navigator.of(context).pop(true);
                      break;
                    }
                    if (permission == LocationPermission.whileInUse) {
                      // ✅ Suficiente para el reporte puntual - cerrar diálogo;
                      // solo el tracking background sigue exigiendo "always"
                      print(
                          '[PERMISOS] whileInUse aceptado para reporte puntual; tracking background requiere always');
                      if (!context.mounted) break;
                      Navigator.of(context).pop(true);
                      break;
                    }
                    // ⏳ Esperar 2 segundos y volver a verificar
                    await Future.delayed(Duration(seconds: 2));
                  }
                },
              ),
              TextButton(
                onPressed: () async {
                  final LocationPermission current =
                      await Geolocator.checkPermission();
                  if (current == LocationPermission.always ||
                      current == LocationPermission.whileInUse) {
                    if (!context.mounted) return;
                    Navigator.of(context).pop(true);
                  } else {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Necesitás dar al menos el permiso "mientras se usa" para continuar.'),
                      ),
                    );
                  }
                },
                child: const Text('Continuar con permiso limitado'),
              ),
            ],
          ),
        );
      },
    );
    return granted ?? false;
  }

  /// 🎯 DIÁLOGO DE UBICACIÓN PRECISA (Android 12+)
  Future<bool> _showLocationPrecisionDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false, // ❌ No se puede cerrar tocando fuera
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async =>
              false, // ❌ No permitir cerrar con botón de atrás
          child: AlertDialog(
            title: Row(
              children: [
                Icon(Icons.my_location, color: Colors.orange, size: 30),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '🎯 Ubicación Precisa Requerida',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: 'La app ',
                    style: TextStyle(fontSize: 16),
                    children: <TextSpan>[
                      TextSpan(
                        text: 'REQUIERE',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                          fontSize: 16,
                        ),
                      ),
                      TextSpan(
                        text: ' acceso a ',
                        style: TextStyle(fontSize: 16),
                      ),
                      TextSpan(
                        text: 'UBICACIÓN PRECISA',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                          fontSize: 16,
                        ),
                      ),
                      TextSpan(
                        text: ' para funcionar correctamente.',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 15),
                Text(
                  '⚠️ Actualmente solo tienes "Ubicación aproximada" activada.',
                  style: TextStyle(fontSize: 14, color: Colors.orange),
                ),
                SizedBox(height: 15),
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📋 Pasos para habilitar:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        '1. Tap en "Abrir Configuración"',
                        style: TextStyle(fontSize: 13),
                      ),
                      Text(
                        '2. Ve a "Permisos" → "Ubicación"',
                        style: TextStyle(fontSize: 13),
                      ),
                      Text(
                        '3. Activa "Usar ubicación precisa"',
                        style: TextStyle(fontSize: 13),
                      ),
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.orange, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Ubicación aproximada reduce la precisión del rastreo.',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton.icon(
                icon: Icon(Icons.settings, color: Colors.white),
                label: Text('Abrir Configuración',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () async {
                  // Abrir configuración de la app para permisos
                  await Geolocator.openAppSettings();

                  // Esperar a que el usuario regrese de configuración
                  await Future.delayed(Duration(seconds: 2));

                  // 🔄 Re-verificar precisión en loop hasta que se active
                  while (true) {
                    try {
                      LocationAccuracyStatus accuracyStatus =
                          await Geolocator.getLocationAccuracy();
                      if (accuracyStatus == LocationAccuracyStatus.precise) {
                        // ✅ Ubicación precisa activada - cerrar diálogo
                        Navigator.of(context).pop();
                        break;
                      }
                    } catch (e) {
                      // Si hay error (Android <12), asumir que está OK y cerrar
                      Navigator.of(context).pop();
                      break;
                    }
                    // ⏳ Esperar 2 segundos y volver a verificar
                    await Future.delayed(Duration(seconds: 2));
                  }
                },
              ),
            ],
          ),
        );
      },
    );
    return true; // Retornar true cuando se cierra (significa que se concedió el permiso)
  }
}
