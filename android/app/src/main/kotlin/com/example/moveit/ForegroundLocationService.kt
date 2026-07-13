package com.example.moveit

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody

class ForegroundLocationService : Service() {

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.e("LocationService-Foreground", "🔥 [ENTRY] onStartCommand() LLAMADO - startId=$startId")
        
        // 🔥 CRÍTICO: Llamar a startForeground() INMEDIATAMENTE (Android 12+ requirement)
        // DEBE ser lo primero para evitar ForegroundServiceDidNotStartInTimeException
        // 🆕 Android 10+ (API 29+) requiere especificar FOREGROUND_SERVICE_TYPE_LOCATION para usar GPS
        
        // 🆕 try-catch para capturar errores al iniciar foreground service
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                startForeground(
                    1710, 
                    createNotification(),
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                )
                Log.d("LocationService-Foreground", "🟢 Servicio iniciado como foreground con LOCATION type (Android 10+)")
            } else {
                startForeground(1710, createNotification())
                Log.d("LocationService-Foreground", "🟢 Servicio iniciado como foreground (Android <10)")
            }
            
            // Log crítico de inicio exitoso
            com.riogas.appmovil.CriticalLogger.logCritical(
                "ForegroundLocationService",
                "Servicio GPS iniciado exitosamente",
                mapOf(
                    "android_version" to android.os.Build.VERSION.SDK_INT,
                    "has_location_type" to (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q)
                ),
                "SERVICE_STARTED"
            )
            
        } catch (e: SecurityException) {
            Log.e("LocationService-Foreground", "❌ SecurityException en startForeground()", e)
            com.riogas.appmovil.CriticalLogger.logCritical(
                "ForegroundLocationService",
                "ERROR CRÍTICO: Sin permiso FOREGROUND_SERVICE_LOCATION",
                e,
                mapOf(
                    "android_version" to android.os.Build.VERSION.SDK_INT,
                    "permissions_required" to "FOREGROUND_SERVICE_LOCATION, POST_NOTIFICATIONS"
                ),
                "SERVICE_START_FAILED"
            )
            stopSelf()
            return START_NOT_STICKY
            
        } catch (e: Exception) {
            Log.e("LocationService-Foreground", "❌ Error desconocido en startForeground()", e)
            com.riogas.appmovil.CriticalLogger.logCritical(
                "ForegroundLocationService",
                "ERROR CRÍTICO: Fallo al iniciar foreground service",
                e,
                mapOf(
                    "android_version" to android.os.Build.VERSION.SDK_INT,
                    "error_type" to e.javaClass.simpleName
                ),
                "SERVICE_START_FAILED"
            )
            stopSelf()
            return START_NOT_STICKY
        }
        
        // Inicializar sistema de logging si no está inicializado
        LocationLogger.initialize(this)
        
        // 🌅 CHEQUEO DE CAMBIO DE DÍA: VERIFICAR INMEDIATAMENTE
        // Este check se ejecuta cada vez que el servicio se llama (cada 60 segundos)
        Log.e("LocationService-Foreground", "🌅 [DAY_CHECK] INICIO - Verificando cambio de día...")
        
        // Extraer parámetros del intent para el check
        val movil = intent?.getStringExtra("movil") ?: ""
        val escenario = intent?.getStringExtra("escenario") ?: ""
        val usuario = intent?.getStringExtra("usuario") ?: ""
        val deviceId = intent?.getStringExtra("deviceId") ?: ""
        
        // 🔧 FIX v14.7: Relajar validación - solo deviceId es obligatorio
        if (deviceId.isNotEmpty()) {
            // Usar valores por defecto si están vacíos
            val finalMovil = if (movil.isEmpty()) "0" else movil
            val finalEscenario = if (escenario.isEmpty()) "0" else escenario
            val finalUsuario = if (usuario.isEmpty()) "" else usuario
            
            val dayChanged = LocationHelper.checkForDayChange(this, finalMovil, finalEscenario, finalUsuario, deviceId)
            
            if (dayChanged) {
                Log.e("LocationService-Foreground", "🌅 [DAY_CHANGE] ¡CAMBIO DE DÍA DETECTADO! Deteniendo servicio...")
                
                // Detener el servicio inmediatamente
                stopForeground(true)
                stopSelf()
                return START_NOT_STICKY
            }
            
            Log.e("LocationService-Foreground", "🌅 [DAY_CHECK] FIN - Mismo día, continuando (movil=$finalMovil, usuario=$finalUsuario, deviceId=$deviceId)...")
        } else {
            Log.w("LocationService-Foreground", "🌅 [DAY_CHECK] SKIP - DeviceId vacío (CRÍTICO: no se puede verificar cambio de día)")
        }
        
        // Verificar si se solicita parar el servicio
        if (intent?.action == "STOP_FOREGROUND_SERVICE") {
            Log.i("LocationService-Foreground", "🛑 Recibida acción de stop, deteniendo servicio y quitando notificación")
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        }
        
        // Verificar si el servicio está deshabilitado
        val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
        val isDisabled = prefs.getBoolean("service_disabled", false)
        
        if (isDisabled) {
            val stopReason = prefs.getString("stop_reason", "Unknown reason")
            val stopTimestamp = prefs.getLong("stop_timestamp", 0)
            val wasAutoStopped = prefs.getBoolean("auto_stopped", false)
            
            Log.i("LocationService-Foreground", "🚫 Servicio deshabilitado: $stopReason")
            Log.i("LocationService-Foreground", "⏰ Deshabilitado en: ${java.util.Date(stopTimestamp)}")
            Log.i("LocationService-Foreground", "🤖 Parada automática: $wasAutoStopped")
            
            LocationLogger.logEvent(this, "SERVICE_SKIP_DISABLED", mapOf(
                "reason" to (stopReason ?: "Unknown"),
                "timestamp" to stopTimestamp.toString(),
                "auto_stopped" to wasAutoStopped.toString()
            ))
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        }
        
        // Verificar si el servicio está pausado temporalmente
        val isPaused = prefs.getBoolean("service_paused", false)
        val resumeTime = prefs.getLong("resume_time", 0)
        val currentTime = System.currentTimeMillis()
        
        if (isPaused && currentTime < resumeTime) {
            val remainingMinutes = (resumeTime - currentTime) / (60 * 1000)
            Log.i("LocationService-Foreground", "⏸️ Servicio pausado, reanudar en ${remainingMinutes}min")
            LocationLogger.logEvent(this, "SERVICE_SKIP_PAUSED", mapOf(
                "remainingMinutes" to remainingMinutes.toString()
            ))
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        } else if (isPaused && currentTime >= resumeTime) {
            // La pausa ha expirado, remover flag
            prefs.edit().apply {
                putBoolean("service_paused", false)
                remove("resume_time")
                remove("pause_minutes")
            }.apply()
            Log.i("LocationService-Foreground", "▶️ Pausa expirada, reanudando servicio")
            LocationLogger.logEvent(this, "SERVICE_PAUSE_EXPIRED", emptyMap())
        }

        // ⚠️ Las variables movil, escenario, usuario, deviceId ya fueron extraídas arriba para el check del día
        Log.d("LocationService", "📦 Parámetros recibidos: movil=$movil, escenario=$escenario, usuario=$usuario, deviceId=$deviceId")
        
        // 🆕 Guardar móvil en SharedPreferences para que CriticalLogger pueda accederlo
        if (movil.isNotEmpty()) {
            val userDataPrefs = getSharedPreferences("user_data", Context.MODE_PRIVATE)
            userDataPrefs.edit().putString("movil", movil).apply()
            Log.d("LocationService", "✅ Móvil guardado en SharedPreferences: $movil")
        }
        
        // � FIX v14.7: Relajar validación - deviceId es suficiente
        // �🛡️ VALIDACIÓN CRÍTICA: Verificar que deviceId NO esté vacío (movil puede estar vacío)
        if (deviceId.isEmpty()) {
            Log.e("LocationService", "❌ CRÍTICO: deviceId vacío! Intentando recuperar de SharedPreferences...")
            val prefs = getSharedPreferences("config", MODE_PRIVATE)
            val savedDeviceId = prefs.getString("last_deviceId", "") ?: ""
            
            if (savedDeviceId.isEmpty()) {
                Log.e("LocationService", "🚫 No se puede recuperar deviceId. DETENIENDO SERVICIO.")
                LocationLogger.logEvent(this, "SERVICE_STOPPED_INVALID_PARAMS", mapOf(
                    "reason" to "deviceId vacío y no hay fallback en SharedPreferences",
                    "movil" to movil,
                    "usuario" to usuario
                ))
                stopSelf()
                return START_NOT_STICKY
            } else {
                Log.w("LocationService", "✅ DeviceId recuperado de SharedPreferences: $savedDeviceId")
                // Reasignar valores recuperados
                val recoveredMovil = if (movil.isEmpty()) prefs.getString("last_movil", "0") ?: "0" else movil
                val recoveredEscenario = if (escenario.isEmpty()) prefs.getString("last_escenario", "0") ?: "0" else escenario
                val recoveredUsuario = if (usuario.isEmpty()) prefs.getString("last_usuario", "") ?: "" else usuario
                val recoveredDeviceId = savedDeviceId
                
                // Continuar con valores recuperados (reasignar mediante nueva llamada)
                val recoveryIntent = Intent(this, ForegroundLocationService::class.java).apply {
                    putExtra("movil", recoveredMovil)
                    putExtra("escenario", recoveredEscenario)
                    putExtra("usuario", recoveredUsuario)
                    putExtra("deviceId", recoveredDeviceId)
                    putExtra("EXECUTE_GPS", intent?.getBooleanExtra("EXECUTE_GPS", false) ?: false)
                }
                
                LocationLogger.logEvent(this, "SERVICE_PARAMS_RECOVERED", mapOf(
                    "movil" to recoveredMovil,
                    "escenario" to recoveredEscenario,
                    "deviceId" to recoveredDeviceId
                ))
                
                return onStartCommand(recoveryIntent, flags, startId)
            }
        }
        
        // ⚠️ ADVERTENCIA: Si movil/usuario/escenario vacíos, usar valores por defecto
        val finalMovil = if (movil.isEmpty()) "0" else movil
        val finalEscenario = if (escenario.isEmpty()) "0" else escenario
        val finalUsuario = if (usuario.isEmpty()) "" else usuario
        
        if (movil.isEmpty() || usuario.isEmpty() || escenario.isEmpty()) {
            Log.w("LocationService", "⚠️ Parámetros opcionales vacíos - usando defaults (movil=$finalMovil, escenario=$finalEscenario, usuario=$finalUsuario, deviceId=$deviceId)")
            LocationLogger.logEvent(this, "SERVICE_STARTED_WITH_DEFAULTS", mapOf(
                "movil" to finalMovil,
                "escenario" to finalEscenario,
                "usuario" to finalUsuario,
                "deviceId" to deviceId,
                "note" to "Algunos parámetros vacíos, usando valores por defecto"
            ))
        }

        // Registrar inicio del servicio
        LocationLogger.logEvent(this, "FOREGROUND_SERVICE_STARTED", mapOf(
            "movil" to movil,
            "escenario" to escenario,
            "usuario" to usuario,
            "deviceId" to deviceId
        ))

        // 🆕 WATCHDOG: Verificar que CriticalLogWorker esté programado
        Thread {
            try {
                Log.d("LocationService-Foreground", "🔍 [WATCHDOG] Verificando CriticalLogWorker...")
                
                val isWorkerScheduled = kotlinx.coroutines.runBlocking<Boolean> {
                    com.riogas.appmovil.ServiceWatchdog.isCriticalLogWorkerScheduled(this@ForegroundLocationService)
                }
                
                if (!isWorkerScheduled) {
                    Log.w("LocationService-Foreground", "⚠️ [WATCHDOG] CriticalLogWorker NO programado - Reiniciando...")
                    
                    // 🚩 MARCAR FLAG: CriticalLogWorker no está programado
                    com.riogas.appmovil.ServiceStatusFlags.setServicesNeedRestart(
                        this@ForegroundLocationService, 
                        true, 
                        "ForegroundLocationService",
                        "CriticalLogWorker no está programado"
                    )
                    com.riogas.appmovil.ServiceStatusFlags.setCriticalLogServiceStatus(
                        this@ForegroundLocationService, 
                        false, 
                        "ForegroundLocationService"
                    )
                    
                    com.riogas.appmovil.ServiceWatchdog.restartCriticalLogWorker(this@ForegroundLocationService)
                    
                    // Flag se actualizará dentro de restartCriticalLogWorker cuando se re-programe
                } else {
                    Log.d("LocationService-Foreground", "✅ [WATCHDOG] CriticalLogWorker activo")
                    
                    // 🚩 MARCAR FLAG: Todo está funcionando correctamente
                    com.riogas.appmovil.ServiceStatusFlags.setServicesNeedRestart(
                        this@ForegroundLocationService, 
                        false, 
                        "ForegroundLocationService",
                        "CriticalLogWorker verificado activo"
                    )
                    com.riogas.appmovil.ServiceStatusFlags.setCriticalLogServiceStatus(
                        this@ForegroundLocationService, 
                        true, 
                        "ForegroundLocationService"
                    )
                }
            } catch (e: Exception) {
                Log.e("LocationService-Foreground", "❌ [WATCHDOG] Error verificando CriticalLogWorker", e)
            }
        }.start()
        
        // 🆕 VERIFICAR SI SE DEBE EJECUTAR GPS O SOLO MANTENER FOREGROUND
        val executeGps = intent?.getBooleanExtra("EXECUTE_GPS", false) ?: false
        val isFirstExecution = intent?.getBooleanExtra("IS_FIRST_EXECUTION", false) ?: false
        
        Log.d("LocationService-Foreground", "🔍 [DEBUG] executeGps=$executeGps | isFirstExecution=$isFirstExecution")
        
        if (executeGps) {
            Log.d("LocationService-Foreground", "🔄 ${if (isFirstExecution) "PRIMER INICIO" else "Modo ALARMMANAGER"}: Ejecutando getCurrentLocation()...")
            
            // 🔥 EJECUTAR EN THREAD SEPARADO PARA NO BLOQUEAR
            // La obtención de GPS puede tardar hasta 45 segundos
            Thread {
                try {
                    Log.d("LocationService-Foreground", "🌍 Iniciando obtención de ubicación en thread separado...")
                    
                    // 🆕 OBTENER Y INCREMENTAR CONTADOR DE EJECUCIONES
                    val prefs = getSharedPreferences("gps_execution", Context.MODE_PRIVATE)
                    var executionCounter = prefs.getInt("execution_counter", 1)
                    
                    Log.d("LocationService-Foreground", "🔢 Ejecución #$executionCounter ${if (isFirstExecution) "(PRIMERA VEZ - envío instantáneo a RioGas)" else ""}")
                    
                    if (isFirstExecution) {
                        Log.d("LocationService-Foreground", "🎯 [LOGIN] Envío instantáneo activado: n8n + RioGas inmediato")
                    } else {
                        Log.d("LocationService-Foreground", "📤 n8n: SIEMPRE | Riogas: ${if (executionCounter % 6 == 0) "SI (cada 3 min)" else "NO (próximo en ${6 - (executionCounter % 6)} ejecuciones)"}")
                    }
                    
                    // Pasar los parámetros al método getCurrentLocation CON CONTADOR Y FLAG DE PRIMER INICIO
                    val coords = LocationHelper.getCurrentLocation(
                        context = this,
                        movil = movil,
                        escenario = escenario,
                        usuario = usuario,
                        deviceId = deviceId,
                        executionCounter = executionCounter,
                        isFirstExecution = isFirstExecution // 🆕 Pasar flag para envío instantáneo en login
                    )
                    Log.i("LocationService", "📍 Coordenadas obtenidas: $coords")
                    
                    // 🆕 INCREMENTAR CONTADOR DESPUÉS DE EJECUCIÓN EXITOSA
                    executionCounter++
                    prefs.edit().putInt("execution_counter", executionCounter).apply()
                    Log.d("LocationService-Foreground", "🔢 Contador incrementado a $executionCounter para próxima ejecución")
                    
                    // 🆕 ACTUALIZAR NOTIFICACIÓN con última coordenada
                    updateNotification("Última actualización: ${java.text.SimpleDateFormat("HH:mm:ss").format(java.util.Date())}")
                    
                } catch (e: Exception) {
                    Log.e("LocationService-Foreground", "❌ Error obteniendo ubicación: ${e.message}", e)
                    
                    // 🆕 SI ES LA PRIMERA EJECUCIÓN Y FALLA, LOGUEAR CRÍTICO SIEMPRE (sin importar debugMode)
                    if (isFirstExecution) {
                        Log.e("LocationService-Foreground", "🚨 CRÍTICO: Falló primer envío de coordenadas al iniciar servicio")
                        com.riogas.appmovil.CriticalLogger.logCritical(
                            "ForegroundLocationService",
                            "ERROR CRÍTICO: Falló primer envío de coordenadas al iniciar servicio GPS",
                            e,
                            mapOf(
                                "movil" to movil,
                                "escenario" to escenario,
                                "usuario" to usuario,
                                "deviceId" to deviceId,
                                "error_message" to (e.message ?: "Unknown error")
                            ),
                            "FIRST_GPS_SEND_FAILED"
                        )
                        
                        // 🆕 ENVIAR LOG INMEDIATAMENTE A N8N (SIN IMPORTAR debugMode)
                        Thread {
                            try {
                                val logsJson = com.riogas.appmovil.CriticalLogger.getLogsAsJson()
                                val client = okhttp3.OkHttpClient.Builder()
                                    .connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
                                    .build()
                                
                                val request = okhttp3.Request.Builder()
                                    .url("https://n8n.riogas.com.uy/webhook/debug-delivery")
                                    .post(logsJson.toRequestBody("application/json".toMediaType()))
                                    .build()
                                
                                client.newCall(request).execute().use { response ->
                                    if (response.isSuccessful) {
                                        Log.i("LocationService-Foreground", "✅ Log crítico de primer envío fallido enviado a n8n")
                                        com.riogas.appmovil.CriticalLogger.clearLogs()
                                    } else {
                                        Log.e("LocationService-Foreground", "❌ Error enviando log crítico a n8n: ${response.code}")
                                    }
                                }
                            } catch (ex: Exception) {
                                Log.e("LocationService-Foreground", "❌ Excepción enviando log crítico a n8n", ex)
                            }
                        }.start()
                    }
                    
                    updateNotification("Error obteniendo ubicación")
                }
                // ⚠️ YA NO DETENEMOS EL SERVICIO - Se mantiene vivo permanentemente
                Log.d("LocationService-Foreground", "✅ Coordenadas obtenidas, servicio continúa activo")
            }.start()
        } else {
            Log.i("LocationService-Foreground", "🚀 INICIANDO SERVICIO GPS POR PRIMERA VEZ (llamado desde Flutter)")
            Log.i("LocationService-Foreground", "📱 Móvil: $movil | Usuario: $usuario | Escenario: $escenario")
            
            // 🆕 RESETEAR CONTADOR DE EJECUCIONES cuando se inicia desde Flutter
            val prefs = getSharedPreferences("gps_execution", Context.MODE_PRIVATE)
            prefs.edit().putInt("execution_counter", 1).apply()
            Log.i("LocationService-Foreground", "🔢 Contador de ejecuciones reseteado a 1")
            
            // 🔄 PROGRAMAR ALARMMANAGER CADA 30 SEGUNDOS
            val intervalMinutes = 0.5 // 🆕 30 segundos (0.5 minutos)
            
            Log.i("LocationService-Foreground", "⏰ Configurando sistema GPS:")
            Log.i("LocationService-Foreground", "   - Intervalo: 30 segundos")
            Log.i("LocationService-Foreground", "   - n8n webhook: CADA 30 segundos (SIEMPRE)")
            Log.i("LocationService-Foreground", "   - Riogas API: Cada 3 minutos (cada 6 ejecuciones)")
            
            // 1️⃣ AlarmManager cada 30 segundos
            LocationHelper.scheduleLocationAlarm(this, intervalMinutes, movil, escenario, usuario, deviceId)
            Log.i("LocationService-Foreground", "✅ AlarmManager programado: cada 30 segundos")
            
            // 2️⃣ WorkManager como BACKUP para cuando la app esté cerrada (15 min)
            try {
                WorkManagerHelper.schedulePeriodicLocationWork(this, 15, movil, escenario, usuario, deviceId)
                Log.d("LocationService-Foreground", "💼 WorkManager programado: cada 15 minutos (backup)")
            } catch (e: Exception) {
                Log.e("LocationService-Foreground", "❌ Error programando WorkManager: ${e.message}", e)
            }
            
            Log.d("LocationService-Foreground", "✅ Sistema híbrido activado: AlarmManager (${intervalMinutes}min) + WorkManager (15min)")
            
            // El servicio se mantiene activo permanentemente con notificación visible
        }

        // START_STICKY: Queremos que Android reinicie el servicio si lo mata
        // Esto mantiene el servicio vivo permanentemente
        return START_STICKY
    }

    private fun createNotification(): Notification {
        val channelId = "location_channel"
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        // 🔔 IMPORTANCE_DEFAULT para que sea más visible (pero sin sonido molesto)
        val channel = NotificationChannel(
            channelId, "Servicio de Ubicación", NotificationManager.IMPORTANCE_DEFAULT
        )
        channel.description = "Envío de coordenadas en segundo plano"
        channel.setSound(null, null)  // Sin sonido
        channel.enableVibration(false)  // Sin vibración
        manager.createNotificationChannel(channel)

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("🚚 RiogasDelivery is running in background")
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setOngoing(true)  // No se puede deslizar para cerrar
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }
    
    // 🆕 Método para actualizar la notificación con información dinámica
    private fun updateNotification(message: String) {
        try {
            val channelId = "location_channel"
            val notification = NotificationCompat.Builder(this, channelId)
                .setContentTitle("🚚 RiogasDelivery is running in background")
                .setSmallIcon(R.drawable.ic_launcher_foreground)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .build()
            
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(1710, notification)
            
            Log.d("LocationService-Foreground", "🔔 Notificación actualizada: $message")
        } catch (e: Exception) {
            Log.e("LocationService-Foreground", "❌ Error actualizando notificación: ${e.message}", e)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()

        // Registrar destrucción del servicio
        LocationLogger.logEvent(this, "FOREGROUND_SERVICE_DESTROYED", emptyMap())
        
        Log.w("LocationService-Foreground", "⚠️ Servicio destruido - Android lo mató o el usuario lo detuvo")

        // 🆕 Solo cancelar notificación si el servicio fue deshabilitado manualmente
        val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
        val isDisabled = prefs.getBoolean("service_disabled", false)
        
        if (isDisabled) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(1710)
            Log.d("LocationService-Foreground", "🔕 Notificación cancelada (servicio deshabilitado manualmente)")
        } else {
            Log.w("LocationService-Foreground", "⚠️ Servicio destruido pero no deshabilitado - Android lo reiniciará (START_STICKY)")
        }
    }

}
