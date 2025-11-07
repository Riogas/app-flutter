import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive/hive.dart';
import 'riogas_service.dart';

/// 🔑 FCM Token Manager
///
/// Sistema automático de gestión de tokens FCM que:
/// - Detecta cuando Firebase invalida/rota el token
/// - Regenera tokens automáticamente
/// - Sincroniza con el backend de RioGas
/// - Mantiene persistencia local del token
class FCMTokenManager {
  static const String _boxName = 'fcmTokenBox';
  static const String _tokenKey = 'currentFCMToken';
  static const String _lastUpdateKey = 'lastTokenUpdate';

  /// Inicializa el sistema de gestión de tokens FCM
  ///
  /// Debe llamarse en el main() después de Firebase.initializeApp()
  static Future<void> initialize() async {
    print('🔑 [FCM_TOKEN_MANAGER] Inicializando...');

    try {
      // 1. Abrir box de persistencia
      final box = await Hive.openBox(_boxName);

      // 2. Obtener token actual de Firebase
      final currentToken = await FirebaseMessaging.instance.getToken();

      if (currentToken == null) {
        print('❌ [FCM_TOKEN_MANAGER] No se pudo obtener token FCM');
        return;
      }

      print(
          '📲 [FCM_TOKEN_MANAGER] Token FCM actual: ${currentToken.substring(0, 20)}...');

      // 3. Comparar con el token guardado
      final savedToken = box.get(_tokenKey);

      if (savedToken != currentToken) {
        print('🔄 [FCM_TOKEN_MANAGER] Token cambió. Actualizando...');
        await _updateToken(currentToken);
      } else {
        print('✅ [FCM_TOKEN_MANAGER] Token válido y actualizado');
      }

      // 4. Configurar listener para renovación automática
      _setupTokenRefreshListener();

      print('✅ [FCM_TOKEN_MANAGER] Sistema inicializado correctamente');
    } catch (e, stackTrace) {
      print('❌ [FCM_TOKEN_MANAGER] Error inicializando: $e');
      print('📚 StackTrace: $stackTrace');
    }
  }

  /// Configura el listener que detecta cuando Firebase rota el token
  static void _setupTokenRefreshListener() {
    print('👂 [FCM_TOKEN_MANAGER] Configurando listener de renovación...');

    FirebaseMessaging.instance.onTokenRefresh.listen(
      (newToken) async {
        print('🔄 [FCM_TOKEN_MANAGER] ¡Token renovado por Firebase!');
        print(
            '📲 [FCM_TOKEN_MANAGER] Nuevo token: ${newToken.substring(0, 20)}...');

        await _updateToken(newToken);
      },
      onError: (error) {
        print('❌ [FCM_TOKEN_MANAGER] Error en listener de renovación: $error');
      },
    );

    print('✅ [FCM_TOKEN_MANAGER] Listener configurado');
  }

  /// Actualiza el token tanto localmente como en el backend
  static Future<void> _updateToken(String newToken) async {
    try {
      print('💾 [FCM_TOKEN_MANAGER] Guardando token localmente...');

      // Guardar en Hive
      final box = await Hive.openBox(_boxName);
      await box.put(_tokenKey, newToken);
      await box.put(_lastUpdateKey, DateTime.now().toIso8601String());

      print('✅ [FCM_TOKEN_MANAGER] Token guardado en Hive');

      // Sincronizar con backend
      await _syncTokenWithBackend(newToken);
    } catch (e, stackTrace) {
      print('❌ [FCM_TOKEN_MANAGER] Error actualizando token: $e');
      print('📚 StackTrace: $stackTrace');
    }
  }

  /// Sincroniza el token con el backend de RioGas
  static Future<void> _syncTokenWithBackend(String token) async {
    try {
      print('🌐 [FCM_TOKEN_MANAGER] Sincronizando token con backend...');

      // Verificar si hay sesión activa
      final sessionBox = await Hive.openBox('sessionBox');
      final deviceId = sessionBox.get('deviceId');

      if (deviceId == null) {
        print(
            '⚠️ [FCM_TOKEN_MANAGER] No hay deviceId. Token se sincronizará en próximo login.');
        return;
      }

      // Llamar al servicio de actualización de token
      final response = await RioGasService.actualizarTokenFCM(
        deviceId: deviceId.toString(),
        token: token,
      );

      if (response != null && response['OK'] == 0) {
        print(
            '✅ [FCM_TOKEN_MANAGER] Token sincronizado con backend exitosamente');
      } else {
        print(
            '⚠️ [FCM_TOKEN_MANAGER] Backend respondió: ${response?['message'] ?? 'Sin mensaje'}');
      }
    } catch (e, stackTrace) {
      print('❌ [FCM_TOKEN_MANAGER] Error sincronizando con backend: $e');
      print('📚 StackTrace: $stackTrace');
    }
  }

