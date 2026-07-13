package com.riogas.appmovil

import android.content.Context
import android.util.Log
import androidx.work.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

/**
 * Worker que envía logs CRÍTICOS a n8n cada 15 minutos
 * 
 * DIFERENCIAS CON DebugLogUploadWorker:
 * - Se ejecuta SIEMPRE (no depende de debugMode)
 * - Solo envía errores críticos (no logs de debug)
 * - Frecuencia: 15 minutos fijos
 * - No requiere activación manual (siempre activo)
 */
class CriticalLogUploadWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : Worker(appContext, workerParams) {

    companion object {
        private const val TAG = "CriticalLogUploadWorker"
        private const val WORK_NAME = "critical_log_upload"
        private const val N8N_WEBHOOK_URL = "https://n8n.riogas.com.uy/webhook/debug-delivery"
        
        /**
         * Programa el trabajo periódico para enviar logs críticos cada 30 segundos
         * 🆕 WATCHDOG: Se ejecuta cada 30 segundos para verificar servicios mutuamente
         */
        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
            
            val uploadRequest = PeriodicWorkRequestBuilder<CriticalLogUploadWorker>(
                30, TimeUnit.SECONDS, // 🆕 Cambiado de 5 minutos a 30 segundos
                15, TimeUnit.SECONDS // Ventana de flexibilidad
            )
                .setConstraints(constraints)
                .setBackoffCriteria(
                    BackoffPolicy.EXPONENTIAL,
                    WorkRequest.MIN_BACKOFF_MILLIS,
                    TimeUnit.MILLISECONDS
                )
                .addTag("critical_logs")
                .build()
            
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP, // Mantener el existente si ya está programado
                uploadRequest
            )
            
