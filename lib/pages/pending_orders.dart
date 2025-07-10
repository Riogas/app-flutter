import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../services/stream_manager.dart'; // Import StreamManager // Asegúrate de usar la ruta correcta
import '../services/pending_orders_diagnostic.dart'; // Add diagnostic import
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hive/hive.dart';
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
  final StreamManager _streamManager = StreamManager(); // Add StreamManager
  List<String> _readOrderIds = [];
  int _orderCount = 0;
  int _newOrderCount = 0;
  late Stream<List<DocumentSnapshot>> _ordersStream;
  late Box constantBox;
  late Box pedidosBox;
  late String username = '';
  late String deviceId = '';
  late Box sesionBox; // Declare the sesionBox variable
  late int movilId = 0;
  late String textoPermisosGPS = '';
  final LocationService locationService =
      LocationService(); // Initialize locationService
  Timer? _hiveStateChecker; // Make it nullable

  @override
  void initState() {
    super.initState();
    print('🔧 PendingOrdersPage: initState() called - Instance: ${hashCode}');
    _initializeFirebase();
    _ordersStream = _streamManager.getPedidosStream();
    print(
        '🔧 PendingOrdersPage: Stream obtained, hashCode: ${_ordersStream.hashCode}');
    _initializeHive().then((_) {
      print('🔧 PendingOrdersPage: Hive initialization completed');
      // Don't call setState here - it causes stream recreation
      username = constantBox.get('username', defaultValue: '');
      deviceId = constantBox.get('DeviceID', defaultValue: '');
      movilId = constantBox.get('MovilID', defaultValue: 0);
      // Remove setState() - not needed since these values aren't used in build()
      // if (mounted) {
      //   setState(() {}); // This was causing StreamBuilder to lose state
      // }
    });

    // Remove problematic Timer that causes unnecessary rebuilds
    // _hiveStateChecker = Timer.periodic(Duration(seconds: 30), (_) {
    //   if (mounted) {
    //     setState(() {}); // This was causing StreamBuilder to lose state
    //   }
    // });
  }

  @override
  void dispose() {
    // Cancel the Timer if it is not null
    _hiveStateChecker?.cancel();
    super.dispose();
  }

  Future<void> _initializeFirebase() async {
    await _firebaseService.initializeFirebase();
  }

  Future<void> _initializeHive() async {
    constantBox = await Hive.openBox('constantBox');
    pedidosBox = await Hive.openBox('pedidosBox');
    sesionBox = await Hive.openBox('sessionBox');
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

    // Realizar operaciones en segundo plano
    Future.microtask(() async {
      try {
        if (pedidosBox.isOpen) {
          var pedidoEstado = pedidosBox.get(pedidoId);
          if (pedidoEstado != 'Leido') {
            await _callDescargaLecturaPedidos(pedido, pedidoId);
            await pedidosBox.put(pedidoId, 'Leido');
          }
        } else {
          debugPrint('⚠️ pedidosBox is not open. Skipping operation.');
        }
      } catch (e, stackTrace) {
        debugPrint('❌ Error in processing pedidoId $pedidoId: $e');
        debugPrint('StackTrace: $stackTrace');
      }
    });

    //if (mounted) {
    //  setState(() {}); // Actualiza el estado solo si el widget sigue montado
    //}
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
    print('🔧 PendingOrdersPage: Stream hashCode: ${_ordersStream.hashCode}');

    if (!Hive.isBoxOpen('pedidosBox')) {
      print('🔧 PendingOrdersPage: pedidosBox not open, showing loading');
      return Scaffold(
        appBar: AppBar(title: Text('Pedidos Pendientes (Cargando...)')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    print('🔧 PendingOrdersPage: Building main scaffold');

    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<List<DocumentSnapshot>>(
          stream: _ordersStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Text('Visitas (Cargando...)');
            } else if (snapshot.hasError) {
              return Text('Visitas (Error)');
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Text('Visitas (0)');
            } else {
              _orderCount = snapshot.data!.where((order) {
                var orderData = order.data() as Map<String, dynamic>?;
                int pedidoId = orderData?['id'] ?? -1;
                var pedidoEstado = pedidosBox.get(pedidoId);
                return pedidoEstado != 'Procesando';
              }).length;

              int newOrderCount = snapshot.data!.where((order) {
                var orderData = order.data() as Map<String, dynamic>?;
                int pedidoId = orderData?['id'] ?? -1;
                var pedidoEstado = pedidosBox.get(pedidoId);
                return (orderData == null ||
                        !orderData.containsKey('FechaHoraLeido') ||
                        orderData['FechaHoraLeido'] == null) &&
                    pedidoEstado != 'Procesando';
              }).length;

              return Text('Visitas ($_orderCount)');
            }
          },
        ),
      ),
      body: StreamBuilder<List<DocumentSnapshot>>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          // Add detailed logging for debugging
          print('🔍 PendingOrders StreamBuilder state:');
          print('   Widget Instance: ${hashCode}');
          print('   Stream hashCode: ${_ordersStream.hashCode}');
          print('   Connection: ${snapshot.connectionState}');
          print('   Has error: ${snapshot.hasError}');
          print('   Has data: ${snapshot.hasData}');
          if (snapshot.hasData) {
            print('   Data length: ${snapshot.data!.length}');
            print(
                '   Sample data: ${snapshot.data!.isNotEmpty ? snapshot.data!.first.id : "no data"}');
          }
          if (snapshot.hasError) {
            print('   Error: ${snapshot.error}');
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Cargando pedidos...'),
                  SizedBox(height: 8),
                  Text(
                      'Si esto toma mucho tiempo, presiona el botón de diagnóstico',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            );
          } else if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text('Error al cargar pedidos'),
                  SizedBox(height: 8),
                  Text('${snapshot.error}', style: TextStyle(fontSize: 12)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      print('🔧 Running diagnostics...');
                      await PendingOrdersDiagnostic
                          .diagnosePendingOrdersIssue();
                    },
                    child: Text('Ejecutar Diagnóstico'),
                  ),
                ],
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No hay pedidos pendientes.'),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      print('🔧 Checking why no orders found...');
                      await PendingOrdersDiagnostic
                          .diagnosePendingOrdersIssue();
                    },
                    child: Text('Verificar Configuración'),
                  ),
                ],
              ),
            );
          } else {
            var orders = snapshot.data!;

            return ListView.builder(
              itemCount: orders.length,
              itemBuilder: (context, index) {
                var pedido = orders[index].data() as Map<String, dynamic>;
                int pedidoId = pedido['id'] ?? -1;

                // Skip rendering the card if the order state is "Procesando"
                if (_getPedidoEstado(pedidoId) == 'Procesando') {
                  return SizedBox.shrink();
                }

                String tipo = pedido['Tipo'] ?? 'Pedidos';
                String direccion = pedido['ClienteDireccion'] ?? 'Desconocida';
                String direccionCorta = direccion.length > 20
                    ? direccion.substring(0, 20) + '...'
                    : direccion;

                // Determinar el estado del pedido y la etiqueta correspondiente
                String etiquetaTexto = _getPedidoEstado(pedidoId);
                Color etiquetaColor = _getPedidoEstadoColor(pedidoId);

                // Depuración: imprimir el valor de urltelefono
                // if (pedido.containsKey('urltelefono')) {
                //   print('urltelefono: ${pedido['urltelefono']}');
                // }

                return GestureDetector(
                  onTap: () async {
                    // Check if GPS is enabled
                    bool isLocationServiceEnabled =
                        await Geolocator.isLocationServiceEnabled();
                    if (!isLocationServiceEnabled) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Por favor, active el GPS para interactuar con los pedidos.',
                          ),
                        ),
                      );
                      return; // Exit if GPS is not enabled
                    }

                    if (pedido.containsKey('DetalleHTML') &&
                        pedido['DetalleHTML'].isNotEmpty) {
                      await _markAsReadAndNavigate(pedido, pedidoId);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('No hay detalles disponibles')),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 4.0,
                    ),
                    child: FutureBuilder<bool>(
                      future: Geolocator.isLocationServiceEnabled(),
                      builder: (context, snapshot) {
                        bool isLocationServiceEnabled = snapshot.data ?? false;
                        if (isLocationServiceEnabled) {
                          textoPermisosGPS = 'Bloqueado - Sin GPS Activado';
                        }
                        // Check for changes in sessionBox for _locationPermissionDenied
                        if (sesionBox.isOpen) {
                          bool locationPermissionDenied = sesionBox.get(
                              '_locationPermissionDenied',
                              defaultValue: true);
                          if (locationPermissionDenied) {
                            isLocationServiceEnabled = false;
                            textoPermisosGPS =
                                'Bloqueado - Sin Permisos de GPS activos.';
                          }
                        }

                        return Card(
                          color: !isLocationServiceEnabled
                              ? Colors.grey // Gray color if GPS is disabled
                              : (_getPedidoEstado(pedidoId) == 'No Leído'
                                  ? (tipo == 'Services'
                                      ? Colors.deepPurpleAccent
                                      : Colors.lightBlue)
                                  : (tipo == 'Services'
                                      ? Colors.deepPurple.withOpacity(0.7)
                                      : Colors.blueGrey)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                          elevation: 5,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                    if (isLocationServiceEnabled)
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 6.0,
                                          vertical: 2.0,
                                        ),
                                        decoration: BoxDecoration(
                                          color: etiquetaColor,
                                          borderRadius: BorderRadius.circular(
                                            8.0,
                                          ),
                                        ),
                                        child: etiquetaTexto.isNotEmpty
                                            ? Text(
                                                etiquetaTexto,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12.0,
                                                ),
                                              )
                                            : SizedBox.shrink(),
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
                                      'Dirección: ${!isLocationServiceEnabled ? textoPermisosGPS : direccionCorta}',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.0,
                                      ),
                                    ),
                                    Spacer(),
                                    if (isLocationServiceEnabled &&
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
                                          ? 'Servicio: ${!isLocationServiceEnabled ? textoPermisosGPS : (pedido['ServicioNombre'] ?? 'Desconocido')}'
                                          : 'Defecto: ${!isLocationServiceEnabled ? textoPermisosGPS : (pedido['Defecto'] ?? 'Desconocido')}',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.0,
                                      ),
                                    ),
                                    Spacer(),
                                    if (isLocationServiceEnabled &&
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
                                if (isLocationServiceEnabled &&
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
                                if (isLocationServiceEnabled)
                                  Row(
                                    children: [
                                      _buildMinutesLeftStream(pedido),
                                      SizedBox(width: 8.0),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            );
          }
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

  Color _getPedidoEstadoColor(int pedidoId) {
    var pedidoEstado = pedidosBox.get(pedidoId);
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
