import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../services/persistent_stream_manager.dart';
import '../services/pending_orders_diagnostic.dart'; // Add diagnostic import
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'order_detail_page.dart'; // Importa la nueva página de detalles
import 'dart:async';
import '../services/riogas_service.dart'; // Import the RioGasService
import 'package:geolocator/geolocator.dart'; // Import Geolocator for getting current location
import '../services/location_service.dart'; // Import your location service

class PendingOrdersPage extends StatefulWidget {
  @override
  _PendingOrdersPageState createState() => _PendingOrdersPageState();
}

class _PendingOrdersPageState extends State<PendingOrdersPage> {
  final FirebaseService _firebaseService = FirebaseService();
  final PersistentStreamManager _streamManager = PersistentStreamManager();
  List<String> _readOrderIds = [];
  int _orderCount = 0;
  int _newOrderCount = 0;
  late Stream<List<DocumentSnapshot>> _ordersStream;
  late Box constantBox;
  Box? pedidosBox;
  late String username = '';
  late String deviceId = '';
  late Box sesionBox; // Declare the sesionBox variable
  late int movilId = 0;
  late String textoPermisosGPS = '';
  final LocationService locationService =
      LocationService(); // Initialize locationService
  Timer? _hiveStateChecker; // Make it nullable
  // Notificador para el estado del GPS
  final ValueNotifier<bool> _gpsEnabledNotifier = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    print('🔧 PendingOrdersPage: initState() called - Instance: ${hashCode}');
    _initializeFirebase();
    _initializeHive().then((_) {
      print('🔧 PendingOrdersPage: Hive initialization completed');
      username = constantBox.get('username', defaultValue: '');
      deviceId = constantBox.get('DeviceID', defaultValue: '');
      movilId = constantBox.get('MovilID', defaultValue: 0);
    });
    _initPersistentStreams();
    _initGpsListener();
  }

  void _initGpsListener() {
    // Estado inicial
    Geolocator.isLocationServiceEnabled().then((enabled) {
      _gpsEnabledNotifier.value = enabled;
    });
    // Escucha cambios en el servicio de ubicación
    Geolocator.getServiceStatusStream().listen((status) async {
      bool enabled = status == ServiceStatus.enabled;
      _gpsEnabledNotifier.value = enabled;
    });
  }

  Future<void> _initPersistentStreams() async {
    await _streamManager.initialize();
    print('🔄 [PendingOrdersPage] PersistentStreamManager initialized');
    // No need to add a listener here, as the stream manager handles it);
  }

  @override
  void dispose() {
    print('🔴 PendingOrdersPage: dispose() called - Instance: ${hashCode}');
    // Cancel the Timer if it is not null
    _hiveStateChecker?.cancel();
    // Decrementa el contador de listeners de pedidos
    _streamManager.removeListener('pedidos');
    super.dispose();
  }

  Future<void> _initializeFirebase() async {
    await _firebaseService.initializeFirebase();
  }

  Future<void> _initializeHive() async {
    constantBox = await Hive.openBox('constantBox');
    final box = await Hive.openBox('pedidosBox');
    setState(() {
      pedidosBox = box;
    });
    sesionBox = await Hive.openBox('sessionBox');
    // Ya no es necesario inicializar ni sincronizar pedidosBox aquí, la lógica está centralizada en PersistentStreamManager
  }

  Map<String, Color> colorMap = {
    "Red": Colors.red,
    "Pink": Colors.pink,
    "Green": Colors.green,
    "Yellow": Colors.orange,
    // Agrega más colores según sea necesario
  };

  Color getColorFromName(String colorName) {
    return colorMap[colorName] ??
        Colors.white; // Devuelve blanco si el color no se encuentra
  }

  Map<String, dynamic>? getDelayInfo(int delayMinutes) {
    for (int id in [40, 41, 42, 43]) {
      if (constantBox.isOpen) {
        var data = constantBox.get(id.toString());
        // print("🔍 Leyendo constante con ID $id: $data");
        if (data != null && data['Estado'] == 'A') {
          // print("✅ Estado es 'A' para ID $id");
          // print(
          //   "🔢 Comparando delayMinutes: $delayMinutes con ValorMin: ${data['ValorMin']} y ValorMax: ${data['ValorMax']}",
          // );
          if ((delayMinutes >= data['ValorMin'] &&
                  delayMinutes <= data['ValorMax']) ||
              (delayMinutes <= data['ValorMin'] &&
                  delayMinutes >= data['ValorMax'])) {
            // print(
            //   "⏳ Delay $delayMinutes está entre ${data['ValorMin']} y ${data['ValorMax']} para ID $id",
            // );
            return {
              "Color": getColorFromName(data['Color']),
              "Etiqueta": data['Etiqueta'],
            };
          } else {
            // print(
            //   "❌ Delay $delayMinutes no está entre ${data['ValorMin']} y ${data['ValorMax']} para ID $id",
            // );
          }
        } else {
          // print("❌ Estado no es 'A' para ID $id o data es null");
        }
      } else {
        // print("⚠️ constantBox is closed. Skipping data retrieval for ID $id.");
      }
    }
    // print("❌ No se encontró un rango válido para delay $delayMinutes");
    return null;
  }

  Future<void> _markAsReadAndNavigate(
    Map<String, dynamic> pedido,
    int pedidoId,
  ) async {
    // Check if GPS is enabled
    bool isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationServiceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Por favor, active el GPS para continuar.')),
      );
      return; // Exit the function if GPS is not enabled
    }

    // Marcar como leído en Hive antes de navegar
    if (pedidosBox != null) {
      await pedidosBox!.put(pedidoId, 'Leído');
    }

    // Navegar inmediatamente
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderDetailPage(
          detalleHtml: pedido['DetalleHTML'],
          estadoNro: pedido['EstadoNro'],
          totalPedido: pedido['Precio'] ?? 0,
          codPedido: pedidoId,
          pedidoTipo: pedido['Tipo'],
          ubicacion:
              pedido.containsKey('ubicacion') && pedido['ubicacion'] is GeoPoint
                  ? pedido['ubicacion'] as GeoPoint
                  : null,
        ),
      ),
    );
    // La lógica de marcar como leído y sincronizar con Hive está centralizada en PersistentStreamManager
    // Si necesitas lógica adicional, implementa solo la llamada a RioGasService aquí si corresponde
  }

  Future<void> _callDescargaLecturaPedidos(
    Map<String, dynamic> pedido,
    int pedidoId,
  ) async {
    String pedidoTpo = pedido['Tipo'] == 'Pedidos' ? 'PEDIDOS' : 'SERVICES';
    String lectDesc = 'LECTURA';
    String fechaHoraCmbEst = DateTime.now().toUtc().toIso8601String();

    var box = await Hive.openBox('sessionBox');
    String deviceId = box.get('deviceId');
    String movilid = box.get('movil');
    int escenarioId = int.tryParse(box.get('escenario').toString()) ?? 0;
    String username = box.get('username');

    String inAux1 = movilid;
    String inAux2 = '';

    String latitud = '0.0';
    String longitud = '0.0';
    String utmx = '0.0';
    String utmy = '0.0';

    // Invoca el método para obtener la ubicación
    final locationData = await locationService.getCurrentLocation();

    if (locationData != null) {
      latitud = locationData['latitude'].toString();
      longitud = locationData['longitude'].toString();
      utmx = locationData['utmX'].toString();
      utmy = locationData['utmY'].toString();
    }

    // Retrieve speed and distance from Hive
    var locationBox = await Hive.openBox('locationBox');
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
        movilid,
        inAux2,
        latitud,
        longitud,
        utmx,
        utmy,
        velocidad, // Pass speed from Hive
        distanciaRecorrida // Pass distance from Hive
        );
  }

  @override
  Widget build(BuildContext context) {
    print('🔧 PendingOrdersPage: build() called - Instance: ${hashCode}');

    if (pedidosBox == null) {
      print(
          '🔧 PendingOrdersPage: pedidosBox not initialized, showing loading');
      return Scaffold(
        appBar: AppBar(title: Text('Pedidos Pendientes (Cargando...)')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    print('🔧 PendingOrdersPage: Building main scaffold');

    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<List<DocumentSnapshot>>(
          valueListenable: _streamManager.pedidosNotifier,
          builder: (context, pedidos, child) {
            final count = pedidos.where((order) {
              var orderData = order.data() as Map<String, dynamic>?;
              int pedidoId = orderData?['id'] ?? -1;
              var pedidoEstado = pedidosBox!.get(pedidoId);
              return pedidoEstado != 'Procesando';
            }).length;
            return Text('Visitas ($count)');
          },
        ),
      ),
      body: pedidosBox == null
          ? Center(child: CircularProgressIndicator())
          : ValueListenableBuilder(
              valueListenable:
                  (Hive.box('pedidosBox') as Box<dynamic>).listenable(),
              builder: (context, box, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _gpsEnabledNotifier,
                  builder: (context, isLocationServiceEnabled, _) {
                    return ValueListenableBuilder<List<DocumentSnapshot>>(
                      valueListenable: _streamManager.pedidosNotifier,
                      builder: (context, pedidos, child) {
                        // Add detailed logging for debugging
                        print('🔍 PendingOrders pedidosNotifier state:');
                        print('   Widget Instance: ${hashCode}');
                        print('   Has data: ${pedidos.isNotEmpty}');
                        if (pedidos.isNotEmpty) {
                          print('   Data length: ${pedidos.length}');
                          print(
                              '   Sample data: ${pedidos.isNotEmpty ? pedidos.first.id : "no data"}');
                        }

                        if (pedidos.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text('No hay pedidos pendientes.'),
                                SizedBox(height: 16),
                              ],
                            ),
                          );
                        } else {
                          var orders = pedidos;

                          return ListView.builder(
                            itemCount: orders.length,
                            itemBuilder: (context, index) {
                              var pedido =
                                  orders[index].data() as Map<String, dynamic>;
                              int pedidoId = pedido['id'] ?? -1;

                              // Skip rendering the card if the order state is "Procesando"
                              if (_getPedidoEstado(pedidoId) == 'Procesando') {
                                return SizedBox.shrink();
                              }

                              String tipo = pedido['Tipo'] ?? 'Pedidos';
                              String direccion =
                                  pedido['ClienteDireccion'] ?? 'Desconocida';
                              String direccionCorta = direccion.length > 20
                                  ? direccion.substring(0, 20) + '...'
                                  : direccion;
                              // Determinar el estado del pedido y la etiqueta correspondiente
                              String etiquetaTexto = _getPedidoEstado(pedidoId);
                              Color etiquetaColor =
                                  _getPedidoEstadoColor(pedidoId);

                              // Excluir mostrar la etiqueta si el estado es 'Leído' o 'No Leído'
                              bool mostrarEtiqueta = etiquetaTexto != 'Leído' &&
                                  etiquetaTexto != 'No Leído' &&
                                  etiquetaTexto.isNotEmpty;

                              // Check for cambios en sessionBox para _locationPermissionDenied
                              bool locationPermissionDenied = false;
                              if (sesionBox.isOpen) {
                                locationPermissionDenied = sesionBox.get(
                                    '_locationPermissionDenied',
                                    defaultValue: true);
                              }
                              bool cardBlocked = !isLocationServiceEnabled ||
                                  locationPermissionDenied;
                              if (cardBlocked) {
                                textoPermisosGPS = locationPermissionDenied
                                    ? 'Bloqueado - Sin Permisos de GPS activos.'
                                    : 'Bloqueado - Sin GPS Activado';
                              }

                              return GestureDetector(
                                onTap: () async {
                                  if (cardBlocked) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Por favor, active el GPS y los permisos para interactuar con los pedidos.'),
                                      ),
                                    );
                                    return;
                                  }

                                  if (pedido.containsKey('DetalleHTML') &&
                                      pedido['DetalleHTML'].isNotEmpty) {
                                    await _markAsReadAndNavigate(
                                        pedido, pedidoId);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'No hay detalles disponibles')),
                                    );
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0, vertical: 4.0),
                                  child: Card(
                                    color: cardBlocked
                                        ? Colors
                                            .grey // Gray color if GPS is disabled
                                        : (_getPedidoEstado(pedidoId) ==
                                                'No Leído'
                                            ? (tipo == 'Services'
                                                ? Colors.deepPurpleAccent
                                                : Colors.lightBlue)
                                            : (tipo == 'Services'
                                                ? Colors.deepPurple
                                                    .withOpacity(0.7)
                                                : Colors.blueGrey)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10.0),
                                    ),
                                    elevation: 5,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(height: 4.0),
                                          Row(
                                            children: [
                                              Text(
                                                'Número: $pedidoId',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  fontSize: 14.0,
                                                ),
                                              ),
                                              SizedBox(width: 8.0),
                                              if (!cardBlocked &&
                                                  mostrarEtiqueta)
                                                Container(
                                                  padding: EdgeInsets.symmetric(
                                                      horizontal: 6.0,
                                                      vertical: 2.0),
                                                  decoration: BoxDecoration(
                                                    color: etiquetaColor,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8.0),
                                                  ),
                                                  child: Text(
                                                    etiquetaTexto,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12.0,
                                                    ),
                                                  ),
                                                ),
                                              Spacer(),
                                              Icon(
                                                tipo == 'Services'
                                                    ? Icons.build
                                                    : Icons.local_shipping,
                                                color: Colors.white,
                                                size: 20.0,
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 4.0),
                                          Row(
                                            children: [
                                              Text(
                                                'Dirección: ${cardBlocked ? textoPermisosGPS : direccionCorta}',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12.0,
                                                ),
                                              ),
                                              Spacer(),
                                              if (!cardBlocked &&
                                                  pedido.containsKey('WazeURL'))
                                                Container(
                                                  child: Icon(
                                                    Icons.location_on,
                                                    color: Colors.white,
                                                    size: 20.0,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          SizedBox(height: 4.0),
                                          Row(
                                            children: [
                                              Text(
                                                tipo == 'Pedidos'
                                                    ? 'Servicio: ${cardBlocked ? textoPermisosGPS : (pedido['ServicioNombre'] ?? 'Desconocido')}'
                                                    : 'Defecto: ${cardBlocked ? textoPermisosGPS : (pedido['Defecto'] ?? 'Desconocido')}',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12.0,
                                                ),
                                              ),
                                              Spacer(),
                                              if (!cardBlocked &&
                                                  pedido.containsKey('Precio'))
                                                Text(
                                                  'Importe: ${pedido['Precio']}',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12.0,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          if (!cardBlocked &&
                                              pedido.containsKey('PedidoObs') &&
                                              pedido['PedidoObs'].isNotEmpty)
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(height: 4.0),
                                                Text(
                                                  'Observaciones: ${pedido['PedidoObs']}',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12.0,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          SizedBox(height: 4.0),
                                          if (!cardBlocked)
                                            Row(
                                              children: [
                                                _buildMinutesLeftStream(pedido),
                                                SizedBox(width: 8.0),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        }
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildMinutesLeftStream(Map<String, dynamic> pedido) {
    final StreamController<int> controller = StreamController<int>();
    DateTime now = DateTime.now();
    DateTime fchHoraPara = (pedido['FchHoraMaxEntComp'] as Timestamp).toDate();
    controller.add(fchHoraPara.difference(now).inMinutes);

    Timer.periodic(Duration(minutes: 1), (_) {
      now = DateTime.now();
      controller.add(fchHoraPara.difference(now).inMinutes);
    });

    return StreamBuilder<int>(
      stream: controller.stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Text(
            'Calculando...',
            style: TextStyle(color: Colors.white, fontSize: 12.0),
          );
        } else {
          int minutesLeft = snapshot.data!;
          var delayInfo = getDelayInfo(minutesLeft);
          return Row(
            children: [
              Text(
                'Min restantes: $minutesLeft',
                style: TextStyle(color: Colors.white, fontSize: 12.0),
              ),
              SizedBox(width: 8.0),
              if (delayInfo != null)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: delayInfo["Color"],
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Text(
                    delayInfo["Etiqueta"],
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.0,
                    ),
                  ),
                ),
            ],
          );
        }
      },
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate();
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
  }

  String _getPedidoEstado(int pedidoId) {
    if (pedidosBox == null) return '';
    var pedidoEstado = pedidosBox!.get(pedidoId);
    if (pedidoEstado == null) {
      return 'No Leído';
    }
    return pedidoEstado.toString();
  }

  Color _getPedidoEstadoColor(int pedidoId) {
    if (pedidosBox == null) return Colors.transparent;
    var pedidoEstado = pedidosBox!.get(pedidoId);
    if (pedidoEstado == null) {
      return Colors.black;
    } else if (pedidoEstado == 'Procesando') {
      return Colors.lightBlue;
    } else if (pedidoEstado == 'Enviando') {
      return Colors.orange;
    }
    return Colors.transparent;
  }
}
