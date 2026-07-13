package com.example.moveit

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import androidx.work.ForegroundInfo
import android.app.NotificationChannel
import android.app.NotificationManager
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 🔄 LocationWorker - Worker para envío periódico de coordenadas
 * 
 * Este Worker es compatible con Android 12+ y ejecuta en background sin violar
 * las restricciones de "Foreground Service Location Access".
 * 
 * WorkManager maneja automáticamente:
 * - Reinicio después de reboot
 * - Persistencia de tareas
 * - Restricciones de batería (Doze Mode)
 * - Reintentos en caso de fallo
 */
class LocationWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "LocationWorker"
        const val CHANNEL_ID = "location_worker_channel"
        const val NOTIFICATION_ID = 2001 // Diferente del ForegroundLocationService
        
        // Keys para los parámetros del Worker
        const val KEY_MOVIL = "movil"
        const val KEY_ESCENARIO = "escenario"
        const val KEY_USUARIO = "usuario"
        const val KEY_DEVICE_ID = "deviceId"
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "🔄 LocationWorker iniciado...")
            
            // Obtener parámetros
            val movil = inputData.getString(KEY_MOVIL) ?: ""
            val escenario = inputData.getString(KEY_ESCENARIO) ?: ""
            val usuario = inputData.getString(KEY_USUARIO) ?: ""
            val deviceId = inputData.getString(KEY_DEVICE_ID) ?: ""
            
            Log.d(TAG, "📋 Parámetros: movil=$movil, escenario=$escenario, usuario=$usuario, deviceId=$deviceId")
            
            if (movil.isEmpty()) {
                Log.e(TAG, "❌ Parámetros vacíos, abortando Worker")
                return@withContext Result.failure()
            }
            
            // Ejecutar obtención de coordenadas (método estático de LocationHelper)
            val result = LocationHelper.getCurrentLocation(
                applicationContext,
                movil,
                escenario,
                usuario,
                deviceId
            )
            
            if (result.containsKey("error")) {
                Log.w(TAG, "⚠️ Error al obtener coordenadas: ${result["error"]}")
                // Retry: WorkManager reintentará automáticamente
                return@withContext Result.retry()
            }
            
            Log.d(TAG, "✅ Coordenadas enviadas exitosamente desde Worker")
            return@withContext Result.success()
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error en LocationWorker: ${e.message}", e)
            LocationLogger.logError(
                applicationContext, 
                "LocationWorker exception", 
                e.message ?: "Unknown error",
                e.stackTraceToString()
            )
            return@withContext Result.retry()
        }
    }
    
    /**
     * 🔔 Define el ForegroundInfo para Android 12+
     * 
     * WorkManager requiere esto cuando se usa setExpedited() en Android 12+
     * para mostrar una notificación temporal mientras ejecuta.
     */
    override suspend fun getForegroundInfo(): ForegroundInfo {
        createNotificationChannel()
        
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setContentTitle("Actualizando ubicación")
            .setContentText("Enviando coordenadas al servidor...")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(false)
            .build()
        
        return ForegroundInfo(NOTIFICATION_ID, notification)
    }
    
    private fun createNotificationChannel() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Actualización de Ubicación",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Canal para actualizaciones periódicas de ubicación"
                setShowBadge(false)
            }
            
            val notificationManager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
}
