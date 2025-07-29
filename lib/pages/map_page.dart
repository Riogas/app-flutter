import 'package:MoveIT/pages/order_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:hive/hive.dart'; // Import Hive for Box
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/persistent_stream_manager.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

class MapPage extends StatefulWidget {
  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  LatLng? _currentPosition;
  LatLng? _focusedPosition; // Track the map's focused position
  bool _locationPermissionDenied = false;
  bool _isMapEnabled = false; // Estado inicial del mapa deshabilitado
  // Eliminado: final StreamManager _streamManager = StreamManager(); // Usar PersistentStreamManager singleton
  List<Marker> _markers = [];
  late Box constantBox;
  late Box pedidosBox;
  late Box sessionBox; // Box para guardar el estado del mapa
  final MapController _mapController =
      MapController(); // 🟢 Agregar controlador del mapa
  bool _mapRendered = false;

  @override
  void initState() {
    super.initState();
    // Inicializa el backend predeterminado y otras tareas asíncronas
    Future.microtask(() async {
      await FMTCObjectBoxBackend().initialise();
      await _initializeTileCache();
      await _initializeHive();
      _checkMapState(); // Verificar el estado del mapa después de inicializar Hive
      _getCurrentLocation();
      // Ya no llamamos a _getPendingOrders, usamos el notifier global
    });
  }

  Future<void> _initializeTileCache() async {
    try {
      // 🟣 Activar logs internos del paquete
      await FMTCStore('mapCache').manage.create();
      print("🟣 Cache de tiles inicializado con logging activado");
    } catch (e) {
      print("🟣 Error al inicializar cache de tiles: $e");
    }
  }

  Future<void> _initializeHive() async {
    constantBox = await Hive.openBox('constantBox');
    print("🟣 Hive constantBox inicializado: ${constantBox.isOpen}");
    print("🟣 Contenido de constantBox: ${constantBox.toMap()}");
    pedidosBox = await Hive.openBox('pedidosBox');
    print("🟣 Hive pedidosBox inicializado: ${pedidosBox.isOpen}");
    sessionBox = await Hive.openBox('sessionBox');
    print("🟣 Hive sessionBox inicializado: ${sessionBox.isOpen}");
  }

  void _checkMapState() {
    final isMapActive = sessionBox.get('isMapActive', defaultValue: false);
    print("🟣 Estado del mapa (isMapActive): $isMapActive");
    setState(() {
      _isMapEnabled = isMapActive;
    });
  }

