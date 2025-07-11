import 'package:MoveIT/main.dart';
import 'package:flutter/material.dart';
import 'pending_orders.dart';
// import 'pending_orders_debug.dart'; // Commented out - not currently used
import 'completed_orders.dart';
import 'map_page.dart';
import 'settings_page.dart';
import 'message_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'dart:async';
import '../services/session_service.dart';
import '../services/firebase_service.dart';
import '../services/location_service.dart'; // 🔹 Importamos LocationService
import '../services/riogas_service.dart'; // 🔹 Importamos LocationService
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
import 'package:android_intent_plus/android_intent.dart'; // Import AndroidIntent
import 'package:android_intent_plus/flag.dart'; // Import Flag for AndroidIntent
import 'package:flutter/services.dart'; // Import SystemNavigator
import '../utils/stream_manager.dart'; // o el path correcto
import '../services/persistent_stream_manager.dart';

// Función utilitaria para abrir cajas Hive de forma segura
dynamic openBoxSafe(String boxName) async {
  try {
    if (!Hive.isBoxOpen(boxName)) {
      return await Hive.openBox(boxName);
    }
    return Hive.box(boxName);
  } catch (e) {
    print('❌ Error abriendo la caja $boxName: $e');
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
      _locationSubscription; // 🔹 Guardamos la suscripción
  final LocationService _locationService =
      LocationService(); // 🔹 Definimos _locationService
  int _selectedIndex = 0;
  // 🔹 Use ValueNotifier for message counter to avoid UI rebuilds
  late ValueNotifier<int> _messageCountNotifier;
  // 🔹 Use ValueNotifier for pending orders counter
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

  // 🔹 FIX: Create stable stream for session management to prevent child widget rebuilds
  late Stream<Map<String, dynamic>?> _sesionesStream;

  static final List<Widget> _widgetOptions = [
    PendingOrdersPage(), // Back to normal page for testing
    /*CompletedOrdersPage(),*/
    MapPage(),
    MessagePage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    //secureScreen();

    // 🔹 Initialize message counter notifier
    _messageCountNotifier = ValueNotifier<int>(0);
    // 🔹 Initialize pending orders counter notifier
    _pendingOrdersCountNotifier = ValueNotifier<int>(0);

    _blinkController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true); // Blinking effect

    // 🔹 FIX: Initialize stable session stream to prevent child widget rebuilds
    _sesionesStream = _firebaseService.getSesionesStream();

    _initializeHomePage();
    //_initPedidosBoxListener(); // Reemplazado por el nuevo método reactivo
    _setupPedidosBoxReactiveCounter(); // <-- Nuevo método reactivo
    _initMensajesBoxListener(); // Add this to initialize the listener

    // 🔹 Resetear la bandera para futuros chequeos de sesión
    Future.delayed(Duration(seconds: 10), () async {
      var box = await Hive.openBox('sessionBox');
      await box.put('firstLoginDone', false);
      // print(
      //   "🔄 Reset de la bandera firstLoginDone, futuras sesiones serán chequeadas normalmente.",
      // );
    });

    // 🔹 Inicializar el servicio de ubicación
    _initializeLocationService();

    // 🔹 Escuchar cambios en Firestore para pedidos y mensajes
    // REMOVED: _listenToFirestoreChangesWithDelay(); // This was creating duplicate direct Firestore subscriptions
    // The required streams are already handled by _listenToMessages() and _listenToPendingOrders()

    // 🔹 Inicializar la verificación de conectividad
    _checkInternetConnectivity();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      // Handle connectivity changes
    });

    connectivitySubscription =
        _connectivitySubscription; // 🔹 Asignar a la global

    /*// Start the counter for periodic connectivity checks
    _counterService.startCounter(
      intervalSeconds: 10,
      onTick: _checkConnectivityAndPerformAction,
    );*/

    // 🔹 Inicializar la verificación de conectividad periódica
    _connectivityCheckTimer = Timer.periodic(
      Duration(seconds: 90),
      (timer) => _checkInternetConnectivity(),
    );

    connectivityCheckTimer = _connectivityCheckTimer; // 🔹 Asignar a la global

    // Obtener el valor de la constante 200
    //_initializeRetryInterval();

    _initGpsListener();
  }

  Future<void> _initializeRetryInterval() async {
    final retryIntervalString = await getConstantValue('200');
    final retryInterval = int.tryParse(retryIntervalString ?? '');

    print("valor de la constante 200: $retryIntervalString");

    if (retryInterval != null && retryInterval > 0) {
      // Llamar periódicamente a monitorAndSendErrors solo si el valor es válido
      Timer.periodic(Duration(seconds: retryInterval), (timer) async {
        print("Monitor de errores activado.");
        await RioGasService.monitorAndSendErrors();
      });
    } else {
      print(
          "❌ No se pudo iniciar el monitor de errores: valor de la constante 200 no válido.");
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
    _messageCountNotifier.dispose(); // 🔹 Dispose message counter notifier
    _pendingOrdersCountNotifier
        .dispose(); // 🔹 Dispose pending orders counter notifier
    _counterService.stopCounter(); // Stop the counter when disposing
    _ordersSubscription?.cancel();
    _locationServiceCompleter.future.then((_) {
      _locationSubscription?.cancel(); // 🔹 Cancelamos el stream de ubicación
      _locationService
          .stopLocationUpdates(); // 🔹 Detenemos el servicio correctamente
    });
    _connectivitySubscription
        ?.cancel(); // 🔹 Cancelar la suscripción de conectividad
    _connectivityCheckTimer.cancel(); // Cancel the timer when disposing
    _connectionCheck.stopMonitoring();
    _connectionStatusNotifier.dispose(); // Dispose the notifier
    _gpsSubscription?.cancel();
    _gpsStreamController.close();
    super.dispose();
  }

  Future<void> _initializeHomePage() async {
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
  }

  Future<void> _initializeLocationService() async {
    try {
      await _locationService.initializeLocationUpdates(context);
      _locationSubscription =
          _locationService.locationStream.listen((location) {});
      _locationServiceCompleter.complete();

      locationSubscription =
          _locationSubscription; // 🔹 Guardamos la suscripción
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error al inicializar el servicio de ubicación: $e')),
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
        // print("❌ Error al obtener documentos de 'Constantes-1000': $e");
      }
    }
  }

  void _initPedidosBoxListener() async {
    final box = await openBoxSafe('pedidosBox');
    if (box == null) return;
    setState(() {
      pedidosBox = box;
    });
    // 🔹 Initialize pending orders counter from existing data (No Leído)
    int initialCount = _countPedidosNoLeidos(box);
    _pendingOrdersCountNotifier.value = initialCount;

    // 🔹 Listen for changes in pedidosBox and update the notifier
    box.watch().listen((event) {
      int pendingCount = _countPedidosNoLeidos(box);
      _pendingOrdersCountNotifier.value = pendingCount;
    });
    // Ya no es necesario agregar listeners manuales aquí, la lógica de sincronización está centralizada en PersistentStreamManager
  }

