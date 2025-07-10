import 'dart:async';
import 'stream_manager.dart';
import 'persistent_stream_manager.dart';

/// Debug and monitoring utilities for the Firestore Stream Management System
///
/// This class provides convenient methods to monitor, test, and debug
/// the StreamManager singleton and track Firestore read operations.
class StreamMonitor {
  static Timer? _monitoringTimer;
  static bool _isMonitoring = false;

  /// Start automatic periodic monitoring of all streams
  /// Prints diagnostics every [intervalSeconds] seconds
  static void startPeriodicMonitoring({int intervalSeconds = 30}) {
    if (_isMonitoring) {
      print('🔍 StreamMonitor: Already monitoring streams');
      return;
    }

    _isMonitoring = true;
    print(
        '🔍 StreamMonitor: Starting periodic monitoring (every ${intervalSeconds}s)');

    _monitoringTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (timer) {
        print('\n🔍 === PERIODIC STREAM MONITORING ===');
        StreamManager.debug();
        print('🔍 === END MONITORING REPORT ===\n');
      },
    );
  }

  /// Stop automatic periodic monitoring
  static void stopPeriodicMonitoring() {
    if (_monitoringTimer != null) {
      _monitoringTimer!.cancel();
      _monitoringTimer = null;
      _isMonitoring = false;
      print('🔍 StreamMonitor: Stopped periodic monitoring');
    }
  }

  /// Perform a quick health check of the stream system
  static void healthCheck() {
    print('🏥 StreamMonitor: Performing health check...');

    final streamManager = StreamManager();
    final debugInfo = streamManager.getDebugInfo();
    final readCounters = streamManager.getReadCounters();

    // Check for potential issues
    List<String> warnings = [];
    List<String> recommendations = [];

    // Check for high read counts
    int totalReads = readCounters.values.fold(0, (sum, reads) => sum + reads);
    if (totalReads > 100) {
      warnings.add('High total read count detected: $totalReads');
      recommendations.add('Consider reviewing stream usage patterns');
    }

    // Check for streams with many listeners but low reads
    debugInfo['listeners'].forEach((streamName, listeners) {
      int reads = readCounters[streamName] ?? 0;
      if (listeners > 0 && reads == 0) {
        warnings.add('Stream $streamName has $listeners listeners but 0 reads');
        recommendations
            .add('Check if $streamName stream is properly connected');
      }
    });

    // Check for inactive streams
    int activeStreams =
        debugInfo['activeStreams'].values.where((active) => active).length;
    int totalListeners = debugInfo['listeners']
        .values
        .fold(0, (sum, listeners) => sum + listeners);

    print('🏥 HEALTH CHECK RESULTS:');
    print('  ✅ Total active streams: $activeStreams');
    print('  ✅ Total listeners: $totalListeners');
    print('  ✅ Total reads: $totalReads');

    if (warnings.isEmpty) {
      print('  🎉 No issues detected - Stream system is healthy!');
    } else {
      print('  ⚠️  Warnings detected:');
      for (String warning in warnings) {
        print('    - $warning');
      }

      if (recommendations.isNotEmpty) {
        print('  💡 Recommendations:');
        for (String rec in recommendations) {
          print('    - $rec');
        }
      }
    }
  }

  /// Test stream creation and cleanup for a specific stream type
  static Future<void> testStreamLifecycle(String streamType) async {
    print('🧪 StreamMonitor: Testing $streamType stream lifecycle...');

    final streamManager = StreamManager();

    // Print initial state
    print('📊 Initial state:');
    StreamManager.debug();

    late StreamSubscription subscription;

    // Create a subscription
    switch (streamType.toLowerCase()) {
      case 'pedidos':
        subscription = streamManager.getPedidosStream().listen((data) {
          print('🧪 Test: Received ${data.length} pedidos');
        });
        break;
      case 'mensajes':
        subscription = streamManager.getMensajesStream().listen((data) {
          print('🧪 Test: Received ${data.length} mensajes');
        });
        break;
      case 'movil':
        subscription = streamManager.getMovilStream().listen((data) {
          print('🧪 Test: Received movil data: ${data != null}');
        });
        break;
      case 'sesiones':
        subscription = streamManager.getSesionesStream().listen((data) {
          print('🧪 Test: Received sesiones data: ${data != null}');
        });
        break;
      default:
        print('❌ Unknown stream type: $streamType');
        return;
    }

    // Wait a bit for stream to initialize
    await Future.delayed(Duration(seconds: 2));

    print('📊 After subscription:');
    StreamManager.debug();

    // Cancel subscription
    subscription.cancel();

    // Wait a bit for cleanup
    await Future.delayed(Duration(seconds: 1));

    print('📊 After cancellation:');
    StreamManager.debug();

    print('🧪 Stream lifecycle test completed for $streamType');
  }

  /// Compare read counts before and after a specific operation
  static Future<void> measureReads(
      String operationName, Future<void> Function() operation) async {
    print('📏 StreamMonitor: Measuring reads for "$operationName"...');

    final streamManager = StreamManager();
    final beforeReads = Map<String, int>.from(streamManager.getReadCounters());

    // Execute the operation
    await operation();

    final afterReads = streamManager.getReadCounters();

    print('📏 Read measurement results for "$operationName":');
    bool hasChanges = false;

    afterReads.forEach((streamName, afterCount) {
      int beforeCount = beforeReads[streamName] ?? 0;
      int difference = afterCount - beforeCount;

      if (difference > 0) {
        hasChanges = true;
        print(
            '  📖 $streamName: +$difference reads (was $beforeCount, now $afterCount)');
      }
    });

    if (!hasChanges) {
      print('  ✅ No additional reads detected during operation');
    }
  }

  /// Generate a comprehensive report for debugging
  static void generateReport() {
    print('\n🔍 === COMPREHENSIVE STREAM MONITORING REPORT ===');
    print('Generated at: ${DateTime.now().toIso8601String()}');
    print('');

    // Stream diagnostics
    StreamManager.debug();

    // Health check
    print('\n');
    healthCheck();

    print('\n🔍 === END COMPREHENSIVE REPORT ===\n');
  }

  /// Quick method to check if monitoring is active
  static bool get isMonitoring => _isMonitoring;

  /// Monitor persistent stream system specifically
  static void monitorPersistentStreams() {
    print('🔍 StreamMonitor: Monitoring persistent stream system...');

    try {
      final persistentManager = PersistentStreamManager();

      print('📊 PERSISTENT STREAM SYSTEM STATUS:');
      print(
          '  🔄 Active Stream Listeners: ${persistentManager.totalActiveListeners} (persistent)');
      print('  📱 Widget Listeners: ${persistentManager.totalWidgetListeners}');
      print('  📖 Total Reads: ${persistentManager.totalReads}');
      print('');

      print('📋 PER STREAM BREAKDOWN:');
      print(
          '  📦 Pedidos: ${persistentManager.pedidosListenerCount} widgets, ${persistentManager.pedidosReads} reads');
      print(
          '  💬 Mensajes: ${persistentManager.mensajesListenerCount} widgets, ${persistentManager.mensajesReads} reads');
      print(
          '  🚗 Movil: ${persistentManager.movilListenerCount} widgets, ${persistentManager.movilReads} reads');
      print(
          '  🔐 Sesiones: ${persistentManager.sesionesListenerCount} widgets, ${persistentManager.sesionesReads} reads');
      print(
          '  📊 SubEstados: ${persistentManager.subEstadosListenerCount} widgets, ${persistentManager.subEstadosReads} reads');
      print(
          '  🚗📊 SubEstadoMoviles: ${persistentManager.subEstadoMovilesListenerCount} widgets, ${persistentManager.subEstadoMovilesReads} reads');

      // Performance indicators
      if (persistentManager.totalActiveListeners == 6) {
        print('  ✅ All persistent listeners active');
      } else {
        print(
            '  ⚠️  Expected 6 listeners, found ${persistentManager.totalActiveListeners}');
      }

      if (persistentManager.totalWidgetListeners > 0) {
        print('  ✅ Widgets are subscribed to notifiers');
      } else {
        print('  ⚠️  No widgets currently subscribed');
      }
    } catch (e) {
      print('❌ Error monitoring persistent streams: $e');
      print('💡 Make sure PersistentStreamManager is initialized');
    }
  }

  /// Compare both stream systems side by side
  static void compareStreamSystems() {
    print('🆚 StreamMonitor: Comparing stream systems...');

    try {
      // Current system
      final streamManager = StreamManager();
      final debugInfo = streamManager.getDebugInfo();
      final readCounters = streamManager.getReadCounters();

      int currentActiveStreams =
          debugInfo['activeStreams'].values.where((active) => active).length;
      int currentTotalListeners = debugInfo['listeners']
          .values
          .fold(0, (sum, listeners) => sum + listeners);
      int currentTotalReads =
          readCounters.values.fold(0, (sum, reads) => sum + reads);

      // Persistent system
      final persistentManager = PersistentStreamManager();

      print('📊 STREAM SYSTEM COMPARISON:');
      print('');
      print('Current System (StreamManager):');
      print('  🔄 Active Streams: $currentActiveStreams');
      print('  👂 Total Listeners: $currentTotalListeners');
      print('  📖 Total Reads: $currentTotalReads');
      print('');
      print('Persistent System (PersistentStreamManager):');
      print(
          '  🔄 Active Streams: ${persistentManager.totalActiveListeners} (persistent)');
      print('  👂 Widget Listeners: ${persistentManager.totalWidgetListeners}');
      print('  📖 Total Reads: ${persistentManager.totalReads}');
      print('');

      // Analysis
      print('🔍 ANALYSIS:');
      if (persistentManager.totalActiveListeners == 6 &&
          currentActiveStreams > 6) {
        print('  ✅ Persistent system uses fewer active streams');
      }

      if (persistentManager.totalReads < currentTotalReads) {
        print('  ✅ Persistent system has fewer total reads');
      }

      print(
          '  💡 Persistent streams never create/cancel listeners during navigation');
      print(
          '  💡 Current system creates/cancels listeners on each page navigation');
    } catch (e) {
      print('❌ Error comparing stream systems: $e');
    }
  }
}
