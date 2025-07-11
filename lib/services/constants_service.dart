import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

class ConstantsService {
  /// Devuelve la cantidad de lecturas realizadas a la colección de constantes
  static Future<int> loadAndSaveConstants() async {
    int constantesReads = 0;
    try {
      await FirebaseFirestore.instance.collection('constantes').get();
      constantesReads = 1; // Si solo haces un get, cuenta como 1 lectura
      // Guardar en Hive la cantidad de lecturas
      try {
        var box = await Hive.openBox('Monitoreo');
        await box.put('ConstantesReads', constantesReads);
      } catch (e) {
        print('❌ Error guardando ConstantesReads en Hive: $e');
      }
    } catch (e) {
      print('❌ Error leyendo la colección de constantes: $e');
    }
    return constantesReads;
  }
}
