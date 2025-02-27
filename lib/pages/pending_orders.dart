import 'package:flutter/material.dart';
import '../services/firebase_service.dart'; // Asegúrate de usar la ruta correcta
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

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

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
    _ordersStream = _firebaseService.getPedidosStream().asBroadcastStream();
  }

  Future<void> _initializeFirebase() async {
    await _firebaseService.initializeFirebase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<List<DocumentSnapshot>>(
          stream: _ordersStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Text('Pedidos Pendientes (Cargando...)');
            } else if (snapshot.hasError) {
              return Text('Pedidos Pendientes (Error)');
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Text('Pedidos Pendientes (0)');
            } else {
              _orderCount = snapshot.data!.length;
              int newOrderCount = snapshot.data!.where((order) {
                var orderData = order.data() as Map<String, dynamic>?;
                return orderData == null ||
                    !orderData.containsKey('FechaHoraLeido') ||
                    orderData['FechaHoraLeido'] == null;
              }).length;
              return Text('Pedidos ($_orderCount)');
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
                bool isNew = !pedido.containsKey('FechaHoraLeido') ||
                    pedido['FechaHoraLeido'] == null;
                String tipo = pedido['Tipo'] ?? 'Pedido';
                String direccion = pedido['ClienteDireccion'] ?? 'Desconocida';
                String direccionCorta = direccion.length > 20
                    ? direccion.substring(0, 20) + '...'
                    : direccion;

                // Determinar el estado del pedido y la etiqueta correspondiente
                String etiquetaTexto;
                Color etiquetaColor;

                if (isNew) {
                  etiquetaTexto = 'Nuevo';
                  etiquetaColor = Colors.red;
                } else if (pedido['EstadoNro'] == 1 &&
                    pedido['Procesando'] == true) {
                  etiquetaTexto = 'Procesando';
                  etiquetaColor = Colors.lightBlue;
                } else if (pedido['EstadoNro'] == 1 &&
                    pedido['Enviando'] == true) {
                  etiquetaTexto = 'Enviando';
                  etiquetaColor = Colors.orange;
                } else {
                  etiquetaTexto = 'Leido';
                  etiquetaColor = Colors.grey;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 4.0),
                  child: Card(
                    color: isNew ? Colors.lightBlue : Colors.blueGrey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    elevation: 5,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 6.0, vertical: 2.0),
                                decoration: BoxDecoration(
                                  color: etiquetaColor,
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                                child: Text(
                                  etiquetaTexto,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.0,
                                  ),
                                ),
                              ),
                              Spacer(),
                              Row(
                                children: [
                                  if (pedido.containsKey('urlwaze'))
                                    GestureDetector(
                                      onTap: () async {
                                        var url = pedido['urlwaze'];
                                        if (await canLaunch(url)) {
                                          await launch(url);
                                        } else {
                                          throw 'Could not launch $url';
                                        }
                                      },
                                      child: Icon(
                                        Icons.location_on,
                                        color: Colors.white,
                                        size: 20.0,
                                      ),
                                    ),
                                  if (pedido.containsKey('urlwaze'))
                                    SizedBox(
                                        width: 8.0), // Espaciado entre iconos
                                  if (pedido.containsKey('urltelefono'))
                                    GestureDetector(
                                      onTap: () async {
                                        var url =
                                            'tel:${pedido['urltelefono']}';
                                        if (await canLaunch(url)) {
                                          await launch(url);
                                        } else {
                                          throw 'Could not launch $url';
                                        }
                                      },
                                      child: Icon(
                                        Icons.phone,
                                        color: Colors.white,
                                        size: 20.0,
                                      ),
                                    ),
                                  if (pedido.containsKey('urltelefono'))
                                    SizedBox(
                                        width: 8.0), // Espaciado entre iconos
                                  Icon(
                                    tipo == 'Servicio'
                                        ? Icons.build
                                        : Icons.local_shipping,
                                    color: Colors.white,
                                    size: 20.0,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: 4.0),
                          Text(
                            'Número: ${pedido['id'] ?? 'Desconocido'}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 14.0,
                            ),
                          ),
                          SizedBox(height: 4.0),
                          Text(
                            'Dirección: $direccionCorta',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.0,
                            ),
                          ),
                          Text(
                            tipo == 'Pedido'
                                ? 'Servicio: ${pedido['ServicioNombre'] ?? 'Desconocido'}'
                                : 'Defecto: ${pedido['Defecto'] ?? 'Desconocido'}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.0,
                            ),
                          ),
                          Text(
                            'Fecha y Hora: ${_formatTimestamp(pedido['FchHoraPara'])}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.0,
                            ),
                          ),
                        ],
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

  String _formatTimestamp(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate();
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
  }
}
