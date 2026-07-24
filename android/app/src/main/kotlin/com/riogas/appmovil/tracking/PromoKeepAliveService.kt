package com.riogas.appmovil.tracking

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.riogas.appmovil.DeviceEventReporter
import com.riogas.appmovil.ServiceStatusFlags

/**
 * 🏪 Keep-alive del perfil comercio (escenario 9998).
 *
 * NO hace absolutamente nada: no lee ubicación, no consulta la red, no
 * programa loops. Existe solo para que el proceso no quede como "cached
 * process" y el low-memory killer no lo mate mientras el comercio tiene la
 * app abierta.
 *
 * Es un FGS de tipo `dataSync` a propósito, NO `location`: no pide ni usa
 * permisos de ubicación, y su notificación no menciona rastreo.
 *
 * Android 15 limita los FGS `dataSync` a ~6 h por día. Al llegar al tope
 * llega onTimeout() y hay que detenerse limpiamente o el sistema mata la app
 * con ForegroundServiceDidNotStopInTimeException. A partir de ahí el proceso
 * vuelve a ser matable: la sesión sigue viva en Hive y el usuario reabre.
 */
class PromoKeepAliveService : Service() {

    companion object {
        private const val TAG = "PromoKeepAlive"
        private const val NOTIF_ID = 1720
        private const val CHANNEL_ID = "promo_keepalive_channel"

        @Volatile
        var isRunning = false
            private set

        /** Idempotente: si ya corre, Android reutiliza la instancia. */
        fun start(context: Context) {
            context.startForegroundService(
                Intent(context, PromoKeepAliveService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, PromoKeepAliveService::class.java))
        }
    }

    override fun onCreate() {
        super.onCreate()
        try {
            startInForeground()
            isRunning = true
            Log.i(TAG, "✅ Keep-alive del comercio en foreground")
        } catch (e: Exception) {
            // Mismo criterio que LocationTrackingService: no propagar, mata el proceso.
            Log.e(TAG, "❌ No se pudo pasar a foreground", e)
            DeviceEventReporter.report(this, "health_fgs_dead", "KEEPALIVE_START_DENIED",
                mapOf("error" to e.javaClass.simpleName))
            isRunning = false
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!isRunning) return START_NOT_STICKY

        // Si el perfil dejó de ser restringido (p.ej. se logueó un chofer),
        // este servicio no tiene razón de existir.
        if (!ServiceStatusFlags.isRestrictedMode(this)) {
            Log.w(TAG, "restricted_mode=false → keep-alive se detiene")
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    private fun startInForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Promociones", NotificationManager.IMPORTANCE_LOW)
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MoveIT")
            .setContentText("Promociones activas")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    /** Android 15+: tope diario de dataSync alcanzado. Detenerse limpio. */
    override fun onTimeout(startId: Int) {
        Log.w(TAG, "⏱️ Tope de dataSync alcanzado → keep-alive se detiene")
        DeviceEventReporter.report(this, "health_fgs_dead", "KEEPALIVE_TIMEOUT")
        isRunning = false
        stopSelf()
    }

    override fun onDestroy() {
        isRunning = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
