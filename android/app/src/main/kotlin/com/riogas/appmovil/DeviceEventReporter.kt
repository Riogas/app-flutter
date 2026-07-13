package com.riogas.appmovil

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Reporta eventos de dispositivo (§8.6) al backend.
 * Transporte transitorio: endpoint RegistrarErrores con campo tipo dentro de data.
 * Cuando GeneXus publique RegistrarEventoDispositivo, cambiar ENDPOINT.
 */
object DeviceEventReporter {
    private const val TAG = "DeviceEventReporter"
    private const val ENDPOINT = "RegistrarErrores" // TODO backend: RegistrarEventoDispositivo
    private const val TOKEN = "IcA.FwL.1710.!"

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    fun report(context: Context, tipo: String, motivo: String = "", extra: Map<String, String> = emptyMap()) {
        val appContext = context.applicationContext
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val flutterPrefs = appContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val config = appContext.getSharedPreferences("config", Context.MODE_PRIVATE)
                var baseUrl = flutterPrefs.getString("flutter.baseUrl", "https://www.riogas.uy/ica_geos_/appservices/")
                    ?: "https://www.riogas.uy/ica_geos_/appservices/"
                if (!baseUrl.contains("/appservices/")) {
                    baseUrl = baseUrl.trimEnd('/') + "/appservices/"
                }
                val movil = config.getString("last_movil", "") ?: ""
                val usuario = config.getString("last_usuario", "") ?: ""
                val deviceId = config.getString("last_deviceId", "") ?: ""

                val data = JSONObject().apply {
                    put("tipo", tipo)
                    put("motivo", motivo)
                    put("ts", System.currentTimeMillis())
                    put("origen", "device_event")
                    extra.forEach { (k, v) -> put(k, v) }
                }
                val payload = JSONObject().apply {
                    put("token", TOKEN)
                    put("movil", movil.toIntOrNull() ?: 0)
                    put("DeviceId", deviceId)
                    put("usuario", usuario)
                    put("data", data.toString())
                }

                val body = payload.toString().toRequestBody("application/json".toMediaType())
                val request = Request.Builder().url("$baseUrl$ENDPOINT").post(body).build()

                var attempts = 0
                while (attempts < 2) {
                    attempts++
                    try {
                        client.newCall(request).execute().use { resp ->
                            if (resp.isSuccessful) {
                                Log.i(TAG, "evento $tipo reportado (intento $attempts)")
                                return@launch
                            }
                            Log.w(TAG, "evento $tipo HTTP ${resp.code} (intento $attempts)")
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "evento $tipo fallo intento $attempts: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "report() error no fatal: ${e.message}")
            }
        }
    }
}
