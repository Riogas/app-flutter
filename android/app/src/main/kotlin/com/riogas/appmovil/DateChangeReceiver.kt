package com.riogas.appmovil

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.example.moveit.ForegroundLocationService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * 🌅 BroadcastReceiver para detectar cambio de día (00:00)
 * 
 * PROPÓSITO:
 * - Recibe ACTION_DATE_CHANGED cuando Android detecta cambio de fecha a las 00:00
 * - Verifica si hay sesión activa del día anterior
 * - Fuerza auto-logout si detecta sesión de día anterior
 * - NO consume batería durante el día (solo se activa a las 00:00)
 * 
 * VENTAJAS vs Timer periódico:
 * - 1 ejecución por día vs 288 ejecuciones (cada 5 min)
 * - 0 consumo de batería durante el día
 * - Más confiable (Android garantiza el disparo)
 * - No despierta el CPU innecesariamente
 */
class DateChangeReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "DateChangeReceiver"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_DATE_CHANGED) {
            return
        }
        
        Log.i(TAG, "🌅 ACTION_DATE_CHANGED recibido - Verificando sesión activa...")
        
        // Usar coroutine para operaciones async
        CoroutineScope(Dispatchers.Default).launch {
            try {
                val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
                val flutterPrefs = context.getSharedPreferences(
                    "FlutterSharedPreferences",
                    Context.MODE_PRIVATE
                )
                
                // Obtener loginDate desde FlutterSharedPreferences (donde Hive guarda datos)
                val loginDate = flutterPrefs.getString("flutter.loginDate", null)
                val currentDate = getCurrentDateString()
                
                Log.d(TAG, "   loginDate: $loginDate")
                Log.d(TAG, "   currentDate: $currentDate")
                
                // Si hay sesión activa del día anterior, forzar logout
                if (loginDate != null && loginDate != currentDate) {
                    Log.w(TAG, "🚨 SESIÓN DEL DÍA ANTERIOR DETECTADA!")
                    Log.w(TAG, "   Login: $loginDate → Hoy: $currentDate")
                    Log.w(TAG, "🛑 Forzando auto-logout...")
                    
                    performAutoLogout(context, prefs, flutterPrefs, loginDate, currentDate)
                } else if (loginDate == null) {
                    Log.d(TAG, "✅ No hay sesión activa (loginDate es null)")
                } else {
                    Log.d(TAG, "✅ Sesión activa del mismo día ($loginDate)")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error en DateChangeReceiver: ${e.message}", e)
                CriticalLogger.logCritical(
                    TAG,
                    "ERROR: Excepción en DateChangeReceiver",
                    e,
                    mapOf(
                        "error_type" to e.javaClass.simpleName,
                        "error_message" to (e.message ?: "Sin mensaje")
                    ),
                    "DATE_CHANGE_ERROR"
                )
            }
        }
    }
    
    private suspend fun performAutoLogout(
        context: Context,
        prefs: android.content.SharedPreferences,
        flutterPrefs: android.content.SharedPreferences,
        loginDate: String,
        currentDate: String
    ) {
        val movil = prefs.getString("last_movil", "") ?: ""
        val escenario = prefs.getString("last_escenario", "") ?: ""
        val usuario = prefs.getString("last_usuario", "") ?: ""
        val deviceId = prefs.getString("last_deviceId", "") ?: ""
        
        Log.i(TAG, "🛑 AUTO-LOGOUT por cambio de día")
        Log.i(TAG, "   Movil: $movil, Usuario: $usuario")
        Log.i(TAG, "   Login: $loginDate → Hoy: $currentDate")
        
        // 1️⃣ Detener GPS service
        try {
            if (ServiceWatchdog.isGPSServiceRunning(context)) {
                val stopIntent = Intent(context, ForegroundLocationService::class.java)
                context.stopService(stopIntent)
                Log.i(TAG, "✅ GPS service detenido")
                
                CriticalLogger.logCritical(
                    TAG,
                    "AUTO_LOGOUT: GPS service detenido por cambio de día",
                    mapOf(
                        "movil" to movil,
                        "usuario" to usuario,
                        "login_date" to loginDate,
                        "current_date" to currentDate
                    ),
                    "DATE_CHANGE_GPS_STOPPED"
                )
            } else {
                Log.d(TAG, "   GPS service ya estaba detenido")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error deteniendo GPS service: ${e.message}", e)
        }
        
        // 2️⃣ Limpiar SharedPreferences
        try {
            // Limpiar FlutterSharedPreferences (Hive data)
            flutterPrefs.edit().apply {
                remove("flutter.loginDate")
                remove("flutter.username")
                remove("flutter.password")
                remove("flutter.escenario")
                remove("flutter.movil")
                remove("flutter.deviceId")
                remove("flutter.NombreUsuario")
                apply()
            }
            
            // Limpiar config nativo
            ServiceStatusFlags.setServiceDisabled(context, true, "AutoLogoutCambioDia")
            ServiceStatusFlags.setWatchdogDisabled(context, true, "AutoLogoutCambioDia") // 🔥 CRÍTICO: Detener watchdog también
            prefs.edit().apply {
                putString("stop_reason", "AutoLogoutCambioDia")
                putLong("stop_timestamp", System.currentTimeMillis())
                apply()
            }
            
            Log.i(TAG, "✅ SharedPreferences limpiado (service + watchdog disabled)")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error limpiando SharedPreferences: ${e.message}", e)
        }
        
        // 3️⃣ Log crítico del auto-logout
        CriticalLogger.logCritical(
            TAG,
            "AUTO_LOGOUT EXITOSO: Sesión cerrada automáticamente por cambio de día",
            mapOf(
                "movil" to movil,
                "escenario" to escenario,
                "usuario" to usuario,
                "deviceId" to deviceId,
                "login_date" to loginDate,
                "current_date" to currentDate,
                "trigger" to "ACTION_DATE_CHANGED",
                "time" to System.currentTimeMillis().toString()
            ),
            "AUTO_LOGOUT_DATE_CHANGE"
        )
        
        Log.i(TAG, "✅ AUTO-LOGOUT COMPLETADO")
    }
    
    /**
     * Obtiene la fecha actual en formato YYYY-MM-DD
     */
    private fun getCurrentDateString(): String {
        val calendar = java.util.Calendar.getInstance()
        val year = calendar.get(java.util.Calendar.YEAR)
        val month = calendar.get(java.util.Calendar.MONTH) + 1 // Enero es 0
        val day = calendar.get(java.util.Calendar.DAY_OF_MONTH)
        
        return String.format("%04d-%02d-%02d", year, month, day)
    }
}
