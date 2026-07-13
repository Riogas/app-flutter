package com.riogas.appmovil

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write

/**
 * Sistema de logging CRÍTICO para errores que deben monitorearse SIEMPRE
 * 
 * DIFERENCIAS CON DebugLogger:
 * - ✅ Se ejecuta SIEMPRE (no depende de debugMode)
 * - ✅ Solo registra errores CRÍTICOS (no spam de info/debug)
 * - ✅ Buffer más pequeño (50 logs vs 100)
 * - ✅ Se envía a n8n automáticamente cada 5 minutos
 * 
 * CASOS DE USO:
 * - Servicio GPS no puede iniciarse (permisos, restricciones)
 * - API de Riogas falla (HTTP 500, timeout)
 * - Servicio detenido inesperadamente
 * - Errores de LocationManager (GPS sin señal)
 * 
 * IMPORTANTE: Usar SOLO para errores críticos que requieren atención inmediata
 */
object CriticalLogger {
    
    private const val TAG = "CriticalLogger"
    private const val MAX_CRITICAL_LOGS = 50
    private const val PREFS_NAME = "critical_logger_prefs"
    private const val PREF_LAST_CLEANUP_DATE = "last_cleanup_date"
    
    data class CriticalLogEntry(
        val timestamp: Long,
        val tag: String,
        val message: String,
        val extras: Map<String, Any> = emptyMap(),
        val errorType: String = "CRITICAL"
    )
    
    private val logs = mutableListOf<CriticalLogEntry>()
    private val lock = ReentrantReadWriteLock()
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
    private val dateOnlyFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    
    private var context: Context? = null
    
    /**
     * Inicializa el logger con el contexto de la aplicación
     * Debe llamarse una vez al inicio de la app
     */
    fun init(appContext: Context) {
        context = appContext.applicationContext
        Log.d(TAG, "✅ CriticalLogger inicializado (SIEMPRE activo)")
    }
    
    /**
     * Registra un error CRÍTICO que debe ser visible SIEMPRE
     * 
     * @param tag Identificador del componente que genera el log
     * @param message Descripción del error crítico
     * @param extras Datos adicionales contextuales (movil, deviceId, etc.)
     * @param errorType Tipo de error: SERVICE_START_FAILED, API_ERROR, GPS_ERROR, etc.
     */
    fun logCritical(
        tag: String, 
        message: String, 
        extras: Map<String, Any> = emptyMap(),
        errorType: String = "CRITICAL"
    ) {
        // ⚠️ NO hay verificación de isEnabled() - SIEMPRE se ejecuta
        addLog(tag, message, extras, errorType)
        Log.e(tag, "🚨 [CRITICAL] $message")
    }
    
    /**
     * Registra un error crítico con excepción
     */
    fun logCritical(
        tag: String, 
        message: String, 
        throwable: Throwable,
        extras: Map<String, Any> = emptyMap(),
        errorType: String = "CRITICAL"
    ) {
        val extrasWithError = extras + mapOf(
            "error" to throwable.javaClass.simpleName,
            "errorMessage" to (throwable.message ?: ""),
            "stackTrace" to throwable.stackTraceToString().take(500) // Limitar tamaño
        )
        
        addLog(tag, message, extrasWithError, errorType)
        Log.e(tag, "🚨 [CRITICAL] $message", throwable)
    }
    
    /**
     * Agrega un log al buffer circular
     */
    private fun addLog(tag: String, message: String, extras: Map<String, Any>, errorType: String) {
        // 🆕 Verificar si es un nuevo día y limpiar logs antiguos
        checkAndClearDailyIfNeeded()
        
        lock.write {
            // Buffer circular: si excedemos MAX_CRITICAL_LOGS, eliminamos el más antiguo
            if (logs.size >= MAX_CRITICAL_LOGS) {
                logs.removeAt(0)
            }
            
            logs.add(CriticalLogEntry(
                timestamp = System.currentTimeMillis(),
                tag = tag,
                message = message,
                extras = extras,
                errorType = errorType
            ))
        }
    }
    
    /**
     * 🆕 Verifica si es un nuevo día y limpia el buffer si es necesario
     * Se ejecuta automáticamente antes de agregar cada log
     */
    private fun checkAndClearDailyIfNeeded() {
        context?.let { ctx ->
            val prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val today = dateOnlyFormat.format(Date())
            val lastCleanupDate = prefs.getString(PREF_LAST_CLEANUP_DATE, "")
            
            if (lastCleanupDate != today) {
                // Es un nuevo día, limpiar logs
                val oldCount = lock.read { logs.size }
                
                lock.write {
                    logs.clear()
                }
                
                // Guardar la nueva fecha
                prefs.edit().putString(PREF_LAST_CLEANUP_DATE, today).apply()
                
                Log.i(TAG, "🗓️ [LIMPIEZA DIARIA] Nuevo día detectado, buffer limpiado")
                Log.d(TAG, "   - Fecha anterior: $lastCleanupDate")
                Log.d(TAG, "   - Fecha actual: $today")
                Log.d(TAG, "   - Logs eliminados: $oldCount")
            }
        }
    }
    
