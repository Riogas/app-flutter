import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'firebase_service.dart';
import 'package:hive/hive.dart';
import 'logout_service.dart';
import 'navigation_service.dart';

/// Optimized stream manager with persistent listeners and ValueNotifiers
/// This eliminates the constant creation/removal of listeners
class PersistentStreamManager {
  // ValueNotifier for SubEstadoFinalizacionPedidos
  final ValueNotifier<List<Map<String, dynamic>>>
      _subEstadoFinalizacionPedidosNotifier = ValueNotifier([]);
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
  // 🎁 Promociones vigentes (rediseño Home V2)
  final ValueNotifier<List<DocumentSnapshot>> _promocionesNotifier =
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
  StreamSubscription? _promocionesSubscription;
  StreamSubscription? _movilSubscription;
  StreamSubscription? _sesionesSubscription;

  /// 🎁 Notifier de promociones vigentes (filtradas por fecha y móvil)
  ValueNotifier<List<DocumentSnapshot>> get promocionesNotifier =>
      _promocionesNotifier;

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
  // SubEstados/SubEstadoMoviles ya no son streams (get() + cache Hive TTL 24h,
  // ver _loadCatalog); se mantienen en 0 para no romper printDiagnostics/resetCounters.
  int _subEstadosReads = 0;
  int _subEstadoMovilesReads = 0;

  // 🛡️ SISTEMA DE VALIDACIÓN ROBUSTA DE SESIÓN
  // ============================================

  /// Control de logout en progreso para evitar loops
  bool _isLoggingOut = false;

  /// Timestamp de la última vez que se detectó sesión válida
  DateTime? _lastValidSessionTimestamp;

  /// Timestamp de la última vez que se detectó sesión NULA
  DateTime? _lastNullSessionTimestamp;

  /// Contador de detecciones consecutivas de sesión nula
  int _consecutiveNullDetections = 0;

  /// Umbral de tiempo (en segundos) antes de confirmar invalidación
  static const int _gracePeriodSeconds = 5;

  /// Máximo de detecciones nulas consecutivas antes de actuar
  static const int _maxConsecutiveNulls = 2;

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
    await _initializePromocionesListener();
    await _initializeMovilListener();
    await _initializeSesionesListener();
    await _loadSubEstadosCatalogos();

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
    _promocionesSubscription?.cancel();
    _movilSubscription?.cancel();
    _sesionesSubscription?.cancel();
    // SubEstados/SubEstadoMoviles/SubEstadoFinalizacionPedidos ya no tienen
    // subscription que cancelar (get() + cache Hive, ver _loadCatalog).

    // NO uses .dispose() en notifiers si pensás reusarlos, mejor:
    _pedidosNotifier.value = [];
    _mensajesNotifier.value = [];
    _promocionesNotifier.value = [];
    _movilNotifier.value = null;
    _sesionesNotifier.value = null;
    _subEstadosNotifier.value = [];
    _subEstadoMovilesNotifier.value = [];

