import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../services/riogas_service.dart';
import '../services/session_service.dart';
import '../services/screen_recording_manager.dart'; // 🎥 Sistema de grabación
import '../utils/constantes.dart'; // 🆕 Para resetear ambiente

/// 🚪 LogoutService - Servicio centralizado para manejar el cierre de sesión
///
/// Puede ser llamado desde:
/// - Settings page (cierre manual del usuario)
/// - FCM remote logout (cierre remoto desde servidor)
///
/// Ejecuta el mismo flujo en ambos casos para mantener consistencia
class LogoutService {
  static const String TAG = 'LogoutService';

  /// Ejecuta el flujo completo de cierre de sesión
  ///
  /// [isRemoteLogout]: true si viene desde FCM, false si es manual
  /// [nombreUsuario], [idUsuario], [deviceId]: Opcionales, si no se proveen se obtienen de Hive
  ///
  /// IMPORTANTE: En logout remoto, NO se envían parámetros desde FCM,
  /// todo se obtiene de Hive (igual que force_gps_execution)
  static Future<bool> executeLogout({
    required bool isRemoteLogout,
    String? nombreUsuario,
    String? idUsuario,
    String? deviceId,
  }) async {
    try {
      print('$TAG 🚪 Iniciando logout (remote: $isRemoteLogout)');

      // Abrir boxes de Hive
      var sessionBox = await Hive.openBox('sessionBox');
      var constantBox = await Hive.openBox('constantBox');
      var mensajesBox = await Hive.openBox('mensajesBox');
      var failedRequestsBox = await Hive.openBox('failedRequestsBox');

      // Obtener datos de sesión SIEMPRE desde Hive (source of truth)
      final movil = sessionBox.get('movil') ?? "0";
      final escenario = sessionBox.get('escenario') ?? "0";
      final usuario = sessionBox.get('username') ?? "string";
      final idTerminal = sessionBox.get('deviceId') ?? "";
      final nombreUsu = sessionBox.get('NombreUsuario') ?? "";
      final usuarioId = sessionBox.get('username') ?? "";

      print('$TAG 📊 Datos de sesión (desde Hive):');
      print('$TAG    - Movil: $movil');
      print('$TAG    - Usuario: $usuario');
      print('$TAG    - DeviceId: $idTerminal');
      print(
          '$TAG    - Logout type: ${isRemoteLogout ? "Remoto (FCM)" : "Manual (Settings)"}');

      // Marcar bandera de logout
      sessionBox.put('firstLoginDone', true);
      sessionBox.put('logoutControlled', true);

      // 🎥 Detener grabación de pantalla si está activa
      try {
        await ScreenRecordingManager.stopRecording();
        print("$TAG 🛑 Grabación de pantalla detenida");
      } catch (e) {
        print('$TAG ⚠️ Error deteniendo grabación: $e');
      }

      // 1️⃣ Detener servicio de ubicación (solo si no es remote, porque FCM ya lo detuvo)
      if (!isRemoteLogout) {
        try {
          final platform = MethodChannel("background_service");
          await platform.invokeMethod("stopLocationService", {
            "movil": movil,
            "escenario": escenario,
            "usuario": usuario,
            "deviceId": idTerminal,
          });
          print("$TAG 🛑 Servicio de ubicación detenido");
        } catch (e) {
          print(
              '$TAG ⚠️ Error deteniendo servicio: $e (puede que FCM ya lo detuvo)');
        }
      } else {
        print(
            '$TAG ℹ️ Servicios ya detenidos por FCM, saltando detención manual');
      }

      // 2️⃣ Llamar al servicio RegistrarCierre
      try {
        await RioGasService.registrarCierre(
          int.tryParse(movil ?? '0') ?? 0,
          idTerminal,
          usuarioId,
          DateTime.now().toIso8601String(),
          isRemoteLogout ? 'Remoto' : 'Controlado',
        );
        print('$TAG ✅ RegistrarCierre ejecutado');
      } catch (e) {
        print('$TAG ❌ Error en RegistrarCierre: $e');
      }

      // 3️⃣ Manejar documentos de Firestore (sesiones)
      try {
        String escenarioId = sessionBox.get('escenario', defaultValue: '0');
        String movilId = sessionBox.get('movil', defaultValue: '0');
        String fechaActualStr = DateTime.now()
            .toUtc()
            .subtract(Duration(hours: 3))
            .toIso8601String()
            .split('T')[0]
            .replaceAll('-', '');

        DocumentReference fechaDocRef = FirebaseFirestore.instance
            .collection('Sesiones-$escenarioId')
            .doc(fechaActualStr);

        // Manejar documento del móvil
        DocumentReference movilActivoDocRef =
            fechaDocRef.collection('Movil-$movilId').doc('activo');

        DocumentSnapshot activeDocSnapshot = await movilActivoDocRef.get();
        if (activeDocSnapshot.exists) {
          var activeData = activeDocSnapshot.data() as Map<String, dynamic>;
          activeData['logout'] = isRemoteLogout ? 'Remoto' : 'Controlado';

          String horaActual =
              DateTime.now().toIso8601String().split('T')[1].split('.')[0];
          DocumentReference backupDocRef =
              fechaDocRef.collection('Movil-$movilId').doc(horaActual);
          await backupDocRef.set(activeData);
          await movilActivoDocRef.delete();

          print('$TAG ✅ Documento móvil actualizado en Firestore');
        }

        // Manejar documento del usuario
        DocumentReference usuarioActivoDocRef =
            fechaDocRef.collection('Usuario-$usuarioId').doc('activo');

        DocumentSnapshot usuarioDocSnapshot = await usuarioActivoDocRef.get();
        if (usuarioDocSnapshot.exists) {
          var usuarioData = usuarioDocSnapshot.data() as Map<String, dynamic>;
          usuarioData['logout'] = isRemoteLogout ? 'Remoto' : 'Controlado';

          String horaActual =
              DateTime.now().toIso8601String().split('T')[1].split('.')[0];
          DocumentReference usuarioBackupDocRef =
              fechaDocRef.collection('Usuario-$usuarioId').doc(horaActual);
          await usuarioBackupDocRef.set(usuarioData);
          await usuarioActivoDocRef.delete();

          print('$TAG ✅ Documento usuario actualizado en Firestore');
        }
      } catch (e) {
        print('$TAG ❌ Error manejando documentos Firestore: $e');
      }

      // 4️⃣ Llamar a SessionService
      try {
        SessionService sessionService = SessionService();

        await sessionService.saveSession(
          idUsuario: usuarioId,
          nomUsuario: nombreUsu,
          primeraUbicacion: LatLng(0, 0),
          versionApp: '1.0.0',
          tipoDeCierreDeSesion: isRemoteLogout ? 'remoteLogout' : 'logoutUser',
        );

        final cerrarSesionResult = await sessionService.cerrarSesion(
          idUsuario: usuarioId,
          tipoDeCierreDeSesion: isRemoteLogout ? 'remoteLogout' : 'logoutUser',
        );

        print('$TAG ✅ SessionService ejecutado: $cerrarSesionResult');
      } catch (e) {
        print('$TAG ❌ Error en SessionService: $e');
      }

      // 5️⃣ Limpiar todas las flags de servicios
      try {
        await RioGasService.clearAllServiceFlags();
        print('$TAG 🧹 Flags de servicios limpiadas');
      } catch (e) {
        print('$TAG ⚠️ Error limpiando flags de servicios: $e');
      }

      // 6️⃣ Limpieza COMPLETA y DEFENSIVA de Hive boxes, SharedPreferences y logs
      print('$TAG 🧹 Iniciando limpieza completa de datos...');

      // 🔹 PRESERVAR datos importantes para próximo login
      String? lastUsername;
      bool? huellaEnabled;
      try {
        if (Hive.isBoxOpen('usuarioBox')) {
          final usuarioBox = Hive.box('usuarioBox');
          lastUsername = usuarioBox.get('lastUsername');
          huellaEnabled = usuarioBox.get('huella');
          print('$TAG 💾 Datos preservados para próximo login:');
          print('$TAG    - lastUsername: $lastUsername');
          print('$TAG    - huella: $huellaEnabled');
        }
      } catch (e) {
        print('$TAG ⚠️ Error preservando datos de usuario: $e');
      }

      // 🔹 Eliminar Hive boxes de sesión (ya abiertos)
      try {
        await sessionBox.deleteFromDisk();
        await constantBox.deleteFromDisk();
        await mensajesBox.deleteFromDisk();
        await failedRequestsBox.deleteFromDisk();
        print(
            '$TAG ✅ Boxes principales eliminados (sessionBox, constantBox, mensajesBox, failedRequestsBox)');
      } catch (e) {
        print('$TAG ❌ Error eliminando boxes principales: $e');
      }

      // 🔹 Eliminar otros Hive boxes que puedan estar abiertos
      final boxesToDelete = [
        'pedidosBox',
        'conexionBox',
        'errorBox',
        'descargaLecturaPedidosBox',
        'OTPBOX',
        'authBox',
        'nativeLogsBox',
      ];

      for (final boxName in boxesToDelete) {
        try {
          if (Hive.isBoxOpen(boxName)) {
            final box = Hive.box(boxName);
            await box.deleteFromDisk();
            print('$TAG ✅ Box eliminado: $boxName');
          } else {
            // Intentar eliminar aunque no esté abierto
            await Hive.deleteBoxFromDisk(boxName);
            print('$TAG ✅ Box eliminado (no abierto): $boxName');
          }
        } catch (e) {
          print('$TAG ⚠️ No se pudo eliminar $boxName: $e (puede no existir)');
        }
      }

      // 🔹 RESTAURAR datos importantes en usuarioBox
      try {
        final usuarioBox = await Hive.openBox('usuarioBox');
        if (lastUsername != null) {
          await usuarioBox.put('lastUsername', lastUsername);
          print('$TAG 💾 lastUsername restaurado: $lastUsername');
        }
        if (huellaEnabled != null) {
          await usuarioBox.put('huella', huellaEnabled);
          print('$TAG 💾 huella restaurado: $huellaEnabled');
        }
      } catch (e) {
        print('$TAG ⚠️ Error restaurando datos de usuario: $e');
      }

      // 🔹 Limpiar SharedPreferences nativos (Android)
      try {
        final platform = MethodChannel('com.riogas.appmovil/shared_prefs');

        // Lista de SharedPreferences a limpiar
        final prefsToClean = [
          'config', // Contiene last_movil, last_escenario, service_disabled, etc.
          'daily_tracking', // Distancias GPS acumuladas
          'coords', // Última ubicación guardada
          'location_errors', // Errores de ubicación acumulados
          'gps_execution', // Contador de ejecuciones GPS
          'FlutterSharedPreferences', // Preferencias de Flutter (baseUrl, etc.)
        ];

        for (final prefsName in prefsToClean) {
          try {
            await platform.invokeMethod(
                'clearSharedPreferences', {'prefsName': prefsName});
            print('$TAG ✅ SharedPreferences limpiado: $prefsName');
          } catch (e) {
            print('$TAG ⚠️ No se pudo limpiar $prefsName: $e');
          }
        }
      } catch (e) {
        print('$TAG ⚠️ Error limpiando SharedPreferences: $e');
      }

      // 🔹 Limpiar archivos de logs nativos
      try {
        final platform = MethodChannel('com.riogas.appmovil/native_logs');
        await platform.invokeMethod('clearAllLogs');
        print('$TAG ✅ Logs nativos limpiados');
      } catch (e) {
        print('$TAG ⚠️ Error limpiando logs nativos: $e');
      }

      print('$TAG 🧹 Limpieza completa finalizada');

      // 🆕 Resetear ambiente a PRODUCCIÓN (por defecto)
      try {
        await AppEnvironment.resetToProduction();
        print('$TAG 🌍 Ambiente reseteado a PRODUCCIÓN');
      } catch (e) {
        print('$TAG ⚠️ Error reseteando ambiente: $e');
      }

      // 7️⃣ Cerrar la aplicación
      print('$TAG 🚪 Cerrando aplicación...');
      Future.microtask(() {
        exit(0);
      });

      return true;
    } catch (e) {
      print('$TAG ❌ Error crítico en logout: $e');
      return false;
    }
  }
}
