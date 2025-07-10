import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../services/stream_manager.dart';
import '../services/firebase_service.dart';

/// Diagnostic utility specifically for PendingOrders loading issues
class PendingOrdersDiagnostic {
  /// Comprehensive diagnostic for PendingOrders infinite loading
  static Future<void> diagnosePendingOrdersIssue() async {
    print('\n🔍 === PENDING ORDERS DIAGNOSTIC ===');
    print('Starting comprehensive diagnosis...\n');

    // Step 1: Check Hive boxes
    print('📦 STEP 1: Checking Hive boxes...');
    await _checkHiveBoxes();

    // Step 2: Check session data
    print('\n👤 STEP 2: Checking session data...');
    await _checkSessionData();

    // Step 3: Check StreamManager state
    print('\n🔄 STEP 3: Checking StreamManager state...');
    _checkStreamManagerState();

    // Step 4: Test Firebase connection
    print('\n🔗 STEP 4: Testing Firebase connection...');
    await _testFirebaseConnection();

    // Step 5: Test direct Firestore query
    print('\n📊 STEP 5: Testing direct Firestore query...');
    await _testDirectFirestoreQuery();

    // Step 6: Test StreamManager
    print('\n🎯 STEP 6: Testing StreamManager...');
    await _testStreamManager();

    print('\n🔍 === DIAGNOSTIC COMPLETED ===\n');
  }

  static Future<void> _checkHiveBoxes() async {
    try {
      // Check if boxes are open
      bool sessionBoxOpen = Hive.isBoxOpen('sessionBox');
      bool pedidosBoxOpen = Hive.isBoxOpen('pedidosBox');
      bool constantBoxOpen = Hive.isBoxOpen('constantBox');

      print('   📦 SessionBox open: $sessionBoxOpen');
      print('   📦 PedidosBox open: $pedidosBoxOpen');
      print('   📦 ConstantBox open: $constantBoxOpen');

      if (!sessionBoxOpen) {
        print('   ❌ SessionBox is closed - this will cause stream failure');
        try {
          await Hive.openBox('sessionBox');
          print('   ✅ Successfully opened SessionBox');
        } catch (e) {
          print('   ❌ Failed to open SessionBox: $e');
        }
      }

      if (!pedidosBoxOpen) {
        print('   ⚠️ PedidosBox is closed - UI may not display correctly');
      }
    } catch (e) {
      print('   ❌ Error checking Hive boxes: $e');
    }
  }

  static Future<void> _checkSessionData() async {
    try {
      if (!Hive.isBoxOpen('sessionBox')) {
        print('   ❌ SessionBox not available');
        return;
      }

      var box = Hive.box('sessionBox');

      // Get all session data
      String escenarioId = box.get('escenario', defaultValue: '').toString();
      String usuario = box.get('username', defaultValue: '').toString();
      String movil = box.get('movil', defaultValue: '').toString();

      print('   🆔 Escenario: "$escenarioId"');
      print('   👤 Usuario: "$usuario"');
      print('   🚗 Movil: "$movil"');

      // Validate critical values
      if (escenarioId.isEmpty || escenarioId == '0') {
        print('   ❌ CRITICAL: Escenario ID is empty or invalid');
      } else {
        print('   ✅ Escenario ID is valid');
      }

      if (usuario.isEmpty) {
        print('   ⚠️ WARNING: Usuario is empty');
      } else {
        print('   ✅ Usuario is set');
      }

      int movilInt = int.tryParse(movil) ?? 0;
      if (movilInt == 0) {
        print('   ❌ CRITICAL: Movil ID is 0 or invalid');
      } else {
        print('   ✅ Movil ID is valid: $movilInt');
      }

      // Print entire box contents for debugging
      print('   📋 Complete SessionBox contents:');
      box.toMap().forEach((key, value) {
        print('     $key: $value');
      });
    } catch (e) {
      print('   ❌ Error checking session data: $e');
    }
  }

