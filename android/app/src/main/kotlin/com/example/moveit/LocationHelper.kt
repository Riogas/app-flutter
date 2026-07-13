package com.example.moveit

import android.Manifest
import android.annotation.SuppressLint
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Criteria
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import okhttp3.*
import org.locationtech.proj4j.CRSFactory
import org.locationtech.proj4j.CoordinateTransformFactory
import org.locationtech.proj4j.ProjCoordinate
import java.io.IOException
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

// 🆕 GOOGLE PLAY SERVICES LOCATION API (lo que usa Flutter internamente)
import com.google.android.gms.location.*
import com.google.android.gms.tasks.CancellationTokenSource
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks

// 🆕 Sistema de logging condicional para diagnóstico
import com.riogas.appmovil.DebugLogger
import com.riogas.appmovil.ServiceStatusFlags

// 🆕 FirebaseAuth y Firestore para validación de sesión robusta
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit


object LocationHelper {
    private const val TAG = "LocationHelper"
    private var totalDistance: Float = 0.0f
    private var lastLocation: Location? = null
    private var lastResetReason: String = "No"
    private var isFirstExecution: Boolean = true
    
    // 🆕 THREAD POOL para limitar threads concurrentes
    private val apiExecutor = java.util.concurrent.Executors.newFixedThreadPool(2) // Máximo 2 threads simultáneos
    private val pendingRequests = java.util.concurrent.atomic.AtomicInteger(0)
    
    // 🆕 FASE 2: Info de satélites GNSS
    private var lastSatelliteCount = 0
    private var lastUsedSatellites = 0
    private var lastAvgSnr = 0f
    private var lastGnssLogTime = 0L // 🔧 Throttling: última vez que se logueó GNSS

    /**
     * 🍪 Obtiene o crea un GX_CLIENT_ID persistente para GeneXus
     * 
     * GeneXus requiere este header Cookie para identificar sesiones HTTP.
     * Se genera una vez y se reutiliza en todas las llamadas.
     * 
     * @param context Contexto de la aplicación
     * @return UUID en formato string (ej: "55b2105f-de6a-4981-8f66-42db0cbe532a")
     */
    private fun getOrCreateGxClientId(context: Context): String {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val key = "flutter.gxClientId"
        
        // Intentar obtener el ID existente
        var gxClientId = prefs.getString(key, null)
        
        if (gxClientId == null) {
            // Generar nuevo UUID
            gxClientId = java.util.UUID.randomUUID().toString()
            prefs.edit().putString(key, gxClientId).apply()
            Log.d(TAG, "🍪 [GX_CLIENT_ID] Generado nuevo: $gxClientId")
        } else {
            Log.d(TAG, "🍪 [GX_CLIENT_ID] Reutilizando existente: $gxClientId")
        }
        
        return gxClientId
    }

    /**
     * 🔐 Verifica si hay una sesión activa ROBUSTA
     * 
     * Validaciones en orden:
     * 1️⃣ Verificar SharedPreferences de Flutter (datos de sesión guardados)
     * 2️⃣ Verificar FirebaseAuth (usuario autenticado)
     * 3️⃣ Verificar Firestore sessions-$escenario (sesión activa HOY)
     * 
     * Propósito: Evitar que el servicio GPS se ejecute cuando NO hay sesión activa
     * 
     * Casos de uso:
     * - Cierre de sesión controlado desde Settings
     * - Cierre de sesión forzado (otro usuario se conecta en sessions-$escenario)
     * - Cambio de día (RegistrarCierre exitoso, sesión cerrada)
     * - Reinicios del dispositivo sin sesión activa
     * 
     * @return true si hay sesión activa válida, false caso contrario
     */
    fun isSessionActive(context: Context): Boolean {
        return try {
            val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            
            // 1️⃣ VALIDACIÓN: Verificar datos en SharedPreferences
            val savedMovil = prefs.getString("last_movil", "") ?: ""
            val savedEscenario = prefs.getString("last_escenario", "") ?: ""
            val savedUsuario = prefs.getString("last_usuario", "") ?: ""
            val savedLoginDate = flutterPrefs.getString("flutter.loginDate", "") ?: ""
            val sessionActive = flutterPrefs.getBoolean("flutter.sessionActive", false)
            
            if (savedMovil.isEmpty() || savedMovil == "0" || savedMovil == "unknown") {
                Log.w(TAG, "⚠️ [SESSION] movil vacío/inválido → Sesión INACTIVA")
                LocationLogger.logEvent(context, "SESSION_CHECK_FAILED", mapOf(
                    "reason" to "Invalid or empty movil",
                    "movil" to savedMovil
                ))
                return false
            }
            
            if (savedEscenario.isEmpty() || savedEscenario == "0" || savedEscenario == "unknown") {
                Log.w(TAG, "⚠️ [SESSION] escenario vacío/inválido → Sesión INACTIVA")
                LocationLogger.logEvent(context, "SESSION_CHECK_FAILED", mapOf(
                    "reason" to "Invalid or empty escenario",
                    "escenario" to savedEscenario
                ))
                return false
            }
            
            if (savedUsuario.isEmpty() || savedUsuario == "unknown") {
                Log.w(TAG, "⚠️ [SESSION] usuario vacío/inválido → Sesión INACTIVA")
                LocationLogger.logEvent(context, "SESSION_CHECK_FAILED", mapOf(
                    "reason" to "Invalid or empty usuario",
                    "usuario" to savedUsuario
                ))
                return false
            }
            
            // Verificar que loginDate sea de HOY
            val today = getTodayDateString()
            if (savedLoginDate != today) {
                Log.w(TAG, "⚠️ [SESSION] loginDate NO es de hoy (loginDate=$savedLoginDate, today=$today) → Sesión INACTIVA")
                LocationLogger.logEvent(context, "SESSION_CHECK_FAILED", mapOf(
                    "reason" to "Login date is not today",
                    "loginDate" to savedLoginDate,
                    "today" to today
                ))
                return false
            }
            
            // 2️⃣ VALIDACIÓN: Verificar FirebaseAuth
            val auth = FirebaseAuth.getInstance()
            val currentUser = auth.currentUser
            
            if (currentUser == null) {
                Log.w(TAG, "⚠️ [SESSION] No hay usuario en FirebaseAuth → Sesión INACTIVA")
                LocationLogger.logEvent(context, "SESSION_CHECK_FAILED", mapOf(
                    "reason" to "FirebaseAuth.currentUser == null"
                ))
                return false
            }
            
            // 3️⃣ VALIDACIÓN: Verificar flag sessionActive (actualizado por Flutter)
            // NOTA: NO consultamos Firestore desde Kotlin porque:
            // - Requiere reglas de seguridad complejas
            // - Puede dar timeout (5 segundos)
            // - Flutter actualiza este flag cuando crea/cierra sesión
            if (!sessionActive) {
                Log.w(TAG, "⚠️ [SESSION] Flag sessionActive = false → Sesión INACTIVA")
                Log.w(TAG, "⚠️ [SESSION] (Flutter debe actualizar este flag al crear/cerrar sesión)")
                LocationLogger.logEvent(context, "SESSION_CHECK_FAILED", mapOf(
                    "reason" to "sessionActive flag is false (set by Flutter)",
                    "savedMovil" to savedMovil,
                    "savedEscenario" to savedEscenario,
                    "savedUsuario" to savedUsuario,
                    "loginDate" to savedLoginDate
                ))
                return false
            }
            
            // ✅ TODAS LAS VALIDACIONES PASARON
            Log.d(TAG, "✅ [SESSION] Sesión ACTIVA: movil=$savedMovil, escenario=$savedEscenario, usuario=$savedUsuario, fecha=$today, sessionActive=$sessionActive")
            return true
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ [SESSION] Error verificando sesión: ${e.message}", e)
            LocationLogger.logError(context, "SESSION_CHECK_ERROR", e.message ?: "Unknown error")
            return false
        }
    }

    /**
     * Funciones para manejo de distancia persistente por día
     */
    private fun getTodayDateString(): String {
        return SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
    }

    private fun saveDailyDistance(context: Context, distance: Float) {
        val today = getTodayDateString()
        val prefs = context.getSharedPreferences("daily_tracking", Context.MODE_PRIVATE)
        prefs.edit().apply {
            putFloat("distance_$today", distance)
            putString("last_update_$today", System.currentTimeMillis().toString())
            putString("last_reset_reason", lastResetReason)
        }.apply()
        Log.d(TAG, "💾 Distancia guardada: ${distance}m para fecha: $today")
    }

    private fun loadDailyDistance(context: Context): Float {
        val today = getTodayDateString()
        val prefs = context.getSharedPreferences("daily_tracking", Context.MODE_PRIVATE)
        val distance = prefs.getFloat("distance_$today", 0.0f)
        Log.d(TAG, "📖 Distancia cargada: ${distance}m para fecha: $today")
        return distance
    }

    private fun checkAndResetDaily(context: Context): String {
        val prefs = context.getSharedPreferences("daily_tracking", Context.MODE_PRIVATE)
        val lastDate = prefs.getString("last_tracking_date", "")
        val today = getTodayDateString()
        
        if (lastDate != today) {
            // Nuevo día - reset automático
            val previousDistance = totalDistance
            totalDistance = 0.0f
            lastLocation = null
            lastResetReason = "Día"
            
            prefs.edit().apply {
                putString("last_tracking_date", today)
                putFloat("distance_$today", 0.0f)
                putString("daily_reset_reason", "Nuevo día")
                putLong("daily_reset_timestamp", System.currentTimeMillis())
                putBoolean("first_sent_today_$today", false)  // Reset flag de PRIMERA
            }.apply()
            
            Log.i(TAG, "📅 Reset por nuevo día: $lastDate -> $today (distancia anterior: ${previousDistance}m)")
            LocationLogger.logEvent(context, "DAILY_DISTANCE_RESET", mapOf(
                "previous_date" to (lastDate ?: "none"),
                "new_date" to today,
                "previous_distance" to previousDistance.toString(),
                "reset_reason" to "Nuevo día"
            ))
            
            return "Día"
        } else {
            // Mismo día - cargar distancia acumulada
            totalDistance = loadDailyDistance(context)
            lastResetReason = prefs.getString("last_reset_reason", "") ?: ""
            
            Log.d(TAG, "📈 Mismo día $today - distancia acumulada: ${totalDistance}m")
            return "No"
        }
    }

    fun resetDailyDistanceByService(context: Context, reason: String) {
        val today = getTodayDateString()
        val prefs = context.getSharedPreferences("daily_tracking", Context.MODE_PRIVATE)
        val previousDistance = totalDistance
        
        // Guardar distancia final antes del reset
        prefs.edit().apply {
            putFloat("final_distance_$today", totalDistance)
            putString("service_stop_reason_$today", reason)
            putLong("service_stop_timestamp", System.currentTimeMillis())
        }.apply()
        
        // Reset por comando del servicio
        totalDistance = 0.0f
        lastLocation = null
        lastResetReason = "Servicio"
        
        Log.w(TAG, "🛑 Reset por servicio: ${reason} (distancia acumulada: ${previousDistance}m)")
        LocationLogger.logEvent(context, "SERVICE_DISTANCE_RESET", mapOf(
            "reason" to reason,
            "date" to today,
            "accumulated_distance" to previousDistance.toString(),
            "reset_reason" to "Servicio"
        ))
        
        saveDailyDistance(context, totalDistance)
    }
    
