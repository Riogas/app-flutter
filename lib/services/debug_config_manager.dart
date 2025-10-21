import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

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

  /// Inicia el listener de Firestore para el móvil especificado
  /// Debe llamarse después del login
  static Future<void> startListening(String movil) async {
    if (_isInitialized && _currentMovil == movil) {
      debugPrint('[$TAG] Ya está escuchando para móvil $movil');
      return;
    }

    // Detener listener anterior si existe
    await stopListening();

    _currentMovil = movil;
    _isInitialized = true;

    debugPrint('[$TAG] Iniciando listener para móvil $movil');

    try {
      // Escuchar cambios en el documento del móvil
      // Estructura: Moviles-1000 (colección) / Moviles-{movil} (documento)
      _debugConfigSubscription = FirebaseFirestore.instance
          .collection('Moviles-1000')
          .doc('Moviles-$movil')
          .snapshots()
          .listen(
        (snapshot) {
          _onDebugConfigChanged(snapshot);
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
  static void _onDebugConfigChanged(DocumentSnapshot snapshot) {
    if (!snapshot.exists) {
      debugPrint('[$TAG] Documento no existe para móvil $_currentMovil');
      return;
    }

    try {
      final data = snapshot.data() as Map<String, dynamic>?;
      if (data == null) {
        debugPrint('[$TAG] Data es null');
        return;
      }

      // Leer flag debugMode (por defecto false)
      final bool debugMode = data['debugMode'] ?? false;
      final String debugLevel = data['debugLevel'] ?? 'INFO';

      debugPrint(
          '[$TAG] 📡 Configuración recibida: debugMode=$debugMode, level=$debugLevel');

      // Comunicar cambio a la capa nativa (Kotlin)
      _notifyNativeLayer(debugMode, debugLevel);
    } catch (e) {
      debugPrint('[$TAG] ❌ Error procesando cambio de config: $e');
    }
  }

  /// Notifica a la capa nativa (Kotlin) sobre el cambio de configuración
  static Future<void> _notifyNativeLayer(bool enabled, String level) async {
    try {
      debugPrint('[$TAG] 📤 Enviando a Kotlin: enabled=$enabled, level=$level');

      final result = await _channel.invokeMethod('setDebugMode', {
        'enabled': enabled,
        'level': level,
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
  static Future<void> uploadLogsNow() async {
    try {
      debugPrint('[$TAG] 🚀 Enviando logs inmediatamente...');
      await _channel.invokeMethod('uploadLogsNow');
      debugPrint('[$TAG] ✅ Logs enviados exitosamente');
    } catch (e) {
      debugPrint('[$TAG] ⚠️ Error enviando logs: $e');
    }
  }

  /// Verifica si el manager está escuchando
  static bool get isListening =>
      _isInitialized && _debugConfigSubscription != null;

  /// Obtiene el móvil actual que se está escuchando
  static String? get currentMovil => _currentMovil;
}
