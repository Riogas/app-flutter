package com.riogas.appmovil

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.example.moveit.ForegroundLocationService
import com.example.moveit.LocationHelper
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import java.text.SimpleDateFormat
import java.util.*

/**
 * 🔔 FcmPushReceiver - Recibe push notifications silenciosas desde FCM
 * 
 * Permite control remoto del GPS service desde el servidor:
 * - restart_gps_service: Reinicia el servicio GPS completo (flujo igual al login)
 * - stop_gps_service: Detiene el servicio GPS
 * - force_gps_execution: Fuerza una ejecución inmediata del GPS
 * - get_status: Reporta el estado actual del servicio
 * 
 * Todo se loguea en CriticalLogger para monitoreo en n8n
 */
class FcmPushReceiver : FirebaseMessagingService() {

    companion object {
        private const val TAG = "FcmPushReceiver"
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())
        
        Log.d(TAG, "🔔 [FCM] Push recibido: ${remoteMessage.data}")

        // Loguear recepción del push
        CriticalLogger.logCritical(
            TAG,
            "FCM: Push notification recibido",
            mapOf(
                "timestamp" to timestamp,
                "from" to (remoteMessage.from ?: "unknown"),
                "data" to remoteMessage.data.toString(),
                "message_id" to (remoteMessage.messageId ?: "no_id")
            ),
            "FCM_PUSH_RECEIVED"
        )

        // Procesar el comando
        val action = remoteMessage.data["action"]
        
        if (action.isNullOrEmpty()) {
            Log.w(TAG, "⚠️ [FCM] Push sin campo 'action', ignorando")
            CriticalLogger.logCritical(
                TAG,
                "FCM ERROR: Push sin campo 'action'",
                mapOf(
                    "data" to remoteMessage.data.toString()
                ),
                "FCM_MISSING_ACTION"
            )
            return
        }

        Log.i(TAG, "🎯 [FCM] Acción recibida: $action")

        when (action) {
            "restart_gps_service" -> handleRestartGpsService(remoteMessage)
            "stop_gps_service" -> handleStopGpsService(remoteMessage)
            "force_gps_execution" -> handleForceGpsExecution(remoteMessage)
            "get_status" -> handleGetStatus(remoteMessage)
            "logout_user" -> handleLogoutUser(remoteMessage)
            else -> {
                Log.w(TAG, "⚠️ [FCM] Acción desconocida: $action")
                CriticalLogger.logCritical(
                    TAG,
                    "FCM ERROR: Acción desconocida",
                    mapOf(
                        "action" to action,
                        "data" to remoteMessage.data.toString()
                    ),
                    "FCM_UNKNOWN_ACTION"
                )
            }
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "🔑 [FCM] Nuevo token generado: $token")
        
        // Guardar el token en SharedPreferences para enviarlo al servidor
        val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
        prefs.edit().putString("fcm_token", token).apply()
        
