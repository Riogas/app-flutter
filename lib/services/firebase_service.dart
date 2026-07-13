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
import 'logout_service.dart'; // 🔥 Para auto-logout por cambio de día

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

  // 🛡️ OPCIÓN 4: Variables para protección contra race conditions
  static Map<String, dynamic>? _lastValidSessionData;
  static DateTime? _lastValidSessionTimestamp;
  static DateTime? _lastServerNullTimestamp;
  static const Duration _sessionGracePeriod = Duration(seconds: 5);

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

  /// 🚨 Verifica SINCRÓNICAMENTE si el documento de sesión existe y es válido
  /// Retorna: true si sesión válida, false si debe desloguearse
  ///
  /// Este método se ejecuta ANTES de inicializar streams para evitar
  /// mostrar datos de pedidos cuando la sesión ya no es válida
  Future<bool> verificarSesionValida() async {
    print('$kFirebaseSesionesTag 🔍 INICIO verificación síncrona de sesión');

    var box = await openBoxSafe('sessionBox');
    if (box == null) {
      print('$kFirebaseSesionesTag ❌ No se pudo abrir sessionBox');
      return false;
    }

    // Verificar cambio de día primero
    String? loginDate = box.get('loginDate');
    String currentDate = DateTime.now().toIso8601String().split('T')[0];

    if (loginDate != null && loginDate != currentDate) {
      print(
          '$kFirebaseSesionesTag 🌅 Cambio de día detectado - Sesión inválida');
      print('$kFirebaseSesionesTag    Login: $loginDate → Hoy: $currentDate');
      return false;
    }

    String escenarioId = box.get('escenario', defaultValue: '0').toString();
    String usuarioDocName = 'Usuario-${box.get('username', defaultValue: '0')}';
    String fechaActual =
        DateTime.now().toIso8601String().split('T')[0].replaceAll('-', '');
    String deviceId = box.get('deviceId', defaultValue: '');
    String collectionName = 'sessions-$escenarioId';

    print(
        '$kFirebaseSesionesTag 📍 Verificando doc: $collectionName/$fechaActual/activeSessions/$usuarioDocName');
    print('$kFirebaseSesionesTag 📱 deviceId local: $deviceId');

    try {
      DocumentSnapshot snapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(fechaActual)
          .collection('activeSessions')
          .doc(usuarioDocName)
          .get(const GetOptions(
              source: Source.server)) // Forzar lectura del servidor
          .timeout(
            Duration(seconds: 5),
            onTimeout: () =>
                throw TimeoutException('Timeout verificando sesión'),
          );

      if (!snapshot.exists) {
        print('$kFirebaseSesionesTag ⚠️ Documento NO existe - Sesión inválida');
        return false;
      }

      var data = snapshot.data() as Map<String, dynamic>;
      String firestoreDeviceId = data['idTerminal'] ?? '';

      print(
          '$kFirebaseSesionesTag 📱 deviceId en Firestore: $firestoreDeviceId');

      if (firestoreDeviceId != deviceId) {
        print(
            '$kFirebaseSesionesTag ⚠️ idTerminal NO coincide - Sesión usurpada por otro dispositivo');
        print(
            '$kFirebaseSesionesTag    Local: $deviceId ≠ Firestore: $firestoreDeviceId');
        return false;
      }

      print('$kFirebaseSesionesTag ✅ Sesión VÁLIDA - deviceId coincide');
      return true;
    } catch (e) {
      print('$kFirebaseSesionesTag ❌ Error verificando sesión: $e');
      // En caso de error de red, ser conservador y permitir continuar
      // (el stream de sesiones lo validará de forma reactiva después)
      return true;
    }
  }

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

    // ✅ SOLUCIÓN 2: Intentar leer del caché local primero, luego del servidor
    try {
      print('$kFirebaseSesionesTag 📡 [T4] Intentando leer del caché local...');
      print(
          '$kFirebaseSesionesTag ⏱️ Timestamp: ${DateTime.now().millisecondsSinceEpoch}');

      // 1️⃣ Intentar leer del caché local primero (rápido)
      DocumentSnapshot snapshot = await usuarioDocRef
          .get(
        const GetOptions(source: Source.cache),
      )
          .timeout(
        Duration(seconds: 2),
        onTimeout: () {
          print(
              '$kFirebaseSesionesTag ⚠️ Timeout leyendo caché, intentando servidor...');
          throw TimeoutException('Timeout caché');
        },
      );

      if (snapshot.exists && snapshot.data() != null) {
        var data = snapshot.data() as Map<String, dynamic>;
        print(
            '$kFirebaseSesionesTag ✅ Documento encontrado en CACHÉ: ${data['idUsuario']}');
        print(
            '$kFirebaseSesionesTag 📝 [T5] Timestamp: ${DateTime.now().millisecondsSinceEpoch}');
        yield data;
      } else {
        // 2️⃣ Si no está en caché, leer del servidor
        print(
            '$kFirebaseSesionesTag 📡 No encontrado en caché, leyendo del SERVIDOR...');
        snapshot = await usuarioDocRef
            .get(
          const GetOptions(source: Source.server),
        )
            .timeout(
          Duration(seconds: 5),
          onTimeout: () {
            print('$kFirebaseSesionesTag ⚠️ Timeout leyendo servidor');
            throw TimeoutException('Timeout servidor');
          },
        );

        if (snapshot.exists) {
          var data = snapshot.data() as Map<String, dynamic>;
          print(
              '$kFirebaseSesionesTag ✅ Documento encontrado en SERVIDOR: ${data['idUsuario']}');
          print(
              '$kFirebaseSesionesTag 📝 [T5] Timestamp: ${DateTime.now().millisecondsSinceEpoch}');
          yield data;
        } else {
          print(
              '$kFirebaseSesionesTag ⚠️ Documento NO encontrado ni en caché ni en servidor');
          print(
              '$kFirebaseSesionesTag ⚠️ Esta situación causará eliminación de sesión si ocurre después de crear el documento');
          //await _deleteAllHiveBoxes();
          yield null;
        }
      }
    } catch (error) {
      print(
          '$kFirebaseSesionesTag ❌ Error al obtener el documento inicial: $error');
      print('$kFirebaseSesionesTag ❌ Stack trace:');
      print(StackTrace.current);
      await _logError('Firestore Error', error.toString());
      yield null;
    }

    print(
        '$kFirebaseSesionesTag 🔊 Iniciando snapshots() stream para escuchar cambios en tiempo real...');
    print(
        '$kFirebaseSesionesTag 📍 Documento a observar: $collectionName/$fechaActual/activeSessions/$usuarioDocName');
    print(
        '$kFirebaseSesionesTag 🔑 usuario: ${box.get('username')}, movil: $movil, escenario: $escenarioId');
    print('$kFirebaseSesionesTag 📱 deviceId: ${box.get('deviceId')}');

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
      print(
          '$kFirebaseSesionesTag ════════════════════════════════════════════════════════');
      print('$kFirebaseSesionesTag 🔔 SNAPSHOT RECIBIDO - Análisis Detallado');
      print(
          '$kFirebaseSesionesTag ════════════════════════════════════════════════════════');
      print(
          '$kFirebaseSesionesTag ⏰ Timestamp: ${DateTime.now().toIso8601String()}');
      print(
          '$kFirebaseSesionesTag 📍 Buscando: $collectionName/$fechaActual/activeSessions/$usuarioDocName');
      print('$kFirebaseSesionesTag 📄 Document ID esperado: $usuarioDocName');
      print('$kFirebaseSesionesTag ✅ snapshot.exists: ${snapshot.exists}');
      print('$kFirebaseSesionesTag 🔑 snapshot.id: ${snapshot.id}');
      print(
          '$kFirebaseSesionesTag 📋 snapshot.reference.path: ${snapshot.reference.path}');
      print('$kFirebaseSesionesTag 📊 snapshot.metadata:');
      print(
          '$kFirebaseSesionesTag    - hasPendingWrites: ${snapshot.metadata.hasPendingWrites}');
      print(
          '$kFirebaseSesionesTag    - isFromCache: ${snapshot.metadata.isFromCache}');

      if (snapshot.exists) {
        var data = snapshot.data() as Map<String, dynamic>;

        // 🛡️ OPCIÓN 4: Guardar sesión válida en memoria
        _lastValidSessionData = data;
        _lastValidSessionTimestamp = DateTime.now();
        _lastServerNullTimestamp = null; // Reset del timestamp de "null"

        print('$kFirebaseSesionesTag ✅✅✅ DOCUMENTO ENCONTRADO ✅✅✅');
        print('$kFirebaseSesionesTag 🛡️ Guardado en memoria (Opción 4)');
        print('$kFirebaseSesionesTag ⏰ Timestamp: $_lastValidSessionTimestamp');
        print('$kFirebaseSesionesTag � Contenido del documento:');
        print('$kFirebaseSesionesTag    - idUsuario: ${data['idUsuario']}');
        print('$kFirebaseSesionesTag    - idTerminal: ${data['idTerminal']}');
        print('$kFirebaseSesionesTag    - movil: ${data['movil']}');
        print('$kFirebaseSesionesTag    - idSesion: ${data['idSesion']}');
        print('$kFirebaseSesionesTag    - estado: ${data['estado']}');
        print(
            '$kFirebaseSesionesTag    - fchHoraInicio: ${data['fchHoraInicio']}');
        print('$kFirebaseSesionesTag 📦 Data completo: $data');
        print(
            '$kFirebaseSesionesTag ════════════════════════════════════════════════════════');
        return data;
      } else {
        print('$kFirebaseSesionesTag 🔴 DOCUMENTO NO EXISTE EN SNAPSHOT');

        // 🛡️ OPCIÓN 4: DEBOUNCE - Verificar si estamos en período de gracia
        if (!snapshot.metadata.isFromCache &&
            _lastValidSessionData != null &&
            _lastValidSessionTimestamp != null) {
          final timeSinceLastValid =
              DateTime.now().difference(_lastValidSessionTimestamp!);

          print('$kFirebaseSesionesTag 🛡️ OPCIÓN 4: DEBOUNCE ACTIVO');
          print(
              '$kFirebaseSesionesTag ⏰ Tiempo desde última sesión válida: ${timeSinceLastValid.inMilliseconds}ms');
          print(
              '$kFirebaseSesionesTag ⏰ Período de gracia: ${_sessionGracePeriod.inMilliseconds}ms');

          if (timeSinceLastValid < _sessionGracePeriod) {
            // ✅ Dentro del período de gracia - IGNORAR snapshot falso
            print('$kFirebaseSesionesTag ✅✅✅ DENTRO DEL PERÍODO DE GRACIA ✅✅✅');
            print(
                '$kFirebaseSesionesTag 🛡️ IGNORANDO snapshot falso del servidor');
            print('$kFirebaseSesionesTag 📦 Devolviendo sesión desde memoria');
            print(
                '$kFirebaseSesionesTag 💡 Esto previene logout por Firebase Auth refresh');
            print(
                '$kFirebaseSesionesTag ════════════════════════════════════════════════════════');
            return _lastValidSessionData;
          } else {
            // ❌ Fuera del período de gracia - Eliminación real
            print(
                '$kFirebaseSesionesTag ⏰ FUERA del período de gracia (${timeSinceLastValid.inSeconds}s > ${_sessionGracePeriod.inSeconds}s)');
            print('$kFirebaseSesionesTag ❌ Eliminación CONFIRMADA por timeout');
          }
        }

        // 🛡️ OPCIÓN 3 (FALLBACK): Si el servidor dice que no existe pero NO viene del caché,
        // re-leer del caché antes de asumir eliminación (protege contra race conditions)
        if (!snapshot.metadata.isFromCache) {
          print(
              '$kFirebaseSesionesTag � Snapshot del SERVIDOR dice "no existe"');
          print(
              '$kFirebaseSesionesTag 🛡️ OPCIÓN 3 (FALLBACK): RE-LEYENDO DEL CACHÉ para validar...');

          try {
            DocumentSnapshot cacheSnapshot = await usuarioDocRef
                .get(
              const GetOptions(source: Source.cache),
            )
                .timeout(
              Duration(seconds: 2),
              onTimeout: () {
                print(
                    '$kFirebaseSesionesTag ⚠️ Timeout leyendo caché de validación');
                throw TimeoutException('Cache validation timeout');
              },
            );

            if (cacheSnapshot.exists) {
              var cacheData = cacheSnapshot.data() as Map<String, dynamic>;
              print('$kFirebaseSesionesTag ✅ DOCUMENTO ENCONTRADO EN CACHÉ!');
              print(
                  '$kFirebaseSesionesTag 🛡️ IGNORANDO snapshot falso del servidor');
              print(
                  '$kFirebaseSesionesTag 📦 Usando data del caché: ${cacheData['idSesion']}');
              print(
                  '$kFirebaseSesionesTag 💡 Opción 3 funcionó (caché aún válido)');
              print(
                  '$kFirebaseSesionesTag ════════════════════════════════════════════════════════');
              return cacheData; // ✅ Usar data del caché
            } else {
              print(
                  '$kFirebaseSesionesTag ❌ Tampoco existe en caché - Eliminación CONFIRMADA');
            }
          } catch (e) {
            print('$kFirebaseSesionesTag ⚠️ Error verificando caché: $e');
            // Continuar con el flujo normal de "no existe"
          }
        } else {
          print('$kFirebaseSesionesTag 📦 Snapshot del CACHÉ dice "no existe"');
        }

        print('$kFirebaseSesionesTag 🔴🔴🔴 ELIMINACIÓN CONFIRMADA 🔴🔴🔴');
        print('$kFirebaseSesionesTag ⚠️ Razones posibles:');
        print('$kFirebaseSesionesTag    1. El documento nunca fue creado');
        print(
            '$kFirebaseSesionesTag    2. El documento fue eliminado externamente');
        print(
            '$kFirebaseSesionesTag    3. El ID del documento no coincide con el esperado');
        print('$kFirebaseSesionesTag    4. Problema de permisos de Firestore');
        print('$kFirebaseSesionesTag 🔍 Verificar en Firebase Console:');
        print(
            '$kFirebaseSesionesTag    Ruta: $collectionName → $fechaActual → activeSessions');
        print(
            '$kFirebaseSesionesTag    Buscar documento con ID: $usuarioDocName');
        print(
            '$kFirebaseSesionesTag 💡 Comparar con session_service.dart línea 334:');
        print(
            '$kFirebaseSesionesTag    ¿El ID creado coincide con: $usuarioDocName?');
        print(
            '$kFirebaseSesionesTag ════════════════════════════════════════════════════════');
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

  /// Lectura única del catálogo SubEstadoMoviles (reemplaza el listener 24h; cache en Hive).
  Future<List<Map<String, dynamic>>> getSubEstadoMovilesOnce() async {
    var box = await openBoxSafe('sessionBox');
    if (box == null) return [];
    String escenarioId = box.get('escenario', defaultValue: '0').toString();
    String collectionName = 'SubEstadoMoviles-$escenarioId';

    try {
      final snapshot = await _firestore.collection(collectionName).get();
      return snapshot.docs.map((doc) {
        var data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (error) {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
          error.message ?? 'Permission denied',
        );
      } else {
        await _logError('Firestore Error', error.toString());
      }
      rethrow;
    }
  }

  /// Lectura única del catálogo SubEstadoFinalizacionPedidos (reemplaza el listener 24h; cache en Hive).
  Future<List<Map<String, dynamic>>>
      getSubEstadoFinalizacionPedidosOnce() async {
    var box = await openBoxSafe('sessionBox');
    if (box == null) return [];
    String escenarioId = box.get('escenario', defaultValue: '0').toString();
    String collectionName = 'SubEstadoFinalizacionPedidos-$escenarioId';

    try {
      final snapshot = await _firestore
          .collection(collectionName)
          .orderBy('Orden')
          .get();
      return snapshot.docs.map((doc) {
        var data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (error) {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
          error.message ?? 'Permission denied',
        );
      } else {
        await _logError('Firestore Error', error.toString());
      }
      rethrow;
    }
  }

  // Agrega más métodos para otras consultas según sea necesario

  /// 🌅 Auto-logout al cambio de día
  Future<void> _performAutoLogout(Box sessionBox) async {
    try {
      final movil = sessionBox.get('movil', defaultValue: 0);
      final usuario = sessionBox.get('username', defaultValue: '');

      print('$kFirebaseSesionesTag 🛑 AUTO-LOGOUT por cambio de día');
      print('$kFirebaseSesionesTag    Movil: $movil, Usuario: $usuario');

      // 🔥 USAR LogoutService.executeLogout() para consistencia
      // Esto garantiza que:
      // 1. firstLoginDone se resetee a true
      // 2. GPS service se detenga correctamente
      // 3. Backend registre el cierre
      // 4. Hive y SharedPreferences se limpien
      await LogoutService.executeLogout(
        isRemoteLogout: false, // Es auto-logout por cambio de día
      );

      print(
          '$kFirebaseSesionesTag ✅ AUTO-LOGOUT COMPLETADO (via LogoutService)');
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