            Log.d(TAG, "✅ CriticalLogUploadWorker programado (cada 30 segundos)")
        }
        
        /**
         * Cancela el trabajo periódico
         */
        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            Log.d(TAG, "🛑 CriticalLogUploadWorker cancelado")
        }
    }

    override fun doWork(): Result {
        Log.d(TAG, "🚀 [WATCHDOG] CriticalLogWorker ejecutándose...")
        
        // 🆕 PASO 1: WATCHDOG - Verificar que GPS service esté activo
        val isGPSRunning = com.riogas.appmovil.ServiceWatchdog.isGPSServiceRunning(applicationContext)
        val isAlarmScheduled = com.riogas.appmovil.ServiceWatchdog.isAlarmScheduled(applicationContext)
        
        Log.d(TAG, "📊 [WATCHDOG] Estado GPS: ServiceRunning=$isGPSRunning, AlarmScheduled=$isAlarmScheduled")
        
        if (!isGPSRunning || !isAlarmScheduled) {
            Log.w(TAG, "⚠️ [WATCHDOG] GPS service MUERTO detectado - Intentando reiniciar...")
            
            // Usar runBlocking porque estamos en un Worker (no en coroutine)
            val restarted = runBlocking {
                com.riogas.appmovil.ServiceWatchdog.restartGPSService(applicationContext)
            }
            
            if (restarted) {
                Log.i(TAG, "✅ [WATCHDOG] GPS service reiniciado exitosamente")
            } else {
                Log.e(TAG, "❌ [WATCHDOG] No se pudo reiniciar GPS service localmente")
                
                // 🆕 NUEVO: Si reinicio local falla, enviar comando FCM remoto
                try {
                    val prefs = applicationContext.getSharedPreferences("config", Context.MODE_PRIVATE)
                    val movil = prefs.getString("last_movil", "") ?: ""
                    val escenario = prefs.getString("last_escenario", "0") ?: "0"
                    val escenarioId = escenario.toIntOrNull() ?: 0
                    
                    if (movil.isNotEmpty() && escenarioId > 0) {
                        Log.i(TAG, "🚨 [WATCHDOG] Reinicio local falló, enviando comando FCM remoto...")
                        
                        CriticalLogger.logCritical(
                            TAG,
                            "WATCHDOG: Reinicio local falló - Solicitando reinicio remoto via FCM",
                            mapOf(
                                "movil" to movil,
                                "escenario" to escenario,
                                "action" to "restart_gps_service",
                                "trigger" to "local_restart_failed",
                                "context" to "CriticalLogUploadWorker"
                            ),
                            "WATCHDOG_LOCAL_RESTART_FAILED"
                        )
                        
                        FcmApiHelper.restartGpsService(
                            applicationContext,
                            escenarioId,
                            movil,
                            onSuccess = { response ->
                                Log.i(TAG, "✅ [WATCHDOG] Comando FCM enviado exitosamente: $response")
                                CriticalLogger.logCritical(
                                    TAG,
                                    "WATCHDOG: Comando FCM restart_gps_service enviado - esperando respuesta remota",
                                    mapOf(
                                        "movil" to movil,
                                        "escenario" to escenario,
                                        "action" to "restart_gps_service",
                                        "trigger" to "local_restart_failed",
                                        "response" to response
                                    ),
                                    "WATCHDOG_FCM_RESTART_SENT"
                                )
                            },
                            onError = { error ->
                                Log.e(TAG, "❌ [WATCHDOG] Error enviando comando FCM restart: $error")
                                CriticalLogger.logCritical(
                                    TAG,
                                    "WATCHDOG ERROR: Fallo enviando comando FCM restart remoto",
                                    mapOf(
                                        "movil" to movil,
                                        "escenario" to escenario,
                                        "error" to error,
                                        "action" to "restart_gps_service",
                                        "trigger" to "local_restart_failed"
                                    ),
                                    "WATCHDOG_FCM_RESTART_ERROR"
                                )
                            }
                        )
                    } else {
                        Log.w(TAG, "⚠️ [WATCHDOG] No se puede enviar comando FCM: movil o escenario inválidos")
                        CriticalLogger.logCritical(
                            TAG,
                            "WATCHDOG ERROR: No se pudo enviar comando FCM - datos insuficientes",
                            mapOf(
                                "movil" to movil,
                                "escenario" to escenario,
                                "escenarioId" to escenarioId.toString(),
                                "reason" to "invalid_movil_or_escenario"
                            ),
                            "WATCHDOG_FCM_INVALID_DATA"
                        )
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ [WATCHDOG] Excepción al invocar FCM API: ${e.message}", e)
                    CriticalLogger.logCritical(
                        TAG,
                        "WATCHDOG EXCEPTION: Error crítico invocando FCM API desde CriticalLogWorker",
                        e,
                        mapOf(
                            "error_type" to e.javaClass.simpleName,
                            "error_message" to (e.message ?: "Sin mensaje")
                        ),
                        "WATCHDOG_FCM_EXCEPTION"
                    )
                }
            }
        } else {
            Log.d(TAG, "✅ [WATCHDOG] GPS service activo y saludable")
        }
        
        // 🆕 PASO 2: Verificar si hay logs críticos para enviar
        val logCount = CriticalLogger.getLogCount()
        
        if (logCount == 0) {
            Log.d(TAG, "ℹ️ No hay logs críticos para enviar (solo watchdog ejecutado)")
            return Result.success()
        }
        
        // 🆕 VERIFICAR DEBUG MODE: Solo enviar si debugMode = true
        val debugMode = com.riogas.appmovil.DebugLogger.isEnabled()
        
        if (!debugMode) {
            Log.d(TAG, "🔇 [DEBUG-OFF] debugMode=false → NO enviando $logCount logs a n8n")
            Log.d(TAG, "   - Logs se mantienen en buffer para cuando debugMode se active")
            // NO limpiamos logs - se acumularán hasta que debugMode sea true
            return Result.success()
        }
        
        Log.d(TAG, "📦 Preparando envío de $logCount logs críticos (debugMode=true)...")
        
        try {
            // Obtener logs en formato JSON
            val logsJson = CriticalLogger.getLogsAsJson()
            
            // Crear cliente HTTP con timeouts
            val client = OkHttpClient.Builder()
                .connectTimeout(30, TimeUnit.SECONDS)
                .writeTimeout(30, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS)
                .build()
            
            // Crear request
            val request = Request.Builder()
                .url(N8N_WEBHOOK_URL)
                .addHeader("Content-Type", "application/json")
                .post(logsJson.toRequestBody("application/json".toMediaType()))
                .build()
            
            val startTime = System.currentTimeMillis()
            Log.d(TAG, "🌐 Enviando $logCount logs críticos a n8n (debugMode=true)...")
            Log.d(TAG, "📤 Payload size: ${logsJson.length} bytes")
            
            // Ejecutar request
            client.newCall(request).execute().use { response ->
                val elapsedTime = System.currentTimeMillis() - startTime
                
                if (response.isSuccessful) {
                    val responseBody = response.body?.string() ?: "empty"
                    Log.i(TAG, "✅ Logs críticos enviados exitosamente")
                    Log.i(TAG, "   - HTTP Code: ${response.code}")
                    Log.i(TAG, "   - Logs enviados: $logCount")
                    Log.i(TAG, "   - Tiempo: ${elapsedTime}ms")
                    Log.i(TAG, "   - Response: $responseBody")
                    
                    // ✅ Limpiar logs después de envío exitoso
                    CriticalLogger.clearLogs()
                    Log.d(TAG, "🧹 Buffer de logs críticos limpiado")
                    
                    // Generar snapshot del sistema para el próximo ciclo
                    val snapshot = CriticalLogger.generateSystemSnapshot(applicationContext)
                    Log.d(TAG, "📸 Snapshot generado: $snapshot")
                    
                    return Result.success()
                    
                } else {
                    val errorBody = response.body?.string() ?: "empty"
                    Log.e(TAG, "❌ Error enviando logs críticos")
                    Log.e(TAG, "   - HTTP Code: ${response.code}")
                    Log.e(TAG, "   - Message: ${response.message}")
                    Log.e(TAG, "   - Response: $errorBody")
                    Log.e(TAG, "   - Tiempo: ${elapsedTime}ms")
                    
                    // ⚠️ NO limpiamos logs si falla el envío (se reintentarán)
                    return Result.retry()
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "💥 Excepción enviando logs críticos: ${e.message}", e)
            
            // ⚠️ NO limpiamos logs si hay excepción (se reintentarán)
            return Result.retry()
        }
    }
}
