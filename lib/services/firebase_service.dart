import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import '../utils/error_event.dart';
import '../utils/config.dart'; // Importa el archivo de configuración

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? _user;

  Future<void> initializeFirebase() async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      // Inicializar Firebase
      await Firebase.initializeApp();
      print('Firebase initialized successfully');
    } catch (e) {
      print('Error initializing Firebase: $e');
      await _logError('Firebase Initialization Error', e.toString());
    }

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
      print("User signed in: ${_user?.email}");
    } on FirebaseAuthException catch (e) {
      print("Error signing in: $e");
      await _logError('Firebase Auth Error', e.toString());
    }
  }

  Future<bool> checkFirestoreConnectivity() async {
    try {
      await _firestore.collection('test').limit(1).get();
      return true;
    } catch (e) {
      print('No Firestore connectivity: $e');
      return false;
    }
  }

  Future<void> _logFirestorePermissionError(String message) async {
    print('Firestore permission error: $message');
    await _logError('Firestore Permission Error', message);
  }

  Stream<Map<String, dynamic>?> getSesionesStream() async* {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    String movil = box.get('movil', defaultValue: '0');
    String collectionName = 'Sesiones-$escenarioId';

    // Obtener la fecha actual en formato yyyymmdd
    DateTime now = DateTime.now();
    String fechaActual =
        now.toIso8601String().split('T')[0].replaceAll('-', '');

    // Nombre de la colección del móvil
    String movilCollectionName = 'Movil-$movil';

    // Nombre del documento "activo"
    String activoDocName = 'activo';

    // Obtener la referencia del documento "activo"
    DocumentReference activoDocRef = FirebaseFirestore.instance
        .collection(collectionName)
        .doc(fechaActual)
        .collection(movilCollectionName)
        .doc(activoDocName);

    try {
      // 🌐 Hacer una consulta inicial FORZANDO datos desde el servidor (sin caché)
      DocumentSnapshot snapshot = await activoDocRef.get(
        const GetOptions(source: Source.server),
      );

      if (snapshot.exists) {
        var data = snapshot.data() as Map<String, dynamic>;
        print('✅ Sesión activa encontrada desde el servidor: $data');
        yield data;
      } else {
        print('⚠ No se encontró el documento "activo" en el servidor.');
        yield null;
      }
    } catch (error) {
      print('❌ Error al obtener sesión desde el servidor: $error');
      await _logError('Firestore Error', error.toString());
      yield null;
    }

    // 📡 Ahora, escuchar cambios en Firestore en tiempo real
    yield* activoDocRef
        .snapshots(includeMetadataChanges: true)
        .handleError((error) async {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
            error.message ?? 'Permission denied');
      } else {
        print('❌ Error al escuchar cambios en Firestore: $error');
        await _logError('Firestore Error', error.toString());
      }
      bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        print('⚠ Pérdida de conectividad con Firestore.');
      }
    }).map((snapshot) {
      if (snapshot.exists) {
        var data = snapshot.data() as Map<String, dynamic>;
        print('🔄 Sesión activa actualizada en Firestore: $data');
        return data;
      } else {
        print('⚠ Documento "activo" eliminado o no encontrado en Firestore.');
        return null;
      }
    });
  }

  Stream<List<DocumentSnapshot>> getPedidosStream() async* {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    int movil = int.tryParse(box.get('movil', defaultValue: '0')) ?? 0;

    // Imprimir todo el contenido de sessionBox
    print("Contenido de sessionBox en pedidos:");
    box.toMap().forEach((key, value) {
      print('$key: $value');
    });

    String collectionName = 'Pedidos-$escenarioId';
    String fechaActualStr = DateTime.now()
        .toUtc()
        .subtract(Duration(hours: 3))
        .toIso8601String()
        .split('T')[0]
        .replaceAll('-', '');
    int fechaActual = int.tryParse(fechaActualStr) ?? 0;

    yield* _firestore
        .collection(collectionName)
        .where('Movil', isEqualTo: movil)
        .where('FchPara', isEqualTo: fechaActual)
        .where('VisibleEnApp', isEqualTo: 'S')
        .where('EstadoNro', isEqualTo: 1)
        .orderBy('FchHoraMaxEntComp',
            descending: false) // Ordenar por FchHoraPara en forma ascendente
        .snapshots()
        .handleError((error) async {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
            error.message ?? 'Permission denied');
      } else {
        print('Error fetching pedidos: $error');
        await _logError('Firestore Error', error.toString());
      }
      bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        print('⚠ Pérdida de conectividad con Firestore.');
      }
    }).map((snapshot) {
      print('Fetched ${snapshot.docs.length} pedidos');
      snapshot.docs.forEach((doc) {
        print('Pedido: ${doc.data()}');
      });
      return snapshot.docs;
    });
  }

  Stream<List<DocumentSnapshot>> getPedidosCumplidosStream() async* {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    int movil = int.tryParse(box.get('movil', defaultValue: '0')) ?? 0;

    String collectionName = 'Pedidos-$escenarioId';
    String fechaActualStr = DateTime.now()
        .toUtc()
        .subtract(Duration(hours: 3))
        .toIso8601String()
        .split('T')[0]
        .replaceAll('-', '');
    int fechaActual = int.tryParse(fechaActualStr) ?? 0;

    yield* _firestore
        .collection(collectionName)
        .where('Movil', isEqualTo: movil)
        .where('FchPara', isEqualTo: fechaActual)
        .where('VisibleEnApp', isEqualTo: 'S')
        .where('EstadoNro', isEqualTo: 2)
        .orderBy('FchHoraPara',
            descending: false) // Ordenar por FchHoraPara en forma ascendente
        .snapshots()
        .handleError((error) async {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
            error.message ?? 'Permission denied');
      } else {
        print('Error fetching pedidos cumplidos: $error');
        await _logError('Firestore Error', error.toString());
      }
      bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        print('⚠ Pérdida de conectividad con Firestore.');
      }
    }).map((snapshot) {
      print('Fetched ${snapshot.docs.length} pedidos cumplidos');
      snapshot.docs.forEach((doc) {
        print('Pedido cumplido: ${doc.data()}');
      });
      return snapshot.docs;
    });
  }

  Stream<List<DocumentSnapshot>> getConstantesStream() async* {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    String collectionName = 'Constantes-$escenarioId';

    yield* _firestore
        .collection(collectionName)
        .snapshots()
        .handleError((error) async {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
            error.message ?? 'Permission denied');
      } else {
        print('Error fetching constantes: $error');
        await _logError('Firestore Error', error.toString());
      }
      bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        print('⚠ Pérdida de conectividad con Firestore.');
      }
    }).map((snapshot) {
      print('Fetched ${snapshot.docs.length} constantes');
      snapshot.docs.forEach((doc) {
        print('Constante: ${doc.data()}');
      });
      return snapshot.docs;
    });
  }

  Stream<List<DocumentSnapshot>> getMensajesStream() async* {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    int movil = int.tryParse(box.get('movil', defaultValue: '0')) ?? 0;

    String collectionName = 'Mensajes-$escenarioId';
    String fechaActualStr = DateTime.now()
        .toUtc()
        .subtract(Duration(hours: 3))
        .toIso8601String()
        .split('T')[0]
        .replaceAll('-', '');
    int fechaActual = int.tryParse(fechaActualStr) ?? 0;

    yield* _firestore
        .collection(collectionName)
        .where('Movil', isEqualTo: movil)
        .where('VisibleEnApp', isEqualTo: 'S')
        .where('FchMsj', isEqualTo: fechaActual)
        .snapshots()
        .handleError((error) async {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
            error.message ?? 'Permission denied');
      } else {
        print('Error fetching mensajes: $error');
        await _logError('Firestore Error', error.toString());
      }
      bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        print('⚠ Pérdida de conectividad con Firestore.');
      }
    }).map((snapshot) {
      print('Fetched ${snapshot.docs.length} mensajes');
      snapshot.docs.forEach((doc) {
        print('Mensaje: ${doc.data()}');
      });
      return snapshot.docs;
    });
  }

  Future<List<DocumentSnapshot>> getUnreadMessages() async {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    int movil = int.tryParse(box.get('movil', defaultValue: '0')) ?? 0;

    String collectionName = 'Mensajes-$escenarioId';

    QuerySnapshot snapshot = await _firestore
        .collection(collectionName)
        .where('Movil', isEqualTo: movil)
        .where('VisibleEnApp', isEqualTo: 'S')
        .where('FchHoraLeido', isNull: true) // Ensure the field does not exist
        .get();

    return snapshot.docs;
  }

  Future<void> markMessageAsRead(String messageId) async {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    String collectionName = 'Mensajes-$escenarioId';

    await _firestore.collection(collectionName).doc(messageId).update({
      'FchHoraLeido': FieldValue.serverTimestamp(),
    }).catchError((error) async {
      print('Error marking message as read: $error');
      await _logError('Firestore Error', error.toString());
      bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        print('⚠ Pérdida de conectividad con Firestore.');
      }
    });
  }

  Future<void> updateMessageField(
      String messageId, Map<String, dynamic> fields) async {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    String collectionName = 'Mensajes-$escenarioId';

    await _firestore
        .collection(collectionName)
        .doc(messageId)
        .update(fields)
        .catchError((error) async {
      print('Error updating message field: $error');
      await _logError('Firestore Error', error.toString());
      bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        print('⚠ Pérdida de conectividad con Firestore.');
      }
    });
  }

  Stream<DocumentSnapshot?> getMovilStream() async* {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    String movil = box.get('movil', defaultValue: '0');
    String collectionName = 'Moviles-$escenarioId';
    String documentName = 'Moviles-$movil';

    yield* _firestore
        .collection(collectionName)
        .doc(documentName)
        .snapshots()
        .handleError((error) async {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
            error.message ?? 'Permission denied');
      } else {
        print('Error fetching movil: $error');
        await _logError('Firestore Error', error.toString());
      }
      bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        print('⚠ Pérdida de conectividad con Firestore.');
      }
    }).map((snapshot) {
      print('Fetched movil: ${snapshot.data()}');
      return snapshot;
    });
  }

  Future<void> updateMovilEstado(String movilId, int estado) async {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    String collectionName = 'Moviles-$escenarioId';

    await _firestore
        .collection(collectionName)
        .doc(movilId)
        .update({'EstadoNro': estado}).catchError((error) async {
      print('Error updating movil estado: $error');
      await _logError('Firestore Error', error.toString());
      bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        print('⚠ Pérdida de conectividad con Firestore.');
      }
    });
  }

  Stream<List<Map<String, dynamic>>> getSubEstadoMovilesStream() async* {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    String collectionName = 'SubEstadoMoviles-$escenarioId';

    yield* _firestore
        .collection(collectionName)
        .snapshots()
        .handleError((error) async {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
            error.message ?? 'Permission denied');
      } else {
        print('Error fetching subestado moviles: $error');
        await _logError('Firestore Error', error.toString());
      }
      bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        print('⚠ Pérdida de conectividad con Firestore.');
      }
    }).map((snapshot) {
      print('Fetched ${snapshot.docs.length} subestado moviles');
      return snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Add document ID to the data
        print('SubEstadoMovil: $data');
        return data;
      }).toList();
    });
  }

  Stream<List<Map<String, dynamic>>>
      getSubEstadoFinalizacionPedidosStream() async* {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    String collectionName = 'SubEstadoFinalizacionPedidos-$escenarioId';

    yield* _firestore
        .collection(collectionName)
        .orderBy('Orden')
        .snapshots()
        .handleError((error) async {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await _logFirestorePermissionError(
            error.message ?? 'Permission denied');
      } else {
        print('Error fetching subestado finalizacion pedidos: $error');
        await _logError('Firestore Error', error.toString());
      }
      bool isConnected = await checkFirestoreConnectivity();
      if (!isConnected) {
        // Notificar al usuario sobre la pérdida de conectividad
        print('⚠ Pérdida de conectividad con Firestore.');
      }
    }).map((snapshot) {
      print('Fetched ${snapshot.docs.length} subestado finalizacion pedidos');
      return snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Add document ID to the data
        print('SubEstadoFinalizacionPedido: $data');
        return data;
      }).toList();
    });
  }

  // Agrega más métodos para otras consultas según sea necesario

  static Future<void> _logError(String type, String message,
      [String? additionalInfo]) async {
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
