import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';

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
    }
  }

  Stream<void> getSesionesStream() async* {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    String movil = box.get('movil', defaultValue: '0');
    String collectionName = 'Sesiones-$escenarioId';

    // Obtener la fecha actual en formato yyyymmdd
    String fechaActual =
        DateTime.now().toIso8601String().split('T')[0].replaceAll('-', '');

    // Nombre del documento de la fecha actual
    String fechaDocName = fechaActual;

    // Nombre de la colección del móvil
    String movilCollectionName = 'Movil-$movil';

    // Nombre del documento "activo"
    String activoDocName = 'activo';

    // Obtener el documento "activo" dentro de la colección del móvil
    DocumentReference activoDocRef = _firestore
        .collection(collectionName)
        .doc(fechaDocName)
        .collection(movilCollectionName)
        .doc(activoDocName);

    // Escuchar cambios en el documento "activo"
    yield* activoDocRef.snapshots().handleError((error) {
      print('Error fetching sesiones: $error');
    }).map((snapshot) async {
      if (snapshot.exists) {
        var data = snapshot.data() as Map<String, dynamic>;
        print('Sesion activa encontrada: $data');

        // Guardar o actualizar los valores en sessionBox
        await box.put('movil', data['movil']);
        await box.put('NombreUsuario', data['nomUsuario']);
        await box.put('username', data['idUsuario']);
        await box.put('deviceId', data['idTerminal']);

        print('Datos guardados en sessionBox:');
        print('movil: ${data['movil']}');
        print('NombreUsuario: ${data['nomUsuario']}');
        print('username: ${data['idUsuario']}');
        print('deviceId: ${data['idTerminal']}');
      } else {
        print('No se encontró el documento "activo".');
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

    //print('Fetching pedidos from collection: $collectionName');
    //print('Filters - Movil: $movil, FchPara: $fechaActual');

    yield* _firestore
        .collection(collectionName)
        .where('Movil', isEqualTo: movil)
        .where('FchPara', isEqualTo: fechaActual)
        .where('VisibleEnApp', isEqualTo: 'S')
        .where('EstadoNro', isEqualTo: 1)
        .orderBy('FchHoraPara',
            descending: false) // Ordenar por FchHoraPara en forma ascendente
        .snapshots()
        .handleError((error) {
      //print('Error fetching pedidos: $error');
    }).map((snapshot) {
      //print('Fetched ${snapshot.docs.length} pedidos');
      snapshot.docs.forEach((doc) {
        //print('Pedido: ${doc.data()}');
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

    //print('Fetching pedidos cumplidos from collection: $collectionName');
    //print('Filters - Movil: $movil, FchPara: $fechaActual');

    yield* _firestore
        .collection(collectionName)
        .where('Movil', isEqualTo: movil)
        .where('FchPara', isEqualTo: fechaActual)
        .where('VisibleEnApp', isEqualTo: 'S')
        .where('EstadoNro', isEqualTo: 2)
        .orderBy('FchHoraPara',
            descending: false) // Ordenar por FchHoraPara en forma ascendente
        .snapshots()
        .handleError((error) {
      //print('Error fetching pedidos cumplidos: $error');
    }).map((snapshot) {
      //print('Fetched ${snapshot.docs.length} pedidos cumplidos');
      snapshot.docs.forEach((doc) {
        //print('Pedido cumplido: ${doc.data()}');
      });
      return snapshot.docs;
    });
  }

  Stream<List<DocumentSnapshot>> getConstantesStream() async* {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    String collectionName = 'Constantes-$escenarioId';

    //print('Fetching constantes from collection: $collectionName');
    yield* _firestore
        .collection(collectionName)
        .snapshots()
        .handleError((error) {
      //print('Error fetching constantes: $error');
    }).map((snapshot) {
      //print('Fetched ${snapshot.docs.length} constantes');
      snapshot.docs.forEach((doc) {
        //print('Constante: ${doc.data()}');
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

    //print('Fetching mensajes from collection: $collectionName');
    //print('Filters - Movil: $movil, FchMsj: $fechaActual');

    yield* _firestore
        .collection(collectionName)
        .where('Movil', isEqualTo: movil)
        .where('VisibleEnApp', isEqualTo: 'S')
        .where('FchMsj', isEqualTo: fechaActual)
        .snapshots()
        .handleError((error) {
      //print('Error fetching mensajes: $error');
    }).map((snapshot) {
      //print('Fetched ${snapshot.docs.length} mensajes');
      snapshot.docs.forEach((doc) {
        //print('Mensaje: ${doc.data()}');
      });
      return snapshot.docs;
    });
  }

  Stream<List<DocumentSnapshot>> getMovilesStream() async* {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    String collectionName = 'Moviles-$escenarioId';

    //print('Fetching moviles from collection: $collectionName');
    yield* _firestore
        .collection(collectionName)
        .snapshots()
        .handleError((error) {
      //print('Error fetching moviles: $error');
    }).map((snapshot) {
      //print('Fetched ${snapshot.docs.length} moviles');
      snapshot.docs.forEach((doc) {
        //print('Movil: ${doc.data()}');
      });
      return snapshot.docs;
    });
  }

  // Agrega más métodos para otras consultas según sea necesario
}
