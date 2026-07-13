package com.example.moveit

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.riogas.appmovil.ServiceStatusFlags

/**
 * BootReceiver - Se activa cuando el dispositivo reinicia
 * 
 * Propósito: Reiniciar automáticamente el servicio de ubicación
 * después de un reinicio del dispositivo, para garantizar que el
 * envío de coordenadas continúe sin intervención del usuario.
 * 
 * Eventos que escucha:
 * - BOOT_COMPLETED: Dispositivo completó el reinicio
 * - QUICKBOOT_POWERON: Reinicio rápido (algunos fabricantes)
 * - MY_PACKAGE_REPLACED: App fue actualizada
 * - MY_PACKAGE_RESTARTED: App fue forzada a reiniciar
 */
class BootReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "BootReceiver"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.i(TAG, "🔔 Evento recibido: $action")
        
        // Inicializar logging
        LocationLogger.initialize(context)
        
        // 🔐 VALIDACIÓN #1: Verificar si hay sesión activa
        if (!LocationHelper.isSessionActive(context)) {
            Log.w(TAG, "🚫 [SESSION] No hay sesión activa, no se reprogramará servicio GPS")
            LocationLogger.logEvent(context, "BOOT_SKIP_NO_SESSION", mapOf(
                "action" to (action ?: "unknown"),
                "reason" to "No active Firebase session"
            ))
            return
        }
        
        // Verificar si el servicio está deshabilitado
        val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
        val isDisabled = ServiceStatusFlags.isServiceDisabled(context)
        
        if (isDisabled) {
            val stopReason = prefs.getString("stop_reason", "Unknown")
            Log.w(TAG, "🚫 Servicio deshabilitado ($stopReason), no se reiniciará")
            LocationLogger.logEvent(context, "BOOT_SKIP_DISABLED", mapOf(
                "action" to (action ?: "unknown"),
                "reason" to (stopReason ?: "Unknown")
            ))
            return
        }
        
        // Recuperar parámetros guardados de la última configuración
        val movil = prefs.getString("last_movil", "") ?: ""
        val escenario = prefs.getString("last_escenario", "") ?: ""
        val usuario = prefs.getString("last_usuario", "") ?: ""
        val deviceId = prefs.getString("last_deviceId", "") ?: ""
        val intervalMinutes = prefs.getFloat("last_interval", 0.5f).toDouble() // Default 30 seg
        
        // Verificar que tengamos datos para reiniciar
        if (movil.isEmpty()) {
            Log.w(TAG, "⚠️ No hay datos guardados (movil vacío), no se puede reiniciar servicio")
            LocationLogger.logEvent(context, "BOOT_SKIP_NO_DATA", mapOf(
                "action" to (action ?: "unknown")
            ))
            return
        }
        
        Log.i(TAG, "✅ Reiniciando servicio con:")
        Log.i(TAG, "   movil=$movil")
        Log.i(TAG, "   escenario=$escenario")
        Log.i(TAG, "   usuario=$usuario")
        Log.i(TAG, "   deviceId=$deviceId")
        Log.i(TAG, "   interval=${intervalMinutes}min")
        
        // Registrar evento de reinicio
        LocationLogger.logEvent(context, "SERVICE_AUTO_RESTART", mapOf(
            "action" to (action ?: "unknown"),
            "movil" to movil,
            "escenario" to escenario,
            "usuario" to usuario,
            "deviceId" to deviceId,
            "interval" to intervalMinutes.toString()
        ))
        
        try {
            // Reprogramar el AlarmManager
            LocationHelper.scheduleLocationAlarm(
                context = context,
                intervalMinutes = intervalMinutes,
                movil = movil,
                escenario = escenario,
                usuario = usuario,
                deviceId = deviceId
            )
            
            Log.i(TAG, "✅ Servicio reprogramado exitosamente después de $action")
            
            LocationLogger.logEvent(context, "SERVICE_RESTART_SUCCESS", mapOf(
                "action" to (action ?: "unknown"),
                "interval" to intervalMinutes.toString()
            ))
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error reiniciando servicio: ${e.message}", e)
            LocationLogger.logEvent(context, "SERVICE_RESTART_ERROR", mapOf(
                "action" to (action ?: "unknown"),
                "error" to (e.message ?: "Unknown error")
            ))
        }
    }
}
