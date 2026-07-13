package com.riogas.appmovil

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.example.moveit.ForegroundLocationService
import com.example.moveit.LocationReceiver

/**
 * Sistema de "watchdog" mutuo entre servicios
 * 
 * FUNCIÓN:
 * - CriticalLogUploadWorker verifica que GPS service esté activo
 * - ForegroundLocationService verifica que CriticalLogUploadWorker esté programado
 * - Si alguno detecta que el otro murió, lo reinicia
 * - Todo se loguea en CriticalLogger para n8n
 * 
 * PROPÓSITO:
 * - Garantizar que ambos servicios estén SIEMPRE activos
 * - Auto-recuperación si Android mata alguno
 * - Monitoreo cruzado para máxima resiliencia
 */
object ServiceWatchdog {
    
    private const val TAG = "ServiceWatchdog"
    
    /**
     * Verifica si un servicio específico está corriendo (genérico)
     */
    fun isServiceRunning(context: Context, serviceClass: Class<*>): Boolean {
        return try {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            @Suppress("DEPRECATION")
            for (service in manager.getRunningServices(Integer.MAX_VALUE)) {
                if (serviceClass.name == service.service.className) {
                    return true
                }
            }
            false
        } catch (e: Exception) {
            Log.e(TAG, "Error verificando si servicio ${serviceClass.simpleName} está corriendo", e)
            false
        }
    }
    
    /**
     * Verifica si el ForegroundLocationService está corriendo
     */
    fun isGPSServiceRunning(context: Context): Boolean {
        return isServiceRunning(context, ForegroundLocationService::class.java)
    }
    
