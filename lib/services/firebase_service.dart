import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'dart:convert'; // Para calcular el tamaño de los datos
import '../utils/error_event.dart';
import '../utils/config.dart'; // Importa el archivo de configuración
import '../utils/constantes.dart'; // Importa la función getConstantValue

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

    // Autenticar al usuario
    await signInWithEmailAndPassword();
  }

  Future<void> signInWithEmailAndPassword() async {
    try {
      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: Config.firestoreEmail, // Utiliza la variable global
        password: Config.firestorePassword, // Utiliza la variable global
      );
      _user = userCredential.user;
      // print("User signed in: ${_user?.email}");
    } on FirebaseAuthException catch (e) {
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
    String fechaActualStr = DateTime.now()
        .toUtc()
        .subtract(Duration(hours: 3))
        .toIso8601String()
        .split('T')[0]
        .replaceAll('-', '');
    int fechaActual = int.tryParse(fechaActualStr) ?? 0;

    // Build the query
    Query pedidosQuery = _firestore
        .collection(collectionName)
        .where('Movil', isEqualTo: movil)
        .where('VisibleEnApp', isEqualTo: 'S')
        .where('EstadoNro', isEqualTo: 1)
        .where('FchPara', isLessThanOrEqualTo: fechaActual);

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
