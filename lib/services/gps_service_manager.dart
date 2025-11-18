import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_sync_service.dart'; // 🔄 Importar servicio de sincronización

/// 🛡️ Gestor Centralizado de Inicio del Servicio GPS
///
/// Responsabilidades:
/// - Evitar inicios duplicados del servicio
/// - Implementar rate limiting para prevenir death loops
/// - Detectar y pausar ante comportamiento anormal (circuit breaker)
/// - Coordinar inicios desde múltiples fuentes (WorkManager, FCM, manual)
///
/// Uso:
/// ```dart
/// final canStart = await GpsServiceManager.requestGpsStart(source: 'fcm_push');
/// if (canStart) {
///   // Iniciar servicio
/// }
/// ```
class GpsServiceManager {
  static const String _tag = '[GPS_SERVICE_MANAGER]';
  static const MethodChannel _channel = MethodChannel('background_service');

  // 🔒 Singleton
  static final GpsServiceManager _instance = GpsServiceManager._internal();
  factory GpsServiceManager() => _instance;
  GpsServiceManager._internal();

  // � Debug Mode
  static bool _debugMode = false;

  // �📊 Estado del servicio
  static bool _isServiceRunning = false;
  static DateTime? _lastStartTime;
  static String? _lastStartSource;

  // 🚨 Circuit Breaker
  static int _startAttemptsInWindow = 0;
  static DateTime? _windowStartTime;
  static bool _circuitBreakerOpen = false;
  static DateTime? _circuitBreakerOpenedAt;

  // ⚙️ Configuración
  static const Duration _minTimeBetweenStarts =
      Duration(seconds: 5); // Mínimo 5 seg entre inicios
  static const Duration _circuitBreakerWindow =
      Duration(minutes: 2); // Ventana de 2 min
  static const int _maxStartsInWindow = 10; // Máximo 10 inicios en 2 min
  static const Duration _circuitBreakerCooldown =
      Duration(minutes: 5); // Pausa de 5 min si se abre

  /// 🔍 Verificar si el servicio GPS está corriendo
  ///
  /// Consulta al código nativo (Android) para confirmar el estado real del servicio.
  static Future<bool> isGpsServiceRunning() async {
    try {
      final bool isRunning =
          await _channel.invokeMethod('isGpsServiceRunning') ?? false;
      _isServiceRunning = isRunning;
      _debugLog(
          '🔍 Estado del servicio GPS: ${isRunning ? "CORRIENDO" : "DETENIDO"}');
      return isRunning;
    } catch (e) {
      _debugLog('❌ Error verificando estado del servicio: $e');
      return _isServiceRunning; // Fallback al estado en memoria
    }
  }

  /// 🛑 Detener TODOS los procesos GPS activos
  ///
  /// Usado por force_gps para limpiar duplicados antes de iniciar uno nuevo.
  /// Llama al método nativo que mata TODOS los procesos del servicio GPS.
  static Future<bool> forceStopAllGpsProcesses() async {
    try {
      // 📋 Recuperar datos de sesión ANTES de detener
      final sessionData = await SessionSyncService.getSessionData();
      _debugLog('🛑 Deteniendo TODOS los procesos GPS activos...');
      _debugLog('📋 Datos de sesión recuperados:');
      _debugLog('   - Móvil: ${sessionData['movil']}');
      _debugLog('   - DeviceID: ${sessionData['deviceId']}');
      _debugLog('   - Usuario: ${sessionData['usuario']}');
      _debugLog('   - Escenario: ${sessionData['escenario']}');

      final bool stopped =
          await _channel.invokeMethod('forceStopGpsService') ?? false;
      if (stopped) {
        _isServiceRunning = false;
        _debugLog('✅ Procesos GPS detenidos exitosamente');
        _debugLog('✅ Datos de sesión preservados para reinicio');
      } else {
        _debugLog('⚠️ No se pudieron detener todos los procesos GPS');
      }
      return stopped;
    } catch (e) {
      _debugLog('❌ Error deteniendo procesos GPS: $e');
      return false;
    }
  }