  /// Obtiene el token FCM actual (desde cache o genera uno nuevo)
  ///
  /// Uso:
  /// ```dart
  /// String? token = await FCMTokenManager.getCurrentToken();
  /// ```
  static Future<String?> getCurrentToken() async {
    try {
      final box = await Hive.openBox(_boxName);
      final savedToken = box.get(_tokenKey);

      // Obtener token fresco de Firebase
      final freshToken = await FirebaseMessaging.instance.getToken();

      // Si cambió, actualizar
      if (freshToken != null && freshToken != savedToken) {
        print('🔄 [FCM_TOKEN_MANAGER] Token cambió durante getCurrentToken()');
        await _updateToken(freshToken);
        return freshToken;
      }

      return savedToken ?? freshToken;
    } catch (e) {
      print('❌ [FCM_TOKEN_MANAGER] Error obteniendo token: $e');
      return null;
    }
  }

  /// Fuerza la regeneración del token FCM
  ///
  /// Útil para testing o cuando se detecta que el token no funciona
  static Future<String?> forceTokenRefresh() async {
    try {
      print('🔄 [FCM_TOKEN_MANAGER] Forzando renovación de token...');

      // Eliminar el token antiguo de Firebase
      await FirebaseMessaging.instance.deleteToken();
      print('🗑️ [FCM_TOKEN_MANAGER] Token antiguo eliminado');

      // Esperar un momento
      await Future.delayed(Duration(seconds: 1));

      // Obtener nuevo token
      final newToken = await FirebaseMessaging.instance.getToken();

      if (newToken != null) {
        print(
            '✅ [FCM_TOKEN_MANAGER] Nuevo token generado: ${newToken.substring(0, 20)}...');
        await _updateToken(newToken);
        return newToken;
      } else {
        print('❌ [FCM_TOKEN_MANAGER] No se pudo generar nuevo token');
        return null;
      }
    } catch (e, stackTrace) {
      print('❌ [FCM_TOKEN_MANAGER] Error forzando renovación: $e');
      print('📚 StackTrace: $stackTrace');
      return null;
    }
  }

  /// Valida si el token actual sigue siendo válido
  ///
  /// Retorna true si hay un token guardado y coincide con Firebase
  static Future<bool> isTokenValid() async {
    try {
      final box = await Hive.openBox(_boxName);
      final savedToken = box.get(_tokenKey);
      final currentToken = await FirebaseMessaging.instance.getToken();

      final isValid = savedToken != null &&
          currentToken != null &&
          savedToken == currentToken;

      if (isValid) {
        print('✅ [FCM_TOKEN_MANAGER] Token válido');
      } else {
        print('⚠️ [FCM_TOKEN_MANAGER] Token inválido o desincronizado');
      }

      return isValid;
    } catch (e) {
      print('❌ [FCM_TOKEN_MANAGER] Error validando token: $e');
      return false;
    }
  }

  /// Obtiene información del estado del token
  static Future<Map<String, dynamic>> getTokenInfo() async {
    try {
      final box = await Hive.openBox(_boxName);
      final savedToken = box.get(_tokenKey);
      final lastUpdate = box.get(_lastUpdateKey);
      final currentToken = await FirebaseMessaging.instance.getToken();

      return {
        'savedToken': savedToken?.substring(0, 20) ?? 'No guardado',
        'currentToken': currentToken?.substring(0, 20) ?? 'No disponible',
        'isValid': savedToken == currentToken,
        'lastUpdate': lastUpdate ?? 'Nunca',
        'fullSavedToken': savedToken,
        'fullCurrentToken': currentToken,
      };
    } catch (e) {
      return {
        'error': e.toString(),
      };
    }
  }
}
