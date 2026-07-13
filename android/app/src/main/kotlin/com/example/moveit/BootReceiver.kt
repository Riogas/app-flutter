package com.example.moveit

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.riogas.appmovil.ServiceStatusFlags
import com.riogas.appmovil.tracking.BootPingWorker

/**
 * BootReceiver - Se activa cuando el dispositivo reinicia o la app se actualiza
 *
 * Propósito: Encolar un boot ping (B.5) al backend para que decida si
 * corresponde reenviar restart_tracking por FCM. NO arranca el FGS de
 * ubicación directamente desde este broadcast: el tracking se retoma vía
 * el canal FCM (restart_tracking) o cuando el usuario abre la app.
 *
 * Eventos que escucha:
 * - BOOT_COMPLETED: Dispositivo completó el reinicio
 * - QUICKBOOT_POWERON: Reinicio rápido (algunos fabricantes)
 * - MY_PACKAGE_REPLACED: App fue actualizada
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
            Log.w(TAG, "🚫 [SESSION] No hay sesión activa, no se encolará boot ping")
            LocationLogger.logEvent(context, "BOOT_SKIP_NO_SESSION", mapOf(
                "action" to (action ?: "unknown"),
                "reason" to "No active Firebase session"
            ))
            return
        }

        // 🔐 VALIDACIÓN #2: Verificar si el servicio está deshabilitado
        val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
        val isDisabled = ServiceStatusFlags.isServiceDisabled(context)

        if (isDisabled) {
            val stopReason = prefs.getString("stop_reason", "Unknown")
            Log.w(TAG, "🚫 Servicio deshabilitado ($stopReason), no se encolará boot ping")
            LocationLogger.logEvent(context, "BOOT_SKIP_DISABLED", mapOf(
                "action" to (action ?: "unknown"),
                "reason" to (stopReason ?: "Unknown")
            ))
            return
        }

        Log.i(TAG, "✅ Encolando boot ping tras $action")
        LocationLogger.logEvent(context, "BOOT_PING_ENQUEUED", mapOf(
            "action" to (action ?: "unknown")
        ))

        BootPingWorker.enqueue(context, action ?: "BOOT_COMPLETED")
    }
}
