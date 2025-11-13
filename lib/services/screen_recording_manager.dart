import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:logrocket_flutter/logrocket_flutter.dart';

/// 🎥 Screen Recording Manager - Control de grabación de sesiones con LogRocket
///
/// CARACTERÍSTICAS:
/// - Inicia grabación al hacer login (si grabarPantalla=true en Firestore)
/// - Detiene grabación al cerrar sesión
/// - Control remoto via FCM (toggle on/off sin logout/login)
/// - Identifica sesiones con datos del usuario (movil, usuario, deviceId)
class ScreenRecordingManager {
  static const String TAG = 'ScreenRecordingManager';
  static bool _isRecording = false;

  /// Inicia la grabación de sesión (llamar después del login exitoso)
  ///
  /// [movil]: ID del móvil
  /// [usuario]: Cédula/username del usuario
  /// [deviceId]: ID único del dispositivo Android
  static Future<void> startRecording({
    required String movil,
    required String usuario,
    required String deviceId,
  }) async {
    debugPrint('[$TAG] 🚀🚀🚀 ENTRANDO A startRecording() - movil=$movil');
    try {
      debugPrint('[$TAG] 🔓 Abriendo sessionBox...');
      final sessionBox = await Hive.openBox('sessionBox');
      debugPrint('[$TAG] 📖 Leyendo grabarPantallaEnabled...');
      final grabarPantallaEnabled =
          sessionBox.get('grabarPantallaEnabled', defaultValue: false);
      debugPrint('[$TAG] 📖 Valor leído: $grabarPantallaEnabled');

      debugPrint('[$TAG] 🔍 Verificando si debe grabar...');
      debugPrint('[$TAG]    - Movil: $movil');
      debugPrint('[$TAG]    - Usuario: $usuario');
      debugPrint('[$TAG]    - DeviceId: $deviceId');
      debugPrint('[$TAG]    - grabarPantallaEnabled: $grabarPantallaEnabled');

      if (!grabarPantallaEnabled) {
        debugPrint('[$TAG] ⏸️ Grabación deshabilitada para móvil $movil');
        debugPrint(
            '[$TAG]    - Para habilitar: cambiar grabarPantalla=true en Firestore');
        return;
      }

      if (_isRecording) {
        debugPrint('[$TAG] ⚠️ Ya hay una grabación activa');
        return;
      }

      // Obtener datos adicionales de sesión
      final escenario = sessionBox.get('escenario', defaultValue: '0');
      final nombreUsuario =
          sessionBox.get('NombreUsuario', defaultValue: 'Desconocido');

      // 🔑 Identificar usuario en LogRocket
      // Formato correcto: LogRocket.identify('userID', { traits })
      // El App ID se configura automáticamente desde el paquete
      debugPrint('[$TAG] 🎥 Iniciando LogRocket con identificación...');
      debugPrint(
          '[$TAG]    - App ID: w2ree2/delivery-ammr6 (desde pubspec.yaml)');
      debugPrint('[$TAG]    - User ID: $movil');

      await LogRocket.identify(movil, {
        'name': nombreUsuario,
        'usuario': usuario,
        'deviceId': deviceId,
        'escenario': escenario,
        'movil': movil,
        'email': 'android-$deviceId@riogas.com.uy',
      });

      _isRecording = true;
      debugPrint('[$TAG] ✅ 🎥 Grabación iniciada exitosamente');
      debugPrint(
          '[$TAG]    - Usuario identificado: $nombreUsuario (Movil: $movil)');
      debugPrint(
          '[$TAG]    - La sesión estará disponible en LogRocket en ~30 segundos');
    } catch (e) {
      debugPrint('[$TAG] ❌ Error iniciando grabación: $e');
      debugPrint('[$TAG]    - Verifica la conexión a internet');
      debugPrint(
          '[$TAG]    - Verifica que LogRocket esté correctamente configurado');
    }
  }

  /// Detiene la grabación de sesión (llamar al cerrar sesión)
  static Future<void> stopRecording() async {
    if (!_isRecording) {
      debugPrint('[$TAG] ℹ️ No hay grabación activa para detener');
      return;
    }

    try {
      // LogRocket automáticamente sube la sesión al detener
      // No necesitas llamar a un método explícito, solo marcar como detenido

      _isRecording = false;
      debugPrint('[$TAG] 🛑 Grabación detenida');
      debugPrint(
          '[$TAG]    - La sesión grabada se subirá automáticamente a LogRocket');
      debugPrint('[$TAG]    - Disponible en: https://app.logrocket.com');
    } catch (e) {
      debugPrint('[$TAG] ❌ Error deteniendo grabación: $e');
    }
  }

  /// Toggle remoto via FCM (encender/apagar sin logout/login)
  ///
  /// [enable]: true para iniciar, false para detener
  static Future<void> toggleRecording(bool enable) async {
    try {
      debugPrint(
          '[$TAG] 🔄 Toggle remoto recibido: ${enable ? "ENCENDER" : "APAGAR"}');

      final sessionBox = await Hive.openBox('sessionBox');

      // Guardar nuevo estado en sessionBox
      await sessionBox.put('grabarPantallaEnabled', enable);
      debugPrint('[$TAG] 💾 grabarPantallaEnabled actualizado a: $enable');

      if (enable && !_isRecording) {
        // Encender grabación
        final movil = sessionBox.get('movil', defaultValue: '0');
        final usuario = sessionBox.get('username', defaultValue: 'unknown');
        final deviceId = sessionBox.get('deviceId', defaultValue: '');

        debugPrint('[$TAG] ▶️ Iniciando grabación por comando remoto...');
        await startRecording(
          movil: movil,
          usuario: usuario,
          deviceId: deviceId,
        );
      } else if (!enable && _isRecording) {
        // Apagar grabación
        debugPrint('[$TAG] ⏹️ Deteniendo grabación por comando remoto...');
        await stopRecording();
      } else {
        debugPrint(
            '[$TAG] ℹ️ Estado ya coincide: ${enable ? "grabando" : "detenido"}');
      }
    } catch (e) {
      debugPrint('[$TAG] ❌ Error en toggle remoto: $e');
    }
  }

  /// Verifica si la grabación está activa
  static bool isRecording() => _isRecording;
}
