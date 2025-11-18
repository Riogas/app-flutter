import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 🔄 Servicio de Sincronización de Sesión
///
/// Mantiene sincronizados los datos críticos de sesión entre:
/// - Hive Box (sessionBox) → Usado por Flutter
/// - SharedPreferences → Usado por servicios nativos (GPS, FCM, etc.)
///
/// Datos sincronizados:
/// - movil (ID del móvil asignado)
/// - deviceId (ID único del dispositivo)
/// - usuario (username del usuario logueado)
/// - escenario (Dev/Prod)
///
/// Uso:
/// ```dart
/// // Al hacer login o cambiar datos de sesión:
/// await SessionSyncService.syncToSharedPrefs();
///
/// // Desde GPS Service Manager o servicios nativos:
/// final sessionData = await SessionSyncService.getSessionData();
/// print('Móvil: ${sessionData['movil']}');
/// ```
class SessionSyncService {
  static const String _tag = '[SESSION_SYNC]';

  /// 🔑 Keys de SharedPreferences (mismo formato que Hive)
  static const String _keyMovil = 'movil';
  static const String _keyDeviceId = 'deviceId';
  static const String _keyUsuario = 'username';
  static const String _keyEscenario = 'escenario';

  /// 📦 Sincronizar datos de Hive → SharedPreferences
  ///
  /// Lee los datos críticos de `sessionBox` (Hive) y los copia
  /// a SharedPreferences para que estén disponibles en código nativo.
  ///
  /// Llamar este método:
  /// - Después del login exitoso
  /// - Al cambiar de móvil
  /// - Al actualizar deviceId
  static Future<void> syncToSharedPrefs() async {
    try {
      print('$_tag 🔄 Iniciando sincronización Hive → SharedPreferences...');

      // 1. Abrir Hive sessionBox
      final sessionBox = await Hive.openBox('sessionBox');

      // 2. Leer datos de Hive
      final movil = sessionBox.get(_keyMovil)?.toString() ?? '';
      final deviceId = sessionBox.get(_keyDeviceId)?.toString() ?? '';
      final usuario = sessionBox.get(_keyUsuario)?.toString() ?? '';
      final escenario = sessionBox.get(_keyEscenario)?.toString() ?? '';

      print('$_tag 📖 Datos leídos de Hive:');
      print('$_tag   - movil: $movil');
      print('$_tag   - deviceId: $deviceId');
      print('$_tag   - usuario: $usuario');
      print('$_tag   - escenario: $escenario');

      // 3. Guardar en SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyMovil, movil);
      await prefs.setString(_keyDeviceId, deviceId);
      await prefs.setString(_keyUsuario, usuario);
      await prefs.setString(_keyEscenario, escenario);

      print('$_tag ✅ Sincronización completada exitosamente');
    } catch (e, stackTrace) {
      print('$_tag ❌ Error en sincronización: $e');
      print('$_tag 📚 StackTrace: $stackTrace');
    }
  }

  /// 📥 Obtener datos de sesión desde SharedPreferences
  ///
  /// Retorna un Map con los datos críticos de sesión.
  /// Útil para servicios que no tienen acceso a Hive (código nativo).
  ///
  /// Retorna:
  /// ```dart
  /// {
  ///   'movil': '336',
  ///   'deviceId': 'abc123',
  ///   'usuario': 'jgomez',
  ///   'escenario': '1'
  /// }
  /// ```
  static Future<Map<String, String>> getSessionData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final sessionData = {
        'movil': prefs.getString(_keyMovil) ?? '',
        'deviceId': prefs.getString(_keyDeviceId) ?? '',
        'usuario': prefs.getString(_keyUsuario) ?? '',
        'escenario': prefs.getString(_keyEscenario) ?? '',
      };

      print('$_tag 📋 Datos de sesión obtenidos:');
      print('$_tag   - movil: ${sessionData['movil']}');
      print('$_tag   - deviceId: ${sessionData['deviceId']}');
      print('$_tag   - usuario: ${sessionData['usuario']}');
      print('$_tag   - escenario: ${sessionData['escenario']}');

