package com.example.moveit

import android.content.Context
import android.util.Log
import androidx.work.WorkManager

/**
 * WorkManagerHelper - Gestión de tareas periódicas con WorkManager.
 *
 * NOTA (Task 7 / B.1): se retiró `schedulePeriodicLocationWork` y el fallback
 * `OneTimeWork` (dependían de LocationWorker, ya eliminado). El tracking continuo
 * lo maneja LocationTrackingService; Task 10 reemplaza el work periódico por un
 * health-check. `cancelPeriodicWork` ya NO deshabilita el servicio como efecto
 * colateral (quien detiene el servicio debe marcar el flag vía ServiceStatusFlags).
 */
object WorkManagerHelper {
    private const val TAG = "WorkManagerHelper"
    private const val WORK_NAME = "LocationPeriodicWork"

    /**
     * Cancela el trabajo periódico programado.
     */
    fun cancelPeriodicWork(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        Log.d(TAG, "🛑 Work cancelado")
    }

    /**
     * Verifica el estado del trabajo periódico.
     */
    fun getWorkStatus(context: Context): String {
        val workInfoList = WorkManager.getInstance(context)
            .getWorkInfosForUniqueWork(WORK_NAME)
            .get()

        return if (workInfoList.isEmpty()) {
            "No hay trabajo programado"
        } else {
            val workInfo = workInfoList[0]
            "Estado: ${workInfo.state}, Tags: ${workInfo.tags}, NextSchedule: ${workInfo.nextScheduleTimeMillis}"
        }
    }
}
