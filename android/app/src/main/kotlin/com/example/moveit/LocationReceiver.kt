package com.example.moveit

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class LocationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // � FIX v14.7: Relajar validación - solo verificar deviceId (no sesión Firebase completa)
        // RAZÓN: Watchdog puede reiniciar servicio sin sesión Firebase completa, pero con deviceId válido
        val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
        val deviceId = prefs.getString("last_deviceId", "") ?: ""
        
        if (deviceId.isEmpty()) {
            Log.w("LocationReceiver", "🚫 [DEVICE_ID] DeviceId vacío, cancelando ejecución del servicio GPS")
            LocationLogger.logEvent(context, "ALARM_SKIP_NO_DEVICE_ID", mapOf(
                "reason" to "No deviceId available",
                "trigger_time" to System.currentTimeMillis().toString()
            ))
            
            // 🧹 LIMPIAR: Marcar servicio como deshabilitado y cancelar futuras alarmas
            prefs.edit().apply {
                putBoolean("service_disabled", true)
                putString("stop_reason", "No deviceId available")
                putLong("stop_timestamp", System.currentTimeMillis())
                putBoolean("auto_stopped", true)
            }.apply()
            
            // Cancelar AlarmManager para evitar futuros triggers sin deviceId
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            val cancelIntent = Intent(context, LocationReceiver::class.java)
            val pendingIntent = android.app.PendingIntent.getBroadcast(
                context, 1710, cancelIntent, android.app.PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
            Log.i("LocationReceiver", "✅ [DEVICE_ID] AlarmManager cancelado (no deviceId)")
            
            return
        }
        
        // ⚠️ ADVERTENCIA: Sesión Firebase puede estar inactiva, pero deviceId es suficiente
        if (!LocationHelper.isSessionActive(context)) {
            Log.w("LocationReceiver", "⚠️ [SESSION] Sesión Firebase inactiva pero deviceId presente ($deviceId) - CONTINUANDO")
        }
        
        // Verificar si el servicio está deshabilitado (reusar prefs ya declarado)
        val isDisabled = prefs.getBoolean("service_disabled", false)
        
        if (isDisabled) {
            val stopReason = prefs.getString("stop_reason", "Unknown reason")
            val stopTimestamp = prefs.getLong("stop_timestamp", 0)
            val wasAutoStopped = prefs.getBoolean("auto_stopped", false)
            
            Log.d("LocationReceiver", "🚫 Servicio deshabilitado: $stopReason, cancelando ejecución")
            Log.d("LocationReceiver", "⏰ Deshabilitado en: ${java.util.Date(stopTimestamp)}")
            Log.d("LocationReceiver", "🤖 Parada automática: $wasAutoStopped")
            
            LocationLogger.logEvent(context, "ALARM_SKIP_DISABLED", mapOf(
                "reason" to (stopReason ?: "Unknown"),
                "timestamp" to stopTimestamp.toString(),
                "auto_stopped" to wasAutoStopped.toString(),
                "trigger_time" to System.currentTimeMillis().toString()
            ))
            return
        }
        
        // Verificar si el servicio está pausado temporalmente
        val isPaused = prefs.getBoolean("service_paused", false)
        val resumeTime = prefs.getLong("resume_time", 0)
        val currentTime = System.currentTimeMillis()
        
        if (isPaused && currentTime < resumeTime) {
            val remainingMinutes = (resumeTime - currentTime) / (60 * 1000)
            Log.d("LocationReceiver", "⏸️ Servicio pausado, saltando ejecución. Reanudar en ${remainingMinutes}min")
            LocationLogger.logEvent(context, "ALARM_SKIP_PAUSED", mapOf(
                "remainingMinutes" to remainingMinutes.toString()
            ))
            return
        } else if (isPaused && currentTime >= resumeTime) {
            // La pausa ha expirado, remover flag y continuar
            prefs.edit().apply {
                putBoolean("service_paused", false)
                remove("resume_time")
                remove("pause_minutes")
            }.apply()
            Log.d("LocationReceiver", "▶️ Pausa expirada, reanudando servicio")
            LocationLogger.logEvent(context, "ALARM_PAUSE_EXPIRED", emptyMap())
        }
        
        Log.d("LocationReceiver", "⏰ AlarmManager disparado")
        
        // Inicializar logging si no está inicializado
        LocationLogger.initialize(context)

        val movil = intent.getStringExtra("movil") ?: ""
        val escenario = intent.getStringExtra("escenario") ?: ""
        val usuario = intent.getStringExtra("usuario") ?: ""
        val intentDeviceId = intent.getStringExtra("deviceId") ?: ""
        
        // 🛡️ VALIDACIÓN CRÍTICA: Verificar que movil NO esté vacío
        if (movil.isEmpty()) {
            Log.e("LocationReceiver", "❌ CRÍTICO: movil vacío en alarma! Intentando recuperar...")
            val savedMovil = prefs.getString("last_movil", "") ?: ""
            
            if (savedMovil.isEmpty()) {
                Log.e("LocationReceiver", "🚫 No se puede recuperar movil. CANCELANDO EJECUCIÓN.")
                LocationLogger.logEvent(context, "ALARM_CANCELLED_INVALID_PARAMS", mapOf(
                    "reason" to "movil vacío y no hay fallback en SharedPreferences"
                ))
                return
            } else {
                Log.w("LocationReceiver", "✅ Movil recuperado de SharedPreferences: $savedMovil")
                // Crear Intent con valores recuperados
                val recoveryIntent = Intent(context, LocationReceiver::class.java).apply {
                    putExtra("movil", savedMovil)
                    putExtra("escenario", prefs.getString("last_escenario", escenario) ?: escenario)
                    putExtra("usuario", prefs.getString("last_usuario", usuario) ?: usuario)
                    putExtra("deviceId", prefs.getString("last_deviceId", intentDeviceId) ?: intentDeviceId)
                    putExtra("interval", intent.getFloatExtra("interval", 0.5f)) // 🆕 Leer como Float para soportar 30 segundos (0.5 min)
                }
                
                LocationLogger.logEvent(context, "ALARM_PARAMS_RECOVERED", mapOf(
                    "movil" to savedMovil
                ))
                
                // Reinvocar con parámetros recuperados
                onReceive(context, recoveryIntent)
                return
            }
        }
        
        // Registrar que la alarma se disparó
        LocationLogger.logEvent(context, "ALARM_TRIGGERED", mapOf(
            "movil" to movil,
            "escenario" to escenario,
            "usuario" to usuario,
            "deviceId" to intentDeviceId
        ))

        val serviceIntent = Intent(context, ForegroundLocationService::class.java).apply {
            putExtra("movil", movil)
            putExtra("escenario", escenario)
            putExtra("usuario", usuario)
            putExtra("deviceId", intentDeviceId)
            putExtra("EXECUTE_GPS", true) // 🆕 Flag para indicar que SÍ debe ejecutar getCurrentLocation()
        }

        // 🆕 try-catch para capturar errores al iniciar servicio desde AlarmManager
        try {
            context.startForegroundService(serviceIntent)
            Log.d("LocationReceiver", "✅ Servicio GPS iniciado desde AlarmManager")
            
        } catch (e: SecurityException) {
            Log.e("LocationReceiver", "❌ SecurityException iniciando servicio desde AlarmManager", e)
            com.riogas.appmovil.CriticalLogger.logCritical(
                "LocationReceiver",
                "ERROR: Sin permisos para iniciar servicio GPS desde AlarmManager",
                e,
                mapOf(
                    "movil" to movil,
                    "android_version" to android.os.Build.VERSION.SDK_INT,
                    "context" to "AlarmManager_trigger"
                ),
                "SERVICE_START_FAILED"
            )
            return
            
        } catch (e: IllegalStateException) {
            Log.e("LocationReceiver", "❌ IllegalStateException iniciando servicio desde AlarmManager", e)
            com.riogas.appmovil.CriticalLogger.logCritical(
                "LocationReceiver",
                "ERROR: Servicio GPS bloqueado por background restrictions desde AlarmManager",
                e,
                mapOf(
                    "movil" to movil,
                    "android_version" to android.os.Build.VERSION.SDK_INT,
                    "context" to "AlarmManager_trigger"
                ),
                "SERVICE_START_FAILED"
            )
            return
            
        } catch (e: Exception) {
            Log.e("LocationReceiver", "❌ Error desconocido iniciando servicio desde AlarmManager", e)
            com.riogas.appmovil.CriticalLogger.logCritical(
                "LocationReceiver",
                "ERROR: Fallo desconocido iniciando servicio GPS desde AlarmManager",
                e,
                mapOf(
                    "movil" to movil,
                    "android_version" to android.os.Build.VERSION.SDK_INT,
                    "error_type" to e.javaClass.simpleName,
                    "context" to "AlarmManager_trigger"
                ),
                "SERVICE_START_FAILED"
            )
            return
        }
        
        // Reprogramar la siguiente alarma (necesario para setExactAndAllowWhileIdle)
        val intervalMinutes = intent.getFloatExtra("interval", 0.5f).toDouble() // 🆕 Leer como Float, default 30 segundos (0.5 min)
        val intervalDesc = if (intervalMinutes < 1.0) {
            "${(intervalMinutes * 60).toInt()} segundos"
        } else {
            "$intervalMinutes min"
        }
        Log.d("LocationReceiver", "🔄 Reprogramando siguiente alarma en $intervalDesc")
        LocationHelper.rescheduleNextAlarm(context, intervalMinutes, movil, escenario, usuario, deviceId)
    }

}
