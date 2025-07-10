import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';
import 'package:hive/hive.dart';

/// Singleton class to manage shared Firestore streams
/// This prevents duplicate stream subscriptions across multiple widgets
class StreamManager {
  static final StreamManager _instance = StreamManager._internal();
  factory StreamManager() => _instance;
  StreamManager._internal();

  final FirebaseService _firebaseService = FirebaseService();

  // Broadcast stream controllers for each type of data
  StreamController<List<DocumentSnapshot>>? _pedidosStreamController;
  StreamController<List<DocumentSnapshot>>? _mensajesStreamController;
  StreamController<DocumentSnapshot?>? _movilStreamController;
  StreamController<Map<String, dynamic>?>? _sesionesStreamController;
  StreamController<List<Map<String, dynamic>>>? _subEstadosStreamController;
  StreamController<List<Map<String, dynamic>>>?
      _subEstadoMovilesStreamController;
  StreamController<List<Map<String, dynamic>>>?
      _subEstadoServicesStreamController;

  // Subscription tracking
  StreamSubscription? _pedidosSubscription;
  StreamSubscription? _mensajesSubscription;
  StreamSubscription? _movilSubscription;
  StreamSubscription? _sesionesSubscription;
  StreamSubscription? _subEstadosSubscription;
  StreamSubscription? _subEstadoMovilesSubscription;
  StreamSubscription? _subEstadoServicesSubscription;

  // Listener counters for debugging
  int _pedidosListeners = 0;
  int _mensajesListeners = 0;
  int _movilListeners = 0;
  int _sesionesListeners = 0;
  int _subEstadosListeners = 0;
  int _subEstadoMovilesListeners = 0;
  int _subEstadoServicesListeners = 0;

  // Read counters for each stream type
  int _pedidosReads = 0;
  int _mensajesReads = 0;
  int _movilReads = 0;
  int _sesionesReads = 0;
  int _subEstadosReads = 0;
  int _subEstadoMovilesReads = 0;
  int _subEstadoServicesReads = 0;

  // 🔧 Global counters for total reads across all streams
  int _totalGlobalReads = 0;
  int _totalGlobalListeners = 0;

  // 🔧 Cache latest values to handle late subscribers to broadcast streams
  List<DocumentSnapshot>? _lastMensajesData;
  List<DocumentSnapshot>? _lastPedidosData;
  DocumentSnapshot? _lastMovilData;

  /// Get shared broadcast stream for Pedidos with immediate cache emission
  Stream<List<DocumentSnapshot>> getPedidosStream() {
    print('🔍 StreamManager: getPedidosStream() called');

    // Initialize the underlying stream if it doesn't exist
    if (_pedidosStreamController == null ||
        _pedidosStreamController!.isClosed) {
      print('🔄 StreamManager: Creating new Pedidos broadcast stream');
      _pedidosStreamController =
          StreamController<List<DocumentSnapshot>>.broadcast(
        onListen: _onPedidosListen,
        onCancel: _onPedidosCancel,
      );

      print('🔗 StreamManager: Subscribing to Firebase Pedidos stream');
      // Subscribe to the original stream only once
      _pedidosSubscription = _firebaseService.getPedidosStream().listen(
        (data) {
          print('📨 StreamManager: Received data from Firebase');
          if (!_pedidosStreamController!.isClosed) {
            _pedidosReads++;
            _totalGlobalReads++; // 🔧 Increment global counter
            _lastPedidosData = data; // 🔧 Cache the latest data
            _printLiveStats('Pedidos', _pedidosReads); // 🔧 Print live stats
            print(
                '📖 StreamManager: Pedidos read #$_pedidosReads (Global: $_totalGlobalReads)');
            print('   📦 Documents received: ${data.length}');
            print('   🕐 Timestamp: ${DateTime.now().toIso8601String()}');
            print('   💾 Data cached for late subscribers');
            if (data.isNotEmpty) {
              print('   📋 Sample data: ${data.first.id}');
              print('   📋 Sample doc data: ${data.first.data()}');
            }
            print('🔄 StreamManager: Adding data to broadcast stream');
            _pedidosStreamController!.add(data);
          } else {
            print(
                '⚠️ StreamManager: Stream controller is closed, cannot add data');
          }
        },
        onError: (error) {
          print('❌ StreamManager: Error in Pedidos stream: $error');
          if (!_pedidosStreamController!.isClosed) {
            _pedidosStreamController!.addError(error);
          }
        },
      );
      print('✅ StreamManager: Created new Pedidos broadcast stream');
    } else {
      print('♻️ StreamManager: Reusing existing Pedidos stream');
    }

    // 🔧 Create a stream that immediately emits cached data to new listeners
    return Stream.multi((controller) {
      print('📨 StreamManager: New listener for Pedidos stream');
      _totalGlobalListeners++; // 🔧 Increment global listener counter
      _printListenerStats('Pedidos', 'ADDED'); // 🔧 Print listener stats

      // Immediately emit cached data if available
      if (_lastPedidosData != null) {
        print(
            '💾 StreamManager: Immediately sending cached pedidos data to new listener');
        print('   📦 Cached orders count: ${_lastPedidosData!.length}');
        controller.add(_lastPedidosData!);
      } else {
        print(
            '📭 StreamManager: No cached pedidos data available for immediate emission');
      }

      // Then listen to future data from the broadcast stream
      StreamSubscription<List<DocumentSnapshot>> subscription =
          _pedidosStreamController!.stream.listen(
        (data) {
          print('🔄 StreamManager: Forwarding live pedidos data to listener');
          controller.add(data);
        },
        onError: (error) {
          print(
              '❌ StreamManager: Forwarding pedidos error to listener: $error');
          controller.addError(error);
        },
        onDone: () {
          print('✅ StreamManager: Pedidos stream completed, closing listener');
          controller.close();
        },
      );

      // Clean up when this specific listener is cancelled
      controller.onCancel = () {
        print('🔇 StreamManager: Pedidos listener cancelled, cleaning up');
        _totalGlobalListeners--; // 🔧 Decrement global listener counter
        _printListenerStats('Pedidos', 'REMOVED'); // 🔧 Print listener stats
        subscription.cancel();
      };
    });
  }

