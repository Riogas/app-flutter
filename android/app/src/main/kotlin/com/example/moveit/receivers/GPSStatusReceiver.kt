package com.example.moveit.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.util.Log
import com.riogas.appmovil.DebugLogger

/**
 * 🛰️ BroadcastReceiver para detectar cambios en el estado del GPS
 * 
 * Escucha el action: LocationManager.PROVIDERS_CHANGED_ACTION
 * Se dispara cuando el usuario enciende/apaga el GPS desde Settings
 */
class GPSStatusReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "GPSStatusReceiver"
        
        /**
         * Verifica el estado actual del GPS
         */
        fun isGPSEnabled(context: Context): Boolean {
            val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            return locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
        }
        
        /**
         * Verifica y registra el estado del GPS con más detalle
         */
        fun checkAndLogGPSStatus(context: Context) {
            val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val gpsEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
            val networkEnabled = locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            val passiveEnabled = locationManager.isProviderEnabled(LocationManager.PASSIVE_PROVIDER)
            
            val allProviders = locationManager.allProviders
            val enabledProviders = locationManager.getProviders(true)
            
            Log.i(TAG, "📡 Estado GPS: GPS=${if (gpsEnabled) "ON" else "OFF"}, Network=${if (networkEnabled) "ON" else "OFF"}, Passive=${if (passiveEnabled) "ON" else "OFF"}")
            Log.d(TAG, "📡 Providers disponibles: $allProviders")
            Log.d(TAG, "📡 Providers habilitados: $enabledProviders")
            
            DebugLogger.i(TAG, "Estado de proveedores de ubicación", mapOf(
                "gps" to if (gpsEnabled) "enabled" else "disabled",
                "network" to if (networkEnabled) "enabled" else "disabled",
                "passive" to if (passiveEnabled) "enabled" else "disabled",
                "allProviders" to allProviders.joinToString(","),
                "enabledProviders" to enabledProviders.joinToString(",")
            ))
            
            // 🚨 Alerta si GPS está apagado
            if (!gpsEnabled && !networkEnabled) {
                Log.e(TAG, "⚠️ CRÍTICO: GPS y Network deshabilitados - NO se puede obtener ubicación")
                DebugLogger.e(TAG, "Ubicación bloqueada - Sin proveedores", null, mapOf(
                    "reason" to "GPS and Network providers are disabled",
                    "availableProviders" to allProviders.joinToString(",")
                ))
            }
        }
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        
        if (intent.action == LocationManager.PROVIDERS_CHANGED_ACTION) {
            Log.i(TAG, "🛰️ Cambio en proveedores de ubicación detectado")
            
            val prefs = context.getSharedPreferences("gps_state", Context.MODE_PRIVATE)
            val wasGPSEnabled = prefs.getBoolean("gps_enabled", false)
            val isGPSEnabled = isGPSEnabled(context)
            
            // Detectar cambio específico en GPS
            if (wasGPSEnabled != isGPSEnabled) {
                val action = if (isGPSEnabled) "ENCENDIDO" else "APAGADO"
                Log.w(TAG, "🛰️ GPS $action por el usuario")
                
                DebugLogger.w(TAG, "Cambio en estado del GPS", mapOf(
                    "previousState" to if (wasGPSEnabled) "enabled" else "disabled",
                    "currentState" to if (isGPSEnabled) "enabled" else "disabled",
                    "action" to action
                ))
                
                // Guardar nuevo estado
                prefs.edit().putBoolean("gps_enabled", isGPSEnabled).apply()
                
                // 🚨 Si GPS se apagó, loguear alerta
                if (!isGPSEnabled) {
                    Log.e(TAG, "⚠️ CRÍTICO: GPS apagado - Precisión de ubicación reducida")
                    DebugLogger.e(TAG, "GPS deshabilitado por usuario", null, mapOf(
                        "impact" to "Location accuracy will be reduced - using NETWORK provider",
                        "timestamp" to System.currentTimeMillis()
                    ))
                } else {
                    Log.i(TAG, "✅ GPS encendido - Precisión de ubicación mejorada")
                    DebugLogger.i(TAG, "GPS habilitado por usuario", mapOf(
                        "impact" to "Location accuracy improved - using GPS provider",
                        "timestamp" to System.currentTimeMillis()
                    ))
                }
            }
            
            // Loguear estado completo de todos los proveedores
            checkAndLogGPSStatus(context)
        }
    }
}
