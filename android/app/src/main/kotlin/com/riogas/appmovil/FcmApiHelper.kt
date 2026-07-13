package com.riogas.appmovil

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * 🚨 FcmApiHelper - Invocar API FCMActions desde servicios nativos
 * 
 * Permite a los servicios Android (ForegroundLocationService, CriticalLogger, etc.)
 * invocar la API FCMActions del servidor para enviar comandos FCM remotos cuando
 * detectan que el servicio GPS no responde o no puede auto-recuperarse.
 * 
 * Comandos disponibles:
 * - force_gps_execution: Forzar ejecución GPS inmediata
 * - restart_gps_service: Reiniciar servicio GPS completo
 * - stop_gps_service: Detener servicio GPS
 * - get_status: Consultar estado del servicio
 */
object FcmApiHelper {
    
    private const val TAG = "FcmApiHelper"
    
    /**
     * Envía comando FCM al servidor mediante API FCMActions
     * 
     * @param context Contexto de Android
     * @param escenarioId ID del escenario
     * @param movil Identificador del móvil
     * @param accion Acción a ejecutar (force_gps_execution, restart_gps_service, stop_gps_service, get_status)
     * @param onSuccess Callback en caso de éxito
     * @param onError Callback en caso de error
     */
    fun sendFcmAction(
        context: Context,
        escenarioId: Int,
        movil: String,
        accion: String,
        onSuccess: ((String) -> Unit)? = null,
        onError: ((String) -> Unit)? = null
    ) {
        // Obtener baseUrl de SharedPreferences
        val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
        val baseUrl = prefs.getString("baseUrl", "") ?: ""
        
        if (baseUrl.isEmpty()) {
            val errorMsg = "⚠️ BaseURL no configurado, no se puede enviar FCM action"
            Log.w(TAG, errorMsg)
            onError?.invoke(errorMsg)
            return
        }
        
        // Normalizar URL
        val cleanedBase = baseUrl.replace(Regex("appservices/?$", RegexOption.IGNORE_CASE), "")
        val finalUrl = if (cleanedBase.endsWith("/")) {
            "${cleanedBase}appservices/FCMActions"
        } else {
            "$cleanedBase/appservices/FCMActions"
        }
        
        Log.i(TAG, "📡 Enviando FCM action: $accion para móvil $movil")
        Log.d(TAG, "   URL: $finalUrl")
        
        // Ejecutar en coroutine para no bloquear el hilo principal
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val url = URL(finalUrl)
                val connection = url.openConnection() as HttpURLConnection
                
                connection.requestMethod = "POST"
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setRequestProperty("Accept", "application/json")
                connection.doOutput = true
                connection.connectTimeout = 15000
                connection.readTimeout = 15000
                
                // Body JSON
                val jsonBody = JSONObject().apply {
                    put("escenarioid", escenarioId)
                    put("movil", movil)
                    put("Accion", accion)
                }.toString()
                
                Log.d(TAG, "   Body: $jsonBody")
                
                // Enviar request
                val writer = OutputStreamWriter(connection.outputStream)
                writer.write(jsonBody)
                writer.flush()
                writer.close()
                
                // Leer respuesta
                val responseCode = connection.responseCode
                Log.d(TAG, "   Response Code: $responseCode")
                
                if (responseCode == HttpURLConnection.HTTP_OK) {
                    val reader = BufferedReader(InputStreamReader(connection.inputStream))
                    val response = reader.readText()
                    reader.close()
                    
                    Log.i(TAG, "✅ FCM action enviada exitosamente: $accion")
                    Log.d(TAG, "   Response: $response")
                    
                    // Loguear en CriticalLogger
                    CriticalLogger.logCritical(
                        TAG,
                        "FCM API: Comando enviado exitosamente al servidor",
                        mapOf(
                            "accion" to accion,
                            "movil" to movil,
                            "escenarioId" to escenarioId,
                            "responseCode" to responseCode,
                            "response" to response.take(200), // Limitar longitud
                            "trigger" to "native_service"
                        ),
                        "FCM_API_COMMAND_SENT"
                    )
                    
                    withContext(Dispatchers.Main) {
                        onSuccess?.invoke(response)
                    }
                } else {
                    val errorStream = connection.errorStream
                    val errorResponse = if (errorStream != null) {
                        BufferedReader(InputStreamReader(errorStream)).readText()
                    } else {
                        "No error details"
                    }
                    
                    val errorMsg = "❌ Error HTTP $responseCode: $errorResponse"
                    Log.e(TAG, errorMsg)
                    
                    CriticalLogger.logCritical(
                        TAG,
                        "FCM API ERROR: Fallo al enviar comando",
                        mapOf(
                            "accion" to accion,
                            "movil" to movil,
                            "escenarioId" to escenarioId,
                            "responseCode" to responseCode,
                            "errorResponse" to errorResponse.take(200),
                            "trigger" to "native_service"
                        ),
                        "FCM_API_COMMAND_FAILED"
                    )
                    
                    withContext(Dispatchers.Main) {
                        onError?.invoke(errorMsg)
                    }
                }
                
                connection.disconnect()
                
            } catch (e: Exception) {
                val errorMsg = "❌ Excepción enviando FCM action: ${e.message}"
                Log.e(TAG, errorMsg, e)
                
                CriticalLogger.logCritical(
                    TAG,
                    "FCM API EXCEPTION: Error de red o servidor",
                    e,
                    mapOf(
                        "accion" to accion,
                        "movil" to movil,
                        "escenarioId" to escenarioId,
                        "error_message" to (e.message ?: "Sin mensaje"),
                        "error_type" to e.javaClass.simpleName,
                        "trigger" to "native_service"
                    ),
                    "FCM_API_COMMAND_EXCEPTION"
                )
                
                withContext(Dispatchers.Main) {
                    onError?.invoke(errorMsg)
                }
            }
        }
    }
    
    /**
     * Helper rápido para force_gps_execution
     */
    fun forceGpsExecution(
        context: Context,
        escenarioId: Int,
        movil: String,
        onSuccess: ((String) -> Unit)? = null,
        onError: ((String) -> Unit)? = null
    ) {
        sendFcmAction(context, escenarioId, movil, "force_gps_execution", onSuccess, onError)
    }
    
    /**
     * Helper rápido para restart_gps_service
     */
    fun restartGpsService(
        context: Context,
        escenarioId: Int,
        movil: String,
        onSuccess: ((String) -> Unit)? = null,
        onError: ((String) -> Unit)? = null
    ) {
        sendFcmAction(context, escenarioId, movil, "restart_gps_service", onSuccess, onError)
    }
}
