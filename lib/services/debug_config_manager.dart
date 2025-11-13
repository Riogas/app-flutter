import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Gestor de configuración de debug remoto
///
/// CARACTERÍSTICAS:
/// - Escucha cambios en Firestore para el flag debugMode del móvil
/// - Comunica cambios a la capa nativa (Kotlin) via MethodChannel
/// - Permite activar/desactivar logging remotamente sin reinstalar la app
/// - Auto-limpieza cuando el usuario cierra sesión
class DebugConfigManager {
  static const String TAG = 'DebugConfigManager';
  static const MethodChannel _channel = MethodChannel('debug_config');

  static StreamSubscription<DocumentSnapshot>? _debugConfigSubscription;
  static String? _currentMovil;
  static bool _isInitialized = false;
  static DateTime? _lastUploadTime; // Timestamp del último envío exitoso

  /// Inicia el listener de Firestore para el móvil especificado
  /// Debe llamarse después del login
  static Future<void> startListening(String movil) async {
    // 🆕 SIEMPRE reiniciar el listener (no confiar en flags de estado)
    debugPrint('[$TAG] 🔄 Reiniciando listener para móvil $movil (forzado)');

    // Detener listener anterior si existe
    await stopListening();

    _currentMovil = movil;
    _isInitialized = true;

    debugPrint('[$TAG] 🚀 Iniciando listener para móvil $movil');
    debugPrint('[$TAG]    - Colección: Moviles-1000');
    debugPrint('[$TAG]    - Documento: Moviles-$movil');

    try {
      // Escuchar cambios en el documento del móvil
      // Estructura: Moviles-1000 (colección) / Moviles-{movil} (documento)
      _debugConfigSubscription = FirebaseFirestore.instance
          .collection('Moviles-1000')
          .doc('Moviles-$movil')
          .snapshots()
          .listen(
        (snapshot) async {
          debugPrint('[$TAG] 🔔 Evento recibido desde Firestore');
          await _onDebugConfigChanged(snapshot);
        },
        onError: (error) {
          debugPrint('[$TAG] ❌ Error en stream de debug config: $error');
        },
      );

      debugPrint('[$TAG] ✅ Listener iniciado exitosamente');
    } catch (e) {
      debugPrint('[$TAG] ❌ Error iniciando listener: $e');
    }
  }

  /// Detiene el listener de Firestore
  /// Debe llamarse cuando el usuario cierra sesión
  static Future<void> stopListening() async {
    if (_debugConfigSubscription != null) {
      debugPrint('[$TAG] Deteniendo listener para móvil $_currentMovil');
      await _debugConfigSubscription!.cancel();
      _debugConfigSubscription = null;
      _currentMovil = null;
      _isInitialized = false;

      // Desactivar debug en la capa nativa al cerrar sesión
      try {
        await _channel.invokeMethod('setDebugMode', {'enabled': false});
      } catch (e) {
        debugPrint('[$TAG] Error desactivando debug mode: $e');
      }
    }
  }

