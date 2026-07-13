package com.riogas.appmovil

import android.content.Context
import android.util.Log

/**
 * 🚩 ServiceStatusFlags - Sistema centralizado de flags de estado de servicios
 * 
 * PROPÓSITO:
 * - Marcar cuando los servicios (GPS, CriticalLog) detectan que alguno está apagado
 * - Permitir acceso desde Kotlin y Flutter (via SharedPreferences)
 * - Respetar el cierre de sesión del FCM (watchdog_disabled)
 * 
 * FUNCIONAMIENTO:
 * - Cuando un servicio detecta que otro está apagado: setServicesNeedRestart(true)
 * - Cuando un servicio detecta que el otro volvió a estar activo: setServicesNeedRestart(false)
 * - Si watchdog_disabled=true (cierre sesión FCM): NO modificar la flag
 * 
 * ACCESO DESDE FLUTTER:
 * - Via método channel o SharedPreferences directamente
 */
object ServiceStatusFlags {
    
    private const val TAG = "ServiceStatusFlags"
    private const val PREFS_NAME = "config"
    private const val KEY_SERVICES_NEED_RESTART = "services_need_restart"
    private const val KEY_LAST_CHECK_TIMESTAMP = "services_last_check_timestamp"
    private const val KEY_GPS_STATUS = "gps_service_status"
    private const val KEY_CRITICAL_LOG_STATUS = "critical_log_service_status"
    
    /**
     * Marca que los servicios necesitan reiniciarse
     * @param needRestart true si algún servicio está apagado, false si todos están activos
     * @param checkerService Nombre del servicio que hace la verificación ("GPS", "CriticalLog", etc)
     * @return true si se actualizó la flag, false si fue bloqueado por watchdog_disabled
     */
    fun setServicesNeedRestart(
        context: Context, 
        needRestart: Boolean,
        checkerService: String = "Unknown",
        reason: String = ""
    ): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        
        // 🚫 VALIDACIÓN: No modificar si watchdog está deshabilitado (cierre de sesión FCM)
        val watchdogDisabled = prefs.getBoolean("watchdog_disabled", false)
        if (watchdogDisabled) {
            Log.w(TAG, "⚠️ Flag NO actualizada: watchdog deshabilitado por cierre de sesión FCM")
            CriticalLogger.logCritical(
                TAG,
                "FLAGS: Intento de actualizar flag bloqueado por watchdog_disabled",
                mapOf(
                    "wanted_value" to needRestart.toString(),
                    "checker_service" to checkerService,
                    "reason" to reason,
                    "watchdog_disabled" to "true",
                    "blocked" to "true"
                ),
                "FLAG_UPDATE_BLOCKED"
            )
            return false
        }
        
        val previousValue = prefs.getBoolean(KEY_SERVICES_NEED_RESTART, false)
        val timestamp = System.currentTimeMillis()
        
        prefs.edit().apply {
            putBoolean(KEY_SERVICES_NEED_RESTART, needRestart)
            putLong(KEY_LAST_CHECK_TIMESTAMP, timestamp)
            putString("services_check_by", checkerService)
            if (reason.isNotEmpty()) {
                putString("services_check_reason", reason)
            }
        }.apply()
        
        // Log solo si el valor cambió
        if (previousValue != needRestart) {
            val emoji = if (needRestart) "🔴" else "🟢"
            Log.i(TAG, "$emoji Flag actualizada: services_need_restart = $needRestart")
            Log.d(TAG, "   - Verificado por: $checkerService")
            Log.d(TAG, "   - Razón: $reason")
            Log.d(TAG, "   - Timestamp: ${java.text.SimpleDateFormat("HH:mm:ss").format(timestamp)}")
            
            CriticalLogger.logCritical(
                TAG,
                "FLAGS: Estado de servicios actualizado - ${if (needRestart) "SERVICIOS APAGADOS" else "SERVICIOS ACTIVOS"}",
                mapOf(
                    "services_need_restart" to needRestart.toString(),
                    "previous_value" to previousValue.toString(),
                    "checker_service" to checkerService,
                    "reason" to reason,
                    "timestamp" to timestamp.toString(),
                    "changed" to "true"
                ),
                "FLAG_UPDATED"
            )
        } else {
            Log.v(TAG, "Flag sin cambios: services_need_restart = $needRestart (verificado por $checkerService)")
        }
        
