import 'package:flutter/material.dart';
import '/firebase_service.dart'; // Asegúrate de usar la ruta correcta
import 'package:cloud_firestore/cloud_firestore.dart';

class PendingOrdersPage extends StatefulWidget {
  @override
  _PendingOrdersPageState createState() => _PendingOrdersPageState();
}

class _PendingOrdersPageState extends State<PendingOrdersPage> {
  final FirebaseService _firebaseService = FirebaseService();
  List<String> _readOrderIds = [];
  int _orderCount = 0;
  late Stream<List<DocumentSnapshot>> _ordersStream;

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
    _ordersStream = _firebaseService.getPedidosStream();
  }

  Future<void> _initializeFirebase() async {
    await _firebaseService.initializeFirebase();
    _listenToPendingOrders();
  }

  void _listenToPendingOrders() {
    _ordersStream.listen((orders) {
      setState(() {
        _checkForNewOrders(orders);
        _orderCount = orders.length;
      });
    });
  }

  void _checkForNewOrders(List<DocumentSnapshot> orders) {
    for (var order in orders) {
      if (!_readOrderIds.contains(order.id)) {
        _readOrderIds.add(order.id);
      }
    }
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
              return Text('Pedidos Pendientes ($_orderCount)');
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
            var newOrders = snapshot.data!.where((order) {
              var orderData = order.data() as Map<String, dynamic>?;
              return orderData == null ||
                  !orderData.containsKey('FechaHoraLeido') ||
                  orderData['FechaHoraLeido'] == null;
            }).toList();

            if (newOrders.isNotEmpty) {
              return ListView.builder(
                itemCount: newOrders.length,
                itemBuilder: (context, index) {
                  var pedido = newOrders[index].data() as Map<String, dynamic>;
                  bool isNew = !pedido.containsKey('FechaHoraLeido') ||
                      pedido['FechaHoraLeido'] == null;
                  String tipo = pedido['Tipo'] ?? 'Pedido';
                  String direccion =
                      pedido['ClienteDireccion'] ?? 'Desconocida';
                  String direccionCorta = direccion.length > 20
                      ? direccion.substring(0, 20) + '...'
                      : direccion;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8.0, vertical: 4.0),
                    child: Card(
                      color: isNew ? Colors.lightBlue : Colors.orange,
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
                                if (isNew)
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 6.0, vertical: 2.0),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                    child: Text(
                                      'Nuevo',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.0,
                                      ),
                                    ),
                                  ),
                                Spacer(),
                                Icon(
                                  tipo == 'Servicio'
                                      ? Icons.build
                                      : Icons.shopping_cart,
                                  color: Colors.white,
                                  size: 20.0,
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
                              'Teléfono: ${pedido['ClienteTel'] ?? 'Desconocido'}',
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
            } else {
              return Center(child: Text('No hay pedidos pendientes.'));
            }
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
