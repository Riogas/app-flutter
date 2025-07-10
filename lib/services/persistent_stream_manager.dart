import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'firebase_service.dart';

/// Optimized stream manager with persistent listeners and ValueNotifiers
/// This eliminates the constant creation/removal of listeners
class PersistentStreamManager {
  static final PersistentStreamManager _instance =
      PersistentStreamManager._internal();
  factory PersistentStreamManager() => _instance;
  PersistentStreamManager._internal();

  final FirebaseService _firebaseService = FirebaseService();

  // ValueNotifiers for reactive UI updates
  final ValueNotifier<List<DocumentSnapshot>> _pedidosNotifier =
      ValueNotifier([]);
  final ValueNotifier<List<DocumentSnapshot>> _mensajesNotifier =
      ValueNotifier([]);
  final ValueNotifier<DocumentSnapshot?> _movilNotifier = ValueNotifier(null);
  final ValueNotifier<Map<String, dynamic>?> _sesionesNotifier =
      ValueNotifier(null);
  final ValueNotifier<List<Map<String, dynamic>>> _subEstadosNotifier =
      ValueNotifier([]);
  final ValueNotifier<List<Map<String, dynamic>>> _subEstadoMovilesNotifier =
      ValueNotifier([]);

  // Persistent stream subscriptions (never cancelled)
  StreamSubscription? _pedidosSubscription;
  StreamSubscription? _mensajesSubscription;
  StreamSubscription? _movilSubscription;
  StreamSubscription? _sesionesSubscription;
  StreamSubscription? _subEstadosSubscription;
  StreamSubscription? _subEstadoMovilesSubscription;

  // Listener counters for debugging
  int _pedidosListeners = 0;
  int _mensajesListeners = 0;
  int _movilListeners = 0;
  int _sesionesListeners = 0;
  int _subEstadosListeners = 0;
  int _subEstadoMovilesListeners = 0;

  // Read counters for each stream type
  int _pedidosReads = 0;
  int _mensajesReads = 0;
  int _movilReads = 0;
  int _sesionesReads = 0;
  int _subEstadosReads = 0;
  int _subEstadoMovilesReads = 0;

  // Initialization flag
  bool _initialized = false;

  /// Initialize all persistent listeners
  /// This should be called once at app startup
  Future<void> initialize() async {
    if (_initialized) return;

    print('🔄 [PersistentStreamManager] Initializing persistent listeners...');

    // Start all persistent listeners
    await _initializePedidosListener();
    await _initializeMensajesListener();
    await _initializeMovilListener();
    await _initializeSesionesListener();
    await _initializeSubEstadosListener();
    await _initializeSubEstadoMovilesListener();

    _initialized = true;
    print('✅ [PersistentStreamManager] All persistent listeners initialized');
  }

  /// Initialize persistent Pedidos listener
  Future<void> _initializePedidosListener() async {
    try {
      _pedidosSubscription = _firebaseService.getPedidosStream().listen(
        (List<DocumentSnapshot> pedidos) {
          _pedidosReads++;
          print(
              '📦 [PersistentStreamManager] Pedidos updated: ${pedidos.length} items (reads: $_pedidosReads)');
          _pedidosNotifier.value = pedidos;
        },
        onError: (error) {
          print('❌ [PersistentStreamManager] Pedidos stream error: $error');
        },
      );

      print('🔄 [PersistentStreamManager] Pedidos persistent listener started');
    } catch (e) {
      print(
          '❌ [PersistentStreamManager] Error initializing pedidos listener: $e');
    }
  }

  /// Initialize persistent Mensajes listener
  Future<void> _initializeMensajesListener() async {
    try {
      _mensajesSubscription = _firebaseService.getMensajesStream().listen(
        (List<DocumentSnapshot> mensajes) {
          _mensajesReads++;
          print(
              '💬 [PersistentStreamManager] Mensajes updated: ${mensajes.length} items (reads: $_mensajesReads)');
          _mensajesNotifier.value = mensajes;
        },
        onError: (error) {
          print('❌ [PersistentStreamManager] Mensajes stream error: $error');
        },
      );

      print(
          '🔄 [PersistentStreamManager] Mensajes persistent listener started');
    } catch (e) {
      print(
          '❌ [PersistentStreamManager] Error initializing mensajes listener: $e');
    }
  }

