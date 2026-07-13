package com.riogas.appmovil.tracking

import android.content.Context
import androidx.work.*
import com.riogas.appmovil.DeviceEventReporter

/**
 * Boot ping (B.5): tras reboot (o update de la app) con sesión activa,
 * avisa al backend en segundo plano (WorkManager, no FGS) que el
 * dispositivo volvió a estar disponible. El backend decide si corresponde
 * mandar restart_tracking por FCM. NUNCA arranca el FGS de ubicación
 * directamente desde el broadcast de boot.
 */
class BootPingWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val motivo = inputData.getString(KEY_BOOT_REASON) ?: "BOOT_COMPLETED"
        DeviceEventReporter.reportAndWait(applicationContext, "booted", motivo)
        HealthCheckWorker.schedule(applicationContext) // re-asegurar el health-check tras reboot
        return Result.success()
    }

    companion object {
        private const val KEY_BOOT_REASON = "boot_reason"

        fun enqueue(context: Context, bootReason: String = "BOOT_COMPLETED") {
            val req = OneTimeWorkRequestBuilder<BootPingWorker>()
                .setInputData(workDataOf(KEY_BOOT_REASON to bootReason))
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork("boot_ping", ExistingWorkPolicy.REPLACE, req)
        }
    }
}
