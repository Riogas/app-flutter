package com.riogas.appmovil

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.riogas.appmovil.tracking.LocationTrackingService
import com.example.moveit.LocationHelper
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import java.text.SimpleDateFormat
import java.util.*

/**
 * 🔔 FcmPushReceiver - Recibe push notifications silenciosas desde FCM
 *
 * Permite control remoto del tracking desde el servidor:
 * - restart_tracking (alias legacy: restart_gps_service, force_gps_execution): reinicia LocationTrackingService
 * - stop_tracking (alias legacy: stop_gps_service): detiene LocationTrackingService
 * - get_status: Reporta el estado actual del servicio
 * - logout_user: cierre de sesión remoto
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
            "restart_tracking", "restart_gps_service", "force_gps_execution" -> handleRestartTracking(remoteMessage)
            "stop_tracking", "stop_gps_service" -> handleStopTracking(remoteMessage)
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
     * 🔐 Sesión activa (Firebase) — dueño único de la validación para restart_tracking.
     */
    private fun isSessionValid(): Boolean = LocationHelper.isSessionActive(this)

    /**
     * Lee un campo de identidad de prefs "config" (key last_$field) con fallback a
     * FlutterSharedPreferences (key flutter.$flutterKey). Si se recupera desde Flutter,
     * lo persiste en "config" para las próximas lecturas.
     */
    private fun identityFromPrefs(field: String, flutterKey: String, default: String): String {
        val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        var value = prefs.getString("last_$field", default) ?: default
        if (value.isEmpty() || value == "unknown") value = default
        if (value == default) {
            val fromFlutter = flutterPrefs.getString("flutter.$flutterKey", null)
            if (!fromFlutter.isNullOrEmpty() && fromFlutter != "unknown" && fromFlutter != default) {
                value = fromFlutter
                prefs.edit().putString("last_$field", value).apply()
                Log.i(TAG, "✅ [FCM] $field recuperado desde Flutter: $value")
            }
        }
        return value
    }

    private fun movilFromPrefs(): String = identityFromPrefs("movil", "movil", "0")
    private fun escenarioFromPrefs(): String = identityFromPrefs("escenario", "escenario", "0")
    private fun usuarioFromPrefs(): String = identityFromPrefs("usuario", "username", "")
    private fun deviceIdFromPrefs(): String = identityFromPrefs("deviceId", "deviceId", "")

    /**
     * 🔄 COMANDO: restart_tracking (aliases legacy: restart_gps_service, force_gps_execution)
     * Reinicia LocationTrackingService. Idempotente: si ya corre, start() solo re-entrega
     * extras y re-registra el callback de ubicación (registerLocationUpdates remueve el
     * callback previo, startLoops cancela los jobs previos) — dos llamadas seguidas no
     * duplican nada porque Android reutiliza la instancia única del Service.
     */
    private fun handleRestartTracking(remoteMessage: RemoteMessage) {
        Log.i(TAG, "🔄 [FCM] Ejecutando restart_tracking...")
        try {
            if (!isSessionValid()) {
                Log.w(TAG, "🚫 [FCM] [SESSION] No hay sesión activa, ignorando comando restart_tracking")
                DeviceEventReporter.report(this, "restart_result", "NO_SESSION")
                return
            }

            val movil = movilFromPrefs()
            val escenario = escenarioFromPrefs()
            val usuario = usuarioFromPrefs()
            val deviceId = deviceIdFromPrefs()

            // Habilitar servicio (comando remoto explícito del servidor, ignora disabled/paused previos)
            ServiceStatusFlags.setServiceDisabled(this, false, "restart_tracking FCM")
            ServiceStatusFlags.setServicePaused(this, false, "restart_tracking FCM")
            ServiceStatusFlags.setWatchdogDisabled(this, false, "restart_tracking FCM")

            LocationTrackingService.start(this, movil, escenario, usuario, deviceId)

            Log.i(TAG, "✅ [FCM] restart_tracking OK (movil=$movil)")
            DeviceEventReporter.report(this, "restart_result", "OK",
                mapOf(
                    "movil" to movil,
                    "escenario" to escenario,
                    "usuario" to usuario,
                    "already_running" to LocationTrackingService.isRunning.toString()
                ))
        } catch (e: Exception) {
            // FGS denegado / permiso / GPS off → el server marca "requiere intervencion"
            Log.e(TAG, "❌ [FCM] Error en restart_tracking", e)
            DeviceEventReporter.report(this, "restart_result", "FAILED",
                mapOf("error" to (e.message ?: e.javaClass.simpleName)))
        }
    }

    /**
     * 🛑 COMANDO: stop_tracking (alias legacy: stop_gps_service)
     * Detiene LocationTrackingService y deshabilita el servicio para que nada lo reinicie.
     */
    private fun handleStopTracking(remoteMessage: RemoteMessage) {
        Log.i(TAG, "🛑 [FCM] Ejecutando stop_tracking...")
        try {
            LocationTrackingService.stop(this)
            ServiceStatusFlags.setServiceDisabled(this, true, "stop_tracking FCM")
            Log.i(TAG, "✅ [FCM] LocationTrackingService detenido")
            DeviceEventReporter.report(this, "restart_result", "STOPPED")
        } catch (e: Exception) {
            Log.e(TAG, "❌ [FCM] Error en stop_tracking", e)
            DeviceEventReporter.report(this, "restart_result", "FAILED",
                mapOf("error" to (e.message ?: e.javaClass.simpleName)))
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
                LocationTrackingService.stop(this)
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
            
            // 2️⃣ (Task 7) AlarmManager retirado: ya no hay alarmas de LocationReceiver que cancelar.

            // 3️⃣ Cancelar la subida periódica de logs críticos (WorkManager)
            try {
                CriticalLogUploadWorker.cancel(this)
                Log.i(TAG, "🛑 [FCM] CriticalLogUploadWorker cancelado")

                CriticalLogger.logCritical(
                    TAG,
                    "FCM: CriticalLogUploadWorker cancelado por logout remoto",
                    mapOf(
                        "movil" to movil,
                        "step" to "2_stop_critical_log"
                    ),
                    "FCM_LOGOUT_CRITICALLOG_STOPPED"
                )
            } catch (e: Exception) {
                Log.e(TAG, "❌ [FCM] Error cancelando CriticalLogUploadWorker", e)
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
