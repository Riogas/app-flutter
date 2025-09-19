import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'dart:async';
import 'dart:convert';

/// Servicio para sincronizar logs nativos de Kotlin con Hive en Flutter
class NativeLogSyncService {
  static const platform = MethodChannel('background_service');
  static const String _logBoxName = 'native_logs';
  static Timer? _syncTimer;
  static bool _isInitialized = false;

  /// Inicializa el servicio de sincronización
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Abrir box de logs nativos si no está abierto
      if (!Hive.isBoxOpen(_logBoxName)) {
        await Hive.openBox(_logBoxName);
      }

      _isInitialized = true;

      // Iniciar sincronización periódica cada 2 minutos
      _startPeriodicSync();

      print('🔄 NativeLogSyncService inicializado');
    } catch (e) {
      print('❌ Error inicializando NativeLogSyncService: $e');
    }
  }

  /// Inicia la sincronización periódica
  static void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(Duration(minutes: 2), (timer) {
      syncLogsFromNative();
    });
  }

  /// Detiene la sincronización periódica
  static void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    print('🛑 Sincronización periódica detenida');
  }

  /// Sincroniza logs desde el sistema nativo
  static Future<bool> syncLogsFromNative() async {
    try {
      if (!_isInitialized) await initialize();

      // Obtener logs no sincronizados desde Kotlin
      final result = await platform.invokeMethod('getUnsyncedLogs');

      // Convertir de forma segura el resultado del platform channel
      final Map<String, dynamic> unsyncedLogs =
          Map<String, dynamic>.from(result as Map);

      // Convertir las listas con manejo seguro de tipos
      final rawEvents = unsyncedLogs['events'] as List? ?? [];
      final rawErrors = unsyncedLogs['errors'] as List? ?? [];
      final rawMetrics = unsyncedLogs['metrics'] as List? ?? [];

      final events =
          rawEvents.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final errors =
          rawErrors.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final metrics =
          rawMetrics.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      if (events.isEmpty && errors.isEmpty && metrics.isEmpty) {
        print('📭 No hay logs nuevos para sincronizar');
        return true;
      }

      final box = Hive.box(_logBoxName);
      final syncedEventIds = <int>[];
      final syncedErrorIds = <int>[];
      final syncedMetricIds = <int>[];

      // Procesar eventos
      for (final event in events) {
        final logEntry = {
          'type': 'event',
          'nativeId': event['id'],
          'timestamp': event['timestamp'],
          'dateStr': event['dateStr'],
          'eventType': event['eventType'],
          'data': event['data'],
          'syncedAt': DateTime.now().millisecondsSinceEpoch,
        };

        final key = 'event_${event['id']}_${event['timestamp']}';
        await box.put(key, logEntry);
        syncedEventIds.add(event['id']);
      }

      // Procesar errores
      for (final error in errors) {
        final logEntry = {
          'type': 'error',
          'nativeId': error['id'],
          'timestamp': error['timestamp'],
          'dateStr': error['dateStr'],
          'errorType': error['errorType'],
          'errorMessage': error['errorMessage'],
          'stackTrace': error['stackTrace'],
          'syncedAt': DateTime.now().millisecondsSinceEpoch,
        };

        final key = 'error_${error['id']}_${error['timestamp']}';
        await box.put(key, logEntry);
        syncedErrorIds.add(error['id']);
      }

      // Procesar métricas
      for (final metric in metrics) {
        final logEntry = {
          'type': 'metric',
          'nativeId': metric['id'],
          'timestamp': metric['timestamp'],
          'dateStr': metric['dateStr'],
          'latitude': metric['latitude'],
          'longitude': metric['longitude'],
          'provider': metric['provider'],
          'accuracy': metric['accuracy'],
          'speed': metric['speed'],
          'syncedAt': DateTime.now().millisecondsSinceEpoch,
        };

        final key = 'metric_${metric['id']}_${metric['timestamp']}';
        await box.put(key, logEntry);
        syncedMetricIds.add(metric['id']);
      }

      // Marcar logs como sincronizados en el lado nativo
      await platform.invokeMethod('markLogsSynced', {
        'eventIds': syncedEventIds,
        'errorIds': syncedErrorIds,
        'metricIds': syncedMetricIds,
      });

      print(
          '✅ Logs sincronizados: ${events.length} eventos, ${errors.length} errores, ${metrics.length} métricas');

      return true;
    } catch (e) {
      print('❌ Error sincronizando logs: $e');
      return false;
    }
  }

  /// Obtiene el estado del servicio de ubicación nativo
  static Future<Map<String, dynamic>> getServiceStatus() async {
    try {
      final result = await platform.invokeMethod('getServiceStatus');
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      print('❌ Error obteniendo estado del servicio: $e');
      return {'error': e.toString()};
    }
  }

  /// Reactiva el servicio de ubicación
  static Future<bool> reactivateService(
      {String reason = 'Manual reactivation from Flutter'}) async {
    try {
      await platform.invokeMethod('reactivateService', {'reason': reason});
      print('✅ Servicio reactivado: $reason');
      return true;
    } catch (e) {
      print('❌ Error reactivando servicio: $e');
      return false;
    }
  }

  /// Fuerza la parada del servicio
  static Future<bool> forceStopService(
      {required String movil,
      required String escenario,
      required String usuario,
      required String deviceId,
      String reason = 'Forced stop from Flutter'}) async {
    try {
      await platform.invokeMethod('forceStopService', {
        'movil': movil,
        'escenario': escenario,
        'usuario': usuario,
        'deviceId': deviceId,
        'reason': reason,
      });
      print('🛑 Servicio detenido forzosamente: $reason');
      return true;
    } catch (e) {
      print('❌ Error deteniendo servicio: $e');
      return false;
    }
  }

  /// Limpia logs antiguos tanto en Hive como en el sistema nativo
  static Future<void> cleanupOldLogs() async {
    try {
      // Limpiar logs nativos
      await platform.invokeMethod('cleanupOldLogs');

      // Limpiar logs de Hive (más de 7 días)
      final box = Hive.box(_logBoxName);
      final sevenDaysAgo =
          DateTime.now().millisecondsSinceEpoch - (7 * 24 * 60 * 60 * 1000);

      final keysToDelete = <String>[];
      for (final key in box.keys) {
        final entry = box.get(key);
        if (entry is Map && entry['syncedAt'] != null) {
          final syncedAt = entry['syncedAt'] as int;
          if (syncedAt < sevenDaysAgo) {
            keysToDelete.add(key.toString());
          }
        }
      }

      for (final key in keysToDelete) {
        await box.delete(key);
      }

      print(
          '🧹 Logs antiguos limpiados: ${keysToDelete.length} entradas eliminadas');
    } catch (e) {
      print('❌ Error limpiando logs antiguos: $e');
    }
  }

  /// Obtiene estadísticas de logs
  static Map<String, dynamic> getLogStatistics() {
    try {
      if (!Hive.isBoxOpen(_logBoxName)) {
        return {'error': 'Log box not open'};
      }

      final box = Hive.box(_logBoxName);
      int eventCount = 0;
      int errorCount = 0;
      int metricCount = 0;

      for (final entry in box.values) {
        if (entry is Map && entry['type'] != null) {
          switch (entry['type']) {
            case 'event':
              eventCount++;
              break;
            case 'error':
              errorCount++;
              break;
            case 'metric':
              metricCount++;
              break;
          }
        }
      }

      return {
        'totalEntries': box.length,
        'events': eventCount,
        'errors': errorCount,
        'metrics': metricCount,
        'boxSize': box.length,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Obtiene logs recientes para debugging
  static List<Map<String, dynamic>> getRecentLogs(
      {int limit = 50, String? type}) {
    try {
      if (!Hive.isBoxOpen(_logBoxName)) {
        return [];
      }

      final box = Hive.box(_logBoxName);
      final allLogs = <Map<String, dynamic>>[];

      for (final entry in box.values) {
        if (entry is Map) {
          final logEntry = Map<String, dynamic>.from(entry);
          if (type == null || logEntry['type'] == type) {
            allLogs.add(logEntry);
          }
        }
      }

      // Ordenar por timestamp descendente
      allLogs.sort((a, b) {
        final timestampA = a['timestamp'] ?? 0;
        final timestampB = b['timestamp'] ?? 0;
        return timestampB.compareTo(timestampA);
      });

      return allLogs.take(limit).toList();
    } catch (e) {
      print('❌ Error obteniendo logs recientes: $e');
      return [];
    }
  }

  /// Exporta logs a JSON para debugging
  static Future<String> exportLogsToJson({String? type}) async {
    try {
      final logs = getRecentLogs(limit: 1000, type: type);
      final jsonString = jsonEncode({
        'exportedAt': DateTime.now().toIso8601String(),
        'type': type ?? 'all',
        'count': logs.length,
        'logs': logs,
      });
      return jsonString;
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  /// Verifica eventos de parada del servicio desde el lado nativo
  static Future<Map<String, dynamic>?> checkServiceStoppedEvents() async {
    try {
      final prefs = await platform
          .invokeMethod('getSharedPreferences', {'name': 'flutter_events'});
      final Map<String, dynamic> prefsMap = Map<String, dynamic>.from(prefs);

      if (prefsMap['location_service_stopped'] != null) {
        final stopReason = prefsMap['location_service_stopped'];
        final stopTime = prefsMap['location_service_stopped_time'] ?? 0;

        // Limpiar el evento después de leerlo
        await platform.invokeMethod('clearSharedPreference',
            {'name': 'flutter_events', 'key': 'location_service_stopped'});

        return {
          'stopped': true,
          'reason': stopReason,
          'timestamp': stopTime,
        };
      }

      return null;
    } catch (e) {
      print('❌ Error verificando eventos de parada: $e');
      return null;
    }
  }

  /// Limpia el servicio y libera recursos
  static void dispose() {
    stopPeriodicSync();
    _isInitialized = false;
    print('🧹 NativeLogSyncService disposed');
  }

  /// Muestra todos los logs sincronizados para debugging
  static Future<void> displaySyncedLogs() async {
    try {
      if (!Hive.isBoxOpen(_logBoxName)) {
        await Hive.openBox(_logBoxName);
      }

      final box = Hive.box(_logBoxName);

      print('📊 === LOGS SINCRONIZADOS ===');
      print('Total de entradas: ${box.length}');
      print('');

      final events = <Map>[];
      final errors = <Map>[];
      final metrics = <Map>[];

      // Categorizar los logs
      for (final key in box.keys) {
        final entry = box.get(key);
        if (entry is Map && entry['type'] != null) {
          switch (entry['type']) {
            case 'event':
              events.add(entry);
              break;
            case 'error':
              errors.add(entry);
              break;
            case 'metric':
              metrics.add(entry);
              break;
          }
        }
      }

      // Mostrar eventos
      if (events.isNotEmpty) {
        print('🎯 EVENTOS (${events.length}):');
        for (final event in events) {
          final date =
              DateTime.fromMillisecondsSinceEpoch(event['timestamp'] ?? 0);
          print('  • ID: ${event['nativeId']} | Tipo: ${event['eventType']}');
          print('    Fecha: ${date.toString().substring(0, 19)}');
          print('    Datos: ${event['data']}');
          print(
              '    Sincronizado: ${DateTime.fromMillisecondsSinceEpoch(event['syncedAt'] ?? 0).toString().substring(0, 19)}');
          print('');
        }
      }

      // Mostrar errores - TODOS LOS ERRORES
      if (errors.isNotEmpty) {
        print('❌ ERRORES (${errors.length}):');
        for (final error in errors) {
          final date =
              DateTime.fromMillisecondsSinceEpoch(error['timestamp'] ?? 0);
          print('  • ID: ${error['nativeId']} | Tipo: ${error['errorType']}');
          print('    Fecha: ${date.toString().substring(0, 19)}');
          print('    Mensaje: ${error['errorMessage']}');
          final stack = error['stackTrace']?.toString() ?? '';
          final shortStack =
              stack.length > 150 ? '${stack.substring(0, 150)}...' : stack;
          print('    Stack: $shortStack');
          print(
              '    Sincronizado: ${DateTime.fromMillisecondsSinceEpoch(error['syncedAt'] ?? 0).toString().substring(0, 19)}');
          print('');
        }
      }

      // Mostrar métricas
      if (metrics.isNotEmpty) {
        print('📍 MÉTRICAS DE UBICACIÓN (${metrics.length}):');
        for (final metric in metrics.take(5)) {
          final date =
              DateTime.fromMillisecondsSinceEpoch(metric['timestamp'] ?? 0);
          print('  • ID: ${metric['nativeId']}');
          print('    Fecha: ${date.toString().substring(0, 19)}');
          print('    Ubicación: ${metric['latitude']}, ${metric['longitude']}');
          print(
              '    Proveedor: ${metric['provider']} | Precisión: ${metric['accuracy']}m');
          print(
              '    Velocidad: ${metric['speed']} | Sincronizado: ${DateTime.fromMillisecondsSinceEpoch(metric['syncedAt'] ?? 0).toString().substring(0, 19)}');
          print('');
        }
        if (metrics.length > 5) {
          print('  ... y ${metrics.length - 5} métricas más');
          print('');
        }
      }

      print('📊 === FIN DE LOGS SINCRONIZADOS ===');
    } catch (e) {
      print('❌ Error mostrando logs sincronizados: $e');
    }
  }
}