  /// Procesa cambios en el documento de Firestore
  static Future<void> _onDebugConfigChanged(DocumentSnapshot snapshot) async {
    debugPrint('[$TAG] 📡 Procesando cambio de configuración...');
    debugPrint('[$TAG]    - Documento existe: ${snapshot.exists}');
    debugPrint('[$TAG]    - Móvil actual: $_currentMovil');
    debugPrint('[$TAG]    - Document ID: ${snapshot.id}');

    if (!snapshot.exists) {
      debugPrint('[$TAG] ❌ Documento NO existe para móvil $_currentMovil');
      debugPrint(
          '[$TAG]    - Ruta esperada: Moviles-1000/Moviles-$_currentMovil');
      debugPrint(
          '[$TAG]    - Verifica que el documento esté creado en Firestore');
      return;
    }

    try {
      final data = snapshot.data() as Map<String, dynamic>?;

      debugPrint('[$TAG] 📄 Data recibida:');
      debugPrint('[$TAG]    - Raw data: $data');

      if (data == null) {
        debugPrint('[$TAG] ⚠️ Data es null (documento existe pero vacío)');
        return;
      }

      // Leer flag debugMode (por defecto false) - controla envío de logs a n8n
      final debugModeRaw = data['debugMode'];
      final bool debugMode = debugModeRaw is bool ? debugModeRaw : false;
      final String debugLevel = data['debugLevel'] ?? 'INFO';

      // � Leer flag gpsN8n (por defecto false) - controla envío de coordenadas GPS a n8n cada 30s
      final gpsN8nRaw = data['gpsN8n'];
      final bool gpsN8nEnabled = gpsN8nRaw is bool ? gpsN8nRaw : false;

      // 🎥 Leer flag grabarPantalla (por defecto false) - controla grabación con LogRocket
      final grabarPantallaRaw = data['grabarPantalla'];
      final bool grabarPantallaEnabled =
          grabarPantallaRaw is bool ? grabarPantallaRaw : false;

      debugPrint('[$TAG] 🔍 Campos detectados:');
      debugPrint(
          '[$TAG]    - debugMode (raw): $debugModeRaw (tipo: ${debugModeRaw.runtimeType})');
      debugPrint('[$TAG]    - debugMode (parsed): $debugMode');
      debugPrint('[$TAG]    - debugLevel: $debugLevel');
      debugPrint(
          '[$TAG]    - gpsN8n (raw): $gpsN8nRaw (tipo: ${gpsN8nRaw.runtimeType})');
      debugPrint('[$TAG]    - gpsN8n (parsed): $gpsN8nEnabled');
      debugPrint(
          '[$TAG]    - grabarPantalla (raw): $grabarPantallaRaw (tipo: ${grabarPantallaRaw.runtimeType})');
      debugPrint('[$TAG]    - grabarPantalla (parsed): $grabarPantallaEnabled');

      if (debugModeRaw != null && debugModeRaw is! bool) {
        debugPrint('[$TAG] ⚠️ ADVERTENCIA: debugMode NO es boolean!');
        debugPrint('[$TAG]    - Tipo actual: ${debugModeRaw.runtimeType}');
        debugPrint('[$TAG]    - Valor: $debugModeRaw');
        debugPrint('[$TAG]    - Debe ser boolean true/false en Firestore');
      }

      if (gpsN8nRaw != null && gpsN8nRaw is! bool) {
        debugPrint('[$TAG] ⚠️ ADVERTENCIA: gpsN8n NO es boolean!');
        debugPrint('[$TAG]    - Tipo actual: ${gpsN8nRaw.runtimeType}');
        debugPrint('[$TAG]    - Valor: $gpsN8nRaw');
        debugPrint('[$TAG]    - Debe ser boolean true/false en Firestore');
      }

      if (grabarPantallaRaw != null && grabarPantallaRaw is! bool) {
        debugPrint('[$TAG] ⚠️ ADVERTENCIA: grabarPantalla NO es boolean!');
        debugPrint('[$TAG]    - Tipo actual: ${grabarPantallaRaw.runtimeType}');
        debugPrint('[$TAG]    - Valor: $grabarPantallaRaw');
        debugPrint('[$TAG]    - Debe ser boolean true/false en Firestore');
      }

      debugPrint('[$TAG] ✅ Configuración válida detectada');
      debugPrint(
          '[$TAG]    - debugMode=$debugMode, level=$debugLevel, gpsN8n=$gpsN8nEnabled, grabarPantalla=$grabarPantallaEnabled');

      // Guardar gpsN8n en sessionBox para acceso rápido
      final sessionBox = await Hive.openBox('sessionBox');
      await sessionBox.put('gpsN8nEnabled', gpsN8nEnabled);
      debugPrint('[$TAG] 💾 gpsN8n guardado en sessionBox: $gpsN8nEnabled');

      // 🎥 Guardar grabarPantalla en sessionBox
      await sessionBox.put('grabarPantallaEnabled', grabarPantallaEnabled);
      debugPrint(
          '[$TAG] 💾 grabarPantalla guardado en sessionBox: $grabarPantallaEnabled');

      // Comunicar cambio a la capa nativa (Kotlin)
      _notifyNativeLayer(debugMode, debugLevel, gpsN8nEnabled);
    } catch (e, stackTrace) {
      debugPrint('[$TAG] ❌ Error procesando cambio de config: $e');
      debugPrint('[$TAG]    - StackTrace: $stackTrace');
    }
  }

  /// Notifica a la capa nativa (Kotlin) sobre el cambio de configuración
  static Future<void> _notifyNativeLayer(
      bool enabled, String level, bool gpsN8nEnabled) async {
    try {
      debugPrint(
          '[$TAG] 📤 Enviando a Kotlin: enabled=$enabled, level=$level, gpsN8nEnabled=$gpsN8nEnabled');

      final result = await _channel.invokeMethod('setDebugMode', {
        'enabled': enabled,
        'level': level,
        'gpsN8nEnabled': gpsN8nEnabled,
      });

      debugPrint('[$TAG] ✅ Kotlin respondió: $result');

      if (enabled) {
        // Programar WorkManager para subir logs cada 10 minutos
        _scheduleLogUpload();
      } else {
        // Cancelar WorkManager si se desactiva el debug
        _cancelLogUpload();
      }
    } catch (e) {
      debugPrint('[$TAG] ❌ Error comunicando con Kotlin: $e');
    }
  }