  /// Initialize persistent Movil listener
  Future<void> _initializeMovilListener() async {
    try {
      _movilSubscription = _firebaseService.getMovilStream().listen(
        (DocumentSnapshot? movil) {
          _movilReads++;
          print(
              '🚗 [PersistentStreamManager] Movil updated (reads: $_movilReads)');
          _movilNotifier.value = movil;
        },
        onError: (error) {
          print('❌ [PersistentStreamManager] Movil stream error: $error');
        },
      );

      print('🔄 [PersistentStreamManager] Movil persistent listener started');
    } catch (e) {
      print(
          '❌ [PersistentStreamManager] Error initializing movil listener: $e');
    }
  }

  /// Initialize persistent Sesiones listener
  Future<void> _initializeSesionesListener() async {
    try {
      _sesionesSubscription = _firebaseService.getSesionesStream().listen(
        (Map<String, dynamic>? sesiones) {
          _sesionesReads++;
          print(
              '🔐 [PersistentStreamManager] Sesiones updated (reads: $_sesionesReads)');
          _sesionesNotifier.value = sesiones;
        },
        onError: (error) {
          print('❌ [PersistentStreamManager] Sesiones stream error: $error');
        },
      );

      print(
          '🔄 [PersistentStreamManager] Sesiones persistent listener started');
    } catch (e) {
      print(
          '❌ [PersistentStreamManager] Error initializing sesiones listener: $e');
    }
  }

  /// Initialize persistent SubEstados listener
  Future<void> _initializeSubEstadosListener() async {
    try {
      _subEstadosSubscription =
          _firebaseService.getSubEstadoMovilesStream().listen(
        (List<Map<String, dynamic>> subEstados) {
          _subEstadosReads++;
          print(
              '📊 [PersistentStreamManager] SubEstados updated: ${subEstados.length} items (reads: $_subEstadosReads)');
          _subEstadosNotifier.value = subEstados;
        },
        onError: (error) {
          print('❌ [PersistentStreamManager] SubEstados stream error: $error');
        },
      );

      print(
          '🔄 [PersistentStreamManager] SubEstados persistent listener started');
    } catch (e) {
      print(
          '❌ [PersistentStreamManager] Error initializing subEstados listener: $e');
    }
  }

  /// Initialize persistent SubEstadoMoviles listener
  Future<void> _initializeSubEstadoMovilesListener() async {
    try {
      _subEstadoMovilesSubscription =
          _firebaseService.getSubEstadoMovilesStream().listen(
        (List<Map<String, dynamic>> subEstadoMoviles) {
          _subEstadoMovilesReads++;
          print(
              '🚗📊 [PersistentStreamManager] SubEstadoMoviles updated: ${subEstadoMoviles.length} items (reads: $_subEstadoMovilesReads)');
          _subEstadoMovilesNotifier.value = subEstadoMoviles;
        },
        onError: (error) {
          print(
              '❌ [PersistentStreamManager] SubEstadoMoviles stream error: $error');
        },
      );

      print(
          '🔄 [PersistentStreamManager] SubEstadoMoviles persistent listener started');
    } catch (e) {
      print(
          '❌ [PersistentStreamManager] Error initializing subEstadoMoviles listener: $e');
    }
  }

  // Getters for ValueNotifiers (widgets subscribe to these)
  ValueNotifier<List<DocumentSnapshot>> get pedidosNotifier {
    _pedidosListeners++;
    print(
        '👂 [PersistentStreamManager] Pedidos listener added (total: $_pedidosListeners)');
    return _pedidosNotifier;
  }

  ValueNotifier<List<DocumentSnapshot>> get mensajesNotifier {
    _mensajesListeners++;
    print(
        '👂 [PersistentStreamManager] Mensajes listener added (total: $_mensajesListeners)');
    return _mensajesNotifier;
  }

  ValueNotifier<DocumentSnapshot?> get movilNotifier {
    _movilListeners++;
    print(
        '👂 [PersistentStreamManager] Movil listener added (total: $_movilListeners)');
    return _movilNotifier;
  }

  ValueNotifier<Map<String, dynamic>?> get sesionesNotifier {
    _sesionesListeners++;
    print(
        '👂 [PersistentStreamManager] Sesiones listener added (total: $_sesionesListeners)');
    return _sesionesNotifier;
  }

  ValueNotifier<List<Map<String, dynamic>>> get subEstadosNotifier {
    _subEstadosListeners++;
    print(
        '👂 [PersistentStreamManager] SubEstados listener added (total: $_subEstadosListeners)');
    return _subEstadosNotifier;
  }

