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
import 'main_.dart';

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
    _initializeLocationService(); // 🔹 Ahora con mejor control

    // 🔹 Resetear la bandera para futuros chequeos de sesión
    Future.delayed(Duration(seconds: 10), () async {
      var box = await Hive.openBox('sessionBox');
      await box.put('firstLoginDone', false);
      print(
          "🔄 Reset de la bandera firstLoginDone, futuras sesiones serán chequeadas normalmente.");
    });
  }

  @override
  void dispose() {
    _ordersSubscription.cancel();
    _locationSubscription.cancel(); // 🔹 Cancelamos el stream de ubicación
    _locationService
        .stopLocationUpdates(); // 🔹 Detenemos el servicio correctamente
    super.dispose();
  }

  /// 🔹 **Inicializa el servicio de ubicación y maneja el stream**
  Future<void> _initializeLocationService() async {
    try {
      await _locationService
          .initializeLocationUpdates(); // ⏳ Esperamos a que se inicie correctamente

      // 🔹 Iniciamos la escucha de coordenadas
      _locationSubscription = _locationService.locationStream.listen(
        (LatLng position) {
          print('📍 Nueva coordenada recibida en HomePage: '
              '${position.latitude}, ${position.longitude}');
        },
        onError: (error) {
          print("❌ Error en el stream de ubicación: $error");
        },
      );
    } catch (e) {
      print('❌ Error al inicializar el servicio de ubicación: $e');
    }
  }

  Future<void> _initializeHomePage() async {
    await _loadSessionData();
    _listenToMessages();
    _listenToPendingOrders();
    _printConstantDocumentNames();
  }

  Future<void> _loadSessionData() async {
    var box = await Hive.openBox('sessionBox');
    print("📦 Contenido de sessionBox:");
    box.toMap().forEach((key, value) => print('$key: $value'));
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
      appBar: AppBar(title: Text('MoveIT'), toolbarHeight: 40.0),
      body: FutureBuilder(
        future: Hive.openBox('sessionBox'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          var box = Hive.box('sessionBox');
          bool firstLoginDone = box.get('firstLoginDone', defaultValue: false);

          print('🔒 firstLoginDone home_page: $firstLoginDone');

          // ✅ Si es el primer login manual, ignorar completamente el chequeo de sesión activa
          if (firstLoginDone) {
            print(
                "🚀 Ignorando chequeo de logout forzado en el primer login manual...");
            return _widgetOptions.elementAt(_selectedIndex);
          } else {
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
      ),
    );
  }

  BottomNavigationBarItem _buildBottomNavigationBarItem(
      IconData icon, String label, int badgeCount) {
    return BottomNavigationBarItem(
      icon: Stack(
        children: [
          Icon(icon),
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
