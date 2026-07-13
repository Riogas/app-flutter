package com.riogas.appmovil

import android.content.Context
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Worker para subir logs de depuración al servidor RioGas cada 10 minutos
 * 
 * CARACTERÍSTICAS:
 * - Se ejecuta cada 10 minutos cuando el debug está habilitado
 * - Solo sube si hay logs en el buffer
 * - Limpia el buffer después de envío exitoso
 * - Incluye metadata del dispositivo (móvil, deviceId, Android version)
 */
class DebugLogUploadWorker(
    context: Context,
    workerParams: WorkerParameters
) : Worker(context, workerParams) {
    
    companion object {
        private const val TAG = "DebugLogUploadWorker"
        private const val UPLOAD_URL = "https://n8n.riogas.com.uy/webhook/debug-delivery"
        private const val TIMEOUT_SECONDS = 15L
    }
    
    override fun doWork(): Result {
        val runId = System.currentTimeMillis()
        Log.i(TAG, "🚀 [RUN:$runId] Worker iniciado - doWork()")
        
        // 🆕 LOG: Estado inicial del worker
        try {
            val runAttempt = runAttemptCount
            val tags = tags.joinToString(",")
            Log.d(TAG, "📊 [RUN:$runId] Worker info: attempt=$runAttempt, tags=[$tags]")
            
            // Log del estado de la app
            val prefs = applicationContext.getSharedPreferences("config", Context.MODE_PRIVATE)
            val movil = prefs.getString("last_movil", "0") ?: "0"
            val deviceId = prefs.getString("last_deviceId", "unknown") ?: "unknown"
            val debugEnabled = DebugLogger.isEnabled()
            val logCount = DebugLogger.getLogCount()
            
            Log.i(TAG, "📋 [RUN:$runId] Estado: movil=$movil, deviceId=$deviceId, debugEnabled=$debugEnabled, logCount=$logCount")
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ [RUN:$runId] Error obteniendo info del worker: ${e.message}")
        }
        
        // Verificar si el debugging está habilitado
        if (!DebugLogger.isEnabled()) {
            Log.d(TAG, "⏭️ [RUN:$runId] Debug logging deshabilitado, saltando upload")
            return Result.success()
        }
        
        val logCount = DebugLogger.getLogCount()
        if (logCount == 0) {
            Log.d(TAG, "⏭️ [RUN:$runId] No hay logs para subir (buffer vacío)")
            return Result.success()
        }
        
        Log.d(TAG, "📤 [RUN:$runId] Iniciando upload de $logCount logs al servidor...")
        
        try {
            // Obtener parámetros del contexto de la app
            val prefs = applicationContext.getSharedPreferences("config", Context.MODE_PRIVATE)
            val movil = prefs.getString("last_movil", "0") ?: "0"
            val deviceId = prefs.getString("last_deviceId", "unknown") ?: "unknown"
            
            // 🆕 LOG: Parámetros leídos
            Log.d(TAG, "📋 [RUN:$runId] Parámetros: movil=$movil, deviceId=$deviceId")
            
            // Obtener logs en formato JSON
            val logsJson = DebugLogger.getLogsAsJson()
            val logsSize = logsJson.length
            Log.d(TAG, "📦 [RUN:$runId] Logs JSON generado: ${logsSize} bytes")
            
            // Crear payload con metadata adicional
            val payload = JSONObject()
            payload.put("token", "IcA.FwL.1710.!")
            payload.put("movil", movil)
            payload.put("deviceId", deviceId)
            payload.put("androidVersion", android.os.Build.VERSION.SDK_INT)
            payload.put("deviceModel", "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}")
            payload.put("appVersion", getAppVersion())
            payload.put("logs", JSONObject(logsJson))
            
            val payloadSize = payload.toString().length
            Log.d(TAG, "📦 [RUN:$runId] Payload completo: ${payloadSize} bytes")
            
            // 🆕 LOG: Verificar conectividad
            val connectivityManager = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
            val networkInfo = connectivityManager.activeNetworkInfo
            val isConnected = networkInfo?.isConnected == true
            val networkType = networkInfo?.typeName ?: "none"
            
            Log.d(TAG, "🌐 [RUN:$runId] Network: connected=$isConnected, type=$networkType")
            
            if (!isConnected) {
                Log.w(TAG, "⚠️ [RUN:$runId] Sin conexión a internet - Reintentando más tarde")
                return Result.retry()
            }
            
            // Configurar cliente HTTP con timeout
            val client = OkHttpClient.Builder()
                .connectTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
                .writeTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
                .readTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
                .build()
            
            val request = Request.Builder()
                .url(UPLOAD_URL)
                .addHeader("accept", "application/json")
                .addHeader("Content-Type", "application/json")
                .post(payload.toString().toRequestBody("application/json".toMediaType()))
                .build()
            
            Log.d(TAG, "🌐 [RUN:$runId] Enviando $logCount logs a $UPLOAD_URL (movil=$movil)...")
            val startTime = System.currentTimeMillis()
            
            // Ejecutar request
            client.newCall(request).execute().use { response ->
                val elapsedTime = System.currentTimeMillis() - startTime
                val httpCode = response.code
                val httpMessage = response.message
                
                if (response.isSuccessful) {
                    val responseBody = response.body?.string() ?: "empty"
                    Log.i(TAG, "✅ [RUN:$runId] Logs enviados exitosamente en ${elapsedTime}ms")
                    Log.i(TAG, "📥 [RUN:$runId] Response: HTTP $httpCode - $responseBody")
                    
                    // Limpiar buffer después de envío exitoso
                    DebugLogger.clearLogs()
                    Log.d(TAG, "🧹 [RUN:$runId] Buffer limpiado")
                    
                    // 🆕 REGENERAR LOG INICIAL: Snapshot del sistema (permisos, batería, GPS)
                    // Esto asegura que el próximo batch SIEMPRE tenga el contexto del estado actual
                    try {
                        com.example.moveit.LocationHelper.logSystemSnapshot(applicationContext)
                        Log.d(TAG, "📸 [RUN:$runId] System snapshot regenerado para próximo batch")
                    } catch (e: Exception) {
                        Log.w(TAG, "⚠️ [RUN:$runId] No se pudo regenerar snapshot: ${e.message}")
                    }
                    
                    return Result.success()
                } else {
                    val errorBody = response.body?.string() ?: "empty"
                    Log.e(TAG, "❌ [RUN:$runId] Error HTTP $httpCode: $httpMessage (${elapsedTime}ms)")
                    Log.e(TAG, "📥 [RUN:$runId] Error body: $errorBody")
                    
                    // Reintentar en caso de error (WorkManager lo reintentará automáticamente)
                    return Result.retry()
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ [RUN:$runId] Error subiendo logs: ${e.message}", e)
            Log.e(TAG, "📍 [RUN:$runId] Exception: ${e.javaClass.simpleName} - ${e.stackTrace.firstOrNull()}")
            
            // Si falla, reintentar más tarde
            return Result.retry()
        }
    }
    
    /**
     * Obtiene la versión de la aplicación desde el PackageManager
     */
    private fun getAppVersion(): String {
        return try {
            val packageInfo = applicationContext.packageManager.getPackageInfo(
                applicationContext.packageName,
                0
            )
            packageInfo.versionName ?: "unknown"
        } catch (e: Exception) {
            "unknown"
        }
    }
}