    /**
     * Verifica si hay alarmas programadas para el LocationReceiver
     */
    fun isAlarmScheduled(context: Context): Boolean {
        return try {
            val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            val movil = prefs.getString("last_movil", "") ?: ""
            
            if (movil.isEmpty()) {
                return false
            }
            
            val intent = Intent(context, LocationReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                1710,
                intent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            
            pendingIntent != null
        } catch (e: Exception) {
            Log.e(TAG, "Error verificando si alarma está programada", e)
            false
        }
    }
    
    /**
     * Verifica si CriticalLogAlarmReceiver está programado (AlarmManager)
     * 🆕 Cambio de WorkManager a AlarmManager para ejecución cada 30 segundos
     */
    suspend fun isCriticalLogWorkerScheduled(context: Context): Boolean {
        return try {
            CriticalLogAlarmReceiver.isScheduled(context)
        } catch (e: Exception) {
            Log.e(TAG, "Error verificando si CriticalLogAlarmReceiver está programado", e)
            false
        }
    }
    
    /**
     * Reinicia el servicio GPS desde el watchdog
     * Llamado por CriticalLogUploadWorker cuando detecta que GPS está muerto
     */
    suspend fun restartGPSService(context: Context): Boolean {
        return try {
            val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            var movil = prefs.getString("last_movil", "") ?: ""
            val escenario = prefs.getString("last_escenario", "") ?: ""
            val usuario = prefs.getString("last_usuario", "") ?: ""
            var deviceId = prefs.getString("last_deviceId", "") ?: ""
            val intervalMinutes = prefs.getFloat("last_interval", 0.5f).toDouble()
            val isDisabled = prefs.getBoolean("service_disabled", false)
            val watchdogDisabled = prefs.getBoolean("watchdog_disabled", false)

            // 🚩 MARCAR FLAG: GPS service está apagado
            ServiceStatusFlags.setServicesNeedRestart(
                context, 
                true, 
                "ServiceWatchdog",
                "GPS service detectado como muerto"
            )
            ServiceStatusFlags.setGPSServiceStatus(context, false, "ServiceWatchdog")

            // 🔧 FIX v14.7: Relajar validación - deviceId es suficiente para reiniciar
            // Validación 1: DeviceId vacío - INTENTAR RECUPERAR (CRÍTICO)
            if (deviceId.isEmpty()) {
                Log.w(TAG, "⚠️ [RECOVERY] DeviceId vacío, intentando recuperar (CRÍTICO)...")
                
                // Intentar recuperar deviceId desde TODOS los lugares posibles
                try {
                    // 1️⃣ Intentar desde FlutterSharedPreferences (formato normal de Hive)
                    val flutterPrefs = context.getSharedPreferences(
                        "FlutterSharedPreferences",
                        Context.MODE_PRIVATE
                    )
                    
                    var recoveredDeviceId = flutterPrefs.getString("flutter.deviceId", null)
                        ?: flutterPrefs.getString("flutter.DeviceId", null)
                        ?: flutterPrefs.getString("deviceId", null)
                        ?: flutterPrefs.getString("DeviceId", null)
                    
                    // 2️⃣ Si no está en FlutterSharedPreferences, buscar en sessionBox de Hive
                    if (recoveredDeviceId.isNullOrBlank()) {
                        Log.d(TAG, "   🔍 Buscando en Hive sessionBox...")
                        
                        // Hive guarda sus boxes en SharedPreferences con el prefijo del nombre del box
                        val allPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).all
                        
                        // Buscar cualquier clave que contenga "deviceId"
                        for ((key, value) in allPrefs) {
                            if (key.contains("deviceId", ignoreCase = true)) {
                                Log.d(TAG, "   🔎 Encontrada clave: $key = $value")
                                if (value is String && value.isNotBlank()) {
                                    recoveredDeviceId = value
                                    break
                                }
                            }
                        }
                    }
                    
                    // 3️⃣ Si aún no lo encontró, buscar en config nativo
                    if (recoveredDeviceId.isNullOrBlank()) {
                        Log.d(TAG, "   🔍 Buscando en Native SharedPreferences...")
                        recoveredDeviceId = prefs.getString("last_deviceId", null)
                    }
                    
                    if (!recoveredDeviceId.isNullOrBlank()) {
                        deviceId = recoveredDeviceId
                        prefs.edit().putString("last_deviceId", deviceId).apply()
                        Log.i(TAG, "✅ [RECOVERY] DeviceId recuperado: $deviceId")
                        
                        CriticalLogger.logCritical(
                            TAG,
                            "RECOVERY SUCCESS: DeviceId recuperado exitosamente",
                            mapOf(
                                "deviceId" to deviceId,
                                "recovery_source" to "flutter_or_native_prefs"
                            ),
                            "DEVICE_ID_RECOVERED"
                        )
                    } else {
                        // ❌ CRÍTICO: Sin deviceId, NO SE PUEDE REINICIAR
                        Log.e(TAG, "❌ [RECOVERY] No se pudo recuperar DeviceId - REINICIO IMPOSIBLE")
                        
                        CriticalLogger.logCritical(
                            TAG,
                            "RECOVERY FAILED: No se pudo recuperar DeviceId - servicio NO puede reiniciarse",
                            mapOf(
                                "checked_flutter_prefs" to "true",
                                "checked_hive_box" to "true",
                                "checked_native_prefs" to "true",
                                "movil" to movil,
                                "escenario" to escenario,
                                "usuario" to usuario
                            ),
                            "DEVICE_ID_RECOVERY_FAILED_CRITICAL"
                        )
                        return false // ❌ Detener aquí - deviceId es OBLIGATORIO
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ [RECOVERY] Error recuperando deviceId: ${e.message}", e)
                    CriticalLogger.logCritical(
                        TAG,
                        "RECOVERY ERROR: Excepción recuperando DeviceId",
                        e,
                        mapOf(
                            "error_type" to e.javaClass.simpleName,
                            "error_message" to (e.message ?: "Sin mensaje")
                        ),
                        "DEVICE_ID_RECOVERY_ERROR"
                    )
                    return false // ❌ Error crítico - no continuar
                }
            }
            
            // ⚠️ ADVERTENCIA: Movil vacío pero continuamos (deviceId es suficiente)
            if (movil.isEmpty()) {
                Log.w(TAG, "⚠️ Movil vacío pero deviceId presente ($deviceId) - CONTINUANDO con reinicio")
                
                // Intentar recuperar movil (NO bloqueante)
                Log.i(TAG, "   🔍 Intentando recuperar movil desde API...")
                val recoveredMovil = MovilRecoveryHelper.recoverMovilId(context, deviceId)
                
                if (recoveredMovil != null) {
                    movil = recoveredMovil
                    prefs.edit().putString("last_movil", movil).apply()
                    
                    Log.i(TAG, "✅ [RECOVERY] Movil recuperado: $movil")
                    CriticalLogger.logCritical(
                        TAG,
                        "RECOVERY SUCCESS: Movil recuperado exitosamente",
                        mapOf(
                            "movil" to movil,
                            "deviceId" to deviceId,
                            "recovery_source" to "api"
                        ),
                        "MOVIL_RECOVERED"
                    )
                } else {
                    Log.w(TAG, "⚠️ [RECOVERY] No se pudo recuperar movil - continuando sin movil")
                    // Usar valor por defecto "0" para evitar problemas
                    movil = "0"
                    
                    CriticalLogger.logCritical(
                        TAG,
                        "RECOVERY WARNING: Movil no recuperado - usando valor por defecto '0'",
                        mapOf(
                            "movil" to movil,
                            "deviceId" to deviceId,
                            "api_checked" to "true"
                        ),
                        "MOVIL_RECOVERY_FAILED_USING_DEFAULT"
                    )
                }
            }

            // Validación 2: Watchdog explícitamente deshabilitado (solo por FCM stop_gps_service)
            if (watchdogDisabled) {
                Log.w(TAG, "⚠️ WATCHDOG deshabilitado por comando FCM stop_gps_service")
                Log.i(TAG, "🚨 Invocando comando FCM remoto para reinicio...")
                
                CriticalLogger.logCritical(
                    TAG,
                    "WATCHDOG: Watchdog deshabilitado explícitamente, solicitando reinicio remoto via FCM",
                    mapOf(
                        "movil" to movil,
                        "escenario" to escenario,
                        "usuario" to usuario,
                        "deviceId" to deviceId,
                        "interval" to intervalMinutes,
                        "android_version" to Build.VERSION.SDK_INT,
                        "context" to "CriticalLogWorker_watchdog",
                        "reason" to "watchdog_disabled_by_fcm_stop",
                        "service_disabled" to isDisabled.toString(),
                        "action" to "calling_fcm_api_for_remote_restart"
                    ),
                    "WATCHDOG_RESTART_BLOCKED"
                )
                
                // 🆕 NUEVO: Enviar comando FCM remoto para forzar reinicio desde servidor
                try {
                    val escenarioId = escenario.toIntOrNull() ?: 0
                    
                    FcmApiHelper.forceGpsExecution(
                        context,
                        escenarioId,
                        movil,
                        onSuccess = { response ->
                            Log.i(TAG, "✅ Comando FCM enviado exitosamente: $response")
                            CriticalLogger.logCritical(
                                TAG,
                                "WATCHDOG: Comando FCM enviado - esperando respuesta remota para reinicio",
                                mapOf(
                                    "movil" to movil,
                                    "escenario" to escenario,
                                    "action" to "force_gps_execution",
                                    "trigger" to "watchdog_disabled",
                                    "response" to response
                                ),
                                "WATCHDOG_FCM_COMMAND_SENT"
                            )
                        },
                        onError = { error ->
                            Log.e(TAG, "❌ Error enviando comando FCM: $error")
                            CriticalLogger.logCritical(
                                TAG,
                                "WATCHDOG ERROR: Fallo enviando comando FCM remoto",
                                mapOf(
                                    "movil" to movil,
                                    "escenario" to escenario,
                                    "error" to error,
                                    "action" to "force_gps_execution",
                                    "trigger" to "watchdog_disabled"
                                ),
                                "WATCHDOG_FCM_COMMAND_ERROR"
                            )
                        }
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Excepción al invocar FCM API: ${e.message}", e)
                    CriticalLogger.logCritical(
                        TAG,
                        "WATCHDOG EXCEPTION: Error crítico invocando FCM API",
                        e,
                        mapOf(
                            "movil" to movil,
                            "escenario" to escenario,
                            "error_type" to e.javaClass.simpleName,
                            "error_message" to (e.message ?: "Sin mensaje")
                        ),
                        "WATCHDOG_FCM_COMMAND_EXCEPTION"
                    )
                }
                
                return false
            }

            // ⚠️ IMPORTANTE: service_disabled NO impide el reinicio automático del watchdog
            // Solo se usa para indicar que el usuario/servidor detuvo el servicio manualmente
            // El watchdog SIEMPRE intenta reiniciar si el servicio muere (a menos que watchdog_disabled=true)

            Log.i(TAG, "🔄 [WATCHDOG] Reiniciando GPS service completo desde CriticalLogWorker...")

            // Log inicio del proceso de reinicio
            CriticalLogger.logCritical(
                TAG,
                "WATCHDOG: Iniciando proceso de reinicio completo del GPS service",
                mapOf(
                    "movil" to movil,
                    "escenario" to escenario,
                    "usuario" to usuario,
                    "deviceId" to deviceId,
                    "interval" to intervalMinutes,
                    "android_version" to Build.VERSION.SDK_INT,
                    "sdk_int" to Build.VERSION.SDK_INT,
                    "manufacturer" to Build.MANUFACTURER,
                    "model" to Build.MODEL,
                    "step" to "1_inicio_reinicio",
                    "restarted_by" to "CriticalLogWorker",
                    "reason" to "service_not_running"
                ),
                "WATCHDOG_RESTART_INITIATED"
            )

            // 1️⃣ Limpiar estados de deshabilitación/pausa (igual que en MainActivity)
            prefs.edit().apply {
                putBoolean("service_disabled", false)
                remove("stop_reason")
                remove("stop_timestamp")
                remove("auto_stopped")
                remove("stopped_by_user")
                remove("stopped_from_device")
                putBoolean("service_paused", false)
                remove("resume_time")
                remove("pause_minutes")
            }.apply()
            Log.i(TAG, "🧹 [WATCHDOG] Estados de servicio limpiados antes de reiniciar")

            // Log limpieza de estados
            CriticalLogger.logCritical(
                TAG,
                "WATCHDOG: Estados de servicio limpiados exitosamente",
                mapOf(
                    "movil" to movil,
                    "step" to "2_estados_limpiados",
                    "flags_cleared" to "service_disabled,stop_reason,stop_timestamp,auto_stopped,stopped_by_user,stopped_from_device,service_paused,resume_time,pause_minutes"
                ),
                "WATCHDOG_RESTART_STATE_CLEARED"
            )

            // 2️⃣ Cancelar alarmas/workers existentes para evitar duplicados
            var alarmCancelled = false
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val alarmIntent = Intent(context, com.example.moveit.LocationReceiver::class.java)
                val pendingIntent = PendingIntent.getBroadcast(
                    context,
                    1710,
                    alarmIntent,
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                )
                if (pendingIntent != null) {
                    alarmManager.cancel(pendingIntent)
                    Log.i(TAG, "🧹 [WATCHDOG] Alarma anterior cancelada")
                    alarmCancelled = true
                    
                    CriticalLogger.logCritical(
                        TAG,
                        "WATCHDOG: AlarmManager anterior cancelado exitosamente",
                        mapOf(
                            "movil" to movil,
                            "step" to "3_alarm_cancelled",
                            "had_existing_alarm" to "true"
                        ),
                        "WATCHDOG_RESTART_ALARM_CANCELLED"
                    )
                } else {
                    Log.i(TAG, "🧹 [WATCHDOG] No había alarma anterior activa")
                    CriticalLogger.logCritical(
                        TAG,
                        "WATCHDOG: No había AlarmManager anterior activo",
                        mapOf(
                            "movil" to movil,
                            "step" to "3_alarm_check",
                            "had_existing_alarm" to "false"
                        ),
                        "WATCHDOG_RESTART_NO_ALARM"
                    )
                }
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ [WATCHDOG] Error cancelando alarma anterior: ${e.message}")
                CriticalLogger.logCritical(
                    TAG,
                    "WATCHDOG ERROR: Fallo al cancelar AlarmManager anterior",
                    e,
                    mapOf(
                        "movil" to movil,
                        "step" to "3_alarm_error",
                        "error_message" to (e.message ?: "Sin mensaje"),
                        "error_type" to e.javaClass.simpleName
                    ),
                    "WATCHDOG_RESTART_ALARM_ERROR"
                )
            }

            var workManagerCancelled = false
            try {
                com.example.moveit.WorkManagerHelper.cancelPeriodicWork(context)
                Log.i(TAG, "🧹 [WATCHDOG] WorkManager anterior cancelado")
                workManagerCancelled = true
                
                CriticalLogger.logCritical(
                    TAG,
                    "WATCHDOG: WorkManager anterior cancelado exitosamente",
                    mapOf(
                        "movil" to movil,
                        "step" to "4_workmanager_cancelled"
                    ),
                    "WATCHDOG_RESTART_WORKMANAGER_CANCELLED"
                )
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ [WATCHDOG] Error cancelando WorkManager: ${e.message}")
                CriticalLogger.logCritical(
                    TAG,
                    "WATCHDOG ERROR: Fallo al cancelar WorkManager anterior",
                    e,
                    mapOf(
                        "movil" to movil,
                        "step" to "4_workmanager_error",
                        "error_message" to (e.message ?: "Sin mensaje"),
                        "error_type" to e.javaClass.simpleName
                    ),
                    "WATCHDOG_RESTART_WORKMANAGER_ERROR"
                )
            }

            // 3️⃣ Iniciar ForegroundService (igual que en MainActivity)
            val serviceIntent = Intent(context, ForegroundLocationService::class.java).apply {
                putExtra("movil", movil)
                putExtra("escenario", escenario)
                putExtra("usuario", usuario)
                putExtra("deviceId", deviceId)
                putExtra("intervalMinutes", intervalMinutes)
                putExtra("EXECUTE_GPS", true) // ✅ SÍ ejecutar GPS para programar AlarmManager
                putExtra("IS_WATCHDOG_RESTART", true) // Marcar que es un reinicio del watchdog
            }

            // Log antes de iniciar el servicio
            CriticalLogger.logCritical(
                TAG,
                "WATCHDOG: Iniciando ForegroundLocationService",
                mapOf(
                    "movil" to movil,
                    "escenario" to escenario,
                    "usuario" to usuario,
                    "deviceId" to deviceId,
                    "interval" to intervalMinutes,
                    "step" to "5_starting_service",
                    "execute_gps" to "true", // ✅ Cambiado a true
                    "is_watchdog_restart" to "true",
                    "android_version" to Build.VERSION.SDK_INT,
                    "uses_foreground_service" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O).toString()
                ),
                "WATCHDOG_RESTART_STARTING_SERVICE"
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }

            Log.i(TAG, "✅ [WATCHDOG] GPS service reiniciado exitosamente (flujo completo)")
            Log.d(TAG, "   - Movil: $movil")
            Log.d(TAG, "   - Escenario: $escenario")
            Log.d(TAG, "   - Usuario: $usuario")
            Log.d(TAG, "   - Interval: $intervalMinutes min")

            // 🚩 MARCAR FLAG: GPS service reiniciado exitosamente
            // Nota: La flag volverá a false en la próxima verificación cuando detecte que está activo
            ServiceStatusFlags.setGPSServiceStatus(context, true, "ServiceWatchdog")

            // Log crítico de reinicio exitoso COMPLETO
            CriticalLogger.logCritical(
                TAG,
                "WATCHDOG EXITOSO: GPS service reiniciado automáticamente - Flujo completo ejecutado",
                mapOf(
                    "movil" to movil,
                    "escenario" to escenario,
                    "usuario" to usuario,
                    "deviceId" to deviceId,
                    "interval" to intervalMinutes,
                    "step" to "6_restart_complete",
                    "android_version" to Build.VERSION.SDK_INT,
                    "sdk_int" to Build.VERSION.SDK_INT,
                    "manufacturer" to Build.MANUFACTURER,
                    "model" to Build.MODEL,
                    "restarted_by" to "CriticalLogWorker",
                    "reason" to "service_not_running",
                    "alarm_cancelled" to alarmCancelled.toString(),
                    "workmanager_cancelled" to workManagerCancelled.toString(),
                    "complete_flow" to "true"
                ),
                "WATCHDOG_SERVICE_RESTARTED_SUCCESS"
            )

            true

        } catch (e: SecurityException) {
            val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            val movil = prefs.getString("last_movil", "unknown") ?: "unknown"
            val escenario = prefs.getString("last_escenario", "") ?: ""
            val usuario = prefs.getString("last_usuario", "") ?: ""
            val deviceId = prefs.getString("last_deviceId", "") ?: ""
            
            Log.e(TAG, "❌ [WATCHDOG] SecurityException reiniciando GPS service", e)
            CriticalLogger.logCritical(
                TAG,
                "WATCHDOG ERROR: Sin permisos para reiniciar GPS service - SecurityException",
                e,
                mapOf(
                    "error_type" to e.javaClass.simpleName,
                    "error_message" to (e.message ?: "Sin mensaje"),
                    "error_cause" to (e.cause?.javaClass?.simpleName ?: "Sin causa"),
                    "stack_trace" to e.stackTraceToString().take(500),
                    "movil" to movil,
                    "escenario" to escenario,
                    "usuario" to usuario,
                    "deviceId" to deviceId,
                    "android_version" to Build.VERSION.SDK_INT,
                    "sdk_int" to Build.VERSION.SDK_INT,
                    "manufacturer" to Build.MANUFACTURER,
                    "model" to Build.MODEL,
                    "context" to "CriticalLogWorker_watchdog",
                    "reason" to "security_exception"
                ),
                "WATCHDOG_RESTART_FAILED"
            )
            false

        } catch (e: IllegalStateException) {
            val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            val movil = prefs.getString("last_movil", "unknown") ?: "unknown"
            val escenario = prefs.getString("last_escenario", "") ?: ""
            val usuario = prefs.getString("last_usuario", "") ?: ""
            val deviceId = prefs.getString("last_deviceId", "") ?: ""
            
            Log.e(TAG, "❌ [WATCHDOG] IllegalStateException reiniciando GPS service", e)
            CriticalLogger.logCritical(
                TAG,
                "WATCHDOG ERROR: GPS service bloqueado por background restrictions - IllegalStateException",
                e,
                mapOf(
                    "error_type" to e.javaClass.simpleName,
                    "error_message" to (e.message ?: "Sin mensaje"),
                    "error_cause" to (e.cause?.javaClass?.simpleName ?: "Sin causa"),
                    "stack_trace" to e.stackTraceToString().take(500),
                    "movil" to movil,
                    "escenario" to escenario,
                    "usuario" to usuario,
                    "deviceId" to deviceId,
                    "android_version" to Build.VERSION.SDK_INT,
                    "sdk_int" to Build.VERSION.SDK_INT,
                    "manufacturer" to Build.MANUFACTURER,
                    "model" to Build.MODEL,
                    "context" to "CriticalLogWorker_watchdog",
                    "reason" to "illegal_state_exception",
                    "android_restriction" to "background_execution_limit"
                ),
                "WATCHDOG_RESTART_FAILED"
            )
            false

        } catch (e: Exception) {
            val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            val movil = prefs.getString("last_movil", "unknown") ?: "unknown"
            val escenario = prefs.getString("last_escenario", "") ?: ""
            val usuario = prefs.getString("last_usuario", "") ?: ""
            val deviceId = prefs.getString("last_deviceId", "") ?: ""
            
            Log.e(TAG, "❌ [WATCHDOG] Error desconocido reiniciando GPS service", e)
            CriticalLogger.logCritical(
                TAG,
                "WATCHDOG ERROR: Fallo desconocido reiniciando GPS service - ${e.javaClass.simpleName}",
                e,
                mapOf(
                    "error_type" to e.javaClass.simpleName,
                    "error_message" to (e.message ?: "Sin mensaje"),
                    "error_cause" to (e.cause?.javaClass?.simpleName ?: "Sin causa"),
                    "error_cause_message" to (e.cause?.message ?: "Sin mensaje de causa"),
                    "stack_trace" to e.stackTraceToString().take(500),
                    "movil" to movil,
                    "escenario" to escenario,
                    "usuario" to usuario,
                    "deviceId" to deviceId,
                    "android_version" to Build.VERSION.SDK_INT,
                    "sdk_int" to Build.VERSION.SDK_INT,
                    "manufacturer" to Build.MANUFACTURER,
                    "model" to Build.MODEL,
                    "context" to "CriticalLogWorker_watchdog",
                    "reason" to "unknown_exception"
                ),
                "WATCHDOG_RESTART_FAILED"
            )
            false
        }
    }
    
