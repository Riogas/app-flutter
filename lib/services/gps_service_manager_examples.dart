// 📝 EJEMPLO DE INTEGRACIÓN: GPS Service Manager
//
// Este archivo muestra cómo integrar el GPS Service Manager
// en diferentes partes del código para prevenir death loops.

import 'package:flutter/services.dart';
import '../services/gps_service_manager.dart';

// ═══════════════════════════════════════════════════════════════
// EJEMPLO 1: Inicio Manual desde Flutter UI
// ═══════════════════════════════════════════════════════════════

class LocationServiceExample {
  static const platform = MethodChannel('background_service');

  /// Iniciar GPS desde botón en la UI
  static Future<void> startGpsFromUI({
    required String movil,
    required String escenario,
    required String usuario,
    required String deviceId,
    required int interval,
  }) async {
    print('🔵 [UI] Usuario solicita inicio de GPS');

    // 1️⃣ Verificar con GPS Service Manager
    final canStart = await GpsServiceManager.requestGpsStart(
      source: 'manual_ui',
      force: false,
    );

    if (!canStart) {
      print('⏭️ [UI] Inicio bloqueado por Service Manager');
      // Mostrar mensaje al usuario
      // showSnackBar('El GPS ya está activo');
      return;
    }

    // 2️⃣ Proceder con el inicio
    try {
      print('✅ [UI] Iniciando servicio GPS...');
      await platform.invokeMethod('startLocationService', {
        'movil': movil,
        'escenario': escenario,
        'usuario': usuario,
        'deviceId': deviceId,
        'interval': interval,
      });
      print('✅ [UI] GPS iniciado correctamente');
    } catch (e) {
      print('❌ [UI] Error iniciando GPS: $e');
      // Notificar al manager que falló
      GpsServiceManager.notifyServiceStopped(reason: 'start_failed');
    }
  }