// Helper to count pedidos "No Leído" (same logic as PendingOrdersPage)
  int _countPedidosNoLeidos(Box box) {
    int count = 0;
    print('[PEDIDOS] Recorriendo ${box.keys.length} pedidos en pedidosBox...');
    for (var key in box.keys) {
      var pedidoEstado = box.get(key);
      print('[PEDIDOS] Pedido $key → Estado: $pedidoEstado');
      if (pedidoEstado == null || pedidoEstado == 'No Leído') {
        count++;
        print('[PEDIDOS] Pedido $key está sin leer (null o "No Leído")');
      }
    }
    print('[PEDIDOS] Total de pedidos no leídos: $count');
    return count;
  }

  // Refresca el contador de pedidos no leídos basado en los pedidos actuales del stream y su estado en Hive
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
      // Obtén los pedidos actuales del stream manager
      final pedidos = _streamManager.pedidos;
      int count = 0;
      for (var pedido in pedidos) {
        var estado = box.get(pedido.id);
        if (estado == null || estado == 'No Leído') {
          count++;
        }
      }
      print('[PEDIDOS][SMART COUNT] Total de pedidos no leídos: $count');
      _pendingOrdersCountNotifier.value = count;
    }

    // Inicializa el contador con el valor actual
    updatePedidosCount();

    // Escucha cambios en Hive
    box.watch().listen((event) {
      print(
          '[PEDIDOS][WATCH] Evento en pedidosBox: key=${event.key}, value=${event.value}, deleted=${event.deleted}');
      updatePedidosCount();
    });

    // Escucha cambios en el stream de pedidos
    _streamManager.pedidosNotifier.addListener(() {
      updatePedidosCount();
    });
  }

  // Refresca el contador de mensajes no leídos basado en los mensajes actuales del stream y su estado en Hive
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
      print('[MENSAJES][SMART COUNT] Total de mensajes no leídos: $count');
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

    gpsSubscription = _gpsSubscription; // 🔹 Asignar a la global
  }

  void _listenToMessages() async {
    // Ya no se agrega manualmente ningún listener aquí. El ValueListenableBuilder en el build() se encarga de reaccionar a los cambios.
    // Si necesitas inicializar datos de Hive, hazlo aquí una sola vez si es necesario.
    // La lógica de actualización de Hive y procesamiento de mensajes debe estar en PersistentStreamManager o en los listeners de Hive.
    var mensajesBox = await openBoxSafe('mensajesBox');
    if (mensajesBox == null) return;
    // Lógica de inicialización si es necesaria, pero sin listeners manuales.
  }

  // 🔹 Separate method for expensive operations that run in background
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
            print('❌ Error processing message ${message.id}: $e');
          }
        }
      } catch (e) {
        print('❌ Error in background message processing: $e');
      }
    });
  }

  void _listenToPendingOrders() {
    // Ya no se agrega manualmente ningún listener aquí. El ValueListenableBuilder en el build() se encarga de reaccionar a los cambios.
    // Si necesitas inicializar datos de Hive, hazlo aquí una sola vez si es necesario.
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

    // Invoca el método para obtener la ubicación
    final locationData = await locationService.getCurrentLocation();

    if (locationData != null) {
      final latitude = locationData['latitude'];
      final longitude = locationData['longitude'];
      final utmX = locationData['utmX'];
      final utmY = locationData['utmY'];

      print('Latitud: $latitude, Longitud: $longitude');
      print('UTMX: $utmX, UTMY: $utmY');
    } else {
      print('No se pudo obtener la ubicación.');
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
      //vibrationPattern: Int64List.fromList([0, 500, 100, 1500]), // Vibración prolongada
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

  Future<void> forzarDeslogueoYRedirigir(
    BuildContext context,
    String nomUsuario,
    String movil,
  ) async {
    print(
        '\u001b[31m[HOME_SESSION] forzarDeslogueoYRedirigir llamado con nomUsuario: $nomUsuario, movil: $movil\u001b[0m');
    final mensaje = (nomUsuario == 'Desconocido' || movil == 'Desconocido')
        ? 'Se ha terminado su tiempo de sesión, por favor ingrese nuevamente.'
        : 'Se ha conectado el usuario $nomUsuario con el móvil $movil en otro dispositivo.';

    print('\u001b[31m[HOME_SESSION] Mensaje de deslogueo: $mensaje\u001b[0m');
    // Redirigir al LoginPage, pasándole que debe ejecutar cierre forzado
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          print('[HOME_SESSION] Navegando a LoginPage con forcedLogout');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => LoginPage(
                forcedLogout: true,
                forcedLogoutMessage: mensaje,
                movil: movil,
              ),
            ),
          );
        } catch (e, stack) {
          print(
              '\u001b[31m[HOME_SESSION] ❌ Error navegando a LoginPage: $e\n$stack\u001b[0m');
        }
      });
    } catch (e, stack) {
      print(
          '\u001b[31m[HOME_SESSION] ❌ Error en forzarDeslogueoYRedirigir: $e\n$stack\u001b[0m');
    }
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
            ? 'Se ha terminado su tiempo de sesión, por favor ingrese nuevamente.'
            : 'Se ha conectado el usuario $nomUsuario con el móvil $movil en otro dispositivo.',
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
    // print('🔍 Verificando conectividad a Internet...');
    var conexionBox = await Hive.openBox('conexionBox');
    var connectivityResult =
        await InternetConnectionChecker.createInstance().hasConnection;

    if (!connectivityResult) {
      // print('❌ No hay conexión a Internet.');
      await conexionBox.put('network', false);
      final mostrarDesconexion = await getConstantValue('230');
      if (mostrarDesconexion != null && mostrarDesconexion == 'S') {
        if (!showPopup) _showNoInternetDialog(); // entra a modo "bloqueo"
      }
    } else {
      // print('✅ Conexión a Internet disponible.');
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
            title: Text('Sin Conexión a Internet'),
            content: Text(
              sinConexString ??
                  'No tienes conexión a Internet. Por favor, verifica tu conexión.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop(); // Cierra el diálogo actual
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
    // print('🔁 Reintento de conexión iniciado...');
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none ||
        (connectivityResult is List &&
            connectivityResult.contains(ConnectivityResult.none))) {
      // print('🚫 Aún sin conexión. Mostrando diálogo nuevamente.');
      final mostrarDesconexion = await getConstantValue('230');
      if (mostrarDesconexion != null && mostrarDesconexion == 'S') {
        _showNoInternetDialog(); // vuelve a mostrar el diálogo si sigue sin internet
      }
    } else {
      // print('✅ Conexión restaurada.');
      // Aquí podés continuar con el flujo normal de tu app
    }
  }

  void _checkConnectivityAndPerformAction() async {
    // print('🔄 Checking connectivity...');
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      // print('❌ No connectivity detected. Performing fallback action...');
      // Placeholder for future action when no connectivity is detected
    } else {
      // print('✅ Connectivity available.');
      // Placeholder for future action when connectivity is available
    }
  }

  Future<void> _markMessageAsRead(String messageId) async {
    var mensajesBox = await openBoxSafe('mensajesBox');
    if (mensajesBox == null) return;
    await mensajesBox.put(messageId, 'Leido'); // Mark as read
    // print('📨 Mensaje $messageId marcado como "Leido" en Hive.');
  }

  void _showRioGasConnectivityModal() {
    // print('⚠️ Showing RioGas connectivity modal...');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Conectividad con RioGas'),
          content: Text(
            'Actualmente no hay conectividad con RioGas. Por favor, verifica tu conexión.',
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
    print('🔄 Actualizando estado de conexión: $status');

    //String? token = await FirebaseMessaging.instance.getToken();
    //print('token: $token');
    // Only update the notifier if the status has changed
    if (_connectionStatusNotifier.value['network'] != status['network'] ||
        _connectionStatusNotifier.value['firestore'] != status['firestore'] ||
        _connectionStatusNotifier.value['riogas'] != status['riogas']) {
      print('🔔 Cambio detectado en el estado de conexión. Actualizando...');
      _connectionStatusNotifier.value = status;
    } else {
      print('✅ No hay cambios en el estado de conexión.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '',
          style: TextStyle(fontSize: 14.0), // Reduced font size
        ),
        toolbarHeight: 40.0,
        backgroundColor: Colors.lightBlueAccent,
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: GestureDetector(
              onTap: () => _showConnectivityDialog(context),
              child: ValueListenableBuilder<Map<String, dynamic>>(
                valueListenable: _connectionStatusNotifier,
                builder: (context, connectionStatus, child) {
                  Color antennaColor = _getAntennaColor(connectionStatus);
                  bool shouldBlink = !connectionStatus['network'] ||
                      !connectionStatus['firestore'] ||
                      !connectionStatus['riogas'];
                  return Stack(
                    children: [
                      AnimatedBuilder(
                        animation: _blinkController,
                        builder: (context, child) {
                          return Opacity(
                            opacity: shouldBlink
                                ? (_blinkController.value > 0.5 ? 1.0 : 0.0)
                                : 1.0,
                            child: Icon(
                              Icons.network_cell,
                              color: antennaColor,
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
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
                      return GestureDetector(
                        onTap: () {
                          _handleEstadoClick(
                            context,
                            _movil,
                            movilData,
                            subEstados,
                          );
                        },
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: estadoColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Movil:$_movil - $estadoText',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                } catch (e) {
                  return Text('Error al cargar el estado del móvil.');
                }
              },
            ),
          ),
        ],
      ),
      body: FutureBuilder(
        future: Hive.openBox('sessionBox'),
        builder: (context, snapshot) {
          print('[HOME_SESSION] future: Hive.openBox(sessionBox)');
          if (!snapshot.hasData) {
            print('[HOME_SESSION] No hay datos en snapshot, mostrando loader');
            return Center(child: CircularProgressIndicator());
          }

          try {
            var box = Hive.box('sessionBox');
            bool firstLoginDone =
                box.get('firstLoginDone', defaultValue: false);
            bool existeSession = Hive.isBoxOpen('sessionBox');

            print(
                '\u001b[36m[HOME_SESSION] firstLoginDone: $firstLoginDone, existeSession: $existeSession\u001b[0m');

            // ✅ Si es el primer login manual, ignorar completamente el chequeo de sesión activa
            if (firstLoginDone && existeSession) {
              print(
                  '\u001b[32m[HOME_SESSION] Ignorando chequeo de logout forzado en el primer login manual...\u001b[0m');
              return _widgetOptions.elementAt(_selectedIndex);
            } else {
              if (existeSession) {
                print(
                    '[HOME_SESSION] Chequeando logout forzado en Firestore...');
                // ✅ Si no es el primer login, proceder con la validación en Firestore
                return StreamBuilder<Map<String, dynamic>?>(
                  stream:
                      _sesionesStream, // 🔹 FIX: Use stable stream to prevent rebuilds
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      print(
                          '[HOME_SESSION] Esperando datos del stream de Firestore...');
                      return Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      print(
                          '\u001b[31m[HOME_SESSION] Error en el stream: ${snapshot.error}\u001b[0m');
                      return Center(
                          child: Text('Error: [31m${snapshot.error}[0m'));
                    }

                    if (snapshot.hasData) {
                      var data = snapshot.data;
                      print('[HOME_SESSION] Datos recibidos del stream: $data');
                      if (Hive.isBoxOpen('sessionBox')) {
                        var box = Hive.box('sessionBox');
                        if (data != null &&
                            data['idTerminal'] != box.get('deviceId')) {
                          print(
                              '\u001b[31m[HOME_SESSION] idTerminal cambiado, forzando deslogueo\u001b[0m');
                          forzarDeslogueoYRedirigir(
                            context,
                            data['nomUsuario'] ?? 'Desconocido',
                            data['movil'] ?? 'Desconocido',
                          );
                        }
                      }
                    } else {
                      print(
                          '[HOME_SESSION] No hay datos en el snapshot del stream, forzando logout si corresponde');
                      // Si no hay datos en el snapshot, forzar logout
                      if (Hive.isBoxOpen('sessionBox')) {
                        var box = Hive.box('sessionBox');
                        bool logoutControlled =
                            box.get('logoutControlled', defaultValue: false);
                        print(
                            '[HOME_SESSION] logoutControlled: $logoutControlled');
                        if (!logoutControlled) {
                          print(
                              '\u001b[31m[HOME_SESSION] Forzando deslogueo por ausencia de datos en Firestore\u001b[0m');
                          forzarDeslogueoYRedirigir(
                            context,
                            'Desconocido',
                            'Desconocido',
                          );
                        }
                      }
                    }

                    return _widgetOptions.elementAt(_selectedIndex);
                  },
                );
              } else {
                print(
                    '[HOME_SESSION] No existe sessionBox, mostrando widget principal');
                return _widgetOptions.elementAt(_selectedIndex);
              }
            }
          } catch (e) {
            print(
                '\u001b[31m[HOME_SESSION] ❌ Error al abrir la caja sessionBox: $e\u001b[0m');
            return _showForcedLogoutDialog(
                context, 'Desconocido', 'Desconocido');
          }
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
                    messageCount, // 🔹 Use ValueNotifier value instead of _unreadMessages
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
                          labelText: 'Observación',
                          hintText:
                              'Ingrese una observación (mín. 5 caracteres)',
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
                  onPressed: () async {
                    if (selectedEstadoDesc != null) {
                      if (permiteObservacion && observacion.trim().length < 5) {
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

                      // Mostrar loading
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => AlertDialog(
                          content: Row(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(width: 16),
                              Text('Activando'),
                            ],
                          ),
                        ),
                      );

                      final selectedSubEstado = subEstados.firstWhere(
                        (s) => s['SubEstadoDesc'] == selectedEstadoDesc,
                        orElse: () => {'SubEstadoCod': currentEstado},
                      );

                      final newEstadoNro = int.tryParse(
                            selectedSubEstado['SubEstadoCod'].toString(),
                          ) ??
                          currentEstado;

                      await _firebaseService.updateMovilEstado(newEstadoNro);

                      var locationBox = await openBoxSafe('locationBox');
                      if (locationBox == null) return;

                      double velocidad = double.parse(locationBox
                          .get('lastSpeed', defaultValue: 0.0)
                          .toStringAsFixed(2));
                      double distanciaRecorrida =
                          locationBox.get('totalDistance', defaultValue: 0.0);

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

                      final result = await RioGasService.actualizarMoviles(
                        int.parse(await Hive.box('sessionBox')
                            .get('escenario', defaultValue: '0')),
                        int.parse(movilId),
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
                        observacion, // ✅ Se pasa aquí la observación
                        velocidad,
                        distanciaRecorrida,
                      );

                      Navigator.of(context, rootNavigator: true).pop();
                      Navigator.of(context).pop();
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

    print('🔍 Manejo de estado del móvil:');
    print('Móvil ID: $movilId');
    print('Estado actual: $estadoActual');

    print('Subestados: $subEstados');

    // Obtener el TipoEstado actual del móvil
    final subEstadoActual = subEstados.firstWhere(
      (s) => s['SubEstadoCod'].toString() == estadoActual.toString(),
      orElse: () => <String, dynamic>{},
    );
    final tipoEstadoActual = subEstadoActual['TipoEstado'];

    print('TipoEstado actual: $tipoEstadoActual');

    // ✅ Verificar que tipoEstadoActual no sea null o vacío
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

    // Filtrar subestados válidos
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
    print('Subestados válidos: $subEstadosValidos');

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
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Permiso de GPS requerido'),
              content: Text(
                'La aplicación requiere que habilites los permisos de ubicación TODO EL TIEMPO para funcionar correctamente. Por favor, habilítalos.',
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('Cancelar'),
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                ),
                TextButton(
                  child: Text('Continuar'),
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                ),
              ],
            );
          },
        ) ??
        false;
  }
}
