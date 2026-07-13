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
         * Programa el trabajo periódico para enviar logs críticos cada 15 minutos.
         * (Task 7 / B.1: ya NO hace watchdog; solo sube logs críticos con WorkManager.)
         */
        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val uploadRequest = PeriodicWorkRequestBuilder<CriticalLogUploadWorker>(
                15, TimeUnit.MINUTES, // 🔧 Task 7: 30s → 15 min (sin watchdog)
                5, TimeUnit.MINUTES // Ventana de flexibilidad
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
            
            Log.d(TAG, "✅ CriticalLogUploadWorker programado (cada 15 minutos)")
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
        Log.d(TAG, "🚀 CriticalLogUploadWorker ejecutándose (subida de logs)...")

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
