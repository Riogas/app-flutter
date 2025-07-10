import 'package:flutter/material.dart';
import '../services/stream_manager.dart';
import '../services/pending_orders_diagnostic.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

/// Simplified PendingOrders page for debugging stream issues
class PendingOrdersDebugPage extends StatefulWidget {
  @override
  _PendingOrdersDebugPageState createState() => _PendingOrdersDebugPageState();
}

class _PendingOrdersDebugPageState extends State<PendingOrdersDebugPage> {
  final StreamManager _streamManager = StreamManager();
  late Stream<List<DocumentSnapshot>> _ordersStream;
  @override
  void initState() {
    super.initState();
    print('🔍 Debug: Initializing PendingOrdersDebugPage');

    // 🔧 RESET STREAMMANAGER TO FORCE NEW STREAM CREATION
    print('🔄 Debug: Resetting StreamManager to fix zombie stream');
    _streamManager.dispose(); // Force cleanup of existing streams

    // Run prerequisites check
    _checkPrerequisites();

    // Initialize stream AFTER reset
    print('🔄 Debug: Creating fresh stream after reset');
    _ordersStream = _streamManager.getPedidosStream();
    print('✅ Debug: Stream initialized');
  }

  Future<void> _checkPrerequisites() async {
    print('🔍 Debug: Checking prerequisites...');
    await StreamManager.debugPedidosPrerequisites();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pedidos Debug'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () async {
              print('🔄 Debug: Manual refresh triggered');
              await PendingOrdersDiagnostic.diagnosePendingOrdersIssue();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Status Card
          Card(
            margin: EdgeInsets.all(8),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Estado del Sistema:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  _buildStatusRow('SessionBox', Hive.isBoxOpen('sessionBox')),
                  _buildStatusRow('PedidosBox', Hive.isBoxOpen('pedidosBox')),
                  _buildStreamManagerInfo(),
                ],
              ),
            ),
          ),

          // Stream Content
          Expanded(
            child: StreamBuilder<List<DocumentSnapshot>>(
              stream: _ordersStream,
              builder: (context, snapshot) {
                print('🔍 Debug StreamBuilder: ${snapshot.connectionState}');
                print('   Has error: ${snapshot.hasError}');
                print('   Has data: ${snapshot.hasData}');
                if (snapshot.hasData) {
                  print('   Data count: ${snapshot.data!.length}');
                }
                if (snapshot.hasError) {
                  print('   Error: ${snapshot.error}');
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingWidget();
                } else if (snapshot.hasError) {
                  return _buildErrorWidget(snapshot.error.toString());
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return _buildEmptyWidget();
                } else {
                  return _buildDataWidget(snapshot.data!);
                }
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Reset StreamManager button
          FloatingActionButton(
            heroTag: "reset",
            onPressed: () async {
              print('🔄 Debug: Manual StreamManager reset');

              // Reset StreamManager
              _streamManager.dispose();

              // Wait a moment
              await Future.delayed(Duration(milliseconds: 500));

              // Recreate stream
              setState(() {
                _ordersStream = _streamManager.getPedidosStream();
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'StreamManager reseteado - Probando nuevo stream')),
              );
            },
            child: Icon(Icons.refresh),
            tooltip: 'Resetear StreamManager',
            backgroundColor: Colors.orange,
          ),
          SizedBox(height: 8),
          // Diagnostic button
          FloatingActionButton(
            heroTag: "diagnostic",
            onPressed: () async {
              print('🔧 Debug: Running comprehensive diagnostic');
              await PendingOrdersDiagnostic.diagnosePendingOrdersIssue();
              PendingOrdersDiagnostic.printQuickFixes();

              // Also print StreamManager status
              StreamManager.debug();
            },
            child: Icon(Icons.bug_report),
            tooltip: 'Diagnóstico Completo',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, bool status) {
    return Row(
      children: [
        Icon(
          status ? Icons.check_circle : Icons.error,
          color: status ? Colors.green : Colors.red,
          size: 16,
        ),
        SizedBox(width: 8),
        Text('$label: ${status ? "OK" : "ERROR"}'),
      ],
    );
  }

  Widget _buildStreamManagerInfo() {
    final debugInfo = _streamManager.getDebugInfo();
    final listeners = debugInfo['listeners']['pedidos'] ?? 0;
    final reads = debugInfo['reads']['pedidos'] ?? 0;
    final active = debugInfo['activeStreams']['pedidos'] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 8),
        Text('StreamManager:', style: TextStyle(fontWeight: FontWeight.bold)),
        _buildStatusRow('Stream Activo', active),
        Text('  Listeners: $listeners'),
        Text('  Reads: $reads'),
      ],
    );
  }

  Widget _buildLoadingWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Cargando pedidos...'),
          SizedBox(height: 16),
          Text('Tiempo de espera:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          StreamBuilder(
            stream: Stream.periodic(Duration(seconds: 1), (i) => i),
            builder: (context, snapshot) {
              int seconds = snapshot.data ?? 0;
              return Text('${seconds}s');
            },
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              await PendingOrdersDiagnostic.diagnosePendingOrdersIssue();
            },
            child: Text('Ejecutar Diagnóstico'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text('Error en el Stream',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                await PendingOrdersDiagnostic.diagnosePendingOrdersIssue();
              },
              child: Text('Diagnosticar Error'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('No hay pedidos'),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              print('🔍 Checking why no orders...');
              await PendingOrdersDiagnostic.diagnosePendingOrdersIssue();
            },
            child: Text('¿Por qué no hay pedidos?'),
          ),
        ],
      ),
    );
  }

  Widget _buildDataWidget(List<DocumentSnapshot> orders) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          color: Colors.green.shade100,
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text(
                  '✅ Stream funcionando: ${orders.length} pedidos encontrados'),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;

              return ListTile(
                title: Text('Pedido ${data['id'] ?? 'Sin ID'}'),
                subtitle: Text('Cliente: ${data['ClienteNombre'] ?? 'N/A'}'),
                trailing: Text('${data['Movil'] ?? 'N/A'}'),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Datos del Pedido'),
                      content: SingleChildScrollView(
                        child: Text(data.toString()),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Cerrar'),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
