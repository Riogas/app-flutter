import 'package:MoveIT/pages/order_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/firebase_service.dart'; // Asegúrate de usar la ruta correcta
import 'package:hive/hive.dart'; // Import Hive for Box
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:MoveIT/pages/pending_orders.dart';

class MapPage extends StatefulWidget {
  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  LatLng? _currentPosition;
  LatLng? _focusedPosition; // Track the map's focused position
  bool _locationPermissionDenied = false;
  bool _isMapEnabled = false; // Estado inicial del mapa deshabilitado
  final FirebaseService _firebaseService = FirebaseService();
  List<Marker> _markers = [];
  late Box constantBox;
  late Box pedidosBox;
  late Box sessionBox; // Box para guardar el estado del mapa
  final MapController _mapController =
      MapController(); // 🟢 Agregar controlador del mapa

  @override
  void initState() {
    super.initState();
    _initializeHive().then((_) {
      _checkMapState(); // Verificar el estado del mapa después de inicializar Hive
      _getCurrentLocation();
      _getPendingOrders();
    });
  }

  Future<void> _initializeHive() async {
    constantBox = await Hive.openBox('constantBox');
    pedidosBox = await Hive.openBox('pedidosBox');
    sessionBox = await Hive.openBox('sessionBox'); // Inicializar sessionBox
  }