  /// Get shared broadcast stream for Mensajes with immediate cache emission
  Stream<List<DocumentSnapshot>> getMensajesStream() {
    print('🔄 StreamManager: getMensajesStream() called');

    // Initialize the underlying stream if it doesn't exist
    if (_mensajesStreamController == null ||
        _mensajesStreamController!.isClosed) {
      print('🔄 StreamManager: Creating new Mensajes broadcast stream');

      _mensajesStreamController =
          StreamController<List<DocumentSnapshot>>.broadcast(
        onListen: _onMensajesListen,
        onCancel: _onMensajesCancel,
      );

      // Subscribe to the original stream only once
      print('🔄 StreamManager: Subscribing to Firebase Mensajes stream');
      _mensajesSubscription = _firebaseService.getMensajesStream().listen(
        (data) {
          if (!_mensajesStreamController!.isClosed) {
            _mensajesReads++;
            _totalGlobalReads++; // 🔧 Increment global counter
            _lastMensajesData = data; // 🔧 Cache the latest data
            _printLiveStats('Mensajes', _mensajesReads); // 🔧 Print live stats
            print(
                '📖 StreamManager: Mensajes read #$_mensajesReads (Global: $_totalGlobalReads)');
            print('   📧 Messages received: ${data.length}');
            print('   🕐 Timestamp: ${DateTime.now().toIso8601String()}');
            print('   💾 Data cached for late subscribers');
            if (data.isNotEmpty) {
              print('   📋 Sample message: ${data.first.id}');
            }
            print('🔄 StreamManager: Adding data to broadcast stream');
            _mensajesStreamController!.add(data);
          }
        },
        onError: (error) {
          print('❌ StreamManager: Mensajes stream error: $error');
          if (!_mensajesStreamController!.isClosed) {
            _mensajesStreamController!.addError(error);
          }
        },
      );
      print('🔄 StreamManager: Created new Mensajes broadcast stream');
    } else {
      print('♻️ StreamManager: Reusing existing Mensajes stream');
    }

    // 🔧 Create a stream that immediately emits cached data to new listeners
    return Stream.multi((controller) {
      print('📨 StreamManager: New listener for Mensajes stream');
      _totalGlobalListeners++; // 🔧 Increment global listener counter
      _printListenerStats('Mensajes', 'ADDED'); // 🔧 Print listener stats

      // Immediately emit cached data if available
      if (_lastMensajesData != null) {
        print(
            '💾 StreamManager: Immediately sending cached mensajes data to new listener');
        print('   📧 Cached messages count: ${_lastMensajesData!.length}');
        controller.add(_lastMensajesData!);
      } else {
        print(
            '📭 StreamManager: No cached mensajes data available for immediate emission');
      }

      // Then listen to future data from the broadcast stream
      StreamSubscription? subscription =
          _mensajesStreamController!.stream.listen(
        (data) {
          print('🔄 StreamManager: Forwarding live data to listener');
          controller.add(data);
        },
        onError: (error) {
          print('❌ StreamManager: Forwarding error to listener: $error');
          controller.addError(error);
        },
        onDone: () {
          print('✅ StreamManager: Stream completed, closing listener');
          controller.close();
        },
      );

      // Clean up when this specific listener is cancelled
      controller.onCancel = () {
        print('🔇 StreamManager: Listener cancelled, cleaning up');
        _totalGlobalListeners--; // 🔧 Decrement global listener counter
        _printListenerStats('Mensajes', 'REMOVED'); // 🔧 Print listener stats
        subscription.cancel();
      };
    });
  }