    /**
     * 🌅 DETECCIÓN DE CAMBIO DE DÍA
     * 
     * Verifica si cambió el día comparando loginDate (guardado en SharedPreferences por Flutter)
     * con la fecha actual.
     * 
     * @return true si cambió el día (sesión inválida), false si es el mismo día (sesión válida)
     * 
     * Esta función se ejecuta cada vez que el servicio GPS se ejecuta (~30 segundos),
     * garantizando detección automática del cambio de día mientras la app está en uso.
     */
    fun checkForDayChange(context: Context, movil: String, escenario: String, usuario: String, deviceId: String): Boolean {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val loginDate = prefs.getString("flutter.loginDate", null)
            
            if (loginDate == null) {
                // No hay loginDate guardado, probablemente sesión no iniciada
                Log.d(TAG, "🌅 [DAY_CHECK] loginDate no encontrado en SharedPreferences")
                return false // No marcar como cambio de día si no hay loginDate
            }
            
            // Obtener fecha actual en formato YYYY-MM-DD
            val currentDate = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
            
            Log.d(TAG, "🌅 [DAY_CHECK] loginDate: $loginDate | currentDate: $currentDate")
            
            if (loginDate != currentDate) {
                // ¡CAMBIÓ EL DÍA! 
                Log.e(TAG, "🌅 [DAY_CHANGE] ¡Cambio de día detectado! ($loginDate -> $currentDate)")
                
                // 🔥 Log crítico visible SIEMPRE (independiente de debugMode)
                com.riogas.appmovil.CriticalLogger.logCritical(
                    TAG,
                    "CAMBIO DE DÍA DETECTADO - Sesión inválida por cambio de fecha",
                    mapOf(
                        "loginDate" to loginDate,
                        "currentDate" to currentDate,
                        "movil" to movil,
                        "escenario" to escenario,
                        "usuario" to usuario,
                        "deviceId" to deviceId,
                        "action" to "Deteniendo servicio GPS",
                        "reason" to "Auto-logout por cambio de día"
                    ),
                    "DAY_CHANGE_DETECTED"
                )
                
                // 📊 Registrar evento de cambio de día
                LocationLogger.logEvent(context, "DAY_CHANGE_AUTO_LOGOUT", mapOf(
                    "login_date" to loginDate,
                    "current_date" to currentDate,
                    "movil" to movil,
                    "action" to "GPS service will be stopped"
                ))
                
                // Enviar cierre al backend
                sendCloseToBackend(context, movil, escenario, usuario, deviceId, "AutoLogoutCambioDia")
                
                return true // Cambio de día detectado
                
            } else {
                // Mismo día, todo OK
                Log.d(TAG, "🌅 [DAY_CHECK] Mismo día - sesión válida")
                return false // Mismo día, sesión válida
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ [DAY_CHECK] Error verificando cambio de día: ${e.message}", e)
            com.riogas.appmovil.CriticalLogger.logCritical(
                TAG,
                "ERROR en checkForDayChange",
                mapOf(
                    "error" to (e.message ?: "unknown"),
                    "movil" to movil
                ),
                "DAY_CHECK_ERROR"
            )
            return false // En caso de error, no detener el servicio
        }
    }
    
    /**
     * � Enviar cierre al backend antes de detener servicio por cambio de día
     */
    private fun sendCloseToBackend(context: Context, movil: String, escenario: String, usuario: String, deviceId: String, reason: String) {
        try {
            Log.i(TAG, "📡 [BACKEND] Enviando cierre por cambio de día: movil=$movil, reason=$reason")
            
            // 🌍 Obtener URL desde SharedPreferences
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            var baseUrl = prefs.getString("flutter.baseUrl", "https://www.riogas.uy/ica_geos_/appservices/") ?: "https://www.riogas.uy/ica_geos_/appservices/"
            
            // 🔧 ASEGURAR que baseUrl incluya /appservices/ (fix para SGM y otros ambientes)
            if (!baseUrl.contains("/appservices/")) {
                baseUrl = baseUrl.trimEnd('/') + "/appservices/"
                Log.d(TAG, "🔧 [URL-FIX] URL ajustada para incluir /appservices/: $baseUrl")
            }
            
            val url = "${baseUrl}RegistrarCierre"
            
            // 📦 Obtener datos adicionales de SharedPreferences
            val appVersion = prefs.getString("flutter.appVersion", "1.0.0") ?: "1.0.0"
            val nombreUsuario = prefs.getString("flutter.NombreUsuario", "") ?: ""
            
            val client = OkHttpClient.Builder()
                .connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
                .writeTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
                .readTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
                .build()
            
            val isoDate = DateTimeFormatter.ISO_INSTANT.format(Instant.now())
            
            // ✅ Usar EXACTAMENTE el mismo formato que la versión Dart (riogas_service.dart)
            val jsonBody = """
                {
                    "token": "IcA.FwL.1710.!",
                    "movil": ${movil.toIntOrNull() ?: 0},
                    "DeviceId": "$deviceId",
                    "usuario": "$usuario",
                    "TipoCierre": "$reason",
                    "FechaHora": "$isoDate",
                    "version": "$appVersion",
                    "origen": "MoveIT",
                    "usuarioCierre": "$nombreUsuario",
                    "aplicaFirestore": false
                }
            """.trimIndent()
            
            // 🔍 LOG DETALLADO DEL REQUEST
            Log.d(TAG, "🔍 [REQUEST] URL: $url")
            Log.d(TAG, "🔍 [REQUEST] Headers:")
            Log.d(TAG, "    - accept: application/json")
            Log.d(TAG, "    - Content-Type: application/json")
            Log.d(TAG, "🔍 [REQUEST] Body:")
            Log.d(TAG, jsonBody)
            
            val request = Request.Builder()
                .url(url)
                .addHeader("accept", "application/json")
                .addHeader("Content-Type", "application/json")
                .post(jsonBody.toRequestBody("application/json".toMediaType()))
                .build()
            
            // Ejecutar en thread separado para no bloquear
            Thread {
                try {
                    client.newCall(request).execute().use { response ->
                        val responseBody = response.body?.string() ?: ""
                        
                        // 🔍 LOG DETALLADO DEL RESPONSE
                        Log.d(TAG, "🔍 [RESPONSE] Status Code: ${response.code}")
                        Log.d(TAG, "🔍 [RESPONSE] Headers:")
                        response.headers.forEach { (name, value) ->
                            Log.d(TAG, "    - $name: $value")
                        }
                        Log.d(TAG, "🔍 [RESPONSE] Body:")
                        Log.d(TAG, responseBody)
                        
                        if (response.isSuccessful) {
                            Log.i(TAG, "✅ [BACKEND] Cierre registrado exitosamente")
                        } else {
                            Log.w(TAG, "⚠️ [BACKEND] Error registrando cierre: ${response.code}")
                            Log.w(TAG, "⚠️ [BACKEND] Response body: $responseBody")
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ [BACKEND] Error enviando cierre: ${e.message}", e)
                }
            }.start()
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error enviando cierre al backend: ${e.message}", e)
        }
    }
    
    /**
     * 🆕 FASE 2: Registrar callback de GNSS para monitorear satélites
     */
    private fun registerGnssCallback(context: Context) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) {
            Log.w(TAG, "⚠️ [GNSS] Requiere Android 7.0+ (API 24+), versión actual: ${android.os.Build.VERSION.SDK_INT}")
            return
        }
        
        try {
            val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            
            val gnssCallback = object : android.location.GnssStatus.Callback() {
                override fun onSatelliteStatusChanged(status: android.location.GnssStatus) {
                    // 🔧 THROTTLING: Solo loguear cada 5 segundos para evitar spam
                    val now = System.currentTimeMillis()
                    val timeSinceLastLog = now - lastGnssLogTime
                    val minLogInterval = 5000L // 5 segundos
                    
                    val totalSats = status.satelliteCount
                    var usedSats = 0
                    var totalSnr = 0f
                    
                    for (i in 0 until totalSats) {
                        if (status.usedInFix(i)) {
                            usedSats++
                            totalSnr += status.getCn0DbHz(i)
                        }
                    }
                    
                    val avgSnr = if (usedSats > 0) totalSnr / usedSats else 0f
                    
                    // Guardar para logging posterior (siempre actualizar)
                    lastSatelliteCount = totalSats
                    lastUsedSatellites = usedSats
                    lastAvgSnr = avgSnr
                    
                    // Solo loguear si han pasado 5+ segundos desde el último log
                    if (timeSinceLastLog >= minLogInterval) {
                        lastGnssLogTime = now
                        
                        Log.i(TAG, "🛰️ [GNSS] Satélites: $usedSats/$totalSats usados | SNR promedio: ${String.format("%.1f", avgSnr)}dB")
                        
                        if (usedSats < 4) {
                            Log.w(TAG, "⚠️ [GNSS] Pocos satélites ($usedSats < 4), precisión puede ser baja")
                        }
                        
                        if (avgSnr < 20f && usedSats > 0) {
                            Log.w(TAG, "⚠️ [GNSS] SNR bajo (${String.format("%.1f", avgSnr)}dB), señal débil")
                        }
                    }
                }
            }
            
            locationManager.registerGnssStatusCallback(gnssCallback, android.os.Handler(android.os.Looper.getMainLooper()))
            Log.i(TAG, "✅ [GNSS] Callback registrado para monitoreo de satélites")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ [GNSS] Error registrando callback: ${e.message}")
        }
    }

    @SuppressLint("MissingPermission")
    fun getCurrentLocation(
        context: Context,
        movil: String,
        escenario: String,
        usuario: String,
        deviceId: String,
        executionCounter: Int = 0, // 🆕 Contador de ejecuciones para control de envío a Riogas
        isFirstExecution: Boolean = false // 🆕 Flag para envío instantáneo al login
    ): Map<String, Any?> {
        // Fix puntual SIN warm-up ni arranque de servicios: el tracking continuo
        // (LocationTrackingService) mantiene el chip GPS caliente. Este método solo
        // obtiene una ubicación puntual para el pipeline legacy (RioGas/n8n) vía Dart.
        Log.d(TAG, "📍 [PUNTUAL] getCurrentLocation ejecución #$executionCounter (isFirstExecution=$isFirstExecution)")
        DebugLogger.i(TAG, "getCurrentLocation iniciado", mapOf(
            "movil" to movil,
            "escenario" to escenario,
            "usuario" to usuario,
            "deviceId" to deviceId,
            "executionCounter" to executionCounter,
            "isFirstExecution" to isFirstExecution
        ))

        // 🆕 USAR FUSED LOCATION API (Google Play Services) - Lo mismo que usa Flutter internamente
        val fusedLocationClient = LocationServices.getFusedLocationProviderClient(context)

        val appState = isAppActive(context)
        Log.i(TAG, "📱 Estado de la aplicación: $appState")

        // --- 1. Verificar permisos ---
        val hasFine = ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val hasCoarse = ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val hasBackground = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
        } else {
            true // Android <10 no requiere permiso explícito de background
        }
        