      return sessionData;
    } catch (e, stackTrace) {
      print('$_tag ❌ Error obteniendo datos de sesión: $e');
      print('$_tag 📚 StackTrace: $stackTrace');
      return {
        'movil': '',
        'deviceId': '',
        'usuario': '',
        'escenario': '',
      };
    }
  }

  /// 🧹 Limpiar datos de sesión (logout)
  ///
  /// Elimina los datos de sesión tanto de Hive como de SharedPreferences.
  /// Llamar este método al hacer logout.
  static Future<void> clearSessionData() async {
    try {
      print('$_tag 🧹 Limpiando datos de sesión...');

      // 1. Limpiar Hive
      final sessionBox = await Hive.openBox('sessionBox');
      await sessionBox.clear();

      // 2. Limpiar SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyMovil);
      await prefs.remove(_keyDeviceId);
      await prefs.remove(_keyUsuario);
      await prefs.remove(_keyEscenario);

      print('$_tag ✅ Datos de sesión limpiados');
    } catch (e, stackTrace) {
      print('$_tag ❌ Error limpiando datos de sesión: $e');
      print('$_tag 📚 StackTrace: $stackTrace');
    }
  }

  /// 🔍 Validar que los datos de sesión estén sincronizados
  ///
  /// Compara los datos de Hive con SharedPreferences.
  /// Útil para debugging y validar que la sincronización funciona.
  ///
  /// Retorna `true` si están sincronizados, `false` si no.
  static Future<bool> validateSync() async {
    try {
      print('$_tag 🔍 Validando sincronización...');

      // 1. Leer de Hive
      final sessionBox = await Hive.openBox('sessionBox');
      final hiveMovil = sessionBox.get(_keyMovil)?.toString() ?? '';
      final hiveDeviceId = sessionBox.get(_keyDeviceId)?.toString() ?? '';
      final hiveUsuario = sessionBox.get(_keyUsuario)?.toString() ?? '';
      final hiveEscenario = sessionBox.get(_keyEscenario)?.toString() ?? '';

      // 2. Leer de SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final prefsMovil = prefs.getString(_keyMovil) ?? '';
      final prefsDeviceId = prefs.getString(_keyDeviceId) ?? '';
      final prefsUsuario = prefs.getString(_keyUsuario) ?? '';
      final prefsEscenario = prefs.getString(_keyEscenario) ?? '';

      // 3. Comparar
      final movilSync = hiveMovil == prefsMovil;
      final deviceIdSync = hiveDeviceId == prefsDeviceId;
      final usuarioSync = hiveUsuario == prefsUsuario;
      final escenarioSync = hiveEscenario == prefsEscenario;

      print('$_tag 📊 Resultado de validación:');
      print(
          '$_tag   - movil: ${movilSync ? "✅" : "❌"} (Hive: $hiveMovil, Prefs: $prefsMovil)');
      print(
          '$_tag   - deviceId: ${deviceIdSync ? "✅" : "❌"} (Hive: $hiveDeviceId, Prefs: $prefsDeviceId)');
      print(
          '$_tag   - usuario: ${usuarioSync ? "✅" : "❌"} (Hive: $hiveUsuario, Prefs: $prefsUsuario)');
      print(
          '$_tag   - escenario: ${escenarioSync ? "✅" : "❌"} (Hive: $hiveEscenario, Prefs: $prefsEscenario)');

      final allSync = movilSync && deviceIdSync && usuarioSync && escenarioSync;
      print(
          '$_tag ${allSync ? "✅" : "⚠️"} Sincronización: ${allSync ? "OK" : "DESINCRONIZADO"}');

      return allSync;
    } catch (e, stackTrace) {
      print('$_tag ❌ Error validando sincronización: $e');
      print('$_tag 📚 StackTrace: $stackTrace');
      return false;
    }
  }
}