  static void _checkStreamManagerState() {
    try {
      final streamManager = StreamManager();
      final debugInfo = streamManager.getDebugInfo();

      print('   🔄 Active streams: ${debugInfo['activeStreams']}');
      print('   👂 Listeners: ${debugInfo['listeners']}');
      print('   📖 Reads: ${debugInfo['reads']}');

      bool pedidosActive = debugInfo['activeStreams']['pedidos'] ?? false;
      int pedidosListeners = debugInfo['listeners']['pedidos'] ?? 0;
      int pedidosReads = debugInfo['reads']['pedidos'] ?? 0;

      print('   📊 Pedidos stream active: $pedidosActive');
      print('   👂 Pedidos listeners: $pedidosListeners');
      print('   📖 Pedidos reads: $pedidosReads');

      if (!pedidosActive && pedidosListeners > 0) {
        print('   ⚠️ WARNING: Listeners exist but stream is inactive');
      }
    } catch (e) {
      print('   ❌ Error checking StreamManager state: $e');
    }
  }

  static Future<void> _testFirebaseConnection() async {
    try {
      final firebaseService = FirebaseService();
      await firebaseService.initializeFirebase();
      print('   ✅ Firebase service initialized');

      // Test basic Firestore connection
      final firestore = FirebaseFirestore.instance;
      await firestore
          .collection('test')
          .limit(1)
          .get()
          .timeout(Duration(seconds: 10));
      print('   ✅ Firestore connection successful');
    } catch (e) {
      print('   ❌ Firebase connection failed: $e');

      if (e.toString().contains('permission-denied')) {
        print('   🔐 ISSUE: Permission denied - check Firestore rules');
      } else if (e.toString().contains('timeout')) {
        print('   ⏱️ ISSUE: Connection timeout - check network');
      } else if (e.toString().contains('unauthenticated')) {
        print('   🚫 ISSUE: Authentication failed');
      }
    }
  }

  static Future<void> _testDirectFirestoreQuery() async {
    try {
      if (!Hive.isBoxOpen('sessionBox')) {
        print('   ❌ Cannot test: SessionBox not available');
        return;
      }

      var box = Hive.box('sessionBox');
      String escenarioId = box.get('escenario', defaultValue: '0').toString();
      int movil = int.tryParse(box.get('movil', defaultValue: '0')) ?? 0;

      String collectionName = 'Pedidos-$escenarioId';
      String fechaActualStr = DateTime.now()
          .toUtc()
          .subtract(Duration(hours: 3))
          .toIso8601String()
          .split('T')[0]
          .replaceAll('-', '');
      int fechaActual = int.tryParse(fechaActualStr) ?? 0;

      print('   📊 Testing query parameters:');
      print('     Collection: $collectionName');
      print('     Movil: $movil');
      print('     FchPara: $fechaActual');

      final firestore = FirebaseFirestore.instance;

      // Test if collection exists
      final collectionRef = firestore.collection(collectionName);
      final snapshot =
          await collectionRef.limit(1).get().timeout(Duration(seconds: 10));
      print(
          '   ✅ Collection "$collectionName" exists (${snapshot.docs.length} sample docs)');

      // Test the exact query used by the app
      final query = collectionRef
          .where('Movil', isEqualTo: movil)
          .where('FchPara', isEqualTo: fechaActual)
          .where('VisibleEnApp', isEqualTo: 'S')
          .where('EstadoNro', isEqualTo: 1);

      final querySnapshot = await query.get().timeout(Duration(seconds: 10));
      print('   📊 Query results: ${querySnapshot.docs.length} documents');

      if (querySnapshot.docs.isEmpty) {
        print('   ⚠️ No documents match the query criteria');
        print('   💡 Suggestions:');
        print('     - Check if Movil $movil has orders for date $fechaActual');
        print('     - Verify VisibleEnApp = "S" and EstadoNro = 1');
        print('     - Check if orders exist in the collection at all');

        // Test with relaxed criteria
        final relaxedQuery =
            collectionRef.where('Movil', isEqualTo: movil).limit(5);
        final relaxedSnapshot = await relaxedQuery.get();
        print(
            '   🔍 Relaxed query (only Movil filter): ${relaxedSnapshot.docs.length} documents');

        if (relaxedSnapshot.docs.isNotEmpty) {
          print('   📋 Sample document from relaxed query:');
          final sampleDoc = relaxedSnapshot.docs.first;
          print('     Document ID: ${sampleDoc.id}');
          print('     Data: ${sampleDoc.data()}');
        }
      } else {
        print('   ✅ Query successful - documents found');
        print('   📋 Sample document:');
        final sampleDoc = querySnapshot.docs.first;
        print('     Document ID: ${sampleDoc.id}');
        final data = sampleDoc.data() as Map<String, dynamic>;
        print('     Movil: ${data['Movil']}');
        print('     FchPara: ${data['FchPara']}');
        print('     VisibleEnApp: ${data['VisibleEnApp']}');
        print('     EstadoNro: ${data['EstadoNro']}');
      }
    } catch (e) {
      print('   ❌ Direct query failed: $e');

      if (e.toString().contains('index')) {
        print('   📊 ISSUE: Missing Firestore index');
      } else if (e.toString().contains('permission-denied')) {
        print('   🔐 ISSUE: Permission denied for this query');
      }
    }
  }

