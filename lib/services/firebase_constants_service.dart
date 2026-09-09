import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import Firebase Auth
import 'package:hive/hive.dart';
import '../utils/config.dart'; // Import config.dart for credentials

class ConstantsService {
  /// Las tres constantes que definen a qué servidor se pega la app:
  /// 600 + 601 arman producción, 611 es desarrollo.
  static const List<String> constantesDeUrl = ['600', '601', '611'];

  /// ¿Falta alguna de las constantes de URL en el cache local?
  ///
  /// Es la pregunta que importa al arrancar: el logout borra el `constantBox`
  /// del disco, y ese es exactamente el arranque en el que el `baseUrl` de
  /// producción se armaba con el valor por defecto. Se resuelve leyendo Hive,
  /// sin gastar una sola lectura de Firestore.
  static Future<bool> faltanConstantesDeUrl() async {
    try {
      final box = await Hive.openBox('constantBox');
      for (final id in constantesDeUrl) {
        final d = box.get(id);
        if (d == null || (d['Valor'] ?? '').toString().trim().isEmpty) {
          return true;
        }
      }
      return false;
    } catch (e) {
      print('⚠️ [CONSTANTES] No se pudo revisar el cache: $e');
      return true; // ante la duda, bajarlas
    }
  }

  /// Baja SOLO las tres constantes de URL: 3 documentos en vez de los 48 de
  /// la colección entera.
  ///
  /// Corre al arrancar, antes de armar ninguna URL y sin depender del login
  /// —se autentica sola contra Firebase—, pero únicamente cuando faltan. El
  /// refresco completo sigue haciéndose en el login.
  static Future<void> cargarConstantesDeUrl() async {
    // La sesión de Firebase SOBREVIVE al logout de la app (nadie hace
    // signOut), así que en el arranque que nos importa —el posterior a cerrar
    // sesión— ya hay usuario y alcanza con leer.
    //
    // Si no lo hay, se intenta con las credenciales de Config. Ojo: arrancan
    // VACÍAS (viven en `authBox` y las carga FirebaseService, más tarde), y
    // con strings vacíos el signIn tira "Given String is empty or null". Por
    // eso primero se cargan, y si aun así no están se sale prolijo: las
    // constantes van a llegar igual con el login.
    if (FirebaseAuth.instance.currentUser == null) {
      if (Config.firestoreEmail.isEmpty || Config.firestorePassword.isEmpty) {
        await Config.loadCredentials();
      }
      if (Config.firestoreEmail.isEmpty || Config.firestorePassword.isEmpty) {
        print('⚠️ [CONSTANTES] Sin sesión de Firebase ni credenciales: '
            'las constantes se bajan en el login');
        return;
      }
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: Config.firestoreEmail,
          password: Config.firestorePassword,
        );
      } catch (e) {
        print('❌ [CONSTANTES] No se pudo autenticar contra Firebase: $e');
        return;
      }
    } else {
      print('🔑 [CONSTANTES] Sesión de Firebase ya activa: '
          '${FirebaseAuth.instance.currentUser?.email}');
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('Constantes-1000')
          .where(FieldPath.documentId, whereIn: constantesDeUrl)
          .get();

      final box = await Hive.openBox('constantBox');
      for (final doc in snap.docs) {
        final data = Map<String, dynamic>.from(doc.data() as Map);
        data.forEach((k, v) {
          if (v is Timestamp) data[k] = v.toDate();
        });
        await box.put(doc.id, data);
        print('✅ [CONSTANTES] URL ${doc.id} = "${data['Valor']}"');
      }
    } catch (e) {
      print('❌ [CONSTANTES] No se pudieron bajar las de URL: $e');
    }
  }

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
    String escenario = box.get('escenario', defaultValue: '1000').toString();

    print("🔍 Escenario obtenido de sessionBox: $escenario");

    QuerySnapshot querySnapshot =
        await FirebaseFirestore.instance.collection('Constantes-1000').get();
    var constantBox = await Hive.openBox('constantBox');

    print(
      "📥 Número de documentos obtenidos de Firestore: ${querySnapshot.docs.length}",
    );

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

    // Guardar en Hive la cantidad de lecturas de la colección de constantes y actualizar el total
    try {
      var monitoreoBox = await Hive.openBox('Monitoreo');
      await monitoreoBox.put('ConstantesReads',
          querySnapshot.docs.length); // 1 lectura por documento

      // Sumar ConstantesReads al TotalReads (si ya existe, sumar; si no, crear)
      int totalReads = monitoreoBox.get('TotalReads', defaultValue: 0);
      totalReads += querySnapshot.docs.length;
      await monitoreoBox.put('TotalReads', totalReads);

      print(
          '✅ ConstantesReads guardado en Hive (Monitoreo): ${querySnapshot.docs.length}');
      print('✅ TotalReads actualizado en Hive (Monitoreo): $totalReads');
    } catch (e) {
      print('❌ Error guardando ConstantesReads en Hive: $e');
    }
  }
}
