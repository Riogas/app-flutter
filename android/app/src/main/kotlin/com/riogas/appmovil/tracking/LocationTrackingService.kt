package com.riogas.appmovil.tracking

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import com.riogas.appmovil.DeviceEventReporter
import com.riogas.appmovil.ServiceStatusFlags
import kotlinx.coroutines.*
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class LocationTrackingService : Service() {

    companion object {
        private const val TAG = "LocationTrackingService"
        private const val NOTIF_ID = 1710
        private const val CHANNEL_ID = "location_channel"
        private const val SILENCE_THRESHOLD_MS = 90_000L
        private const val TRACK_FLUSH_MS = 30_000L
        private const val RIOGAS_FLUSH_MS = 180_000L
        private const val WATCH_TICK_MS = 30_000L
        private const val MIN_UPDATE_MS = 5_000L
        private const val DEFAULT_INTERVAL_S = 12

        @Volatile var isRunning = false
            private set

        /** Idempotente: si ya corre, solo actualiza extras. Llamar SOLO desde foreground
         *  (Activity) o desde FCM high-priority / health-check con exención. */
        fun start(context: Context, movil: String, escenario: String, usuario: String, deviceId: String) {
            val intent = Intent(context, LocationTrackingService::class.java).apply {
                putExtra("movil", movil); putExtra("escenario", escenario)
                putExtra("usuario", usuario); putExtra("deviceId", deviceId)
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LocationTrackingService::class.java))
        }
    }

    private lateinit var fusedClient: FusedLocationProviderClient
    private var locationCallback: LocationCallback? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    @Volatile private var lastFixElapsed = 0L
    private var movil = ""; private var escenario = "0"; private var usuario = ""; private var deviceId = ""

    override fun onCreate() {
        super.onCreate()
        fusedClient = LocationServices.getFusedLocationProviderClient(this)
        startInForeground()
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let {
            it.getStringExtra("movil")?.takeIf { s -> s.isNotBlank() }?.let { s -> movil = s }
            it.getStringExtra("escenario")?.takeIf { s -> s.isNotBlank() }?.let { s -> escenario = s }
            it.getStringExtra("usuario")?.takeIf { s -> s.isNotBlank() }?.let { s -> usuario = s }
            it.getStringExtra("deviceId")?.takeIf { s -> s.isNotBlank() }?.let { s -> deviceId = s }
        }
        if (movil.isBlank()) restoreIdentityFromPrefs()
        persistIdentityToPrefs()

        if (ServiceStatusFlags.isServiceDisabled(this)) {
            Log.w(TAG, "service_disabled=true → no arranca tracking")
            stopSelf(); return START_NOT_STICKY
        }

        registerLocationUpdates()   // idempotente: remueve callback previo antes de registrar
        startLoops()                // idempotente: cancela jobs previos
        return START_STICKY
    }

    private fun startInForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Ubicación", NotificationManager.IMPORTANCE_DEFAULT)
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
        }
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MoveIT")
            .setContentText("Rastreo de ubicación activo")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else startForeground(NOTIF_ID, notif)
    }

    private fun intervalSeconds(): Int {
        val v = getSharedPreferences("config", MODE_PRIVATE).getInt("tracking_interval_seconds", DEFAULT_INTERVAL_S)
        return if (v > 0) v else DEFAULT_INTERVAL_S   // constante validada >0
    }

    /**
     * @param reportIfNoPermission si false, no reporta heartbeat_no_gps por falta de permiso
     * en el early-return (el llamador ya reportó, ej. el watchdog) — máximo 1 evento
     * heartbeat_no_gps por tick.
     * @return true solo si el registro con FusedLocationProviderClient se realizó efectivamente.
     */
    private fun registerLocationUpdates(reportIfNoPermission: Boolean = true): Boolean {
        if (!hasLocationPermission()) {
            if (reportIfNoPermission) {
                DeviceEventReporter.report(this, "heartbeat_no_gps", "NO_PERMISSION")
            }
            return false
        }
        locationCallback?.let { fusedClient.removeLocationUpdates(it) }
        locationCallback = null
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, intervalSeconds() * 1000L)
            .setMinUpdateIntervalMillis(MIN_UPDATE_MS)
            .build()
        val callback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val loc = result.lastLocation ?: return
                lastFixElapsed = android.os.SystemClock.elapsedRealtime()
                val fechaHora = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(Date())
                scope.launch {
                    try {
                        // UTM real (mismo cálculo que LocationHelper.convertToUTM, EPSG:4326 → UTM21S)
                        val utm = com.example.moveit.LocationHelper.convertToUTM(loc.latitude, loc.longitude)
                        TrackingDatabase.get(this@LocationTrackingService).locationFixDao().insert(
                            LocationFixEntity(
                                movil = movil.toIntOrNull() ?: 0,
                                escenario = escenario.toIntOrNull() ?: 0,
                                usuario = usuario, deviceId = deviceId,
                                latitud = loc.latitude, longitud = loc.longitude,
                                accuracy = loc.accuracy, fechaHora = fechaHora,
                                createdAt = System.currentTimeMillis(),
                                utmX = utm.first, utmY = utm.second,
                                // Columnas que salen directo del objeto Location (Task 5 las agregó
                                // a la entity con default; acá se pueblan igual que
                                // LocationHelper.kt:2438-2450). Las de contexto vivo cross-fix
                                // (distanciaRecorrida/movementType/executionCounter) las deja con
                                // default: no son atributos de Location, requieren estado acumulado
                                // que no vive en este callback.
                                altitude = if (loc.hasAltitude()) loc.altitude else null,
                                bearing = if (loc.hasBearing()) loc.bearing else null,
                                provider = loc.provider ?: "",
                                velocidad = if (loc.hasSpeed()) loc.speed else 0f,
                                speedAccuracy = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && loc.hasSpeedAccuracy()) {
                                    loc.speedAccuracyMetersPerSecond
                                } else null,
                                isMockLocation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                    loc.isMock
                                } else {
                                    @Suppress("DEPRECATION")
                                    loc.isFromMockProvider
                                }
                            )
                        )
                    } catch (e: Exception) { Log.e(TAG, "insert fix: ${e.message}") }
                }
            }
        }
        return try {
            fusedClient.requestLocationUpdates(request, callback, Looper.getMainLooper())
            locationCallback = callback
            lastFixElapsed = android.os.SystemClock.elapsedRealtime()
            Log.i(TAG, "requestLocationUpdates registrado (intervalo ${intervalSeconds()}s)")
            true
        } catch (e: SecurityException) {
            DeviceEventReporter.report(this, "heartbeat_no_gps", "NO_PERMISSION", mapOf("error" to (e.message ?: "")))
            false
        }
    }

    private var flushTrackJob: Job? = null
    private var flushRioGasJob: Job? = null
    private var watchJob: Job? = null

    private fun startLoops() {
        flushTrackJob?.cancel(); flushRioGasJob?.cancel(); watchJob?.cancel()
        flushTrackJob = scope.launch {
            while (isActive) { delay(TRACK_FLUSH_MS)
                try { LocationBatchUploader.flushTrack(this@LocationTrackingService) }
                catch (e: Exception) { Log.e(TAG, "flushTrack: ${e.message}") } }
        }
        flushRioGasJob = scope.launch {
            while (isActive) { delay(RIOGAS_FLUSH_MS)
                try {
                    LocationBatchUploader.flushRioGas(this@LocationTrackingService)
                    val dao = TrackingDatabase.get(this@LocationTrackingService).locationFixDao()
                    dao.purgeSent(System.currentTimeMillis() - 24 * 3600_000L)
                    // Retención dura de 7 días pase lo que pase: cubre el caso
                    // gpsN8nEnabled=false, donde flushTrack nunca marca sentTrack y purgeSent
                    // nunca borra esas filas (crecimiento sin límite de tracking.db).
                    dao.purgeOlderThan(System.currentTimeMillis() - 7 * 24 * 3600_000L)
                } catch (e: Exception) { Log.e(TAG, "flushRioGas: ${e.message}") } }
        }
        // Auto-monitoreo interno: ¿recibí un fix en los últimos 90 s?
        watchJob = scope.launch {
            while (isActive) { delay(WATCH_TICK_MS)
                val silence = android.os.SystemClock.elapsedRealtime() - lastFixElapsed
                if (silence > SILENCE_THRESHOLD_MS) {
                    val motivo = when {
                        !hasLocationPermission() -> "NO_PERMISSION"
                        !isGpsProviderEnabled() -> "GPS_DISABLED_IN_SETTINGS"
                        else -> "NO_SIGNAL"
                    }
                    Log.w(TAG, "silencio ${silence}ms → re-registrando callback ($motivo)")
                    DeviceEventReporter.report(this@LocationTrackingService, "heartbeat_no_gps", motivo,
                        mapOf("silence_ms" to silence.toString()))
                    val reregistered = withContext(Dispatchers.Main) {
                        registerLocationUpdates(reportIfNoPermission = false)
                    }
                    if (reregistered) {
                        DeviceEventReporter.report(this@LocationTrackingService, "tracking_reregistered", motivo)
                    }
                }
            }
        }
    }

    private fun hasLocationPermission(): Boolean =
        checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun isGpsProviderEnabled(): Boolean =
        (getSystemService(LOCATION_SERVICE) as android.location.LocationManager)
            .isProviderEnabled(android.location.LocationManager.GPS_PROVIDER)

    private fun restoreIdentityFromPrefs() {
        val p = getSharedPreferences("config", MODE_PRIVATE)
        movil = p.getString("last_movil", "") ?: ""
        escenario = p.getString("last_escenario", "0") ?: "0"
        usuario = p.getString("last_usuario", "") ?: ""
        deviceId = p.getString("last_deviceId", "") ?: ""
    }

    private fun persistIdentityToPrefs() {
        getSharedPreferences("config", MODE_PRIVATE).edit()
            .putString("last_movil", movil).putString("last_escenario", escenario)
            .putString("last_usuario", usuario).putString("last_deviceId", deviceId)
            .apply()
    }

    // Android 15: el sistema puede dar timeout a FGS location de larga duración
    override fun onTimeout(startId: Int) {
        DeviceEventReporter.report(this, "heartbeat_no_gps", "FGS_TIMEOUT_A15")
        stopSelf()
    }

    override fun onDestroy() {
        isRunning = false
        locationCallback?.let { fusedClient.removeLocationUpdates(it) }
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
