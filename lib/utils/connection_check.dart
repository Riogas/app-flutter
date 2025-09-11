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
  Timer? _timer;

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
    _setupConnectionBoxListener(); // Escuchar cambios en conexionBox
    _timer = Timer.periodic(checkInterval, (_) async {
      await _checkConnectivity();
    });
  }

  // Nuevo método para escuchar cambios en conexionBox
  Future<void> _setupConnectionBoxListener() async {
    print('👂 Configurando listener de cambios en conexionBox...');
    var conexionBox = await Hive.openBox('conexionBox');

    conexionBox.watch(key: 'conexionRioGas').listen((BoxEvent event) {
      bool isConnected = event.value ?? false;
      print('📦 ¡CAMBIO DETECTADO! conexionRioGas: $isConnected');

      if (!isConnected) {
        // Conexión perdida, iniciar timer de reconexión inmediatamente
        if (_rioGasTimer == null) {
          print('❌ Conexión RioGas perdida. Iniciando timer de reconexión...');
          _startRioGasTimer();
        } else {
          print('⏱️ Timer de reconexión ya está corriendo');
        }
      } else {
        // Conexión restaurada, procesar requests pendientes
        print('✅ Conexión RioGas restaurada.');
        _resetRioGasTimer();
        _processPendingRequestsAsync();
      }
    });
    print('✅ Listener de conexionBox configurado exitosamente');
  }

  // Método async separado para no bloquear el listener
  Future<void> _processPendingRequestsAsync() async {
    try {
      var failedRequestsBox = await Hive.openBox('failedRequestsBox');
      if (failedRequestsBox.isNotEmpty) {
        print(
            '📦 Procesando ${failedRequestsBox.length} requests pendientes tras reconexión...');
        await RioGasService.processPendingRequests();
      }
    } catch (e) {
      print('❌ Error procesando requests pendientes: $e');
    }
  }

  void stopMonitoring() {
    _timer?.cancel(); // ✅ Solo cancela si fue inicializado
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
    print('🔍 Iniciando chequeo de conectividad...');
    Map<String, dynamic> status = {
      'network': false,
      'firestore': false,
      'riogas': false,
      'showPopup': false, // Add flag for popup
    };

    try {
      // Check Internet connectivity and type FIRST
      var connectivityResult = await Connectivity().checkConnectivity();
      print('📡 Connectivity result: $connectivityResult');

      if (connectivityResult == ConnectivityResult.none) {
        print('❌ Sin conectividad de red');
        status['network'] = false;
      } else {
        bool hasInternet =
            await InternetConnectionChecker.createInstance().hasConnection;
        print('🌐 Internet check: $hasInternet');
        status['network'] = hasInternet;
      }

      // Check Firestore connectivity
      status['firestore'] =
          true; //await _firebaseService.checkFirestoreConnectivity();

      // Check RioGas connectivity only if we have internet
      if (status['network']) {
        status['riogas'] = await _checkRioGasConnectivity();
      } else {
        print('❌ Sin internet, marcando RioGas como desconectado');
        status['riogas'] = false;
      }

      // Update Hive box
      var conexionBox = await Hive.openBox('conexionBox');

      // Comparar valores anteriores para ver si hay cambios
      bool prevNetwork = await conexionBox.get('network', defaultValue: true);
      bool prevRioGas =
          await conexionBox.get('conexionRioGas', defaultValue: true);

      await conexionBox.put('conexionFirestore', status['firestore']);
      await conexionBox.put('conexionRioGas', status['riogas']);
      await conexionBox.put('network', status['network']);
      await conexionBox.put(
        'lastCheck',
        DateTime.now().toUtc().toIso8601String(),
      );

      // Log cambios importantes
      if (prevNetwork != status['network']) {
        print('🔄 Network cambió: $prevNetwork → ${status['network']}');
      }
      if (prevRioGas != status['riogas']) {
        print('🔄 RioGas cambió: $prevRioGas → ${status['riogas']}');
      }

      if (!status['riogas']) {
        if (_rioGasTimer == null) {
          _startRioGasTimer();
        }
      } else {
        // RioGas está conectado, procesar requests pendientes y resetear timer
        var failedRequestsBox = await Hive.openBox('failedRequestsBox');
        if (failedRequestsBox.isNotEmpty) {
          print(
              '📦 RioGas conectado. Procesando ${failedRequestsBox.length} requests pendientes...');
          await RioGasService.processPendingRequests();
        }
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
      print('🔍 Chequeando conectividad RioGas...');
      var sessionBox = await Hive.openBox('sessionBox');
      var deviceId = sessionBox.get('deviceId');

      if (deviceId == null || (deviceId is String && deviceId.isEmpty)) {
        print('❌ No deviceId found for RioGas connectivity check');
        return false;
      }

      print('📱 Usando deviceId: $deviceId');
      var response = await RioGasService.validarDispositivo(deviceId);

      if (response == null) {
        print('❌ RioGas response is null');
        return false;
      }

      print('📥 RioGas response: $response');
      bool isConnected = response['Existe'] == true ||
          response['success'] == true ||
          response['OK'] == 0 ||
          response['ok'] == 0;

      print(
          '🌐 RioGas connectivity result: ${isConnected ? "✅ Connected" : "❌ Disconnected"}');
      return isConnected;
    } catch (e) {
      print('❌ RioGas connectivity error: $e');
      await _logError('RioGas Connectivity Error', e.toString());
      return false;
    }
  }

  void _startRioGasTimer() {
    print('⏱️ Iniciando timer de reconexión RioGas (cada 5 segundos)...');
    _rioGasTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      _counter += 5; // Incrementar en 5 segundos
      print(
          '⏱️ Reintentando conexión RioGas... Tiempo transcurrido: $_counter segundos');

      // Intentar reconectar
      bool connected = await _checkRioGasConnectivity();
      if (connected) {
        print('✅ RioGas reconectado exitosamente!');
        var conexionBox = await Hive.openBox('conexionBox');
        await conexionBox.put('conexionRioGas', true);
        await conexionBox.put(
            'conexionRioGasTimestamp', DateTime.now().toIso8601String());

        // Procesar requests pendientes
        var failedRequestsBox = await Hive.openBox('failedRequestsBox');
        if (failedRequestsBox.isNotEmpty) {
          print(
              '📦 Procesando ${failedRequestsBox.length} requests pendientes...');
          await RioGasService.processPendingRequests();
        }

        _resetRioGasTimer();
        return;
      }

      if (_counter >= _maxCounter) {
        print(
            '⏱️ Tiempo máximo alcanzado ($_maxCounter segundos). Deteniendo reintentos.');
        _rioGasTimer?.cancel();
        _counter = 0;
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
    print('👂 Iniciando listener de cambios de internet...');
    listener = InternetConnectionChecker.createInstance()
        .onStatusChange
        .listen((status) async {
      print('📡 Internet status cambió a: $status');
      final conexionBox = await Hive.openBox('conexionBox');
      switch (status) {
        case InternetConnectionStatus.connected:
          print('✅ Conexión a Internet restaurada');
          await conexionBox.put('network', true);
          // No restablecer RioGas automáticamente, dejar que el chequeo lo determine
          break;
        case InternetConnectionStatus.disconnected:
          print('❌ Internet desconectado - marcando RioGas como false');
          await conexionBox.put('network', false);
          // Sin internet, RioGas también debe estar desconectado
          await conexionBox.put('conexionRioGas', false);
          break;
        case InternetConnectionStatus.slow:
          print('⚠️ Conexión lenta - marcando RioGas como false');
          await conexionBox.put('network', false);
          // Conexión lenta también afecta RioGas
          await conexionBox.put('conexionRioGas', false);
          break;
      }
      print(
          '📦 Box actualizado - network: ${await conexionBox.get('network')}, RioGas: ${await conexionBox.get('conexionRioGas')}');
    });
  }

  void detenerEscucha() {
    listener?.cancel();
  }
}