    /**
     * Obtiene todos los logs críticos en formato JSON para enviar al servidor
     * 🆕 Formato compatible con n8n: incluye movil, deviceId, android, modelo, appVersion en el body raíz
     * Formato: { "movil": "693", "deviceId": "...", "logs": [...], "metadata": {...} }
     */
    fun getLogsAsJson(): String {
        val logsCopy = lock.read {
            logs.toList()
        }
        
        val ctx = context ?: throw IllegalStateException("CriticalLogger no inicializado - llamar init() primero")
        
        // 🆕 Obtener datos del contexto del dispositivo
        val prefs = ctx.getSharedPreferences("user_data", Context.MODE_PRIVATE)
        val movil = prefs.getString("movil", "unknown") ?: "unknown"
        val deviceId = android.provider.Settings.Secure.getString(
            ctx.contentResolver,
            android.provider.Settings.Secure.ANDROID_ID
        )
        
        // 🆕 Obtener appVersion desde PackageManager
        val appVersion = try {
            val packageInfo = ctx.packageManager.getPackageInfo(ctx.packageName, 0)
            packageInfo.versionName ?: "unknown"
        } catch (e: Exception) {
            "unknown"
        }
        
        val metadata = JSONObject().apply {
            put("timestamp", System.currentTimeMillis())
            put("count", logsCopy.size)
            put("system", "CriticalLogger")
            put("version", "1.0")
            put("android_version", android.os.Build.VERSION.SDK_INT)
        }
        
        val logsArray = JSONArray()
        logsCopy.forEach { entry ->
            val logJson = JSONObject().apply {
                put("timestamp", entry.timestamp)
                put("datetime", dateFormat.format(Date(entry.timestamp)))
                put("tag", entry.tag)
                put("message", entry.message)
                put("errorType", entry.errorType)
                
                // Agregar extras como objeto JSON
                if (entry.extras.isNotEmpty()) {
                    val extrasJson = JSONObject()
                    entry.extras.forEach { (key, value) ->
                        extrasJson.put(key, value.toString())
                    }
                    put("extras", extrasJson)
                }
            }
            logsArray.put(logJson)
        }
        
        // 🆕 JSON raíz ahora incluye campos de contexto para n8n (misma estructura que GPS data)
        val result = JSONObject().apply {
            put("movil", movil)
            put("deviceId", deviceId)
            put("android", android.os.Build.VERSION.SDK_INT)
            put("modelo", "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}")
            put("appVersion", appVersion)
            put("timestampFormatted", dateFormat.format(Date())) // 🆕 Timestamp formateado del momento de captura
            put("logs", logsArray)
            put("metadata", metadata)
        }
        
        return result.toString()
    }
    
    /**
     * Limpia todos los logs críticos del buffer
     */
    fun clearLogs() {
        lock.write {
            val count = logs.size
            logs.clear()
            Log.d(TAG, "🧹 Buffer de logs críticos limpiado ($count logs eliminados)")
        }
    }
    
    /**
     * Obtiene el número de logs críticos en el buffer
     */
    fun getLogCount(): Int {
        return lock.read {
            logs.size
        }
    }
    
    /**
     * Genera un snapshot del sistema (batería, permisos, GPS, etc.)
     * Se llama después de limpiar el buffer para tener contexto
     */
    fun generateSystemSnapshot(context: Context): Map<String, Any> {
        return try {
            mapOf(
                "timestamp" to System.currentTimeMillis(),
                "battery_level" to getBatteryLevel(context),
                "is_charging" to isCharging(context),
                "gps_enabled" to isGPSEnabled(context),
                "location_permissions" to getLocationPermissionsStatus(context),
                "notification_permissions" to areNotificationsEnabled(context),
                "app_state" to isAppActive(context),
                "android_version" to android.os.Build.VERSION.SDK_INT,
                "device_model" to android.os.Build.MODEL,
                "device_manufacturer" to android.os.Build.MANUFACTURER
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error generando snapshot: ${e.message}", e)
            mapOf("error" to "snapshot_failed", "message" to (e.message ?: "unknown"))
        }
    }
    
    // ========== MÉTODOS AUXILIARES ==========
    
    private fun getBatteryLevel(context: Context): Int {
        return try {
            val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
            batteryManager.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
        } catch (e: Exception) {
            -1
        }
    }
    
    private fun isCharging(context: Context): Boolean {
        return try {
            val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
            batteryManager.isCharging
        } catch (e: Exception) {
            false
        }
    }
    
    private fun isGPSEnabled(context: Context): Boolean {
        return try {
            val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
            locationManager.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) ||
            locationManager.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER)
        } catch (e: Exception) {
            false
        }
    }
    
    private fun getLocationPermissionsStatus(context: Context): String {
        return try {
            val fineLocation = android.content.pm.PackageManager.PERMISSION_GRANTED ==
                androidx.core.content.ContextCompat.checkSelfPermission(
                    context,
                    android.Manifest.permission.ACCESS_FINE_LOCATION
                )
            val coarseLocation = android.content.pm.PackageManager.PERMISSION_GRANTED ==
                androidx.core.content.ContextCompat.checkSelfPermission(
                    context,
                    android.Manifest.permission.ACCESS_COARSE_LOCATION
                )
            
            when {
                fineLocation && coarseLocation -> "FULL"
                coarseLocation -> "COARSE_ONLY"
                fineLocation -> "FINE_ONLY"
                else -> "DENIED"
            }
        } catch (e: Exception) {
            "UNKNOWN"
        }
    }
    
    private fun areNotificationsEnabled(context: Context): Boolean {
        return try {
            androidx.core.app.NotificationManagerCompat.from(context).areNotificationsEnabled()
        } catch (e: Exception) {
            false
        }
    }
    
    private fun isAppActive(context: Context): String {
        return try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            val runningProcesses = activityManager.runningAppProcesses ?: return "UNKNOWN"
            
            for (processInfo in runningProcesses) {
                if (processInfo.processName == context.packageName) {
                    return when (processInfo.importance) {
                        android.app.ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND -> "ACTIVE"
                        android.app.ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE -> "VISIBLE"
                        android.app.ActivityManager.RunningAppProcessInfo.IMPORTANCE_SERVICE -> "BACKGROUND_SERVICE"
                        else -> "BACKGROUND"
                    }
                }
            }
            "NOT_RUNNING"
        } catch (e: Exception) {
            "UNKNOWN"
        }
    }
}
