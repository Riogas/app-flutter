import 'package:flutter/material.dart';
import '../services/firebase_service.dart'; // Asegúrate de usar la ruta correcta
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hive/hive.dart';
import 'order_detail_page.dart'; // Importa la nueva página de detalles
import 'dart:async';
import '../services/riogas_service.dart'; // Import the RioGasService
import 'package:geolocator/geolocator.dart'; // Import Geolocator for getting current location

class PendingOrdersPage extends StatefulWidget {
  @override
  _PendingOrdersPageState createState() => _PendingOrdersPageState();
}

class _PendingOrdersPageState extends State<PendingOrdersPage> {
  final FirebaseService _firebaseService = FirebaseService();
  List<String> _readOrderIds = [];
  int _orderCount = 0;
  int _newOrderCount = 0;
  late Stream<List<DocumentSnapshot>> _ordersStream;
  late Box constantBox;
  late Box pedidosBox;
  late String username = '';
  late String deviceId = '';
  late int movilId = 0;
  late int escenarioId = 0;

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
    _ordersStream = _firebaseService.getPedidosStream().asBroadcastStream();
    _initializeHive().then((_) {
      setState(() {
        username = constantBox.get('username', defaultValue: '');
        deviceId = constantBox.get('DeviceID', defaultValue: '');
        movilId = constantBox.get('MovilID', defaultValue: 0);
        escenarioId = constantBox.get('EscenarioID', defaultValue: 0);
      });
    });
  }

  Future<void> _initializeFirebase() async {
    await _firebaseService.initializeFirebase();
  }

  Future<void> _initializeHive() async {
    constantBox = await Hive.openBox('constantBox');
    pedidosBox = await Hive.openBox('pedidosBox');
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
      var data = constantBox.get(id.toString());
      print("🔍 Leyendo constante con ID $id: $data");
      if (data != null && data['Estado'] == 'A') {
        print("✅ Estado es 'A' para ID $id");
        print(
            "🔢 Comparando delayMinutes: $delayMinutes con ValorMin: ${data['ValorMin']} y ValorMax: ${data['ValorMax']}");
        if ((delayMinutes >= data['ValorMin'] &&
                delayMinutes <= data['ValorMax']) ||
            (delayMinutes <= data['ValorMin'] &&
                delayMinutes >= data['ValorMax'])) {
          print(
              "⏳ Delay $delayMinutes está entre ${data['ValorMin']} y ${data['ValorMax']} para ID $id");
          return {
            "Color": getColorFromName(data['Color']),
            "Etiqueta": data['Etiqueta'],
          };
        } else {
          print(
              "❌ Delay $delayMinutes no está entre ${data['ValorMin']} y ${data['ValorMax']} para ID $id");
        }
      } else {
        print("❌ Estado no es 'A' para ID $id o data es null");
      }
    }
    print("❌ No se encontró un rango válido para delay $delayMinutes");
    return null;
  }

  Future<void> _markAsReadAndNavigate(
      Map<String, dynamic> pedido, int pedidoId) async {
    await pedidosBox.put(pedidoId, 'Leido');
    await _callDescargaLecturaPedidos(pedido, pedidoId);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderDetailPage(
          detalleHtml: pedido['DetalleHTML'],
          estadoNro: pedido['EstadoNro'],
        ),
      ),
    );
    setState(() {}); // Actualiza el estado al volver de la pantalla de detalles
  }

  Future<void> _callDescargaLecturaPedidos(
      Map<String, dynamic> pedido, int pedidoId) async {
    String pedidoTpo = pedido['Tipo'] == 'Pedidos' ? '1' : '2';
    String lectDesc = 'LECTURA';
    String fechaHoraCmbEst = DateTime.now().toIso8601String();
    String inAux1 = '';
    String inAux2 = '';

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    String latitud = position.latitude.toString();
    String longitud = position.longitude.toString();

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

  @override
  Widget build(BuildContext context) {
    if (!Hive.isBoxOpen('pedidosBox')) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Pedidos Pendientes (Cargando...)'),
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
              _orderCount = snapshot.data!.length;
              int newOrderCount = snapshot.data!.where((order) {
                var orderData = order.data() as Map<String, dynamic>?;
                return orderData == null ||
                    !orderData.containsKey('FechaHoraLeido') ||
                    orderData['FechaHoraLeido'] == null;
              }).length;
              return Text('Visitas ($_orderCount)');
            }
          },
        ),
      ),
      body: StreamBuilder<List<DocumentSnapshot>>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('No hay pedidos pendientes.'));
          } else {
            var orders = snapshot.data!;

            return ListView.builder(
              itemCount: orders.length,
              itemBuilder: (context, index) {
                var pedido = orders[index].data() as Map<String, dynamic>;
                int pedidoId = pedido['id'] ?? -1;
                String tipo = pedido['Tipo'] ?? 'Pedidos';
                String direccion = pedido['ClienteDireccion'] ?? 'Desconocida';
                String direccionCorta = direccion.length > 20
                    ? direccion.substring(0, 20) + '...'
                    : direccion;

                // Determinar el estado del pedido y la etiqueta correspondiente
                String etiquetaTexto = '';
                Color etiquetaColor = Colors.transparent;

                var pedidoEstado = pedidosBox.get(pedidoId);
                if (pedidoEstado == null) {
                  etiquetaTexto = 'No Leído';
                  etiquetaColor = Colors.black;
                } else if (pedidoEstado == 'Procesando') {
                  etiquetaTexto = 'Procesando';
                  etiquetaColor = Colors.lightBlue;
                } else if (pedidoEstado == 'Enviando') {
                  etiquetaTexto = 'Enviando';
                  etiquetaColor = Colors.orange;
                }

                // Depuración: imprimir el valor de urltelefono
                if (pedido.containsKey('urltelefono')) {
                  print('urltelefono: ${pedido['urltelefono']}');
                }

                return GestureDetector(
                  onTap: () async {
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
                        horizontal: 8.0, vertical: 4.0),
                    child: Card(
                      color: pedidoEstado == null
                          ? (tipo == 'Services'
                              ? Colors.deepPurpleAccent
                              : Colors.lightBlue)
                          : (tipo == 'Services'
                              ? Colors.deepPurple.withOpacity(0.7)
                              : Colors.blueGrey),
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
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 6.0, vertical: 2.0),
                                  decoration: BoxDecoration(
                                    color: etiquetaColor,
                                    borderRadius: BorderRadius.circular(8.0),
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
                                  'Dirección: $direccionCorta',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.0,
                                  ),
                                ),
                                Spacer(),
                                if (pedido.containsKey('WazeURL'))
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
                                      ? 'Servicio: ${pedido['ServicioNombre'] ?? 'Desconocido'}'
                                      : 'Defecto: ${pedido['Defecto'] ?? 'Desconocido'}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.0,
                                  ),
                                ),
                                Spacer(),
                                if (pedido.containsKey('Precio'))
                                  Text(
                                    'Importe: ${pedido['Precio']}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.0,
                                    ),
                                  ),
                              ],
                            ),
                            if (pedido.containsKey('PedidoObs') &&
                                pedido['PedidoObs'].isNotEmpty)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
            style: TextStyle(
              color: Colors.white,
              fontSize: 12.0,
            ),
          );
        } else {
          int minutesLeft = snapshot.data!;
          var delayInfo = getDelayInfo(minutesLeft);
          return Row(
            children: [
              Text(
                'Min restantes: $minutesLeft',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.0,
                ),
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
}
