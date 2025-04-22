import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:flutter/material.dart'; // Import for showing modal
import 'package:internet_connection_checker/internet_connection_checker.dart';
import '../services/firebase_service.dart';
import '../services/riogas_service.dart';
import '../utils/error_event.dart';
import '../utils/constantes.dart'; // Import for getConstantValue
import '../services/riogas_service.dart'; // Import for RioGasService

class ConnectionCheck {
  final FirebaseService _firebaseService = FirebaseService();
  final Duration checkInterval = Duration(seconds: 10);
  late Timer _timer;
  Timer? _rioGasTimer; // Timer for counting seconds
  int _counter = 0; // Counter for RioGas connectivity
  int _maxCounter = 0; // Max counter value from constant
  final StreamController<Map<String, dynamic>> _connectionStatusController =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get connectionStatusStream =>
      _connectionStatusController.stream;

  StreamSubscription<InternetConnectionStatus>? listener;

  void startMonitoring() {
    _initializeMaxCounter(); // Fetch the constant value
    iniciarEscucha();
    _timer = Timer.periodic(checkInterval, (_) async {
      await _checkConnectivity();
    });
  }

  void stopMonitoring() {
    _timer.cancel();
    detenerEscucha();
    _connectionStatusController.close();
  }

  Future<void> _initializeMaxCounter() async {
    try {
      var constantValue = await getConstantValue('50'); // Fetch constant
      _maxCounter = int.tryParse(constantValue?.toString() ?? '0') ??
          0; // Convert to String if needed
      // print('⏱️ Max counter value set to: $_maxCounter seconds');
    } catch (e) {
      // print('❌ Error fetching constant 50 value: $e');
    }
  }

  Future<void> _checkConnectivity() async {
    Map<String, dynamic> status = {
      'network': false,
      'firestore': false,
      'riogas': false,
      'showPopup': false, // Add flag for popup
    };

    try {
      // Check Firestore connectivity
      status['firestore'] = await _firebaseService.checkFirestoreConnectivity();

      // Check RioGas connectivity
      status['riogas'] = await _checkRioGasConnectivity();

      // Check Internet connectivity and type
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        status['network'] = false;
      } else {
        status['network'] =
            await InternetConnectionChecker.createInstance().hasConnection;
      }

      // Update Hive box
      var conexionBox = await Hive.openBox('conexionBox');
      await conexionBox.put('conexionFirestore', status['firestore']);
      await conexionBox.put('conexionRioGas', status['riogas']);
      await conexionBox.put('network', status['network']);
      await conexionBox.put(
        'lastCheck',
        DateTime.now().toUtc().toIso8601String(),
      );

      if (!status['riogas']) {
        if (_rioGasTimer == null) {
          _startRioGasTimer();
        }
      } else {
        await RioGasService.processPendingRequests(); // Updated call
        _resetRioGasTimer();
      }

      // Emit popup flag if counter exceeds max
      status['showPopup'] = _counter >= _maxCounter;
    } catch (e) {
      await _logError('Connection Check Error', e.toString());
    }

    // Emit updated status if the stream is not closed
    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(status);
    }
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

  void _startRioGasTimer() {
    // print('⏱️ Starting RioGas connectivity timer...');
    _rioGasTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _counter++;
      // print('⏱️ Counter: $_counter');
      if (_counter >= _maxCounter) {
        _rioGasTimer?.cancel(); // Stop the timer after counter reaches max
        _counter = 0; // Reset the counter
      }
    });
  }

  void _resetRioGasTimer() {
    // print('✅ RioGas connectivity restored. Resetting timer...');
    _rioGasTimer?.cancel();
    _rioGasTimer = null;
    _counter = 0;
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

  void iniciarEscucha() {
    listener = InternetConnectionChecker.createInstance()
        .onStatusChange
        .listen((status) async {
      final conexionBox = await Hive.openBox('conexionBox');
      switch (status) {
        case InternetConnectionStatus.connected:
          print('✅ Conexión a Internet');
          await conexionBox.put('network', true);
          break;
        case InternetConnectionStatus.disconnected:
          print('❌ Desconectado');
          await conexionBox.put('network', false);
          break;
        case InternetConnectionStatus.slow:
          print('⚠️ Conexión lenta');
          await conexionBox.put('network', false); // Treat as disconnected
          break;
        default:
          print('⚠️ Estado desconocido');
          await conexionBox.put('network', false); // Treat as disconnected
          break;
      }
    });
  }

  void detenerEscucha() {
    listener?.cancel();
  }
}
