import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

class ConstantsService {
  static Future<void> loadAndSaveConstants() async {
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