        return true
    }
    
    /**
     * Obtiene el estado actual de la flag
     * @return true si los servicios necesitan reiniciarse, false si están todos activos
     */
    fun getServicesNeedRestart(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_SERVICES_NEED_RESTART, false)
    }
    
    /**
     * Actualiza el estado individual del GPS Service
     * @param isRunning true si el servicio GPS está corriendo, false si está apagado
     */
    fun setGPSServiceStatus(context: Context, isRunning: Boolean, checkedBy: String = "Unknown") {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val watchdogDisabled = prefs.getBoolean("watchdog_disabled", false)
        
        if (watchdogDisabled) {
            Log.v(TAG, "GPS status no actualizado: watchdog deshabilitado")
            return
        }
        
        prefs.edit().apply {
            putBoolean(KEY_GPS_STATUS, isRunning)
            putLong("gps_status_timestamp", System.currentTimeMillis())
            putString("gps_status_checked_by", checkedBy)
        }.apply()
        
        Log.v(TAG, "${if (isRunning) "🟢" else "🔴"} GPS Service: ${if (isRunning) "Running" else "Stopped"} (checado por $checkedBy)")
    }
    
    /**
     * Actualiza el estado individual del CriticalLog Service
     * @param isScheduled true si CriticalLogAlarmReceiver está programado, false si no
     */
    fun setCriticalLogServiceStatus(context: Context, isScheduled: Boolean, checkedBy: String = "Unknown") {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val watchdogDisabled = prefs.getBoolean("watchdog_disabled", false)
        
        if (watchdogDisabled) {
            Log.v(TAG, "CriticalLog status no actualizado: watchdog deshabilitado")
            return
        }
        
        prefs.edit().apply {
            putBoolean(KEY_CRITICAL_LOG_STATUS, isScheduled)
            putLong("critical_log_status_timestamp", System.currentTimeMillis())
            putString("critical_log_status_checked_by", checkedBy)
        }.apply()
        
        Log.v(TAG, "${if (isScheduled) "🟢" else "🔴"} CriticalLog Alarm: ${if (isScheduled) "Scheduled" else "Not Scheduled"} (checado por $checkedBy)")
    }
    
    /**
     * Obtiene el estado completo de todos los servicios
     */
    fun getFullStatus(context: Context): Map<String, Any> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        
        return mapOf(
            "services_need_restart" to prefs.getBoolean(KEY_SERVICES_NEED_RESTART, false),
            "last_check_timestamp" to prefs.getLong(KEY_LAST_CHECK_TIMESTAMP, 0),
            "checked_by" to (prefs.getString("services_check_by", "Unknown") ?: "Unknown"),
            "check_reason" to (prefs.getString("services_check_reason", "") ?: ""),
            "gps_service_status" to prefs.getBoolean(KEY_GPS_STATUS, false),
            "gps_status_timestamp" to prefs.getLong("gps_status_timestamp", 0),
            "gps_checked_by" to (prefs.getString("gps_status_checked_by", "Unknown") ?: "Unknown"),
            "critical_log_status" to prefs.getBoolean(KEY_CRITICAL_LOG_STATUS, false),
            "critical_log_timestamp" to prefs.getLong("critical_log_status_timestamp", 0),
            "critical_log_checked_by" to (prefs.getString("critical_log_status_checked_by", "Unknown") ?: "Unknown"),
            "watchdog_disabled" to prefs.getBoolean("watchdog_disabled", false)
        )
    }
    
    /**
     * Limpia todas las flags (útil en login o reinicio completo)
     */
    fun clearAllFlags(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().apply {
            remove(KEY_SERVICES_NEED_RESTART)
            remove(KEY_LAST_CHECK_TIMESTAMP)
            remove("services_check_by")
            remove("services_check_reason")
            remove(KEY_GPS_STATUS)
            remove("gps_status_timestamp")
            remove("gps_status_checked_by")
            remove(KEY_CRITICAL_LOG_STATUS)
            remove("critical_log_status_timestamp")
            remove("critical_log_status_checked_by")
        }.apply()
        
        Log.i(TAG, "🧹 Todas las flags de servicios limpiadas")
    }
}
