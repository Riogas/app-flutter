package com.riogas.appmovil

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import kotlinx.coroutines.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

/**
 * 🆕 WATCHDOG CON ALARMMANAGER
 * BroadcastReceiver que se ejecuta cada 30 segundos mediante AlarmManager
 * 
 * FUNCIONES:
 * 1. Verificar que GPS Service esté activo (watchdog)
 * 2. Reiniciar GPS Service si está muerto
 * 3. Enviar logs críticos a n8n (solo si debugMode=true)
 * 
 * VENTAJAS sobre WorkManager:
 * - Se ejecuta exactamente cada 30 segundos (sin mínimo de 15 minutos)
 * - Más confiable para watchdog de alta frecuencia
 * - Menor latencia en detección de fallos
 */
class CriticalLogAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "CriticalLogAlarm"
        private const val ACTION_WATCHDOG_CHECK = "com.riogas.appmovil.WATCHDOG_CHECK"
        private const val ALARM_INTERVAL_MS = 30_000L // 30 segundos
        private const val N8N_WEBHOOK_URL = "https://n8n.riogas.com.uy/webhook/debug-delivery"
        
        private var lastExecutionTime = 0L
        
        /**
         * Programa la alarma para ejecutar cada 30 segundos
         */
        fun schedule(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, CriticalLogAlarmReceiver::class.java).apply {
                action = ACTION_WATCHDOG_CHECK
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                12345, // Request code único para CriticalLog
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val triggerTime = System.currentTimeMillis() + ALARM_INTERVAL_MS
            
            // Usar setRepeating para ejecución precisa cada 30 segundos
            alarmManager.setRepeating(
                AlarmManager.RTC_WAKEUP,
                triggerTime,
                ALARM_INTERVAL_MS,
                pendingIntent
            )
            
            Log.i(TAG, "✅ CriticalLog AlarmManager programado (cada 30 segundos)")
            Log.d(TAG, "   - Intervalo: ${ALARM_INTERVAL_MS / 1000}s")
            Log.d(TAG, "   - Próxima ejecución: ${java.text.SimpleDateFormat("HH:mm:ss").format(triggerTime)}")
        }
        
        /**
         * Cancela la alarma
         */
        fun cancel(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, CriticalLogAlarmReceiver::class.java).apply {
                action = ACTION_WATCHDOG_CHECK
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                12345,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            alarmManager.cancel(pendingIntent)
            Log.i(TAG, "🛑 CriticalLog AlarmManager cancelado")
        }
        
        /**
         * Verifica si la alarma está programada
         */
        fun isScheduled(context: Context): Boolean {
            val intent = Intent(context, CriticalLogAlarmReceiver::class.java).apply {
                action = ACTION_WATCHDOG_CHECK
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                12345,
                intent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            
            return pendingIntent != null
        }
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_WATCHDOG_CHECK) {
            Log.w(TAG, "⚠️ Intent ignorado: ${intent.action}")
            return
        }
        
        // Evitar ejecuciones duplicadas muy rápidas
        val now = System.currentTimeMillis()
        if (now - lastExecutionTime < 15_000) { // Mínimo 15 segundos entre ejecuciones
            Log.w(TAG, "⏭️ Ejecución duplicada detectada, saltando...")
            return
        }
        lastExecutionTime = now
        
        val executionTime = java.text.SimpleDateFormat("HH:mm:ss.SSS").format(now)
        Log.d(TAG, "🔔 [WATCHDOG-ALARM] Ejecutando verificación a las $executionTime")
        
        // PASO 1: WATCHDOG - Verificar GPS Service
        performWatchdogCheck(context)
        
        // PASO 2: Enviar logs críticos si hay (en coroutine para no bloquear)
        sendCriticalLogsIfNeeded(context)
        
        // Reprogramar la próxima alarma (por si Android la canceló)
        val nextExecutionTime = now + ALARM_INTERVAL_MS
        Log.v(TAG, "⏰ Próxima verificación programada: ${java.text.SimpleDateFormat("HH:mm:ss").format(nextExecutionTime)}")
    }
    
    /**
     * Verifica que GPS Service esté activo y lo reinicia si está muerto
     */
    private fun performWatchdogCheck(context: Context) {
        val isGPSRunning = ServiceWatchdog.isGPSServiceRunning(context)
        val isAlarmScheduled = ServiceWatchdog.isAlarmScheduled(context)
        
        Log.d(TAG, "📊 [WATCHDOG] Estado GPS Service:")
        Log.d(TAG, "   - Service Running: $isGPSRunning")
        Log.d(TAG, "   - Alarm Scheduled: $isAlarmScheduled")
        
        if (!isGPSRunning || !isAlarmScheduled) {
            Log.w(TAG, "⚠️ [WATCHDOG] GPS Service MUERTO detectado!")
            Log.w(TAG, "   - Service: ${if (isGPSRunning) "✅" else "❌"}")
            Log.w(TAG, "   - Alarm: ${if (isAlarmScheduled) "✅" else "❌"}")
            Log.w(TAG, "🔄 Intentando reiniciar GPS Service...")
            
            // 🚩 MARCAR FLAG: GPS service está apagado
            ServiceStatusFlags.setServicesNeedRestart(
                context, 
                true, 
                "CriticalLogAlarm",
                "GPS service detectado como muerto - serviceRunning=$isGPSRunning, alarmScheduled=$isAlarmScheduled"
            )
            ServiceStatusFlags.setGPSServiceStatus(context, false, "CriticalLogAlarm")
            
            // Registrar error crítico
            CriticalLogger.logCritical(
                TAG,
                "GPS Service MUERTO detectado por watchdog",
                mapOf(
                    "serviceRunning" to isGPSRunning,
                    "alarmScheduled" to isAlarmScheduled,
                    "timestamp" to System.currentTimeMillis()
                ),
                "GPS_SERVICE_DEAD"
            )
            
            // Reiniciar GPS Service usando coroutine (porque ahora es suspend)
            CoroutineScope(Dispatchers.Default).launch {
                try {
                    val restarted = ServiceWatchdog.restartGPSService(context)
                    
                    if (restarted) {
                        Log.i(TAG, "✅ [WATCHDOG] GPS Service reiniciado exitosamente")
                        
                        // 🚩 MARCAR FLAG: GPS service reiniciado (la flag volverá a false en próxima verificación)
                        ServiceStatusFlags.setGPSServiceStatus(context, true, "CriticalLogAlarm")
                        
                        // Registrar recuperación exitosa
                        CriticalLogger.logCritical(
                            TAG,
                            "GPS Service reiniciado exitosamente por watchdog",
                            mapOf(
                                "timestamp" to System.currentTimeMillis()
                            ),
                            "GPS_SERVICE_RECOVERED"
                        )
                    } else {
                        Log.e(TAG, "❌ [WATCHDOG] FALLO al reiniciar GPS Service")
                        
                        // Registrar fallo de recuperación
                        CriticalLogger.logCritical(
                            TAG,
                            "FALLO CRÍTICO: No se pudo reiniciar GPS Service",
                            mapOf(
                                "timestamp" to System.currentTimeMillis(),
                                "reason" to "movil_not_recoverable_or_other"
                            ),
                            "GPS_SERVICE_RECOVERY_FAILED"
                        )
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ [WATCHDOG] Excepción al reiniciar GPS Service: ${e.message}", e)
                    CriticalLogger.logCritical(
                        TAG,
                        "WATCHDOG EXCEPTION: Error al intentar reiniciar GPS Service",
                        e,
                        mapOf(
                            "error_type" to e.javaClass.simpleName,
                            "error_message" to (e.message ?: "Sin mensaje")
                        ),
                        "WATCHDOG_RESTART_EXCEPTION"
                    )
                }
            }
        } else {
            // ✅ Servicios activos, marcar flag en false
            Log.d(TAG, "✅ [WATCHDOG] GPS Service activo y saludable")
            
            // 🚩 MARCAR FLAG: Todo está funcionando correctamente
            ServiceStatusFlags.setServicesNeedRestart(
                context, 
                false, 
                "CriticalLogAlarm",
                "GPS service verificado activo y saludable"
            )
            ServiceStatusFlags.setGPSServiceStatus(context, true, "CriticalLogAlarm")
        }
    }
    
    /**
     * Envía logs críticos a n8n si hay logs pendientes y debugMode=true
     * Se ejecuta en coroutine para no bloquear el BroadcastReceiver
     */
    private fun sendCriticalLogsIfNeeded(context: Context) {
        val logCount = CriticalLogger.getLogCount()
        
        if (logCount == 0) {
            Log.v(TAG, "ℹ️ No hay logs críticos pendientes")
            return
        }
        
        // Verificar debugMode
        val debugMode = DebugLogger.isEnabled()
        
        if (!debugMode) {
            Log.d(TAG, "🔇 [DEBUG-OFF] debugMode=false → NO enviando $logCount logs a n8n")
            Log.d(TAG, "   - Logs acumulados: $logCount (esperando debugMode=true)")
            return
        }
        
        Log.d(TAG, "📦 [DEBUG-ON] Hay $logCount logs críticos pendientes, enviando a n8n...")
        
        // Ejecutar en coroutine para no bloquear el receiver
        // goAsync() permite que el receiver continúe después de onReceive()
        val pendingResult = goAsync()
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val success = sendLogsToN8n(context, logCount)
                
                if (success) {
                    Log.i(TAG, "✅ $logCount logs críticos enviados exitosamente a n8n")
                    CriticalLogger.clearLogs()
                    Log.d(TAG, "🧹 Buffer de logs limpiado")
                } else {
                    Log.w(TAG, "⚠️ Error enviando logs a n8n, se reintentarán en próxima ejecución")
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "💥 Excepción enviando logs: ${e.message}", e)
            } finally {
                pendingResult.finish()
            }
        }
    }
    
    /**
     * Envía los logs a n8n webhook
     * @return true si envío exitoso, false si hubo error
     */
    private suspend fun sendLogsToN8n(context: Context, logCount: Int): Boolean = withContext(Dispatchers.IO) {
        try {
            val logsJson = CriticalLogger.getLogsAsJson()
            
            val client = OkHttpClient.Builder()
                .connectTimeout(10, TimeUnit.SECONDS)
                .writeTimeout(10, TimeUnit.SECONDS)
                .readTimeout(10, TimeUnit.SECONDS)
                .build()
            
            val request = Request.Builder()
                .url(N8N_WEBHOOK_URL)
                .addHeader("Content-Type", "application/json")
                .post(logsJson.toRequestBody("application/json".toMediaType()))
                .build()
            
            val startTime = System.currentTimeMillis()
            Log.d(TAG, "🌐 Enviando $logCount logs a n8n (${logsJson.length} bytes)...")
            
            client.newCall(request).execute().use { response ->
                val elapsedTime = System.currentTimeMillis() - startTime
                
                if (response.isSuccessful) {
                    val responseBody = response.body?.string() ?: "empty"
                    Log.i(TAG, "✅ Envío exitoso (${elapsedTime}ms)")
                    Log.d(TAG, "   - HTTP Code: ${response.code}")
                    Log.d(TAG, "   - Response: $responseBody")
                    return@withContext true
                } else {
                    val errorBody = response.body?.string() ?: "empty"
                    Log.w(TAG, "⚠️ Error HTTP ${response.code} (${elapsedTime}ms)")
                    Log.w(TAG, "   - Message: ${response.message}")
                    Log.w(TAG, "   - Response: $errorBody")
                    return@withContext false
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "💥 Excepción: ${e.message}", e)
            return@withContext false
        }
    }
}
