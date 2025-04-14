import 'package:flutter/material.dart';
import '../services/firebase_service.dart'; // Asegúrate de usar la ruta correcta
import 'package:geolocator/geolocator.dart'; // Import Geolocator package
import 'package:cloud_firestore/cloud_firestore.dart';
import 'order_detail_page.dart'; // Importa la nueva página de detalles
import '../utils/constantes.dart'; // Importa la función getConstantValue
import 'dart:async'; // Importa para usar StreamController
import 'package:flutter/scheduler.dart';

class CompletedOrdersPage extends StatefulWidget {
  @override
  _CompletedOrdersPageState createState() => _CompletedOrdersPageState();
}

class _CompletedOrdersPageState extends State<CompletedOrdersPage> {
  final FirebaseService _firebaseService = FirebaseService();
  final StreamController<bool> _gpsStreamController =
      StreamController<bool>.broadcast();

  @override
  void initState() {
    super.initState();
    _startGpsListener();
  }

  void _startGpsListener() {
    Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      _gpsStreamController.add(status == ServiceStatus.enabled);
    });
  }

  Stream<bool> get gpsStream => _gpsStreamController.stream;

  Future<bool> _isGpsEnabled(BuildContext context) async {
    try {
      bool isLocationServiceEnabled =
          await Geolocator.isLocationServiceEnabled();
      if (!isLocationServiceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Por favor, active el GPS para continuar.')),
        );
        return false;
      }
      return true;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al verificar el estado del GPS: $e')),
      );
      return false;
    }
  }

  Future<String> _getConstantValue(String key) async {
    return await getConstantValue(key) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: gpsStream,
      builder: (context, snapshot) {
        if (snapshot.hasData && !snapshot.data!) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('El GPS está desactivado. Por favor, actívelo.'),
              ),
            );
          });
          return _buildBlockedView();
        }

        return FutureBuilder<bool>(
          future: _isGpsEnabled(context),
          builder: (context, gpsSnapshot) {
            if (!gpsSnapshot.hasData || !gpsSnapshot.data!) {
              return _buildBlockedView();
            }

            return FutureBuilder<String>(
              future: _getConstantValue('150'),
              builder: (context, constant150Snapshot) {
                if (!constant150Snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }

                String constant150 = constant150Snapshot.data!;
                return FutureBuilder<String>(
                  future: _getConstantValue('151'),
                  builder: (context, constant151Snapshot) {
                    if (!constant151Snapshot.hasData) {
                      return Center(child: CircularProgressIndicator());
                    }

                    String constant151 = constant151Snapshot.data!;
                    return _buildMainView(context, constant150, constant151);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _gpsStreamController.close();
    super.dispose();
  }

  Widget _buildBlockedView() {
    return Scaffold(
      appBar: AppBar(title: Text('Finalizados (Bloqueado)')),
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
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 4.0),
                  child: Card(
                    color: Colors.grey, // Set all cards to gray
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
                              Spacer(),
                              Icon(
                                Icons.lock, // Indicate blocked state
                                color: Colors.white,
                                size: 20.0,
                              ),
                            ],
                          ),
                          SizedBox(height: 4.0),
                          Text(
                            'Datos bloqueados',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.0,
                            ),
                          ),
                          SizedBox(height: 4.0),
                          Row(
                            children: [
                              Text(
                                'Finalizado por: Datos bloqueados',
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
                );
              },
            );
          }
        },
      ),
    );
  }

  Widget _buildMainView(
      BuildContext context, String constant150, String constant151) {
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
                bool canAccessDetails = constant150 == 'S';
                bool showAddress = constant151 == 'S';
                return GestureDetector(
                  onTap: canAccessDetails
                      ? () async {
                          if (pedido.containsKey('DetalleHTML') &&
                              pedido['DetalleHTML'].isNotEmpty) {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => OrderDetailPage(
                                  detalleHtml: pedido['DetalleHTML'],
                                  estadoNro: pedido['EstadoNro'],
                                  totalPedido: pedido['Precio'] ?? 0,
                                  codPedido: pedido['id'],
                                  pedidoTipo: pedido['Tipo'],
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('No hay detalles disponibles')),
                            );
                          }
                        }
                      : null,
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
                            if (showAddress)
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
                            SizedBox(height: 4.0),
                            if (pedido.containsKey('FinalizadoPor') &&
                                pedido['FinalizadoPor'] != null &&
                                pedido['FinalizadoPor'].isNotEmpty)
                              Row(
                                children: [
                                  Text(
                                    'Finalizado por: ${pedido['FinalizadoPor']}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.0,
                                    ),
                                  ),
                                ],
                              ),
                            if (pedido.containsKey('FchHoraCumplido'))
                              SizedBox(height: 4.0),
                            if (pedido.containsKey('FchHoraCumplido'))
                              Row(
                                children: [
                                  Text(
                                    'Finalizado: ${_formatTimestamp(pedido['FchHoraCumplido'])}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.0,
                                    ),
                                  ),
                                ],
                              ),
                            if (pedido.containsKey('ObsCumpFletero') &&
                                pedido['ObsCumpFletero'] != null &&
                                pedido['ObsCumpFletero'].isNotEmpty)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(height: 4.0),
                                  Text(
                                    'Observaciones: ${pedido['ObsCumpFletero']}',
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
