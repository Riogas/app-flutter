import 'package:flutter/material.dart';
import 'pending_orders.dart';
import 'completed_orders.dart';
import 'map_page.dart';
import 'settings_page.dart';
import 'message_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:flutter_background/flutter_background.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'session_service.dart'; // Importar el servicio de sesión
import 'firebase_service.dart'; // Importar el servicio de Firebase

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseService _firebaseService = FirebaseService();
  int _selectedIndex = 0;
  int _unreadMessages = 0;
  int _newOrders = 0;
  Timer? _timer;
  LatLng? _currentPosition;
  bool _locationPermissionDenied = false;
  bool _constantsLoaded = false;
  int _coordinateUpdateInterval = 30; // Valor por defecto en segundos

  static List<Widget> _widgetOptions = <Widget>[
    PendingOrdersPage(),
    CompletedOrdersPage(),
    MapPage(),
    MessagePage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _loadSessionData();
    _startLocationUpdates();
    _printConstantDocumentNames();
    _listenToMessages();
    _listenToPendingOrders();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadSessionData() async {
    var box = await Hive.openBox('sessionBox');
    var frecuenciaEnvio = box.get(
        'Frecuencia envio coordenadas a Riogas (segs)',
        defaultValue: {'Valor': 30, 'Estado': 'I'});

    if (frecuenciaEnvio['Estado'] == 'A') {
      setState(() {
        _coordinateUpdateInterval = frecuenciaEnvio['Valor'];
      });
    }

    // Debug: Mostrar todo el contenido de sessionBox
    print("Contenido de sessionBox:");
    box.toMap().forEach((key, value) {
      print('$key: $value');
    });
  }

  void _startLocationUpdates() async {
    // Obtener las coordenadas inmediatamente
    await _getAndShowLocation();

    // Configurar el timer para obtener las coordenadas según el valor de la constante
    print(
        'Configurando el timer para obtener las coordenadas cada $_coordinateUpdateInterval segundos.');
    _timer = Timer.periodic(Duration(seconds: _coordinateUpdateInterval),
        (timer) async {
      print('Obteniendo coordenadas...');
      await _getAndShowLocation();
    });
  }

  Future<void> _getAndShowLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _locationPermissionDenied = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Permisos de ubicación denegados. Por favor, actívelos para continuar.'),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _locationPermissionDenied = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Permisos de ubicación denegados permanentemente. Por favor, actívelos en la configuración.'),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    // Obtener la ubicación actual del usuario
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
      _locationPermissionDenied = false;
    });

    print('Latitud: ${position.latitude}, Longitud: ${position.longitude}');
  }

  Future<void> _printConstantDocumentNames() async {
    if (!_constantsLoaded) {
      try {
        QuerySnapshot querySnapshot = await FirebaseFirestore.instance
            .collection('Constantes-1000')
            .get();
        print("Documentos en 'Constantes-1000':");
        for (var doc in querySnapshot.docs) {
          print('📝 Document ID: ${doc.id}');
        }
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
          return !data.containsKey('FchHoraLeido') ||
              data['FchHoraLeido'] == null;
        }).length;
      });
    });
  }

  void _listenToPendingOrders() {
    _firebaseService.getPedidosStream().listen((orders) {
      setState(() {
        _newOrders = orders.where((order) {
          var data = order.data() as Map<String, dynamic>;
          return !data.containsKey('FechaHoraLeido') ||
              data['FechaHoraLeido'] == null;
        }).length;
      });
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('MoveIT'),
        toolbarHeight: 40.0, // Ajusta la altura del AppBar
      ),
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                Icon(Icons.list),
                if (_newOrders > 0)
                  Positioned(
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      constraints: BoxConstraints(
                        minWidth: 12,
                        minHeight: 12,
                      ),
                      child: Text(
                        '$_newOrders',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Pendientes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle),
            label: 'Finalizados',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Mapa',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                Icon(Icons.message),
                if (_unreadMessages > 0)
                  Positioned(
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      constraints: BoxConstraints(
                        minWidth: 12,
                        minHeight: 12,
                      ),
                      child: Text(
                        '$_unreadMessages',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Mensajes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Configuración',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        unselectedItemColor:
            Colors.grey, // Color de los elementos no seleccionados
        onTap: _onItemTapped,
      ),
    );
  }
}