    /**
     * Re-programa CriticalLogAlarmReceiver desde el GPS service
     * 🆕 Cambio de WorkManager a AlarmManager
     * Llamado por ForegroundLocationService cuando detecta que alarm no está programada
     */
    fun restartCriticalLogWorker(context: Context) {
        try {
            // 🚩 MARCAR FLAG: CriticalLog alarm no está programada
            ServiceStatusFlags.setServicesNeedRestart(
                context, 
                true, 
                "GPS_Service",
                "CriticalLogAlarmReceiver no está programada"
            )
            ServiceStatusFlags.setCriticalLogServiceStatus(context, false, "GPS_Service")

            Log.i(TAG, "🔄 [WATCHDOG] Re-programando CriticalLogAlarmReceiver desde GPS service...")
            
            CriticalLogAlarmReceiver.schedule(context)
            
            Log.i(TAG, "✅ [WATCHDOG] CriticalLogAlarmReceiver re-programado exitosamente")
            
            // 🚩 MARCAR FLAG: CriticalLog alarm re-programada exitosamente
            ServiceStatusFlags.setCriticalLogServiceStatus(context, true, "GPS_Service")

            // Log crítico de re-programación exitosa
            CriticalLogger.logCritical(
                TAG,
                "WATCHDOG EXITOSO: CriticalLogWorker re-programado automáticamente",
                mapOf(
                    "restarted_by" to "GPS_Service",
                    "reason" to "worker_not_scheduled"
                ),
                "WATCHDOG_WORKER_RESTARTED"
            )
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ [WATCHDOG] Error re-programando CriticalLogWorker", e)
            CriticalLogger.logCritical(
                TAG,
                "WATCHDOG ERROR: No se pudo re-programar CriticalLogWorker",
                e,
                mapOf(
                    "error_type" to e.javaClass.simpleName,
                    "context" to "GPS_Service_watchdog"
                ),
                "WATCHDOG_RESTART_FAILED"
            )
        }
    }
    
    /**
     * Estado completo del sistema de monitoreo
     */
    fun getSystemHealth(context: Context): Map<String, Any> {
        val isGPSRunning = isGPSServiceRunning(context)
        val isAlarmActive = isAlarmScheduled(context)
        
        return mapOf(
            "gps_service_running" to isGPSRunning,
            "alarm_scheduled" to isAlarmActive,
            "timestamp" to System.currentTimeMillis(),
            "android_version" to Build.VERSION.SDK_INT
        )
    }
}