  /// Get shared broadcast stream for Movil
  Stream<DocumentSnapshot?> getMovilStream() {
    if (_movilStreamController == null || _movilStreamController!.isClosed) {
      _movilStreamController = StreamController<DocumentSnapshot?>.broadcast(
        onListen: _onMovilListen,
        onCancel: _onMovilCancel,
      );

      // Subscribe to the original stream only once
      _movilSubscription = _firebaseService.getMovilStream().listen(
        (data) {
          if (!_movilStreamController!.isClosed) {
            _movilReads++;
            _totalGlobalReads++; // 🔧 Increment global counter
            _lastMovilData = data; // 🔧 Cache the latest data
            _printLiveStats('Movil', _movilReads); // 🔧 Print live stats
            print(
                '📖 StreamManager: Movil read #$_movilReads (Global: $_totalGlobalReads)');
            print('   🚗 Document exists: ${data?.exists == true}');
            print('   🕐 Timestamp: ${DateTime.now().toIso8601String()}');
            print('   💾 Data cached for late subscribers');
            if (data?.exists == true) {
              print('   📋 Movil data: ${data!.data()}');
            }
            _movilStreamController!.add(data);
          }
        },
        onError: (error) {
          if (!_movilStreamController!.isClosed) {
            _movilStreamController!.addError(error);
          }
        },
      );
      print('🔄 StreamManager: Created new Movil broadcast stream');
    }
    return _movilStreamController!.stream;
  }

  /// Get shared broadcast stream for Sesiones
  Stream<Map<String, dynamic>?> getSesionesStream() {
    if (_sesionesStreamController == null ||
        _sesionesStreamController!.isClosed) {
      _sesionesStreamController =
          StreamController<Map<String, dynamic>?>.broadcast(
        onListen: _onSesionesListen,
        onCancel: _onSesionesCancel,
      );

      // Subscribe to the original stream only once
      _sesionesSubscription = _firebaseService.getSesionesStream().listen(
        (data) {
          if (!_sesionesStreamController!.isClosed) {
            _sesionesReads++;
            print('📖 StreamManager: Sesiones read #$_sesionesReads');
            print('   👤 Session data exists: ${data != null}');
            print('   🕐 Timestamp: ${DateTime.now().toIso8601String()}');
            if (data != null) {
              print('   📋 Session keys: ${data.keys.toList()}');
            }
            _sesionesStreamController!.add(data);
          }
        },
        onError: (error) {
          if (!_sesionesStreamController!.isClosed) {
            _sesionesStreamController!.addError(error);
          }
        },
      );
      print('🔄 StreamManager: Created new Sesiones broadcast stream');
    }
    return _sesionesStreamController!.stream;
  }

  /// Get shared broadcast stream for SubEstados
  Stream<List<Map<String, dynamic>>> getSubEstadoFinalizacionPedidosStream() {
    if (_subEstadosStreamController == null ||
        _subEstadosStreamController!.isClosed) {
      _subEstadosStreamController =
          StreamController<List<Map<String, dynamic>>>.broadcast(
        onListen: _onSubEstadosListen,
        onCancel: _onSubEstadosCancel,
      );

      // Subscribe to the original stream only once
      _subEstadosSubscription =
          _firebaseService.getSubEstadoFinalizacionPedidosStream().listen(
        (data) {
          if (!_subEstadosStreamController!.isClosed) {
            _subEstadosReads++;
            print(
                '📖 StreamManager: SubEstados read #$_subEstadosReads (${data.length} items)');
            _subEstadosStreamController!.add(data);
          }
        },
        onError: (error) {
          if (!_subEstadosStreamController!.isClosed) {
            _subEstadosStreamController!.addError(error);
          }
        },
      );
      print('🔄 StreamManager: Created new SubEstados broadcast stream');
    }
    return _subEstadosStreamController!.stream;
  }

