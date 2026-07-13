package com.riogas.appmovil

import android.app.ActivityManager
import android.content.Context
import android.util.Log
import com.riogas.appmovil.tracking.LocationTrackingService

/**
 * Utilidad de solo-lectura para reporting del estado del tracking GPS.
 *
 * NOTA (Task 7 / B.1): se retiró todo el rol de "reiniciador" del watchdog
 * (restartGPSService, restartCriticalLogWorker, isAlarmScheduled,
 * isCriticalLogWorkerScheduled, getSystemHealth). El arranque del tracking es
 * responsabilidad única de LocationTrackingService. Este objeto ya NO reinicia
 * ningún servicio ni programa alarmas.
 */
object ServiceWatchdog {

    private const val TAG = "ServiceWatchdog"

    /**
     * Verifica si un servicio específico está corriendo (genérico).
     */
    fun isServiceRunning(context: Context, serviceClass: Class<*>): Boolean {
        return try {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            @Suppress("DEPRECATION")
            manager.getRunningServices(Integer.MAX_VALUE).any { serviceClass.name == it.service.className }
        } catch (e: Exception) {
            Log.e(TAG, "Error verificando si servicio ${serviceClass.simpleName} está corriendo", e)
            false
        }
    }

    /**
     * Estado del tracking GPS (solo lectura, para reporting).
     */
    fun isGPSServiceRunning(context: Context): Boolean = LocationTrackingService.isRunning
}
