package com.riogas.appmovil

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write

/**
 * Sistema de logging condicional para diagnóstico remoto del servicio GPS
 * 
 * CARACTERÍSTICAS:
 * - Buffer circular de hasta 100 logs para evitar consumo excesivo de memoria
 * - Niveles: INFO, WARN, ERROR
 * - Exportación a JSON para envío al servidor
 * - Activación/desactivación remota mediante flag en SharedPreferences
 * - Thread-safe usando ReadWriteLock
 */
object DebugLogger {
    
    private const val TAG = "DebugLogger"
    private const val MAX_LOGS = 100
    private const val PREFS_NAME = "debug_logger_prefs"
    private const val KEY_DEBUG_ENABLED = "debug_enabled"
    
    data class LogEntry(
        val timestamp: Long,
        val level: String,
        val tag: String,
        val message: String,
        val extras: Map<String, Any> = emptyMap()
    )
    
    private val logs = mutableListOf<LogEntry>()
    private val lock = ReentrantReadWriteLock()
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
    
    private var context: Context? = null
    private var prefs: SharedPreferences? = null
    
    /**
     * Inicializa el logger con el contexto de la aplicación
     * Debe llamarse una vez al inicio de la app
     */
    fun init(appContext: Context) {
        context = appContext.applicationContext
        prefs = context?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        Log.d(TAG, "DebugLogger inicializado. Estado: ${if (isEnabled()) "ACTIVO" else "INACTIVO"}")
    }
    
    /**
     * Verifica si el logging está habilitado
     */
    fun isEnabled(): Boolean {
        return prefs?.getBoolean(KEY_DEBUG_ENABLED, false) ?: false
    }
    
    /**
     * Habilita o deshabilita el logging
     * Llamado desde MainActivity cuando Flutter comunica cambio de flag
     */
    fun setEnabled(enabled: Boolean) {
        prefs?.edit()?.putBoolean(KEY_DEBUG_ENABLED, enabled)?.apply()
        Log.d(TAG, "Debug logging ${if (enabled) "HABILITADO" else "DESHABILITADO"}")
        
        if (enabled) {
            i("DebugLogger", "Sistema de logging activado", mapOf("timestamp" to System.currentTimeMillis()))
        } else {
            i("DebugLogger", "Sistema de logging desactivado", mapOf("timestamp" to System.currentTimeMillis()))
            // Limpiamos logs al desactivar
            clearLogs()
        }
    }
    
    /**
     * Log nivel INFO
     */
    fun i(tag: String, message: String, extras: Map<String, Any> = emptyMap()) {
        if (!isEnabled()) return
        addLog("INFO", tag, message, extras)
        Log.i(tag, message)
    }
    
    /**
     * Log nivel WARN
     */
    fun w(tag: String, message: String, extras: Map<String, Any> = emptyMap()) {
        if (!isEnabled()) return
        addLog("WARN", tag, message, extras)
        Log.w(tag, message)
    }
    
    /**
     * Log nivel ERROR
     */
    fun e(tag: String, message: String, throwable: Throwable? = null, extras: Map<String, Any> = emptyMap()) {
        if (!isEnabled()) return
        
        val extrasWithError = if (throwable != null) {
            extras + mapOf(
                "error" to throwable.javaClass.simpleName,
                "errorMessage" to (throwable.message ?: ""),
                "stackTrace" to throwable.stackTraceToString().take(500) // Limitar tamaño
            )
        } else {
            extras
        }
        
        addLog("ERROR", tag, message, extrasWithError)
        if (throwable != null) {
            Log.e(tag, message, throwable)
        } else {
            Log.e(tag, message)
        }
    }
    
    /**
     * Agrega un log al buffer circular
     */
    private fun addLog(level: String, tag: String, message: String, extras: Map<String, Any>) {
        lock.write {
            // Buffer circular: si excedemos MAX_LOGS, eliminamos el más antiguo
            if (logs.size >= MAX_LOGS) {
                logs.removeAt(0)
            }
            
            logs.add(LogEntry(
                timestamp = System.currentTimeMillis(),
                level = level,
                tag = tag,
                message = message,
                extras = extras
            ))
        }
    }
    
    /**
     * Obtiene todos los logs en formato JSON para enviar al servidor
     * Formato: { "logs": [...], "metadata": {...} }
     */
    fun getLogsAsJson(): String {
        val logsCopy = lock.read {
            logs.toList()
        }
        
        val jsonArray = JSONArray()
        for (log in logsCopy) {
            val jsonLog = JSONObject()
            jsonLog.put("timestamp", log.timestamp)
            jsonLog.put("timestampFormatted", dateFormat.format(Date(log.timestamp)))
            jsonLog.put("level", log.level)
            jsonLog.put("tag", log.tag)
            jsonLog.put("message", log.message)
            
            if (log.extras.isNotEmpty()) {
                val extrasJson = JSONObject()
                for ((key, value) in log.extras) {
                    extrasJson.put(key, value)
                }
                jsonLog.put("extras", extrasJson)
            }
            
            jsonArray.put(jsonLog)
        }
        
        val result = JSONObject()
        result.put("logs", jsonArray)
        result.put("metadata", JSONObject().apply {
            put("logCount", logsCopy.size)
            put("capturedAt", System.currentTimeMillis())
            put("capturedAtFormatted", dateFormat.format(Date()))
        })
        
        return result.toString()
    }
    
    /**
     * Limpia todos los logs del buffer
     * Llamado después de enviar exitosamente al servidor
     */
    fun clearLogs() {
        lock.write {
            val count = logs.size
            logs.clear()
            Log.d(TAG, "Buffer de logs limpiado ($count logs eliminados)")
        }
    }
    
    /**
     * Obtiene el número actual de logs en buffer
     */
    fun getLogCount(): Int {
        return lock.read {
            logs.size
        }
    }
    
    /**
     * Obtiene estadísticas del buffer
     */
    fun getStats(): Map<String, Any> {
        return lock.read {
            val infoCount = logs.count { it.level == "INFO" }
            val warnCount = logs.count { it.level == "WARN" }
            val errorCount = logs.count { it.level == "ERROR" }
            
            mapOf(
                "total" to logs.size,
                "info" to infoCount,
                "warn" to warnCount,
                "error" to errorCount,
                "enabled" to isEnabled(),
                "oldestLog" to (logs.firstOrNull()?.timestamp ?: 0),
                "newestLog" to (logs.lastOrNull()?.timestamp ?: 0)
            )
        }
    }
}