  /// Get shared broadcast stream for SubEstadoMoviles
  Stream<List<Map<String, dynamic>>> getSubEstadoMovilesStream() {
    if (_subEstadoMovilesStreamController == null ||
        _subEstadoMovilesStreamController!.isClosed) {
      _subEstadoMovilesStreamController =
          StreamController<List<Map<String, dynamic>>>.broadcast(
        onListen: _onSubEstadoMovilesListen,
        onCancel: _onSubEstadoMovilesCancel,
      );

      // Subscribe to the original stream only once
      _subEstadoMovilesSubscription =
          _firebaseService.getSubEstadoMovilesStream().listen(
        (data) {
          if (!_subEstadoMovilesStreamController!.isClosed) {
            _subEstadoMovilesReads++;
            _totalGlobalReads++; // 🔧 Increment global counter
            _printLiveStats(
                'SubEstMoviles', _subEstadoMovilesReads); // 🔧 Print live stats
            print(
                '📖 StreamManager: SubEstadoMoviles read #$_subEstadoMovilesReads (Global: $_totalGlobalReads) (${data.length} items)');
            _subEstadoMovilesStreamController!.add(data);
          }
        },
        onError: (error) {
          if (!_subEstadoMovilesStreamController!.isClosed) {
            print('❌ StreamManager: SubEstadoMoviles error: $error');
            _subEstadoMovilesStreamController!.addError(error);
          }
        },
      );
      print('🔄 StreamManager: Created new SubEstadoMoviles broadcast stream');
    }
    return _subEstadoMovilesStreamController!.stream;
  }

  /// Get shared broadcast stream for SubEstadoFinalizacionServices
  Stream<List<Map<String, dynamic>>> getSubEstadoFinalizacionServicesStream() {
    if (_subEstadoServicesStreamController == null ||
        _subEstadoServicesStreamController!.isClosed) {
      _subEstadoServicesStreamController =
          StreamController<List<Map<String, dynamic>>>.broadcast(
        onListen: _onSubEstadoServicesListen,
        onCancel: _onSubEstadoServicesCancel,
      );

      // Subscribe to the original stream only once
      _subEstadoServicesSubscription =
          _firebaseService.getSubEstadoFinalizacionServicesStream().listen(
        (data) {
          if (!_subEstadoServicesStreamController!.isClosed) {
            _subEstadoServicesReads++;
            print(
                '📖 StreamManager: SubEstadoServices read #$_subEstadoServicesReads (${data.length} items)');
            _subEstadoServicesStreamController!.add(data);
          }
        },
        onError: (error) {
          if (!_subEstadoServicesStreamController!.isClosed) {
            print('❌ StreamManager: SubEstadoServices error: $error');
            _subEstadoServicesStreamController!.addError(error);
          }
        },
      );
      print('🔄 StreamManager: Created new SubEstadoServices broadcast stream');
    }
    return _subEstadoServicesStreamController!.stream;
  }

  // Listener management for Pedidos
  void _onPedidosListen() {
    _pedidosListeners++;
    print('📊 StreamManager: Pedidos listeners: $_pedidosListeners');
    print('🎧 StreamManager: New listener attached to Pedidos stream');

    // 🔧 Send cached data to new listener immediately if available
    if (_lastPedidosData != null && !_pedidosStreamController!.isClosed) {
      print('💾 StreamManager: Sending cached pedidos data to new listener');
      print('   📦 Cached orders count: ${_lastPedidosData!.length}');
      // Schedule the emission for the next microtask to ensure the listener is properly registered
      Future.microtask(() {
        if (!_pedidosStreamController!.isClosed) {
          _pedidosStreamController!.add(_lastPedidosData!);
          print('✅ StreamManager: Cached data sent to new pedidos listener');
        }
      });
    } else {
      print(
          '📭 StreamManager: No cached pedidos data available for new listener');
    }
  }

  void _onPedidosCancel() {
    _pedidosListeners--;
    print('📊 StreamManager: Pedidos listeners: $_pedidosListeners');
    print('🔇 StreamManager: Listener removed from Pedidos stream');
    if (_pedidosListeners <= 0) {
      print('🧹 StreamManager: No more listeners, scheduling cleanup');
      _cleanupPedidosStream();
    }
  }

  // Listener management for Mensajes
  void _onMensajesListen() {
    _mensajesListeners++;
    print('📊 StreamManager: Mensajes listeners: $_mensajesListeners');
    print('🎧 StreamManager: New listener attached to Mensajes stream');

    // 🔧 Send cached data to new listener immediately if available
    if (_lastMensajesData != null && !_mensajesStreamController!.isClosed) {
      print('💾 StreamManager: Sending cached mensajes data to new listener');
      print('   📧 Cached messages count: ${_lastMensajesData!.length}');
      // Schedule the emission for the next microtask to ensure the listener is properly registered
      Future.microtask(() {
        if (!_mensajesStreamController!.isClosed) {
          _mensajesStreamController!.add(_lastMensajesData!);
          print('✅ StreamManager: Cached data sent to new mensajes listener');
        }
      });
    } else {
      print(
          '📭 StreamManager: No cached mensajes data available for new listener');
    }
  }

  void _onMensajesCancel() {
    _mensajesListeners--;
    print('📊 StreamManager: Mensajes listeners: $_mensajesListeners');
    if (_mensajesListeners <= 0) {
      _cleanupMensajesStream();
    }
  }

