import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import Firebase Auth
import 'package:hive/hive.dart';
import '../utils/config.dart'; // Import config.dart for credentials

class ConstantsService {
  static Future<void> loadAndSaveConstants() async {
    // 🔐 Authenticate with Firebase using credentials from config.dart
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: Config.firestoreEmail,
        password: Config.firestorePassword,
      );
      print("✅ Firebase authentication successful.");
    } catch (e) {
      print("❌ Firebase authentication failed: $e");
      return; // Exit if authentication fails
    }

    var box = await Hive.openBox('sessionBox');
    String escenario = box.get('escenario', defaultValue: '1000');

    print("🔍 Escenario obtenido de sessionBox: $escenario");

    QuerySnapshot querySnapshot = await FirebaseFirestore.instance
        .collection('Constantes-$escenario')
        .get();
    var constantBox = await Hive.openBox('constantBox');

    print(
        "📥 Número de documentos obtenidos de Firestore: ${querySnapshot.docs.length}");

    for (var doc in querySnapshot.docs) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

      // 🔹 Convertir cualquier Timestamp en DateTime antes de guardar
      data.forEach((key, value) {
        if (value is Timestamp) {
          data[key] = value.toDate(); // Convierte a DateTime
        }
      });

      await constantBox.put(doc.id, data);
      print("✅ Documento guardado en constantBox con ID: ${doc.id}");
    }

    print("📦 Contenido de constantBox después de guardar las constantes:");
    constantBox.toMap().forEach((key, value) => print('$key: $value'));
  }
}