  /// Detener GPS desde botón en la UI
  static Future<void> stopGpsFromUI() async {
    print('🔴 [UI] Usuario solicita detener GPS');

    try {
      await platform.invokeMethod('stopLocationService');

      // Notificar al manager que el servicio fue detenido
      GpsServiceManager.notifyServiceStopped(reason: 'manual_stop');

      print('✅ [UI] GPS detenido correctamente');
    } catch (e) {
      print('❌ [UI] Error deteniendo GPS: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// EJEMPLO 2: FCM Push Notification (Force GPS)
// ═══════════════════════════════════════════════════════════════

class FcmGpsHandler {
  static const platform = MethodChannel('background_service');

  /// Manejar comando FCM force_gps_execution
  static Future<void> handleForceGpsCommand(Map<String, dynamic> data) async {
    print('📩 [FCM] Recibido comando force_gps_execution');

    // 1️⃣ Verificar con GPS Service Manager (force=true)
    final canStart = await GpsServiceManager.requestGpsStart(
      source: 'fcm_force',
      force: true, // ← force=true para comandos remotos
    );

    if (!canStart) {
      print('🚨 [FCM] Inicio bloqueado - Circuit breaker activo');
      print('⚠️ Detectado death loop, esperando cooldown');

      // Reportar al backend que no se pudo ejecutar
      // await reportFcmExecutionBlocked();
      return;
    }

    // 2️⃣ Proceder con el inicio forzado
    try {
      print('✅ [FCM] Iniciando GPS forzadamente...');

      final movil = data['movil'] ?? '0';
      final escenario = data['escenario'] ?? '0';

      await platform.invokeMethod('startLocationService', {
        'movil': movil,
        'escenario': escenario,
        'usuario': 'fcm_system',
        'deviceId': data['deviceId'] ?? '0',
        'interval': 1,
      });

      print('✅ [FCM] GPS forzado correctamente');
    } catch (e) {
      print('❌ [FCM] Error forzando GPS: $e');
      GpsServiceManager.notifyServiceStopped(reason: 'fcm_force_failed');
    }
  }

  /// Manejar comando FCM normal (no force)
  static Future<void> handleNormalGpsCommand(Map<String, dynamic> data) async {
    print('📩 [FCM] Recibido comando GPS normal');

    // Verificar sin force
    final canStart = await GpsServiceManager.requestGpsStart(
      source: 'fcm_push',
      force: false,
    );

    if (!canStart) {
      print('⏭️ [FCM] GPS ya está corriendo, omitiendo');
      return;
    }

    // Proceder normalmente...
  }
}

// ═══════════════════════════════════════════════════════════════
// EJEMPLO 3: WorkManager / AlarmManager (Periódico)
// ═══════════════════════════════════════════════════════════════

class PeriodicGpsHandler {
  static const platform = MethodChannel('background_service');

  /// Llamado por WorkManager cada 10 minutos
  static Future<void> handlePeriodicExecution() async {
    print('⏰ [WorkManager] Ejecución periódica iniciada');

    // 1️⃣ Verificar con GPS Service Manager
    final canStart = await GpsServiceManager.requestGpsStart(
      source: 'workmanager',
      force: false,
    );

    if (!canStart) {
      print('⏭️ [WorkManager] GPS ya corriendo o rate limited, omitiendo');
      return; // ✅ Salir silenciosamente
    }

    // 2️⃣ Verificar otras condiciones (batería, red, etc.)
    final hasInternet = await checkInternetConnection();
    if (!hasInternet) {
      print('⚠️ [WorkManager] Sin internet, omitiendo ejecución');
      return;
    }

    // 3️⃣ Proceder con el inicio
    try {
      print('✅ [WorkManager] Iniciando GPS periódico...');

      // Obtener datos de sesión
      final sessionData = await getSessionData();

      await platform.invokeMethod('startLocationService', {
        'movil': sessionData['movil'],
        'escenario': sessionData['escenario'],
        'usuario': sessionData['usuario'],
        'deviceId': sessionData['deviceId'],
        'interval': 1,
      });

      print('✅ [WorkManager] GPS iniciado correctamente');
    } catch (e) {
      print('❌ [WorkManager] Error: $e');
      GpsServiceManager.notifyServiceStopped(reason: 'workmanager_failed');
    }
  }

  static Future<bool> checkInternetConnection() async {
    // Implementar verificación de internet
    return true;
  }

  static Future<Map<String, String>> getSessionData() async {
    // Obtener datos de Hive
    return {
      'movil': '336',
      'escenario': '2000',
      'usuario': 'jgomez',
      'deviceId': 'abc123',
    };
  }
}

// ═══════════════════════════════════════════════════════════════
// EJEMPLO 4: Página de Configuración (Ver Estadísticas)
// ═══════════════════════════════════════════════════════════════

class GpsStatsWidget {
  /// Mostrar estadísticas del GPS Service Manager
  static Future<void> showGpsStats() async {
    print('📊 [Stats] Obteniendo estadísticas...');

    final stats = await GpsServiceManager.getStatistics();

    print('═══════════════════════════════════════');
    print('📊 GPS SERVICE MANAGER STATS');
    print('═══════════════════════════════════════');
    print('Servicio corriendo: ${stats['is_running']}');
    print('Último inicio: ${stats['last_start_time']}');
    print('Fuente: ${stats['last_start_source']}');
    print(
        'Circuit breaker: ${stats['circuit_breaker_open'] ? "🔴 ABIERTO" : "🟢 CERRADO"}');
    print('Inicios en ventana: ${stats['starts_in_current_window']}');
    print('Total inicios: ${stats['total_starts']}');
    print('Eventos de circuit breaker: ${stats['circuit_breaker_events']}');
    print('═══════════════════════════════════════');

    // Mostrar en UI
    // showDialog(
    //   context: context,
    //   builder: (_) => AlertDialog(
    //     title: Text('GPS Service Stats'),
    //     content: Text(JsonEncoder.withIndent('  ').convert(stats)),
    //   ),
    // );
  }

  /// Reset manual del estado (solo para testing)
  static Future<void> resetGpsManagerState() async {
    print('🧹 [Stats] Reseteando GPS Service Manager...');

    await GpsServiceManager.resetState();

    print('✅ [Stats] Estado reseteado correctamente');
  }
}

// ═══════════════════════════════════════════════════════════════
// EJEMPLO 5: Debugging y Monitoreo
// ═══════════════════════════════════════════════════════════════

class GpsDebugHelper {
  /// Simular death loop (para testing)
  static Future<void> simulateDeathLoop() async {
    print('🚨 [Debug] Simulando death loop...');

    for (int i = 0; i < 15; i++) {
      print('🔄 [Debug] Intento de inicio #${i + 1}');

      final canStart = await GpsServiceManager.requestGpsStart(
        source: 'debug_test',
        force: false,
      );

      if (!canStart) {
        print('🚫 [Debug] Bloqueado en intento #${i + 1}');
        print('🎯 [Debug] Circuit breaker funcionando correctamente!');
        break;
      }

      // Simular inicio rápido
      await Future.delayed(Duration(milliseconds: 100));
    }

    print('✅ [Debug] Simulación completada');
  }

  /// Verificar estado del servicio
  static Future<void> checkServiceState() async {
    print('🔍 [Debug] Verificando estado del servicio...');

    final isRunning = await GpsServiceManager.isGpsServiceRunning();
    print('Estado: ${isRunning ? "🟢 CORRIENDO" : "🔴 DETENIDO"}');

    final stats = await GpsServiceManager.getStatistics();
    if (stats['circuit_breaker_open'] == true) {
      final openedAt = stats['circuit_breaker_opened_at'];
      print('⚠️ Circuit breaker abierto desde: $openedAt');
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// EJEMPLO 6: Integración en LocationHelper
// ═══════════════════════════════════════════════════════════════

class LocationHelperExample {
  static const platform = MethodChannel('background_service');

  /// Método principal para iniciar GPS (reemplazar el existente)
  static Future<void> startGpsService({
    required String movil,
    required String escenario,
    required String usuario,
    required String deviceId,
  }) async {
    print('🌍 [LocationHelper] Solicitando inicio de GPS');

    // 1️⃣ Verificar con GPS Service Manager
    final canStart = await GpsServiceManager.requestGpsStart(
      source: 'location_helper',
      force: false,
    );

    if (!canStart) {
      print('⏭️ [LocationHelper] Inicio bloqueado por Service Manager');

      // Verificar razón del bloqueo
      final stats = await GpsServiceManager.getStatistics();
      if (stats['circuit_breaker_open'] == true) {
        print('🚨 Circuit breaker activo - Death loop detectado');
        // Notificar al backend o al usuario
      } else if (stats['is_running'] == true) {
        print('ℹ️ GPS ya está corriendo');
      } else {
        print('⏱️ Rate limited - esperando cooldown');
      }

      return;
    }

    // 2️⃣ Proceder con el inicio normal
    try {
      print('✅ [LocationHelper] Iniciando GPS...');

      await platform.invokeMethod('startLocationService', {
        'movil': movil,
        'escenario': escenario,
        'usuario': usuario,
        'deviceId': deviceId,
        'interval': 1,
      });

      print('✅ [LocationHelper] GPS iniciado correctamente');
    } catch (e, stackTrace) {
      print('❌ [LocationHelper] Error iniciando GPS: $e');
      print('📚 StackTrace: $stackTrace');

      // Notificar al manager que falló
      GpsServiceManager.notifyServiceStopped(reason: 'location_helper_error');
    }
  }

  /// Detener GPS
  static Future<void> stopGpsService() async {
    print('🛑 [LocationHelper] Deteniendo GPS...');

    try {
      await platform.invokeMethod('stopLocationService');

      // Notificar al manager
      GpsServiceManager.notifyServiceStopped(reason: 'location_helper_stop');

      print('✅ [LocationHelper] GPS detenido');
    } catch (e) {
      print('❌ [LocationHelper] Error deteniendo GPS: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// NOTAS DE IMPLEMENTACIÓN
// ═══════════════════════════════════════════════════════════════

/*

PASOS PARA INTEGRAR EN TU CÓDIGO:

1. LocationHelper.dart:
   - Reemplazar método startGpsService() con LocationHelperExample.startGpsService()
   - Agregar verificación con GpsServiceManager antes de iniciar

2. FCM Handler (fcm_push_receiver.dart o similar):
   - Agregar FcmGpsHandler.handleForceGpsCommand() para force_gps_execution
   - Agregar FcmGpsHandler.handleNormalGpsCommand() para otros comandos

3. WorkManager/AlarmManager:
   - Agregar PeriodicGpsHandler.handlePeriodicExecution() en el worker
   - Verificar con GpsServiceManager antes de iniciar

4. Settings Page:
   - Agregar botón para ver estadísticas (GpsStatsWidget.showGpsStats())
   - Agregar botón de reset para testing (GpsStatsWidget.resetGpsManagerState())

5. Testing:
   - Usar GpsDebugHelper.simulateDeathLoop() para probar circuit breaker
   - Usar GpsDebugHelper.checkServiceState() para verificar estado

IMPORTANTE:
- SIEMPRE llamar a GpsServiceManager.requestGpsStart() ANTES de iniciar el servicio
- SIEMPRE llamar a GpsServiceManager.notifyServiceStopped() cuando el servicio se detenga
- Usar force=true SOLO para comandos FCM force_gps_execution
- Respetar el resultado de requestGpsStart() - NO iniciar si retorna false

*/