  void _checkMapState() {
    final isMapActive = sessionBox.get('isMapActive', defaultValue: false);
    setState(() {
      _isMapEnabled = isMapActive;
    });
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _locationPermissionDenied = true;
        });
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _locationPermissionDenied = true;
          });
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _locationPermissionDenied = true;
        });
      }
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    if (mounted) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);

        // 🟢 Agregar marcador de la ubicación actual
        _markers.add(
          Marker(
            width: 80.0,
            height: 80.0,
            point: _currentPosition!,
            child: Icon(
              Icons.local_shipping, // Ícono de usuario
              color: Colors.blue, // Color diferente a los pedidos
              size: 30.0,
            ),
          ),
        );
      });
    }
  }

  void _centerMapOnUser() {
    if (_currentPosition != null) {
      _mapController.move(
        _currentPosition!,
        15.0,
      ); // 🟢 Mover el mapa a la posición actual con zoom 15
    }
  }

  String _getPedidoEstado(int pedidoId) {
    var pedidoEstado = pedidosBox.get(pedidoId);
    if (pedidoEstado == null) {
      return 'No Leído';
    } else if (pedidoEstado == 'Procesando') {
      return ''; // Ignorar pedidos con estado "Procesando"
    } else if (pedidoEstado == 'Enviando') {
      return 'Enviando';
    }
    return 'Nuevo';
  }

  void _centerMapOnPriorityOrder(List<QueryDocumentSnapshot> orders) {
    // Filtrar pedidos que no tengan estado "Procesando"
    var filteredOrders = orders.where((order) {
      var data = order.data() as Map<String, dynamic>;
      var pedidoId = data['id'];
      return _getPedidoEstado(pedidoId) != '';
    }).toList();

    if (filteredOrders.isNotEmpty) {
      var firstOrder = filteredOrders.first;
      var data = firstOrder.data() as Map<String, dynamic>;
      var location = data['ubicacion'] as GeoPoint;

      setState(() {
        _focusedPosition = LatLng(location.latitude, location.longitude);
      });
    } else if (_currentPosition != null) {
      // Si no hay pedidos para geolocalizar, centrar en la ubicación actual
      _mapController.move(_currentPosition!, 15.0);
    }
  }

  void _getPendingOrders() {
    _firebaseService.getPedidosStream().listen((orders) {
      setState(() {
        _markers = orders
            .map((order) {
              var data = order.data() as Map<String, dynamic>;

              // Check if 'ubicacion' field exists
              if (!data.containsKey('ubicacion') || data['ubicacion'] == null) {
                return null; // Skip orders without 'ubicacion'
              }

              var location = data['ubicacion'] as GeoPoint;
              var pedidoId = data['id'];

              // Check the order state in Hive
              var pedidoEstado = pedidosBox.get(pedidoId);
              if (pedidoEstado == 'Procesando') {
                return null; // Skip orders with "Procesando" state
              }

              // Calculate delay in minutes
              DateTime now = DateTime.now();
              DateTime fchHoraPara =
                  (data['FchHoraMaxEntComp'] as Timestamp).toDate();
              int delayMinutes = fchHoraPara.difference(now).inMinutes;

              // Get delay info (color and label)
              var delayInfo = getDelayInfo(delayMinutes);
              Color pinColor =
                  delayInfo?["Color"] ?? Colors.red; // Default to red

              return Marker(
                width: 80.0,
                height: 80.0,
                point: LatLng(location.latitude, location.longitude),
                child: IconButton(
                  icon: Icon(Icons.location_on),
                  color: pinColor, // Use the color from delayInfo
                  iconSize: 40.0,
                  onPressed: () {
                    // Navegar directamente a la página de detalles
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OrderDetailPage(
                          detalleHtml: data['DetalleHTML'] ?? '',
                          estadoNro: 1, // Ajusta según sea necesario
                          totalPedido: data['TotalPedido'] ??
                              0.0, // Ajusta según sea necesario
                          codPedido: data['id'],
                          pedidoTipo: data['Tipo'],
                          ubicacion: data.containsKey('ubicacion') &&
                                  data['ubicacion'] is GeoPoint
                              ? data['ubicacion'] as GeoPoint
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              );
            })
            .where((marker) => marker != null)
            .toList()
            .cast<Marker>(); // Filter out null markers and cast to List<Marker>

        // Center map on the client with the longest delay or the first order
        _centerMapOnPriorityOrder(
          orders.cast<QueryDocumentSnapshot<Object?>>(),
        );
      });
    });
  }

  Map<String, dynamic>? getDelayInfo(int delayMinutes) {
    for (int id in [40, 41, 42, 43]) {
      var data = constantBox.get(id.toString());
      print("🔍 Leyendo constante con ID $id: $data");
      if (data != null && data['Estado'] == 'A') {
        print("✅ Estado es 'A' para ID $id");
        print(
          "🔢 Comparando delayMinutes: $delayMinutes con ValorMin: ${data['ValorMin']} y ValorMax: ${data['ValorMax']}",
        );
        if ((delayMinutes >= data['ValorMin'] &&
                delayMinutes <= data['ValorMax']) ||
            (delayMinutes <= data['ValorMin'] &&
                delayMinutes >= data['ValorMax'])) {
          print(
            "⏳ Delay $delayMinutes está entre ${data['ValorMin']} y ${data['ValorMax']} para ID $id",
          );
          return {
            "Color": getColorFromName(data['Color']),
            "Etiqueta": data['Etiqueta'],
          };
        } else {
          print(
            "❌ Delay $delayMinutes no está entre ${data['ValorMin']} y ${data['ValorMax']} para ID $id",
          );
        }
      } else {
        print("❌ Estado no es 'A' para ID $id o data es null");
      }
    }
    print("❌ No se encontró un rango válido para delay $delayMinutes");
    return null;
  }

  Color getColorFromName(String colorName) {
    return colorMap[colorName] ??
        Colors.white; // Devuelve blanco si el color no se encuentra
  }

  Map<String, Color> colorMap = {
    "Red": Colors.red,
    "Pink": Colors.pink,
    "Green": Colors.green,
    "Yellow": Colors.orange,
    // Agrega más colores según sea necesario
  };

  void _activateMap() {
    setState(() {
      _isMapEnabled = true;
    });
    sessionBox.put(
        'isMapActive', true); // Guardar el estado del mapa como activo
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mapa'),
        actions: [
          IconButton(
            icon: Icon(Icons.my_location),
            onPressed: _isMapEnabled
                ? _centerMapOnUser
                : null, // Solo habilitar si el mapa está activo
          ),
        ],
      ),
      body: !_isMapEnabled
          ? Center(
              child: ElevatedButton(
                onPressed: _activateMap, // Activar el mapa y guardar el estado
                child: Text('Activar Mapa'),
              ),
            )
          : (_currentPosition == null
              ? Center(
                  child: _locationPermissionDenied
                      ? Text('Permiso de ubicación denegado')
                      : CircularProgressIndicator(),
                )
              : FlutterMap(
                  mapController: _mapController, // Asignar controlador al mapa
                  options: MapOptions(
                    initialCenter:
                        _focusedPosition ?? _currentPosition ?? LatLng(0, 0),
                    initialZoom: 15.0,
                    minZoom: 5.0,
                    maxZoom: 18.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                      subdomains: ['a', 'b', 'c'],
                    ),
                    MarkerLayer(markers: _markers),
                  ],
                )),
    );
  }
}
