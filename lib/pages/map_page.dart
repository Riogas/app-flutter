import 'package:MoveIT/pages/order_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/firebase_service.dart'; // Asegúrate de usar la ruta correcta
import 'package:cloud_firestore/cloud_firestore.dart';

class MapPage extends StatefulWidget {
  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  LatLng? _currentPosition;
  bool _locationPermissionDenied = false;
  final FirebaseService _firebaseService = FirebaseService();
  List<Marker> _markers = [];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _getPendingOrders();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _locationPermissionDenied = true;
      });
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _locationPermissionDenied = true;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _locationPermissionDenied = true;
      });
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);

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

  void _getPendingOrders() {
    _firebaseService.getPedidosStream().listen((orders) {
      setState(() {
        _markers = orders.map((order) {
          var data = order.data() as Map<String, dynamic>;
          var location = data['ubicacion'] as GeoPoint;
          return Marker(
            width: 80.0,
            height: 80.0,
            point: LatLng(location.latitude, location.longitude),
            child: IconButton(
              // ✅ Usar `child` en lugar de `builder`
              icon: Icon(Icons.location_on),
              color: Colors.red,
              iconSize: 40.0,
              onPressed: () {
                _showOrderDetails(
                  data['id'].toString(),
                  data['ClienteDireccion'],
                  data['DetalleHTML'],
                );
              },
            ),
          );
        }).toList();
      });
    });
  }

  void _showOrderDetails(String? id, String? address, String? detalleHtml) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Número: $id'),
        content: Text(address ?? 'Desconocida'),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                },
                child: Text('Cerrar'),
              ),
              TextButton(
                onPressed: () {
                  // Navegar a la página de detalles
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OrderDetailPage(
                        detalleHtml: detalleHtml ?? '',
                        estadoNro: 1, // Ajusta según sea necesario
                      ),
                    ),
                  );
                },
                child: Text('Ver Detalle'),
              ),
              TextButton(
                onPressed: () {
                  // Espacio para redirección a URL de llamada
                },
                child: Text('Llamar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mapa'),
      ),
      body: _currentPosition == null
          ? Center(
              child: _locationPermissionDenied
                  ? Text('Permiso de ubicación denegado')
                  : CircularProgressIndicator(),
            )
          : FlutterMap(
              options: MapOptions(
                initialCenter: _currentPosition ?? LatLng(0, 0),
                minZoom: 5.0,
                maxZoom: 18.0,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                  subdomains: ['a', 'b', 'c'],
                ),
                MarkerLayer(
                  markers: _markers,
                ),
              ],
            ),
    );
  }
}
