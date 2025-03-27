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
    _blinkController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true); // Blinking effect
    _initializeHomePage();

    // 🔹 Resetear la bandera para futuros chequeos de sesión
    Future.delayed(Duration(seconds: 10), () async {
      var box = await Hive.openBox('sessionBox');
      await box.put('firstLoginDone', false);
      print(
          "🔄 Reset de la bandera firstLoginDone, futuras sesiones serán chequeadas normalmente.");
    });

    // 🔹 Inicializar el servicio de ubicación
    _initializeLocationService();

    // 🔹 Escuchar cambios en Firestore para pedidos y mensajes
    _listenToFirestoreChanges();

    // 🔹 Inicializar la verificación de conectividad
    _checkInternetConnectivity();

    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
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
    super.dispose();
  }

  Future<void> _initializeHomePage() async {
    await _loadSessionData();
    await RioGasService
        .initializeService(); // 🔹 Inicializa el servicio de RioGas
    _listenToMessages();
    _listenToPendingOrders();
    _printConstantDocumentNames();
  }

  Future<void> _initializeLocationService() async {
    await _locationService.initializeLocationUpdates(context);
    _locationSubscription = _locationService.locationStream.listen((location) {
      print('📍 Nueva ubicación recibida en HomePage: $location');
    });
    _locationServiceCompleter.complete();
  }

  Future<void> _loadSessionData() async {
    var box = await Hive.openBox('sessionBox');
    print("📦 Contenido de sessionBox:");
    box.toMap().forEach((key, value) => print('$key: $value'));
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
            .collection('Constantes-$escenario')
            .get();
        print("📂 Documentos en 'Constantes-$escenario':");
        querySnapshot.docs.forEach((doc) => print('📝 ${doc.id}'));

        setState(() {
          _constantsLoaded = true;
        });
      } catch (e) {
        print("❌ Error al obtener documentos de 'Constantes-1000': $e");
      }
    }
  }

  void _listenToMessages() async {
    var mensajesBox = await Hive.openBox('mensajesBox'); // Open mensajesBox
    _firebaseService.getMensajesStream().listen((messages) async {
      int newMessagesCount = 0;

      print("📦 Contenido de mensajesBox:");
      print(mensajesBox.toMap());

      for (var message in messages) {
        if (!mensajesBox.containsKey(message.id)) {
          await mensajesBox.put(message.id, 'Descargado'); // Mark as downloaded
          newMessagesCount++;

          // Parse message ID as an integer
          final numericIdMatch = RegExp(r'\d+').firstMatch(message.id);
          int messageId = int.parse(numericIdMatch!.group(0)!);

          // Call descargaLecturaMensajes for each new message
          var box = await Hive.openBox('sessionBox');
          String escenario = box.get('escenario', defaultValue: '1000');
          String movil = box.get('movil');
          String username = box.get('username');
          String deviceId = box.get('deviceId');
          Position position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high);

          print('📨 Enviando datos al servicio descargaLecturaMensajes:');
          print('EscenarioId: ${int.parse(escenario)}');
          print('MovilId: ${int.parse(movil)}');
          print('MessageId: $messageId');
          print('Usuario: $username');
          print('NroSesion: ');
          print('TermMobileEquipo: $deviceId');
          print('LectDesc: LECTURA');
          print('FechaHoraCmbEst: ${DateTime.now().toUtc().toIso8601String()}');
          print('INAux1: ');
          print('INAux2: ');
          print('Latitud: ${position.latitude}');
          print('Longitud: ${position.longitude}');

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
          );
        } else {
          if (mensajesBox.get(message.id) == 'Leido') {
            // Ya está descargado
            newMessagesCount--;
          }
        }
      }

      if (newMessagesCount > 0) {
        _showNotification(
            'Nuevo Mensaje', 'Tienes $newMessagesCount mensajes nuevos.');
      }

      setState(() {
        _unreadMessages = mensajesBox.length; // Update unread messages count
      });
    });
  }

  void _listenToPendingOrders() {
    _ordersSubscription =
        _firebaseService.getPedidosStream().listen((orders) async {
      setState(() {
        _newOrders = orders.length;
      });

      for (var order in orders) {
        var pedido = order.data() as Map<String, dynamic>; // Extract data
        int pedidoId = pedido['id'] ?? -1; // Extract ID from the data map

        var pedidosBox = await Hive.openBox('pedidosBox'); // Open pedidosBox

        if (!pedidosBox.containsKey(pedidoId.toString())) {
          await pedidosBox.put(
              pedidoId.toString(), 'Descargado'); // Mark as "Descargado"
          _showNotification(
              'Nueva Visita', 'Tienes un nueva visita pendiente.');

          // Call the download and read routine here
          await _callDescargaLecturaPedidos(pedido, pedidoId);
        }
      }
    });
  }

  Future<void> _callDescargaLecturaPedidos(
      Map<String, dynamic> pedido, int pedidoId) async {
    String pedidoTpo = pedido['Tipo'] == 'Pedidos' ? '1' : '2';
    String lectDesc = 'DESCARGA';
    String fechaHoraCmbEst = DateTime.now().toUtc().toIso8601String();

    String inAux2 = '';

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    String latitud = position.latitude.toString();
    String longitud = position.longitude.toString();

    var box = await Hive.openBox('sessionBox');
    int escenarioId = int.tryParse(box.get('escenario').toString()) ?? 0;
    String movil = box.get('movil');
    String username = box.get('username');
    String deviceId = box.get('deviceId');
    String inAux1 = deviceId;

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
    );
  }

  void _listenToFirestoreChanges() {
    FirebaseFirestore.instance
        .collection('Pedidos')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          _showNotification(
              'Nueva Visita', 'Tienes un nueva visita pendiente.');
        }
      }
    });

    FirebaseFirestore.instance
        .collection('Mensajes')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          _showNotification('Nuevo Mensaje', 'Tienes un nuevo mensaje.');
        }
      }
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
      //sound: RawResourceAndroidNotificationSound(
      //  'custom_sound'), // Cambia 'custom_sound' por el nombre de tu archivo de sonido en res/raw
      //vibrationPattern: Int64List.fromList([0, 1000, 500, 2000]), // Duración y fuerza de la vibración
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
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
      BuildContext context, String nomUsuario, String movil) {
    return AlertDialog(
      title: Text('Deslogueo forzado'),
      content: Text(
          'Se ha conectado el usuario $nomUsuario con el móvil $movil en otro dispositivo.'),
      actions: [
        TextButton(
          onPressed: () async {
            await Hive.openBox('sessionBox').then((box) => box.clear());
            await Hive.openBox('mensajesBox')
                .then((box) => box.clear()); // Clear mensajesBox
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
    print('🔍 Verificando conectividad a Internet...');
    var connectivityResult = await Connectivity().checkConnectivity();
    print('🔍 Resultado de conectividad: $connectivityResult');

    if (connectivityResult == ConnectivityResult.none ||
        (connectivityResult is List &&
            connectivityResult.contains(ConnectivityResult.none))) {
      print('❌ No hay conexión a Internet.');
      if (!showPopup) _showNoInternetDialog(); // entra a modo "bloqueo"
      //_showNoInternetDialog(); // entra a modo "bloqueo"
    } else {
      print('✅ Conexión a Internet disponible.');
      showPopup = false;
      // Podés continuar con la app aquí si querés.
    }
  }

  void _showNoInternetDialog() {
    print('⚠️ Mostrando diálogo de "Sin Conexión a Internet".');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: navigatorKey.currentContext!,
        barrierDismissible: false, // No puede cerrarse tocando fuera del dialog
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Sin Conexión a Internet'),
            content: Text(
                'No tienes conexión a Internet. Por favor, verifica tu conexión.'),
            actions: <Widget>[
              TextButton(
                onPressed: () async {
                  print('🔄 Reintentando conectividad a Internet...');
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
    print('🔁 Reintento de conexión iniciado...');
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none ||
        (connectivityResult is List &&
            connectivityResult.contains(ConnectivityResult.none))) {
      print('🚫 Aún sin conexión. Mostrando diálogo nuevamente.');
      _showNoInternetDialog(); // vuelve a mostrar el diálogo si sigue sin internet
    } else {
      print('✅ Conexión restaurada.');
      // Aquí podés continuar con el flujo normal de tu app
    }
  }

  void _checkConnectivityAndPerformAction() async {
    print('🔄 Checking connectivity...');
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      print('❌ No connectivity detected. Performing fallback action...');
      // Placeholder for future action when no connectivity is detected
    } else {
      print('✅ Connectivity available.');
      // Placeholder for future action when connectivity is available
    }
  }

  Future<void> _markMessageAsRead(String messageId) async {
    var mensajesBox = await Hive.openBox('mensajesBox');
    await mensajesBox.put(messageId, 'Leido'); // Mark as read
    print('📨 Mensaje $messageId marcado como "Leido" en Hive.');
  }

  void _showRioGasConnectivityModal() {
    print('⚠️ Showing RioGas connectivity modal...');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Conectividad con RioGas'),
          content: Text(
              'Actualmente no hay conectividad con RioGas. Por favor, verifica tu conexión.'),
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
        title: Text('MoveIT'),
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
                            child:
                                Icon(Icons.network_cell, color: antennaColor),
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
                print('EstadoNro from Movil: $estadoNro'); // Log estadoNro

                return StreamBuilder<List<Map<String, dynamic>>>(
                  // New stream for SubEstadoMoviles
                  stream: _firebaseService.getSubEstadoMovilesStream(),
                  builder: (context, subEstadoSnapshot) {
                    if (!subEstadoSnapshot.hasData) {
                      return Center(child: CircularProgressIndicator());
                    }

                    var subEstados = subEstadoSnapshot.data!;
                    print('SubEstados fetched: $subEstados'); // Log subEstados

                    var subEstado = subEstados.firstWhere(
                      (element) =>
                          int.tryParse(element['SubEstadoCod'].toString()) ==
                          estadoNro,
                      orElse: () =>
                          {'DescCombo': 'Desconocido', 'CodColor': '000000'},
                    );

                    print(
                        'Matched SubEstado: $subEstado'); // Log matched subEstado

                    String estadoText = subEstado['DescCombo'];
                    String codColor = subEstado['CodColor'];
                    List<String> rgb = codColor.split(',');
                    String hexColor = rgb.length == 3
                        ? rgb
                            .map((c) =>
                                int.parse(c).toRadixString(16).padLeft(2, '0'))
                            .join()
                        : '000000';
                    Color estadoColor = Color(int.parse('0xff$hexColor'));

                    return GestureDetector(
                      onTap: () => _showEstadoDropdown(
                          context, movilDoc.id, estadoNro, subEstados),
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

          print('🔒 firstLoginDone home_page: $firstLoginDone');
          print('🔒 existeSession home_page: $existeSession');

          // ✅ Si es el primer login manual, ignorar completamente el chequeo de sesión activa
          if (firstLoginDone && existeSession) {
            print(
                "🚀 Ignorando chequeo de logout forzado en el primer login manual...");
            return _widgetOptions.elementAt(_selectedIndex);
          } else {
            if (existeSession) {
              print("🔒 Chequeando logout forzado en Firestore...");
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
                      if (data != null &&
                          data['idTerminal'] != box.get('deviceId')) {
                        return _showForcedLogoutDialog(
                            context, data['nomUsuario'], data['movil']);
                      }
                    } else {
                      return _showForcedLogoutDialog(
                          context, 'Desconocido', 'Desconocido');
                    }

                    return _widgetOptions.elementAt(_selectedIndex);
                  });
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
              Icons.message, 'Mensajes', _unreadMessages),
          _buildBottomNavigationBarItem(Icons.settings, 'Configuración', 0),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        elevation: 10,
        selectedLabelStyle:
            TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
        unselectedLabelStyle:
            TextStyle(fontWeight: FontWeight.normal, fontSize: 10),
        showSelectedLabels: true,
        showUnselectedLabels: false,
      ),
    );
  }

  BottomNavigationBarItem _buildBottomNavigationBarItem(
      IconData icon, String label, int badgeCount) {
    return BottomNavigationBarItem(
      icon: Stack(
        children: [
          Icon(icon, size: 20),
          if (badgeCount > 0)
            Positioned(
              right: 0,
              child: _buildBadge(badgeCount),
            ),
        ],
      ),
      label: label,
    );
  }

  Widget _buildBadge(int count) {
    return Container(
      padding: EdgeInsets.all(1),
      decoration: BoxDecoration(
          color: Colors.red, borderRadius: BorderRadius.circular(6)),
      constraints: BoxConstraints(minWidth: 12, minHeight: 12),
      child: Text('$count',
          style: TextStyle(color: Colors.white, fontSize: 8),
          textAlign: TextAlign.center),
    );
  }

  void _showEstadoDropdown(BuildContext context, String movilId,
      int currentEstado, List<Map<String, dynamic>> subEstados) {
    String?
        selectedEstadoDesc; // Variable to store the selected state's DescCombo

    // Get the current state's DescCombo
    String currentEstadoDesc = subEstados.firstWhere(
      (element) =>
          int.tryParse(element['SubEstadoCod'].toString()) == currentEstado,
      orElse: () => {'DescCombo': 'Desconocido'},
    )['DescCombo'];

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
                    .where((subEstado) =>
                        subEstado['VisibleEnCombo'] == true &&
                        subEstado['DescCombo'] != currentEstadoDesc)
                    .map((subEstado) {
                  return DropdownMenuItem<String>(
                    value: subEstado['DescCombo'] as String,
                    child: Text(subEstado['DescCombo'] as String),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    selectedEstadoDesc = newValue; // Update the selected state
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
                              selectedSubEstado['SubEstadoCod'].toString()) ??
                          currentEstado;

                      await _firebaseService.updateMovilEstado(newEstadoNro);
                      // Call the actualizarMoviles service
                      var result = await RioGasService.actualizarMoviles(
                        int.parse(await Hive.box('sessionBox')
                            .get('escenario', defaultValue: '0')),
                        int.parse(movilId),
                        await Hive.box('sessionBox')
                            .get('username', defaultValue: ''),
                        '', // NroSesion (if available, replace with actual value)
                        await Hive.box('sessionBox')
                            .get('deviceId', defaultValue: ''),
                        newEstadoNro.toString(),
                        '', // Latitude (if available, replace with actual value)
                        '', // Longitude (if available, replace with actual value)
                        DateTime.now().toUtc().toIso8601String(),
                        '', // inAux1
                        '', // inAux2
                      );

                      if (result != null) {
                        print('✅ Estado del móvil actualizado correctamente.');
                      } else {
                        print('❌ Error al actualizar el estado del móvil.');
                      }

                      Navigator.of(context)
                          .pop(); // Close dialog after confirmation
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
    print("📦 Contenido de conexionBox:");
    box.toMap().forEach((key, value) => print('$key: $value'));
    bool conexionFirestore = box.get('conexionFirestore', defaultValue: true);
    bool conexionRioGas = box.get('conexionRioGas', defaultValue: false);
    String lastConnectivityDateFirestore =
        _formatTime(box.get('lastSuccessfulConnection', defaultValue: 'N/A'));
    String lastConnectivityDateRiogas =
        _formatTime(box.get('conexionRioGasTimestamp', defaultValue: 'N/A'));
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
                  'Nube', firestoreColor, lastConnectivityDateFirestore),
              _buildConnectivityRow(
                  'RioGas', rioGasColor, lastConnectivityDateRiogas),
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
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
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