    _hiveSyncInitialized = false;
    _initialized = false;
  }

  /// 🎁 Initialize persistent Promociones listener (rediseño Home V2)
  /// Filtra client-side: VisibleEnApp=='S', vigencia FchDesde<=hoy<=FchHasta
  /// (int AAAAMMDD) y Movil (0/ausente = todos los móviles).
  Future<void> _initializePromocionesListener() async {
    try {
      final movil = int.tryParse(
              Hive.box('sessionBox').get('movil', defaultValue: '0').toString()) ??
          0;

      _promocionesSubscription =
          _firebaseService.getPromocionesStream().listen(
        (List<DocumentSnapshot> promos) {
          final hoyDt = DateTime.now().toUtc().subtract(Duration(hours: 3));
          final hoy = hoyDt.year * 10000 + hoyDt.month * 100 + hoyDt.day;

          final vigentes = promos.where((doc) {
            final data = doc.data() as Map<String, dynamic>?;
            if (data == null) return false;
            if (data['VisibleEnApp'] != 'S') return false;
            final desde =
                int.tryParse(data['FchDesde']?.toString() ?? '') ?? 0;
            final hasta =
                int.tryParse(data['FchHasta']?.toString() ?? '') ?? 99999999;
            if (hoy < desde || hoy > hasta) return false;
            final promoMovil =
                int.tryParse(data['Movil']?.toString() ?? '') ?? 0;
            if (promoMovil != 0 && promoMovil != movil) return false;
            return true;
          }).toList();

          print(
              '🎁 [PersistentStreamManager] Promociones vigentes: ${vigentes.length}/${promos.length}');
          _promocionesNotifier.value = vigentes;
        },
        onError: (error) {
          print(
              '❌ [PersistentStreamManager] Promociones stream error: $error');
        },
      );

      print(
          '🔄 [PersistentStreamManager] Promociones persistent listener started');
    } catch (e) {
      print(
          '❌ [PersistentStreamManager] Error initializing promociones listener: $e');
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

          // 🛡️ VALIDACIÓN ROBUSTA DE SESIÓN
          _handleSessionValidation(sesiones);

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
          // 🛡️ En caso de error de stream, asumir sesión válida (conservador)
          print(
              '🛡️ [PersistentStreamManager] Error en stream - asumiendo sesión válida (conservador)');
        },
      );

      print(
          '🔄 [PersistentStreamManager] Sesiones persistent listener started');
    } catch (e) {
      print(
          '❌ [PersistentStreamManager] Error initializing sesiones listener: $e');
    }
  }

  static const _catalogTtlHours = 24;

  /// Carga los catálogos SubEstado (get() único + cache Hive con TTL 24h).
  /// Sirve el cache al instante y refresca en background si venció el TTL
  /// o no había cache. Si Firestore falla, se sigue sirviendo el cache.
  /// Nunca lanza: un fallo de Hive o de Firestore se loguea y como mucho
  /// deja el notifier con su valor previo (la app siempre arranca/loguea).
  Future<void> _loadCatalog({
    required String cacheKey,
    required Future<List<Map<String, dynamic>>> Function() fetch,
    required List<Map<String, dynamic>> Function() current,
    required void Function(List<Map<String, dynamic>>) apply,
  }) async {
    dynamic box;
    dynamic cached;
    var key = cacheKey;

    // 0) abrir Hive de forma defensiva; si falla, seguimos sin cache
    try {
      box = await Hive.openBox('catalogCacheBox');
      final sessionBox = Hive.box('sessionBox');
      final escenario = sessionBox.get('escenario', defaultValue: '0');
      key = '$cacheKey-$escenario';

      // 1) servir cache al instante si existe (nunca pisar datos ya
      // presentes con un cache vacío)
      cached = box.get(key);
      if (cached != null) {
        final cachedData = List<Map<String, dynamic>>.from(
            (cached['data'] as List)
                .map((e) => Map<String, dynamic>.from(e)));
        if (cachedData.isNotEmpty || current().isEmpty) {
          apply(cachedData);
        }
      }
    } catch (e) {
      print(
          '⚠️ [CatalogCache] error accediendo a Hive para $cacheKey (se intenta fetch directo sin cache): $e');
    }

    // 2) refrescar desde server solo si venció el TTL o no había cache
    final ts = cached is Map ? cached['ts'] as int? : null;
    final expired = ts == null ||
        DateTime.now().millisecondsSinceEpoch - ts > _catalogTtlHours * 3600000;
    if (expired) {
      try {
        final fresh = await fetch();
        // No pisar datos ya presentes (cache o notifier) con un fetch vacío;
        // [] solo es un estado válido si no había nada previo.
        if (fresh.isNotEmpty || current().isEmpty) {
          apply(fresh);
          if (box != null) {
            try {
              await box.put(key, {
                'data': fresh,
                'ts': DateTime.now().millisecondsSinceEpoch,
              });
            } catch (e) {
              print(
                  '⚠️ [CatalogCache] no se pudo persistir $key en cache (se sigue sirviendo el dato en memoria): $e');
            }
          }
        } else {
          print(
              '⚠️ [CatalogCache] fetch $key devolvió vacío con datos previos existentes, se conserva el dato actual');
        }
      } catch (e) {
        print('⚠️ [CatalogCache] refresh $key falló (sirviendo cache): $e');
      }
    }
  }

  /// Carga los catálogos SubEstados/SubEstadoMoviles/SubEstadoFinalizacionPedidos
  /// (reemplaza los 3 listeners persistentes por get() + cache Hive TTL 24h).
  /// Nunca lanza: nunca debe impedir que `initialize()` (y por lo tanto el
  /// login) termine.
  Future<void> _loadSubEstadosCatalogos() async {
    try {
      await _loadCatalog(
        cacheKey: 'subEstadoMoviles',
        fetch: _firebaseService.getSubEstadoMovilesOnce,
        current: () => _subEstadoMovilesNotifier.value,
        apply: (list) {
          // Mismo origen de datos para ambos notifiers (elimina la doble lectura)
          _subEstadosNotifier.value = list;
          _subEstadoMovilesNotifier.value = list;
        },
      );
    } catch (e) {
      print('❌ [PersistentStreamManager] Error cargando catálogo subEstadoMoviles: $e');
    }

    try {
      await _loadCatalog(
        cacheKey: 'subEstadoFinalizacionPedidos',
        fetch: _firebaseService.getSubEstadoFinalizacionPedidosOnce,
        current: () => _subEstadoFinalizacionPedidosNotifier.value,
        apply: (list) => _subEstadoFinalizacionPedidosNotifier.value = list,
      );
    } catch (e) {
      print('❌ [PersistentStreamManager] Error cargando catálogo subEstadoFinalizacionPedidos: $e');
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
    // SubEstados/SubEstadoMoviles/SubEstadoFinalizacionPedidos ya no son
    // streams persistentes (get() + cache Hive), no aportan a este check.
    return _initialized &&
        _pedidosSubscription != null &&
        _mensajesSubscription != null &&
        _movilSubscription != null &&
        _sesionesSubscription != null;
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

  // ═══════════════════════════════════════════════════════════════════
  // 🛡️ SISTEMA DE VALIDACIÓN ROBUSTA DE SESIÓN
  // ═══════════════════════════════════════════════════════════════════

  /// Handler principal que valida cada snapshot de sesión
  void _handleSessionValidation(Map<String, dynamic>? sesiones) {
    print('🛡️ [SessionValidator] Iniciando validación de sesión...');
    print(
        '🛡️ [SessionValidator] Datos recibidos: ${sesiones != null ? "DATOS PRESENTES" : "NULL"}');

    // 🔒 PROTECCIÓN 1: Si ya estamos en proceso de logout, ignorar
    if (_isLoggingOut) {
      print(
          '🛡️ [SessionValidator] ⏸️ Logout en progreso - ignorando validación');
      return;
    }

    // 🔒 PROTECCIÓN 2: Si recibimos datos válidos, resetear contadores
    if (sesiones != null && sesiones.isNotEmpty) {
      print('🛡️ [SessionValidator] ✅ Sesión VÁLIDA detectada');
      _lastValidSessionTimestamp = DateTime.now();
      _consecutiveNullDetections = 0;
      _lastNullSessionTimestamp = null;
      return;
    }

    // 🚨 Sesión nula o vacía detectada
    print('🛡️ [SessionValidator] ⚠️ Sesión NULA/VACÍA detectada');
    _consecutiveNullDetections++;
    _lastNullSessionTimestamp = DateTime.now();

    print(
        '🛡️ [SessionValidator] Detecciones nulas consecutivas: $_consecutiveNullDetections/$_maxConsecutiveNulls');

    // 🔒 PROTECCIÓN 3: Periodo de gracia - dar tiempo para que se estabilice
    if (_lastValidSessionTimestamp != null) {
      final secondsSinceLastValid =
          DateTime.now().difference(_lastValidSessionTimestamp!).inSeconds;
      print(
          '🛡️ [SessionValidator] Tiempo desde última sesión válida: ${secondsSinceLastValid}s / ${_gracePeriodSeconds}s');

      if (secondsSinceLastValid < _gracePeriodSeconds) {
        print(
            '🛡️ [SessionValidator] ⏸️ Dentro del periodo de gracia - esperando...');
        return;
      }
    }

    // 🔒 PROTECCIÓN 4: Requerir múltiples detecciones consecutivas
    if (_consecutiveNullDetections < _maxConsecutiveNulls) {
      print(
          '🛡️ [SessionValidator] ⏸️ Esperando más detecciones consecutivas...');
      return;
    }

    // 🚨 CONFIRMACIÓN TRIPLE: Antes de actuar, verificar directamente en Firestore
    print(
        '🛡️ [SessionValidator] 🔍 Iniciando VERIFICACIÓN TRIPLE en Firestore...');
    _verifySessionExistsInFirestore();
  }

  /// Verificación directa en Firestore (bypass de cache)
  Future<void> _verifySessionExistsInFirestore() async {
    try {
      print('🔍 [SessionValidator] ══════════════════════════════════════');
      print('🔍 [SessionValidator] INICIANDO VERIFICACIÓN TRIPLE');
      print('🔍 [SessionValidator] ══════════════════════════════════════');

      final sessionBox = Hive.box('sessionBox');
      final usuario = sessionBox.get('username');
      final escenario = sessionBox.get('escenario');

      if (usuario == null || escenario == null) {
        print(
            '🔍 [SessionValidator] ⚠️ No hay datos de sesión en Hive - sesión ya cerrada');
        return;
      }

      // Construir path del documento
      final fecha = DateTime.now();
      final fechaStr =
          '${fecha.year}${fecha.month.toString().padLeft(2, '0')}${fecha.day.toString().padLeft(2, '0')}';
      final docId = 'Usuario-$usuario';
      final docPath = 'sessions-$escenario/$fechaStr/activeSessions/$docId';

      print('🔍 [SessionValidator] Verificando documento:');
      print('🔍 [SessionValidator]   - Path: $docPath');
      print('🔍 [SessionValidator]   - Usuario: $usuario');
      print('🔍 [SessionValidator]   - Escenario: $escenario');

      // 🔥 VERIFICACIÓN CON FIRESTORE DIRECTO (sin cache)
      final docSnapshot = await FirebaseFirestore.instance
          .doc(docPath)
          .get(const GetOptions(source: Source.server));

      print('🔍 [SessionValidator] ──────────────────────────────────────');
      print('🔍 [SessionValidator] RESULTADO DE VERIFICACIÓN DIRECTA:');
      print('🔍 [SessionValidator]   - Existe: ${docSnapshot.exists}');
      print(
          '🔍 [SessionValidator]   - Metadata.isFromCache: ${docSnapshot.metadata.isFromCache}');
      print(
          '🔍 [SessionValidator]   - Metadata.hasPendingWrites: ${docSnapshot.metadata.hasPendingWrites}');

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        print('🔍 [SessionValidator]   - Data presente: ${data != null}');
        if (data != null) {
          print('🔍 [SessionValidator]   - idSesion: ${data['idSesion']}');
          print('🔍 [SessionValidator]   - Keys: ${data.keys.toList()}');
        }
      }
      print('🔍 [SessionValidator] ──────────────────────────────────────');

      // 🎯 DECISIÓN FINAL
      if (docSnapshot.exists) {
        print(
            '🔍 [SessionValidator] ✅ SESIÓN CONFIRMADA - documento existe en servidor');
        print(
            '🔍 [SessionValidator] 🔄 Falsa alarma detectada - resetando contadores');

        // Resetear contadores - fue falsa alarma
        _consecutiveNullDetections = 0;
        _lastNullSessionTimestamp = null;
        _lastValidSessionTimestamp = DateTime.now();

        print('🔍 [SessionValidator] ══════════════════════════════════════');
        print('🔍 [SessionValidator] VERIFICACIÓN COMPLETADA - SESIÓN VÁLIDA');
        print('🔍 [SessionValidator] ══════════════════════════════════════');
      } else {
        print('🔍 [SessionValidator] 🚨 SESIÓN INVÁLIDA CONFIRMADA');
        print('🔍 [SessionValidator] 🚨 Documento NO existe en servidor');
        print('🔍 [SessionValidator] 🚨 Procediendo con logout forzado...');
        print('🔍 [SessionValidator] ══════════════════════════════════════');

        // 🚨 SESIÓN REALMENTE INVÁLIDA - ejecutar logout
        await _executeForceLogout('Sesión cerrada en otro dispositivo');
      }
    } catch (e, stackTrace) {
      print('❌ [SessionValidator] Error verificando sesión en Firestore: $e');
      print('❌ [SessionValidator] StackTrace: $stackTrace');

      // 🛡️ En caso de error de red, asumir sesión válida (conservador)
      print(
          '🛡️ [SessionValidator] Asumiendo sesión VÁLIDA por error de red (conservador)');
      _consecutiveNullDetections = 0;
    }
  }

  /// Ejecuta logout forzado limpio
  Future<void> _executeForceLogout(String reason) async {
    // 🔒 Evitar ejecuciones múltiples
    if (_isLoggingOut) {
      print('🚨 [SessionValidator] Logout ya en progreso - ignorando');
      return;
    }

    _isLoggingOut = true;
    print('🚨 [SessionValidator] ══════════════════════════════════════');
    print('🚨 [SessionValidator] EJECUTANDO LOGOUT FORZADO');
    print('🚨 [SessionValidator] Razón: $reason');
    print('🚨 [SessionValidator] ══════════════════════════════════════');

    try {
      // 1. Detener todos los listeners de Firestore
      print('🚨 [SessionValidator] 1/4 - Deteniendo listeners...');
      dispose();

      // 2. Llamar al LogoutService centralizado
      print('🚨 [SessionValidator] 2/4 - Ejecutando LogoutService...');
      await LogoutService.executeLogout(isRemoteLogout: true);

      // 3. Mostrar dialog explicativo al usuario
      print('🚨 [SessionValidator] 3/4 - Mostrando dialog...');
      await NavigationService.showSessionInvalidDialog(
        title: 'Sesión Finalizada',
        message: reason,
      );

      // 4. Navegar al login
      print('🚨 [SessionValidator] 4/4 - Navegando al login...');
      await NavigationService.navigateToLogin(reason: reason);

      print('🚨 [SessionValidator] ══════════════════════════════════════');
      print('🚨 [SessionValidator] LOGOUT FORZADO COMPLETADO');
      print('🚨 [SessionValidator] ══════════════════════════════════════');
    } catch (e, stackTrace) {
      print('❌ [SessionValidator] Error ejecutando logout forzado: $e');
      print('❌ [SessionValidator] StackTrace: $stackTrace');

      // Intentar navegar al login de todas formas
      await NavigationService.navigateToLogin(reason: 'Error: $e');
    } finally {
      _isLoggingOut = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // FIN DEL SISTEMA DE VALIDACIÓN ROBUSTA
  // ═══════════════════════════════════════════════════════════════════

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
    _promocionesSubscription?.cancel();
    _movilSubscription?.cancel();
    _sesionesSubscription?.cancel();
    // SubEstados/SubEstadoMoviles/SubEstadoFinalizacionPedidos ya no tienen
    // subscription que cancelar (get() + cache Hive, ver _loadCatalog).

    // ❌ NO hacer esto:
    // _pedidosNotifier.dispose();  👈❌
    // _mensajesNotifier.dispose(); 👈❌
    // etc.

    _initialized = false;
    _hiveSyncInitialized = false;

    print('✅ [PersistentStreamManager] All listeners disposed (soft)');
  }
}
