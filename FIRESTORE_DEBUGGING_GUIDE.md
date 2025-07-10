# Firestore Stream Debugging and Monitoring Guide

## Quick Reference

### 🔍 Instant Debugging Commands

```dart
// Print comprehensive diagnostics
StreamManager.debug();

// Check read counters only
StreamManager.checkReads();

// Reset counters (for testing)
StreamManager.resetCounters();
```

### 📊 Advanced Monitoring

```dart
import '../services/stream_monitor.dart';

// Start automatic monitoring (prints report every 30 seconds)
StreamMonitor.startPeriodicMonitoring();

// Stop automatic monitoring
StreamMonitor.stopPeriodicMonitoring();

// Perform health check
StreamMonitor.healthCheck();

// Generate comprehensive report
StreamMonitor.generateReport();
```

## Detailed Usage Guide

### 1. Basic Stream Diagnostics

The `StreamManager.debug()` method provides a complete overview:

```dart
// From anywhere in your app:
StreamManager.debug();
```

**Output Example:**
```
🔍 StreamManager Comprehensive Diagnostics:
==================================================
📊 ACTIVE STREAMS SUMMARY:
  🔄 Pedidos: ACTIVE (2 listeners, 15 reads)
  🔄 Mensajes: ACTIVE (1 listeners, 8 reads)
  ⭕ Movil: INACTIVE
  ⭕ Sesiones: INACTIVE
  🔄 SubEstados: ACTIVE (1 listeners, 3 reads)
  ⭕ SubEstadoMoviles: INACTIVE
  ⭕ SubEstadoServices: INACTIVE
==================================================
📈 TOTALS:
  🔄 Active Streams: 3
  👂 Total Listeners: 4
  📖 Total Reads: 26
  🕐 Current Time: 2024-01-15T10:30:00.000Z
==================================================
📊 PERFORMANCE INSIGHTS:
  📊 Average reads per stream: 8.67
  ✅ Read count looks healthy
==================================================
```

### 2. Monitoring During Development

For continuous monitoring during development:

```dart
// In your main.dart or any initialization code:
import 'services/stream_monitor.dart';

void main() {
  runApp(MyApp());
  
  // Start monitoring in debug mode
  if (kDebugMode) {
    StreamMonitor.startPeriodicMonitoring(intervalSeconds: 30);
  }
}
```

### 3. Testing Stream Lifecycle

Test individual streams to ensure proper creation and cleanup:

```dart
// Test a specific stream
await StreamMonitor.testStreamLifecycle('pedidos');
await StreamMonitor.testStreamLifecycle('mensajes');
await StreamMonitor.testStreamLifecycle('movil');
```

### 4. Measuring Read Impact

Measure how many reads a specific operation causes:

```dart
await StreamMonitor.measureReads('Home Page Navigation', () async {
  // Navigate to home page
  Navigator.pushNamed(context, '/home');
  await Future.delayed(Duration(seconds: 2));
});
```

### 5. Health Checks

Regular health checks help identify potential issues:

```dart
// Perform health check
StreamMonitor.healthCheck();
```

**Example Output:**
```
🏥 StreamMonitor: Performing health check...
🏥 HEALTH CHECK RESULTS:
  ✅ Total active streams: 3
  ✅ Total listeners: 4
  ✅ Total reads: 26
  🎉 No issues detected - Stream system is healthy!
```

## Common Debugging Scenarios

### Scenario 1: Too Many Reads

**Symptoms:** High read counts, performance issues
**Diagnosis:**
```dart
StreamManager.debug();
// Look for high read counts in output
```

**Solution:** Check if multiple widgets are subscribing to the same stream

### Scenario 2: Memory Leaks

**Symptoms:** Streams not cleaning up, listener counts never decrease
**Diagnosis:**
```dart
// Monitor over time
StreamMonitor.startPeriodicMonitoring();
// Navigate through app, check if listener counts decrease when leaving pages
```

**Solution:** Ensure widgets properly dispose of stream subscriptions

### Scenario 3: Duplicate Subscriptions

**Symptoms:** Multiple active streams of the same type
**Diagnosis:**
```dart
StreamManager.debug();
// Check if same stream type appears multiple times as ACTIVE
```

**Solution:** Ensure all widgets use StreamManager instead of direct FirebaseService

### Scenario 4: Stream Not Receiving Data

**Symptoms:** Listeners > 0 but reads = 0
**Diagnosis:**
```dart
StreamMonitor.healthCheck();
// Will warn about streams with listeners but no reads
```

**Solution:** Check Firebase rules, network connectivity, or stream configuration

## Logging Format Reference

### Stream Creation Logs
```
🔄 StreamManager: Created new Pedidos broadcast stream
```

### Listener Changes
```
📊 StreamManager: Pedidos listeners: 2
```

### Read Operations
```
📖 StreamManager: Pedidos read #15 (5 documents)
   📄 Sample document IDs: [doc1, doc2, doc3, ...]
   🕐 Timestamp: 2024-01-15T10:30:00.000Z
```

### Stream Cleanup
```
🧹 StreamManager: Cleaning up Pedidos stream (no more listeners)
📊 StreamManager: Pedidos total reads: 15
```

### Error Logging
```
❌ StreamManager: Pedidos error: [error details]
```

## Performance Monitoring Tips

1. **Monitor Total Reads:** Keep total reads under 100 for normal app usage
2. **Check Listener Ratios:** Each active stream should have at least 1 listener
3. **Watch for Memory Leaks:** Listener counts should decrease when leaving pages
4. **Regular Health Checks:** Run health checks after major navigation changes

## Production Monitoring

For production apps, consider:

```dart
// Log only critical issues in production
if (kReleaseMode) {
  // Only log errors and high read counts
  final totalReads = StreamManager().getReadCounters().values.fold(0, (a, b) => a + b);
  if (totalReads > 200) {
    // Log to your analytics service
    print('⚠️ High Firestore read count: $totalReads');
  }
} else {
  // Full monitoring in debug mode
  StreamMonitor.startPeriodicMonitoring();
}
```

## Troubleshooting Common Issues

### Issue: StreamManager singleton not working
**Solution:** Ensure all imports use the correct path:
```dart
import '../services/stream_manager.dart';
```

### Issue: Streams not cleaning up
**Solution:** Check widget disposal:
```dart
@override
void dispose() {
  _subscription?.cancel(); // Make sure to cancel subscriptions
  super.dispose();
}
```

### Issue: High read counts
**Solution:** Review and optimize query patterns, ensure proper stream sharing

---

## Summary

The StreamManager and StreamMonitor provide comprehensive tools for:
- ✅ Preventing duplicate Firestore subscriptions
- ✅ Monitoring read operations in real-time
- ✅ Debugging stream lifecycle issues
- ✅ Optimizing app performance
- ✅ Ensuring proper resource cleanup

Use these tools during development to maintain optimal Firestore usage and prevent excessive billing.
