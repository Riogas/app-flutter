import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import '../services/firebase_service.dart';
import '../services/riogas_service.dart';
import '../utils/error_event.dart';

class ConnectionCheck {
  final FirebaseService _firebaseService = FirebaseService();
  final Duration checkInterval = Duration(seconds: 10);
  late Timer _timer;
  final StreamController<Map<String, dynamic>> _connectionStatusController =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get connectionStatusStream =>
      _connectionStatusController.stream;

  void startMonitoring() {
    _timer = Timer.periodic(checkInterval, (_) async {
      await _checkConnectivity();
    });
  }

  void stopMonitoring() {
    _timer.cancel();
    _connectionStatusController.close();
  }

  Future<void> _checkConnectivity() async {
    Map<String, dynamic> status = {
      'network': false,
      'firestore': false,
      'riogas': false,
    };

    try {
      // Check network connectivity
      var connectivityResult = await Connectivity().checkConnectivity();
      status['network'] = connectivityResult != ConnectivityResult.none;

      if (!status['network']) {
        // Log no network connectivity
        print('❌ No network connectivity detected.');
        // If no network, set all connections to false
        status['firestore'] = false;
        status['riogas'] = false;
      } else {
        // Log network connectivity
        print('✅ Network connectivity detected.');

        // Check Firestore connectivity
        status['firestore'] =
            await _firebaseService.checkFirestoreConnectivity();
        print('Firestore connectivity: ${status['firestore']}');

        // Check RioGas connectivity
        status['riogas'] = await _checkRioGasConnectivity();
        print('RioGas connectivity: ${status['riogas']}');
      }

      // Update Hive box
      var conexionBox = await Hive.openBox('conexionBox');
      await conexionBox.put('conexionFirestore', status['firestore']);
      await conexionBox.put('conexionRioGas', status['riogas']);
      await conexionBox.put('network', status['network']);
      await conexionBox.put('lastCheck', DateTime.now().toIso8601String());
    } catch (e) {
      print('❌ Error during connectivity check: $e');
      await _logError('Connection Check Error', e.toString());
    }

    // Emit updated status
    _connectionStatusController.add(status);
  }

  Future<bool> _checkRioGasConnectivity() async {
    try {
      var response = await RioGasService.validarDispositivo('testDeviceId');
      return response != null;
    } catch (e) {
      await _logError('RioGas Connectivity Error', e.toString());
      return false;
    }
  }

  Future<void> _logError(String type, String message) async {
    var errorBox = await Hive.openBox<ErrorEvent>('errorBox');
    var errorEvent = ErrorEvent(
      type: type,
      message: message,
      timestamp: DateTime.now(),
    );
    await errorBox.add(errorEvent);
  }
}
