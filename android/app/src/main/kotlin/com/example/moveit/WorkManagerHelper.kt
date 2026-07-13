package com.example.moveit

import android.content.Context
import android.util.Log
import androidx.work.*
import java.util.concurrent.TimeUnit

/**
 * 🔧 WorkManagerHelper - Gestión de tareas periódicas con WorkManager
 * 
 * WorkManager es la solución recomendada por Google para tareas en background
 * que necesitan ejecutarse periódicamente, incluso después de reinicios del dispositivo.
 * 
 * Ventajas vs AlarmManager:
 * - ✅ Compatible con Android 12+ (sin restricciones de FGS)
 * - ✅ Auto-reinicio después de reboot
 * - ✅ Respeta Doze Mode y App Standby
 * - ✅ Reintentos automáticos en caso de fallo
 * - ✅ Persistencia garantizada
 */
object WorkManagerHelper {
    private const val TAG = "WorkManagerHelper"
    private const val WORK_NAME = "LocationPeriodicWork"
    
    /**
     * Programa el envío periódico de coordenadas usando WorkManager
     * 
     * @param context Contexto de la aplicación
     * @param intervalMinutes Intervalo en minutos (mínimo 15 según limitaciones de WorkManager)
     * @param movil ID del móvil
     * @param escenario ID del escenario
     * @param usuario ID del usuario
     * @param deviceId ID del dispositivo
     */
    fun schedulePeriodicLocationWork(
        context: Context,
        intervalMinutes: Int,
        movil: String,
        escenario: String,
        usuario: String,
        deviceId: String
    ) {
        Log.d(TAG, "📅 Programando Worker periódico cada $intervalMinutes minutos...")
        
        // Guardar parámetros en SharedPreferences para persistencia
        val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
        prefs.edit().apply {
            putString("last_movil", movil)
            putString("last_escenario", escenario)
            putString("last_usuario", usuario)
            putString("last_deviceId", deviceId)
            putFloat("last_interval", intervalMinutes.toFloat())
            putLong("last_schedule_time", System.currentTimeMillis())
        }.apply()
        Log.d(TAG, "💾 Parámetros guardados en SharedPreferences")
        
        // Crear datos de entrada para el Worker
        val inputData = Data.Builder()
            .putString(LocationWorker.KEY_MOVIL, movil)
            .putString(LocationWorker.KEY_ESCENARIO, escenario)
            .putString(LocationWorker.KEY_USUARIO, usuario)
            .putString(LocationWorker.KEY_DEVICE_ID, deviceId)
            .build()
        
        // WorkManager tiene restricción de mínimo 15 minutos para PeriodicWork
        // Si el intervalo es menor, usamos OneTimeWork con delay y re-schedule
        if (intervalMinutes < 15) {
            Log.w(TAG, "⚠️ Intervalo <15min no soportado por PeriodicWorkRequest")
            Log.w(TAG, "🔄 Usando estrategia de OneTimeWork con re-schedule automático")
            scheduleOneTimeWork(context, intervalMinutes, inputData)
        } else {
            schedulePeriodicWork(context, intervalMinutes, inputData)
        }
    }
    
    /**
     * Programa un PeriodicWorkRequest (para intervalos >= 15 minutos)
     */
    private fun schedulePeriodicWork(
        context: Context,
        intervalMinutes: Int,
        inputData: Data
    ) {
        val constraints = Constraints.Builder()
            .setRequiresBatteryNotLow(false) // ✅ Permitir con batería baja
            .setRequiresCharging(false)       // ✅ Permitir sin estar cargando
            .build()
        
        val periodicWorkRequest = PeriodicWorkRequestBuilder<LocationWorker>(
            intervalMinutes.toLong(), TimeUnit.MINUTES,
            5, TimeUnit.MINUTES // ✅ Flex interval de 5 minutos
        )
            .setInputData(inputData)
            .setConstraints(constraints)
            .addTag(WORK_NAME)
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                1, TimeUnit.MINUTES
            )
            .build()
        
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WORK_NAME,
            ExistingPeriodicWorkPolicy.CANCEL_AND_REENQUEUE, // ✅ Cancelar trabajo anterior
            periodicWorkRequest
        )
        
        Log.d(TAG, "✅ PeriodicWork programado: cada $intervalMinutes minutos")
    }
    
    /**
     * Programa un OneTimeWorkRequest con re-schedule (para intervalos < 15 minutos)
     * 
     * NOTA: Esta es una solución temporal. WorkManager está diseñado para intervalos >= 15min.
     * Para intervalos más cortos, AlarmManager + ForegroundService es más apropiado,
     * pero requiere que la app esté en foreground inicialmente.
     */
    private fun scheduleOneTimeWork(
        context: Context,
        intervalMinutes: Int,
        inputData: Data
    ) {
        val constraints = Constraints.Builder()
            .setRequiresBatteryNotLow(false)
            .setRequiresCharging(false)
            .build()
        
        val oneTimeWorkRequest = OneTimeWorkRequestBuilder<LocationWorker>()
            .setInputData(inputData)
            .setConstraints(constraints)
            .setInitialDelay(intervalMinutes.toLong(), TimeUnit.MINUTES)
            .addTag(WORK_NAME)
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                1, TimeUnit.MINUTES
            )
            .build()
        
        WorkManager.getInstance(context).enqueueUniqueWork(
            WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            oneTimeWorkRequest
        )
        
        Log.d(TAG, "✅ OneTimeWork programado: delay de $intervalMinutes minutos")
        Log.w(TAG, "⚠️ ADVERTENCIA: Para intervalos <15min, considera usar ForegroundService desde la app activa")
    }
    
    /**
     * Cancela el trabajo periódico programado
     */
    fun cancelPeriodicWork(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        Log.d(TAG, "🛑 Work cancelado")
        
        // Marcar como deshabilitado en SharedPreferences
        val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
        prefs.edit().putBoolean("service_disabled", true).apply()
    }
    
    /**
     * Verifica el estado del trabajo periódico
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
