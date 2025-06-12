import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Config {
  // Credenciales de conexión a Firestore
  static String firestoreEmail = "";
  static String firestorePassword = "";

  // Agrega más variables globales según sea necesario
}

Future<void> registerOrReuseUser(String email, String password) async {
  print("🔐 Iniciando registerOrReuseUser()");
  print("📧 Email: $email");
  print("🔑 Password: $password");

  if (email.isEmpty || password.isEmpty) {
    print("❌ Email o password están vacíos. Abortando login/registro.");
    return;
  }

  try {
    print("🔎 Intentando login con FirebaseAuth...");
    UserCredential loginCredential = await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password);

    String uid = loginCredential.user!.uid;
    print("✅ Usuario ya existía. UID: $uid");

    Config.firestoreEmail = email;
    Config.firestorePassword = password;

    final docRef = FirebaseFirestore.instance
        .collection('Roles')
        .doc('editor')
        .collection('users')
        .doc(uid);

    print("🔍 Verificando acceso a Firestore...");
    try {
      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        print("📄 UID no encontrado. Creando nuevo documento en Firestore...");
        await docRef.set({
          'createdAt': FieldValue.serverTimestamp(),
          'email': email,
        });
        print("✅ UID registrado en Firestore.");
      } else {
        print("ℹ️ UID ya estaba registrado en Firestore.");
      }
    } catch (e) {
      print("🚫 Acceso denegado o error de permisos: $e");
      print("🔄 Reintentando con usuario con permisos...");

      // Desloguear usuario actual
      await FirebaseAuth.instance.signOut();

      // Login con usuario con permisos
      const String firestoreEmail = "firestoreappdelivery@riogas.com.uy";
      const String firestorePassword = "MoveIT1710!";

      UserCredential adminCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
              email: firestoreEmail, password: firestorePassword);
      print("✅ Login con usuario de permisos exitoso");

      // Crear el documento con el UID original
      final docRefAdmin = FirebaseFirestore.instance
          .collection('Roles')
          .doc('editor')
          .collection('users')
          .doc(uid);

      await docRefAdmin.set({
        'createdAt': FieldValue.serverTimestamp(),
        'email': email,
      });

      print("✅ UID guardado en Firestore en Roles/editor/users/$uid");

      // Desloguear admin
      await FirebaseAuth.instance.signOut();

      // Volver a loguear el usuario original
      print("🔁 Volviendo a loguear al usuario original...");
      loginCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      print("✅ Usuario relogueado correctamente.");
      Config.firestoreEmail = email;
      Config.firestorePassword = password;
    }
  } on FirebaseAuthException catch (e) {
    print("⚠️ Error al intentar login con FirebaseAuth: ${e.code}");

    if (e.code == 'invalid-credential') {
      print("👤 Usuario no encontrado. Intentando crear nuevo usuario...");
      try {
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        String uid = userCredential.user!.uid;
        print("✅ Usuario nuevo creado. UID: $uid");

        String firestoreEmail = "firestoreappdelivery@riogas.com.uy";
        String firestorePassword = "MoveIT1710!";

        UserCredential loginCredential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(
                email: firestoreEmail, password: firestorePassword);

        final docRef = FirebaseFirestore.instance
            .collection('Roles')
            .doc('editor')
            .collection('users')
            .doc(uid);

        await docRef.set({
          'createdAt': FieldValue.serverTimestamp(),
          'email': email,
        });

        print("✅ UID guardado en Firestore en Roles/editor/users/$uid");

        Config.firestoreEmail = email;
        Config.firestorePassword = password;

        // Cerrar sesión del usuario auxiliar
        await FirebaseAuth.instance.signOut();
      } catch (e2) {
        print("❌ Error al crear el usuario en Firebase: ${e2.toString()}");
      }
    } else if (e.code == 'wrong-password') {
      print("❌ Contraseña incorrecta para el usuario: $email");
    } else if (e.code == 'invalid-credential' || e.code == 'invalid-email') {
      print("❌ Credencial inválida o malformada para $email.");
    } else {
      print("❌ Error no manejado de FirebaseAuth: ${e.message} (${e.code})");
    }
  } catch (e) {
    print("❌ Error inesperado fuera de FirebaseAuthException: ${e.toString()}");
  }
}
