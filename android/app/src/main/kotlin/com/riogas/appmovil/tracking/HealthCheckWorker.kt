package com.riogas.appmovil.tracking

import android.app.ForegroundServiceStartNotAllowedException
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import androidx.work.*
import com.riogas.appmovil.DeviceEventReporter
import com.riogas.appmovil.ServiceStatusFlags
import java.util.concurrent.TimeUnit

/**
 * Health-check periódico (B.4): NO es fuente de GPS, solo verifica que
 * LocationTrackingService siga vivo y, si murió (FGS matado por el SO),
 * intenta revivirlo cuando hay exención de batería o avisa al backend
 * para que el servidor pueda disparar B.3 (notificación push al usuario).
 */
class HealthCheckWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val ctx = applicationContext
        if (ServiceStatusFlags.isServiceDisabled(ctx)) return Result.success()
        // 🏪 Perfil comercio: aunque haya quedado programado de una sesión
        // anterior (se encola con KEEP y sobrevive reinicios), no revivir el FGS.
        if (ServiceStatusFlags.isRestrictedMode(ctx)) return Result.success()

        // permission_revoked check (B.2)
        if (ctx.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED) {
            DeviceEventReporter.reportAndWait(ctx, "permission_revoked", "HEALTH_CHECK")
            return Result.success()
        }

        if (LocationTrackingService.isRunning) return Result.success()

        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        val exempt = pm.isIgnoringBatteryOptimizations(ctx.packageName)
        return try {
            if (exempt) {
                val p = ctx.getSharedPreferences("config", Context.MODE_PRIVATE)
                LocationTrackingService.start(ctx,
                    p.getString("last_movil", "") ?: "", p.getString("last_escenario", "0") ?: "0",
                    p.getString("last_usuario", "") ?: "", p.getString("last_deviceId", "") ?: "")
                DeviceEventReporter.reportAndWait(ctx, "health_fgs_dead", "RESTARTED_BY_HEALTH_CHECK")
            } else {
                DeviceEventReporter.reportAndWait(ctx, "health_fgs_dead", "NO_BATTERY_EXEMPTION")
            }
            Result.success()
        } catch (e: Exception) {
            val motivo = if (Build.VERSION.SDK_INT >= 31 && e is ForegroundServiceStartNotAllowedException)
                "FGS_START_NOT_ALLOWED" else e.javaClass.simpleName
            // aviso HTTP simple, legal desde background → el server puede disparar B.3
            DeviceEventReporter.reportAndWait(ctx, "health_fgs_dead", motivo)
            Result.success()
        }
    }

    companion object {
        const val WORK_NAME = "tracking_health_check"
        fun schedule(context: Context) {
            val req = PeriodicWorkRequestBuilder<HealthCheckWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, req)
        }
        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }
}