  /// 📋 Obtener datos de sesión actual
  ///
  /// Recupera deviceId, movilId, usuario y escenario desde SharedPreferences.
  /// Estos datos están sincronizados desde Hive al hacer login.
  ///
  /// Retorna un Map con los datos de sesión:
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
      final sessionData = await SessionSyncService.getSessionData();
      _debugLog('📋 Datos de sesión obtenidos correctamente');
      return sessionData;
    } catch (e) {
      _debugLog('❌ Error obteniendo datos de sesión: $e');
      return {
        'movil': '',
        'deviceId': '',
        'usuario': '',
        'escenario': '',
      };
    }
  }

  /// 🚦 Solicitar inicio del servicio GPS
  ///
  /// Retorna `true` si el inicio está permitido, `false` si debe bloquearse.
  ///
  /// [source] Identificador de la fuente que solicita el inicio
  /// (ej: 'workmanager', 'fcm_push', 'fcm_force', 'alarm_manager', 'manual')
  ///
  /// [force] Si es true, detiene TODOS los procesos GPS activos y luego inicia uno nuevo
  /// (solo para comandos FCM force_gps_execution)
  static Future<bool> requestGpsStart({
    required String source,
    bool force = false,
  }) async {
    _debugLog(
        '📥 Solicitud de inicio recibida (source: $source, force: $force)');

    // 🔴 FORCE GPS: Detener TODOS los procesos activos antes de continuar
    if (force) {
      _debugLog(
          '🛑 Modo FORCE activado - Deteniendo todos los procesos GPS duplicados');
      final stopped = await forceStopAllGpsProcesses();
      if (stopped) {
        _debugLog(
            '✅ Procesos duplicados eliminados - Preparado para inicio limpio');
      } else {
        _debugLog(
            '⚠️ No se pudieron detener todos los procesos - Continuando de todas formas');
      }
      // Esperar 1 segundo para asegurar que los procesos terminaron
      await Future.delayed(Duration(seconds: 1));
    }

    // 1️⃣ Verificar si el circuit breaker está abierto
    if (_circuitBreakerOpen) {
      final timeSinceOpen = DateTime.now().difference(_circuitBreakerOpenedAt!);
      if (timeSinceOpen < _circuitBreakerCooldown) {
        final remaining = _circuitBreakerCooldown - timeSinceOpen;
        _debugLog(
            '🚨 CIRCUIT BREAKER ABIERTO - Pausado por ${remaining.inMinutes} min más');
        _debugLog(
            'ℹ️ Razón: Detectado loop infinito (${_startAttemptsInWindow} inicios en ${_circuitBreakerWindow.inMinutes} min)');

        // Reportar a sistema de logs
        await _reportCircuitBreakerEvent(source);

        // ⚠️ IMPORTANTE: Force GPS TAMBIÉN respeta circuit breaker
        // Si hay un loop detectado, incluso force_gps debe esperar
        return false; // ❌ BLOQUEADO
      } else {
        // Cooldown completado, cerrar circuit breaker
        _debugLog('✅ Circuit breaker cerrado - Reanudando operación normal');
        _circuitBreakerOpen = false;
        _circuitBreakerOpenedAt = null;
        _resetCircuitBreakerCounters();
      }
    }

    // 2️⃣ Verificar estado actual del servicio
    final isRunning = await isGpsServiceRunning();
    if (isRunning && !force) {
      _debugLog(
          '⏭️ Servicio GPS ya está corriendo - Inicio omitido (source: $source)');
      return false; // ❌ NO INICIAR (ya está corriendo)
    }

    // 3️⃣ Rate Limiting: Verificar tiempo desde último inicio
    if (_lastStartTime != null) {
      final timeSinceLastStart = DateTime.now().difference(_lastStartTime!);
      if (timeSinceLastStart < _minTimeBetweenStarts) {
        final remaining = _minTimeBetweenStarts - timeSinceLastStart;
        _debugLog(
            '⏱️ Rate limit activo - Último inicio hace ${timeSinceLastStart.inSeconds}s');
        _debugLog('⏭️ Esperar ${remaining.inSeconds}s más (source: $source)');
        return false; // ❌ RATE LIMITED
      }
    }

    // 4️⃣ Circuit Breaker: Verificar si hay demasiados inicios en ventana de tiempo
    _updateCircuitBreakerCounters();
    if (_startAttemptsInWindow >= _maxStartsInWindow) {
      _debugLog('🚨 ABRIENDO CIRCUIT BREAKER');
      _debugLog(
          '⚠️ Detectados ${_startAttemptsInWindow} inicios en ${_circuitBreakerWindow.inMinutes} min');
      _debugLog(
          '🔴 Pausando inicios GPS por ${_circuitBreakerCooldown.inMinutes} min');

      _circuitBreakerOpen = true;
      _circuitBreakerOpenedAt = DateTime.now();

      // Reportar a sistema de logs y backend
      await _reportCircuitBreakerEvent(source);

      return false; // ❌ BLOQUEADO POR CIRCUIT BREAKER
    }

    // 5️⃣ ✅ PERMITIR INICIO
    _debugLog('✅ Inicio GPS PERMITIDO (source: $source)');

    // Actualizar estado
    _lastStartTime = DateTime.now();
    _lastStartSource = source;
    _startAttemptsInWindow++;
    _isServiceRunning = true;

    // Guardar métricas
    await _saveStartMetrics(source);

    return true; // ✅ PERMITIDO
  }

  /// 📊 Actualizar contadores del circuit breaker
  static void _updateCircuitBreakerCounters() {
    final now = DateTime.now();

    // Iniciar nueva ventana si no existe
    if (_windowStartTime == null) {
      _windowStartTime = now;
      _startAttemptsInWindow = 0;
      return;
    }

    // Verificar si la ventana expiró
    final windowDuration = now.difference(_windowStartTime!);
    if (windowDuration > _circuitBreakerWindow) {
      print(
          '$_tag 🔄 Ventana de circuit breaker expirada - Reiniciando contadores');
      _resetCircuitBreakerCounters();
      _windowStartTime = now;
    }
  }

  /// 🔄 Resetear contadores del circuit breaker
  static void _resetCircuitBreakerCounters() {
    _startAttemptsInWindow = 0;
    _windowStartTime = null;
  }

  /// 🔔 Notificar que el servicio fue detenido
  ///
  /// Llamar desde el código nativo cuando el servicio se detenga
  static void notifyServiceStopped({required String reason}) {
    print('$_tag 🛑 Servicio GPS detenido (razón: $reason)');
    _isServiceRunning = false;
  }

  /// 📝 Guardar métricas de inicio
  static Future<void> _saveStartMetrics(String source) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toIso8601String();

      // Guardar último inicio
      await prefs.setString('gps_last_start_time', now);
      await prefs.setString('gps_last_start_source', source);

      // Incrementar contador total
      final totalStarts = prefs.getInt('gps_total_starts') ?? 0;
      await prefs.setInt('gps_total_starts', totalStarts + 1);

      // Guardar contador por fuente
      final sourceKey = 'gps_starts_from_$source';
      final sourceStarts = prefs.getInt(sourceKey) ?? 0;
      await prefs.setInt(sourceKey, sourceStarts + 1);

      print(
          '$_tag 📊 Métricas actualizadas (total: ${totalStarts + 1}, source: $source)');
    } catch (e) {
      print('$_tag ❌ Error guardando métricas: $e');
    }
  }

  /// 🚨 Reportar evento de circuit breaker
  static Future<void> _reportCircuitBreakerEvent(String triggerSource) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toIso8601String();

      // Guardar evento
      await prefs.setString('gps_circuit_breaker_last_opened', now);
      await prefs.setString(
          'gps_circuit_breaker_trigger_source', triggerSource);

      // Incrementar contador de eventos
      final events = prefs.getInt('gps_circuit_breaker_events') ?? 0;
      await prefs.setInt('gps_circuit_breaker_events', events + 1);

      print(
          '$_tag 🚨 Evento de circuit breaker reportado (total: ${events + 1})');

      // TODO: Enviar a backend/Firebase para monitoreo
      // await _sendCircuitBreakerEventToBackend(triggerSource);
    } catch (e) {
      print('$_tag ❌ Error reportando evento de circuit breaker: $e');
    }
  }

  /// 📊 Obtener estadísticas del servicio GPS
  static Future<Map<String, dynamic>> getStatistics() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      return {
        'is_running': _isServiceRunning,
        'last_start_time': _lastStartTime?.toIso8601String(),
        'last_start_source': _lastStartSource,
        'circuit_breaker_open': _circuitBreakerOpen,
        'circuit_breaker_opened_at': _circuitBreakerOpenedAt?.toIso8601String(),
        'starts_in_current_window': _startAttemptsInWindow,
        'window_start_time': _windowStartTime?.toIso8601String(),
        'total_starts': prefs.getInt('gps_total_starts') ?? 0,
        'circuit_breaker_events':
            prefs.getInt('gps_circuit_breaker_events') ?? 0,
      };
    } catch (e) {
      print('$_tag ❌ Error obteniendo estadísticas: $e');
      return {};
    }
  }

  /// 🧹 Limpiar estado (útil para testing o reset manual)
  static Future<void> resetState() async {
    _debugLog('🧹 Reseteando estado del GPS Service Manager');

    _isServiceRunning = false;
    _lastStartTime = null;
    _lastStartSource = null;
    _circuitBreakerOpen = false;
    _circuitBreakerOpenedAt = null;
    _resetCircuitBreakerCounters();

    // Limpiar SharedPreferences (opcional)
    // final prefs = await SharedPreferences.getInstance();
    // await prefs.clear();
  }

  /// 🐞 Activar/Desactivar modo debug
  ///
  /// Cuando está activo, imprime logs detallados de todas las operaciones.
  /// Usar solo para debugging, ya que genera muchos logs.
  ///
  /// Ejemplo:
  /// ```dart
  /// GpsServiceManager.setDebugMode(true); // Activar logs
  /// ```
  static void setDebugMode(bool enabled) {
    _debugMode = enabled;
    _debugLog(
        '🐞 Debug mode ${enabled ? "ACTIVADO" : "DESACTIVADO"} para GPS Service Manager');
  }

  /// 📝 Log interno con control de debug mode
  ///
  /// Solo imprime si _debugMode está activado.
  /// SIEMPRE incluye el tag para facilitar filtrado en logs.
  static void _debugLog(String message) {
    if (_debugMode) {
      print('$_tag $message');
    }
  }

  /// 📝 Log de error (SIEMPRE se imprime, incluso sin debug mode)
  static void _errorLog(String message) {
    print('$_tag ❌ ERROR: $message');
  }
}
