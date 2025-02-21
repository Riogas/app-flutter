import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

class ConstantsService {
  static Future<void> loadAndSaveConstants() async {
    QuerySnapshot querySnapshot =
        await FirebaseFirestore.instance.collection('Constantes-1000').get();
    var box = await Hive.openBox('sessionBox');

    for (var doc in querySnapshot.docs) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

      // 🔹 Convertir cualquier Timestamp en DateTime antes de guardar
      data.forEach((key, value) {
        if (value is Timestamp) {
          data[key] = value.toDate(); // Convierte a DateTime
        }
      });

      await box.put(doc.id, data);
    }
  }
}
