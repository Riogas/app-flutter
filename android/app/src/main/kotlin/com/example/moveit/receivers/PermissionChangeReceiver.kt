package com.example.moveit.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import com.riogas.appmovil.DebugLogger

/**
 * 🔔 BroadcastReceiver para detectar cambios en permisos de ubicación
 * 
 * IMPORTANTE: Android NO envía broadcasts automáticos cuando cambian permisos.
 * Este receiver debe ser invocado manualmente desde la Activity cuando el usuario
 * regresa desde Settings o cuando se otorgan/revocan permisos.
 * 
 * Para detectar cambios automáticamente, se debe:
 * 1. Usar onResume() en MainActivity para verificar permisos
 * 2. Comparar con estado anterior guardado en SharedPreferences
 * 3. Si cambió, llamar a este receiver manualmente
 */
class PermissionChangeReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "PermissionChange"
        const val ACTION_PERMISSION_CHANGED = "com.example.moveit.PERMISSION_CHANGED"
        const val EXTRA_PERMISSION_NAME = "permission_name"
        const val EXTRA_WAS_GRANTED = "was_granted"
        const val EXTRA_IS_GRANTED = "is_granted"
        
        /**
         * Verifica permisos y detecta cambios comparando con estado previo
         */
        fun checkAndLogPermissionChanges(context: Context) {
            val prefs = context.getSharedPreferences("permission_state", Context.MODE_PRIVATE)
            val permissions = listOf(
                android.Manifest.permission.ACCESS_FINE_LOCATION,
                android.Manifest.permission.ACCESS_COARSE_LOCATION,
                android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
            )
            
            for (permission in permissions) {
                val currentlyGranted = ContextCompat.checkSelfPermission(
                    context, 
                    permission
                ) == PackageManager.PERMISSION_GRANTED
                
                val previouslyGranted = prefs.getBoolean(permission, false)
                
                if (currentlyGranted != previouslyGranted) {
                    // 🔔 Cambio detectado
                    val action = if (currentlyGranted) "OTORGADO" else "REVOCADO"
                    Log.w(TAG, "🔔 Permiso $action: ${getPermissionName(permission)}")
                    
                    DebugLogger.w(TAG, "Cambio de permiso detectado", mapOf(
                        "permission" to getPermissionName(permission),
                        "previousState" to if (previouslyGranted) "granted" else "denied",
                        "currentState" to if (currentlyGranted) "granted" else "denied",
                        "action" to action
                    ))
                    
                    // Guardar nuevo estado
                    prefs.edit().putBoolean(permission, currentlyGranted).apply()
                    
                    // 🚨 Si se revocó permiso de ubicación, loguear alerta
                    if (!currentlyGranted && (permission == android.Manifest.permission.ACCESS_FINE_LOCATION || 
                        permission == android.Manifest.permission.ACCESS_COARSE_LOCATION)) {
                        Log.e(TAG, "⚠️ CRÍTICO: Permiso de ubicación revocado - Servicio GPS NO funcionará")
                        DebugLogger.e(TAG, "Servicio GPS bloqueado por permisos", null, mapOf(
                            "reason" to "User revoked location permission",
                            "permission" to permission
                        ))
                    }
                }
            }
        }
        
        private fun getPermissionName(permission: String): String {
            return when (permission) {
                android.Manifest.permission.ACCESS_FINE_LOCATION -> "ACCESS_FINE_LOCATION"
                android.Manifest.permission.ACCESS_COARSE_LOCATION -> "ACCESS_COARSE_LOCATION"
                android.Manifest.permission.ACCESS_BACKGROUND_LOCATION -> "ACCESS_BACKGROUND_LOCATION"
                else -> permission
            }
        }
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        
        when (intent.action) {
            ACTION_PERMISSION_CHANGED -> {
                val permissionName = intent.getStringExtra(EXTRA_PERMISSION_NAME) ?: "unknown"
                val wasGranted = intent.getBooleanExtra(EXTRA_WAS_GRANTED, false)
                val isGranted = intent.getBooleanExtra(EXTRA_IS_GRANTED, false)
                
                val action = if (isGranted) "OTORGADO" else "REVOCADO"
                Log.i(TAG, "🔔 Permiso $action: $permissionName (antes: $wasGranted, ahora: $isGranted)")
                
                DebugLogger.i(TAG, "Cambio de permiso", mapOf(
                    "permission" to permissionName,
                    "wasGranted" to wasGranted,
                    "isGranted" to isGranted,
                    "action" to action
                ))
            }
        }
    }
}