  ValueNotifier<List<Map<String, dynamic>>> get subEstadoMovilesNotifier {
    _subEstadoMovilesListeners++;
    print(
        '👂 [PersistentStreamManager] SubEstadoMoviles listener added (total: $_subEstadoMovilesListeners)');
    return _subEstadoMovilesNotifier;
  }

  // Convenience getters for current values
  List<DocumentSnapshot> get pedidos => _pedidosNotifier.value;
  List<DocumentSnapshot> get mensajes => _mensajesNotifier.value;
  DocumentSnapshot? get movil => _movilNotifier.value;
  Map<String, dynamic>? get sesiones => _sesionesNotifier.value;
  List<Map<String, dynamic>> get subEstados => _subEstadosNotifier.value;
  List<Map<String, dynamic>> get subEstadoMoviles =>
      _subEstadoMovilesNotifier.value;

  // Counts for widgets listening to each notifier
  int get pedidosListenerCount => _pedidosListeners;
  int get mensajesListenerCount => _mensajesListeners;
  int get movilListenerCount => _movilListeners;
  int get sesionesListenerCount => _sesionesListeners;
  int get subEstadosListenerCount => _subEstadosListeners;
  int get subEstadoMovilesListenerCount => _subEstadoMovilesListeners;

  // Total active listeners (always 6 after initialization)
  int get totalActiveListeners => 6;

  // Total widget listeners across all notifiers
  int get totalWidgetListeners =>
      _pedidosListeners +
      _mensajesListeners +
      _movilListeners +
      _sesionesListeners +
      _subEstadosListeners +
      _subEstadoMovilesListeners;

  // Read counts
  int get pedidosReads => _pedidosReads;
  int get mensajesReads => _mensajesReads;
  int get movilReads => _movilReads;
  int get sesionesReads => _sesionesReads;
  int get subEstadosReads => _subEstadosReads;
  int get subEstadoMovilesReads => _subEstadoMovilesReads;

  int get totalReads =>
      _pedidosReads +
      _mensajesReads +
      _movilReads +
      _sesionesReads +
      _subEstadosReads +
      _subEstadoMovilesReads;

  /// Print diagnostic information
  void printDiagnostics() {
    print('\n🔍 [PersistentStreamManager] DIAGNOSTICS');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📊 Active Stream Listeners: $totalActiveListeners (persistent)');
    print('📊 Widget Listeners: $totalWidgetListeners');
    print('📊 Total Reads: $totalReads');
    print('');
    print('Per Stream Breakdown:');
    print('  📦 Pedidos: $_pedidosListeners widgets, $_pedidosReads reads');
    print('  💬 Mensajes: $_mensajesListeners widgets, $_mensajesReads reads');
    print('  🚗 Movil: $_movilListeners widgets, $_movilReads reads');
    print('  🔐 Sesiones: $_sesionesListeners widgets, $_sesionesReads reads');
    print(
        '  📊 SubEstados: $_subEstadosListeners widgets, $_subEstadosReads reads');
    print(
        '  🚗📊 SubEstadoMoviles: $_subEstadoMovilesListeners widgets, $_subEstadoMovilesReads reads');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }

  /// Reset all counters
  void resetCounters() {
    _pedidosListeners = 0;
    _mensajesListeners = 0;
    _movilListeners = 0;
    _sesionesListeners = 0;
    _subEstadosListeners = 0;
    _subEstadoMovilesListeners = 0;

    _pedidosReads = 0;
    _mensajesReads = 0;
    _movilReads = 0;
    _sesionesReads = 0;
    _subEstadosReads = 0;
    _subEstadoMovilesReads = 0;

    print('🔄 [PersistentStreamManager] All counters reset');
  }

  /// Dispose all listeners (should only be called on app termination)
  void dispose() {
    print('🔄 [PersistentStreamManager] Disposing all listeners...');

    _pedidosSubscription?.cancel();
    _mensajesSubscription?.cancel();
    _movilSubscription?.cancel();
    _sesionesSubscription?.cancel();
    _subEstadosSubscription?.cancel();
    _subEstadoMovilesSubscription?.cancel();

    _pedidosNotifier.dispose();
    _mensajesNotifier.dispose();
    _movilNotifier.dispose();
    _sesionesNotifier.dispose();
    _subEstadosNotifier.dispose();
    _subEstadoMovilesNotifier.dispose();

    _initialized = false;
    print('✅ [PersistentStreamManager] All listeners disposed');
  }
}