  // Listener management for Movil
  void _onMovilListen() {
    _movilListeners++;
    print('📊 StreamManager: Movil listeners: $_movilListeners');
    print('🎧 StreamManager: New listener attached to Movil stream');

    // 🔧 Send cached data to new listener immediately if available
    if (_lastMovilData != null && !_movilStreamController!.isClosed) {
      print('💾 StreamManager: Sending cached movil data to new listener');
      print('   🚗 Cached movil exists: ${_lastMovilData?.exists == true}');
      // Schedule the emission for the next microtask to ensure the listener is properly registered
      Future.microtask(() {
        if (!_movilStreamController!.isClosed) {
          _movilStreamController!.add(_lastMovilData);
          print('✅ StreamManager: Cached data sent to new movil listener');
        }
      });
    } else {
      print(
          '📭 StreamManager: No cached movil data available for new listener');
    }
  }

  void _onMovilCancel() {
    _movilListeners--;
    print('📊 StreamManager: Movil listeners: $_movilListeners');
    if (_movilListeners <= 0) {
      _cleanupMovilStream();
    }
  }

  // Listener management for Sesiones
  void _onSesionesListen() {
    _sesionesListeners++;
    print('📊 StreamManager: Sesiones listeners: $_sesionesListeners');
  }

  void _onSesionesCancel() {
    _sesionesListeners--;
    print('📊 StreamManager: Sesiones listeners: $_sesionesListeners');
    if (_sesionesListeners <= 0) {
      _cleanupSesionesStream();
    }
  }

  // Listener management for SubEstados
  void _onSubEstadosListen() {
    _subEstadosListeners++;
    print('📊 StreamManager: SubEstados listeners: $_subEstadosListeners');
  }

  void _onSubEstadosCancel() {
    _subEstadosListeners--;
    print('📊 StreamManager: SubEstados listeners: $_subEstadosListeners');
    if (_subEstadosListeners <= 0) {
      _cleanupSubEstadosStream();
    }
  }

  // Listener management for SubEstadoMoviles
  void _onSubEstadoMovilesListen() {
    _subEstadoMovilesListeners++;
    print(
        '📊 StreamManager: SubEstadoMoviles listeners: $_subEstadoMovilesListeners');
  }

  void _onSubEstadoMovilesCancel() {
    _subEstadoMovilesListeners--;
    print(
        '📊 StreamManager: SubEstadoMoviles listeners: $_subEstadoMovilesListeners');
    if (_subEstadoMovilesListeners <= 0) {
      _cleanupSubEstadoMovilesStream();
    }
  }

  // Listener management for SubEstadoServices
  void _onSubEstadoServicesListen() {
    _subEstadoServicesListeners++;
    print(
        '📊 StreamManager: SubEstadoServices listeners: $_subEstadoServicesListeners');
  }

  void _onSubEstadoServicesCancel() {
    _subEstadoServicesListeners--;
    print(
        '📊 StreamManager: SubEstadoServices listeners: $_subEstadoServicesListeners');
    if (_subEstadoServicesListeners <= 0) {
      _cleanupSubEstadoServicesStream();
    }
  }

  // Cleanup methods
  void _cleanupPedidosStream() {
    print('🧹 StreamManager: Cleaning up Pedidos stream (no more listeners)');
    print('📊 StreamManager: Pedidos total reads: $_pedidosReads');
    _pedidosSubscription?.cancel();
    _pedidosSubscription = null;
    _pedidosStreamController?.close();
    _pedidosStreamController = null;
    _pedidosReads = 0; // Reset read counter
  }

  void _cleanupMensajesStream() {
    print('🧹 StreamManager: Cleaning up Mensajes stream (no more listeners)');
    print('📊 StreamManager: Mensajes total reads: $_mensajesReads');
    _mensajesSubscription?.cancel();
    _mensajesSubscription = null;
    _mensajesStreamController?.close();
    _mensajesStreamController = null;
    _mensajesReads = 0; // Reset read counter
  }

  void _cleanupMovilStream() {
    print('🧹 StreamManager: Cleaning up Movil stream (no more listeners)');
    print('📊 StreamManager: Movil total reads: $_movilReads');
    _movilSubscription?.cancel();
    _movilSubscription = null;
    _movilStreamController?.close();
    _movilStreamController = null;
    _movilReads = 0; // Reset read counter
  }

  void _cleanupSesionesStream() {
    print('🧹 StreamManager: Cleaning up Sesiones stream (no more listeners)');
    print('📊 StreamManager: Sesiones total reads: $_sesionesReads');
    _sesionesSubscription?.cancel();
    _sesionesSubscription = null;
    _sesionesStreamController?.close();
    _sesionesStreamController = null;
    _sesionesReads = 0; // Reset read counter
  }

