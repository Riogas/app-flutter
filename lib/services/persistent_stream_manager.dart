import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'firebase_service.dart';
import 'package:hive/hive.dart';

/// Optimized stream manager with persistent listeners and ValueNotifiers
/// This eliminates the constant creation/removal of listeners
class PersistentStreamManager {
  // ValueNotifier for SubEstadoFinalizacionPedidos
  final ValueNotifier<List<Map<String, dynamic>>>
      _subEstadoFinalizacionPedidosNotifier = ValueNotifier([]);
  StreamSubscription? _subEstadoFinalizacionPedidosSubscription;
  // --- Real listener tracking ---
  final Map<String, int> _activeListeners = {
    'pedidos': 0,
    'mensajes': 0,
    'movil': 0,
    'sesiones': 0,
    'subEstados': 0,
    'subEstadoMoviles': 0,
  };

  void _incrementListener(String key) {
    _activeListeners[key] = (_activeListeners[key] ?? 0) + 1;
    _logToMonitoreo('ActiveListeners_$key', _activeListeners[key]);
    _logToMonitoreo('ActiveListenersTotal',
        _activeListeners.values.reduce((a, b) => a + b));
  }

  void _decrementListener(String key) {
    if (_activeListeners[key] != null && _activeListeners[key]! > 0) {
      _activeListeners[key] = _activeListeners[key]! - 1;
      _logToMonitoreo('ActiveListeners_' + key, _activeListeners[key]);
      _logToMonitoreo('ActiveListenersTotal',
          _activeListeners.values.reduce((a, b) => a + b));
    }
  }

  // --- Monitoreo Hive box for diagnostics ---
  Future<void> _logToMonitoreo(String etiqueta, dynamic valor) async {
    try {
      var box = await Hive.openBox('Monitoreo');
      await box.put(etiqueta, valor);
    } catch (e) {
      print('❌ [PersistentStreamManager] Error logging to Monitoreo: $e');
    }
  }

  // --- Centralized Hive sync for mensajes and pedidos ---
  bool _hiveSyncInitialized = false;
  void initializeHiveSync() {
    if (_hiveSyncInitialized) return;
    _hiveSyncInitialized = true;
    // Escucha cambios en mensajesNotifier y sincroniza con Hive
    _mensajesNotifier.addListener(() async {
      final mensajes = _mensajesNotifier.value;
      var mensajesBox = await _openBoxSafe('mensajesBox');
      if (mensajesBox == null) return;
      List<DocumentSnapshot> nuevos = [];
      for (var message in mensajes) {
        var data = message.data() as Map<String, dynamic>?;
        if (!mensajesBox.containsKey(message.id) &&
            (data == null ||
                data['VisibleEnApp'] == null ||
                data['VisibleEnApp'] == 'S')) {
          await mensajesBox.put(message.id, 'Descargado');
          nuevos.add(message);
        } else if (data != null &&
            data['VisibleEnApp'] == 'N' &&
            mensajesBox.containsKey(message.id)) {
          await mensajesBox.put(message.id, 'Leido');
        }
      }
      if (nuevos.isNotEmpty) {
        print(
            '🟢 [PersistentStreamManager] Nuevos mensajes descargados: ${nuevos.length}');
      }
    });
    // Escucha cambios en pedidosNotifier y sincroniza con Hive
    _pedidosNotifier.addListener(() async {
      final pedidos = _pedidosNotifier.value;
      var pedidosBox = await _openBoxSafe('pedidosBox');
      if (pedidosBox == null) return;
      List<DocumentSnapshot> nuevos = [];
      for (var pedido in pedidos) {
        var data = pedido.data() as Map<String, dynamic>?;
        int? pedidoId;
        if (data != null && data.containsKey('id')) {
          pedidoId = data['id'] is int
              ? data['id']
              : int.tryParse(data['id'].toString());
        }
        if (pedidoId == null) continue;
        if (!pedidosBox.containsKey(pedidoId)) {
          await pedidosBox.put(pedidoId, 'No Leído');
          nuevos.add(pedido);
        }
        // Si el pedido ya está en Hive, no lo sobreescribimos aquí (solo el usuario lo marca como leído o cambia de estado)
      }
      if (nuevos.isNotEmpty) {
        print(
            '🟢 [PersistentStreamManager] Nuevos pedidos sincronizados: ${nuevos.length}');
      }
    });
    print(
        '✅ [PersistentStreamManager] Hive sync for mensajes y pedidos activado');
  }