  Future<void> _getCurrentLocation() async {
    print("🟣 Iniciando obtención de ubicación actual...");
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    print("🟣 Servicio de ubicación habilitado: $serviceEnabled");
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _locationPermissionDenied = true;
        });
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    print("🟣 Permiso de ubicación actual: $permission");
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      print("🟣 Permiso de ubicación solicitado: $permission");
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
      print("🟣 Permiso de ubicación denegado permanentemente");
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
    print(
        "🟣 Ubicación obtenida: Latitud ${position.latitude}, Longitud ${position.longitude}");

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
        print("🟣 Marcador de ubicación actual agregado: $_currentPosition");
      });

      // 🟢 Centrar el mapa en la ubicación actual después de que el widget esté renderizado
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(_currentPosition!, 15.0);
        } catch (e) {
          print("🟣 Error al mover el mapa: $e");
        }
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

  int _getTileCacheDays() {
    var data = constantBox.get('300');
    print("🔍 Leyendo constante con ID 300 para días de cache: $data");
    if (data != null && data['Estado'] == 'A') {
      print("✅ Estado es 'A' para ID 300, días configurados: ${data['Valor']}");
      return data['Valor'] ??
          7; // Usar el valor de la constante o 7 por defecto
    } else {
      print(
          "❌ Estado no es 'A' para ID 300 o data es null, usando 7 días por defecto");
      return 7; // Valor por defecto
    }
  }

  // Ya no se usa _getPendingOrders, la lógica se mueve al ValueListenableBuilder en el build

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
    return {
      "Color": Colors.white,
      "Etiqueta": "",
    }; // Color y etiqueta por defecto
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
    print("🟣 Mapa activado y estado guardado en Hive");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mapa'),
        actions: [
          IconButton(
            icon: Icon(Icons.my_location),
            onPressed: _isMapEnabled ? _centerMapOnUser : null,
          ),
        ],
      ),
      body: !_isMapEnabled
          ? Center(
              child: ElevatedButton(
                onPressed: _activateMap,
                child: Text('Activar Mapa'),
              ),
            )
          : (_currentPosition == null
              ? Center(
                  child: _locationPermissionDenied
                      ? Text('Permiso de ubicación denegado')
                      : CircularProgressIndicator(),
                )
              : ValueListenableBuilder<List<DocumentSnapshot>>(
                  valueListenable: PersistentStreamManager().pedidosNotifier,
                  builder: (context, pedidos, child) {
                    List<Marker> markers = [];
                    for (var order in pedidos) {
                      var data = order.data() as Map<String, dynamic>;
                      if (!data.containsKey('ubicacion') ||
                          data['ubicacion'] == null) continue;
                      var location = data['ubicacion'] as GeoPoint;
                      var pedidoId = data['id'];
                      var pedidoEstado = pedidosBox.get(pedidoId);
                      if (pedidoEstado == 'Procesando') continue;
                      DateTime now = DateTime.now();
                      DateTime fchHoraPara =
                          (data['FchHoraMaxEntComp'] as Timestamp).toDate();
                      int delayMinutes = fchHoraPara.difference(now).inMinutes;
                      var delayInfo = getDelayInfo(delayMinutes);
                      Color pinColor = delayInfo?['Color'] ?? Colors.red;

                      markers.add(
                        Marker(
                          width: 80.0,
                          height: 80.0,
                          point: LatLng(location.latitude, location.longitude),
                          child: IconButton(
                            icon: Icon(Icons.location_on),
                            color: pinColor,
                            iconSize: 40.0,
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => OrderDetailPage(
                                    detalleHtml: data['DetalleHTML'] ?? '',
                                    estadoNro: 1,
                                    totalPedido: data['TotalPedido'] ?? 0.0,
                                    codPedido: data['id'],
                                    pedidoTipo: data['Tipo'],
                                    ubicacion: data['ubicacion'] as GeoPoint,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    }

                    // Centrar el mapa en el pedido prioritario
                    if (pedidos.isNotEmpty) {
                      var filteredOrders = pedidos.where((order) {
                        var data = order.data() as Map<String, dynamic>;
                        var pedidoId = data['id'];
                        return _getPedidoEstado(pedidoId) != '';
                      }).toList();

                      if (filteredOrders.isNotEmpty) {
                        var firstOrder = filteredOrders.first;
                        var data = firstOrder.data() as Map<String, dynamic>;
                        var location = data['ubicacion'] as GeoPoint;
                        _focusedPosition =
                            LatLng(location.latitude, location.longitude);
                      } else if (_currentPosition != null) {
                        _focusedPosition = _currentPosition;
                      }
                    }

                    markers.addAll(_markers);

                    var tileServerData = constantBox.get('270');
                    String tileServerUrl =
                        "http://osmtileserver.riogas.uy/tile";

                    if (tileServerData != null &&
                        tileServerData['Estado'] == 'A') {
                      tileServerUrl = tileServerData['Valor'];
                      print(
                          "✅ URL del servidor de tiles obtenida desde constante: $tileServerUrl");
                    }

                    return FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _focusedPosition ??
                            _currentPosition ??
                            LatLng(0, 0),
                        initialZoom: 15.0,
                        minZoom: 5.0,
                        maxZoom: 18.0,
                        onMapReady: () {
                          print(
                              "🟣 Mapa renderizado. Intentando centrar en ubicación...");
                          if (_focusedPosition != null) {
                            _mapController.move(_focusedPosition!, 15.0);
                          } else if (_currentPosition != null) {
                            _mapController.move(_currentPosition!, 15.0);
                          }
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: "$tileServerUrl/{z}/{x}/{y}.png",
                          tileProvider: FMTCTileProvider(
                            stores: {'mapCache': BrowseStoreStrategy.read},
                            cachedValidDuration:
                                Duration(days: _getTileCacheDays()),
                          ),
                          subdomains: [],
                          additionalOptions: {
                            'User-Agent':
                                'MoveITApp/1.0 (https://moveit.example.com)',
                            'Referer': 'https://moveit.example.com',
                          },
                        ),
                        MarkerLayer(markers: markers),
                      ],
                    );
                  },
                )),
    );
  }
}