  void _cleanupSubEstadosStream() {
    print(
        '🧹 StreamManager: Cleaning up SubEstados stream (no more listeners)');
    print('📊 StreamManager: SubEstados total reads: $_subEstadosReads');
    _subEstadosSubscription?.cancel();
    _subEstadosSubscription = null;
    _subEstadosStreamController?.close();
    _subEstadosStreamController = null;
    _subEstadosReads = 0; // Reset read counter
  }

  void _cleanupSubEstadoMovilesStream() {
    print(
        '🧹 StreamManager: Cleaning up SubEstadoMoviles stream (no more listeners)');
    print(
        '📊 StreamManager: SubEstadoMoviles total reads: $_subEstadoMovilesReads');
    _subEstadoMovilesSubscription?.cancel();
    _subEstadoMovilesSubscription = null;
    _subEstadoMovilesStreamController?.close();
    _subEstadoMovilesStreamController = null;
    _subEstadoMovilesReads = 0; // Reset read counter
  }

  void _cleanupSubEstadoServicesStream() {
    print(
        '🧹 StreamManager: Cleaning up SubEstadoServices stream (no more listeners)');
    print(
        '📊 StreamManager: SubEstadoServices total reads: $_subEstadoServicesReads');
    _subEstadoServicesSubscription?.cancel();
    _subEstadoServicesSubscription = null;
    _subEstadoServicesStreamController?.close();
    _subEstadoServicesStreamController = null;
    _subEstadoServicesReads = 0; // Reset read counter
  }

  /// Cleanup all streams - call this when app is disposed
  void dispose() {
    print('🧹 StreamManager: Disposing all streams');
    _cleanupPedidosStream();
    _cleanupMensajesStream();
    _cleanupMovilStream();
    _cleanupSesionesStream();
    _cleanupSubEstadosStream();
    _cleanupSubEstadoMovilesStream();
    _cleanupSubEstadoServicesStream();
  }

  /// Get debug information about active streams and listeners
  Map<String, dynamic> getDebugInfo() {
    return {
      'listeners': {
        'pedidos': _pedidosListeners,
        'mensajes': _mensajesListeners,
        'movil': _movilListeners,
        'sesiones': _sesionesListeners,
        'subEstados': _subEstadosListeners,
        'subEstadoMoviles': _subEstadoMovilesListeners,
        'subEstadoServices': _subEstadoServicesListeners,
      },
      'reads': {
        'pedidos': _pedidosReads,
        'mensajes': _mensajesReads,
        'movil': _movilReads,
        'sesiones': _sesionesReads,
        'subEstados': _subEstadosReads,
        'subEstadoMoviles': _subEstadoMovilesReads,
        'subEstadoServices': _subEstadoServicesReads,
      },
      'activeStreams': {
        'pedidos': _pedidosStreamController != null &&
            !_pedidosStreamController!.isClosed,
        'mensajes': _mensajesStreamController != null &&
            !_mensajesStreamController!.isClosed,
        'movil':
            _movilStreamController != null && !_movilStreamController!.isClosed,
        'sesiones': _sesionesStreamController != null &&
            !_sesionesStreamController!.isClosed,
        'subEstados': _subEstadosStreamController != null &&
            !_subEstadosStreamController!.isClosed,
        'subEstadoMoviles': _subEstadoMovilesStreamController != null &&
            !_subEstadoMovilesStreamController!.isClosed,
        'subEstadoServices': _subEstadoServicesStreamController != null &&
            !_subEstadoServicesStreamController!.isClosed,
      },
    };
  }

  /// Get a summary of all read counters
  Map<String, int> getReadCounters() {
    return {
      'pedidos': _pedidosReads,
      'mensajes': _mensajesReads,
      'movil': _movilReads,
      'sesiones': _sesionesReads,
      'subEstados': _subEstadosReads,
      'subEstadoMoviles': _subEstadoMovilesReads,
      'subEstadoServices': _subEstadoServicesReads,
    };
  }

  /// Get global read counter across all streams
  int get totalGlobalReads => _totalGlobalReads;

  /// Get global listener counter across all streams
  int get totalGlobalListeners => _totalGlobalListeners;

  /// Get individual stream read counters
  Map<String, int> get streamReadCounters => {
        'Pedidos': _pedidosReads,
        'Mensajes': _mensajesReads,
        'Movil': _movilReads,
        'Sesiones': _sesionesReads,
        'SubEstados': _subEstadosReads,
        'SubEstadoMoviles': _subEstadoMovilesReads,
        'SubEstadoServices': _subEstadoServicesReads,
      };

  /// Get individual stream listener counters
  Map<String, int> get streamListenerCounters => {
        'Pedidos': _pedidosListeners,
        'Mensajes': _mensajesListeners,
        'Movil': _movilListeners,
        'Sesiones': _sesionesListeners,
        'SubEstados': _subEstadosListeners,
        'SubEstadoMoviles': _subEstadoMovilesListeners,
        'SubEstadoServices': _subEstadoServicesListeners,
      };

