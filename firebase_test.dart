import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> main() async {
  // Inicializar Firebase
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: 'AIzaSyBM0Hn6fXIrD2r42q0avKD2gZ5kzqaxaUM',
      appId: '1:581291310412:android:9ab960ac4b55a1f71023e9',
      messagingSenderId: '581291310412',
      projectId: 'riogas-pedidos',
      databaseURL: 'https://riogas-pedidos-default-rtdb.firebaseio.com',
      storageBucket: 'riogas-pedidos.firebasestorage.app',
    ),
  );

  // Autenticar usuario
  try {
    UserCredential userCredential =
        await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: "firestoreWrite@riogas.com.uy",
      password: "!!Lecocq1013-",
    );
    print("User signed in: ${userCredential.user?.email}");
  } on FirebaseAuthException catch (e) {
    print("Error signing in: $e");
    return;
  }

  // Conectar con Firestore y leer documentos
  try {
    FirebaseFirestore firestore = FirebaseFirestore.instance;
    QuerySnapshot querySnapshot =
        await firestore.collection('Pedidos-1000').get();

    for (var doc in querySnapshot.docs) {
      print('Document ID: ${doc.id}');
      print('Document Data: ${doc.data()}');
    }
  } catch (e) {
    print("Error reading documents: $e");
  }
}
