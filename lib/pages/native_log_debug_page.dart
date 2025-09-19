import 'package:flutter/material.dart';
import '../services/native_log_sync_service.dart';
import 'dart:convert';

/// Widget de debugging para monitorear logs nativos y estado del servicio
class NativeLogDebugPage extends StatefulWidget {
  @override
  _NativeLogDebugPageState createState() => _NativeLogDebugPageState();
}

class _NativeLogDebugPageState extends State<NativeLogDebugPage> {
  Map<String, dynamic>? serviceStatus;
  Map<String, dynamic>? logStatistics;
  List<Map<String, dynamic>> recentLogs = [];
  bool isLoading = true;
  String selectedLogType = 'all';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);

    try {
      // Obtener estado del servicio
      serviceStatus = await NativeLogSyncService.getServiceStatus();

      // Obtener estadísticas de logs
      logStatistics = NativeLogSyncService.getLogStatistics();

      // Obtener logs recientes
      recentLogs = NativeLogSyncService.getRecentLogs(
          limit: 100, type: selectedLogType == 'all' ? null : selectedLogType);
    } catch (e) {
      print('Error cargando datos de debug: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Debug: Logs Nativos'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'sync':
                  await _forceSyncLogs();
                  break;
                case 'cleanup':
                  await _cleanupLogs();
                  break;
                case 'export':
                  await _exportLogs();
                  break;
                case 'reactivate':
                  await _reactivateService();
                  break;
                case 'stop':
                  await _stopService();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'sync', child: Text('🔄 Forzar Sync')),
              PopupMenuItem(value: 'cleanup', child: Text('🧹 Limpiar Logs')),
              PopupMenuItem(value: 'export', child: Text('📤 Exportar')),
              PopupMenuItem(
                  value: 'reactivate', child: Text('▶️ Reactivar Servicio')),
              PopupMenuItem(value: 'stop', child: Text('🛑 Detener Servicio')),
            ],
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildServiceStatusCard(),
                    SizedBox(height: 16),
                    _buildLogStatisticsCard(),
                    SizedBox(height: 16),
                    _buildLogFilterCard(),
                    SizedBox(height: 16),
                    _buildRecentLogsCard(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildServiceStatusCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Estado del Servicio',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            if (serviceStatus != null) ...[
              _buildStatusRow('Deshabilitado',
                  serviceStatus!['disabled']?.toString() ?? 'false'),
              _buildStatusRow('Razón de parada',
                  serviceStatus!['stopReason']?.toString() ?? 'N/A'),
              _buildStatusRow('Parada automática',
                  serviceStatus!['autoStopped']?.toString() ?? 'false'),
              if (serviceStatus!['stopTimestamp'] != null &&
                  serviceStatus!['stopTimestamp'] != 0)
                _buildStatusRow('Hora de parada',
                    _formatTimestamp(serviceStatus!['stopTimestamp'])),
              if (serviceStatus!['reactivationTimestamp'] != null &&
                  serviceStatus!['reactivationTimestamp'] != 0)
                _buildStatusRow('Última reactivación',
                    _formatTimestamp(serviceStatus!['reactivationTimestamp'])),
            ] else
              Text('Error cargando estado del servicio'),
          ],
        ),
      ),
    );
  }

  Widget _buildLogStatisticsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Estadísticas de Logs',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            if (logStatistics != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn('Eventos',
                      logStatistics!['events']?.toString() ?? '0', Colors.blue),
                  _buildStatColumn('Errores',
                      logStatistics!['errors']?.toString() ?? '0', Colors.red),
                  _buildStatColumn(
                      'Métricas',
                      logStatistics!['metrics']?.toString() ?? '0',
                      Colors.green),
                  _buildStatColumn(
                      'Total',
                      logStatistics!['totalEntries']?.toString() ?? '0',
                      Colors.orange),
                ],
              ),
            ] else
              Text('Error cargando estadísticas'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildLogFilterCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filtrar Logs',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            DropdownButton<String>(
              value: selectedLogType,
              isExpanded: true,
              items: [
                DropdownMenuItem(
                    value: 'all', child: Text('🔍 Todos los logs')),
                DropdownMenuItem(
                    value: 'event', child: Text('📝 Solo eventos')),
                DropdownMenuItem(
                    value: 'error', child: Text('🚨 Solo errores')),
                DropdownMenuItem(
                    value: 'metric', child: Text('📊 Solo métricas')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => selectedLogType = value);
                  _loadData();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentLogsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Logs Recientes (${recentLogs.length})',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            if (recentLogs.isNotEmpty)
              Container(
                height: 400,
                child: ListView.separated(
                  itemCount: recentLogs.length,
                  separatorBuilder: (context, index) => Divider(),
                  itemBuilder: (context, index) {
                    final log = recentLogs[index];
                    return _buildLogEntry(log);
                  },
                ),
              )
            else
              Text('No hay logs para mostrar'),
          ],
        ),
      ),
    );
  }

  Widget _buildLogEntry(Map<String, dynamic> log) {
    final type = log['type'] ?? 'unknown';
    final timestamp = log['timestamp'] ?? 0;
    final dateStr = log['dateStr'] ?? _formatTimestamp(timestamp);

    Color backgroundColor;
    IconData icon;

    switch (type) {
      case 'event':
        backgroundColor = Colors.blue.withOpacity(0.1);
        icon = Icons.info_outline;
        break;
      case 'error':
        backgroundColor = Colors.red.withOpacity(0.1);
        icon = Icons.error_outline;
        break;
      case 'metric':
        backgroundColor = Colors.green.withOpacity(0.1);
        icon = Icons.location_on;
        break;
      default:
        backgroundColor = Colors.grey.withOpacity(0.1);
        icon = Icons.help_outline;
    }

    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        leading: Icon(icon, color: _getColorForType(type)),
        title: Text(
          _getLogTitle(log),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(dateStr),
        children: [
          Padding(
            padding: EdgeInsets.all(8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _getLogDetails(log),
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'event':
        return Colors.blue;
      case 'error':
        return Colors.red;
      case 'metric':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getLogTitle(Map<String, dynamic> log) {
    final type = log['type'] ?? 'unknown';

    switch (type) {
      case 'event':
        return '📝 ${log['eventType'] ?? 'Unknown Event'}';
      case 'error':
        return '🚨 ${log['errorType'] ?? 'Unknown Error'}';
      case 'metric':
        return '📊 Ubicación (${log['provider'] ?? 'unknown'})';
      default:
        return '❓ Log desconocido';
    }
  }

  String _getLogDetails(Map<String, dynamic> log) {
    final type = log['type'] ?? 'unknown';

    switch (type) {
      case 'event':
        return 'Datos: ${log['data'] ?? 'N/A'}';
      case 'error':
        final message = log['errorMessage'] ?? 'N/A';
        final stackTrace = log['stackTrace'] ?? '';
        return 'Error: $message\nStack: ${stackTrace.isNotEmpty ? stackTrace.substring(0, stackTrace.length > 200 ? 200 : stackTrace.length) : 'N/A'}';
      case 'metric':
        final lat = log['latitude'] ?? 0.0;
        final lon = log['longitude'] ?? 0.0;
        final accuracy = log['accuracy'] ?? 0.0;
        final speed = log['speed'] ?? 0.0;
        return 'Lat: $lat\nLon: $lon\nPrecisión: ${accuracy}m\nVelocidad: ${speed}km/h';
      default:
        return JsonEncoder.withIndent('  ').convert(log);
    }
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null || timestamp == 0) return 'N/A';

    try {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return '${dateTime.day}/${dateTime.month} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Formato inválido';
    }
  }

  Future<void> _forceSyncLogs() async {
    try {
      final success = await NativeLogSyncService.syncLogsFromNative();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              success ? '✅ Logs sincronizados' : '❌ Error en sincronización'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      if (success) _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _cleanupLogs() async {
    try {
      await NativeLogSyncService.cleanupOldLogs();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('🧹 Logs antiguos limpiados'),
            backgroundColor: Colors.green),
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _exportLogs() async {
    try {
      final jsonString = await NativeLogSyncService.exportLogsToJson(
          type: selectedLogType == 'all' ? null : selectedLogType);

      // Aquí podrías guardar en archivo o compartir
      print('📤 Logs exportados:');
      print(jsonString);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('📤 Logs exportados a consola'),
            backgroundColor: Colors.blue),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _reactivateService() async {
    try {
      final success = await NativeLogSyncService.reactivateService(
          reason: 'Manual reactivation from debug page');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(success ? '▶️ Servicio reactivado' : '❌ Error reactivando'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      if (success) _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _stopService() async {
    try {
      final success = await NativeLogSyncService.forceStopService(
          movil: '0', // Valores dummy para testing
          escenario: '0',
          usuario: 'debug',
          deviceId: '0',
          reason: 'Manual stop from debug page');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(success ? '🛑 Servicio detenido' : '❌ Error deteniendo'),
          backgroundColor: success ? Colors.orange : Colors.red,
        ),
      );
      if (success) _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
