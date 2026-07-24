    package com.example.moveit  // 👈 Asegúrate que coincida con el package del manifest

    import android.annotation.SuppressLint
    import android.app.ActivityManager
    import android.content.Context
    import android.location.Location
    import android.location.LocationManager
    import android.os.Build
    import android.os.Bundle
    import android.os.PowerManager
    import android.provider.Settings
    import android.util.Log
    import io.flutter.embedding.android.FlutterFragmentActivity
    import io.flutter.embedding.engine.FlutterEngine
    import io.flutter.plugin.common.MethodChannel
    import io.flutter.FlutterInjector
    import com.google.firebase.FirebaseApp
    import android.content.Intent
    import android.content.BroadcastReceiver
    import android.content.IntentFilter

    class MainActivity : FlutterFragmentActivity() {
        private val CHANNEL = "device_info"
        private val DEBUG_CHANNEL = "debug_config"
        private val REMOTE_LOGOUT_CHANNEL = "com.riogas.appmovil/remote_logout"
        
        private var remoteLogoutChannel: MethodChannel? = null
        private var remoteLogoutReceiver: BroadcastReceiver? = null

        override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
            Log.d("NETWORK_LOCATION", "[INIT] configureFlutterEngine ejecutado")

            // 1. Canal para device_info (Android ID)
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
                if (call.method == "getAndroidId") {
                    val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    result.success(androidId)
                } else {
                    result.notImplemented()
                }
            }

            // 2. Canal para debug_config (control remoto del logging)
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEBUG_CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "setDebugMode" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val gpsN8nEnabled = call.argument<Boolean>("gpsN8nEnabled") ?: false
                        
                        com.riogas.appmovil.DebugLogger.setEnabled(enabled)
                        Log.d("MainActivity", "Debug mode ${if (enabled) "ACTIVADO" else "DESACTIVADO"} desde Flutter")
                        
                        // 🆕 Guardar gpsN8nEnabled en SharedPreferences para uso del servicio GPS
                        val prefs = getSharedPreferences("config", android.content.Context.MODE_PRIVATE)
                        prefs.edit().putBoolean("gpsN8nEnabled", gpsN8nEnabled).apply()
                        Log.d("MainActivity", "🌐 gpsN8nEnabled guardado: $gpsN8nEnabled (envío a N8N ${if (gpsN8nEnabled) "ACTIVADO" else "DESACTIVADO"})")
                        
                        // Si se activa, programar upload periódico
                        if (enabled) {
                            scheduleDebugLogUpload()
                        } else {
                            cancelDebugLogUpload()
                        }
                        
                        result.success("Debug mode actualizado")
                    }
                    "getDebugStats" -> {
                        val stats = com.riogas.appmovil.DebugLogger.getStats()
                        result.success(stats)
                    }
                    "scheduleLogUpload" -> {
                        scheduleDebugLogUpload()
                        result.success("Upload programado")
                    }
                    "cancelLogUpload" -> {
                        cancelDebugLogUpload()
                        result.success("Upload cancelado")
                    }
                    "uploadLogsNow" -> {
                        // Enviar logs inmediatamente (forzar upload sin esperar los 10 minutos)
                        Log.d("MainActivity", "🚀 Upload manual de logs solicitado desde Flutter")
                        androidx.work.OneTimeWorkRequestBuilder<com.riogas.appmovil.DebugLogUploadWorker>()
                            .setConstraints(androidx.work.Constraints.Builder()
                                .setRequiredNetworkType(androidx.work.NetworkType.CONNECTED)
                                .build())
                            .build()
                            .also { workRequest ->
                                androidx.work.WorkManager.getInstance(this).enqueue(workRequest)
                            }
                        result.success("Logs enviándose...")
                    }
                    else -> result.notImplemented()
                }
            }

            // 🆕 Canal para instalación robusta de APK (auto-actualización desde Google Drive)
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "apk_installer").setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath == null) {
                            result.error("INVALID_PATH", "filePath es requerido", null)
                            return@setMethodCallHandler
                        }
                        
                        Log.i("MainActivity", "📦 Instalando APK desde: $filePath")
                        com.riogas.appmovil.DebugLogger.i("MainActivity", "APK Installation", mapOf(
                            "filePath" to filePath,
                            "method" to "native_installer"
                        ))
                        
                        installApkRobust(filePath, result)
                    }
                    else -> result.notImplemented()
                }
            }

            // 🆕 Canal para guardar datos en SharedPreferences nativo (para CriticalLogger)
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.riogas.appmovil/shared_prefs").setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveMovil" -> {
                        val movil = call.argument<String>("movil")
                        if (movil == null) {
                            result.error("INVALID_MOVIL", "movil es requerido", null)
                            return@setMethodCallHandler
                        }
                        
                        try {
                            // Guardar en SharedPreferences "user_data" que usa CriticalLogger
                            val userDataPrefs = getSharedPreferences("user_data", Context.MODE_PRIVATE)
                            userDataPrefs.edit().putString("movil", movil).apply()
                            
                            Log.i("MainActivity", "✅ Móvil guardado en SharedPreferences nativo para CriticalLogger: $movil")
                            result.success("✅ Móvil guardado exitosamente")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Error guardando móvil en SharedPreferences: ${e.message}", e)
                            result.error("SAVE_ERROR", "Error guardando móvil: ${e.message}", null)
                        }
                    }
                    "saveEscenario" -> {
                        val escenario = call.argument<String>("escenario")
                        if (escenario == null) {
                            result.error("INVALID_ESCENARIO", "escenario es requerido", null)
                            return@setMethodCallHandler
                        }
                        
                        try {
                            // Guardar en SharedPreferences "config" que usan los servicios nativos
                            val configPrefs = getSharedPreferences("config", Context.MODE_PRIVATE)
                            configPrefs.edit().putString("last_escenario", escenario).apply()
                            
                            Log.i("MainActivity", "✅ Escenario guardado en SharedPreferences nativo para FCM API: $escenario")
                            result.success("✅ Escenario guardado exitosamente")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Error guardando escenario en SharedPreferences: ${e.message}", e)
                            result.error("SAVE_ERROR", "Error guardando escenario: ${e.message}", null)
                        }
                    }
                    "saveBaseUrl" -> {
                        val baseUrl = call.argument<String>("baseUrl")
                        if (baseUrl == null) {
                            result.error("INVALID_BASEURL", "baseUrl es requerido", null)
                            return@setMethodCallHandler
                        }
                        
                        try {
                            // 🔹 Guardar en SharedPreferences "config" que usa FcmApiHelper
                            val configPrefs = getSharedPreferences("config", Context.MODE_PRIVATE)
                            configPrefs.edit().putString("baseUrl", baseUrl).apply()
                            
                            // 🆕 TAMBIÉN guardar en FlutterSharedPreferences para que LocationHelper pueda leerlo
                            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                            flutterPrefs.edit().putString("flutter.baseUrl", baseUrl).apply()
                            
                            Log.i("MainActivity", "✅ BaseUrl guardada en config.baseUrl: $baseUrl")
                            Log.i("MainActivity", "✅ BaseUrl guardada en flutter.baseUrl: $baseUrl")
                            result.success("✅ BaseUrl guardada exitosamente")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Error guardando baseUrl en SharedPreferences: ${e.message}", e)
                            result.error("SAVE_ERROR", "Error guardando baseUrl: ${e.message}", null)
                        }
                    }
                    "saveIsDevelopment" -> {
                        val isDevelopment = call.argument<Boolean>("isDevelopment")
                        if (isDevelopment == null) {
                            result.error("INVALID_ISDEVELOPMENT", "isDevelopment es requerido", null)
                            return@setMethodCallHandler
                        }
                        
                        try {
                            // Guardar en SharedPreferences "FlutterSharedPreferences" para que FCM pueda leerlo
                            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                            flutterPrefs.edit().putBoolean("flutter.isDevelopment", isDevelopment).apply()
                            
                            Log.i("MainActivity", "✅ isDevelopment guardado en SharedPreferences nativo: $isDevelopment")
                            result.success("✅ isDevelopment guardado exitosamente")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Error guardando isDevelopment: ${e.message}", e)
                            result.error("SAVE_ERROR", "Error guardando isDevelopment: ${e.message}", null)
                        }
                    }
                    "saveLoginDate" -> {
                        val loginDate = call.argument<String>("loginDate")
                        if (loginDate == null) {
                            result.error("INVALID_LOGIN_DATE", "loginDate es requerido", null)
                            return@setMethodCallHandler
                        }
                        
                        try {
                            // 🌅 Guardar en SharedPreferences "FlutterSharedPreferences" para day-change detection
                            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                            flutterPrefs.edit().putString("flutter.loginDate", loginDate).apply()
                            
                            Log.i("MainActivity", "✅ 🌅 loginDate guardado en SharedPreferences nativo: $loginDate")
                            result.success("✅ loginDate guardado exitosamente")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Error guardando loginDate: ${e.message}", e)
                            result.error("SAVE_ERROR", "Error guardando loginDate: ${e.message}", null)
                        }
                    }
                    "saveUsername" -> {
                        val username = call.argument<String>("username")
                        if (username == null) {
                            result.error("INVALID_USERNAME", "username es requerido", null)
                            return@setMethodCallHandler
                        }
                        
                        try {
                            // 👤 Guardar username en SharedPreferences "FlutterSharedPreferences" para que watchdog/force_gps puedan leerlo
                            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                            flutterPrefs.edit().putString("flutter.username", username).apply()
                            
                            Log.i("MainActivity", "✅ 👤 username guardado en SharedPreferences nativo: $username")
                            result.success("✅ username guardado exitosamente")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Error guardando username: ${e.message}", e)
                            result.error("SAVE_ERROR", "Error guardando username: ${e.message}", null)
                        }
                    }
                    "saveAppVersion" -> {
                        val appVersion = call.argument<String>("appVersion")
                        if (appVersion == null) {
                            result.error("INVALID_APP_VERSION", "appVersion es requerido", null)
                            return@setMethodCallHandler
                        }
                        
                        try {
                            // 📦 Guardar appVersion en SharedPreferences para RegistrarCierre
                            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                            flutterPrefs.edit().putString("flutter.appVersion", appVersion).apply()
                            
                            Log.i("MainActivity", "✅ 📦 appVersion guardado en SharedPreferences nativo: $appVersion")
                            result.success("✅ appVersion guardado exitosamente")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Error guardando appVersion: ${e.message}", e)
                            result.error("SAVE_ERROR", "Error guardando appVersion: ${e.message}", null)
                        }
                    }
                    "saveNombreUsuario" -> {
                        val nombreUsuario = call.argument<String>("nombreUsuario")
                        if (nombreUsuario == null) {
                            result.error("INVALID_NOMBRE_USUARIO", "nombreUsuario es requerido", null)
                            return@setMethodCallHandler
                        }
                        
                        try {
                            // 👤 Guardar NombreUsuario en SharedPreferences para RegistrarCierre
                            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                            flutterPrefs.edit().putString("flutter.NombreUsuario", nombreUsuario).apply()
                            
                            Log.i("MainActivity", "✅ 👤 NombreUsuario guardado en SharedPreferences nativo: $nombreUsuario")
                            result.success("✅ NombreUsuario guardado exitosamente")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Error guardando NombreUsuario: ${e.message}", e)
                            result.error("SAVE_ERROR", "Error guardando NombreUsuario: ${e.message}", null)
                        }
                    }
                    "criticalLogFromFlutter" -> {
                        val type = call.argument<String>("type") ?: "UnknownType"
                        val movil = call.argument<String>("movil") ?: "UnknownMovil"
                        val error = call.argument<String>("error") ?: "UnknownError"
                        val contextStr = call.argument<String>("context") ?: "NoContext"
                        
                        try {
                            com.riogas.appmovil.CriticalLogger.logCritical(
                                "Flutter",
                                "Error recibido desde Flutter: $type",
                                Exception(error),
                                mapOf(
                                    "movil" to movil,
                                    "error" to error,
                                    "context" to contextStr,
                                    "source" to "Flutter MethodChannel"
                                ),
                                "FLUTTER_CRITICAL_ERROR"
                            )
                            Log.i("MainActivity", "🟠 Log crítico recibido desde Flutter y registrado: $type - $error")
                            result.success("Log crítico registrado")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Error registrando log crítico desde Flutter: ${e.message}", e)
                            result.error("CRITICAL_LOG_ERROR", "Error registrando log crítico: ${e.message}", null)
                        }
                    }
                    "clearSharedPreferences" -> {
                        val prefsName = call.argument<String>("prefsName")
                        if (prefsName == null) {
                            result.error("INVALID_PREFS_NAME", "prefsName es requerido", null)
                            return@setMethodCallHandler
                        }
                        
                        try {
                            // 🧹 Limpiar SharedPreferences especificado (defensivo)
                            val prefs = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                            prefs.edit().clear().apply()
                            
                            Log.i("MainActivity", "🧹 SharedPreferences limpiado: $prefsName")
                            result.success("✅ SharedPreferences limpiado: $prefsName")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Error limpiando SharedPreferences '$prefsName': ${e.message}", e)
                            result.error("CLEAR_ERROR", "Error limpiando SharedPreferences: ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

            // 🧹 Canal para limpieza de logs nativos
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.riogas.appmovil/native_logs").setMethodCallHandler { call, result ->
                when (call.method) {
                    "clearAllLogs" -> {
                        try {
                            // Limpiar logs de CriticalLogger y DebugLogger
                            val logsDir = filesDir.resolve("critical_logs")
                            var deletedCount = 0
                            
                            if (logsDir.exists() && logsDir.isDirectory) {
                                logsDir.listFiles()?.forEach { file ->
                                    try {
                                        if (file.delete()) {
                                            deletedCount++
                                        }
                                    } catch (e: Exception) {
                                        Log.w("MainActivity", "⚠️ No se pudo eliminar log: ${file.name}", e)
                                    }
                                }
                            }
                            
                            // Limpiar logs de DebugLogger si existe carpeta separada
                            val debugLogsDir = filesDir.resolve("debug_logs")
                            if (debugLogsDir.exists() && debugLogsDir.isDirectory) {
                                debugLogsDir.listFiles()?.forEach { file ->
                                    try {
                                        if (file.delete()) {
                                            deletedCount++
                                        }
                                    } catch (e: Exception) {
                                        Log.w("MainActivity", "⚠️ No se pudo eliminar debug log: ${file.name}", e)
                                    }
                                }
                            }
                            
                            Log.i("MainActivity", "🧹 Logs nativos limpiados: $deletedCount archivos eliminados")
                            result.success("✅ Logs limpiados: $deletedCount archivos")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Error limpiando logs nativos: ${e.message}", e)
                            result.error("CLEAR_LOGS_ERROR", "Error limpiando logs: ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "background_service").setMethodCallHandler { call, result ->
                when (call.method) {
                    "startLocationService" -> {
                        val interval = call.argument<Int>("interval") ?: 1
                        val movil = call.argument<String>("movil") ?: "0"
                        val escenario = call.argument<String>("escenario") ?: "0"
                        val usuario = call.argument<String>("usuario") ?: "string"
                        val deviceId = call.argument<String>("deviceId") ?: "0"

                        // Limpiar estados de deshabilitación/pausa previos
                        com.riogas.appmovil.ServiceStatusFlags.setServiceDisabled(this, false, "startLocationService desde Flutter UI")
                        com.riogas.appmovil.ServiceStatusFlags.setServicePaused(this, false, "startLocationService desde Flutter UI")
                        com.riogas.appmovil.ServiceStatusFlags.setWatchdogDisabled(this, false, "startLocationService")
                        // 🏪 Un chofer normal arrancando tracking limpia el perfil comercio,
                        // por si este mismo teléfono lo usó antes un comercio 9998.
                        com.riogas.appmovil.ServiceStatusFlags.setRestrictedMode(this, false, "startLocationService desde Flutter UI")
                        val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
                        prefs.edit().apply {
                            remove("stop_reason")
                            remove("stop_timestamp")
                            remove("auto_stopped")
                            remove("stopped_by_user")
                            remove("stopped_from_device")
                            remove("resume_time")
                            remove("pause_minutes")
                        }.apply()
                        Log.i("MainActivity", "🧹 Estados de servicio limpiados antes de iniciar")

                        // Log del evento de inicio
                        LocationLogger.logEvent(this, "SERVICE_STARTED_MANUALLY", mapOf(
                            "usuario" to usuario,
                            "deviceId" to deviceId,
                            "movil" to movil,
                            "escenario" to escenario,
                            "interval" to interval.toString(),
                            "source" to "Flutter_UI"
                        ))

                        // No persistir tracking_interval_seconds: "interval" es legacy en minutos
                        // (típicamente 3 → 180s). Se deja que rija el default de 12s del service.

                        // Arranque único del FGS nuevo (idempotente: si ya corre, actualiza extras)
                        com.riogas.appmovil.tracking.LocationTrackingService.start(this, movil, escenario, usuario, deviceId)

                        // B.4: programar health-check (15 min, NO fuente de GPS)
                        com.riogas.appmovil.tracking.HealthCheckWorker.schedule(this)

                        Log.d("MainActivity", "✅ LocationTrackingService iniciado desde Flutter")
                        result.success("✅ Servicio de ubicación iniciado con intervalo $interval minutos")
                    }
                    "saveRestrictedMode" -> {
                        val restricted = call.argument<Boolean>("restricted") ?: false
                        com.riogas.appmovil.ServiceStatusFlags.setRestrictedMode(
                            this, restricted, "login Flutter")
                        if (restricted) {
                            // Nada de tracking para este perfil: matar el FGS por
                            // si venía corriendo de una sesión anterior de chofer.
                            com.riogas.appmovil.tracking.LocationTrackingService.stop(this)
                        }
                        result.success("✅ restricted_mode=$restricted")
                    }
                    "cancelHealthCheck" -> {
                        com.riogas.appmovil.tracking.HealthCheckWorker.cancel(this)
                        Log.i("MainActivity", "🏪 HealthCheckWorker cancelado (modo restringido)")
                        result.success("✅ HealthCheckWorker cancelado")
                    }
                    "startPromoKeepAlive" -> {
                        com.riogas.appmovil.tracking.PromoKeepAliveService.start(this)
                        result.success("✅ PromoKeepAliveService iniciado")
                    }
                    "stopPromoKeepAlive" -> {
                        com.riogas.appmovil.tracking.PromoKeepAliveService.stop(this)
                        result.success("✅ PromoKeepAliveService detenido")
                    }
                    "stopLocationService" -> {
                        val movil = call.argument<String>("movil") ?: "0"
                        val escenario = call.argument<String>("escenario") ?: "0"
                        val usuario = call.argument<String>("usuario") ?: "string"
                        val deviceId = call.argument<String>("deviceId") ?: "0"

                        // 1. Cancelar WorkManager (ya no hay AlarmManager que cancelar)
                        try {
                            WorkManagerHelper.cancelPeriodicWork(this)
                            com.riogas.appmovil.tracking.HealthCheckWorker.cancel(this)
                            Log.i("MainActivity", "🛑 WorkManager cancelado desde Flutter")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Error cancelando WorkManager: ${e.message}")
                        }

                        // 2. Guardar flag para bloquear futuros disparos con razón específica
                        com.riogas.appmovil.ServiceStatusFlags.setServiceDisabled(this, true, "Manual stop from Flutter UI")
                        com.riogas.appmovil.ServiceStatusFlags.setWatchdogDisabled(this, true, "Manual stop from Flutter UI") // 🔥 CRÍTICO: Detener watchdog también
                        val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
                        prefs.edit().apply {
                            putString("stop_reason", "Manual stop from Flutter UI")
                            putLong("stop_timestamp", System.currentTimeMillis())
                            putBoolean("auto_stopped", false) // Parada manual
                            putString("stopped_by_user", usuario)
                            putString("stopped_from_device", deviceId)
                        }.apply()
                        Log.i("MainActivity", "📛 Bandera de desactivación guardada con detalles (service + watchdog)")

                        // 3. Detener el tracking foreground nuevo
                        com.riogas.appmovil.tracking.LocationTrackingService.stop(this)
                        Log.i("MainActivity", "🧹 Servicio detenido y notificación eliminada")

                        // 4. Resetear distancia diaria por parada manual
                        LocationHelper.resetDailyDistanceByService(this, "Manual stop from Flutter UI")

                        // 5. Log del evento de parada manual
                        LocationLogger.logEvent(this, "SERVICE_STOPPED_MANUALLY", mapOf(
                            "usuario" to usuario,
                            "deviceId" to deviceId,
                            "movil" to movil,
                            "escenario" to escenario,
                            "source" to "Flutter_UI",
                            "distanceReset" to "true"
                        ))

                        result.success("✅ Servicio de ubicación detenido correctamente")
                    }

                    "getAppState" -> {
                        // Devuelve el estado de la app: foreground/background
                        val isInForeground = isAppInForeground()
                        result.success(if (isInForeground) "foreground" else "background")
                    }
                    "isGpsServiceRunning" -> {
                        // 🔍 Verificar si el tracking GPS está corriendo
                        val isRunning = com.riogas.appmovil.tracking.LocationTrackingService.isRunning
                        Log.d("MainActivity", "🔍 isGpsServiceRunning: $isRunning")
                        result.success(isRunning)
                    }
                    "forceStopGpsService" -> {
                        // 🛑 Detener FORZOSAMENTE el tracking GPS (force → disabled=true)
                        Log.d("MainActivity", "🛑 forceStopGpsService - Deteniendo tracking GPS")
                        try {
                            com.riogas.appmovil.tracking.LocationTrackingService.stop(this)
                            com.riogas.appmovil.tracking.HealthCheckWorker.cancel(this)
                            com.riogas.appmovil.ServiceStatusFlags.setServiceDisabled(this, true, "forceStopGpsService desde Flutter UI")
                            val stopped = !com.riogas.appmovil.tracking.LocationTrackingService.isRunning
                            Log.d("MainActivity", "✅ forceStopGpsService completado - detenido: $stopped")
                            result.success(stopped)
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Error en forceStopGpsService: ${e.message}")
                            result.success(false)
                        }
                    }
                    "FcmNotification" -> {
                        // Aquí podrías simular o verificar la recepción de FCM
                        val interval = call.argument<Int>("interval") ?: 1
                        val movil = call.argument<String>("movil") ?: "0"
                        val escenario = call.argument<String>("escenario") ?: "0"
                        val usuario = call.argument<String>("usuario") ?: "string"
                        val deviceId = call.argument<String>("deviceId") ?: "0"
                        
                        result.success("FCM test OK (implementa lógica real si lo necesitas)")
                    }
                    "getServiceStatus" -> {
                        // Obtener estado completo del servicio de ubicación
                        val status = LocationServiceController.getServiceStatus(this)
                        result.success(status)
                    }
                    "reactivateService" -> {
                        val reason = call.argument<String>("reason") ?: "Manual reactivation from Flutter"
                        LocationServiceController.reactivateService(this, reason)
                        result.success("✅ Servicio reactivado: $reason")
                    }
                    "getUnsyncedLogs" -> {
                        // Obtener logs no sincronizados para enviar a Hive
                        val unsyncedLogs = LocationLogger.getUnsyncedLogs(this)
                        result.success(unsyncedLogs)
                    }
                    "markLogsSynced" -> {
                        val eventIds = call.argument<List<Int>>("eventIds") ?: emptyList()
                        val errorIds = call.argument<List<Int>>("errorIds") ?: emptyList()
                        val metricIds = call.argument<List<Int>>("metricIds") ?: emptyList()
                        
                        LocationLogger.markLogsSynced(this, eventIds, errorIds, metricIds)
                        result.success("✅ Logs marcados como sincronizados")
                    }
                    "cleanupOldLogs" -> {
                        LocationLogger.cleanupOldLogs(this)
                        result.success("✅ Logs antiguos limpiados")
                    }
                    "forceStopService" -> {
                        val movil = call.argument<String>("movil") ?: "0"
                        val escenario = call.argument<String>("escenario") ?: "0"
                        val usuario = call.argument<String>("usuario") ?: "string"
                        val deviceId = call.argument<String>("deviceId") ?: "0"
                        val reason = call.argument<String>("reason") ?: "Forced stop from Flutter"
                        
                        // Resetear distancia diaria por parada manual
                        LocationHelper.resetDailyDistanceByService(this, "Manual stop: $reason")
                        
                        LocationServiceController.stopLocationServiceFromBackground(
                            this, movil, escenario, usuario, deviceId, reason
                        )
                        result.success("✅ Servicio detenido forzosamente: $reason")
                    }
                    "getSharedPreferences" -> {
                        val prefsName = call.argument<String>("name") ?: "config"
                        val prefs = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                        val allPrefs = prefs.all
                        result.success(allPrefs)
                    }
                    "clearSharedPreference" -> {
                        val prefsName = call.argument<String>("name") ?: "config"
                        val key = call.argument<String>("key") ?: ""
                        val prefs = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                        prefs.edit().remove(key).apply()
                        result.success("✅ Preferencia limpiada: $key")
                    }
                    "checkBatteryOptimization" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                        val packageName = applicationContext.packageName
                        val isIgnoring = pm.isIgnoringBatteryOptimizations(packageName)
                        
                        Log.d("MainActivity", "🔋 Battery optimization status: isIgnoring=$isIgnoring")
                        result.success(isIgnoring)
                    }
                    "requestBatteryOptimizationExemption" -> {
                        try {
                            val pm = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                            val packageName = applicationContext.packageName
                            
                            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                intent.data = android.net.Uri.parse("package:$packageName")
                                startActivity(intent)
                                
                                Log.d("MainActivity", "🔋 Solicitud de exclusión de batería enviada")
                                result.success("✅ Solicitud enviada")
                            } else {
                                Log.d("MainActivity", "✅ La app ya está exenta de optimización de batería")
                                result.success("✅ Ya exenta")
                            }
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Error solicitando exclusión de batería: ${e.message}", e)
                            result.error("ERROR", "Error al solicitar exclusión: ${e.message}", null)
                        }
                    }
                    "checkAndRestartLocationService" -> {
                        try {
                            Log.d("MainActivity", "🔍 Verificando estado del servicio de ubicación...")
                            com.riogas.appmovil.DebugLogger.i("MainActivity", "Service health check iniciado", mapOf(
                                "source" to "order_detail_page",
                                "action" to "checkAndRestartLocationService"
                            ))
                            
                            val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
                            
                            // 1️⃣ Verificar si el servicio está deshabilitado manualmente
                            val isDisabled = com.riogas.appmovil.ServiceStatusFlags.isServiceDisabled(this)
                            if (isDisabled) {
                                Log.w("MainActivity", "⚠️ Servicio deshabilitado manualmente, no se reiniciará automáticamente")
                                // keys de log: nombres estables para n8n (no son accesos a prefs)
                                com.riogas.appmovil.DebugLogger.w("MainActivity", "Servicio deshabilitado manualmente", mapOf(
                                    "service_disabled" to true
                                ))
                                result.success(mapOf<String, Any>(
                                    "status" to "disabled",
                                    "message" to "Servicio deshabilitado manualmente",
                                    "restarted" to false
                                ))
                                return@setMethodCallHandler
                            }
                            
                            // 2️⃣ CRITICAL: Obtener movil desde Flutter (Hive) - source of truth
                            val movilFromFlutter = call.argument<String>("movil")
                            val escenarioFromFlutter = call.argument<String>("escenario")
                            val usuarioFromFlutter = call.argument<String>("usuario")
                            val deviceIdFromFlutter = call.argument<String>("deviceId")
                            val intervalFromFlutter = call.argument<Int>("interval") ?: 3
                            
                            // Validar que movil no esté vacío (viene desde Hive en Flutter)
                            if (movilFromFlutter.isNullOrEmpty() || movilFromFlutter.isBlank()) {
                                Log.e("MainActivity", "❌ CRITICAL: movil vacío recibido desde Flutter/Hive")
                                LocationLogger.logEvent(this@MainActivity, "HEALTH_CHECK_NO_MOVIL", mapOf<String, String>(
                                    "usuario" to (usuarioFromFlutter ?: ""),
                                    "deviceId" to (deviceIdFromFlutter ?: ""),
                                    "movil" to "",
                                    "error" to "movil parameter is empty from Flutter/Hive"
                                ))
                                result.success(mapOf<String, Any>(
                                    "status" to "error",
                                    "message" to "No se puede validar servicio: movil vacío en Hive",
                                    "restarted" to false,
                                    "movil" to "",
                                    "error" to "empty_movil_from_hive"
                                ))
                                return@setMethodCallHandler
                            }
                            
                            // Usar movil validado desde Flutter/Hive como source of truth
                            val movil = movilFromFlutter
                            val escenario = escenarioFromFlutter
                            val usuario = usuarioFromFlutter
                            val deviceId = deviceIdFromFlutter
                            val intervalMinutes = intervalFromFlutter
                            
                            // 3️⃣ SIEMPRE sincronizar parámetros Hive → SharedPreferences (fix usuario vacío)
                            val lastMovilInPrefs = prefs.getString("last_movil", "") ?: ""
                            val paramsChanged = lastMovilInPrefs != movil
                            
                            // 🔧 FIX v14.7: Guardar SIEMPRE los parámetros (no solo cuando movil cambia)
                            // RAZÓN: Si solo guardamos en caso de mismatch, usuario/escenario pueden quedar vacíos
                            prefs.edit().apply {
                                putString("last_movil", movil)
                                putString("last_escenario", escenario)
                                putString("last_usuario", usuario)
                                putString("last_deviceId", deviceId)
                                apply()
                            }
                            
                            if (paramsChanged) {
                                Log.w("MainActivity", "⚠️ PARAM_MISMATCH detectado: SharedPreferences movil='$lastMovilInPrefs' → Hive movil='$movil'")
                            }
                            
                            LocationLogger.logEvent(this@MainActivity, "PARAMS_SYNCED_HIVE_TO_PREFS", mapOf<String, String>(
                                "old_movil" to lastMovilInPrefs,
                                "new_movil" to movil,
                                "usuario" to (usuario ?: ""),
                                "deviceId" to (deviceId ?: ""),
                                "changed" to paramsChanged.toString()
                            ))
                            
                            Log.i("MainActivity", "✅ Parámetros sincronizados: Hive → SharedPreferences (movil=$movil, usuario=$usuario, escenario=$escenario)")
                            
                            // Arranque idempotente del tracking nuevo: si ya corre, actualiza params.
                            // No persistir tracking_interval_seconds: intervalMinutes es legacy en
                            // minutos, se deja que rija el default de 12s del service.

                            val wasRunning = com.riogas.appmovil.tracking.LocationTrackingService.isRunning
                            com.riogas.appmovil.tracking.LocationTrackingService.start(this, movil, escenario ?: "0", usuario ?: "", deviceId ?: "")
                            com.riogas.appmovil.tracking.HealthCheckWorker.schedule(this)

                            LocationLogger.logEvent(this, "SERVICE_HEALTH_CHECK", mapOf<String, String>(
                                "usuario" to (usuario ?: ""),
                                "deviceId" to (deviceId ?: ""),
                                "movil" to movil,
                                "escenario" to (escenario ?: ""),
                                "interval" to intervalMinutes.toString(),
                                "wasRunning" to wasRunning.toString(),
                                "paramsChanged" to paramsChanged.toString()
                            ))

                            Log.i("MainActivity", "✅ Tracking asegurado (wasRunning=$wasRunning, movil=$movil)")
                            result.success(mapOf<String, Any>(
                                "status" to if (wasRunning) "active" else "restarted",
                                "message" to if (wasRunning) "Servicio activo" else "Servicio iniciado",
                                "restarted" to !wasRunning,
                                "movil" to movil,
                                "interval" to intervalMinutes,
                                "movil_validated" to true
                            ))

                                                } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Error verificando/reiniciando servicio: ${e.message}", e)
                            result.error("ERROR", "Error al verificar servicio: ${e.message}", null)
                        }
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }

            // 2. Canal para ubicación por red (con try-catch global)
            try {
                Log.d("NETWORK_LOCATION", "🛠 Intentando registrar MethodChannel...")
                
                MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "network_location").setMethodCallHandler { call, result ->
                    Log.d("NETWORK_LOCATION", "📞 Método invocado: ${call.method}")
                    
                    if (call.method == "getNetworkLocation") {
                        Log.d("NETWORK_LOCATION", "🔍 Iniciando obtención de ubicación por red...")
                        
                        try {
                            Log.d("NETWORK_LOCATION", "🛠 Obteniendo LocationManager...")
                            val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
                            
                            @SuppressLint("MissingPermission")
                            Log.d("NETWORK_LOCATION", "📡 Buscando última ubicación conocida (NETWORK_PROVIDER)...")
                            val location: Location? = locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                            
                            if (location != null) {
                                Log.d("NETWORK_LOCATION", "📍 Ubicación obtenida: Lat=${location.latitude}, Lon=${location.longitude}")
                                val response = mapOf(
                                    "latitude" to location.latitude,
                                    "longitude" to location.longitude
                                )
                                Log.d("NETWORK_LOCATION", "📤 Enviando respuesta: $response")
                                result.success(response)
                            } else {
                                Log.d("NETWORK_LOCATION", "⚠️ No se pudo obtener ubicación (null)")
                                result.success(null)
                            }
                            
                        } catch (e: Exception) {
                            Log.e("NETWORK_LOCATION", "🔥 Error en getNetworkLocation", e)
                            result.error(
                                "LOCATION_ERROR", 
                                "Error interno: ${e.message}",
                                null
                            )
                        }
                        
                    } else {
                        Log.d("NETWORK_LOCATION", "🚫 Método no implementado: ${call.method}")
                        result.notImplemented()
                    }
                }
                
                Log.d("NETWORK_LOCATION", "[FIN] MethodChannel 'network_location' registrado CORRECTAMENTE")
                
            } catch (e: Exception) {
                Log.e("NETWORK_LOCATION", "‼️‼️ ERROR CRÍTICO al registrar MethodChannel", e)
                // Puedes notificar a Flutter mediante un canal alternativo si es necesario
            }

            // 🚩 MethodChannel para acceso a flags de estado de servicios
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.riogas.appmovil/service_status").setMethodCallHandler { call, result ->
                when (call.method) {
                    "getServicesNeedRestart" -> {
                        try {
                            val needRestart = com.riogas.appmovil.ServiceStatusFlags.getServicesNeedRestart(this)
                            Log.d("MainActivity", "🚩 [FLAGS] Devolviendo services_need_restart = $needRestart")
                            result.success(needRestart)
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ [FLAGS] Error obteniendo services_need_restart", e)
                            result.error("FLAG_ERROR", "Error obteniendo flag: ${e.message}", null)
                        }
                    }
                    "getFullServiceStatus" -> {
                        try {
                            val status = com.riogas.appmovil.ServiceStatusFlags.getFullStatus(this)
                            Log.d("MainActivity", "🚩 [FLAGS] Devolviendo estado completo de servicios")
                            result.success(status)
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ [FLAGS] Error obteniendo estado completo", e)
                            result.error("FLAG_ERROR", "Error obteniendo estado: ${e.message}", null)
                        }
                    }
                    "clearAllServiceFlags" -> {
                        try {
                            com.riogas.appmovil.ServiceStatusFlags.clearAllFlags(this)
                            Log.d("MainActivity", "🚩 [FLAGS] Todas las flags limpiadas")
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ [FLAGS] Error limpiando flags", e)
                            result.error("FLAG_ERROR", "Error limpiando flags: ${e.message}", null)
                        }
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
            
            // 🚨 MethodChannel para remote logout (FCM)
            // Este canal NO tiene handler porque solo se usa para ENVIAR eventos desde Kotlin → Flutter
            remoteLogoutChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REMOTE_LOGOUT_CHANNEL)

            super.configureFlutterEngine(flutterEngine)
        }
        
        /**
         * Reinicia el servicio de ubicación desde foreground si hay parámetros guardados.
         * Esto es CRÍTICO para Android 12+ porque permite que el ForegroundService
         * acceda a la ubicación (ya que se inicia desde foreground, no desde background).
         */
        private fun restartLocationServiceFromForeground() {
            // 🏪 Perfil comercio: nunca arrancar el FGS de ubicación. Este método
            // corre en onCreate ANTES de super.onCreate(), o sea antes de que
            // exista el engine de Flutter: es el único punto donde se puede
            // frenar este camino.
            if (com.riogas.appmovil.ServiceStatusFlags.isRestrictedMode(this)) {
                Log.i("MainActivity", "🏪 restricted_mode=true → no se arranca el FGS de ubicación")
                return
            }

            val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
            val movil = prefs.getString("last_movil", "")
            val isDisabled = com.riogas.appmovil.ServiceStatusFlags.isServiceDisabled(this)
            
            if (movil.isNullOrEmpty()) {
                Log.d("MainActivity", "ℹ️ No hay parámetros guardados, servicio no iniciado")
                return
            }
            
            if (isDisabled) {
                Log.d("MainActivity", "🚫 Servicio está deshabilitado, no se reinicia")
                return
            }
            
            // Recuperar todos los parámetros guardados
            val escenario = prefs.getString("last_escenario", "") ?: ""
            var usuario = prefs.getString("last_usuario", "") ?: ""
            val deviceId = prefs.getString("last_deviceId", "") ?: ""
            val intervalSeconds = prefs.getInt("tracking_interval_seconds", 12)

            // 👤 Si usuario está vacío, intentar recuperarlo desde FlutterSharedPreferences
            if (usuario.isEmpty()) {
                val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                usuario = flutterPrefs.getString("flutter.username", "") ?: ""
                Log.d("MainActivity", "👤 Usuario recuperado desde FlutterSharedPreferences: $usuario")
            }

            Log.d("MainActivity", "🔄 Reiniciando servicio desde foreground: movil=$movil, interval=${intervalSeconds}s")

            // 🆕 try-catch para capturar errores al iniciar servicio
            try {
                com.riogas.appmovil.tracking.LocationTrackingService.start(this, movil, escenario, usuario, deviceId)

                Log.d("MainActivity", "✅ LocationTrackingService reiniciado desde foreground")

            } catch (e: SecurityException) {
                Log.e("MainActivity", "❌ SecurityException reiniciando servicio desde foreground", e)
                com.riogas.appmovil.CriticalLogger.logCritical(
                    "MainActivity",
                    "ERROR: Sin permisos para reiniciar servicio GPS desde foreground",
                    e,
                    mapOf(
                        "movil" to movil,
                        "android_version" to Build.VERSION.SDK_INT,
                        "context" to "restartLocationServiceFromForeground"
                    ),
                    "SERVICE_START_FAILED"
                )
                return
                
            } catch (e: IllegalStateException) {
                Log.e("MainActivity", "❌ IllegalStateException reiniciando servicio desde foreground", e)
                com.riogas.appmovil.CriticalLogger.logCritical(
                    "MainActivity",
                    "ERROR: Servicio GPS bloqueado por background restrictions en onCreate",
                    e,
                    mapOf(
                        "movil" to movil,
                        "android_version" to Build.VERSION.SDK_INT,
                        "context" to "restartLocationServiceFromForeground"
                    ),
                    "SERVICE_START_FAILED"
                )
                return
                
            } catch (e: Exception) {
                Log.e("MainActivity", "❌ Error desconocido reiniciando servicio desde foreground", e)
                com.riogas.appmovil.CriticalLogger.logCritical(
                    "MainActivity",
                    "ERROR: Fallo desconocido reiniciando servicio GPS desde foreground",
                    e,
                    mapOf(
                        "movil" to movil,
                        "android_version" to Build.VERSION.SDK_INT,
                        "error_type" to e.javaClass.simpleName,
                        "context" to "restartLocationServiceFromForeground"
                    ),
                    "SERVICE_START_FAILED"
                )
                return
            }
            
            // Log del evento
            LocationLogger.logEvent(this, "SERVICE_RESTARTED_FROM_FOREGROUND", mapOf(
                "movil" to movil,
                "escenario" to escenario,
                "usuario" to usuario,
                "deviceId" to deviceId,
                "interval" to "${intervalSeconds}s"
            ))
        }

        override fun onCreate(savedInstanceState: Bundle?) {
            val sdk = Build.VERSION.SDK_INT
            println("🟢 Android SDK Version Detected: $sdk")

            // 🔥 Inicializar Firebase
            FirebaseApp.initializeApp(this) // 👈 ESTA LÍNEA

            // 🔥 Inicializar sistema de logging nativo
            LocationLogger.initialize(this)
            
            // 🆕 Inicializar DebugLogger para diagnóstico remoto
            com.riogas.appmovil.DebugLogger.init(applicationContext)
            Log.d("MainActivity", "DebugLogger inicializado")
            
            // 🆕 Inicializar CriticalLogger para errores que se envían SIEMPRE (independiente de debugMode)
            com.riogas.appmovil.CriticalLogger.init(applicationContext)
            Log.d("MainActivity", "✅ CriticalLogger inicializado (SIEMPRE activo)")
            
            // Subida periódica de logs críticos (WorkManager, cada 15 min; sin alarmas ni watchdog)
            com.riogas.appmovil.CriticalLogUploadWorker.schedule(applicationContext)
            Log.d("MainActivity", "✅ CriticalLogUploadWorker programado (cada 15 min)")

            // 🧹 Task 10 / B.4: limpieza one-shot del work periódico viejo (pre-refactor) en teléfonos actualizados
            androidx.work.WorkManager.getInstance(this).cancelUniqueWork("LocationPeriodicWork")

            // 🔄 REINICIAR SERVICIO DESDE FOREGROUND (Android 12+ compatible)
            // 🏪 Simétrico al camino del GPS: el comercio arranca su keep-alive
            // sin ubicación, el chofer arranca el FGS de tracking.
            if (com.riogas.appmovil.ServiceStatusFlags.isRestrictedMode(this)) {
                com.riogas.appmovil.tracking.PromoKeepAliveService.start(this)
                Log.i("MainActivity", "🏪 Keep-alive del comercio iniciado desde onCreate")
            } else {
                restartLocationServiceFromForeground()
            }

            val args = mutableListOf<String>()

            if (sdk < Build.VERSION_CODES.O) {
                println("⚠️ Ejecutando en Android < 8: activando modo software rendering y desactivando Impeller")
                args.add("--enable-software-rendering")
                args.add("--disable-impeller")
            } else {
                println("✅ Ejecutando en Android >= 8: usando Impeller")
                args.add("--enable-impeller")
            }

            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(this)
            loader.ensureInitializationComplete(this, args.toTypedArray())

            super.onCreate(savedInstanceState)
            
            // 🆕 Loguear versión del APK instalado
            try {
                val packageInfo = packageManager.getPackageInfo(packageName, 0)
                val versionName = packageInfo.versionName
                val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    packageInfo.longVersionCode
                } else {
                    @Suppress("DEPRECATION")
                    packageInfo.versionCode.toLong()
                }
                
                Log.i("MainActivity", "📦 APK instalado: v$versionName (code: $versionCode)")
                com.riogas.appmovil.DebugLogger.i("MainActivity", "Versión de APK", mapOf(
                    "versionName" to (versionName ?: "unknown"),
                    "versionCode" to versionCode.toString(),
                    "androidVersion" to Build.VERSION.SDK_INT.toString(),
                    "device" to "${Build.MANUFACTURER} ${Build.MODEL}",
                    "timestamp" to System.currentTimeMillis().toString()
                ))
            } catch (e: Exception) {
                Log.e("MainActivity", "Error obteniendo versión del APK: ${e.message}")
            }
            
            // 🆕 Verificar estado inicial de GPS y permisos
            com.example.moveit.receivers.GPSStatusReceiver.checkAndLogGPSStatus(this)
            com.example.moveit.receivers.PermissionChangeReceiver.checkAndLogPermissionChanges(this)
            
            // 🚨 Registrar BroadcastReceiver para logout remoto
            setupRemoteLogoutReceiver()
        }
        
        override fun onDestroy() {
            super.onDestroy()
            // 🚨 Desregistrar BroadcastReceiver para evitar memory leaks
            remoteLogoutReceiver?.let {
                try {
                    unregisterReceiver(it)
                    Log.d("MainActivity", "🚨 BroadcastReceiver de logout remoto desregistrado")
                } catch (e: Exception) {
                    Log.w("MainActivity", "⚠️ Error desregistrando BroadcastReceiver: ${e.message}")
                }
            }
        }
        
        /**
         * Configura el BroadcastReceiver para escuchar el broadcast REMOTE_LOGOUT
         * enviado desde FcmPushReceiver cuando se recibe el comando "logout_user"
         */
        /**
         * Configura el BroadcastReceiver para escuchar el broadcast REMOTE_LOGOUT
         * enviado desde FcmPushReceiver cuando se recibe el comando "logout_user".
         * 
         * NO envía parámetros a Flutter, ya que Flutter los obtiene desde Hive.
         */
        private fun setupRemoteLogoutReceiver() {
            remoteLogoutReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == "com.riogas.appmovil.REMOTE_LOGOUT") {
                        Log.d("MainActivity", "🚨 [REMOTE_LOGOUT] Broadcast recibido desde FcmPushReceiver")
                        
                        // Notificar a Flutter via MethodChannel
                        // NO enviamos parámetros, Flutter obtiene todo de Hive
                        remoteLogoutChannel?.invokeMethod("onRemoteLogout", mapOf(
                            "timestamp" to System.currentTimeMillis()
                        ))
                        
                        Log.d("MainActivity", "🚨 [REMOTE_LOGOUT] Notificación enviada a Flutter (datos en Hive)")
                    }
                }
            }
            
            val intentFilter = IntentFilter("com.riogas.appmovil.REMOTE_LOGOUT")
            
            // 🔒 Android 13+ requiere especificar RECEIVER_NOT_EXPORTED
            // Este receiver solo recibe broadcasts internos de FcmPushReceiver
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(remoteLogoutReceiver, intentFilter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(remoteLogoutReceiver, intentFilter)
            }
            
            Log.d("MainActivity", "✅ BroadcastReceiver de logout remoto registrado")
        }

        /**
         * 🆕 onResume: Detectar cambios en permisos y GPS cuando usuario regresa de Settings
         */
        override fun onResume() {
            super.onResume()
            
            // Verificar cambios en permisos
            com.example.moveit.receivers.PermissionChangeReceiver.checkAndLogPermissionChanges(this)
            
            // Verificar cambios en GPS
            com.example.moveit.receivers.GPSStatusReceiver.checkAndLogGPSStatus(this)
            
            // 🚨 Verificar si hay un remote logout pendiente en el intent
            handleRemoteLogoutIntent(intent)
        }
        
        /**
         * 🚨 onNewIntent: Recibir remote logout cuando la app ya está corriendo
         */
        override fun onNewIntent(intent: Intent) {
            super.onNewIntent(intent)
            setIntent(intent) // Actualizar el intent actual
            
            Log.d("MainActivity", "🚨 [REMOTE_LOGOUT] onNewIntent llamado con action: ${intent.action}")
            handleRemoteLogoutIntent(intent)
        }
        
        /**
         * 🚨 Procesar intent de remote logout
         */
        private fun handleRemoteLogoutIntent(intent: Intent?) {
            if (intent?.action == "com.riogas.appmovil.REMOTE_LOGOUT") {
                val isRemoteLogout = intent.getBooleanExtra("remote_logout", false)
                if (isRemoteLogout) {
                    Log.d("MainActivity", "🚨 [REMOTE_LOGOUT] Intent de logout remoto detectado")
                    Log.d("MainActivity", "🚨 [REMOTE_LOGOUT] Notificando a Flutter via MethodChannel...")
                    
                    // Notificar a Flutter via MethodChannel
                    remoteLogoutChannel?.invokeMethod("onRemoteLogout", mapOf(
                        "timestamp" to System.currentTimeMillis()
                    ))
                    
                    Log.d("MainActivity", "✅ [REMOTE_LOGOUT] Notificación enviada a Flutter")
                    
                    // Limpiar el flag del intent para no procesarlo de nuevo
                    intent.removeExtra("remote_logout")
                }
            }
        }

        // Función de utilidad para saber si la app está en foreground
        private fun isAppInForeground(): Boolean {
            // Puedes mejorar esta lógica según tus necesidades
            return this.hasWindowFocus()
        }
        
        // Función para verificar si un servicio específico está corriendo
        private fun isServiceRunning(serviceClass: Class<*>): Boolean {
            val manager = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            @Suppress("DEPRECATION")
            for (service in manager.getRunningServices(Integer.MAX_VALUE)) {
                if (serviceClass.name == service.service.className) {
                    return true
                }
            }
            return false
        }
        
        // Programar WorkManager para subir logs cada 10 minutos
        private fun scheduleDebugLogUpload() {
            try {
                Log.i("MainActivity", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                Log.i("MainActivity", "📅 PROGRAMANDO WORKMANAGER")
                Log.i("MainActivity", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                
                // 1️⃣ Verificar batería
                val powerManager = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                val isIgnoringBatteryOpt = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                    powerManager.isIgnoringBatteryOptimizations(packageName)
                } else {
                    true // Android 5 o menor no tiene esta restricción
                }
                Log.i("MainActivity", "🔋 Batería optimizada: ${!isIgnoringBatteryOpt}")
                Log.i("MainActivity", "   - En whitelist: $isIgnoringBatteryOpt")
                
                if (!isIgnoringBatteryOpt) {
                    Log.w("MainActivity", "⚠️ ADVERTENCIA: App NO está en whitelist de batería")
                    Log.w("MainActivity", "   - WorkManager puede NO ejecutarse en background")
                    Log.w("MainActivity", "   - Solicitar al usuario ignorar optimización")
                }
                
                // 2️⃣ Verificar red
                val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
                val activeNetwork = connectivityManager.activeNetworkInfo
                val hasInternet = activeNetwork?.isConnectedOrConnecting == true
                Log.i("MainActivity", "🌐 Red disponible: $hasInternet")
                Log.i("MainActivity", "   - Tipo: ${activeNetwork?.typeName ?: "NONE"}")
                Log.i("MainActivity", "   - Estado: ${if (activeNetwork?.isConnected == true) "CONNECTED" else "DISCONNECTED"}")
                
                if (!hasInternet) {
                    Log.w("MainActivity", "⚠️ ADVERTENCIA: Sin conexión a internet")
                    Log.w("MainActivity", "   - WorkManager esperará hasta que haya red")
                }
                
                // 3️⃣ Verificar si ya está programado
                val workManager = androidx.work.WorkManager.getInstance(applicationContext)
                val existingWork = workManager.getWorkInfosForUniqueWork("debug_log_upload").get()
                
                if (existingWork.isNotEmpty()) {
                    val state = existingWork.first().state
                    Log.i("MainActivity", "📦 WorkManager existente: $state")
                    if (!state.isFinished) {
                        Log.i("MainActivity", "   - Ya está programado, reemplazando...")
                    }
                }
                
                // 4️⃣ Programar WorkManager
                val uploadWorkRequest = androidx.work.PeriodicWorkRequestBuilder<com.riogas.appmovil.DebugLogUploadWorker>(
                    10, java.util.concurrent.TimeUnit.MINUTES
                )
                    .setConstraints(
                        androidx.work.Constraints.Builder()
                            .setRequiredNetworkType(androidx.work.NetworkType.CONNECTED)
                            .build()
                    )
                    .build()
                
                val requestId = uploadWorkRequest.id
                Log.i("MainActivity", "🆔 Work Request ID: $requestId")
                
                workManager.enqueueUniquePeriodicWork(
                    "debug_log_upload",
                    androidx.work.ExistingPeriodicWorkPolicy.REPLACE,
                    uploadWorkRequest
                )
                
                // 5️⃣ Confirmar programación
                val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
                val movil = prefs.getString("last_movil", "unknown") ?: "unknown"
                
                Log.i("MainActivity", "✅ WORKMANAGER PROGRAMADO EXITOSAMENTE")
                Log.i("MainActivity", "   - Intervalo: 10 minutos")
                Log.i("MainActivity", "   - Red requerida: SÍ")
                Log.i("MainActivity", "   - Móvil: $movil")
                Log.i("MainActivity", "   - Request ID: $requestId")
                Log.i("MainActivity", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                
                // 6️⃣ Loguear para n8n
                com.riogas.appmovil.DebugLogger.i("MainActivity", "WorkManager programado", mapOf<String, Any>(
                    "workName" to "debug_log_upload",
                    "interval" to "10 minutes",
                    "networkRequired" to true,
                    "batteryWhitelisted" to isIgnoringBatteryOpt,
                    "hasInternet" to hasInternet,
                    "networkType" to (activeNetwork?.typeName ?: "none"),
                    "movil" to movil,
                    "requestId" to requestId.toString(),
                    "device" to "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}",
                    "android" to android.os.Build.VERSION.RELEASE
                ))
                
            } catch (e: Exception) {
                Log.e("MainActivity", "❌ ERROR PROGRAMANDO WORKMANAGER")
                Log.e("MainActivity", "   - Tipo: ${e.javaClass.simpleName}")
                Log.e("MainActivity", "   - Mensaje: ${e.message}")
                Log.e("MainActivity", "   - StackTrace:", e)
                
                com.riogas.appmovil.DebugLogger.e("MainActivity", "Error programando WorkManager", e, mapOf<String, Any>(
                    "errorType" to e.javaClass.simpleName,
                    "errorMessage" to (e.message ?: "unknown")
                ))
            }
        }
        
        // Cancelar WorkManager de upload de logs
        private fun cancelDebugLogUpload() {
            try {
                Log.i("MainActivity", "🛑 Cancelando WorkManager de logs...")
                
                androidx.work.WorkManager.getInstance(applicationContext)
                    .cancelUniqueWork("debug_log_upload")
                
                Log.i("MainActivity", "✅ WorkManager de logs cancelado")
                
                com.riogas.appmovil.DebugLogger.i("MainActivity", "WorkManager cancelado", mapOf<String, Any>(
                    "workName" to "debug_log_upload"
                ))
            } catch (e: Exception) {
                Log.e("MainActivity", "❌ Error cancelando WorkManager: ${e.message}", e)
                com.riogas.appmovil.DebugLogger.e("MainActivity", "Error cancelando WorkManager", e, mapOf<String, Any>(
                    "errorType" to e.javaClass.simpleName,
                    "errorMessage" to (e.message ?: "unknown")
                ))
            }
        }
        
        // 🆕 Instalación robusta de APK con manejo de conflictos de paquetes
        private fun installApkRobust(filePath: String, result: io.flutter.plugin.common.MethodChannel.Result) {
            try {
                val apkFile = java.io.File(filePath)
                
                if (!apkFile.exists()) {
                    Log.e("MainActivity", "❌ APK no encontrado: $filePath")
                    result.error("FILE_NOT_FOUND", "El archivo APK no existe", null)
                    return
                }
                
                Log.i("MainActivity", "📦 APK encontrado: ${apkFile.length()} bytes")
                
                val apkUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    // Android 7.0+ requiere FileProvider
                    androidx.core.content.FileProvider.getUriForFile(
                        this,
                        "${applicationContext.packageName}.fileprovider",
                        apkFile
                    )
                } else {
                    android.net.Uri.fromFile(apkFile)
                }
                
                val installIntent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(apkUri, "application/vnd.android.package-archive")
                    
                    // 🔑 FLAGS CRÍTICOS para actualización robusta
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or 
                                Intent.FLAG_ACTIVITY_NEW_TASK
                    } else {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    
                    // 🆕 Forzar reinstalación sin necesidad de desinstalar manualmente
                    putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                    putExtra(Intent.EXTRA_RETURN_RESULT, true)
                    putExtra(Intent.EXTRA_INSTALLER_PACKAGE_NAME, applicationContext.packageName)
                }
                
                Log.i("MainActivity", "🚀 Lanzando instalador de Android...")
                Log.i("MainActivity", "   - URI: $apkUri")
                Log.i("MainActivity", "   - Flags: ${installIntent.flags}")
                Log.i("MainActivity", "   - SDK: ${Build.VERSION.SDK_INT}")
                
                com.riogas.appmovil.DebugLogger.i("MainActivity", "Instalando APK", mapOf<String, Any>(
                    "filePath" to filePath,
                    "fileSize" to apkFile.length().toString(),
                    "sdkVersion" to Build.VERSION.SDK_INT.toString(),
                    "flags" to installIntent.flags.toString()
                ))
                
                startActivity(installIntent)
                
                result.success(mapOf(
                    "status" to "installation_started",
                    "filePath" to filePath,
                    "fileSize" to apkFile.length()
                ))
                
            } catch (e: Exception) {
                Log.e("MainActivity", "❌ Error instalando APK: ${e.message}", e)
                
                com.riogas.appmovil.DebugLogger.e("MainActivity", "Error instalando APK", e, mapOf<String, Any>(
                    "filePath" to filePath,
                    "errorType" to e.javaClass.simpleName,
                    "errorMessage" to (e.message ?: "unknown")
                ))
                
                result.error("INSTALL_ERROR", e.message, e.stackTraceToString())
            }
        }
    }