  static Future<void> _testStreamManager() async {
    print('   🎯 Testing StreamManager getPedidosStream()...');

    try {
      // Test prerequisites
      await StreamManager.debugPedidosPrerequisites();

      // Test getting the stream
      final streamManager = StreamManager();
      final stream = streamManager.getPedidosStream();

      print('   📡 Got stream from StreamManager');

      // Listen for a short time to see if data comes through
      bool dataReceived = false;
      bool errorOccurred = false;
      String? errorMessage;

      final subscription = stream.timeout(Duration(seconds: 10)).listen(
        (data) {
          dataReceived = true;
          print('   ✅ Data received: ${data.length} documents');
        },
        onError: (error) {
          errorOccurred = true;
          errorMessage = error.toString();
          print('   ❌ Stream error: $error');
        },
      );

      // Wait for data or timeout
      await Future.delayed(Duration(seconds: 5));

      subscription.cancel();

      if (!dataReceived && !errorOccurred) {
        print('   ⏱️ No data received within timeout period');
        print('   💡 This suggests the stream is not emitting data');
      } else if (errorOccurred) {
        print('   ❌ Stream failed with error: $errorMessage');
      }
    } catch (e) {
      print('   ❌ StreamManager test failed: $e');
    }
  }

  /// Quick fix suggestions based on common issues
  static void printQuickFixes() {
    print('\n🔧 === QUICK FIXES FOR PENDING ORDERS ===');
    print('1. Check session data:');
    print('   StreamManager.debugPedidosPrerequisites()');
    print('');
    print('2. Reset StreamManager:');
    print('   StreamManager().dispose()');
    print('   StreamManager.resetCounters()');
    print('');
    print('3. Verify Hive boxes:');
    print('   - Ensure sessionBox is open');
    print('   - Check escenario, movil, and username values');
    print('');
    print('4. Check Firestore:');
    print('   - Verify collection "Pedidos-{escenarioId}" exists');
    print('   - Check Firebase authentication');
    print('   - Verify Firestore rules allow read access');
    print('');
    print('5. Network issues:');
    print('   - Check internet connectivity');
    print('   - Try on different network');
    print('=======================================\n');
  }

  /// Quick debug method to call from anywhere in the app
  static Future<void> quickDebug() async {
    print('\n🚨 === QUICK PENDING ORDERS DEBUG ===');

    // Step 1: Check basics
    print('📦 Hive SessionBox open: ${Hive.isBoxOpen('sessionBox')}');
    print('📦 Hive PedidosBox open: ${Hive.isBoxOpen('pedidosBox')}');

    // Step 2: Check session data if available
    if (Hive.isBoxOpen('sessionBox')) {
      var box = Hive.box('sessionBox');
      String escenario = box.get('escenario', defaultValue: 'NONE').toString();
      String movil = box.get('movil', defaultValue: 'NONE').toString();
      String username = box.get('username', defaultValue: 'NONE').toString();

      print('🆔 Escenario: $escenario');
      print('🚗 Movil: $movil');
      print('👤 Username: $username');

      if (escenario == 'NONE' || escenario == '0') {
        print('❌ CRITICAL: Invalid escenario ID');
      }
      if (movil == 'NONE' || movil == '0') {
        print('❌ CRITICAL: Invalid movil ID');
      }
    } else {
      print('❌ CRITICAL: SessionBox not open');
    }

    // Step 3: Check StreamManager
    final streamManager = StreamManager();
    final debugInfo = streamManager.getDebugInfo();
    print('🔄 Pedidos stream active: ${debugInfo['activeStreams']['pedidos']}');
    print('👂 Pedidos listeners: ${debugInfo['listeners']['pedidos']}');
    print('📖 Pedidos reads: ${debugInfo['reads']['pedidos']}');

    print('🚨 === END QUICK DEBUG ===\n');
  }
}