        CriticalLogger.logCritical(
            TAG,
            "FCM: Nuevo token FCM generado",
            mapOf(
                "token" to token,
                "timestamp" to SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())
            ),
            "FCM_NEW_TOKEN"
        )
    }

    /**
     * 🔄 COMANDO: restart_gps_service
     * Reinicia el GPS service completo, replicando el flujo de login
     */
    private fun handleRestartGpsService(remoteMessage: RemoteMessage) {
        Log.i(TAG, "🔄 [FCM] Ejecutando restart_gps_service...")

        try {
            // 🔐 VALIDACIÓN #1: Verificar si hay sesión activa
            if (!LocationHelper.isSessionActive(this)) {
                Log.w(TAG, "🚫 [FCM] [SESSION] No hay sesión activa, ignorando comando restart_gps_service")
                CriticalLogger.logCritical(
                    TAG,
                    "FCM: Comando restart_gps_service ignorado (sin sesión activa)",
                    mapOf(
                        "reason" to "No active Firebase session",
                        "command" to "restart_gps_service"
                    ),
                    "FCM_COMMAND_IGNORED_NO_SESSION"
                )
                return
            }
            
            val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            
            // 🆕 OBTENER DATOS CON FALLBACK A FLUTTER
            // 1️⃣ movil (CRÍTICO) - Default "0" si no se encuentra
            var movil = prefs.getString("last_movil", "0") ?: "0"
            if (movil.isEmpty() || movil == "unknown") {
                movil = "0"  // Normalizar a "0" si está vacío o unknown
            }
            
            // Intentar recuperar desde Flutter si es "0"
            if (movil == "0") {
                val movilFromFlutter = flutterPrefs.getString("flutter.movil", null)
                if (!movilFromFlutter.isNullOrEmpty() && movilFromFlutter != "unknown" && movilFromFlutter != "0") {
                    movil = movilFromFlutter
                    prefs.edit().putString("last_movil", movil).apply()
                    Log.i(TAG, "✅ [FCM] movil recuperado desde Flutter: $movil")
                } else {
                    Log.w(TAG, "⚠️ [FCM] movil no disponible, usando \"0\" (el servicio se iniciará igual)")
                }
            }
            
            // 2️⃣ escenario
            var escenario = prefs.getString("last_escenario", "0") ?: "0"
            if (escenario.isEmpty() || escenario == "unknown") {
                escenario = "0"
            }
            if (escenario == "0") {
                val escenarioFromFlutter = flutterPrefs.getString("flutter.escenario", null)
                if (!escenarioFromFlutter.isNullOrEmpty() && escenarioFromFlutter != "unknown") {
                    escenario = escenarioFromFlutter
                    prefs.edit().putString("last_escenario", escenario).apply()
                    Log.i(TAG, "✅ [FCM] escenario recuperado desde Flutter: $escenario")
                }
            }
            
            // 3️⃣ usuario
            var usuario = prefs.getString("last_usuario", "") ?: ""
            if (usuario.isEmpty() || usuario == "unknown") {
                val usuarioFromFlutter = flutterPrefs.getString("flutter.username", null)
                if (!usuarioFromFlutter.isNullOrEmpty() && usuarioFromFlutter != "unknown") {
                    usuario = usuarioFromFlutter
                    prefs.edit().putString("last_usuario", usuario).apply()
                    Log.i(TAG, "✅ [FCM] usuario recuperado desde Flutter: $usuario")
                }
            }
            
            // 4️⃣ deviceId
            var deviceId = prefs.getString("last_deviceId", "") ?: ""
            if (deviceId.isEmpty() || deviceId == "unknown") {
                val deviceIdFromFlutter = flutterPrefs.getString("flutter.deviceId", null)
                if (!deviceIdFromFlutter.isNullOrEmpty() && deviceIdFromFlutter != "unknown") {
                    deviceId = deviceIdFromFlutter
                    prefs.edit().putString("last_deviceId", deviceId).apply()
                    Log.i(TAG, "✅ [FCM] deviceId recuperado desde Flutter: $deviceId")
                }
            }
            
            val intervalMinutes = prefs.getInt("last_intervalMinutes", 5)
            val isDisabled = ServiceStatusFlags.isServiceDisabled(this)
            
            // 🆕 RESPETAR AMBIENTE: Leer isDevelopment y calcular URL correcta
            val isDevelopment = flutterPrefs.getBoolean("flutter.isDevelopment", false)
            val devUrl = "https://sgm.riogas.com.uy/appservices/"
            val prodUrl = "https://www.riogas.uy/ica_geos_/appservices/"
            val correctUrl = if (isDevelopment) devUrl else prodUrl
            
            Log.i(TAG, "🔧 [FCM] Ambiente: ${if (isDevelopment) "DESARROLLO" else "PRODUCCIÓN"}")
            Log.i(TAG, "🔧 [FCM] URL a usar: $correctUrl")
            
            // Guardar URL correcta en FlutterSharedPreferences para que el servicio la lea
            flutterPrefs.edit().putString("flutter.baseUrl", correctUrl).apply()
            Log.i(TAG, "✅ [FCM] BaseUrl actualizada según ambiente antes de reiniciar servicio")

            CriticalLogger.logCritical(
                TAG,
                "FCM: Iniciando restart_gps_service desde FCM push (FORZADO)",
                mapOf(
                    "movil" to movil,
                    "escenario" to escenario,
                    "usuario" to usuario,
                    "deviceId" to deviceId,
                    "interval" to intervalMinutes,
                    "service_disabled_flag" to isDisabled.toString(),
                    "ambiente" to if (isDevelopment) "DESARROLLO" else "PRODUCCIÓN",
                    "url" to correctUrl,
                    "step" to "1_validating_data",
                    "trigger" to "fcm_remote_command",
                    "note" to "Servicio se iniciará incluso con movil=0"
                ),
                "FCM_RESTART_GPS_INITIATED"
            )

            // ⚠️ IMPORTANTE: FCM restart_gps_service SIEMPRE reinicia (incluso con movil="0")
            // Ignora service_disabled porque es un comando remoto explícito del servidor
            // Si estaba deshabilitado, lo habilitamos automáticamente
            if (isDisabled) {
                Log.i(TAG, "ℹ️ [FCM] Servicio estaba deshabilitado, habilitándolo por comando FCM...")
                CriticalLogger.logCritical(
                    TAG,
                    "FCM: Servicio estaba deshabilitado, habilitándolo automáticamente",
                    mapOf(
                        "movil" to movil,
                        "trigger" to "fcm_remote_command",
                        "previous_state" to "disabled",
                        "new_state" to "enabled_by_fcm"
                    ),
                    "FCM_RESTART_GPS_ENABLING_SERVICE"
                )
            }

            // 1️⃣ Limpiar estados Y re-habilitar watchdog
            ServiceStatusFlags.setServiceDisabled(this, false, "FCM restart_gps_service")
            ServiceStatusFlags.setWatchdogDisabled(this, false, "FCM restart_gps_service")  // ✅ Re-habilitar watchdog
            ServiceStatusFlags.setServicePaused(this, false, "FCM restart_gps_service")
            prefs.edit().apply {
                remove("stop_reason")
                remove("stop_timestamp")
                remove("auto_stopped")
                remove("stopped_by_user")
                remove("stopped_from_device")
                remove("resume_time")
                remove("pause_minutes")
            }.apply()

            Log.i(TAG, "🧹 [FCM] Estados limpiados + Watchdog re-habilitado")
            CriticalLogger.logCritical(
                TAG,
                "FCM: Estados de servicio limpiados + Watchdog re-habilitado",
                mapOf(
                    "movil" to movil,
                    "step" to "2_states_cleared",
                    "trigger" to "fcm_remote_command",
                    "service_disabled_flag" to "false",
                    "watchdog_disabled_flag" to "false",
                    "note" to "Watchdog ahora protegerá el servicio automáticamente"
                ),
                "FCM_RESTART_GPS_STATES_CLEARED"
            )

            // 2️⃣ Cancelar AlarmManager anterior
            try {
                val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val alarmIntent = Intent(this, com.example.moveit.LocationReceiver::class.java)
                val pendingIntent = PendingIntent.getBroadcast(
                    this,
                    1710,
                    alarmIntent,
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                )
                if (pendingIntent != null) {
                    alarmManager.cancel(pendingIntent)
                    Log.i(TAG, "🧹 [FCM] AlarmManager anterior cancelado")
                    CriticalLogger.logCritical(
                        TAG,
                        "FCM: AlarmManager anterior cancelado",
                        mapOf(
                            "movil" to movil,
                            "step" to "3_alarm_cancelled",
                            "trigger" to "fcm_remote_command"
                        ),
                        "FCM_RESTART_GPS_ALARM_CANCELLED"
                    )
                }
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ [FCM] Error cancelando alarma: ${e.message}")
                CriticalLogger.logCritical(
                    TAG,
                    "FCM ERROR: Error cancelando AlarmManager",
                    e,
                    mapOf(
                        "movil" to movil,
                        "error_message" to (e.message ?: "Sin mensaje"),
                        "trigger" to "fcm_remote_command"
                    ),
                    "FCM_RESTART_GPS_ALARM_ERROR"
                )
            }

            // 3️⃣ Cancelar WorkManager anterior
            try {
                com.example.moveit.WorkManagerHelper.cancelPeriodicWork(this)
                Log.i(TAG, "🧹 [FCM] WorkManager anterior cancelado")
                CriticalLogger.logCritical(
                    TAG,
                    "FCM: WorkManager anterior cancelado",
                    mapOf(
                        "movil" to movil,
                        "step" to "4_workmanager_cancelled",
                        "trigger" to "fcm_remote_command"
                    ),
                    "FCM_RESTART_GPS_WORKMANAGER_CANCELLED"
                )
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ [FCM] Error cancelando WorkManager: ${e.message}")
                CriticalLogger.logCritical(
                    TAG,
                    "FCM ERROR: Error cancelando WorkManager",
                    e,
                    mapOf(
                        "movil" to movil,
                        "error_message" to (e.message ?: "Sin mensaje"),
                        "trigger" to "fcm_remote_command"
                    ),
                    "FCM_RESTART_GPS_WORKMANAGER_ERROR"
                )
            }

            // 4️⃣ MATAR servicio existente ANTES de iniciar uno nuevo (evitar duplicación)
            try {
                val existingServiceIntent = Intent(this, ForegroundLocationService::class.java)
                stopService(existingServiceIntent)
                Log.i(TAG, "🔪 [FCM] Servicio GPS existente detenido para evitar duplicación")
                Thread.sleep(500)  // Dar tiempo para que el servicio se detenga completamente
                CriticalLogger.logCritical(
                    TAG,
                    "FCM: Servicio GPS existente detenido",
                    mapOf(
                        "movil" to movil,
                        "step" to "5_kill_existing_service",
                        "trigger" to "fcm_remote_command",
                        "reason" to "prevent_duplication"
                    ),
                    "FCM_RESTART_GPS_KILLED_OLD_SERVICE"
                )
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ [FCM] Error deteniendo servicio existente: ${e.message}")
            }

            // 5️⃣ Iniciar ForegroundLocationService NUEVO
            val serviceIntent = Intent(this, ForegroundLocationService::class.java).apply {
                putExtra("movil", movil)
                putExtra("escenario", escenario)
                putExtra("usuario", usuario)
                putExtra("deviceId", deviceId)
                putExtra("intervalMinutes", intervalMinutes)
                putExtra("EXECUTE_GPS", false)
                putExtra("IS_FCM_RESTART", true) // Marcar que es reinicio por FCM
            }

            CriticalLogger.logCritical(
                TAG,
                "FCM: Iniciando ForegroundLocationService",
                mapOf(
                    "movil" to movil,
                    "step" to "6_starting_service",
                    "trigger" to "fcm_remote_command",
                    "execute_gps" to "false"
                ),
                "FCM_RESTART_GPS_STARTING_SERVICE"
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }

            Log.i(TAG, "✅ [FCM] GPS service reiniciado exitosamente desde FCM")
            CriticalLogger.logCritical(
                TAG,
                "FCM EXITOSO: GPS service reiniciado desde push remoto",
                mapOf(
                    "movil" to movil,
                    "escenario" to escenario,
                    "usuario" to usuario,
                    "step" to "7_restart_complete",
                    "trigger" to "fcm_remote_command",
                    "android_version" to Build.VERSION.SDK_INT,
                    "manufacturer" to Build.MANUFACTURER,
                    "model" to Build.MODEL
                ),
                "FCM_RESTART_GPS_SUCCESS"
            )

        } catch (e: Exception) {
            Log.e(TAG, "❌ [FCM] Error reiniciando GPS service", e)
            CriticalLogger.logCritical(
                TAG,
                "FCM ERROR CRÍTICO: Error reiniciando GPS service",
                e,
                mapOf(
                    "error_type" to e.javaClass.simpleName,
                    "error_message" to (e.message ?: "Sin mensaje"),
                    "stack_trace" to e.stackTraceToString().take(500),
                    "trigger" to "fcm_remote_command"
                ),
                "FCM_RESTART_GPS_EXCEPTION"
            )
        }
    }

    /**
     * 🛑 COMANDO: stop_gps_service
     * Detiene el GPS service Y deshabilita el watchdog para que no lo reinicie
     */
    private fun handleStopGpsService(remoteMessage: RemoteMessage) {
        Log.i(TAG, "🛑 [FCM] Ejecutando stop_gps_service...")
        
        val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
        val movil = prefs.getString("last_movil", "unknown") ?: "unknown"

        try {
            val serviceIntent = Intent(this, ForegroundLocationService::class.java)
            stopService(serviceIntent)

            // Marcar servicio como deshabilitado Y deshabilitar watchdog
            ServiceStatusFlags.setServiceDisabled(this, true, "FCM stop_gps_service")
            ServiceStatusFlags.setWatchdogDisabled(this, true, "FCM stop_gps_service")  // 🚫 Watchdog no reiniciará

            Log.i(TAG, "✅ [FCM] GPS service detenido exitosamente + Watchdog deshabilitado")
            CriticalLogger.logCritical(
                TAG,
                "FCM: GPS service detenido desde push remoto + Watchdog deshabilitado",
                mapOf(
                    "movil" to movil,
                    "trigger" to "fcm_remote_command",
                    "action" to "stop_gps_service",
                    "service_disabled_flag" to "true",
                    "watchdog_disabled_flag" to "true",
                    "note" to "Solo restart_gps_service puede volver a iniciarlo"
                ),
                "FCM_STOP_GPS_SUCCESS"
            )
        } catch (e: Exception) {
            Log.e(TAG, "❌ [FCM] Error deteniendo GPS service", e)
            CriticalLogger.logCritical(
                TAG,
                "FCM ERROR: Error deteniendo GPS service",
                e,
                mapOf(
                    "movil" to movil,
                    "error_message" to (e.message ?: "Sin mensaje"),
                    "trigger" to "fcm_remote_command"
                ),
                "FCM_STOP_GPS_ERROR"
            )
        }
    }

    /**
     * ⚡ COMANDO: force_gps_execution
     * Fuerza una ejecución inmediata del GPS
     * Si el servicio está muerto, lo reinicia primero
     * Si el servicio está vivo, lo MATA y lo reinicia con datos frescos
     */
    private fun handleForceGpsExecution(remoteMessage: RemoteMessage) {
        Log.i(TAG, "⚡ [FCM] Ejecutando force_gps_execution (MODO EMERGENCIA)...")
        
        // � FUERZA DE EMERGENCIA: NO verificar sesión, este comando SIEMPRE ejecuta
        // Este comando está diseñado para recuperar dispositivos en estado corrupto
        Log.w(TAG, "🚨 [FORCE_GPS] Comando de emergencia - ignorando verificación de sesión")
        
        val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        
        // 🆕 OBTENER DATOS CON FALLBACK A FLUTTER - SIEMPRE recuperar datos frescos
        // 1️⃣ movil - Default "0" si no se encuentra
        var movil = prefs.getString("last_movil", "0") ?: "0"
        if (movil.isEmpty() || movil == "unknown") {
            movil = "0"
        }
        if (movil == "0") {
            val movilFromFlutter = flutterPrefs.getString("flutter.movil", null)
            if (!movilFromFlutter.isNullOrEmpty() && movilFromFlutter != "unknown" && movilFromFlutter != "0") {
                movil = movilFromFlutter
                prefs.edit().putString("last_movil", movil).apply()
                Log.i(TAG, "✅ [FCM] movil recuperado desde Flutter: $movil")
            } else {
                Log.w(TAG, "⚠️ [FCM] movil no disponible, usando \"0\" (el servicio se iniciará igual)")
            }
        }

        // 2️⃣ escenario
        var escenario = prefs.getString("last_escenario", "0") ?: "0"
        if (escenario.isEmpty() || escenario == "unknown") {
            escenario = "0"
        }
        if (escenario == "0") {
            val escenarioFromFlutter = flutterPrefs.getString("flutter.escenario", null)
            if (!escenarioFromFlutter.isNullOrEmpty() && escenarioFromFlutter != "unknown") {
                escenario = escenarioFromFlutter
                prefs.edit().putString("last_escenario", escenario).apply()
                Log.i(TAG, "✅ [FCM] escenario recuperado desde Flutter: $escenario")
            }
        }
        
        // 3️⃣ usuario
        var usuario = prefs.getString("last_usuario", "") ?: ""
        if (usuario.isEmpty() || usuario == "unknown") {
            val usuarioFromFlutter = flutterPrefs.getString("flutter.username", null)
            if (!usuarioFromFlutter.isNullOrEmpty() && usuarioFromFlutter != "unknown") {
                usuario = usuarioFromFlutter
                prefs.edit().putString("last_usuario", usuario).apply()
                Log.i(TAG, "✅ [FCM] usuario recuperado desde Flutter: $usuario")
            }
        }
        
        // 4️⃣ deviceId
        var deviceId = prefs.getString("last_deviceId", "") ?: ""
        if (deviceId.isEmpty() || deviceId == "unknown") {
            val deviceIdFromFlutter = flutterPrefs.getString("flutter.deviceId", null)
            if (!deviceIdFromFlutter.isNullOrEmpty() && deviceIdFromFlutter != "unknown") {
                deviceId = deviceIdFromFlutter
                prefs.edit().putString("last_deviceId", deviceId).apply()
                Log.i(TAG, "✅ [FCM] deviceId recuperado desde Flutter: $deviceId")
            }
        }
        
        val intervalMinutes = prefs.getInt("last_intervalMinutes", 5)

        // 🚨 PASO 1: LIMPIAR FLAGS DE BLOQUEO (service_disabled, watchdog_disabled)
        Log.i(TAG, "🧹 [FORCE_GPS] Limpiando flags de bloqueo...")
        ServiceStatusFlags.setServiceDisabled(this, false, "FCM force_gps_execution")
        ServiceStatusFlags.setWatchdogDisabled(this, false, "FCM force_gps_execution")
        prefs.edit().apply {
            remove("stop_reason")
            remove("stop_timestamp")
            remove("auto_stopped")
        }.apply()
        Log.i(TAG, "✅ [FORCE_GPS] Flags limpiados: service_disabled=false, watchdog_disabled=false")

        CriticalLogger.logCritical(
            TAG,
            "FORCE_GPS: Flags de bloqueo limpiados",
            mapOf(
                "service_disabled_flag" to "false",
                "watchdog_disabled_flag" to "false",
                "movil" to movil,
                "trigger" to "fcm_force_gps_execution"
            ),
            "FORCE_GPS_FLAGS_CLEARED"
        )
        
        // 🚨 PASO 2: ENVIAR COORDENADA FORZADA INMEDIATA
        Log.i(TAG, "📍 [FORCE_GPS] Enviando coordenada FORZADA inmediata...")
        try {
            // Obtener ubicación actual
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as? android.location.LocationManager
            val lastKnownLocation = try {
                locationManager?.getLastKnownLocation(android.location.LocationManager.GPS_PROVIDER)
                    ?: locationManager?.getLastKnownLocation(android.location.LocationManager.NETWORK_PROVIDER)
            } catch (e: SecurityException) {
                Log.e(TAG, "❌ [FORCE_GPS] Error de permisos obteniendo ubicación: ${e.message}")
                null
            }
            
            if (lastKnownLocation != null) {
                val lat = lastKnownLocation.latitude
                val lon = lastKnownLocation.longitude
                val speed = if (lastKnownLocation.hasSpeed()) lastKnownLocation.speed else 0f
                val accuracy = if (lastKnownLocation.hasAccuracy()) lastKnownLocation.accuracy else 0f
                
                Log.i(TAG, "📍 [FORCE_GPS] Ubicación obtenida: lat=$lat, lon=$lon, speed=$speed, accuracy=$accuracy")
                
                // Convertir a UTM
                val (utmX, utmY) = LocationHelper.convertToUTM(lat, lon)
                
                // Enviar coordenada usando el número de móvil guardado (igual que PRIMERA)
                LocationHelper.invokeRegistrarCoordenadasV2ApiWithRetry(
                    context = this,
                    lat = lat,
                    lon = lon,
                    utmX = utmX,
                    utmY = utmY,
                    totalDistance = 0f,  // Distancia 0 para coordenada forzada
                    speed = speed,
                    movil = movil,  // 🚨 Usar número de móvil guardado (igual que PRIMERA)
                    escenario = escenario,
                    usuario = usuario,
                    deviceId = deviceId,
                    providerUsed = lastKnownLocation.provider ?: "UNKNOWN",
                    movementType = "FORZADA",  // 🚨 Solo esto identifica que es forzada
                    retryCount = 0
                )
                
                Log.i(TAG, "✅ [FORCE_GPS] Coordenada FORZADA enviada exitosamente")
                CriticalLogger.logCritical(
                    TAG,
                    "FORCE_GPS: Coordenada FORZADA enviada",
                    mapOf(
                        "movil" to movil,
                        "escenario" to escenario,
                        "lat" to lat.toString(),
                        "lon" to lon.toString(),
                        "utmX" to utmX.toString(),
                        "utmY" to utmY.toString(),
                        "speed" to speed.toString(),
                        "accuracy" to accuracy.toString(),
                        "provider" to (lastKnownLocation.provider ?: "UNKNOWN"),
                        "trigger" to "fcm_force_gps_execution"
                    ),
                    "FORCE_GPS_COORDINATE_SENT"
                )
            } else {
                Log.w(TAG, "⚠️ [FORCE_GPS] No se pudo obtener ubicación, continuando con reinicio del servicio")
                CriticalLogger.logCritical(
                    TAG,
                    "FORCE_GPS: No se pudo obtener ubicación para coordenada forzada",
                    mapOf(
                        "reason" to "lastKnownLocation is null",
                        "trigger" to "fcm_force_gps_execution"
                    ),
                    "FORCE_GPS_NO_LOCATION"
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ [FORCE_GPS] Error enviando coordenada forzada: ${e.message}")
            CriticalLogger.logCritical(
                TAG,
                "FORCE_GPS: Error enviando coordenada forzada",
                mapOf(
                    "error" to (e.message ?: "Unknown"),
                    "stackTrace" to (e.stackTraceToString()),
                    "trigger" to "fcm_force_gps_execution"
                ),
                "FORCE_GPS_COORDINATE_ERROR"
            )
        }

        try {
            // 🚨 PASO 3: REINICIAR SERVICIO GPS
            // 1️⃣ Verificar si el servicio está corriendo
            val isServiceRunning = ServiceWatchdog.isServiceRunning(this, ForegroundLocationService::class.java)
            
            if (!isServiceRunning) {
                Log.w(TAG, "⚠️ [FCM] Servicio GPS muerto, reiniciándolo primero...")
                
                // 🆕 RESPETAR AMBIENTE: Leer isDevelopment y calcular URL correcta
                val isDevelopment = flutterPrefs.getBoolean("flutter.isDevelopment", false)
                val devUrl = "https://sgm.riogas.com.uy/appservices/"
                val prodUrl = "https://www.riogas.uy/ica_geos_/appservices/"
                val correctUrl = if (isDevelopment) devUrl else prodUrl
                
                Log.i(TAG, "🔧 [FCM] Ambiente: ${if (isDevelopment) "DESARROLLO" else "PRODUCCIÓN"}")
                Log.i(TAG, "🔧 [FCM] URL a usar: $correctUrl")
                
                // Guardar URL correcta en FlutterSharedPreferences para que el servicio la lea
                flutterPrefs.edit().putString("flutter.baseUrl", correctUrl).apply()
                Log.i(TAG, "✅ [FCM] BaseUrl actualizada según ambiente antes de reiniciar servicio")
                
                CriticalLogger.logCritical(
                    TAG,
                    "FCM: Servicio GPS muerto, reiniciándolo antes de forzar ejecución",
                    mapOf(
                        "movil" to movil,
                        "trigger" to "fcm_remote_command",
                        "action" to "force_gps_execution",
                        "service_running" to "false",
                        "ambiente" to if (isDevelopment) "DESARROLLO" else "PRODUCCIÓN",
                        "url" to correctUrl
                    ),
                    "FCM_FORCE_GPS_RESTARTING_SERVICE"
                )
                
                // ✅ Flags ya limpiados al inicio del método
                
                val serviceIntent = Intent(this, ForegroundLocationService::class.java).apply {
                    putExtra("movil", movil)
                    putExtra("escenario", escenario)
                    putExtra("usuario", usuario)
                    putExtra("deviceId", deviceId)
                    putExtra("intervalMinutes", intervalMinutes)
                    putExtra("EXECUTE_GPS", true)  // ✅ Ejecutar GPS inmediatamente
                    putExtra("IS_FCM_FORCE", true)  // Marcar que es fuerza de ejecución
                }
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
                
                Log.i(TAG, "✅ [FCM] Servicio reiniciado con ejecución inmediata")
                CriticalLogger.logCritical(
                    TAG,
                    "FCM: Servicio reiniciado + GPS execution forzada",
                    mapOf(
                        "movil" to movil,
                        "trigger" to "fcm_remote_command",
                        "action" to "force_gps_execution",
                        "service_was_dead" to "true",
                        "execute_gps_immediately" to "true"
                    ),
                    "FCM_FORCE_GPS_SUCCESS_WITH_RESTART"
                )
                
            } else {
                // 2️⃣ Servicio está corriendo - MATARLO primero y reiniciar con datos frescos
                Log.i(TAG, "🔪 [FCM] Servicio activo detectado, MATÁNDOLO para reiniciar con datos frescos...")
                
                try {
                    val existingServiceIntent = Intent(this, ForegroundLocationService::class.java)
                    stopService(existingServiceIntent)
                    Log.i(TAG, "🔪 [FCM] Servicio GPS existente detenido")
                    Thread.sleep(500)  // Dar tiempo para que el servicio se detenga completamente
                    
                    CriticalLogger.logCritical(
                        TAG,
                        "FCM: Servicio GPS activo detenido para forzar ejecución con datos frescos",
                        mapOf(
                            "movil" to movil,
                            "trigger" to "fcm_remote_command",
                            "action" to "force_gps_execution",
                            "service_was_running" to "true",
                            "reason" to "force_execution_with_fresh_data"
                        ),
                        "FCM_FORCE_GPS_KILLED_SERVICE"
                    )
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ [FCM] Error deteniendo servicio: ${e.message}")
                }
                
                // Reiniciar con datos frescos y ejecutar GPS inmediatamente
                val isDevelopment = flutterPrefs.getBoolean("flutter.isDevelopment", false)
                val devUrl = "https://sgm.riogas.com.uy/appservices/"
                val prodUrl = "https://www.riogas.uy/ica_geos_/appservices/"
                val correctUrl = if (isDevelopment) devUrl else prodUrl
                flutterPrefs.edit().putString("flutter.baseUrl", correctUrl).apply()
                
                val serviceIntent = Intent(this, ForegroundLocationService::class.java).apply {
                    putExtra("movil", movil)
                    putExtra("escenario", escenario)
                    putExtra("usuario", usuario)
                    putExtra("deviceId", deviceId)
                    putExtra("intervalMinutes", intervalMinutes)
                    putExtra("EXECUTE_GPS", true)  // ✅ Ejecutar GPS inmediatamente
                    putExtra("IS_FCM_FORCE", true)  // Marcar que es fuerza de ejecución
                }
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }

                Log.i(TAG, "✅ [FCM] GPS execution forzada exitosamente (servicio reiniciado)")
                CriticalLogger.logCritical(
                    TAG,
                    "FCM: GPS execution forzada desde push remoto (servicio reiniciado)",
                    mapOf(
                        "movil" to movil,
                        "trigger" to "fcm_remote_command",
                        "action" to "force_gps_execution",
                        "service_was_running" to "true",
                        "method" to "kill_and_restart_service"
                    ),
                    "FCM_FORCE_GPS_SUCCESS"
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ [FCM] Error forzando GPS execution", e)
            CriticalLogger.logCritical(
                TAG,
                "FCM ERROR: Error forzando GPS execution",
                e,
                mapOf(
                    "movil" to movil,
                    "error_message" to (e.message ?: "Sin mensaje"),
                    "trigger" to "fcm_remote_command"
                ),
                "FCM_FORCE_GPS_ERROR"
            )
        }
    }

    /**
     * 📊 COMANDO: get_status
     * Reporta el estado actual del servicio
     */
    private fun handleGetStatus(remoteMessage: RemoteMessage) {
        Log.i(TAG, "📊 [FCM] Ejecutando get_status...")
        
        val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
        val movil = prefs.getString("last_movil", "unknown") ?: "unknown"
        val escenario = prefs.getString("last_escenario", "") ?: ""
        val usuario = prefs.getString("last_usuario", "") ?: ""
        val isDisabled = ServiceStatusFlags.isServiceDisabled(this)
        val isPaused = ServiceStatusFlags.isServicePaused(this)
        val intervalMinutes = prefs.getInt("last_intervalMinutes", 5)

        CriticalLogger.logCritical(
            TAG,
            "FCM: Reporte de estado del GPS service",
            mapOf(
                "movil" to movil,
                "escenario" to escenario,
                "usuario" to usuario,
                "service_disabled_flag" to isDisabled.toString(),
                "service_paused_flag" to isPaused.toString(),
                "interval_minutes" to intervalMinutes,
                "android_version" to Build.VERSION.SDK_INT,
                "manufacturer" to Build.MANUFACTURER,
                "model" to Build.MODEL,
                "trigger" to "fcm_remote_command",
                "action" to "get_status"
            ),
            "FCM_GET_STATUS_REPORT"
        )
    }

    /**
     * 🚪 COMANDO: logout_user
     * Cierra la sesión del usuario remotamente (igual que cierre manual desde settings)
     * 
     * Este comando:
     * 1. Detiene todos los servicios (GPS y CriticalLog)
     * 2. Registra el cierre en el servidor
     * 3. Limpia documentos de Firestore (sesiones)
     * 4. Llama a Flutter para que complete el flujo de logout
     * 5. NO cierra la app - Flutter lo hace después de limpiar Hive
     */
    private fun handleLogoutUser(remoteMessage: RemoteMessage) {
        Log.i(TAG, "🚪 [FCM] Ejecutando logout_user remoto...")
        
        try {
            val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
            val movil = prefs.getString("last_movil", "") ?: ""
            val escenario = prefs.getString("last_escenario", "") ?: ""
            val usuario = prefs.getString("last_usuario", "") ?: ""
            val deviceId = prefs.getString("last_deviceId", "") ?: ""
            
            Log.i(TAG, "🚪 [FCM] Datos de sesión: movil=$movil, usuario=$usuario, deviceId=$deviceId")
            
            CriticalLogger.logCritical(
                TAG,
                "FCM: Iniciando cierre de sesión remoto",
                mapOf(
                    "movil" to movil,
                    "escenario" to escenario,
                    "usuario" to usuario,
                    "deviceId" to deviceId,
                    "trigger" to "fcm_remote_command",
                    "action" to "logout_user",
                    "logout_type" to "remote_logout"
                ),
                "FCM_LOGOUT_INITIATED"
            )
            
            // 1️⃣ Detener GPS Service
            try {
                val serviceIntent = Intent(this, ForegroundLocationService::class.java)
                stopService(serviceIntent)
                Log.i(TAG, "🛑 [FCM] GPS service detenido")
                
                CriticalLogger.logCritical(
                    TAG,
                    "FCM: GPS service detenido por logout remoto",
                    mapOf(
                        "movil" to movil,
                        "step" to "1_stop_gps_service"
                    ),
                    "FCM_LOGOUT_GPS_STOPPED"
                )
            } catch (e: Exception) {
                Log.e(TAG, "❌ [FCM] Error deteniendo GPS service", e)
            }
            
            // 2️⃣ Cancelar AlarmManager (LocationReceiver)
            try {
                val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val alarmIntent = Intent(this, com.example.moveit.LocationReceiver::class.java)
                val pendingIntent = PendingIntent.getBroadcast(
                    this,
                    1710,
                    alarmIntent,
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                )
                if (pendingIntent != null) {
                    alarmManager.cancel(pendingIntent)
                    Log.i(TAG, "🛑 [FCM] AlarmManager cancelado")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ [FCM] Error cancelando AlarmManager", e)
            }
            
            // 3️⃣ Cancelar CriticalLogAlarmReceiver
            try {
                CriticalLogAlarmReceiver.cancel(this)
                Log.i(TAG, "🛑 [FCM] CriticalLogAlarmReceiver cancelado")
                
                CriticalLogger.logCritical(
                    TAG,
                    "FCM: CriticalLogAlarmReceiver cancelado por logout remoto",
                    mapOf(
                        "movil" to movil,
                        "step" to "2_stop_critical_log"
                    ),
                    "FCM_LOGOUT_CRITICALLOG_STOPPED"
                )
            } catch (e: Exception) {
                Log.e(TAG, "❌ [FCM] Error cancelando CriticalLogAlarmReceiver", e)
            }
            
            // 4️⃣ Marcar servicio como deshabilitado Y deshabilitar watchdog
            ServiceStatusFlags.setServiceDisabled(this, true, "FCM remote logout")
            ServiceStatusFlags.setWatchdogDisabled(this, true, "FCM remote logout")  // 🚫 Watchdog no reiniciará
            prefs.edit().apply {
                putString("stop_reason", "FCM remote logout")
                putLong("stop_timestamp", System.currentTimeMillis())
                putBoolean("auto_stopped", false)
                putBoolean("stopped_by_user", true)
                putBoolean("stopped_from_device", false)
            }.apply()

            Log.i(TAG, "🚫 [FCM] Servicios deshabilitados + Watchdog deshabilitado")

            CriticalLogger.logCritical(
                TAG,
                "FCM: Servicios deshabilitados por logout remoto",
                mapOf(
                    "movil" to movil,
                    "step" to "3_disable_services",
                    "service_disabled_flag" to "true",
                    "watchdog_disabled_flag" to "true"
                ),
                "FCM_LOGOUT_SERVICES_DISABLED"
            )
            
            // 5️⃣ Invocar Flutter para completar el flujo de logout
            // Flutter obtendrá los datos (movil, escenario, usuario, deviceId) desde Hive
            // Flutter se encargará de:
            // - Llamar a RioGasService.registrarCierre()
            // - Manejar documentos de Firestore (sesiones)
            // - Llamar a SessionService
            // - Limpiar Hive boxes
            // - Cerrar la aplicación
            try {
                // 🔥 USAR EXPLICIT INTENT hacia MainActivity para que funcione desde background
                val intent = Intent(this, com.example.moveit.MainActivity::class.java).apply {
                    action = "com.riogas.appmovil.REMOTE_LOGOUT"
                    // Flags para traer MainActivity al frente si está en background
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("remote_logout", true)
                    putExtra("timestamp", System.currentTimeMillis())
                }
                
                // Iniciar MainActivity (se recibirá en onNewIntent)
                startActivity(intent)
                
                Log.i(TAG, "📨 [FCM] Activity intent REMOTE_LOGOUT enviado a MainActivity")
                
                CriticalLogger.logCritical(
                    TAG,
                    "FCM: Activity intent REMOTE_LOGOUT enviado a MainActivity para completar logout",
                    mapOf(
                        "movil" to movil,
                        "step" to "4_invoke_flutter_logout",
                        "intent_action" to "com.riogas.appmovil.REMOTE_LOGOUT",
                        "intent_type" to "explicit_activity",
                        "note" to "MainActivity procesará en onNewIntent o onResume"
                    ),
                    "FCM_LOGOUT_FLUTTER_INVOKED"
                )
            } catch (e: Exception) {
                Log.e(TAG, "❌ [FCM] Error enviando broadcast a Flutter", e)
                CriticalLogger.logCritical(
                    TAG,
                    "FCM ERROR: Error enviando broadcast REMOTE_LOGOUT a Flutter",
                    e,
                    mapOf(
                        "movil" to movil,
                        "error_message" to (e.message ?: "Sin mensaje")
                    ),
                    "FCM_LOGOUT_BROADCAST_ERROR"
                )
            }
            
            Log.i(TAG, "✅ [FCM] Logout remoto completado (servicios detenidos, esperando Flutter)")
            
            CriticalLogger.logCritical(
                TAG,
                "FCM EXITOSO: Logout remoto procesado - servicios detenidos, Flutter completará el flujo",
                mapOf(
                    "movil" to movil,
                    "escenario" to escenario,
                    "usuario" to usuario,
                    "deviceId" to deviceId,
                    "step" to "5_logout_complete",
                    "trigger" to "fcm_remote_command",
                    "note" to "Flutter completará limpieza de Hive y cierre de app"
                ),
                "FCM_LOGOUT_SUCCESS"
            )
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ [FCM] Error crítico en logout remoto", e)
            CriticalLogger.logCritical(
                TAG,
                "FCM ERROR CRÍTICO: Error procesando logout remoto",
                e,
                mapOf(
                    "error_type" to e.javaClass.simpleName,
                    "error_message" to (e.message ?: "Sin mensaje"),
                    "stack_trace" to e.stackTraceToString().take(500),
                    "trigger" to "fcm_remote_command"
                ),
                "FCM_LOGOUT_EXCEPTION"
            )
        }
    }
}
