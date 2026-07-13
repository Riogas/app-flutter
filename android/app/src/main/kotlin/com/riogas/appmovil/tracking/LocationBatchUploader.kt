package com.riogas.appmovil.tracking

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Uploader de la cola durable (Room) de fixes GPS.
 *
 * Reglas WS-C: nunca se borra/marca sent antes del 200 del POST; se marca por target
 * (sentTrack/sentRioGas independientes); sin Thread.sleep — los reintentos quedan a
 * cargo del próximo tick de flush (no hay retry inmediato acá).
 */
object LocationBatchUploader {
    private const val TAG = "LocationBatchUploader"
    private const val BATCH_LIMIT = 200
    private const val TOKEN = "IcA.FwL.1710.!"
    private const val TRACK_URL = "https://track.riogas.com.uy/api/import/gps"

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    /** POST batch (array JSON) a https://track.riogas.com.uy/api/import/gps. */
    suspend fun flushTrack(context: Context): Int {
        val dao = TrackingDatabase.get(context).locationFixDao()
        val batch = dao.getUnsentTrack(BATCH_LIMIT)
        if (batch.isEmpty()) return 0

        // Mismo flag que LocationHelper.sendToN8nWebhook (LocationHelper.kt:2382-2394):
        // si el envío a track está deshabilitado, no se consume la cola (no es un fallo).
        val configPrefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
        if (!configPrefs.getBoolean("gpsN8nEnabled", false)) {
            Log.d(TAG, "gpsN8nEnabled=false, no se envía batch a track.riogas")
            return 0
        }

        val ok = postToTrack(batch)
        return if (ok) {
            dao.markTrackSent(batch.map { it.id })
            batch.size
        } else {
            dao.incrementAttempts(batch.map { it.id })
            0
        }
    }

    /** POST a {baseUrl}RegistrarCoordenadasV2, un fix por request (formato legacy actual). */
    suspend fun flushRioGas(context: Context): Int {
        val dao = TrackingDatabase.get(context).locationFixDao()
        val batch = dao.getUnsentRioGas(BATCH_LIMIT)
        var sent = 0
        for (fix in batch) {
            if (postToRioGas(context, fix)) {
                dao.markRioGasSent(listOf(fix.id))
                sent++
            } else {
                dao.incrementAttempts(listOf(fix.id))
                break
            }
        }
        return sent
    }

    /**
     * Body: array JSON, un objeto por fix, con los mismos nombres de campo que
     * LocationHelper.sendToN8nWebhook() (LocationHelper.kt:2417-2500: token, movil,
     * latitud, longitud, utmX, utmY, deviceId, fechaHora, distanciaRecorrida, velocidad,
     * escenarioid, usuario, accuracy). Los campos de contexto en vivo (batería, red,
     * dispositivo, estado de la app, etc.) no existen en LocationFixEntity porque el
     * replay ocurre después de capturado el fix, así que se omiten (ver Deviations).
     */
    private suspend fun postToTrack(batch: List<LocationFixEntity>): Boolean = withContext(Dispatchers.IO) {
        try {
            val array = JSONArray()
            batch.forEach { fix ->
                val obj = JSONObject().apply {
                    put("token", TOKEN)
                    put("movil", fix.movil)
                    put("latitud", fix.latitud)
                    put("longitud", fix.longitud)
                    put("utmX", 0.0)
                    put("utmY", 0.0)
                    put("deviceId", fix.deviceId)
                    put("fechaHora", fix.fechaHora)
                    put("distanciaRecorrida", 0.0f)
                    put("velocidad", 0.0f)
                    put("escenarioid", fix.escenario)
                    put("usuario", fix.usuario)
                    put("accuracy", fix.accuracy)
                }
                array.put(obj)
            }
            val body = array.toString().toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url(TRACK_URL)
                .addHeader("Content-Type", "application/json")
                .post(body)
                .build()

            client.newCall(request).execute().use { response ->
                if (response.isSuccessful) {
                    true
                } else {
                    Log.w(TAG, "track batch HTTP ${response.code}: ${response.message}")
                    false
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "track batch error: ${e.message}")
            false
        }
    }

    /**
     * Body: mismos campos que LocationHelper.invokeRegistrarCoordenadasV2ApiWithRetry()
     * (LocationHelper.kt:1560-1629: token, movil, Latitud, longitud, utmX, utmY, DeviceId,
     * FechaHora, DistanciaRecorrida, Velocidad, escenarioid, usuario, INAux1, INAux2,
     * NroSesion) más headers accept/Content-Type/Cookie GX_CLIENT_ID y la normalización
     * de baseUrl (LocationHelper.kt:1565-1579). utmX/utmY/DistanciaRecorrida/Velocidad no
     * existen en LocationFixEntity (no se recalculan en el replay) → van en 0. INAux2 no
     * lleva el diagnóstico en vivo (appState/batería/etc., no disponible en replay
     * diferido) → se marca "Cola:Replay" para distinguir estos envíos en el backend.
     */
    private suspend fun postToRioGas(context: Context, fix: LocationFixEntity): Boolean = withContext(Dispatchers.IO) {
        try {
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            var baseUrl = flutterPrefs.getString("flutter.baseUrl", "https://www.riogas.uy/ica_geos_/appservices/")
                ?: "https://www.riogas.uy/ica_geos_/appservices/"
            if (!baseUrl.endsWith("/appservices/")) {
                baseUrl = if (baseUrl.endsWith("/")) "${baseUrl}appservices/" else "${baseUrl}/appservices/"
            }
            val url = "${baseUrl}RegistrarCoordenadasV2"

            val jsonBody = JSONObject().apply {
                put("token", TOKEN)
                put("movil", fix.movil)
                put("Latitud", fix.latitud.toString())
                put("longitud", fix.longitud.toString())
                put("utmX", "0")
                put("utmY", "0")
                put("DeviceId", fix.deviceId)
                put("FechaHora", fix.fechaHora)
                put("DistanciaRecorrida", 0.0f)
                put("Velocidad", 0.0f)
                put("escenarioid", fix.escenario)
                put("usuario", fix.usuario)
                put("INAux1", fix.movil.toString())
                put("INAux2", "Cola:Replay")
                put("NroSesion", "")
            }.toString()

            val gxClientId = getOrCreateGxClientId(context)

            val request = Request.Builder()
                .url(url)
                .addHeader("accept", "application/json")
                .addHeader("Content-Type", "application/json")
                .addHeader("Cookie", "GX_CLIENT_ID=$gxClientId")
                .post(jsonBody.toRequestBody("application/json".toMediaType()))
                .build()

            client.newCall(request).execute().use { response ->
                if (response.isSuccessful) {
                    true
                } else {
                    Log.w(TAG, "RioGas fix ${fix.id} HTTP ${response.code}: ${response.message}")
                    false
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "RioGas fix ${fix.id} error: ${e.message}")
            false
        }
    }

    /**
     * Replica LocationHelper.getOrCreateGxClientId (privado, LocationHelper.kt:90-107)
     * leyendo/escribiendo la misma key en FlutterSharedPreferences para reutilizar el
     * mismo GX_CLIENT_ID persistente que usa el resto de la app.
     */
    private fun getOrCreateGxClientId(context: Context): String {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val key = "flutter.gxClientId"
        var gxClientId = prefs.getString(key, null)
        if (gxClientId == null) {
            gxClientId = java.util.UUID.randomUUID().toString()
            prefs.edit().putString(key, gxClientId).apply()
        }
        return gxClientId
    }
}