  Future<dynamic> _openBoxSafe(String boxName) async {
    try {
      if (!await Future.value(Hive.isBoxOpen(boxName))) {
        return await Hive.openBox(boxName);
      }
      return Hive.box(boxName);
    } catch (e) {
      print('❌ [PersistentStreamManager] Error abriendo la caja $boxName: $e');
      return null;
    }
  }

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
  DateTime? lastInitializationTime;

  /// Initialize all persistent listeners
  /// This should be called once at app startup
  Future<void> initialize() async {
    if (_initialized) return;

    lastInitializationTime = DateTime.now();
    print('[PersistentStreamManager] Initializing persistent listeners...');

    print('🔄 [PersistentStreamManager] Initializing persistent listeners...');

    // 🔒 VALIDAR SESIÓN ANTES DE INICIAR CUALQUIER LISTENER
    final sessionBox = await Hive.openBox('sessionBox');
    final movil = sessionBox.get('movil');
    final username = sessionBox.get('username');
    final escenario = sessionBox.get('escenario');

    // Si NO hay sesión válida, NO iniciar ningún listener de Firestore
    if (movil == null ||
        username == null ||
        escenario == null ||
        movil.toString() == '0' ||
        username.toString() == '0' ||
        escenario.toString() == '0') {
      print(
          '⏸️ [PersistentStreamManager] ⚠️ NO hay sesión activa, listeners de Firestore NO iniciados');
      print('   - Movil: $movil');
      print('   - Username: $username');
      print('   - Escenario: $escenario');
      _initialized = true; // Marcar como inicializado para evitar reintentos
      return; // 🛑 SALIR SIN INICIAR LISTENERS
    }

    print(
        '✅ [PersistentStreamManager] Sesión válida detectada, iniciando listeners...');
    print('   - Movil: $movil');
    print('   - Username: $username');
    print('   - Escenario: $escenario');

    // Start all persistent listeners
    await _initializePedidosListener();
    await _initializeMensajesListener();
    await _initializeMovilListener();
    await _initializeSesionesListener();
    await _initializeSubEstadosListener();
    await _initializeSubEstadoMovilesListener();

    await _initializeSubEstadoFinalizacionPedidosListener();

    _initialized = true;
    print('✅ [PersistentStreamManager] All persistent listeners initialized');
  }

  /// 🆕 Iniciar TODOS los listeners después del login exitoso
  Future<void> startSesionesListenerAfterLogin() async {
    print(
        '🔐 [PersistentStreamManager] Iniciando TODOS los listeners post-login...');

    // Reiniciar la bandera de inicialización para forzar recreación
    _initialized = false;

    // Llamar a initialize() que ahora validará la sesión y arrancará todos los listeners
    await initialize();

    print(
        '✅ [PersistentStreamManager] Todos los listeners iniciados después del login');
  }