  /// Programa el Worker para subir logs periódicamente
  static Future<void> _scheduleLogUpload() async {
    try {
      // Kotlin se encargará de programar el WorkManager
      debugPrint('[$TAG] 🔄 Solicitando programación de upload periódico');
      await _channel.invokeMethod('scheduleLogUpload');
    } catch (e) {
      debugPrint('[$TAG] ⚠️ Error programando upload: $e');
    }
  }

  /// Cancela el Worker de upload de logs
  static Future<void> _cancelLogUpload() async {
    try {
      debugPrint('[$TAG] 🛑 Cancelando upload periódico');
      await _channel.invokeMethod('cancelLogUpload');
    } catch (e) {
      debugPrint('[$TAG] ⚠️ Error cancelando upload: $e');
    }
  }

  /// Obtiene estadísticas del buffer de logs (para debugging)
  static Future<Map<String, dynamic>?> getDebugStats() async {
    try {
      final result = await _channel.invokeMethod('getDebugStats');
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      debugPrint('[$TAG] Error obteniendo stats: $e');
      return null;
    }
  }

  /// Fuerza el envío inmediato de logs al servidor (sin esperar los 10 minutos)
  /// Útil para enviar logs en momentos críticos (ej: después de DescargaLecturaPedidos o FinalizarPedido)
  ///
  /// **THROTTLE:** Solo envía si han pasado 10 minutos desde el último envío exitoso
  /// para evitar duplicados con el WorkManager automático de Kotlin.
  ///
  /// Parámetros:
  /// - [force]: Si es true, ignora el throttle y envía siempre (default: false)
  ///
  /// Retorna:
  /// - true: Logs enviados exitosamente
  /// - false: No se enviaron (throttle activo o error)
  static Future<bool> uploadLogsNow({bool force = false}) async {
    try {
      // Verificar throttle de 10 minutos (a menos que sea forzado)
      if (!force && _lastUploadTime != null) {
        final timeSinceLastUpload = DateTime.now().difference(_lastUploadTime!);
        final minutesSinceLastUpload = timeSinceLastUpload.inMinutes;

        if (minutesSinceLastUpload < 10) {
          debugPrint(
              '[$TAG] ⏳ Throttle activo: último envío hace $minutesSinceLastUpload min');
          debugPrint(
              '[$TAG]    - Faltan ${10 - minutesSinceLastUpload} min para próximo envío permitido');
          return false;
        }
      }

      debugPrint('[$TAG] 🚀 Enviando logs inmediatamente...');
      debugPrint('[$TAG]    - Forzado: $force');
      debugPrint(
          '[$TAG]    - Último envío: ${_lastUploadTime?.toString() ?? "nunca"}');

      await _channel.invokeMethod('uploadLogsNow');

      // Actualizar timestamp del último envío exitoso
      _lastUploadTime = DateTime.now();

      debugPrint('[$TAG] ✅ Logs enviados exitosamente');
      debugPrint(
          '[$TAG]    - Próximo envío permitido: ${DateTime.now().add(const Duration(minutes: 10))}');

      return true;
    } catch (e) {
      debugPrint('[$TAG] ⚠️ Error enviando logs: $e');
      return false;
    }
  }

  /// Limpia el timestamp del último envío (útil para testing o reset manual)
  static void resetUploadThrottle() {
    _lastUploadTime = null;
    debugPrint('[$TAG] 🔄 Throttle de upload reseteado');
  }

  /// Obtiene el tiempo restante hasta el próximo envío permitido (en minutos)
  /// Retorna null si no hay throttle activo
  static int? getMinutesUntilNextUpload() {
    if (_lastUploadTime == null) return null;

    final timeSinceLastUpload = DateTime.now().difference(_lastUploadTime!);
    final minutesRemaining = 10 - timeSinceLastUpload.inMinutes;

    return minutesRemaining > 0 ? minutesRemaining : 0;
  }

  /// Verifica si el manager está escuchando
  static bool get isListening =>
      _isInitialized && _debugConfigSubscription != null;

  /// Obtiene el móvil actual que se está escuchando
  static String? get currentMovil => _currentMovil;
}
