import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart'; // Para MethodChannel
import 'package:hive/hive.dart';
import 'dart:convert'; // Para calcular el tamaño de los datos
import 'dart:async'; // Para Timer
import '../utils/error_event.dart';
import '../utils/config.dart'; // Importa el archivo de configuración
import '../utils/constantes.dart'; // Importa la función getConstantValue
import 'riogas_service.dart'; // Para registrarCierre
import 'persistent_stream_manager.dart'; // Para cancelar streams

// Función utilitaria para abrir cajas Hive de forma segura
dynamic openBoxSafe(String boxName) async {
  try {
    if (!Hive.isBoxOpen(boxName)) {
      // Si tu versión de Hive soporta boxExists, puedes agregar aquí la verificación
      // if (!await Hive.boxExists(boxName)) {
      //   print('⚠️ La caja $boxName no existe en disco.');
      //   return null;
      // }
      return await Hive.openBox(boxName);
    }
    return Hive.box(boxName);
  } catch (e) {
    print('❌ Error abriendo la caja $boxName: $e');
    return null;
  }
}

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? _user;
  static int streamCount = 0;
  static Map<String, int> streamCounters = {};

  // Control para el listener de auth state
  static bool _authListenerInitialized = false;

  // Timer para refresh proactivo del token
  static Timer? _tokenRefreshTimer;

  Future<void> initializeFirebase() async {
    //WidgetsFlutterBinding.ensureInitialized();

    /*try {
      // Inicializar Firebase
      await Firebase.initializeApp();
      // print('Firebase initialized successfully');
    } catch (e) {
      // print('Error initializing Firebase: $e');
      await _logError('Firebase Initialization Error', e.toString());
    }*/

    // Cargar credenciales guardadas antes de intentar login
    await Config.loadCredentials();

    // Autenticar al usuario
    await signInWithEmailAndPassword();

    // Inicializar listener de auth state (solo una vez)
    _setupAuthStateListener();

    // Iniciar refresh proactivo del token
    startProactiveTokenRefresh();
  }

  /// Configura el listener de cambios en el estado de autenticación
  void _setupAuthStateListener() {
    if (_authListenerInitialized) {
      print('ℹ️ [FIREBASE_SERVICE] Listener de auth ya inicializado');
      return;
    }

    FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (user == null) {
        print('🔴 [FIREBASE_SERVICE] Usuario desautenticado o token expirado');
        print('   Timestamp: ${DateTime.now().toIso8601String()}');

        // Intentar re-autenticar si hay credenciales guardadas
        if (Config.firestoreEmail.isNotEmpty &&
            Config.firestorePassword.isNotEmpty) {
          print(
              '🔄 [FIREBASE_SERVICE] Intentando re-autenticación automática...');
          await signInWithEmailAndPassword();
        } else {
          print('⚠️ [FIREBASE_SERVICE] No hay credenciales para re-autenticar');
        }
      } else {
        print('✅ [FIREBASE_SERVICE] Usuario autenticado: ${user.email}');
        print('   UID: ${user.uid}');
        print('   Timestamp: ${DateTime.now().toIso8601String()}');
        _user = user;
      }
    }, onError: (error) {
      print('❌ [FIREBASE_SERVICE] Error en authStateChanges: $error');
    });

    _authListenerInitialized = true;
    print('✅ [FIREBASE_SERVICE] Listener de auth state inicializado');
  }

  /// Inicia el timer para refresh proactivo del token cada 45 minutos
  /// Esto previene que el token expire (expira a la 1 hora)
  void startProactiveTokenRefresh() {
    // Cancelar timer existente si hay
    _tokenRefreshTimer?.cancel();

    // Crear nuevo timer que se ejecuta cada 45 minutos
    _tokenRefreshTimer =
        Timer.periodic(const Duration(minutes: 45), (timer) async {
      print('⏰ [FIREBASE_SERVICE] Timer de refresh de token ejecutado');
      print('   Timestamp: ${DateTime.now().toIso8601String()}');

      bool refreshed = await refreshAuthToken();

      if (refreshed) {
        print('✅ [FIREBASE_SERVICE] Token refrescado proactivamente');
      } else {
        print('❌ [FIREBASE_SERVICE] Falló el refresh proactivo del token');
      }
    });

    print(
        '✅ [FIREBASE_SERVICE] Timer de refresh proactivo iniciado (cada 45 min)');
  }

  /// Detiene el timer de refresh proactivo
  void stopProactiveTokenRefresh() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    print('🛑 [FIREBASE_SERVICE] Timer de refresh proactivo detenido');
  }

  /// Refresca el token del usuario actual
  /// Llama a este método antes de operaciones críticas o periódicamente
  Future<bool> refreshAuthToken() async {
    try {
      final User? currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        print(
            '⚠️ [FIREBASE_SERVICE] No hay usuario autenticado para refrescar token');

        // Intentar re-autenticar
        if (Config.firestoreEmail.isNotEmpty &&
            Config.firestorePassword.isNotEmpty) {
          print('🔄 [FIREBASE_SERVICE] Intentando re-autenticación...');
          await signInWithEmailAndPassword();
          return FirebaseAuth.instance.currentUser != null;
        }

        return false;
      }

      print(
          '🔄 [FIREBASE_SERVICE] Refrescando token para: ${currentUser.email}');

      // getIdToken(true) fuerza el refresh del token
      String? token = await currentUser.getIdToken(true);

      if (token != null) {
        print('✅ [FIREBASE_SERVICE] Token refrescado exitosamente');
        print('   Timestamp: ${DateTime.now().toIso8601String()}');
        return true;
      } else {
        print('❌ [FIREBASE_SERVICE] No se pudo obtener el token');
        return false;
      }
    } catch (e) {
      print('❌ [FIREBASE_SERVICE] Error refrescando token: $e');
      await _logError('Token Refresh Error', e.toString());
      return false;
    }
  }

  /// Verifica si el usuario está autenticado y el token es válido
  /// Retorna true si está todo OK, false si necesita re-autenticación
  Future<bool> ensureAuthenticated() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      print(
          '⚠️ [FIREBASE_SERVICE] Usuario no autenticado, intentando login...');
      await signInWithEmailAndPassword();
      return FirebaseAuth.instance.currentUser != null;
    }

    // Verificar si el token necesita refresh (opcional, getIdToken lo hace automáticamente)
    try {
      String? token =
          await currentUser.getIdToken(false); // false = usa cache si es válido
      return token != null;
    } catch (e) {
      print('❌ [FIREBASE_SERVICE] Error verificando autenticación: $e');
      // Intentar refresh
      return await refreshAuthToken();
    }
  }

  Future<void> signInWithEmailAndPassword() async {
    try {
      // Verificar que las credenciales no estén vacías
      if (Config.firestoreEmail.isEmpty || Config.firestorePassword.isEmpty) {
        print(
            '⚠️ [FIREBASE_SERVICE] Credenciales vacías, no se puede hacer login');
        print(
            '   Email: "${Config.firestoreEmail}", Password: "${Config.firestorePassword}"');
        await _logError('Firebase Auth Error',
            'Credenciales vacías - Usuario no ha hecho login');
        return;
      }

      print(
          '🔐 [FIREBASE_SERVICE] Intentando login con: ${Config.firestoreEmail}');

      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: Config.firestoreEmail, // Utiliza la variable global
        password: Config.firestorePassword, // Utiliza la variable global
      );
      _user = userCredential.user;
      print('✅ [FIREBASE_SERVICE] Usuario autenticado: ${_user?.email}');
      // print("User signed in: ${_user?.email}");
    } on FirebaseAuthException catch (e) {
      print(
          '❌ [FIREBASE_SERVICE] Error de autenticación: ${e.code} - ${e.message}');
      // print("Error signing in: $e");
      await _logError('Firebase Auth Error', e.toString());
    }
  }

  /*Future<bool> checkFirestoreConnectivity() async {
    try {
      var snapshot = await _firestore
          .collection('test')
          .snapshots()
          .first
          .timeout(const Duration(seconds: 3));

      print('✅ Firestore stream is active.'); // 👈 aquí va el print

      await _updateConnectionErrorState(false);
      return true;
    } catch (e) {
      await _updateConnectionErrorState(true);
      return false;
    }
  }*/

  Future<void> _logFirestorePermissionError(String message) async {
    // print('Firestore permission error: $message');
    await _logError('Firestore Permission Error', message);
  }

  Future<void> _updateConnectionErrorState(bool hasError) async {
    var conexionBox = await openBoxSafe('conexionBox');
    if (conexionBox == null) return;
    DateTime? now = DateTime.now();
    if (now == null) {
      // print('⚠ Error: DateTime.now() returned null.');
      return; // Handle the error or exit the function gracefully
    }

    if (hasError) {
      if (!conexionBox.containsKey('firstErrorTimeFirestore')) {
        conexionBox.put('firstErrorTimeFirestore', now);
      }
      conexionBox.put('conexionFirestore', true); // Ensure false until resolved
      conexionBox.put('conexionFirestore', false);
      DateTime firstErrorTime = conexionBox.get('firstErrorTimeFirestore');
      if (now.difference(firstErrorTime).inMinutes >= 5) {
        // print(
        //   '⚠ Error persistente: No hay conexión con Firestore durante más de 5 minutos.',
        // );
      }
    } else {
      conexionBox.delete('firstErrorTimeFirestore');
      conexionBox.put('conexionFirestore', true);
      conexionBox.put('lastConnectionTimeFirestore', now);
    }
  }

  void monitorStream<T>(Stream<T> stream, String streamName) {
    streamCount++;
    streamCounters[streamName] = (streamCounters[streamName] ?? 0) + 1;
    print(
        '🔁 Nueva instancia del stream $streamName (${streamCounters[streamName]} de este tipo, $streamCount total)');
    stream.listen(
      (event) async {
        print('✅ Stream "$streamName" received data: $event');
        var conexionBox = await openBoxSafe('conexionBox');
        if (conexionBox == null) return;
        DateTime now = DateTime.now();
        conexionBox.put('ConexionFirestore', true);
        conexionBox.put('lastSuccessfulConnection', now.toIso8601String());
      },
      onError: (error) async {
        print('❌ Stream "$streamName" encountered an error: $error');
        var conexionBox = await openBoxSafe('conexionBox');
        if (conexionBox == null) return;
        conexionBox.put('ConexionFirestore', false);
        if (error is FirebaseException && error.code == 'permission-denied') {
          await _logFirestorePermissionError(
              error.message ?? 'Permission denied');
        } else {
          await _logError('Stream Error', error.toString());
        }
      },
      onDone: () async {
        streamCount--;
        streamCounters[streamName] = (streamCounters[streamName] ?? 1) - 1;
        print(
            '⚠ Stream "$streamName" has been closed. (${streamCounters[streamName]} de este tipo, $streamCount total)');
        var conexionBox = await openBoxSafe('conexionBox');
        if (conexionBox == null) return;
        conexionBox.put('ConexionFirestore', false);
      },
      cancelOnError: true,
    );
  }

  void monitorStreamWithReconnect<T>(
      Stream<T> stream, String streamName, Function reconnectCallback) {
    stream.listen(
      (event) async {
        var conexionBox = await openBoxSafe('conexionBox');
        if (conexionBox == null) return;
        DateTime now = DateTime.now();
        conexionBox.put('ConexionFirestore', true);
        conexionBox.put('lastSuccessfulConnection', now.toIso8601String());
      },
      onError: (error) async {
        var conexionBox = await openBoxSafe('conexionBox');
        if (conexionBox == null) return;
        conexionBox.put('ConexionFirestore', false);
        if (error is FirebaseException && error.code == 'permission-denied') {
          await _logFirestorePermissionError(
              error.message ?? 'Permission denied');
        } else {
          await _logError('Stream Error', error.toString());
        }
        reconnectCallback();
      },
      onDone: () async {
        var conexionBox = await openBoxSafe('conexionBox');
        if (conexionBox == null) return;
        conexionBox.put('ConexionFirestore', false);
        reconnectCallback();
      },
      cancelOnError: true,
    );
  }

  void monitorStreamWithUsage<T>(Stream<T> stream, String streamName) {
    streamCount++;
    streamCounters[streamName] = (streamCounters[streamName] ?? 0) + 1;
    print(
        '🔁 Nueva instancia del stream con uso $streamName (${streamCounters[streamName]} de este tipo, $streamCount total)');
    int totalBytes = 0;
    DateTime startTime = DateTime.now();
    stream.listen(
      (event) async {
        try {
          String jsonData = '';

          if (event is List<DocumentSnapshot>) {
            List<Map<String, dynamic>> dataList = event.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return _convertFirestoreData(data);
            }).toList();
            jsonData = jsonEncode(dataList);
          } else if (event is DocumentSnapshot) {
            final data = event.data();
            if (data is Map<String, dynamic>) {
              final cleaned = _convertFirestoreData(data);
              jsonData = jsonEncode(cleaned);
            } else {
              jsonData = jsonEncode({'raw': data});
            }
          } else if (event is Map<String, dynamic>) {
            final cleaned = _convertFirestoreData(event);
            jsonData = jsonEncode(cleaned);
          } else {
            jsonData = jsonEncode(event);
          }

          int dataSize = utf8.encode(jsonData).length;
          totalBytes += dataSize;

          print('✅ Stream "$streamName" recibió datos');
          print('📊 "$streamName" Tamaño del evento: $dataSize bytes');

          if (DateTime.now().difference(startTime).inMinutes >= 1) {
            print(
                '📈 Consumo del stream "$streamName" en el último minuto: $totalBytes bytes');
            totalBytes = 0;
            startTime = DateTime.now();
          }

          var conexionBox = await openBoxSafe('conexionBox');
          if (conexionBox == null) return;
          conexionBox.put('ConexionFirestore', true);
          conexionBox.put(
              'lastSuccessfulConnection', DateTime.now().toIso8601String());
        } catch (e) {
          print('❌ Error al procesar el evento del stream "$streamName": $e');
        }
      },
      onError: (error) async {
        print('❌ Stream "$streamName" encontró un error: $error');
        var conexionBox = await openBoxSafe('conexionBox');
        if (conexionBox == null) return;
        conexionBox.put('ConexionFirestore', false);
        await _logError('Stream Error', error.toString());
      },
      onDone: () async {
        streamCount--;
        streamCounters[streamName] = (streamCounters[streamName] ?? 1) - 1;
        print(
            '⚠ Stream "$streamName" se ha cerrado. (${streamCounters[streamName]} de este tipo, $streamCount total)');
        var conexionBox = await openBoxSafe('conexionBox');
        if (conexionBox == null) return;
        conexionBox.put('ConexionFirestore', false);
      },
      cancelOnError: true,
    );
  }

  /// Convierte todos los tipos especiales de Firestore (GeoPoint, Timestamp) a tipos válidos de JSON
  Map<String, dynamic> _convertFirestoreData(Map<String, dynamic> data) {
    final result = <String, dynamic>{};

    data.forEach((key, value) {
      if (value is GeoPoint) {
        result[key] = {
          'latitude': value.latitude,
          'longitude': value.longitude
        };
      } else if (value is Timestamp) {
        result[key] = value.toDate().toIso8601String();
      } else if (value is Map) {
        result[key] = _convertFirestoreData(value.cast<String, dynamic>());
      } else if (value is List) {
        result[key] = value.map((item) {
          if (item is Map) {
            return _convertFirestoreData(item.cast<String, dynamic>());
          } else if (item is GeoPoint) {
            return {'latitude': item.latitude, 'longitude': item.longitude};
          } else if (item is Timestamp) {
            return item.toDate().toIso8601String();
          }
          return item;
        }).toList();
      } else {
        result[key] = value;
      }
    });

    return result;
  }

  static const String kFirebaseSesionesTag = '[FIREBASE_SESIONES]';

  Stream<Map<String, dynamic>?> getSesionesStream() async* {
    print('$kFirebaseSesionesTag INICIO getSesionesStream');
    var box = await openBoxSafe('sessionBox');
    if (box == null) {
      print('$kFirebaseSesionesTag No se pudo abrir sessionBox');
      return;
    }

    // 🌅 VERIFICAR CAMBIO DE DÍA - Auto-logout si es necesario
    String? loginDate = box.get('loginDate');
    String currentDate = DateTime.now().toIso8601String().split('T')[0];

    if (loginDate != null && loginDate != currentDate) {
      print('$kFirebaseSesionesTag 🌅 CAMBIO DE DÍA DETECTADO');
      print('$kFirebaseSesionesTag    Login: $loginDate');
      print('$kFirebaseSesionesTag    Hoy: $currentDate');
      print('$kFirebaseSesionesTag 🛑 Iniciando auto-logout...');

      await _performAutoLogout(box);
      yield null; // Terminar stream
      return; // Salir del método
    }

    String escenarioId = box.get('escenario', defaultValue: '0').toString();
    String movil = box.get('movil', defaultValue: '0');
    String collectionName = 'sessions-$escenarioId';

    DateTime now = DateTime.now();
    String fechaActual =
        now.toIso8601String().split('T')[0].replaceAll('-', '');

    // Referencia al documento del usuario en activeSessions
    String usuarioDocName = 'Usuario-${box.get('username', defaultValue: '0')}';
    DocumentReference usuarioDocRef = FirebaseFirestore.instance
        .collection(collectionName)
        .doc(fechaActual)
        .collection('activeSessions')
        .doc(usuarioDocName);

    print(
        '$kFirebaseSesionesTag Referencia a doc: $collectionName/$fechaActual/activeSessions/$usuarioDocName');
    try {
      DocumentSnapshot snapshot = await usuarioDocRef.get(
        const GetOptions(source: Source.server),
      );

      if (snapshot.exists) {
        var data = snapshot.data() as Map<String, dynamic>;
        print('$kFirebaseSesionesTag ✅ Documento inicial encontrado: $data');
        yield data;
      } else {
        print(
            '$kFirebaseSesionesTag ⚠️ Documento inicial no encontrado. Eliminando Hive boxes.');
        //await _deleteAllHiveBoxes();
        yield null;
      }
    } catch (error) {
      print(
          '$kFirebaseSesionesTag ❌ Error al obtener el documento inicial: $error');
      await _logError('Firestore Error', error.toString());
      yield null;
    }

    Stream<Map<String, dynamic>?> sesionesStream = usuarioDocRef
        .snapshots(includeMetadataChanges: false)
        .handleError((error) async {
      print('$kFirebaseSesionesTag ❌ Error en el stream de Firestore: $error');
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
          error.message ?? 'Permission denied',
        );
      } else {
        await _logError('Firestore Error', error.toString());
      }
    }).asyncMap((snapshot) async {
      if (snapshot.exists) {
        var data = snapshot.data() as Map<String, dynamic>;
        print(
            '$kFirebaseSesionesTag 🔄 [${DateTime.now()}] Documento actualizado en Firestore: $data');
        print(
            '$kFirebaseSesionesTag 📋 Metadatos del documento: ${snapshot.metadata}');
        return data;
      } else {
        print(
            '$kFirebaseSesionesTag ⚠️ Documento eliminado en Firestore. Eliminando Hive boxes.');
        //await _deleteAllHiveBoxes();
        return null;
      }
    });

    print(
        '$kFirebaseSesionesTag 📡 Iniciando escucha de cambios en Firestore (estructura nueva).');
    // ⚠️ ELIMINAR DUPLICACIÓN: Solo usar monitorStreamWithUsage
    // monitorStream(sesionesStream, 'SesionesStream');
    monitorStreamWithUsage(sesionesStream, 'SesionesStream');
    yield* sesionesStream;
  }

  Future<void> _deleteAllHiveBoxes() async {
    var box = await openBoxSafe('sessionBox');
    var constantBox = await openBoxSafe('constantBox');
    var mensajesBox = await openBoxSafe('mensajesBox');
    var failedRequestsBox = await openBoxSafe('failedRequestsBox');
    if (box != null) await box.deleteFromDisk();
    if (constantBox != null) await constantBox.deleteFromDisk();
    if (mensajesBox != null) await mensajesBox.deleteFromDisk();
    if (failedRequestsBox != null) await failedRequestsBox.deleteFromDisk();
  }

  Stream<List<DocumentSnapshot>> getPedidosStream() async* {
    var box = await openBoxSafe('sessionBox');
    if (box == null) return;
    String escenarioId = box.get('escenario', defaultValue: '0').toString();
    String usuario = box.get('username', defaultValue: '0').toString();
    int movil = int.tryParse(box.get('movil', defaultValue: '0')) ?? 0;

    // Imprimir todo el contenido de sessionBox
    // print("Contenido de sessionBox en pedidos:");
    box.toMap().forEach((key, value) {
      // print('$key: $value');
    });

    String collectionName = 'Pedidos-$escenarioId';
    // Base en UTC-3 para armar AAAAMMDD tanto de hoy como de ayer
    final DateTime base = DateTime.now().toUtc().subtract(Duration(hours: 3));
    final String fechaActualStr =
        base.toIso8601String().split('T')[0].replaceAll('-', '');
    final String fechaAyerStr = base
        .subtract(Duration(days: 1))
        .toIso8601String()
        .split('T')[0]
        .replaceAll('-', '');

    final int fechaActual = int.tryParse(fechaActualStr) ?? 0;
    final int fechaAyer = int.tryParse(fechaAyerStr) ?? 0;

    print(
        "📅 Fechas para consulta de pedidos: hoy=$fechaActual | ayer=$fechaAyer");

    // Build the query
    Query pedidosQuery = _firestore
        .collection(collectionName)
        .where('Movil', isEqualTo: movil)
        .where('VisibleEnApp', isEqualTo: 'S')
        .where('EstadoNro', isEqualTo: 1)
        // Filtra por FchPara igual a hoy o ayer
        .where('FchPara', whereIn: [fechaActual, fechaAyer]);

    Stream<List<DocumentSnapshot>> pedidosStream = pedidosQuery
        .orderBy(
          'FchHoraMaxEntComp',
          descending: false,
        )
        .snapshots()
        .handleError((error) async {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
          error.message ?? 'Permission denied',
        );
      } else {
        // print('Error fetching pedidos: $error');
        await _logError('Firestore Error', error.toString());
      }
      /*bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        // print('⚠ Pérdida de conectividad con Firestore.');
      }*/
    }).map((snapshot) {
      print("📥 Snapshot recibido con ${snapshot.docs.length} docs");
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.removed) {
          print("🗑️ Eliminado: ${change.doc.id}");
        }
      }
      return snapshot.docs;
    });

    // ⚠️ ELIMINAR DUPLICACIÓN: Solo usar monitorStreamWithUsage
    // monitorStream(pedidosStream, 'PedidosStream'); // Monitorea el stream
    print(
        '📡 Iniciando escucha de cambios en Firestore de pedidos antes del tamaño.');
    monitorStreamWithUsage(pedidosStream, 'PedidosStream');
    yield* pedidosStream;
  }

  Stream<List<DocumentSnapshot>> getMensajesStream() async* {
    try {
      var box = await openBoxSafe('sessionBox');
      if (box == null) return;
      String escenarioId = box.get('escenario', defaultValue: '0').toString();
      int movil = int.tryParse(box.get('movil', defaultValue: '0')) ?? 0;

      String collectionName = 'Mensajes-$escenarioId';
      String fechaActualStr = DateTime.now()
          .toUtc()
          .subtract(Duration(hours: 3))
          .toIso8601String()
          .split('T')[0]
          .replaceAll('-', '');
      int fechaActual = int.tryParse(fechaActualStr) ?? 0;

      try {
        Stream<List<DocumentSnapshot>> mensajesStream = _firestore
            .collection(collectionName)
            .where('Movil', isEqualTo: movil)
            .where('VisibleEnApp', isEqualTo: 'S')
            //.where('FchMsj', isEqualTo: fechaActual)
            .snapshots()
            .handleError((error) async {
          // print('❌ Error in Firestore stream: $error');
          if (error is FirebaseException && error.code == 'permission-denied') {
            await _logFirestorePermissionError(
              error.message ?? 'Permission denied',
            );
          } else {
            await _logError('Firestore Error', error.toString());
          }
          /*bool isConnected = await checkFirestoreConnectivity();
          if (!isConnected) {
            // print('⚠ Pérdida de conectividad con Firestore.');
          }*/
        }).map((snapshot) {
          // print('Fetched ${snapshot.docs.length} mensajes');
          snapshot.docs.forEach((doc) {
            // print('Mensaje: ${doc.data()}');
          });
          return snapshot.docs;
        });

        // ⚠️ ELIMINAR DUPLICACIÓN: Solo usar monitorStreamWithUsage
        // monitorStream(mensajesStream, 'MensajesStream'); // Monitorea el stream
        monitorStreamWithUsage(mensajesStream, 'MensajesStream');
        yield* mensajesStream;
      } catch (e, stackTrace) {
        // print('❌ Error setting up Firestore stream: $e');
        // print('StackTrace: $stackTrace');
        await _logError('Stream Setup Error', e.toString());
      }
    } catch (e, stackTrace) {
      // print('❌ Error in getMensajesStream: $e');
      // print('StackTrace: $stackTrace');
      await _logError('General Error', e.toString());
    }
  }

  Future<List<DocumentSnapshot>> getUnreadMessages() async {
    var box = await openBoxSafe('sessionBox');
    if (box == null) return [];
    String escenarioId = box.get('escenario', defaultValue: '0').toString();
    int movil = int.tryParse(box.get('movil', defaultValue: '0')) ?? 0;

    String collectionName = 'Mensajes-$escenarioId';

    QuerySnapshot snapshot = await _firestore
        .collection(collectionName)
        .where('Movil', isEqualTo: movil)
        .where('VisibleEnApp', isEqualTo: 'S')
        .where(
          'FchHoraLeido',
          isNull: true,
        ) // Ensure the field does not exist
        .get();

    return snapshot.docs;
  }

  Future<void> markMessageAsRead(String messageId) async {
    var box = await openBoxSafe('sessionBox');
    if (box == null) return;
    String escenarioId = box.get('escenario', defaultValue: '0').toString();
    String collectionName = 'Mensajes-$escenarioId';

    await _firestore
        .collection(collectionName)
        .doc(messageId)
        .update({'FchHoraLeido': FieldValue.serverTimestamp()}).catchError(
            (error) async {
      // print('Error marking message as read: $error');
      await _logError('Firestore Error', error.toString());
      /*bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        // print('⚠ Pérdida de conectividad con Firestore.');
      }*/
    });
  }

  Future<void> updateMessageField(
    String messageId,
    Map<String, dynamic> fields,
  ) async {
    var box = await openBoxSafe('sessionBox');
    if (box == null) return;
    String escenarioId = box.get('escenario', defaultValue: '0').toString();
    String collectionName = 'Mensajes-$escenarioId';

    await _firestore
        .collection(collectionName)
        .doc(messageId)
        .update(fields)
        .catchError((error) async {
      // print('Error updating message field: $error');
      await _logError('Firestore Error', error.toString());
      /*bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        // print('⚠ Pérdida de conectividad con Firestore.');
      }*/
    });
  }

  Stream<DocumentSnapshot?> getMovilStream() async* {
    var box = await openBoxSafe('sessionBox');
    if (box == null) return;
    String escenarioId = box.get('escenario', defaultValue: '0').toString();
    String movil = box.get('movil', defaultValue: '0');
    String collectionName = 'Moviles-$escenarioId';
    String documentName = 'Moviles-$movil';

    Stream<DocumentSnapshot?> movilStream = _firestore
        .collection(collectionName)
        .doc(documentName)
        .snapshots()
        .handleError((error) async {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
          error.message ?? 'Permission denied',
        );
      } else {
        // print('Error fetching movil: $error');
        await _logError('Firestore Error', error.toString());
      }
      /*bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        // print('⚠ Pérdida de conectividad con Firestore.');
      }*/
    }).map((snapshot) {
      // print('Fetched movil: ${snapshot.data()}');
      return snapshot;
    });

    // ⚠️ ELIMINAR DUPLICACIÓN: Solo usar monitorStreamWithUsage
    // monitorStream(movilStream, 'MovilStream'); // Monitorea el stream
    monitorStreamWithUsage(movilStream, 'MovilStream');
    yield* movilStream;
  }

  Future<void> updateMovilEstado(int estado) async {
    var box = await openBoxSafe('sessionBox');
    if (box == null) return;
    var movilid = await box.get('movil');
    String escenarioId = box.get('escenario', defaultValue: '0').toString();
    String collectionName = 'Moviles-$escenarioId';
    String documentName = 'Moviles-$movilid';

    // print('Updating movil estado to $estado');
    // print('Movil ID: $movilid');

    await _firestore
        .collection(collectionName)
        .doc(documentName)
        .update({'EstadoNro': estado}).catchError((error) async {
      // print('Error updating movil estado: $error');
      await _logError('Firestore Error', error.toString());
      /*bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        // print('⚠ Pérdida de conectividad con Firestore.');
      }*/
    });
  }

  Stream<List<Map<String, dynamic>>> getSubEstadoMovilesStream() async* {
    var box = await openBoxSafe('sessionBox');
    if (box == null) return;
    String escenarioId = box.get('escenario', defaultValue: '0').toString();
    print('Escenario ID: $escenarioId');
    print('Movil ID: ${box.get('movil')}');
    String collectionName = 'SubEstadoMoviles-$escenarioId';

    Stream<List<Map<String, dynamic>>> subEstadoMovilesStream = _firestore
        .collection(collectionName)
        .snapshots()
        .handleError((error) async {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
          error.message ?? 'Permission denied',
        );
      } else {
        // print('Error fetching subestado moviles: $error');
        await _logError('Firestore Error', error.toString());
      }
      /*bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        // print('⚠ Pérdida de conectividad con Firestore.');
      }*/
    }).map((snapshot) {
      // print('Fetched ${snapshot.docs.length} subestado moviles');
      return snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Add document ID to the data
        // print('SubEstadoMovil: $data');
        return data;
      }).toList();
    });

    // ⚠️ ELIMINAR DUPLICACIÓN: Solo usar monitorStreamWithUsage
    // monitorStream(
    //   subEstadoMovilesStream,
    //   'SubEstadoMovilesStream',
    // ); // Monitorea el stream
    monitorStreamWithUsage(subEstadoMovilesStream, 'SubEstadoMovilesStream');
    // print('SubEstadoMovilesStream: $subEstadoMovilesStream');
    yield* subEstadoMovilesStream;
  }

  Stream<List<Map<String, dynamic>>>
      getSubEstadoFinalizacionPedidosStream() async* {
    var box = await openBoxSafe('sessionBox');
    if (box == null) return;
    String escenarioId = box.get('escenario', defaultValue: '0').toString();
    String collectionName = 'SubEstadoFinalizacionPedidos-$escenarioId';

    Stream<List<Map<String, dynamic>>> subEstadoFinalizacionPedidosStream =
        _firestore
            .collection(collectionName)
            .orderBy('Orden')
            .snapshots()
            .handleError((error) async {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
          error.message ?? 'Permission denied',
        );
      } else {
        // print('Error fetching subestado finalizacion pedidos: $error');
        await _logError('Firestore Error', error.toString());
      }
      /*bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        // print('⚠ Pérdida de conectividad con Firestore.');
      }*/
    }).map((snapshot) {
      // print(
      //   'Fetched ${snapshot.docs.length} subestado finalizacion pedidos',
      // );
      return snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Add document ID to the data
        // print('SubEstadoFinalizacionPedido: $data');
        return data;
      }).toList();
    });

    // ⚠️ ELIMINAR DUPLICACIÓN: Solo usar monitorStreamWithUsage
    // monitorStream(
    //   subEstadoFinalizacionPedidosStream,
    //   'SubEstadoFinalizacionPedidosStream',
    // ); // Monitorea el stream
    monitorStreamWithUsage(
      subEstadoFinalizacionPedidosStream,
      'SubEstadoFinalizacionPedidosStream',
    );
    yield* subEstadoFinalizacionPedidosStream;
  }

  Stream<List<Map<String, dynamic>>>
      getSubEstadoFinalizacionServicesStream() async* {
    var box = await openBoxSafe('sessionBox');
    if (box == null) return;
    String escenarioId = box.get('escenario', defaultValue: '0').toString();
    String collectionName = 'SubEstadoFinalizacionServices-$escenarioId';

    Stream<List<Map<String, dynamic>>> SubEstadoFinalizacionServicesStream =
        _firestore
            .collection(collectionName)
            .orderBy('Orden')
            .snapshots()
            .handleError((error) async {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
          error.message ?? 'Permission denied',
        );
      } else {
        // print('Error fetching subestado finalizacion pedidos: $error');
        await _logError('Firestore Error', error.toString());
      }
      /*bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        // print('⚠ Pérdida de conectividad con Firestore.');
      }*/
    }).map((snapshot) {
      // print(
      //   'Fetched ${snapshot.docs.length} subestado finalizacion pedidos',
      // );
      return snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Add document ID to the data
        // print('SubEstadoFinalizacionPedido: $data');
        return data;
      }).toList();
    });

    // ⚠️ ELIMINAR DUPLICACIÓN: Solo usar monitorStreamWithUsage
    // monitorStream(
    //   SubEstadoFinalizacionServicesStream,
    //   'SubEstadoFinalizacionServicesStream',
    // ); // Monitorea el stream
    monitorStreamWithUsage(
      SubEstadoFinalizacionServicesStream,
      'SubEstadoFinalizacionServicesStream',
    );
    yield* SubEstadoFinalizacionServicesStream;
  }

  // Agrega más métodos para otras consultas según sea necesario

  /// 🌅 Auto-logout al cambio de día
  Future<void> _performAutoLogout(Box sessionBox) async {
    try {
      final movil = sessionBox.get('movil', defaultValue: 0);
      final deviceId = sessionBox.get('deviceId', defaultValue: '');
      final usuario = sessionBox.get('username', defaultValue: '');
      final escenario = sessionBox.get('escenario', defaultValue: '0');

      print('$kFirebaseSesionesTag 🛑 AUTO-LOGOUT por cambio de día');
      print('$kFirebaseSesionesTag    Movil: $movil, Usuario: $usuario');

      // 1️⃣ Detener GPS service
      try {
        final platform = MethodChannel("background_service");
        await platform.invokeMethod("stopLocationService", {
          "movil": movil.toString(),
          "escenario": escenario,
          "usuario": usuario,
          "deviceId": deviceId,
        });
        print('$kFirebaseSesionesTag ✅ GPS service detenido');
      } catch (e) {
        print('$kFirebaseSesionesTag ❌ Error deteniendo GPS service: $e');
      }

      // 2️⃣ Registrar cierre en backend
      try {
        await RioGasService.registrarCierre(
          movil,
          deviceId,
          usuario,
          DateTime.now().toIso8601String(),
          'AutoLogoutCambioDia',
        );
        print('$kFirebaseSesionesTag ✅ Cierre registrado en backend');
      } catch (e) {
        print('$kFirebaseSesionesTag ❌ Error registrando cierre: $e');
      }

      // 3️⃣ Cancelar todos los streams
      try {
        PersistentStreamManager().dispose();
        print('$kFirebaseSesionesTag ✅ Streams cancelados');
      } catch (e) {
        print('$kFirebaseSesionesTag ❌ Error cancelando streams: $e');
      }

      // 4️⃣ Limpiar Hive
      try {
        await sessionBox.clear();
        if (Hive.isBoxOpen('mensajesBox')) {
          await Hive.box('mensajesBox').clear();
        }
        if (Hive.isBoxOpen('pedidosBox')) {
          await Hive.box('pedidosBox').clear();
        }
        print('$kFirebaseSesionesTag ✅ Hive limpiado');
      } catch (e) {
        print('$kFirebaseSesionesTag ❌ Error limpiando Hive: $e');
      }

      print('$kFirebaseSesionesTag ✅ AUTO-LOGOUT COMPLETADO');
    } catch (e) {
      print('$kFirebaseSesionesTag ❌ Error en auto-logout: $e');
    }
  }

  static Future<void> _logError(
    String type,
    String message, [
    String? additionalInfo,
  ]) async {
    var errorBox = await Hive.openBox<ErrorEvent>('errorBox');
    var errorEvent = ErrorEvent(
      type: type,
      message: message,
      timestamp: DateTime.now(),
      additionalInfo: additionalInfo,
    );
    await errorBox.add(errorEvent);
  }
}