  /// Initialize persistent Pedidos listener
  Future<void> _initializePedidosListener() async {
    try {
      final movil = Hive.box('sessionBox').get('movil');

      print('[PersistentStreamManager] Movil obtenido: $movil');
      _pedidosSubscription = _firebaseService.getPedidosStream().listen(
        (List<DocumentSnapshot> pedidos) {
          _pedidosReads += pedidos.length;

          // 🔎 Mostrar todos los documentos crudos antes de filtrar
          print(
              '📄 [PersistentStreamManager] Pedidos recibidos sin filtrar (${pedidos.length}):');
          for (var doc in pedidos) {
            print('  ➖ Pedido ID: ${doc.id}, Data: ${doc.data()}');
          }

          // 🔹 Aplicar el filtro
          final pedidosFiltrados = pedidos.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['EstadoNro'] == 1 &&
                data['VisibleEnApp'] == 'S' &&
                data['Movil'] == int.tryParse(movil);
          }).toList();

          // ✅ Mostrar los pedidos que pasaron el filtro
          print(
              '✅ [PersistentStreamManager] Pedidos filtrados (${pedidosFiltrados.length}):');
          for (var doc in pedidosFiltrados) {
            print('  🟢 Pedido ID: ${doc.id}, Data: ${doc.data()}');
          }

          _pedidosNotifier.value = pedidosFiltrados;

          _logToMonitoreo('PedidosReads', _pedidosReads);
          _logToMonitoreo('TotalReads', totalReads);
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
          // Increment by the number of documents received (real Firestore reads)
          _mensajesReads += mensajes.length;
          print(
              '💬 [PersistentStreamManager] Mensajes updated: ${mensajes.length} items (reads: $_mensajesReads)');
          _mensajesNotifier.value = mensajes;
          // Log to Hive every time the read counter changes
          _logToMonitoreo('MensajesReads', _mensajesReads);
          _logToMonitoreo('TotalReads', totalReads);
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

  void reset() {
    print('🔄 [PersistentStreamManager] Reseteando estado interno');

    _pedidosSubscription?.cancel();
    _mensajesSubscription?.cancel();
    _movilSubscription?.cancel();
    _sesionesSubscription?.cancel();
    _subEstadosSubscription?.cancel();
    _subEstadoMovilesSubscription?.cancel();

    // NO uses .dispose() en notifiers si pensás reusarlos, mejor:
    _pedidosNotifier.value = [];
    _mensajesNotifier.value = [];
    _movilNotifier.value = null;
    _sesionesNotifier.value = null;
    _subEstadosNotifier.value = [];
    _subEstadoMovilesNotifier.value = [];

    _hiveSyncInitialized = false;
    _initialized = false;
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
          // Log to Hive every time the read counter changes
          _logToMonitoreo('MovilReads', _movilReads);
          _logToMonitoreo('TotalReads', totalReads);
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

  Future<void> _initializeSesionesListener() async {
    try {
      // 🔒 No inicializar si no hay usuario/escenario (pre-login)
      final sessionBox = Hive.box('sessionBox');
      final usuario = sessionBox.get('username');
      final escenario = sessionBox.get('escenario');

      print(
          '🔍 [PersistentStreamManager] _initializeSesionesListener: usuario=$usuario, escenario=$escenario');

      if (usuario == null || escenario == null) {
        print(
            '⏸️ [PersistentStreamManager] Sesiones listener NO iniciado (sin sesión activa)');
        return;
      }

      print('🚀 [PersistentStreamManager] Iniciando getSesionesStream()...');
      _sesionesSubscription = _firebaseService.getSesionesStream().listen(
        (Map<String, dynamic>? sesiones) {
          _sesionesReads++;
          print(
              '🔐 [PersistentStreamManager] Sesiones updated (reads: $_sesionesReads)');

          if (_sesionesNotifier.value != sesiones) {
            _sesionesNotifier.value = sesiones;
          } else {
            _sesionesNotifier.value = sesiones == null ? {} : {...sesiones};
          }

          _logToMonitoreo('SesionesReads', _sesionesReads);
          _logToMonitoreo('TotalReads', totalReads);
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
          // Increment by the number of documents received (real Firestore reads)
          _subEstadosReads += subEstados.length;
          print(
              '📊 [PersistentStreamManager] SubEstados updated: ${subEstados.length} items (reads: $_subEstadosReads)');
          _subEstadosNotifier.value = subEstados;
          // Log to Hive every time the read counter changes
          _logToMonitoreo('SubEstadosReads', _subEstadosReads);
          _logToMonitoreo('TotalReads', totalReads);
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
          // Increment by the number of documents received (real Firestore reads)
          _subEstadoMovilesReads += subEstadoMoviles.length;
          print(
              '🚗📊 [PersistentStreamManager] SubEstadoMoviles updated: ${subEstadoMoviles.length} items (reads: $_subEstadoMovilesReads)');
          _subEstadoMovilesNotifier.value = subEstadoMoviles;
          // Log to Hive every time the read counter changes
          _logToMonitoreo('SubEstadoMovilesReads', _subEstadoMovilesReads);
          _logToMonitoreo('TotalReads', totalReads);
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

  /// Initialize persistent SubEstadoFinalizacionPedidos listener
  Future<void> _initializeSubEstadoFinalizacionPedidosListener() async {
    try {
      _subEstadoFinalizacionPedidosSubscription =
          _firebaseService.getSubEstadoFinalizacionPedidosStream().listen(
        (List<Map<String, dynamic>> subEstadosFinalizacionPedidos) {
          print(
              '✅ [PersistentStreamManager] SubEstadoFinalizacionPedidos updated: ${subEstadosFinalizacionPedidos.length} items');
          _subEstadoFinalizacionPedidosNotifier.value =
              subEstadosFinalizacionPedidos;
        },
        onError: (error) {
          print(
              '❌ [PersistentStreamManager] SubEstadoFinalizacionPedidos stream error: $error');
        },
      );
      print(
          '🔄 [PersistentStreamManager] SubEstadoFinalizacionPedidos persistent listener started');
    } catch (e) {
      print(
          '❌ [PersistentStreamManager] Error initializing SubEstadoFinalizacionPedidos listener: $e');
    }
  }

  // --- Gestión manual de listeners por widget ---
  void removeListener(String streamType) {
    switch (streamType) {
      case 'pedidos':
        if (_pedidosListeners > 0) {
          _pedidosListeners--;
          _decrementListener('pedidos');
          _logToMonitoreo('PedidosListenerCount', _pedidosListeners);
          _logToMonitoreo('TotalWidgetListeners', totalWidgetListeners);
          print(
              '🗑️ [PersistentStreamManager] Pedidos listener removed (remaining: $_pedidosListeners)');
        }
        break;
      case 'mensajes':
        if (_mensajesListeners > 0) {
          _mensajesListeners--;
          _decrementListener('mensajes');
          _logToMonitoreo('MensajesListenerCount', _mensajesListeners);
          _logToMonitoreo('TotalWidgetListeners', totalWidgetListeners);
          print(
              '🗑️ [PersistentStreamManager] Mensajes listener removed (remaining: $_mensajesListeners)');
        }
        break;
      case 'movil':
        if (_movilListeners > 0) {
          _movilListeners--;
          _decrementListener('movil');
          _logToMonitoreo('MovilListenerCount', _movilListeners);
          _logToMonitoreo('TotalWidgetListeners', totalWidgetListeners);
          print(
              '🗑️ [PersistentStreamManager] Movil listener removed (remaining: $_movilListeners)');
        }
        break;
      case 'sesiones':
        if (_sesionesListeners > 0) {
          _sesionesListeners--;
          _decrementListener('sesiones');
          _logToMonitoreo('SesionesListenerCount', _sesionesListeners);
          _logToMonitoreo('TotalWidgetListeners', totalWidgetListeners);
          print(
              '🗑️ [PersistentStreamManager] Sesiones listener removed (remaining: $_sesionesListeners)');
        }
        break;
      case 'subEstados':
        if (_subEstadosListeners > 0) {
          _subEstadosListeners--;
          _decrementListener('subEstados');
          _logToMonitoreo('SubEstadosListenerCount', _subEstadosListeners);
          _logToMonitoreo('TotalWidgetListeners', totalWidgetListeners);
          print(
              '🗑️ [PersistentStreamManager] SubEstados listener removed (remaining: $_subEstadosListeners)');
        }
        break;
      case 'subEstadoMoviles':
        if (_subEstadoMovilesListeners > 0) {
          _subEstadoMovilesListeners--;
          _decrementListener('subEstadoMoviles');
          _logToMonitoreo(
              'SubEstadoMovilesListenerCount', _subEstadoMovilesListeners);
          _logToMonitoreo('TotalWidgetListeners', totalWidgetListeners);
          print(
              '🗑️ [PersistentStreamManager] SubEstadoMoviles listener removed (remaining: $_subEstadoMovilesListeners)');
        }
        break;
    }
  }

  void removeListeners(List<String> streamTypes) {
    for (String streamType in streamTypes) {
      removeListener(streamType);
    }
  }

  // --- Métodos de monitoreo detallado ---
  Map<String, int> get activeListenersMap => Map.from(_activeListeners);

  Map<String, Map<String, int>> getDetailedListenerInfo() {
    return {
      'pedidos': {
        'widgetListeners': _pedidosListeners,
        'activeListeners': _activeListeners['pedidos'] ?? 0,
        'reads': _pedidosReads,
      },
      'mensajes': {
        'widgetListeners': _mensajesListeners,
        'activeListeners': _activeListeners['mensajes'] ?? 0,
        'reads': _mensajesReads,
      },
      'movil': {
        'widgetListeners': _movilListeners,
        'activeListeners': _activeListeners['movil'] ?? 0,
        'reads': _movilReads,
      },
      'sesiones': {
        'widgetListeners': _sesionesListeners,
        'activeListeners': _activeListeners['sesiones'] ?? 0,
        'reads': _sesionesReads,
      },
      'subEstados': {
        'widgetListeners': _subEstadosListeners,
        'activeListeners': _activeListeners['subEstados'] ?? 0,
        'reads': _subEstadosReads,
      },
      'subEstadoMoviles': {
        'widgetListeners': _subEstadoMovilesListeners,
        'activeListeners': _activeListeners['subEstadoMoviles'] ?? 0,
        'reads': _subEstadoMovilesReads,
      },
    };
  }

  void printListenerSummary() {
    print('\n📊 [PersistentStreamManager] LISTENER SUMMARY');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔄 Persistent Streams Active: $totalActiveListeners/6');
    print('📱 Total Widget Listeners: $totalWidgetListeners');
    print('📖 Total Database Reads: $totalReads');
    print('');
    final info = getDetailedListenerInfo();
    info.forEach((streamName, data) {
      print(
          '  📊 $streamName: ${data['widgetListeners']} widgets, ${data['activeListeners']} active, ${data['reads']} reads');
    });
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }

  bool get isProperlyInitialized {
    return _initialized &&
        _pedidosSubscription != null &&
        _mensajesSubscription != null &&
        _movilSubscription != null &&
        _sesionesSubscription != null &&
        _subEstadosSubscription != null &&
        _subEstadoMovilesSubscription != null;
  }

  // Getters for ValueNotifiers (widgets subscribe to these)
  ValueNotifier<List<DocumentSnapshot>> get pedidosNotifier {
    _pedidosListeners++;
    print(
        '👂 [PersistentStreamManager] Pedidos listener added (total: $_pedidosListeners)');
    _incrementListener('pedidos');
    _logToMonitoreo('PedidosListenerCount', _pedidosListeners);
    _logToMonitoreo('TotalWidgetListeners', totalWidgetListeners);
    _logToMonitoreo('PedidosReads', _pedidosReads);
    _logToMonitoreo('TotalReads', totalReads);
    // Attach a removal callback for real listener tracking
    _pedidosNotifier.addListener(() {
      // No-op, just to ensure listener is tracked
    });
    // Remove listener when widget is disposed
    _pedidosNotifier.addListener(() {
      // This will be called on dispose, so decrement
      _decrementListener('pedidos');
    });
    return _pedidosNotifier;
  }

  ValueNotifier<List<DocumentSnapshot>> get mensajesNotifier {
    _mensajesListeners++;
    print(
        '👂 [PersistentStreamManager] Mensajes listener added (total: $_mensajesListeners)');
    _incrementListener('mensajes');
    _logToMonitoreo('MensajesListenerCount', _mensajesListeners);
    _logToMonitoreo('TotalWidgetListeners', totalWidgetListeners);
    _logToMonitoreo('MensajesReads', _mensajesReads);
    _logToMonitoreo('TotalReads', totalReads);
    _mensajesNotifier.addListener(() {});
    _mensajesNotifier.addListener(() {
      _decrementListener('mensajes');
    });
    return _mensajesNotifier;
  }

  ValueNotifier<DocumentSnapshot?> get movilNotifier {
    _movilListeners++;
    print(
        '👂 [PersistentStreamManager] Movil listener added (total: $_movilListeners)');
    _incrementListener('movil');
    _logToMonitoreo('MovilListenerCount', _movilListeners);
    _logToMonitoreo('TotalWidgetListeners', totalWidgetListeners);
    _logToMonitoreo('MovilReads', _movilReads);
    _logToMonitoreo('TotalReads', totalReads);
    _movilNotifier.addListener(() {});
    _movilNotifier.addListener(() {
      _decrementListener('movil');
    });
    return _movilNotifier;
  }

  ValueNotifier<Map<String, dynamic>?> get sesionesNotifier {
    _sesionesListeners++;
    print(
        '👂 [PersistentStreamManager] Sesiones listener added (total: $_sesionesListeners)');
    _incrementListener('sesiones');
    _logToMonitoreo('SesionesListenerCount', _sesionesListeners);
    _logToMonitoreo('TotalWidgetListeners', totalWidgetListeners);
    _logToMonitoreo('SesionesReads', _sesionesReads);
    _logToMonitoreo('TotalReads', totalReads);
    _sesionesNotifier.addListener(() {});
    _sesionesNotifier.addListener(() {
      _decrementListener('sesiones');
    });
    return _sesionesNotifier;
  }

  ValueNotifier<List<Map<String, dynamic>>> get subEstadosNotifier {
    _subEstadosListeners++;
    print(
        '👂 [PersistentStreamManager] SubEstados listener added (total: $_subEstadosListeners)');
    _incrementListener('subEstados');
    _logToMonitoreo('SubEstadosListenerCount', _subEstadosListeners);
    _logToMonitoreo('TotalWidgetListeners', totalWidgetListeners);
    _logToMonitoreo('SubEstadosReads', _subEstadosReads);
    _logToMonitoreo('TotalReads', totalReads);
    _subEstadosNotifier.addListener(() {});
    _subEstadosNotifier.addListener(() {
      _decrementListener('subEstados');
    });
    return _subEstadosNotifier;
  }

  ValueNotifier<List<Map<String, dynamic>>> get subEstadoMovilesNotifier {
    _subEstadoMovilesListeners++;
    print(
        '👂 [PersistentStreamManager] SubEstadoMoviles listener added (total: $_subEstadoMovilesListeners)');
    _incrementListener('subEstadoMoviles');
    _logToMonitoreo(
        'SubEstadoMovilesListenerCount', _subEstadoMovilesListeners);
    _logToMonitoreo('TotalWidgetListeners', totalWidgetListeners);
    _logToMonitoreo('SubEstadoMovilesReads', _subEstadoMovilesReads);
    _logToMonitoreo('TotalReads', totalReads);
    _subEstadoMovilesNotifier.addListener(() {});
    _subEstadoMovilesNotifier.addListener(() {
      _decrementListener('subEstadoMoviles');
    });
    return _subEstadoMovilesNotifier;
  }

  ValueNotifier<List<Map<String, dynamic>>>
      get subEstadoFinalizacionPedidosNotifier {
    return _subEstadoFinalizacionPedidosNotifier;
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
    _logToMonitoreo('ActiveStreamListeners', totalActiveListeners);
    _logToMonitoreo('WidgetListeners', totalWidgetListeners);
    _logToMonitoreo('TotalReads', totalReads);
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
    _logToMonitoreo('PedidosReads', _pedidosReads);
    _logToMonitoreo('MensajesReads', _mensajesReads);
    _logToMonitoreo('MovilReads', _movilReads);
    _logToMonitoreo('SesionesReads', _sesionesReads);
    _logToMonitoreo('SubEstadosReads', _subEstadosReads);
    _logToMonitoreo('SubEstadoMovilesReads', _subEstadoMovilesReads);
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

    // ❌ NO hacer esto:
    // _pedidosNotifier.dispose();  👈❌
    // _mensajesNotifier.dispose(); 👈❌
    // etc.

    _initialized = false;
    _hiveSyncInitialized = false;

    print('✅ [PersistentStreamManager] All listeners disposed (soft)');
  }
}