        // Verificar optimización de batería
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val isBatterySaverOn = powerManager.isPowerSaveMode
        val isIgnoringBatteryOptimizations = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            powerManager.isIgnoringBatteryOptimizations(context.packageName)
        } else {
            true // Android <6 no tiene optimización de batería
        }
        
        // Verificar Doze Mode (Android 6+)
        val isDeviceIdle = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            powerManager.isDeviceIdleMode
        } else {
            false
        }
        
        // 🆕 LOGUEAR ESTADO COMPLETO DE PERMISOS Y BATERÍA
        DebugLogger.i(TAG, "Estado de permisos y batería", mapOf(
            "movil" to movil,
            "permission_fine" to hasFine,
            "permission_coarse" to hasCoarse,
            "permission_background" to hasBackground,
            "battery_saver_on" to isBatterySaverOn,
            "battery_optimization_ignored" to isIgnoringBatteryOptimizations,
            "doze_mode_active" to isDeviceIdle,
            "android_version" to Build.VERSION.SDK_INT,
            "app_state" to appState
        ))

        if (!hasFine && !hasCoarse) {
            Log.w(TAG, "🚫 Sin permisos de ubicación (ni FINE ni COARSE). Intentando IP o datos previos...")
            DebugLogger.w(TAG, "Sin permisos de ubicación", mapOf(
                "movil" to movil,
                "has_fine" to false,
                "has_coarse" to false,
                "has_background" to hasBackground
            ))
            // 🚫 SIN PERMISOS = NO ENVIAR COORDENADAS
            Log.e(TAG, "🚫 [NO-PERMISSIONS] Sin permisos de ubicación - NO se enviarán coordenadas")
            return emptyMap()
        }
        
        Log.d(TAG, "🔧 [FUSED-API] Usando FusedLocationProviderClient (lo mismo que Flutter internamente)")
        Log.d(TAG, "🎯 [PRIORITY] Alta precisión HIGH_ACCURACY (GPS como prioridad)")
        Log.d(TAG, "⚙️ [TIMEOUT] 45 segundos (suficiente para cold start indoor)")

        // --- 2. Obtener ubicación ACTUAL usando estrategia HIGH_ACCURACY ---
        var location: Location? = null
        var providerUsed = "fused"
        
        try {
            Log.d(TAG, "🎯 [FUSED-START] Solicitando ubicación puntual (fix único)...")

            val googleApiAvailability = GoogleApiAvailability.getInstance()
            val resultCode = googleApiAvailability.isGooglePlayServicesAvailable(context)
            if (resultCode != ConnectionResult.SUCCESS) {
                Log.e(TAG, "❌ [FUSED-ERROR] Google Play Services no disponible: código=$resultCode")
                throw Exception("Google Play Services no disponible")
            }

            // Fix puntual: el chip GPS ya está caliente por el tracking continuo del FGS.
            // Sin warm-up de 7 fixes, sin polling ni Thread.sleep: un getCurrentLocation con timeout.
            val cts = CancellationTokenSource()
            location = Tasks.await(
                fusedLocationClient.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, cts.token),
                15, TimeUnit.SECONDS
            )
            if (location != null) {
                providerUsed = location.provider ?: "fused"
                Log.i(TAG, "📍 [COORDS] Lat: ${location.latitude}, Lng: ${location.longitude}, Accuracy=${location.accuracy}m")
            } else {
                Log.w(TAG, "❌ [NO-FIX] getCurrentLocation devolvió null")
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "❌ [PERMISSION] Error de permisos: ${e.message}")
            Log.e(TAG, "❌ [PERMISSION] ¿Permisos FINE_LOCATION y BACKGROUND_LOCATION concedidos?")
            LocationLogger.logError(context, "FUSED_PERMISSION_ERROR", e.message ?: "Unknown error")
        } catch (e: Exception) {
            Log.e(TAG, "❌ [ERROR] Error obteniendo ubicación: ${e.message}", e)
            LocationLogger.logError(context, "FUSED_LOCATION_ERROR", e.message ?: "Unknown error")
        }

        return if (location != null) {
            Log.d(TAG, "📍 Ubicación obtenida de ${location.provider}")

            val lat = location.latitude
            val lon = location.longitude
            val speedGPS = location.speed // Velocidad reportada por GPS
            
            // 🆕 FASE 1: CALCULAR VELOCIDAD MANUAL (más precisa que GPS en trayectos cortos)
            var speedManual = 0f
            if (lastLocation != null) {
                val distance = lastLocation!!.distanceTo(location) // metros
                val timeDelta = (location.time - lastLocation!!.time) / 1000.0 // segundos
                if (timeDelta > 0) {
                    speedManual = (distance / timeDelta).toFloat() // m/s
                }
            }
            
            // 🆕 Usar la velocidad manual si es más confiable, sino GPS
            val speed = if (speedManual > 0) {
                Log.d(TAG, "🚗 [SPEED] GPS: ${speedGPS}m/s | Manual: ${speedManual}m/s → Usando: ${speedManual}m/s")
                speedManual
            } else {
                Log.d(TAG, "🚗 [SPEED] GPS: ${speedGPS}m/s | Manual: N/A → Usando GPS")
                speedGPS
            }

            // Guardar en SharedPreferences para fallback futuro
            val shared = context.getSharedPreferences("coords", Context.MODE_PRIVATE)
            shared.edit().apply {
                putFloat("lat", lat.toFloat())
                putFloat("lon", lon.toFloat())
                putLong("timestamp", System.currentTimeMillis())
                putString("provider", providerUsed)
            }.apply()
            Log.v(TAG, "💾 Ubicación guardada en caché para fallback")

            // Cargar distancia diaria desde persistencia (no relacionado con envío GPS)
            totalDistance = loadDailyDistance(context)
            Log.i(TAG, "🔄 Distancia cargada desde persistencia: ${totalDistance}m")

            // Verificar y procesar reset diario
            val resetReason = checkAndResetDaily(context)
            if (resetReason != "No") {
                Log.i(TAG, "🗓️ Reset diario aplicado - Razón: $resetReason")
            }

            // Obtener fecha actual para verificaciones
            val today = getTodayDateString()

            // Calcular tipo de movimiento antes de filtrar
            var movementType: String
            var filteredDistance = 0f
            var rawDistance = 0f
            
            if (lastLocation != null) {
                rawDistance = lastLocation!!.distanceTo(location)
                
                // ===== SIN FILTRADO - DISTANCIA SIEMPRE SE SUMA =====
                filteredDistance = filterGPSNoise(rawDistance, location, lastLocation!!, speed)
                
                // ✅ SUMAR SIEMPRE LA DISTANCIA (sin filtros que la descarten)
                Log.i(TAG, "✅ [DISTANCE] Distancia calculada: ${filteredDistance}m → Será sumada SIEMPRE")
                
                // 🆕 CLASIFICACIÓN SIMPLE: QUIETO < 3m, MOVIMIENTO ≥ 3m
                movementType = if (filteredDistance < 3.0f) {
                    Log.i(TAG, "🔵 [MOVEMENT] QUIETO - Distancia < 3m (${filteredDistance}m)")
                    "QUIETO"
                } else {
                    Log.i(TAG, "🟢 [MOVEMENT] MOVIMIENTO - Distancia ≥ 3m (${filteredDistance}m)")
                    "MOVIMIENTO"
                }
            } else {
                // Primera ejecución del día O reinicio de proceso
                // Verificar si ya se envió PRIMERA hoy
                val prefs = context.getSharedPreferences("daily_tracking", Context.MODE_PRIVATE)
                val firstSentToday = prefs.getBoolean("first_sent_today_$today", false)
                
                movementType = if (firstSentToday) {
                    "QUIETO"  // Ya se envió PRIMERA hoy, marcar como QUIETO
                } else {
                    // Marcar que ya se envió PRIMERA hoy
                    prefs.edit().putBoolean("first_sent_today_$today", true).apply()
                    "PRIMERA"  // Primera lectura del día
                }
            }
            
            // ===== OPTIMIZACIÓN DE RUIDO GPS =====
            // Distancias < 5m = Suma 0.1m (registro simbólico sin inflar distancia)
            // Distancias >= 5m = Suma distancia real (movimiento genuino)
            if (filteredDistance > 0f) {
                val distanceToAdd = if (filteredDistance < 5.0f) {
                    0.1f  // Ruido GPS: suma simbólica para registro
                } else {
                    filteredDistance  // Movimiento real: suma completa
                }
                
                totalDistance += distanceToAdd
                saveDailyDistance(context, totalDistance)
                
                if (filteredDistance < 5.0f) {
                    Log.d(TAG, "� Ruido GPS: ${rawDistance}m → ${filteredDistance}m → Sumado: 0.1m (Total: ${totalDistance}m) | Tipo: $movementType")
                } else {
                    Log.d(TAG, "✅ Movimiento real: ${rawDistance}m → ${filteredDistance}m → Sumado: ${filteredDistance}m (Total: ${totalDistance}m) | Tipo: $movementType")
                }
            } else {
                Log.d(TAG, "🔇 Distancia descartada por filtros: ${rawDistance}m (velocidad: ${speed}m/s) | Tipo: $movementType | Razón: Accuracy/Speed/Time fuera de rango")
            }
            lastLocation = location

            val (utmX, utmY) = convertToUTM(lat, lon)

            Log.i(TAG, "📌 Coordenadas: lat=$lat, lon=$lon, utmX=$utmX, utmY=$utmY, velocidad=${speed}m/s, distancia total=${totalDistance}m, tipo: $movementType")

            // 🆕 INTENTAR ENVIAR A N8N WEBHOOK (cada 30 seg, SOLO SI gpsN8nEnabled=true)
            Log.d(TAG, "📤 [N8N] Intentando enviar a n8n webhook (ejecución #$executionCounter)")
            sendToN8nWebhook(
                context, location, lat, lon, utmX, utmY, totalDistance, speed,
                movil, escenario, usuario, deviceId, providerUsed, movementType, executionCounter
            )
            
            // 🆕 ENVIAR A RIOGAS: SIEMPRE en primera ejecución (login), luego cada 6 ejecuciones (3 min)
            val shouldSendToRiogas = isFirstExecution || (executionCounter % 6 == 0)
            
            if (shouldSendToRiogas) {
                val reason = if (isFirstExecution) "🎯 PRIMER LOGIN (envío instantáneo)" else "⏰ Ciclo regular (cada 3 min)"
                Log.d(TAG, "📤 [RIOGAS] $reason - Enviando datos a Riogas API")
                invokeRegistrarCoordenadasV2Api(context, lat, lon, utmX, utmY, totalDistance, speed, movil, escenario, usuario, deviceId, providerUsed, movementType)
            } else {
                val nextRiogasIn = 6 - (executionCounter % 6)
                Log.d(TAG, "⏭️ [RIOGAS] Próximo envío a Riogas en $nextRiogasIn ejecuciones (${nextRiogasIn * 30}s)")
            }

            mapOf(
                "latitude" to lat,
                "longitude" to lon,
                "utmX" to utmX,
                "utmY" to utmY,
                "speed" to speed,
                "totalDistance" to totalDistance,
                "appState" to appState
            )
        } else {
            // 🚫 NUNCA ENVIAR COORDENADAS CACHE - Diagnosticar y reintentar o abortar
            Log.e(TAG, "❌ [GPS-FAIL] No se pudo obtener ubicación GPS real")
            
            // 🔍 DIAGNOSTICAR CAUSA ESPECÍFICA DEL FALLO
            val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            val debugMode = prefs.getBoolean("debugMode", false)
            
            val hasFineLocation = ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            val hasCoarseLocation = ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
            val hasBackgroundLocation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
            } else true
            
            val googleApiAvailability = GoogleApiAvailability.getInstance()
            val playServicesAvailable = googleApiAvailability.isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS
            
            val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val gpsEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
            
            val failureReason = when {
                !hasFineLocation && !hasCoarseLocation -> "NO_LOCATION_PERMISSION"
                !hasBackgroundLocation -> "NO_BACKGROUND_PERMISSION"
                !playServicesAvailable -> "GOOGLE_PLAY_SERVICES_UNAVAILABLE"
                !gpsEnabled -> "GPS_DISABLED_IN_SETTINGS"
                else -> "GPS_TIMEOUT_OR_WEAK_SIGNAL"
            }
            
            Log.e(TAG, "🔍 [DIAGNOSIS] Razón del fallo: $failureReason")
            Log.e(TAG, "🔍 [PERMISSIONS] FINE=$hasFineLocation | COARSE=$hasCoarseLocation | BACKGROUND=$hasBackgroundLocation")
            Log.e(TAG, "🔍 [SERVICES] PlayServices=$playServicesAvailable | GPS_ON=$gpsEnabled")
            
            // 🔥 LOG CRÍTICO SI DEBUG MODE ACTIVO
            if (debugMode) {
                com.riogas.appmovil.CriticalLogger.logCritical(
                    TAG,
                    "GPS FALLÓ - NO SE ENVIARÁN COORDENADAS CACHE",
                    Exception("GPS acquisition failed: $failureReason"),
                    mapOf(
                        "failure_reason" to failureReason,
                        "movil" to movil,
                        "escenario" to escenario,
                        "has_fine_permission" to hasFineLocation,
                        "has_coarse_permission" to hasCoarseLocation,
                        "has_background_permission" to hasBackgroundLocation,
                        "play_services_available" to playServicesAvailable,
                        "gps_enabled" to gpsEnabled,
                        "app_state" to appState,
                        "execution_counter" to executionCounter
                    ),
                    "GPS_FAILURE_NO_CACHE"
                )
            }
            
            // 🚫 NUNCA RETORNAR COORDENADAS CACHE - Retornar mapa vacío
            Log.e(TAG, "🚫 [ABORT] NO se enviarán coordenadas CACHE a ningún servicio")
            
            emptyMap() // ❌ SIN COORDENADAS CACHE
        }
    }

    private fun areNotificationsEnabled(context: Context): Boolean {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        return notificationManager.areNotificationsEnabled()
    }

    private fun isGPSEnabled(context: Context): Boolean {
        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
    }


    /**
     * Invoca el API de RioGas para registrar coordenadas con retry y procesamiento de respuesta
     * 🆕 CON CIRCUIT BREAKER MEJORADO: Múltiples capas de protección contra tormentas de requests
     */
    private fun invokeRegistrarCoordenadasV2Api(context: Context, lat: Double, lon: Double, utmX: Double, utmY: Double, totalDistance: Float, speed: Float, movil: String, escenario: String, usuario: String, deviceId: String, providerUsed: String, movementType: String = "DESCONOCIDO") {
        // � FIX v14.7: Relajar validación - deviceId es suficiente
        // �🛡️ VALIDACIÓN CRÍTICA: Verificar que deviceId NO esté vacío (movil puede estar vacío)
        if (deviceId.isEmpty() || deviceId.isBlank()) {
            Log.e(TAG, "🚫 BLOQUEADO: deviceId vacío detectado! NO se enviará request")
            DebugLogger.e(TAG, "API Request bloqueado - deviceId vacío", null, mapOf(
                "lat" to lat,
                "lon" to lon,
                "movil" to movil,
                "reason" to "deviceId vacío - request descartado"
            ))
            return // ❌ Sin deviceId, no podemos continuar
        }
        
        // ⚠️ ADVERTENCIA: Si movil vacío, intentar recuperar pero NO bloquear request
        var finalMovil = movil
        if (finalMovil.isEmpty() || finalMovil.isBlank()) {
            Log.w(TAG, "⚠️ movil vacío, intentando recuperar de SharedPreferences...")
            val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            val savedMovil = prefs.getString("last_movil", "") ?: ""
            
            if (savedMovil.isEmpty()) {
                Log.w(TAG, "⚠️ No hay movil guardado - usando \"0\" como fallback")
                finalMovil = "0" // Usar "0" como valor por defecto
                DebugLogger.w(TAG, "Movil vacío - usando fallback", mapOf(
                    "deviceId" to deviceId,
                    "movil_fallback" to "0",
                    "note" to "Request continuará con movil=0"
                ))
            } else {
                Log.i(TAG, "✅ Movil recuperado de SharedPreferences: $savedMovil")
                finalMovil = savedMovil
            }
        }
        
        // 🆕 CIRCUIT BREAKER MEJORADO: Verificar múltiples condiciones
        val prefs = context.getSharedPreferences("location_errors", Context.MODE_PRIVATE)
        val errorCount = prefs.getInt("error_count", 0)
        val lastErrorTime = prefs.getLong("last_error_time", 0)
        val lastSuccessTime = prefs.getLong("last_success_time", 0)
        val now = System.currentTimeMillis()
        
        // 🛡️ PROTECCIÓN 1: Cooldown progresivo según cantidad de errores
        val cooldownMs = when {
            errorCount > 100 -> 300000L  // 5 minutos si >100 errores
            errorCount > 50 -> 180000L   // 3 minutos si >50 errores
            errorCount > 20 -> 60000L    // 1 minuto si >20 errores
            errorCount > 10 -> 30000L    // 30 segundos si >10 errores
            else -> 0L                   // Sin cooldown si <10 errores
        }
        
        if (cooldownMs > 0) {
            val timeSinceLastError = now - lastErrorTime
            if (timeSinceLastError < cooldownMs) {
                val remainingTime = (cooldownMs - timeSinceLastError) / 1000
                Log.w(TAG, "🚫 CIRCUIT BREAKER ACTIVADO: Demasiados errores ($errorCount). Bloqueando request por ${remainingTime}s más")
                com.riogas.appmovil.DebugLogger.w(TAG, "Circuit Breaker activo", mapOf(
                    "errorCount" to errorCount,
                    "cooldownRemaining" to remainingTime,
                    "reason" to "Protección contra tormenta de requests"
                ))
                return // NO INTENTAR enviar
            } else {
                // Cooldown terminado, resetear contador y permitir intento
                Log.i(TAG, "✅ CIRCUIT BREAKER: Cooldown terminado, permitiendo nuevo intento...")
                resetErrorCount(context)
            }
        }
        
        // 🛡️ PROTECCIÓN 2: Rate limiting - máximo 1 request cada 500ms
        val lastRequestTime = prefs.getLong("last_request_time", 0)
        val timeSinceLastRequest = now - lastRequestTime
        val minRequestInterval = 500L // Mínimo 500ms entre requests
        
        if (timeSinceLastRequest < minRequestInterval) {
            val waitTime = minRequestInterval - timeSinceLastRequest
            Log.w(TAG, "⏱️ RATE LIMIT: Request demasiado frecuente, bloqueando por ${waitTime}ms")
            com.riogas.appmovil.DebugLogger.w(TAG, "Rate limit aplicado", mapOf(
                "timeSinceLastRequest" to timeSinceLastRequest,
                "minInterval" to minRequestInterval,
                "reason" to "Protección contra requests consecutivos"
            ))
            return
        }
        
        // 🛡️ PROTECCIÓN 3: Si los últimos 5 intentos fueron todos errores 400, bloquear por 2 minutos
        val last5Errors = prefs.getString("last_5_errors", "")?.split(",")?.filter { it.isNotEmpty() } ?: emptyList()
        if (last5Errors.size >= 5 && last5Errors.all { it == "400" }) {
            val timeSinceLastSuccess = now - lastSuccessTime
            val http400CooldownMs = 120000L // 2 minutos
            
            // Si NO ha habido éxito en los últimos 2 minutos, bloquear
            if (lastSuccessTime == 0L || timeSinceLastSuccess < http400CooldownMs) {
                val remainingTime = if (lastSuccessTime > 0) (http400CooldownMs - timeSinceLastSuccess) / 1000 else 120
                Log.w(TAG, "🚫 HTTP 400 PROTECTION: Últimos 5 intentos fallaron con 400. Bloqueando por ${remainingTime}s")
                com.riogas.appmovil.DebugLogger.w(TAG, "HTTP 400 protection activa", mapOf(
                    "consecutiveErrors" to 5,
                    "errorCode" to 400,
                    "cooldownRemaining" to remainingTime,
                    "reason" to "JSON inválido o problema de datos"
                ))
                return
            } else {
                // Cooldown terminado, limpiar historial de errores para permitir nuevo intento
                Log.i(TAG, "✅ HTTP 400 PROTECTION: Cooldown terminado, limpiando historial...")
                prefs.edit().remove("last_5_errors").apply()
            }
        }
        
        // Registrar timestamp de este request
        prefs.edit().putLong("last_request_time", now).apply()
        
        // Intentar con retry inteligente (usando finalMovil validado)
        invokeRegistrarCoordenadasV2ApiWithRetry(context, lat, lon, utmX, utmY, totalDistance, speed, finalMovil, escenario, usuario, deviceId, providerUsed, movementType, 0)
    }
    
    /**
     * Invoca el API con lógica de reintentos SECUENCIALES
     * 🔧 OPTIMIZADO: Solo 1 intento (si falla con 400, es problema de datos, no de red)
     */
    // 🆕 Función pública para enviar coordenadas a Riogas API
    // Necesaria para que FcmPushReceiver pueda enviar coordenadas forzadas
    fun invokeRegistrarCoordenadasV2ApiWithRetry(context: Context, lat: Double, lon: Double, utmX: Double, utmY: Double, totalDistance: Float, speed: Float, movil: String, escenario: String, usuario: String, deviceId: String, providerUsed: String, movementType: String, retryCount: Int) {
        val maxRetries = 1 // 🔧 Reducido de 3 a 1 (evita tormentas de requests con errores de datos)
        
        // 🌍 Obtener URL desde SharedPreferences (guardada por Flutter según ambiente)
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        var baseUrl = prefs.getString("flutter.baseUrl", "https://www.riogas.uy/ica_geos_/appservices/") ?: "https://www.riogas.uy/ica_geos_/appservices/"
        
        // 🔧 FIX: Asegurar que baseUrl termine con /appservices/
        if (!baseUrl.endsWith("/appservices/")) {
            baseUrl = if (baseUrl.endsWith("/")) {
                "${baseUrl}appservices/"
            } else {
                "${baseUrl}/appservices/"
            }
            Log.d(TAG, "🔧 [URL_FIX] Agregado /appservices/ → $baseUrl")
        }
        
        val url = "${baseUrl}RegistrarCoordenadasV2"
        
        Log.d(TAG, "🌍 [URL_AMBIENTE] BaseUrl obtenida: $baseUrl")
        Log.d(TAG, "🌍 [URL_AMBIENTE] URL completa: $url")
        
        // Cliente con timeout reducido para no acumular delays
        val client = OkHttpClient.Builder()
            .connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
            .writeTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
            .build()

        val isoDate = DateTimeFormatter.ISO_INSTANT.format(Instant.now())
        val appState = isAppActive(context)
        val notify = if (areNotificationsEnabled(context)) "ON" else "OFF"
        val gpsStatus = if (isGPSEnabled(context)) "ON" else "OFF ($providerUsed)"

        // 🔧 Convertir movil y escenario a Int, usando 0 si están vacíos/null
        val movilInt = movil.toIntOrNull() ?: 0
        val escenarioInt = escenario.toIntOrNull() ?: 0

        val jsonBody = """
            {
                "token": "IcA.FwL.1710.!",
                "movil": $movilInt,
                "Latitud": "$lat",
                "longitud": "$lon",
                "utmX": "$utmX",
                "utmY": "$utmY",
                "DeviceId": "$deviceId",
                "FechaHora": "$isoDate",
                "DistanciaRecorrida": $totalDistance,
                "Velocidad": $speed,
                "escenarioid": $escenarioInt,
                "usuario": "$usuario",
                "INAux1": "$movilInt",
                "INAux2": "Estado: $appState | Mov: $movementType | Notif: $notify | Permisos: ${getLocationPermissionsStatusShort(context)} | GPS: $gpsStatus | Retry: $retryCount | Reset: ${if (lastResetReason.isNotEmpty() && lastResetReason != "No") "Si" else "No"}",
                "NroSesion": ""
            }
        """.trimIndent()

        // 🍪 Generar o recuperar GX_CLIENT_ID persistente para GeneXus
        val gxClientId = getOrCreateGxClientId(context)

        val request = Request.Builder()
            .url(url)
            .addHeader("accept", "application/json")
            .addHeader("Content-Type", "application/json")
            .addHeader("Cookie", "GX_CLIENT_ID=$gxClientId")
            .post(jsonBody.toRequestBody("application/json".toMediaType()))
            .build()

        // 🆕 LOG REMOTO: Capturar payload completo del API request
        DebugLogger.i(TAG, "API Request preparado", mapOf(
            "url" to url,
            "movil" to movil,
            "lat" to lat,
            "lon" to lon,
            "utmX" to utmX,
            "utmY" to utmY,
            "deviceId" to deviceId,
            "timestamp" to isoDate,
            "distance" to totalDistance,
            "speed" to speed,
            "escenario" to escenario,
            "usuario" to usuario,
            "appState" to appState,
            "movementType" to movementType,
            "provider" to providerUsed,
            "retryAttempt" to (retryCount + 1),
            "maxRetries" to maxRetries
        ))

        // 🆕 VERIFICAR LÍMITE DE REQUESTS PENDIENTES
        val currentPending = pendingRequests.get()
        if (currentPending >= 5) {
            Log.w(TAG, "⚠️ LÍMITE DE REQUESTS: Ya hay $currentPending requests pendientes, descartando este request")
            return
        }
        
        pendingRequests.incrementAndGet()
        Log.d(TAG, "🌐 Request (intento ${retryCount + 1}/$maxRetries): URL=$url [Pendientes: ${pendingRequests.get()}]")
        Log.d(TAG, "📤 Body: $jsonBody")

        try {
            // 🆕 USAR THREAD POOL EN LUGAR DE Thread {} para limitar concurrencia
            apiExecutor.execute {
                try {
                    var success = false
                    var currentAttempt = retryCount
                    
                    // Bucle de reintentos DENTRO del mismo thread
                    while (currentAttempt < maxRetries && !success) {
                    try {
                        val startTime = System.currentTimeMillis()
                        
                        client.newCall(request).execute().use { response ->
                            val elapsedTime = System.currentTimeMillis() - startTime
                            
                            if (response.isSuccessful) {
                                val responseBody = response.body?.string()
                                Log.i(TAG, "✅ API exitosa (intento ${currentAttempt + 1}, ${elapsedTime}ms): $responseBody")
                                DebugLogger.i(TAG, "API call exitosa", mapOf(
                                    "movil" to movil,
                                    "attempt" to (currentAttempt + 1),
                                    "elapsedMs" to elapsedTime,
                                    "provider" to providerUsed,
                                    "movementType" to movementType,
                                    "distance" to totalDistance,
                                    "speed" to speed,
                                    "httpCode" to response.code,
                                    "responseBody" to (responseBody ?: "empty")
                                ))
                                
                                // Registrar métrica de ubicación enviada
                                LocationLogger.logLocationMetric(context, lat, lon, providerUsed, 0f, speed)
                                
                                // Procesar respuesta del servidor
                                processServerResponse(context, responseBody, movil, escenario, usuario, deviceId)
                                
                                // Resetear contador de errores al tener éxito
                                resetErrorCount(context)
                                
                                success = true // Marcar como exitoso para salir del bucle
                                
                            } else {
                                // 🆕 CRITICAL: Leer response body TAMBIÉN en errores para debugging
                                val errorBody = response.body?.string() ?: "empty"
                                val errorMsg = "Error HTTP ${response.code}: ${response.message}"
                                Log.e(TAG, "❌ $errorMsg (intento ${currentAttempt + 1})")
                                Log.e(TAG, "📄 Response body: $errorBody")
                                
                                // 🆕 Usar DebugLogger para debug detallado (solo si debugMode=true)
                                DebugLogger.w(TAG, "API call fallida", mapOf(
                                    "movil" to movil,
                                    "httpCode" to response.code,
                                    "httpMessage" to response.message,
                                    "attempt" to (currentAttempt + 1),
                                    "responseBody" to errorBody,
                                    "requestPayload" to jsonBody
                                ))
                                
                                // 🆕 Usar CriticalLogger para errores SIEMPRE visibles (independiente de debugMode)
                                com.riogas.appmovil.CriticalLogger.logCritical(
                                    TAG,
                                    "ERROR API: No se pudo enviar coordenadas al servidor",
                                    mapOf(
                                        "movil" to movil,
                                        "httpCode" to response.code,
                                        "httpMessage" to response.message,
                                        "attempt" to (currentAttempt + 1),
                                        "maxRetries" to maxRetries,
                                        "responseBody" to errorBody.take(200), // Limitar tamaño
                                        "lat" to lat,
                                        "lon" to lon
                                    ),
                                    "API_ERROR"
                                )
                                
                                // Registrar error con código HTTP para tracking
                                LocationLogger.logError(context, "HTTP_ERROR", errorMsg)
                                incrementErrorCount(context, response.code)
                                
                                // 🔧 DECISIÓN DE RETRY: Solo reintentar errores 5xx (servidor) o timeouts
                                // HTTP 4xx (400-499) = Error de cliente (JSON mal formado, etc.) → NO REINTENTAR
                                val shouldRetry = response.code >= 500 // Solo errores de servidor (5xx)
                                
                                if (shouldRetry && currentAttempt < maxRetries - 1) {
                                    // Retry sin Thread.sleep (maxRetries=1 lo deja inalcanzable; la cola Room reintenta).
                                    currentAttempt++
                                } else {
                                    if (!shouldRetry) {
                                        Log.e(TAG, "❌ Error ${response.code} (cliente) - NO se reintenta, registro PERDIDO")
                                        LocationLogger.logError(context, "CLIENT_ERROR_NO_RETRY", "HTTP ${response.code} - Client error, no retry")
                                    } else {
                                        Log.e(TAG, "💥 Máximo de reintentos alcanzado (${maxRetries} intentos)")
                                        LocationLogger.logError(context, "MAX_RETRIES_REACHED", "Failed after $maxRetries attempts")
                                    }
                                    
                                    // 🆕 Log en DebugLogger (solo si debugMode=true)
                                    DebugLogger.e(TAG, if (!shouldRetry) "Error de cliente - No se reintenta" else "Máximo de reintentos alcanzado", null, mapOf(
                                        "movil" to movil,
                                        "httpCode" to response.code,
                                        "shouldRetry" to shouldRetry,
                                        "maxRetries" to maxRetries
                                    ))
                                    
                                    // 🆕 Log CRÍTICO (SIEMPRE visible, independiente de debugMode)
                                    com.riogas.appmovil.CriticalLogger.logCritical(
                                        TAG,
                                        if (!shouldRetry) "ERROR: HTTP ${response.code} (cliente) - Registro descartado permanentemente" 
                                        else "ERROR CRÍTICO: Máximo de reintentos alcanzado - Coordenadas NO enviadas",
                                        mapOf(
                                            "movil" to movil,
                                            "maxRetries" to maxRetries,
                                            "lastHttpCode" to response.code,
                                            "shouldRetry" to shouldRetry,
                                            "lat" to lat,
                                            "lon" to lon
                                        ),
                                        if (!shouldRetry) "API_CLIENT_ERROR" else "API_MAX_RETRIES"
                                    )
                                    
                                    // Salir del bucle (forzar a alcanzar maxRetries)
                                    currentAttempt = maxRetries
                                }
                            }
                        }
                    } catch (e: Exception) {
                        val errorMsg = "Error de conexión: ${e.message}"
                        Log.e(TAG, "❌ $errorMsg (intento ${currentAttempt + 1})")
                        
                        // 🆕 Log en DebugLogger (solo si debugMode=true)
                        DebugLogger.e(TAG, "Error de conexión al API", e, mapOf(
                            "movil" to movil,
                            "attempt" to (currentAttempt + 1)
                        ))
                        
                        // 🆕 Log CRÍTICO (SIEMPRE visible, independiente de debugMode)
                        com.riogas.appmovil.CriticalLogger.logCritical(
                            TAG,
                            "ERROR CRÍTICO: Error de conexión al API - Sin internet o timeout",
                            e,
                            mapOf(
                                "movil" to movil,
                                "attempt" to (currentAttempt + 1),
                                "maxRetries" to maxRetries,
                                "lat" to lat,
                                "lon" to lon
                            ),
                            "API_CONNECTION_ERROR"
                        )
                        
                        // Registrar error (sin código HTTP porque es error de conexión)
                        LocationLogger.logError(context, "CONNECTION_ERROR", errorMsg)
                        incrementErrorCount(context, 0)
                        
                        // Reintentar si no hemos alcanzado el máximo
                        if (currentAttempt < maxRetries - 1) {
                            // Retry sin Thread.sleep (ver arriba).
                            currentAttempt++
                        } else {
                            Log.e(TAG, "💥 Máximo de reintentos alcanzado (${maxRetries} intentos)")
                            LocationLogger.logError(context, "MAX_CONNECTION_RETRIES", "Connection failed after $maxRetries attempts")
                        }
                    }
                }
                
                    if (!success) {
                        Log.w(TAG, "📍 Coordenada PERDIDA (lat=$lat, lon=$lon) después de $maxRetries intentos")
                    }
                } finally {
                    // 🆕 SIEMPRE DECREMENTAR EL CONTADOR AL FINALIZAR
                    pendingRequests.decrementAndGet()
                    Log.d(TAG, "✅ Request finalizado [Pendientes restantes: ${pendingRequests.get()}]")
                }
            }
            
        } catch (e: Exception) {
            pendingRequests.decrementAndGet() // Decrementar también en caso de error
            Log.e(TAG, "❌ Error en thread pool: ${e.message}", e)
            LocationLogger.logError(context, "THREAD_ERROR", "Error en thread pool: ${e.message}")
        }
    }
    
    /**
     * Procesa la respuesta del servidor y verifica comandos de control
     */
    private fun processServerResponse(context: Context, responseBody: String?, movil: String, escenario: String, usuario: String, deviceId: String) {
        try {
            if (responseBody.isNullOrEmpty()) {
                Log.w(TAG, "⚠️ Respuesta del servidor vacía")
                return
            }
            
            val jsonResponse = org.json.JSONObject(responseBody)
            Log.d(TAG, "📨 Procesando respuesta del servidor: $jsonResponse")
            
            // Verificar comando de parada del servicio
            val shouldStop = jsonResponse.optBoolean("stopService", false)
            val stopReason = jsonResponse.optString("stopReason", "Server command")
            val okValue = jsonResponse.optInt("OK", -1)
            
            // También verificar el valor "OK" = 1 (lógica existente)
            if (okValue == 1 || shouldStop) {
                val finalReason = if (okValue == 1) "Server response OK=1" else stopReason
                Log.w(TAG, "🛑 Servidor solicita detener servicio: $finalReason")
                
                // 🆕 REGISTRAR LOG CRÍTICO para enviar a n8n (ANTES de detener servicios)
                com.riogas.appmovil.CriticalLogger.logCritical(
                    TAG,
                    "SERVICIO DETENIDO POR COMANDO DEL SERVIDOR",
                    mapOf(
                        "reason" to finalReason,
                        "okValue" to okValue,
                        "shouldStop" to shouldStop,
                        "movil" to movil,
                        "usuario" to usuario,
                        "deviceId" to deviceId,
                        "timestamp" to System.currentTimeMillis()
                    ),
                    "SERVER_STOP_COMMAND"
                )
                
                // Resetear distancia diaria por comando del servicio
                resetDailyDistanceByService(context, finalReason)
                
                // Registrar evento de parada
                LocationLogger.logEvent(context, "SERVER_STOP_COMMAND", mapOf(
                    "reason" to finalReason,
                    "okValue" to okValue.toString(),
                    "shouldStop" to shouldStop.toString(),
                    "movil" to movil,
                    "distanceReset" to "true"
                ))
                
                // 🆕 INTENTAR ENVIAR LOGS CRÍTICOS ANTES DE DETENER (si debugMode=true)
                sendCriticalLogsBeforeShutdown(context)
                
                // Detener la subida periódica de logs críticos (WorkManager)
                Log.i(TAG, "🛑 Cancelando CriticalLogUploadWorker por comando del servidor...")
                com.riogas.appmovil.CriticalLogUploadWorker.cancel(context)
                
                // Detener servicio GPS usando el controlador centralizado
                LocationServiceController.stopLocationServiceFromBackground(
                    context, movil, escenario, usuario, deviceId, finalReason
                )
            } else {
                // Respuesta normal, registrar éxito
                LocationLogger.logEvent(context, "COORDINATES_SENT", mapOf(
                    "movil" to movil,
                    "response" to responseBody.take(200) // Limitar tamaño del log
                ))
                
                // Limpiar razón de reset después del envío exitoso
                lastResetReason = ""
            }
            
            // Verificar otros comandos del servidor (extensible)
            processAdditionalServerCommands(context, jsonResponse, movil, escenario, usuario, deviceId)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error procesando respuesta del servidor", e)
            LocationLogger.logError(context, "RESPONSE_PROCESSING_ERROR", e.message ?: "Unknown error", e.stackTraceToString())
        }
    }
    
    /**
     * 🆕 Envía logs críticos inmediatamente antes de detener los servicios
     * Se ejecuta de forma SÍNCRONA (bloqueante) para asegurar que se envíen antes del shutdown
     */
    private fun sendCriticalLogsBeforeShutdown(context: Context) {
        try {
            val logCount = com.riogas.appmovil.CriticalLogger.getLogCount()
            
            if (logCount == 0) {
                Log.d(TAG, "ℹ️ [SHUTDOWN] No hay logs críticos pendientes")
                return
            }
            
            // Verificar debugMode
            val debugMode = com.riogas.appmovil.DebugLogger.isEnabled()
            
            if (!debugMode) {
                Log.w(TAG, "⚠️ [SHUTDOWN] debugMode=false, logs NO se enviarán ($logCount logs se perderán)")
                // Limpiar logs para evitar acumulación
                com.riogas.appmovil.CriticalLogger.clearLogs()
                return
            }
            
            Log.i(TAG, "📤 [SHUTDOWN] Enviando $logCount logs críticos ANTES de detener servicios...")
            
            // Obtener JSON de logs
            val logsJson = com.riogas.appmovil.CriticalLogger.getLogsAsJson()
            
            // Cliente HTTP con timeout corto (máximo 5 segundos)
            val client = OkHttpClient.Builder()
                .connectTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
                .writeTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
                .readTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
                .build()
            
            val request = Request.Builder()
                .url("https://n8n.riogas.com.uy/webhook/debug-delivery")
                .addHeader("Content-Type", "application/json")
                .post(logsJson.toRequestBody("application/json".toMediaType()))
                .build()
            
            val startTime = System.currentTimeMillis()
            
            // EJECUTAR DE FORMA SÍNCRONA (bloqueante)
            client.newCall(request).execute().use { response ->
                val elapsedTime = System.currentTimeMillis() - startTime
                
                if (response.isSuccessful) {
                    val responseBody = response.body?.string() ?: "empty"
                    Log.i(TAG, "✅ [SHUTDOWN] Logs enviados exitosamente (${elapsedTime}ms)")
                    Log.d(TAG, "   - HTTP Code: ${response.code}")
                    Log.d(TAG, "   - Response: $responseBody")
                    
                    // Limpiar logs después de envío exitoso
                    com.riogas.appmovil.CriticalLogger.clearLogs()
                    Log.d(TAG, "🧹 [SHUTDOWN] Buffer de logs limpiado")
                    
                } else {
                    val errorBody = response.body?.string() ?: "empty"
                    Log.w(TAG, "⚠️ [SHUTDOWN] Error enviando logs: HTTP ${response.code} (${elapsedTime}ms)")
                    Log.w(TAG, "   - Message: ${response.message}")
                    Log.w(TAG, "   - Response: $errorBody")
                    
                    // NO limpiar logs si falló el envío (pero se perderán al detener el servicio)
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ [SHUTDOWN] Error enviando logs críticos: ${e.message}", e)
            // Continuar con el shutdown aunque falle el envío
        }
    }
    
    /**
     * Procesa comandos adicionales del servidor (extensible)
     */
    private fun processAdditionalServerCommands(context: Context, jsonResponse: org.json.JSONObject, movil: String, escenario: String, usuario: String, deviceId: String) {
        try {
            // Comando para cambiar intervalo de ubicación
            if (jsonResponse.has("newInterval")) {
                val newInterval = jsonResponse.getDouble("newInterval")
                if (newInterval > 0) {
                    Log.i(TAG, "📡 Servidor solicita cambio de intervalo: ${newInterval}min")
                    updateLocationInterval(context, newInterval, movil, escenario, usuario, deviceId)
                }
            }
            
            // Comando para pausar temporalmente
            if (jsonResponse.has("pauseMinutes")) {
                val pauseMinutes = jsonResponse.getInt("pauseMinutes")
                if (pauseMinutes > 0) {
                    Log.i(TAG, "⏸️ Servidor solicita pausa temporal: ${pauseMinutes}min")
                    pauseLocationServiceTemporarily(context, pauseMinutes)
                }
            }
            
            // Comando para configuración de batería
            if (jsonResponse.has("batteryOptimized")) {
                val batteryOptimized = jsonResponse.getBoolean("batteryOptimized")
                Log.i(TAG, "🔋 Servidor configura optimización de batería: $batteryOptimized")
                setBatteryOptimizationMode(context, batteryOptimized)
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error procesando comandos adicionales del servidor", e)
            LocationLogger.logError(context, "ADDITIONAL_COMMANDS_ERROR", e.message ?: "Unknown error")
        }
    }

    // 🆕 Función pública para convertir coordenadas geográficas a UTM
    // Necesaria para que FcmPushReceiver pueda enviar coordenadas forzadas
    fun convertToUTM(lat: Double, lon: Double): Pair<Double, Double> {
        val crsFactory = CRSFactory()
        val transformFactory = CoordinateTransformFactory()
        val srcCRS = crsFactory.createFromName("EPSG:4326")
        val dstCRS = crsFactory.createFromParameters("UTM21S", "+proj=utm +zone=21 +south +datum=WGS84 +units=m +no_defs")
        val transform = transformFactory.createTransform(srcCRS, dstCRS)
        val src = ProjCoordinate(lon, lat)
        val dst = ProjCoordinate()
        transform.transform(src, dst)
        return Pair(dst.x, dst.y)
    }

    /**
     * Incrementa el contador de errores y mantiene historial de códigos HTTP
     * @param httpCode Código HTTP del error (0 si es error de conexión)
     */
    private fun incrementErrorCount(context: Context, httpCode: Int = 0) {
        try {
            val prefs = context.getSharedPreferences("location_errors", Context.MODE_PRIVATE)
            val currentCount = prefs.getInt("error_count", 0)
            
            // 🆕 Mantener historial de últimos 5 códigos de error
            val last5Errors = prefs.getString("last_5_errors", "")?.split(",")?.toMutableList() ?: mutableListOf()
            if (httpCode > 0) {
                last5Errors.add(httpCode.toString())
                if (last5Errors.size > 5) {
                    last5Errors.removeAt(0) // Eliminar el más antiguo
                }
            }
            
            prefs.edit().apply {
                putInt("error_count", currentCount + 1)
                putLong("last_error_time", System.currentTimeMillis())
                putString("last_5_errors", last5Errors.joinToString(","))
            }.apply()
            
            // Si hay demasiados errores, considerar pausar temporalmente
            if (currentCount + 1 > 5) {
                Log.w(TAG, "🚫 Demasiados errores consecutivos (${currentCount + 1}), considerando pausa temporal")
                LocationLogger.logEvent(context, "HIGH_ERROR_COUNT", mapOf(
                    "errorCount" to (currentCount + 1).toString(),
                    "last5Errors" to last5Errors.joinToString(",")
                ))
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error incrementando contador de errores", e)
        }
    }
    
    /**
     * Resetea el contador de errores y registra timestamp de éxito
     */
    private fun resetErrorCount(context: Context) {
        try {
            val prefs = context.getSharedPreferences("location_errors", Context.MODE_PRIVATE)
            prefs.edit().apply {
                putInt("error_count", 0)
                remove("last_error_time")
                remove("last_5_errors") // Limpiar historial de errores
                putLong("last_success_time", System.currentTimeMillis()) // Registrar éxito
            }.apply()
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error reseteando contador de errores", e)
        }
    }
    
    /**
     * Actualiza el intervalo de ubicación (comando del servidor)
     */
    private fun updateLocationInterval(context: Context, newInterval: Double, movil: String, escenario: String, usuario: String, deviceId: String) {
        try {
            // El tracking continuo (LocationTrackingService) lee el intervalo desde prefs.
            // Sin AlarmManager: solo persistimos el nuevo valor en segundos.
            val intervalSeconds = (newInterval * 60).toInt().coerceAtLeast(1)
            context.getSharedPreferences("config", Context.MODE_PRIVATE)
                .edit().putInt("tracking_interval_seconds", intervalSeconds).apply()

            LocationLogger.logEvent(context, "INTERVAL_UPDATED", mapOf(
                "newInterval" to newInterval.toString(),
                "intervalSeconds" to intervalSeconds.toString(),
                "movil" to movil
            ))
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error actualizando intervalo", e)
            LocationLogger.logError(context, "UPDATE_INTERVAL_ERROR", e.message ?: "Unknown error")
        }
    }
    
    /**
     * Pausa el servicio temporalmente
     */
    private fun pauseLocationServiceTemporarily(context: Context, pauseMinutes: Int) {
        try {
            val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            val resumeTime = System.currentTimeMillis() + (pauseMinutes * 60 * 1000)

            ServiceStatusFlags.setServicePaused(context, true, "pauseLocationServiceTemporarily ${pauseMinutes}min")
            prefs.edit().apply {
                putLong("resume_time", resumeTime)
                putInt("pause_minutes", pauseMinutes)
            }.apply()
            
            LocationLogger.logEvent(context, "SERVICE_PAUSED", mapOf(
                "pauseMinutes" to pauseMinutes.toString(),
                "resumeTime" to resumeTime.toString()
            ))
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error pausando servicio", e)
            LocationLogger.logError(context, "PAUSE_SERVICE_ERROR", e.message ?: "Unknown error")
        }
    }
    
    /**
     * Configura el modo de optimización de batería
     */
    private fun setBatteryOptimizationMode(context: Context, enabled: Boolean) {
        try {
            val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("battery_optimized", enabled).apply()
            
            LocationLogger.logEvent(context, "BATTERY_OPTIMIZATION_SET", mapOf(
                "enabled" to enabled.toString()
            ))
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error configurando optimización de batería", e)
            LocationLogger.logError(context, "BATTERY_OPTIMIZATION_ERROR", e.message ?: "Unknown error")
        }
    }

    /**
     * FILTRADO SIMPLIFICADO SIN VALIDACIONES DE ACCURACY NI VELOCIDAD
     * 
     * ESTRATEGIA SIMPLE:
     * - Se suma SIEMPRE la distancia calculada entre coordenadas
     * - NO se valida accuracy (precisión GPS)
     * - NO se valida velocidad máxima
     * - SOLO se retorna la distancia cruda para clasificación posterior
     */
    private fun filterGPSNoise(rawDistance: Float, currentLocation: Location, lastLocation: Location, speed: Float): Float {
        try {
            val currentAccuracy = if (currentLocation.hasAccuracy()) currentLocation.accuracy else 999f
            
            // 🆕 LOG SIMPLIFICADO - Solo informativo
            Log.i(TAG, "� [DISTANCE] Distancia calculada: ${rawDistance}m | Accuracy: ${currentAccuracy}m | Speed: ${speed}m/s")
            
            // ✅ RETORNAR SIEMPRE LA DISTANCIA CRUDA - Sin filtros
            return rawDistance
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error calculando distancia", e)
            return if (rawDistance < 100f) rawDistance else 0f
        }
    }

    fun isAppActive(context: Context): String {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        val appProcesses = activityManager.runningAppProcesses
        val packageName = context.packageName

        appProcesses?.forEach { process ->
            if (process.processName == packageName) {
                return when (process.importance) {
                    android.app.ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND -> "active"
                    android.app.ActivityManager.RunningAppProcessInfo.IMPORTANCE_BACKGROUND -> "background"
                    else -> "inactive"
                }
            }
        }
        return "inactive"
    }

    /**
     * Obtiene el estado detallado de los permisos de ubicación
     */
    private fun getLocationPermissionsStatus(context: Context): String {
        try {
            val fineLocation = ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_FINE_LOCATION)
            val coarseLocation = ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_COARSE_LOCATION)
            val backgroundLocation = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_BACKGROUND_LOCATION)
            } else {
                PackageManager.PERMISSION_GRANTED // No necesario en versiones anteriores
            }
            
            val permissions = mutableListOf<String>()
            
            // Verificar permisos individuales
            if (fineLocation == PackageManager.PERMISSION_GRANTED) {
                permissions.add("FINE")
            }
            if (coarseLocation == PackageManager.PERMISSION_GRANTED) {
                permissions.add("COARSE")
            }
            if (backgroundLocation == PackageManager.PERMISSION_GRANTED) {
                permissions.add("BACK")
            }
            
            // Si no tiene ningún permiso
            if (permissions.isEmpty()) {
                return "DENIED"
            }
            
            // Estado ideal: FINE + BACKGROUND
            val hasIdealPermissions = fineLocation == PackageManager.PERMISSION_GRANTED && 
                                    backgroundLocation == PackageManager.PERMISSION_GRANTED
            
            return if (hasIdealPermissions) {
                "FULL(${permissions.joinToString("+")})"
            } else {
                "PARTIAL(${permissions.joinToString("+")})"
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error verificando permisos", e)
            return "ERROR"
        }
    }

    /**
     * Obtiene el estado simplificado de los permisos de ubicación (solo FULL/PARTIAL)
     */
    private fun getLocationPermissionsStatusShort(context: Context): String {
        try {
            val fineLocation = ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_FINE_LOCATION)
            val backgroundLocation = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_BACKGROUND_LOCATION)
            } else {
                PackageManager.PERMISSION_GRANTED // No necesario en versiones anteriores
            }
            
            // Estado ideal: FINE + BACKGROUND
            val hasIdealPermissions = fineLocation == PackageManager.PERMISSION_GRANTED && 
                                    backgroundLocation == PackageManager.PERMISSION_GRANTED
            
            return if (hasIdealPermissions) {
                "FULL"
            } else {
                "PARTIAL"
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error verificando permisos", e)
            return "ERROR"
        }
    }
    
    /**
     * Loguea un snapshot completo del estado del sistema (permisos, batería, GPS)
     * Llamado automáticamente después de cada upload de logs para tener contexto fresco
     */
    fun logSystemSnapshot(context: Context) {
        try {
            val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
            val movil = prefs.getString("last_movil", "0") ?: "0"
            
            // Verificar permisos
            val hasFine = ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            val hasCoarse = ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
            val hasBackground = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
            } else {
                true
            }
            
            // Verificar estado de batería
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val isBatterySaverOn = pm?.isPowerSaveMode ?: false
            val isIgnoringBatteryOptimizations = pm?.isIgnoringBatteryOptimizations(context.packageName) ?: false
            val isDeviceIdle = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                pm?.isDeviceIdleMode ?: false
            } else {
                false
            }
            
            // Verificar GPS
            val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            val isGPSEnabled = locationManager?.isProviderEnabled(LocationManager.GPS_PROVIDER) ?: false
            val isNetworkEnabled = locationManager?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ?: false
            
            // Determinar estado de la app
            val appState = if (isAppActive(context) == "active") "FOREGROUND" else "BACKGROUND"
            
            // Logear snapshot completo
            com.riogas.appmovil.DebugLogger.i(TAG, "📸 Snapshot del sistema", mapOf<String, Any>(
                "movil" to movil,
                "permission_fine" to hasFine,
                "permission_coarse" to hasCoarse,
                "permission_background" to hasBackground,
                "battery_saver_on" to isBatterySaverOn,
                "battery_optimization_ignored" to isIgnoringBatteryOptimizations,
                "doze_mode_active" to isDeviceIdle,
                "gps_enabled" to isGPSEnabled,
                "network_enabled" to isNetworkEnabled,
                "android_version" to Build.VERSION.SDK_INT,
                "app_state" to appState,
                "device_model" to "${Build.MANUFACTURER} ${Build.MODEL}"
            ))
            
            Log.d(TAG, "📸 System snapshot logged for debugging")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error logging system snapshot: ${e.message}", e)
        }
    }
    
    // ============================================================================
    // 🆕 TRACK RIOGAS - ENVÍO DE DATOS EXTENDIDOS CADA 30 SEGUNDOS
    // ============================================================================
    
    /**
     * Envía datos extendidos a track.riogas.com.uy
     * ✅ UN SOLO INTENTO - Sin reintentos, sin CriticalLogger
     * ✅ TODOS los datos estructurados (no en INAux2)
     */
    fun sendToN8nWebhook(
        context: Context,
        location: Location,
        lat: Double,
        lon: Double,
        utmX: Double,
        utmY: Double,
        totalDistance: Float,
        speed: Float,
        movil: String,
        escenario: String,
        usuario: String,
        deviceId: String,
        providerUsed: String,
        movementType: String,
        executionCounter: Int
    ) {
        val url = "https://track.riogas.com.uy/api/import/gps"
        
        // 🆕 VERIFICAR gpsN8nEnabled: Solo enviar si gpsN8nEnabled = true
        val prefs = context.getSharedPreferences("config", android.content.Context.MODE_PRIVATE)
        val gpsN8nEnabled = prefs.getBoolean("gpsN8nEnabled", false)
        
        if (!gpsN8nEnabled) {
            Log.d(TAG, "🔇 [TRACK-OFF] gpsN8nEnabled=false → NO enviando datos GPS a track.riogas")
            DebugLogger.i(TAG, "Track Riogas GPS webhook omitido por gpsN8nEnabled=false", mapOf(
                "movil" to movil,
                "executionCounter" to executionCounter,
                "reason" to "gpsN8nEnabled=false"
            ))
            return // NO enviar
        }
        
        Log.d(TAG, "🌐 [TRACK-ON] gpsN8nEnabled=true → Enviando datos GPS a track.riogas")
        
        try {
            // Cliente HTTP básico sin timeouts largos
            val client = OkHttpClient.Builder()
                .connectTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
                .writeTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
                .readTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
                .build()
            
            val isoDate = DateTimeFormatter.ISO_INSTANT.format(Instant.now())
            val appState = isAppActive(context)
            
            // 🔥 OBTENER TODOS LOS DATOS EXTENDIDOS
            val batteryInfo = getBatteryInfo(context)
            val networkInfo = getNetworkInfo(context)
            val locationPermissions = getAllLocationPermissions(context)
            val deviceInfo = getDeviceInfo()
            val powerInfo = getPowerManagementInfo(context)
            val memoryInfo = getMemoryInfo(context)
            
            // 🔥 CONSTRUIR PAYLOAD ESTRUCTURADO (todos los campos separados)
            val payload = mapOf(
                // Datos básicos de ubicación
                "token" to "IcA.FwL.1710.!",
                "movil" to movil,
                "latitud" to lat,
                "longitud" to lon,
                "utmX" to utmX,
                "utmY" to utmY,
                "deviceId" to deviceId,
                "fechaHora" to isoDate,
                "distanciaRecorrida" to totalDistance,
                "velocidad" to speed,
                "escenarioid" to escenario,
                "usuario" to usuario,
                
                // Estado de la app
                "appState" to appState,
                "movementType" to movementType,
                
                // GPS/Location info
                "accuracy" to location.accuracy,
                "altitude" to if (location.hasAltitude()) location.altitude else null,
                "bearing" to if (location.hasBearing()) location.bearing else null,
                "provider" to providerUsed,
                "speed_accuracy" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && location.hasSpeedAccuracy()) {
                    location.speedAccuracyMetersPerSecond
                } else null,
                "is_mock_location" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    location.isMock
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
                    @Suppress("DEPRECATION")
                    location.isFromMockProvider
                } else false,
                "location_age_ms" to (System.currentTimeMillis() - location.time),
                "gps_enabled" to isGPSEnabled(context),
                "satellites_used" to lastUsedSatellites,
                "satellites_total" to lastSatelliteCount,
                "satellites_avg_snr" to lastAvgSnr,
                
                // Permisos de ubicación
                "permission_fine_location" to locationPermissions["permission_fine_location"],
                "permission_coarse_location" to locationPermissions["permission_coarse_location"],
                "permission_background_location" to locationPermissions["permission_background_location"],
                "notifications_enabled" to areNotificationsEnabled(context),
                
                // Batería
                "battery_level" to batteryInfo["battery_level"],
                "battery_charging" to batteryInfo["battery_charging"],
                "battery_status" to batteryInfo["battery_status"],
                "battery_saver_on" to powerInfo["battery_saver_on"],
                "battery_optimization_ignored" to powerInfo["battery_optimization_ignored"],
                "doze_mode_active" to powerInfo["doze_mode_active"],
                
                // Red
                "network_type" to networkInfo["network_type"],
                "network_connected" to networkInfo["network_connected"],
                
                // Dispositivo
                "device_manufacturer" to deviceInfo["device_manufacturer"],
                "device_model" to deviceInfo["device_model"],
                "device_brand" to deviceInfo["device_brand"],
                "android_version" to deviceInfo["android_version"],
                "android_release" to deviceInfo["android_release"],
                
                // Memoria
                "memory_available_mb" to memoryInfo["memory_available_mb"],
                "memory_total_mb" to memoryInfo["memory_total_mb"],
                "memory_low" to memoryInfo["memory_low"],
                
                // Control
                "execution_counter" to executionCounter,
                "last_reset_reason" to lastResetReason,
                "app_version" to try {
                    val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
                    packageInfo.versionName
                } catch (e: Exception) {
                    "unknown"
                },
                
                // Timestamps
                "timestamp_local" to java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssZ", java.util.Locale.getDefault()).format(java.util.Date()),
                "timestamp_utc" to isoDate
            )
            
            // Convertir a JSON
            val jsonPayload = org.json.JSONObject(payload).toString()
            
            Log.d(TAG, "📤 [TRACK] Enviando datos extendidos a track.riogas")
            Log.d(TAG, "📤 [TRACK] URL: $url")
            Log.v(TAG, "📤 [TRACK] Payload: ${jsonPayload.take(500)}...") // Primeros 500 chars para no saturar log
            
            val request = Request.Builder()
                .url(url)
                .addHeader("Content-Type", "application/json")
                .post(jsonPayload.toRequestBody("application/json".toMediaType()))
                .build()
            
            // 🔥 EJECUTAR EN THREAD SEPARADO (no bloquear)
            Thread {
                try {
                    val startTime = System.currentTimeMillis()
                    client.newCall(request).execute().use { response ->
                        val elapsedTime = System.currentTimeMillis() - startTime
                        
                        if (response.isSuccessful) {
                            val responseBody = response.body?.string()
                            Log.i(TAG, "✅ [TRACK] Datos enviados exitosamente a track.riogas (${elapsedTime}ms)")
                            Log.d(TAG, "✅ [TRACK] Response: $responseBody")
                        } else {
                            val errorBody = response.body?.string() ?: "empty"
                            Log.w(TAG, "⚠️ [TRACK] Error HTTP ${response.code}: ${response.message} (${elapsedTime}ms)")
                            Log.w(TAG, "⚠️ [TRACK] Response body: $errorBody")
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ [TRACK] Error enviando a track.riogas: ${e.message}")
                }
            }.start()
            
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ [TRACK] Error preparando request a track.riogas: ${e.message}")
        }
    }
    
    // ============================================================================
    // 🆕 MÉTODOS HELPER PARA OBTENER DATOS EXTENDIDOS DEL DISPOSITIVO
    // ============================================================================
    
    /**
     * Obtiene información completa de batería
     */
    private fun getBatteryInfo(context: Context): Map<String, Any> {
        return try {
            val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
            val batteryLevel = batteryManager.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
            val batteryStatus = context.registerReceiver(null, android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))
            val status = batteryStatus?.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1) ?: -1
            val isCharging = status == android.os.BatteryManager.BATTERY_STATUS_CHARGING || 
                            status == android.os.BatteryManager.BATTERY_STATUS_FULL
            
            mapOf(
                "battery_level" to batteryLevel,
                "battery_charging" to isCharging,
                "battery_status" to when(status) {
                    android.os.BatteryManager.BATTERY_STATUS_CHARGING -> "CHARGING"
                    android.os.BatteryManager.BATTERY_STATUS_DISCHARGING -> "DISCHARGING"
                    android.os.BatteryManager.BATTERY_STATUS_FULL -> "FULL"
                    android.os.BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "NOT_CHARGING"
                    else -> "UNKNOWN"
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error obteniendo info de batería: ${e.message}")
            mapOf(
                "battery_level" to -1,
                "battery_charging" to false,
                "battery_status" to "ERROR"
            )
        }
    }
    
    /**
     * Obtiene información completa de red
     */
    private fun getNetworkInfo(context: Context): Map<String, Any> {
        return try {
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
            
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                val activeNetwork = connectivityManager.activeNetwork
                val capabilities = connectivityManager.getNetworkCapabilities(activeNetwork)
                
                val networkType = when {
                    capabilities == null -> "NONE"
                    capabilities.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) -> "WiFi"
                    capabilities.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR) -> "CELLULAR"
                    capabilities.hasTransport(android.net.NetworkCapabilities.TRANSPORT_ETHERNET) -> "ETHERNET"
                    else -> "UNKNOWN"
                }
                
                mapOf(
                    "network_type" to networkType,
                    "network_connected" to (activeNetwork != null)
                )
            } else {
                @Suppress("DEPRECATION")
                val activeNetworkInfo = connectivityManager.activeNetworkInfo
                
                mapOf(
                    "network_type" to (activeNetworkInfo?.typeName ?: "NONE"),
                    "network_connected" to (activeNetworkInfo?.isConnected ?: false)
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error obteniendo info de red: ${e.message}")
            mapOf(
                "network_type" to "ERROR",
                "network_connected" to false
            )
        }
    }
    
    /**
     * Obtiene todos los permisos de ubicación con detalle
     */
    private fun getAllLocationPermissions(context: Context): Map<String, Boolean> {
        return mapOf(
            "permission_fine_location" to (ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED),
            "permission_coarse_location" to (ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED),
            "permission_background_location" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
            } else {
                true // No se requiere en Android <10
            }
        )
    }
    
    /**
     * Obtiene información del dispositivo
     */
    private fun getDeviceInfo(): Map<String, Any> {
        return mapOf(
            "device_manufacturer" to Build.MANUFACTURER,
            "device_model" to Build.MODEL,
            "device_brand" to Build.BRAND,
            "android_version" to Build.VERSION.SDK_INT,
            "android_release" to Build.VERSION.RELEASE,
            "device_fingerprint" to Build.FINGERPRINT.take(100) // Limitar tamaño
        )
    }
    
    /**
     * Obtiene información de optimización de batería y doze mode
     */
    private fun getPowerManagementInfo(context: Context): Map<String, Any> {
        return try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            
            mapOf(
                "battery_saver_on" to powerManager.isPowerSaveMode,
                "battery_optimization_ignored" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    powerManager.isIgnoringBatteryOptimizations(context.packageName)
                } else {
                    true
                },
                "doze_mode_active" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    powerManager.isDeviceIdleMode
                } else {
                    false
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error obteniendo power management info: ${e.message}")
            mapOf(
                "battery_saver_on" to false,
                "battery_optimization_ignored" to false,
                "doze_mode_active" to false
            )
        }
    }
    
    /**
     * Obtiene información de memoria disponible
     */
    private fun getMemoryInfo(context: Context): Map<String, Any> {
        return try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            
            mapOf(
                "memory_available_mb" to (memoryInfo.availMem / 1024 / 1024),
                "memory_total_mb" to (memoryInfo.totalMem / 1024 / 1024),
                "memory_low" to memoryInfo.lowMemory
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error obteniendo memory info: ${e.message}")
            mapOf(
                "memory_available_mb" to -1,
                "memory_total_mb" to -1,
                "memory_low" to false
            )
        }
    }
}