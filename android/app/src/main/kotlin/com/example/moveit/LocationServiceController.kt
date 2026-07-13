package com.example.moveit

import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log
import com.riogas.appmovil.ServiceStatusFlags
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Controlador centralizado para el manejo del servicio de ubicación
 * Permite iniciar, detener y controlar el servicio desde cualquier contexto
 */
object LocationServiceController {
    private const val TAG = "LocationServiceController"

    /**
     * Detiene el servicio de ubicación desde contexto de background
     * Puede ser llamado incluso cuando la app está cerrada
     */
    fun stopLocationServiceFromBackground(
        context: Context, 
        movil: String, 
        escenario: String, 
        usuario: String, 
        deviceId: String,
        reason: String = "Background stop"
    ) {
        Log.i(TAG, "🛑 Deteniendo servicio desde background: $reason")
        
        try {
            // 1. Cancelar WorkManager (health-check) — ya no hay alarmas que cancelar
            WorkManagerHelper.cancelPeriodicWork(context)
            com.riogas.appmovil.tracking.HealthCheckWorker.cancel(context)

            // 2. Marcar como deshabilitado vía ServiceStatusFlags
            markServiceAsDisabled(context, reason)

            // 3. Detener el tracking foreground nuevo
            com.riogas.appmovil.tracking.LocationTrackingService.stop(context)
            
            // 4. Registrar evento en logs nativos
            LocationLogger.logEvent(context, "SERVICE_STOPPED", mapOf(
                "reason" to reason,
                "movil" to movil,
                "timestamp" to System.currentTimeMillis().toString()
            ))
            
            // 5. Notificar a Flutter si es posible
            notifyFlutterServiceStopped(context, reason)
            
            Log.i(TAG, "✅ Servicio detenido completamente por: $reason")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error al detener servicio", e)
            LocationLogger.logError(context, "STOP_SERVICE_ERROR", e.message ?: "Unknown error")
        }
    }
    
    /**
     * Marca el servicio como deshabilitado en SharedPreferences
     */
    private fun markServiceAsDisabled(context: Context, reason: String) {
        try {
            ServiceStatusFlags.setServiceDisabled(context, true, reason)
            val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            prefs.edit().apply {
                putString("stop_reason", reason)
                putLong("stop_timestamp", System.currentTimeMillis())
                putBoolean("auto_stopped", true) // Flag para distinguir paradas automáticas
            }.apply()
            
            Log.i(TAG, "💾 Estado del servicio guardado: deshabilitado")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error guardando estado del servicio", e)
        }
    }
    
    /**
     * Notifica a Flutter sobre la parada del servicio usando SharedPreferences
     */
    private fun notifyFlutterServiceStopped(context: Context, reason: String) {
        try {
            val flutterPrefs = context.getSharedPreferences("flutter_events", Context.MODE_PRIVATE)
            flutterPrefs.edit().apply {
                putString("location_service_stopped", reason)
                putLong("location_service_stopped_time", System.currentTimeMillis())
                putBoolean("needs_flutter_sync", true)
            }.apply()
            
            Log.i(TAG, "📤 Evento notificado a Flutter: $reason")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error notificando a Flutter", e)
        }
    }
    
    /**
     * Verifica si el servicio está actualmente deshabilitado
     */
    fun isServiceDisabled(context: Context): Boolean {
        return try {
            ServiceStatusFlags.isServiceDisabled(context)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error verificando estado del servicio", e)
            false
        }
    }
    
    /**
     * Reactiva el servicio (limpia flag de deshabilitado)
     */
    fun reactivateService(context: Context, reason: String = "Manual reactivation") {
        try {
            ServiceStatusFlags.setServiceDisabled(context, false, reason)
            val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            prefs.edit().apply {
                putString("reactivation_reason", reason)
                putLong("reactivation_timestamp", System.currentTimeMillis())
                remove("stop_reason")
                remove("auto_stopped")
            }.apply()
            
            LocationLogger.logEvent(context, "SERVICE_REACTIVATED", mapOf(
                "reason" to reason,
                "timestamp" to System.currentTimeMillis().toString()
            ))
            
            Log.i(TAG, "✅ Servicio reactivado: $reason")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error reactivando servicio", e)
            LocationLogger.logError(context, "REACTIVATE_SERVICE_ERROR", e.message ?: "Unknown error")
        }
    }
    
    /**
     * Obtiene el estado completo del servicio
     */
    fun getServiceStatus(context: Context): Map<String, Any> {
        return try {
            val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            mapOf<String, Any>(
                "disabled" to ServiceStatusFlags.isServiceDisabled(context),
                "stopReason" to (prefs.getString("stop_reason", "") ?: ""),
                "stopTimestamp" to prefs.getLong("stop_timestamp", 0),
                "autoStopped" to prefs.getBoolean("auto_stopped", false),
                "reactivationReason" to (prefs.getString("reactivation_reason", "") ?: ""),
                "reactivationTimestamp" to prefs.getLong("reactivation_timestamp", 0)
            )
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error obteniendo estado del servicio", e)
            mapOf<String, Any>("error" to (e.message ?: "Unknown error"))
        }
    }
    
    /**
     * Verifica si el dispositivo está en modo de ahorro de batería
     */
    fun isInBatteryOptimizationMode(context: Context): Boolean {
        return try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            powerManager.isPowerSaveMode
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error verificando modo de batería", e)
            false
        }
    }
    
    /**
     * Calcula intervalo de ubicación adaptativo según batería y uso
     */
    fun calculateAdaptiveInterval(context: Context, baseInterval: Int): Int {
        return try {
            val batteryOptimized = isInBatteryOptimizationMode(context)
            val errorCount = getRecentErrorCount(context)
            
            var adjustedInterval = baseInterval
            
            // Aumentar intervalo si hay ahorro de batería
            if (batteryOptimized) {
                adjustedInterval *= 2
                Log.i(TAG, "🔋 Modo ahorro batería: intervalo aumentado a ${adjustedInterval}min")
            }
            
            // Aumentar intervalo si hay errores recurrentes
            if (errorCount > 3) {
                adjustedInterval = (adjustedInterval * 1.5).toInt()
                Log.i(TAG, "⚠️ Errores recurrentes: intervalo aumentado a ${adjustedInterval}min")
            }
            
            // Mínimo 1 minuto, máximo 60 minutos
            adjustedInterval.coerceIn(1, 60)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error calculando intervalo adaptativo", e)
            baseInterval
        }
    }
    
    /**
     * Obtiene el número de errores recientes
     */
    private fun getRecentErrorCount(context: Context): Int {
        return try {
            val prefs = context.getSharedPreferences("location_errors", Context.MODE_PRIVATE)
            val lastErrorTime = prefs.getLong("last_error_time", 0)
            val currentTime = System.currentTimeMillis()
            
            // Solo contar errores de los últimos 30 minutos
            if (currentTime - lastErrorTime < 30 * 60 * 1000) {
                prefs.getInt("error_count", 0)
            } else {
                // Resetear contador si han pasado más de 30 minutos
                prefs.edit().putInt("error_count", 0).apply()
                0
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error obteniendo conteo de errores", e)
            0
        }
    }
}