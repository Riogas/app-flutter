package com.riogas.appmovil.tracking

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.time.Instant
import java.time.format.DateTimeFormatter
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

    /**
     * POST a https://track.riogas.com.uy/api/import/gps, un fix por request — mismo
     * formato (objeto plano) que LocationHelper.sendToN8nWebhook() manda hoy
     * (LocationHelper.kt:2379-2513). Corta el loop al primer fallo, igual que flushRioGas.
     */
    suspend fun flushTrack(context: Context): Int {
        val dao = TrackingDatabase.get(context).locationFixDao()
        val batch = dao.getUnsentTrack(BATCH_LIMIT)
        if (batch.isEmpty()) return 0

        // Mismo flag que LocationHelper.sendToN8nWebhook (LocationHelper.kt:2382-2394):
        // si el envío a track está deshabilitado, no se consume la cola (no es un fallo).
        val configPrefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
        if (!configPrefs.getBoolean("gpsN8nEnabled", false)) {
            Log.d(TAG, "gpsN8nEnabled=false, no se envía a track.riogas")
            return 0
        }

        var sent = 0
        for (fix in batch) {
            if (postToTrack(context, fix)) {
                dao.markTrackSent(listOf(fix.id))
                sent++
            } else {
                dao.incrementAttempts(listOf(fix.id))
                break
            }
        }
        return sent
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
     * Body: objeto JSON plano, un fix por request, mismos nombres/tipos de campo que
     * LocationHelper.sendToN8nWebhook() (LocationHelper.kt:2417-2500). Los campos que
     * describen el fix salen de LocationFixEntity; los de contexto vivo del dispositivo
     * (batería, red, memoria, permisos, versión de app, etc.) se recalculan acá al momento
     * del envío con las mismas lecturas de prefs/system services que usa LocationHelper hoy
     * (ver helpers privados debajo). Excepciones documentadas en el reporte:
     * satellites_used/total/avg_snr y last_reset_reason viven en `private var` de
     * LocationHelper (no accesibles sin tocar ese archivo) → van con el mismo valor inicial
     * que tienen en LocationHelper antes de la primera actualización GNSS (0/0/0.0/"No").
     */
    private suspend fun postToTrack(context: Context, fix: LocationFixEntity): Boolean = withContext(Dispatchers.IO) {
        try {
            val isoNow = DateTimeFormatter.ISO_INSTANT.format(Instant.now())
            val appState = com.example.moveit.LocationHelper.isAppActive(context)
            val batteryInfo = getBatteryInfo(context)
            val networkInfo = getNetworkInfo(context)
            val locationPermissions = getAllLocationPermissions(context)
            val deviceInfo = getDeviceInfo()
            val powerInfo = getPowerManagementInfo(context)
            val memoryInfo = getMemoryInfo(context)

            val payload = JSONObject().apply {
                // Datos básicos de ubicación (LocationHelper.kt:2418-2431)
                put("token", TOKEN)
                put("movil", fix.movil.toString()) // String en el original (param movil: String)
                put("latitud", fix.latitud)
                put("longitud", fix.longitud)
                put("utmX", fix.utmX)
                put("utmY", fix.utmY)
                put("deviceId", fix.deviceId)
                put("fechaHora", fix.fechaHora)
                put("distanciaRecorrida", fix.distanciaRecorrida)
                put("velocidad", fix.velocidad)
                put("escenarioid", fix.escenario.toString()) // String en el original (param escenario: String)
                put("usuario", fix.usuario)

                // Estado de la app (LocationHelper.kt:2433-2435)
                put("appState", appState)
                put("movementType", fix.movementType)

                // GPS/Location info (LocationHelper.kt:2437-2455)
                put("accuracy", fix.accuracy)
                putNullable("altitude", fix.altitude)
                putNullable("bearing", fix.bearing)
                put("provider", fix.provider)
                putNullable("speed_accuracy", fix.speedAccuracy)
                put("is_mock_location", fix.isMockLocation)
                put("location_age_ms", System.currentTimeMillis() - fix.createdAt)
                put("gps_enabled", isGPSEnabled(context))
                put("satellites_used", 0)
                put("satellites_total", 0)
                put("satellites_avg_snr", 0.0f)

                // Permisos de ubicación (LocationHelper.kt:2458-2461)
                put("permission_fine_location", locationPermissions["permission_fine_location"])
                put("permission_coarse_location", locationPermissions["permission_coarse_location"])
                put("permission_background_location", locationPermissions["permission_background_location"])
                put("notifications_enabled", areNotificationsEnabled(context))

                // Batería (LocationHelper.kt:2464-2469)
                put("battery_level", batteryInfo["battery_level"])
                put("battery_charging", batteryInfo["battery_charging"])
                put("battery_status", batteryInfo["battery_status"])
                put("battery_saver_on", powerInfo["battery_saver_on"])
                put("battery_optimization_ignored", powerInfo["battery_optimization_ignored"])
                put("doze_mode_active", powerInfo["doze_mode_active"])

                // Red (LocationHelper.kt:2472-2473)
                put("network_type", networkInfo["network_type"])
                put("network_connected", networkInfo["network_connected"])

                // Dispositivo (LocationHelper.kt:2476-2480)
                put("device_manufacturer", deviceInfo["device_manufacturer"])
                put("device_model", deviceInfo["device_model"])
                put("device_brand", deviceInfo["device_brand"])
                put("android_version", deviceInfo["android_version"])
                put("android_release", deviceInfo["android_release"])

                // Memoria (LocationHelper.kt:2483-2485)
                put("memory_available_mb", memoryInfo["memory_available_mb"])
                put("memory_total_mb", memoryInfo["memory_total_mb"])
                put("memory_low", memoryInfo["memory_low"])

                // Control (LocationHelper.kt:2488-2495)
                put("execution_counter", fix.executionCounter)
                put("last_reset_reason", "No")
                put("app_version", getAppVersion(context))

                // Timestamps (LocationHelper.kt:2498-2499)
                put("timestamp_local", getTimestampLocal())
                put("timestamp_utc", isoNow)
            }

            val request = Request.Builder()
                .url(TRACK_URL)
                .addHeader("Content-Type", "application/json")
                .post(payload.toString().toRequestBody("application/json".toMediaType()))
                .build()

            client.newCall(request).execute().use { response ->
                if (response.isSuccessful) {
                    true
                } else {
                    Log.w(TAG, "track fix ${fix.id} HTTP ${response.code}: ${response.message}")
                    false
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "track fix ${fix.id} error: ${e.message}")
            false
        }
    }

    /**
     * Body: mismos campos que LocationHelper.invokeRegistrarCoordenadasV2ApiWithRetry()
     * (LocationHelper.kt:1560-1629: token, movil, Latitud, longitud, utmX, utmY, DeviceId,
     * FechaHora, DistanciaRecorrida, Velocidad, escenarioid, usuario, INAux1, INAux2,
     * NroSesion) más headers accept/Content-Type/Cookie GX_CLIENT_ID y la normalización
     * de baseUrl (LocationHelper.kt:1565-1579). INAux2 no lleva el diagnóstico en vivo
     * completo del original (appState/notif/permisos/GPS/retry/reset) porque ese formato es
     * específico de este endpoint legacy y no fue parte del pedido de fix de review (que se
     * enfocó en track) → se mantiene "Cola:Replay" como marcador.
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
                put("utmX", fix.utmX.toString())
                put("utmY", fix.utmY.toString())
                put("DeviceId", fix.deviceId)
                put("FechaHora", fix.fechaHora)
                put("DistanciaRecorrida", fix.distanciaRecorrida)
                put("Velocidad", fix.velocidad)
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

    private fun JSONObject.putNullable(key: String, value: Any?) {
        put(key, value ?: JSONObject.NULL)
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

    // ============================================================================
    // Helpers de contexto en vivo, replicados de LocationHelper.kt (privados ahí,
    // por eso se duplica la lógica en vez de invocarlos) — mismos system services /
    // SharedPreferences que lee LocationHelper.sendToN8nWebhook() hoy.
    // ============================================================================

    /** Replica LocationHelper.getBatteryInfo (LocationHelper.kt:2549-2577). */
    private fun getBatteryInfo(context: Context): Map<String, Any> {
        return try {
            val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            val batteryLevel = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            val batteryStatus = context.registerReceiver(null, android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))
            val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL

            mapOf(
                "battery_level" to batteryLevel,
                "battery_charging" to isCharging,
                "battery_status" to when (status) {
                    BatteryManager.BATTERY_STATUS_CHARGING -> "CHARGING"
                    BatteryManager.BATTERY_STATUS_DISCHARGING -> "DISCHARGING"
                    BatteryManager.BATTERY_STATUS_FULL -> "FULL"
                    BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "NOT_CHARGING"
                    else -> "UNKNOWN"
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error obteniendo info de batería: ${e.message}")
            mapOf("battery_level" to -1, "battery_charging" to false, "battery_status" to "ERROR")
        }
    }

    /** Replica LocationHelper.getNetworkInfo (LocationHelper.kt:2582-2618). */
    private fun getNetworkInfo(context: Context): Map<String, Any> {
        return try {
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val activeNetwork = connectivityManager.activeNetwork
                val capabilities = connectivityManager.getNetworkCapabilities(activeNetwork)
                val networkType = when {
                    capabilities == null -> "NONE"
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "WiFi"
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "CELLULAR"
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ETHERNET"
                    else -> "UNKNOWN"
                }
                mapOf("network_type" to networkType, "network_connected" to (activeNetwork != null))
            } else {
                @Suppress("DEPRECATION")
                val activeNetworkInfo = connectivityManager.activeNetworkInfo
                mapOf(
                    "network_type" to (activeNetworkInfo?.typeName ?: "NONE"),
                    "network_connected" to (activeNetworkInfo?.isConnected ?: false)
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error obteniendo info de red: ${e.message}")
            mapOf("network_type" to "ERROR", "network_connected" to false)
        }
    }

    /**
     * Replica LocationHelper.getAllLocationPermissions (LocationHelper.kt:2623-2633).
     * Usa Context.checkSelfPermission (nativo, API 23+) en vez de ActivityCompat para no
     * agregar una dependencia nueva a androidx.core — mismo resultado, minSdk=25.
     */
    private fun getAllLocationPermissions(context: Context): Map<String, Boolean> {
        return mapOf(
            "permission_fine_location" to (context.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED),
            "permission_coarse_location" to (context.checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED),
            "permission_background_location" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                context.checkSelfPermission(android.Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
            } else {
                true
            }
        )
    }

    /** Replica LocationHelper.getDeviceInfo (LocationHelper.kt:2638-2647), sin device_fingerprint (no usado en el payload). */
    private fun getDeviceInfo(): Map<String, Any> {
        return mapOf(
            "device_manufacturer" to Build.MANUFACTURER,
            "device_model" to Build.MODEL,
            "device_brand" to Build.BRAND,
            "android_version" to Build.VERSION.SDK_INT,
            "android_release" to Build.VERSION.RELEASE
        )
    }

    /** Replica LocationHelper.getPowerManagementInfo (LocationHelper.kt:2652-2677). */
    private fun getPowerManagementInfo(context: Context): Map<String, Any> {
        return try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            mapOf(
                "battery_saver_on" to powerManager.isPowerSaveMode,
                "battery_optimization_ignored" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    powerManager.isIgnoringBatteryOptimizations(context.packageName)
                } else {
                    true
                },
                "doze_mode_active" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    powerManager.isDeviceIdleMode
                } else {
                    false
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error obteniendo power management info: ${e.message}")
            mapOf("battery_saver_on" to false, "battery_optimization_ignored" to false, "doze_mode_active" to false)
        }
    }

    /** Replica LocationHelper.getMemoryInfo (LocationHelper.kt:2682-2701). */
    private fun getMemoryInfo(context: Context): Map<String, Any> {
        return try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            mapOf(
                "memory_available_mb" to (memoryInfo.availMem / 1024 / 1024),
                "memory_total_mb" to (memoryInfo.totalMem / 1024 / 1024),
                "memory_low" to memoryInfo.lowMemory
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error obteniendo memory info: ${e.message}")
            mapOf("memory_available_mb" to -1, "memory_total_mb" to -1, "memory_low" to false)
        }
    }

    /** Replica LocationHelper.isGPSEnabled (LocationHelper.kt:1429-1432). */
    private fun isGPSEnabled(context: Context): Boolean {
        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
        return locationManager.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER)
    }

    /** Replica LocationHelper.areNotificationsEnabled (LocationHelper.kt:1424-1427). */
    private fun areNotificationsEnabled(context: Context): Boolean {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        return notificationManager.areNotificationsEnabled()
    }

    /** Replica el bloque try/catch de app_version en LocationHelper.kt:2490-2495. */
    private fun getAppVersion(context: Context): String {
        return try {
            val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
            packageInfo.versionName ?: "unknown"
        } catch (e: Exception) {
            "unknown"
        }
    }

    /** Replica LocationHelper.kt:2498 (timestamp_local). */
    private fun getTimestampLocal(): String {
        return java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssZ", java.util.Locale.getDefault()).format(java.util.Date())
    }
}
