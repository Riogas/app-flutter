import 'package:MoveIT/main.dart';
import 'package:flutter/material.dart';
import 'pending_orders.dart';
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
import '../services/counter_service.dart'; // Import the new CounterService
import '../utils/connection_check.dart';
import '../utils/screenBlock.dart'; // Import secureScreen
import '../utils/constantes.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final FirebaseService _firebaseService = FirebaseService();
  late StreamSubscription<LatLng>
      _locationSubscription; // 🔹 Guardamos la suscripción
  final LocationService _locationService =
      LocationService(); // 🔹 Definimos _locationService
  int _selectedIndex = 0;
  int _unreadMessages = 0;
  int _newOrders = 0;
  bool _constantsLoaded = false;
  late StreamSubscription _ordersSubscription;
  final Completer<void> _locationServiceCompleter = Completer<void>();
  String _movil = '0';
  late StreamSubscription _connectivitySubscription;
  final CounterService _counterService =
      CounterService(); // Initialize CounterService
  late AnimationController _blinkController;
  late Timer _connectivityCheckTimer; // Add a Timer for periodic checks
  final ConnectionCheck _connectionCheck = ConnectionCheck();
  final ValueNotifier<Map<String, dynamic>> _connectionStatusNotifier =
      ValueNotifier({'network': true, 'firestore': true, 'riogas': true});
  bool showPopup = false; // Add a flag for showing the popup
  late Box pedidosBox;
  bool _isFirstLoad = true; // Flag to suppress notifications on first load
  late StreamSubscription<bool> _gpsSubscription;
  final StreamController<bool> _gpsStreamController =
      StreamController<bool>.broadcast();

  static final List<Widget> _widgetOptions = [
    PendingOrdersPage(),
    CompletedOrdersPage(),
    MapPage(),
    MessagePage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    //secureScreen();

    _blinkController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true); // Blinking effect
    _initializeHomePage();
    _initPedidosBoxListener();
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
    _listenToFirestoreChangesWithDelay(); // Usar la nueva función con delay

    // 🔹 Inicializar la verificación de conectividad
    _checkInternetConnectivity();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      // Handle connectivity changes
    });

    // Start the counter for periodic connectivity checks
    _counterService.startCounter(
      intervalSeconds: 10,
      onTick: _checkConnectivityAndPerformAction,
    );

    // 🔹 Inicializar la verificación de conectividad periódica
    _connectivityCheckTimer = Timer.periodic(
      Duration(seconds: 5),
      (timer) => _checkInternetConnectivity(),
    );

    // Obtener el valor de la constante 200
    _initializeRetryInterval();

    _initGpsListener();
  }

  Future<void> _initializeRetryInterval() async {
    final retryIntervalString = await getConstantValue('200');
    final retryInterval = int.tryParse(retryIntervalString ?? '');

    if (retryInterval != null) {
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
      _connectionStatusNotifier.value = status; // Update only the notifier
      if (status['showPopup'] == true) {
        _showRioGasConnectivityModal();
      }
    });
  }

  @override
  void dispose() {
    _blinkController.dispose(); // Dispose the animation controller
    _counterService.stopCounter(); // Stop the counter when disposing
    _ordersSubscription.cancel();
    _locationServiceCompleter.future.then((_) {
      _locationSubscription.cancel(); // 🔹 Cancelamos el stream de ubicación
      _locationService
          .stopLocationUpdates(); // 🔹 Detenemos el servicio correctamente
    });
    _connectivitySubscription
        .cancel(); // 🔹 Cancelar la suscripción de conectividad
    _connectivityCheckTimer.cancel(); // Cancel the timer when disposing
    _connectionCheck.stopMonitoring();
    _connectionStatusNotifier.dispose(); // Dispose the notifier
    _gpsSubscription.cancel();
    _gpsStreamController.close();
    super.dispose();
  }

  Future<void> _initializeHomePage() async {
    await _loadSessionData();
    await RioGasService.initializeService(); //
    var box = await Hive.openBox('sessionBox');
    bool firstLoginDone = box.get('firstLoginDone', defaultValue: false);

    setState(() {
      _isFirstLoad =
          !firstLoginDone; // Set _isFirstLoad based on firstLoginDone
    });

    _listenToMessages();
    _listenToPendingOrders();
    _printConstantDocumentNames();

    // Set the flag to false after the initial load
    setState(() {
      _isFirstLoad = false;
    });
  }

  Future<void> _initializeLocationService() async {
    try {
      await _locationService.initializeLocationUpdates(context);
      _locationSubscription =
          _locationService.locationStream.listen((location) {
        // print('📍 Nueva ubicación recibida en HomePage: $location');
      });
      _locationServiceCompleter.complete();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error al inicializar el servicio de ubicación: $e')),
      );
      _locationServiceCompleter.completeError(e);
    }
  }

  Future<void> _loadSessionData() async {
    var box = await Hive.openBox('sessionBox');
    // print("📦 Contenido de sessionBox:");
    box.toMap().forEach((key, value) => null);
    setState(() {
      _movil = box.get('movil', defaultValue: '0');
    });
  }

  Future<void> _printConstantDocumentNames() async {
    if (!_constantsLoaded) {
      try {
        var box = await Hive.openBox('sessionBox');
        String escenario = box.get('escenario', defaultValue: '1000');
        QuerySnapshot querySnapshot = await FirebaseFirestore.instance
            .collection('Constantes-1000')
            .get();
        // print("📂 Documentos en 'Constantes-$escenario':");
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
    pedidosBox = await Hive.openBox('pedidosBox');

    pedidosBox.watch().listen((BoxEvent event) {
      if (event.key != null) {
        int pedidoId;

        // Si la clave es un int, usamos directamente; si es String, intentamos parsear
        if (event.key is int) {
          pedidoId = event.key as int;
        } else {
          try {
            pedidoId = int.parse(event.key.toString());
          } catch (_) {
            // print('❌ Clave no válida: ${event.key}');
            return;
          }
        }

        String _getPedidoEstado(int pedidoId) {
          var pedidoEstado = pedidosBox.get(pedidoId);
          if (pedidoEstado == null) {
            return 'No Leído';
          } else if (pedidoEstado == 'Procesando') {
            return 'Procesando';
          } else if (pedidoEstado == 'Enviando') {
            return 'Enviando';
          }
          return '';
        }

        String estado = _getPedidoEstado(pedidoId);
        // print('🔔 Cambio en pedido $pedidoId. Nuevo estado: $estado');

        // Podés hacer algo dependiendo del estado
        switch (estado) {
          case 'Procesando':
            // print('📦 Pedido $pedidoId está siendo procesado.');
            _newOrders--;
            break;
          case 'Enviando':
            // print('🚚 Pedido $pedidoId se está enviando.');
            break;
          case 'No Leído':
            // print('🕵️ Pedido $pedidoId aún no ha sido leído.');
            break;
          default:
          // print('⚠️ Estado desconocido para pedido $pedidoId.');
        }
      }
    });
  }

  void _initMensajesBoxListener() async {
    var mensajesBox = await Hive.openBox('mensajesBox');
    mensajesBox.watch().listen((event) {
      setState(() {
        _unreadMessages = mensajesBox.values
            .where((estado) => estado == 'Descargado')
            .length; // Count only 'Descargado' messages
      });
    });
  }

  void _initGpsListener() {
    _gpsSubscription = _gpsSubscription = Geolocator.getServiceStatusStream()
        .map((ServiceStatus status) => status == ServiceStatus.enabled)
        .listen((bool isEnabled) {
      _gpsStreamController.add(isEnabled);
    });
  }

  void _listenToMessages() async {
    var mensajesBox = await Hive.openBox('mensajesBox'); // Open mensajesBox
    _firebaseService.getMensajesStream().listen((messages) async {
      int newMessagesCount = 0;

      // print("📦 Contenido de mensajesBox: ${mensajesBox.toMap()}");

      for (var message in messages) {
        var messageData =
            message.data() as Map<String, dynamic>?; // Extract message data
        if (!mensajesBox.containsKey(message.id) &&
            (messageData == null ||
                messageData['VisibleEnApp'] == null ||
                messageData['VisibleEnApp'] == 'S')) {
          await mensajesBox.put(message.id, 'Descargado'); // Mark as downloaded
          newMessagesCount = mensajesBox.values
              .where((estado) => estado == 'Descargado')
              .length; // Count only 'Descargado' messages

          // Parse message ID as an integer
          final numericIdMatch = RegExp(r'\d+').firstMatch(message.id);
          int messageId = int.parse(numericIdMatch!.group(0)!);

          // Call descargaLecturaMensajes for each new message
          var box = await Hive.openBox('sessionBox');
          String escenario = box.get('escenario', defaultValue: '1000');
          String movil = box.get('movil');
          String username = box.get('username');
          String deviceId = box.get('deviceId');
          Position? position = await _locationService
              .getCurrentLocation(); // Use LocationService's method

          // Retrieve speed and distance from Hive
          var locationBox = await Hive.openBox('locationBox');
          double velocidad = locationBox.get('lastSpeed', defaultValue: 0.0);
          double distanciaRecorrida =
              locationBox.get('totalDistance', defaultValue: 0.0);

          if (position != null) {
            // print('📨 Enviando datos al servicio descargaLecturaMensajes:');
            // print('Latitud: ${position.latitude}');
            // print('Longitud: ${position.longitude}');
            await RioGasService.descargaLecturaMensajes(
                int.parse(escenario), // escenarioId
                int.parse(movil), // movilId
                messageId, // messageId
                username, // usuario
                '', // nroSesion
                deviceId, // termMobileEquipo
                'DESCARGA', // lectDesc
                DateTime.now().toUtc().toIso8601String(), // fechaHoraCmbEst
                '', // inAux1
                '', // inAux2
                position.latitude.toString(), // latitud
                position.longitude.toString(), // longitud
                velocidad, // velocidad
                distanciaRecorrida // distanciaRecorrida
                );
          }
        } else if (messageData != null &&
            messageData['VisibleEnApp'] == 'N' &&
            mensajesBox.containsKey(message.id)) {
          await mensajesBox.put(message.id, 'Leido'); // Mark as read
          // print('📨 Mensaje ${message.id} marcado como "Leido" en Hive.');
        }
      }

      if (newMessagesCount > 0) {
        _showNotification(
          'Nuevo Mensaje',
          'Tienes $newMessagesCount mensajes nuevos.',
        );
      }

      setState(() {
        _unreadMessages = mensajesBox.values
            .where((estado) => estado == 'Descargado')
            .length; // Count only 'Descargado' messages
      });
    });
  }

  void _listenToPendingOrders() {
    _ordersSubscription = _firebaseService.getPedidosStream().listen((
      orders,
    ) async {
      setState(() {
        //_newOrders = orders.length;
        _newOrders = orders.where((order) {
          var orderData = order.data() as Map<String, dynamic>?;
          int pedidoId = orderData?['id'] ?? -1;
          var pedidoEstado = pedidosBox.get(pedidoId);
          return pedidoEstado != 'Procesando';
        }).length;
      });

      for (var order in orders) {
        var pedido = order.data() as Map<String, dynamic>; // Extract data
        int pedidoId = pedido['id'] ?? -1; // Extract ID from the data map

        var pedidosBox = await Hive.openBox('pedidosBox'); // Open pedidosBox

        if (!pedidosBox.containsKey(pedidoId.toString())) {
          await pedidosBox.put(
            pedidoId.toString(),
            'Descargado',
          ); // Mark as "Descargado"

          // Suppress notifications on first load
          _showNotification(
            'Nueva Visita',
            'Tienes un nueva visita pendiente.',
          );

          // Call the download and read routine here
          await _callDescargaLecturaPedidos(pedido, pedidoId);
        }
      }
    });
  }

  Future<void> _callDescargaLecturaPedidos(
    Map<String, dynamic> pedido,
    int pedidoId,
  ) async {
    String pedidoTpo = pedido['Tipo'] == 'Pedidos' ? '1' : '2';
    String lectDesc = 'DESCARGA';
    String fechaHoraCmbEst = DateTime.now().toUtc().toIso8601String();

    String inAux2 = '';

    Position? position;
    try {
      position = await _locationService
          .getCurrentLocation(); // Use LocationService's method
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al obtener la ubicación: $e')),
      );
    }

    if (position == null) {
      // print('⚠️ No se pudo obtener la ubicación. Usando valores por defecto.');
      position = Position(
        latitude: 0.0,
        longitude: 0.0,
        timestamp: DateTime.now(),
        accuracy: 0.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0, // Added required parameter
        heading: 0.0,
        headingAccuracy: 0.0, // Added required parameter
        speed: 0.0,
        speedAccuracy: 0.0,
      );
    }

    String latitud = position.latitude.toString();
    String longitud = position.longitude.toString();

    var box = await Hive.openBox('sessionBox');
    int escenarioId = int.tryParse(box.get('escenario').toString()) ?? 0;
    String movil = box.get('movil');
    String username = box.get('username');
    String deviceId = box.get('deviceId');
    String inAux1 = movil;

    // Retrieve speed and distance from Hive
    var locationBox = await Hive.openBox('locationBox');
    double velocidad = locationBox.get('lastSpeed', defaultValue: 0.0);
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
        velocidad, // velocidad
        distanciaRecorrida // distanciaRecorrida
        );
  }

  void _listenToFirestoreChanges() {
    FirebaseFirestore.instance.collection('Pedidos').snapshots().listen((
      snapshot,
    ) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          _showNotification(
            'Nueva Visita',
            'Tienes un nueva visita pendiente.',
          );
        }
      }
    });

    FirebaseFirestore.instance.collection('Mensajes').snapshots().listen((
      snapshot,
    ) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          _showNotification('Nuevo Mensaje', 'Tienes un nuevo mensaje.');
        }
      }
    });
  }

  void _listenToFirestoreChangesWithDelay() {
    // Esperar un período inicial antes de activar notificaciones
    Future.delayed(Duration(seconds: 10), () {
      _listenToFirestoreChanges(); // Llamar a la función original después del delay
    });
  }

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

  Widget _showForcedLogoutDialog(
    BuildContext context,
    String nomUsuario,
    String movil,
  ) {
    return AlertDialog(
      title: Text('Deslogueo forzado'),
      content: Text(
        'Se ha conectado el usuario $nomUsuario con el móvil $movil en otro dispositivo.',
      ),
      actions: [
        TextButton(
          onPressed: () async {
            var box = await Hive.openBox('sessionBox');
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
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => LoginPage()),
              (Route<dynamic> route) => false,
            );
          },
          child: Text('Aceptar'),
        ),
      ],
    );
  }

  Future<void> _checkInternetConnectivity() async {
    // print('🔍 Verificando conectividad a Internet...');
    var connectivityResult = await Connectivity().checkConnectivity();
    // print('🔍 Resultado de conectividad: $connectivityResult');

    if (connectivityResult == ConnectivityResult.none ||
        (connectivityResult is List &&
            connectivityResult.contains(ConnectivityResult.none))) {
      // print('❌ No hay conexión a Internet.');
      if (!showPopup) _showNoInternetDialog(); // entra a modo "bloqueo"
      //_showNoInternetDialog(); // entra a modo "bloqueo"
    } else {
      // print('✅ Conexión a Internet disponible.');
      showPopup = false;
      // Podés continuar con la app aquí si querés.
    }
  }

  void _showNoInternetDialog() {
    // print('⚠️ Mostrando diálogo de "Sin Conexión a Internet".');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: navigatorKey.currentContext!,
        barrierDismissible: false, // No puede cerrarse tocando fuera del dialog
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Sin Conexión a Internet'),
            content: Text(
              'No tienes conexión a Internet. Por favor, verifica tu conexión.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () async {
                  // print('🔄 Reintentando conectividad a Internet...');
                  Navigator.of(context).pop(); // Cierra el diálogo actual
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
      _showNoInternetDialog(); // vuelve a mostrar el diálogo si sigue sin internet
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
    var mensajesBox = await Hive.openBox('mensajesBox');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Riogas - MoveIT',
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
                  bool shouldBlink = antennaColor != Colors.green;
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
            child: StreamBuilder<DocumentSnapshot?>(
              // Existing stream for Movil
              stream: _firebaseService.getMovilStream(),
              builder: (context, movilSnapshot) {
                if (!movilSnapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }

                var movilDoc = movilSnapshot.data!;
                var movilData = movilDoc.data() as Map<String, dynamic>;
                int estadoNro = movilData['EstadoNro'];
                // print('EstadoNro from Movil: $estadoNro'); // Log estadoNro

                return StreamBuilder<List<Map<String, dynamic>>>(
                  // New stream for SubEstadoMoviles
                  stream: _firebaseService.getSubEstadoMovilesStream(),
                  builder: (context, subEstadoSnapshot) {
                    if (!subEstadoSnapshot.hasData) {
                      return Center(child: CircularProgressIndicator());
                    }

                    var subEstados = subEstadoSnapshot.data!;
                    // print('SubEstados fetched: $subEstados'); // Log subEstados

                    var subEstado = subEstados.firstWhere(
                      (element) =>
                          int.tryParse(element['SubEstadoCod'].toString()) ==
                          estadoNro,
                      orElse: () => {
                        'DescCombo': 'Desconocido',
                        'CodColor': '000000',
                      },
                    );

                    // print(
                    //   'Matched SubEstado: $subEstado',
                    // ); // Log matched subEstado

                    String estadoText = subEstado['DescCombo'];
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
                      onTap: () => _showEstadoDropdown(
                        context,
                        _movil,
                        estadoNro,
                        subEstados,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
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
              },
            ),
          ),
        ],
      ),
      body: FutureBuilder(
        future: Hive.openBox('sessionBox'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          var box = Hive.box('sessionBox');
          bool firstLoginDone = box.get('firstLoginDone', defaultValue: false);
          bool existeSession = Hive.isBoxOpen('sessionBox');

          // print('🔒 firstLoginDone home_page: $firstLoginDone');
          // print('🔒 existeSession home_page: $existeSession');

          // ✅ Si es el primer login manual, ignorar completamente el chequeo de sesión activa
          if (firstLoginDone && existeSession) {
            // print(
            //   "🚀 Ignorando chequeo de logout forzado en el primer login manual...",
            // );
            return _widgetOptions.elementAt(_selectedIndex);
          } else {
            if (existeSession) {
              // print("🔒 Chequeando logout forzado en Firestore...");
              // ✅ Si no es el primer login, proceder con la validación en Firestore
              return StreamBuilder<Map<String, dynamic>?>(
                stream: _firebaseService.getSesionesStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  if (snapshot.hasData) {
                    var data = snapshot.data;
                    if (Hive.isBoxOpen('sessionBox')) {
                      var box = Hive.box('sessionBox');
                      if (data != null &&
                          data['idTerminal'] != box.get('deviceId')) {
                        return _showForcedLogoutDialog(
                          context,
                          data?['nomUsuario'] ?? 'Desconocido',
                          data?['movil'] ?? 'Desconocido',
                        );
                      }
                    } else {
                      // print(
                      //   '⚠️ sessionBox is not open. Skipping forced logout check.',
                      // );
                    }
                  } else {
                    return _showForcedLogoutDialog(
                      context,
                      'Desconocido',
                      'Desconocido',
                    );
                  }

                  return _widgetOptions.elementAt(_selectedIndex);
                },
              );
            } else {
              return _widgetOptions.elementAt(_selectedIndex);
            }
          }
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: [
          _buildBottomNavigationBarItem(Icons.list, 'Pendientes', _newOrders),
          _buildBottomNavigationBarItem(Icons.check_circle, 'Finalizados', 0),
          _buildBottomNavigationBarItem(Icons.map, 'Mapa', 0),
          _buildBottomNavigationBarItem(
            Icons.message,
            'Mensajes',
            _unreadMessages,
          ),
          _buildBottomNavigationBarItem(Icons.settings, 'Configuración', 0),
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
    String?
        selectedEstadoDesc; // Variable to store the selected state's DescCombo

    // print("🔍 Debugging Estado Dropdown:");
    // print("movilId: $movilId");
    // print("currentEstado: $currentEstado");
    // print("subEstados: $subEstados");

    // Get the current state's DescCombo
    String currentEstadoDesc = subEstados.firstWhere(
      (element) =>
          int.tryParse(element['SubEstadoCod'].toString()) == currentEstado,
      orElse: () => {'TipoEstado': 'Desconocido'},
    )['TipoEstado'];

    // print("currentEstadoDesc: $currentEstadoDesc");

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Cambiar Estado'),
              content: DropdownButton<String>(
                value: selectedEstadoDesc,
                hint: Text('Selecciona un estado'),
                items: subEstados
                    .where(
                  (subEstado) =>
                      subEstado['VisibleEnCombo'] == true &&
                      subEstado['TipoEstado'] != currentEstadoDesc,
                )
                    .map((subEstado) {
                  // print(
                  //   "🔍 SubEstado disponible: ${subEstado['DescCombo']}",
                  // );
                  return DropdownMenuItem<String>(
                    value: subEstado['DescCombo'] as String,
                    child: Text(subEstado['DescCombo'] as String),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    selectedEstadoDesc = newValue; // Update the selected state
                    // print("🔄 Estado seleccionado: $selectedEstadoDesc");
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(), // Close dialog
                  child: Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () async {
                    if (selectedEstadoDesc != null) {
                      var selectedSubEstado = subEstados.firstWhere(
                        (subEstado) =>
                            subEstado['DescCombo'] == selectedEstadoDesc,
                        orElse: () => {'SubEstadoCod': currentEstado},
                      );

                      int newEstadoNro = int.tryParse(
                            selectedSubEstado['SubEstadoCod'].toString(),
                          ) ??
                          currentEstado;

                      // print("✅ SubEstado seleccionado: $selectedSubEstado");
                      // print("🔢 Nuevo EstadoNro: $newEstadoNro");

                      await _firebaseService.updateMovilEstado(newEstadoNro);
                      // Call the actualizarMoviles service
                      var locationBox = await Hive.openBox('locationBox');
                      double velocidad =
                          locationBox.get('lastSpeed', defaultValue: 0.0);
                      double distanciaRecorrida =
                          locationBox.get('totalDistance', defaultValue: 0.0);

                      var result = await RioGasService.actualizarMoviles(
                          int.parse(
                            await Hive.box(
                              'sessionBox',
                            ).get('escenario', defaultValue: '0'),
                          ),
                          int.parse(movilId),
                          await Hive.box(
                            'sessionBox',
                          ).get('username', defaultValue: ''),
                          '', // NroSesion (if available, replace with actual value)
                          await Hive.box(
                            'sessionBox',
                          ).get('deviceId', defaultValue: ''),
                          newEstadoNro.toString(),
                          '', // Latitude (if available, replace with actual value)
                          '', // Longitude (if available, replace with actual value)
                          DateTime.now().toUtc().toIso8601String(),
                          '', // inAux1
                          '', // inAux2
                          velocidad, // Pass speed from Hive
                          distanciaRecorrida // Pass distance from Hive
                          );

                      if (result != null) {
                        // print('✅ Estado del móvil actualizado correctamente.');
                      } else {
                        // print('❌ Error al actualizar el estado del móvil.');
                      }

                      Navigator.of(
                        context,
                      ).pop(); // Close dialog after confirmation
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

  void _showConnectivityDialog(BuildContext context) async {
    var box = await Hive.openBox('conexionBox');
    // print("📦 Contenido de conexionBox:");
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

  Color _getAntennaColor(Map<String, dynamic> connectionStatus) {
    if (!connectionStatus['network']) return Colors.grey;
    if (!connectionStatus['firestore'] && !connectionStatus['riogas']) {
      return Colors.red;
    }
    if (!connectionStatus['firestore'] || !connectionStatus['riogas']) {
      return Colors.yellow;
    }
    return Colors.green;
  }
}
