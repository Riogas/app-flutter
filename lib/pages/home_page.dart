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
import 'package:latlong2/latlong.dart';
import 'package:MoveIT/pages/login_page.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
  }

  @override
  void dispose() {
    _ordersSubscription.cancel();
    _locationServiceCompleter.future.then((_) {
      _locationSubscription.cancel(); // 🔹 Cancelamos el stream de ubicación
      _locationService
          .stopLocationUpdates(); // 🔹 Detenemos el servicio correctamente
    });
    super.dispose();
  }

  Future<void> _initializeHomePage() async {
    await _loadSessionData();
    _listenToMessages();
    _listenToPendingOrders();
    _printConstantDocumentNames();
  }

  Future<void> _initializeLocationService() async {
    await _locationService.initializeLocationUpdates();
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

  void _listenToMessages() {
    _firebaseService.getMensajesStream().listen((messages) {
      setState(() {
        _unreadMessages = messages.where((message) {
          var data = message.data() as Map<String, dynamic>;
          return data['FchHoraLeido'] == null;
        }).length;
      });
    });
  }

  void _listenToPendingOrders() {
    _ordersSubscription = _firebaseService.getPedidosStream().listen((orders) {
      setState(() {
        _newOrders = orders.length;
      });
    });
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
            child: Row(
              children: [
                Icon(Icons.network_cell, color: Colors.green),
                SizedBox(width: 5),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Movil:$_movil - Activo',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
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
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal),
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
}
