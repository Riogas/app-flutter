package com.riogas.appmovil

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * 🔧 Sistema de recuperación de MovilId cuando se pierde
 * 
 * ESTRATEGIA DE RECUPERACIÓN (en orden de prioridad):
 * 1️⃣ SharedPreferences Flutter (FlutterSharedPreferences)
 * 2️⃣ SharedPreferences nativo (config)
 * 3️⃣ API /GetMovilActivo (usando DeviceId)
 * 
 * PROPÓSITO:
 * - Recuperar MovilId cuando watchdog intenta reiniciar GPS service
 * - Evitar que el servicio quede sin movil y no pueda reiniciarse
 * - Permitir auto-recuperación sin intervención manual
 */
object MovilRecoveryHelper {
    
    private const val TAG = "MovilRecoveryHelper"
    
    /**
     * Intenta recuperar el MovilId usando múltiples estrategias
     * 
     * @param context Contexto de la aplicación
     * @param deviceId ID del dispositivo (para consulta API si es necesario)
     * @return MovilId recuperado o null si no se pudo recuperar
     */
    suspend fun recoverMovilId(context: Context, deviceId: String): String? {
        Log.i(TAG, "🔍 [RECOVERY] Iniciando proceso de recuperación de MovilId...")
        Log.i(TAG, "🔍 [RECOVERY] DeviceId: $deviceId")
        
        // 1️⃣ Intentar recuperar desde SharedPreferences de Flutter
        val movilFromFlutter = tryRecoverFromFlutterPrefs(context)
        if (movilFromFlutter != null) {
            Log.i(TAG, "✅ [RECOVERY] MovilId recuperado desde Flutter SharedPreferences: $movilFromFlutter")
            CriticalLogger.logCritical(
                TAG,
                "RECOVERY SUCCESS: MovilId recuperado desde Flutter SharedPreferences",
                mapOf(
                    "movil" to movilFromFlutter,
                    "deviceId" to deviceId,
                    "recovery_method" to "flutter_shared_prefs",
                    "priority" to "1"
                ),
                "MOVIL_RECOVERY_FLUTTER_SUCCESS"
            )
            return movilFromFlutter
        }
        
        // 2️⃣ Intentar recuperar desde SharedPreferences nativo (backup)
        val movilFromNative = tryRecoverFromNativePrefs(context)
        if (movilFromNative != null) {
            Log.i(TAG, "✅ [RECOVERY] MovilId recuperado desde Native SharedPreferences: $movilFromNative")
            CriticalLogger.logCritical(
                TAG,
                "RECOVERY SUCCESS: MovilId recuperado desde Native SharedPreferences",
                mapOf(
                    "movil" to movilFromNative,
                    "deviceId" to deviceId,
                    "recovery_method" to "native_shared_prefs",
                    "priority" to "2"
                ),
                "MOVIL_RECOVERY_NATIVE_SUCCESS"
            )
            return movilFromNative
        }
        
        // 3️⃣ Último recurso: Consultar API /GetMovilActivo
        if (deviceId.isNotBlank()) {
            val movilFromApi = tryRecoverFromApi(context, deviceId)
            if (movilFromApi != null) {
                Log.i(TAG, "✅ [RECOVERY] MovilId recuperado desde API: $movilFromApi")
                
                // Guardar en SharedPreferences para futuros usos
                saveMovilToPreferences(context, movilFromApi)
                
                CriticalLogger.logCritical(
                    TAG,
                    "RECOVERY SUCCESS: MovilId recuperado desde API /GetMovilActivo",
                    mapOf(
                        "movil" to movilFromApi,
                        "deviceId" to deviceId,
                        "recovery_method" to "api_get_movil_activo",
                        "priority" to "3"
                    ),
                    "MOVIL_RECOVERY_API_SUCCESS"
                )
                return movilFromApi
            }
        }
        
        // ❌ No se pudo recuperar por ningún medio
        Log.e(TAG, "❌ [RECOVERY] No se pudo recuperar MovilId por ningún método")
        CriticalLogger.logCritical(
            TAG,
            "RECOVERY FAILED: No se pudo recuperar MovilId después de intentar todos los métodos",
            mapOf(
                "deviceId" to deviceId,
                "flutter_prefs" to "failed",
                "native_prefs" to "failed",
                "api_call" to "failed",
                "all_methods_exhausted" to "true"
            ),
            "MOVIL_RECOVERY_ALL_FAILED"
        )
        
        return null
    }
    