  /// Reset all global counters (useful for testing/debugging)
  void resetGlobalCounters() {
    print('🔄 StreamManager: Resetting global counters');
    _totalGlobalReads = 0;
    _totalGlobalListeners = 0;
  }

  /// Print a summary of all read activity
  void printReadSummary() {
    print('📊 StreamManager Read Summary:');
    print('  📖 Pedidos: $_pedidosReads reads');
    print('  📖 Mensajes: $_mensajesReads reads');
    print('  📖 Movil: $_movilReads reads');
    print('  📖 Sesiones: $_sesionesReads reads');
    print('  📖 SubEstados: $_subEstadosReads reads');
    print('  📖 SubEstadoMoviles: $_subEstadoMovilesReads reads');
    print('  📖 SubEstadoServices: $_subEstadoServicesReads reads');
    int totalReads = _pedidosReads +
        _mensajesReads +
        _movilReads +
        _sesionesReads +
        _subEstadosReads +
        _subEstadoMovilesReads +
        _subEstadoServicesReads;
    print('  📖 Total: $totalReads reads');
  }

  /// Reset all read counters (useful for testing/debugging)
  void resetReadCounters() {
    print('🔄 StreamManager: Resetting all read counters');
    _pedidosReads = 0;
    _mensajesReads = 0;
    _movilReads = 0;
    _sesionesReads = 0;
    _subEstadosReads = 0;
    _subEstadoMovilesReads = 0;
    _subEstadoServicesReads = 0;
  }

  /// Print comprehensive stream status and statistics
  void printStreamDiagnostics() {
    print('🔍 StreamManager Comprehensive Diagnostics:');
    print('=' * 50);

    // Active streams summary
    print('📊 ACTIVE STREAMS SUMMARY:');
    int activeStreams = 0;
    int totalListeners = 0;
    int totalReads = 0;

    if (_pedidosStreamController != null &&
        !_pedidosStreamController!.isClosed) {
      activeStreams++;
      totalListeners += _pedidosListeners;
      totalReads += _pedidosReads;
      print(
          '  🔄 Pedidos: ACTIVE (${_pedidosListeners} listeners, $_pedidosReads reads)');
    } else {
      print('  ⭕ Pedidos: INACTIVE');
    }

    if (_mensajesStreamController != null &&
        !_mensajesStreamController!.isClosed) {
      activeStreams++;
      totalListeners += _mensajesListeners;
      totalReads += _mensajesReads;
      print(
          '  🔄 Mensajes: ACTIVE (${_mensajesListeners} listeners, $_mensajesReads reads)');
    } else {
      print('  ⭕ Mensajes: INACTIVE');
    }

    if (_movilStreamController != null && !_movilStreamController!.isClosed) {
      activeStreams++;
      totalListeners += _movilListeners;
      totalReads += _movilReads;
      print(
          '  🔄 Movil: ACTIVE (${_movilListeners} listeners, $_movilReads reads)');
    } else {
      print('  ⭕ Movil: INACTIVE');
    }

    if (_sesionesStreamController != null &&
        !_sesionesStreamController!.isClosed) {
      activeStreams++;
      totalListeners += _sesionesListeners;
      totalReads += _sesionesReads;
      print(
          '  🔄 Sesiones: ACTIVE (${_sesionesListeners} listeners, $_sesionesReads reads)');
    } else {
      print('  ⭕ Sesiones: INACTIVE');
    }

    if (_subEstadosStreamController != null &&
        !_subEstadosStreamController!.isClosed) {
      activeStreams++;
      totalListeners += _subEstadosListeners;
      totalReads += _subEstadosReads;
      print(
          '  🔄 SubEstados: ACTIVE (${_subEstadosListeners} listeners, $_subEstadosReads reads)');
    } else {
      print('  ⭕ SubEstados: INACTIVE');
    }

    if (_subEstadoMovilesStreamController != null &&
        !_subEstadoMovilesStreamController!.isClosed) {
      activeStreams++;
      totalListeners += _subEstadoMovilesListeners;
      totalReads += _subEstadoMovilesReads;
      print(
          '  🔄 SubEstadoMoviles: ACTIVE (${_subEstadoMovilesListeners} listeners, $_subEstadoMovilesReads reads)');
    } else {
      print('  ⭕ SubEstadoMoviles: INACTIVE');
    }

    if (_subEstadoServicesStreamController != null &&
        !_subEstadoServicesStreamController!.isClosed) {
      activeStreams++;
      totalListeners += _subEstadoServicesListeners;
      totalReads += _subEstadoServicesReads;
      print(
          '  🔄 SubEstadoServices: ACTIVE (${_subEstadoServicesListeners} listeners, $_subEstadoServicesReads reads)');
    } else {
      print('  ⭕ SubEstadoServices: INACTIVE');
    }

    print('=' * 50);
    print('📈 TOTALS:');
    print('  🔄 Active Streams: $activeStreams');
    print('  👂 Total Listeners: $totalListeners');
    print('  📖 Total Reads: $totalReads');
    print('  🌐 Global Listeners: $_totalGlobalListeners');
    print('  🌐 Global Reads: $_totalGlobalReads');
    print('  🕐 Current Time: ${DateTime.now().toIso8601String()}');
    print('=' * 50);

    // Performance insights
    if (totalReads > 0) {
      double averageReadsPerStream =
          totalReads / (activeStreams > 0 ? activeStreams : 1);
      print('📊 PERFORMANCE INSIGHTS:');
      print(
          '  📊 Average reads per stream: ${averageReadsPerStream.toStringAsFixed(2)}');

      if (totalReads > 100) {
        print('  ⚠️  High read count detected - consider optimization');
      } else if (totalReads > 50) {
        print('  🔶 Moderate read count - monitor closely');
      } else {
        print('  ✅ Read count looks healthy');
      }
    }
    print('=' * 50);
  }

