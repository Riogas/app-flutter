import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'logout_service.dart';

/// 🚨 RemoteLogoutListener
///
/// Este servicio escucha notificaciones de logout remoto desde el lado nativo (Kotlin).
/// Cuando FcmPushReceiver recibe el comando FCM "logout_user", envía un broadcast
/// que MainActivity captura y reenvía a Flutter via MethodChannel.
///
/// Flujo completo:
/// 1. FCM push notification "logout_user" → FcmPushReceiver.kt
/// 2. FcmPushReceiver detiene servicios, setea flags, envía broadcast
/// 3. MainActivity recibe broadcast, notifica a Flutter via MethodChannel
/// 4. RemoteLogoutListener recibe evento, ejecuta LogoutService.executeLogout()
/// 5. LogoutService completa los pasos de logout (Firestore, Hive, exit app)
class RemoteLogoutListener {
  static const _channel = MethodChannel('com.riogas.appmovil/remote_logout');
  static bool _isInitialized = false;

  /// Inicializa el listener del MethodChannel
  /// Debe ser llamado en main.dart después de WidgetsFlutterBinding.ensureInitialized()
  static Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint(
          '⚠️ [REMOTE_LOGOUT] Ya inicializado, ignorando segunda llamada');
      return;
    }

    try {
      debugPrint('🚨 [REMOTE_LOGOUT] Inicializando listener...');

      // Configurar handler para eventos desde Kotlin
      _channel.setMethodCallHandler(_handleMethodCall);

      _isInitialized = true;
      debugPrint('✅ [REMOTE_LOGOUT] Listener inicializado correctamente');
    } catch (e) {
      debugPrint('❌ [REMOTE_LOGOUT] Error inicializando listener: $e');
    }
  }

  /// Handler para eventos recibidos desde Kotlin
  ///
  /// NO recibe parámetros desde Kotlin, obtiene todo desde Hive
  /// (igual que force_gps_execution que solo envía la acción)
  static Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onRemoteLogout') {
      try {
        debugPrint('🚨 [REMOTE_LOGOUT] Evento recibido desde Kotlin');
        debugPrint('🚨 [REMOTE_LOGOUT] Obteniendo datos desde Hive...');

        // Ejecutar logout remoto via LogoutService
        // LogoutService obtendrá los datos (movil, escenario, usuario, deviceId) desde Hive
        debugPrint(
            '🚨 [REMOTE_LOGOUT] Ejecutando LogoutService.executeLogout()...');
        await LogoutService.executeLogout(isRemoteLogout: true);

        debugPrint('✅ [REMOTE_LOGOUT] Logout completado exitosamente');
      } catch (e, stackTrace) {
        debugPrint('❌ [REMOTE_LOGOUT] Error ejecutando logout: $e');
        debugPrint('   StackTrace: $stackTrace');
      }
    }
  }
}
