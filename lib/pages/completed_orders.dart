import 'package:flutter/material.dart';
import '../services/firebase_service.dart'; // Asegúrate de usar la ruta correcta
import 'package:cloud_firestore/cloud_firestore.dart';
import 'order_detail_page.dart'; // Importa la nueva página de detalles

class CompletedOrdersPage extends StatelessWidget {
  final FirebaseService _firebaseService = FirebaseService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<List<DocumentSnapshot>>(
          stream: _firebaseService.getPedidosCumplidosStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Text('Finalizados (Cargando...)');
            } else if (snapshot.hasError) {
              return Text('Finalizados (Error)');
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Text('Finalizados (0)');
            } else {
              int orderCount = snapshot.data!.length;
              return Text('Finalizados ($orderCount)');
            }
          },
        ),
      ),
      body: StreamBuilder<List<DocumentSnapshot>>(
        stream: _firebaseService.getPedidosCumplidosStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('No hay Finalizados disponibles.'));
          } else {
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                var pedido =
                    snapshot.data![index].data() as Map<String, dynamic>;
                return GestureDetector(
                  onTap: () async {
                    if (pedido.containsKey('DetalleHTML') &&
                        pedido['DetalleHTML'].isNotEmpty) {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OrderDetailPage(
                            detalleHtml: pedido['DetalleHTML'],
                            estadoNro: pedido['EstadoNro'],
                            totalPedido: pedido['Precio'] ??
                                0, // Added the required argument
                            codPedido: pedido['id'],
                            pedidoTipo: pedido['Tipo'],
                          ),
                        ),
                      );
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
                      color: pedido['SubEstadoNro'] == 3
                          ? Colors.green
                          : Colors.orange,
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
                                  'Número: ${pedido['id'] ?? 'Desconocido'}',
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
                                    color: pedido['SubEstadoNro'] == 3
                                        ? Colors.green[800]
                                        : Colors.orange[800],
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  child: Text(
                                    pedido['SubEstadoDesc'] ?? 'Desconocido',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.0,
                                    ),
                                  ),
                                ),
                                Spacer(),
                                Icon(
                                  pedido['Tipo'] == 'Services'
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
                                  'Dirección: ${pedido['ClienteDireccion']?.length > 20 ? pedido['ClienteDireccion'].substring(0, 20) + '...' : pedido['ClienteDireccion'] ?? 'Desconocida'}',
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
                                  pedido['Tipo'] == 'Pedidos'
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

  String _formatTimestamp(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate();
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
  }
}