  /// Static convenience method to quickly debug streams from anywhere
  static void debug() {
    final instance = StreamManager();
    instance.printStreamDiagnostics();
  }

  /// Static convenience method to quickly check read counters from anywhere
  static void checkReads() {
    final instance = StreamManager();
    instance.printReadSummary();
  }

  /// Static convenience method to reset all counters from anywhere (for testing)
  static void resetCounters() {
    final instance = StreamManager();
    instance.resetReadCounters();
  }

  /// Debug method to check if Pedidos stream prerequisites are met
  static Future<void> debugPedidosPrerequisites() async {
    print('🔍 StreamManager: Debugging Pedidos prerequisites...');

    try {
      // Check Hive box
      if (!Hive.isBoxOpen('sessionBox')) {
        print('❌ SessionBox is not open');
        return;
      }

      var box = Hive.box('sessionBox');
      String escenarioId = box.get('escenario', defaultValue: '0').toString();
      String usuario = box.get('username', defaultValue: '0').toString();
      int movil = int.tryParse(box.get('movil', defaultValue: '0')) ?? 0;

      print('📋 Session data:');
      print('   🆔 Escenario ID: $escenarioId');
      print('   👤 Usuario: $usuario');
      print('   🚗 Movil: $movil');

      // Check collection name
      String collectionName = 'Pedidos-$escenarioId';
      print('   📚 Collection: $collectionName');

      // Check date
      String fechaActualStr = DateTime.now()
          .toUtc()
          .subtract(Duration(hours: 3))
          .toIso8601String()
          .split('T')[0]
          .replaceAll('-', '');
      int fechaActual = int.tryParse(fechaActualStr) ?? 0;
      print('   📅 Fecha actual: $fechaActual');

      // Validate critical parameters
      if (escenarioId == '0' || escenarioId.isEmpty) {
        print('⚠️ WARNING: Escenario ID is invalid: $escenarioId');
      }
      if (movil == 0) {
        print('⚠️ WARNING: Movil ID is invalid: $movil');
      }
      if (fechaActual == 0) {
        print('⚠️ WARNING: Fecha actual is invalid: $fechaActual');
      }

      print('✅ Prerequisites check completed');
    } catch (e) {
      print('❌ Error checking prerequisites: $e');
    }
  }

  /// Print live statistics each time a read occurs
  void _printLiveStats(String streamName, int streamReads) {
    String timestamp =
        DateTime.now().toIso8601String().substring(11, 19); // HH:MM:SS
    print(
        '📊 ${timestamp} | Stream: ${streamName.padRight(12)} | Reads: ${streamReads.toString().padLeft(2)} | Global Total: $_totalGlobalReads');

    // Print summary every 5 reads
    if (_totalGlobalReads % 5 == 0) {
      print('📈 ═══ GLOBAL SUMMARY ═══');
      print('   🌐 Total Global Reads: $_totalGlobalReads');
      print('   👂 Total Global Listeners: $_totalGlobalListeners');
      print(
          '   📊 Breakdown: Pedidos: $_pedidosReads | Mensajes: $_mensajesReads | Movil: $_movilReads | SubEstadoMoviles: $_subEstadoMovilesReads');
      print('📈 ═══════════════════════');
    }
  }

  /// Print live listener statistics
  void _printListenerStats(String streamName, String action) {
    String timestamp =
        DateTime.now().toIso8601String().substring(11, 19); // HH:MM:SS
    print(
        '👂 ${timestamp} | ${action.padRight(10)} | Stream: ${streamName.padRight(12)} | Global Listeners: $_totalGlobalListeners');
  }
}