    /**
     * 1️⃣ Intenta recuperar MovilId desde SharedPreferences de Flutter
     * Formato: FlutterSharedPreferences.flutter.movil
     */
    private fun tryRecoverFromFlutterPrefs(context: Context): String? {
        return try {
            Log.d(TAG, "🔍 [RECOVERY] Intentando recuperar desde Flutter SharedPreferences...")
            
            val flutterPrefs = context.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE
            )
            
            // Intentar varias posibles claves
            val possibleKeys = listOf(
                "flutter.movil",
                "flutter.Movil", 
                "movil",
                "Movil"
            )
            
            for (key in possibleKeys) {
                val value = flutterPrefs.getString(key, null)
                if (!value.isNullOrBlank()) {
                    Log.d(TAG, "   ✅ Encontrado en clave '$key': $value")
                    return value
                }
            }
            
            Log.d(TAG, "   ❌ No encontrado en Flutter SharedPreferences")
            null
            
        } catch (e: Exception) {
            Log.e(TAG, "   ❌ Error leyendo Flutter SharedPreferences: ${e.message}", e)
            null
        }
    }
    
    /**
     * 2️⃣ Intenta recuperar MovilId desde SharedPreferences nativo
     * Formato: config.last_movil
     */
    private fun tryRecoverFromNativePrefs(context: Context): String? {
        return try {
            Log.d(TAG, "🔍 [RECOVERY] Intentando recuperar desde Native SharedPreferences...")
            
            val nativePrefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            val movil = nativePrefs.getString("last_movil", null)
            
            if (!movil.isNullOrBlank()) {
                Log.d(TAG, "   ✅ Encontrado: $movil")
                return movil
            }
            
            Log.d(TAG, "   ❌ No encontrado en Native SharedPreferences")
            null
            
        } catch (e: Exception) {
            Log.e(TAG, "   ❌ Error leyendo Native SharedPreferences: ${e.message}", e)
            null
        }
    }
    
    /**
     * 3️⃣ Último recurso: Consultar API /GetMovilActivo
     * 
     * Endpoint: POST /GetMovilActivo
     * Body: { "DeviceId": "string" }
     * Response: { "MovilId": "693" }
     */
    private suspend fun tryRecoverFromApi(context: Context, deviceId: String): String? {
        return withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "🔍 [RECOVERY] Intentando recuperar desde API /GetMovilActivo...")
                Log.d(TAG, "   📱 DeviceId: $deviceId")
                
                // Obtener baseUrl desde SharedPreferences (desarrollo vs producción)
                // La baseUrl se guarda en "config" SharedPreferences desde Flutter (login_page.dart y settings_page.dart)
                val configPrefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
                val baseUrl = configPrefs.getString("baseUrl", null) 
                    ?: "https://www.riogas.uy/ica_geos_/appservices/"
                
                val apiUrl = "${baseUrl}GetMovilActivo"
                Log.d(TAG, "   🌐 URL: $apiUrl")
                Log.d(TAG, "   🔧 BaseUrl leída desde config SharedPreferences: $baseUrl")
                
                // Crear conexión HTTP
                val url = URL(apiUrl)
                val connection = url.openConnection() as HttpURLConnection
                
                connection.apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Accept", "application/json")
                    doOutput = true
                    doInput = true
                    connectTimeout = 10000 // 10 segundos
                    readTimeout = 10000
                }
                
                // Crear body JSON
                val jsonBody = JSONObject().apply {
                    put("DeviceId", deviceId)
                }
                
                Log.d(TAG, "   📤 Request body: $jsonBody")
                
                // Enviar request
                connection.outputStream.use { os ->
                    val input = jsonBody.toString().toByteArray(Charsets.UTF_8)
                    os.write(input, 0, input.size)
                }
                
                // Leer response
                val responseCode = connection.responseCode
                Log.d(TAG, "   📥 Response code: $responseCode")
                
                if (responseCode == HttpURLConnection.HTTP_OK) {
                    val response = connection.inputStream.bufferedReader().use { it.readText() }
                    Log.d(TAG, "   📥 Response: $response")
                    
                    // Parsear JSON response
                    val jsonResponse = JSONObject(response)
                    val movilId = jsonResponse.optString("MovilId", null)
                    
                    if (!movilId.isNullOrBlank()) {
                        Log.d(TAG, "   ✅ MovilId obtenido desde API: $movilId")
                        return@withContext movilId
                    } else {
                        Log.w(TAG, "   ⚠️ API respondió OK pero sin MovilId válido")
                    }
                } else {
                    val errorBody = connection.errorStream?.bufferedReader()?.use { it.readText() } ?: "Sin detalle"
                    Log.e(TAG, "   ❌ Error HTTP $responseCode: $errorBody")
                }
                
                null
                
            } catch (e: Exception) {
                Log.e(TAG, "   ❌ Error llamando a API /GetMovilActivo: ${e.message}", e)
                
                CriticalLogger.logCritical(
                    TAG,
                    "RECOVERY ERROR: Fallo al llamar API /GetMovilActivo",
                    e,
                    mapOf(
                        "deviceId" to deviceId,
                        "error_type" to e.javaClass.simpleName,
                        "error_message" to (e.message ?: "Sin mensaje")
                    ),
                    "MOVIL_RECOVERY_API_ERROR"
                )
                
                null
            }
        }
    }
    
    /**
     * Guarda el MovilId recuperado en ambos SharedPreferences
     * para evitar tener que recuperarlo de nuevo
     */
    private fun saveMovilToPreferences(context: Context, movil: String) {
        try {
            // Guardar en Native SharedPreferences
            val nativePrefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            nativePrefs.edit().putString("last_movil", movil).apply()
            Log.d(TAG, "💾 [RECOVERY] MovilId guardado en Native SharedPreferences")
            
            // Intentar guardar en Flutter SharedPreferences (puede fallar si no está inicializado)
            try {
                val flutterPrefs = context.getSharedPreferences(
                    "FlutterSharedPreferences",
                    Context.MODE_PRIVATE
                )
                flutterPrefs.edit().putString("flutter.movil", movil).apply()
                Log.d(TAG, "💾 [RECOVERY] MovilId guardado en Flutter SharedPreferences")
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ [RECOVERY] No se pudo guardar en Flutter SharedPreferences: ${e.message}")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ [RECOVERY] Error guardando MovilId en SharedPreferences: ${e.message}", e)
        }
    }
}
