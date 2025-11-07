# 🚨 API FCMActions - Invocar Comandos FCM desde Servicios Nativos

## 📋 Descripción

Sistema que permite a los **servicios nativos Android** (ForegroundLocationService, CriticalLogger, ServiceWatchdog) invocar comandos FCM remotos cuando detectan que el servicio GPS no responde o no puede auto-recuperarse.

---

## 🎯 Propósito

Cuando los servicios nativos detectan problemas que no pueden resolver localmente (watchdog deshabilitado, servicio muerto sin permisos para reiniciar, etc.), **envían un comando al servidor** para que éste envíe un push FCM al dispositivo y reactive el servicio remotamente.

---

## 🔄 Flujo Completo

```
1. Servicio nativo detecta problema (ej: GPS no responde)
2. Servicio llama FcmApiHelper.forceGpsExecution()
3. Helper HTTP POST → servidor/appservices/FCMActions
4. Servidor procesa request y envía push FCM al dispositivo
5. FcmPushReceiver recibe push y ejecuta acción (restart, force, etc.)
6. Servicio GPS se reactiva automáticamente
7. Todo se loguea en CriticalLogger → n8n
```

---

## 📦 Componentes Implementados

### 1️⃣ Flutter: `RioGasService.fcmActions()` 
**Ubicación:** `lib/services/riogas_service.dart`

```dart
/// Invocar acción remota via FCM
static Future<Map<String, dynamic>?> fcmActions({
  required int escenarioId,
  required String movil,
  required String accion, // force_gps_execution, restart_gps_service, stop_gps_service, get_status
}) async {
  return _post('FCMActions', {
    'escenarioid': escenarioId,
    'movil': movil,
    'Accion': accion,
  });
}
```

### 2️⃣ Kotlin: `FcmApiHelper` 
**Ubicación:** `android/app/src/main/kotlin/com/riogas/appmovil/FcmApiHelper.kt`

```kotlin
object FcmApiHelper {
    // Método genérico
    fun sendFcmAction(
        context: Context,
        escenarioId: Int,
        movil: String,
        accion: String, // force_gps_execution, restart_gps_service, stop_gps_service, get_status
        onSuccess: ((String) -> Unit)? = null,
        onError: ((String) -> Unit)? = null
    )
    
    // Helpers rápidos
    fun forceGpsExecution(context, escenarioId, movil, onSuccess, onError)
    fun restartGpsService(context, escenarioId, movil, onSuccess, onError)
}
```

---

## 🚀 Uso desde Servicios Nativos

### Ejemplo 1: ServiceWatchdog detecta servicio muerto

```kotlin
// En ServiceWatchdog.kt cuando detecta que el servicio está muerto
// y watchdog_disabled=true (no puede reiniciar localmente)

fun restartGPSService(context: Context): Boolean {
    val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
    val watchdogDisabled = prefs.getBoolean("watchdog_disabled", false)
    
    if (watchdogDisabled) {
        Log.w(TAG, "⚠️ Watchdog deshabilitado, solicitando reinicio remoto via FCM")
        
        val movil = prefs.getString("last_movil", "") ?: ""
        val escenario = prefs.getString("last_escenario", "0") ?: "0"
        
        // 🆕 Enviar comando FCM al servidor
        FcmApiHelper.forceGpsExecution(
            context,
            escenarioId = escenario.toIntOrNull() ?: 0,
            movil = movil,
            onSuccess = { response ->
                Log.i(TAG, "✅ Comando FCM enviado exitosamente: $response")
                CriticalLogger.logCritical(
                    TAG,
                    "WATCHDOG: Comando FCM enviado - esperando respuesta remota",
                    mapOf(
                        "movil" to movil,
                        "action" to "force_gps_execution",
                        "trigger" to "watchdog_disabled"
                    ),
                    "WATCHDOG_FCM_COMMAND_SENT"
                )
            },
            onError = { error ->
                Log.e(TAG, "❌ Error enviando comando FCM: $error")
                CriticalLogger.logCritical(
                    TAG,
                    "WATCHDOG ERROR: Fallo enviando comando FCM",
                    mapOf(
                        "movil" to movil,
                        "error" to error,
                        "action" to "force_gps_execution"
                    ),
                    "WATCHDOG_FCM_COMMAND_ERROR"
                )
            }
        )
        
        return false // No reinició localmente, esperando comando FCM
    }
    
    // ... resto del código de reinicio local
}
```

---

### Ejemplo 2: CriticalLogger detecta servicio GPS no reportando

```kotlin
// En CriticalLogUploadWorker cuando detecta que GPS no reporta hace tiempo

class CriticalLogUploadWorker(context: Context, params: WorkerParameters) 
    : Worker(context, params) {
    
    override fun doWork(): Result {
        // ... código existente ...
        
        // Verificar si GPS está saludable
        val isGpsHealthy = ServiceWatchdog.isGPSServiceRunning(applicationContext)
        
        if (!isGpsHealthy) {
            Log.w(TAG, "⚠️ GPS service no saludable, intentando reinicio")
            
            val restarted = ServiceWatchdog.restartGPSService(applicationContext)
            
            if (!restarted) {
                // No pudo reiniciar localmente, enviar comando FCM
                val prefs = applicationContext.getSharedPreferences("config", Context.MODE_PRIVATE)
                val movil = prefs.getString("last_movil", "") ?: ""
                val escenario = prefs.getString("last_escenario", "0") ?: "0"
                
                Log.i(TAG, "🚨 Reinicio local falló, enviando comando FCM remoto")
                
                FcmApiHelper.restartGpsService(
                    applicationContext,
                    escenarioId = escenario.toIntOrNull() ?: 0,
                    movil = movil,
                    onSuccess = { response ->
                        Log.i(TAG, "✅ Comando restart_gps_service enviado")
                    },
                    onError = { error ->
                        Log.e(TAG, "❌ Error enviando restart: $error")
                    }
                )
            }
        }
        
        return Result.success()
    }
}
```

---

### Ejemplo 3: ForegroundLocationService detecta fallo crítico

```kotlin
// En ForegroundLocationService cuando detecta error crítico que no puede resolver

class ForegroundLocationService : Service() {
    
    private fun handleCriticalFailure(reason: String) {
        Log.e(TAG, "🔴 Fallo crítico detectado: $reason")
        
        val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
        val movil = prefs.getString("last_movil", "") ?: ""
        val escenario = prefs.getString("last_escenario", "0") ?: "0"
        
        CriticalLogger.logCritical(
            TAG,
            "GPS SERVICE: Fallo crítico detectado - solicitando ayuda remota",
            mapOf(
                "movil" to movil,
                "reason" to reason,
                "action" to "requesting_remote_restart"
            ),
            "GPS_SERVICE_CRITICAL_FAILURE"
        )
        
        // Enviar comando FCM para reinicio remoto
        FcmApiHelper.restartGpsService(
            this,
            escenarioId = escenario.toIntOrNull() ?: 0,
            movil = movil,
            onSuccess = { response ->
                Log.i(TAG, "✅ Comando restart solicitado al servidor")
            },
            onError = { error ->
                Log.e(TAG, "❌ Última esperanza falló: $error")
                // Aquí ya no hay nada más que hacer, esperar intervención manual
            }
        )
    }
}
```

---

## 📊 Logs Esperados en n8n

### Secuencia Completa: Watchdog → FCM API → FCM Push → Servicio Reiniciado

```
1. WATCHDOG_RESTART_BLOCKED
   → watchdog_disabled=true, no puede reiniciar localmente

2. FCM_API_COMMAND_SENT
   → Comando force_gps_execution enviado al servidor
   
3. [Servidor procesa y envía push FCM]

4. FCM_PUSH_RECEIVED
   → FcmPushReceiver recibe el push
   
5. FCM_FORCE_GPS_RESTARTING_SERVICE
   → Servicio estaba muerto, reiniciando
   
6. FCM_FORCE_GPS_SUCCESS_WITH_RESTART
   → Servicio reiniciado + GPS ejecutado
   
7. SERVICE_STARTED
   → ForegroundLocationService activo nuevamente
   
8. GPS_LOCATION_OBTAINED
   → Coordenadas obtenidas y enviadas
```

---

## ⚙️ Configuración Requerida

### En SharedPreferences "config":
```kotlin
baseUrl: "https://www.riogas.uy/ica_geos_/"  // Base URL del servidor
last_movil: "MOV123"                          // ID del móvil
last_escenario: "1"                           // ID del escenario
```

### En el Servidor:
```
Endpoint: POST /appservices/FCMActions

Body:
{
  "escenarioid": 1,
  "movil": "MOV123",
  "Accion": "force_gps_execution"  // o restart_gps_service, stop_gps_service, get_status
}

Respuesta esperada: 200 OK
```

---

## 🔐 Validaciones y Seguridad

### Validaciones en FcmApiHelper:
- ✅ Verifica que baseUrl esté configurado
- ✅ Normaliza URL (quita duplicados de appservices/)
- ✅ Timeout de 15 segundos (connectTimeout y readTimeout)
- ✅ Loguea todo en CriticalLogger (éxitos y errores)
- ✅ Manejo de errores HTTP y excepciones de red
- ✅ Ejecución en coroutine (no bloquea hilo principal)

### Validaciones en el Servidor:
- ✅ Verificar que el móvil existe en la base de datos
- ✅ Validar que el escenario es válido
- ✅ Verificar que el dispositivo tiene un FCM token activo
- ✅ Rate limiting para evitar spam de comandos

---

## 🚨 Casos de Uso

### Caso 1: Watchdog Bloqueado
**Situación:**
- Servicio GPS muere
- `watchdog_disabled=true` (bloqueado por FCM stop_gps_service)
- Watchdog no puede reiniciar localmente

**Solución:**
1. Watchdog detecta servicio muerto
2. Loguea `WATCHDOG_RESTART_BLOCKED`
3. Llama `FcmApiHelper.forceGpsExecution()`
4. Servidor envía push FCM
5. FcmPushReceiver reinicia servicio
6. Loguea `FCM_FORCE_GPS_SUCCESS_WITH_RESTART`

---

### Caso 2: GPS No Reporta Hace Tiempo
**Situación:**
- CriticalLogUploadWorker detecta GPS no saludable
- Reinicio local falla (sin permisos, optimización batería, etc.)

**Solución:**
1. CriticalLogUploadWorker intenta reinicio local
2. Reinicio local falla
3. Loguea `CRITICAL_LOG_WORKER_RESTART_FAILED`
4. Llama `FcmApiHelper.restartGpsService()`
5. Servidor envía push FCM
6. FcmPushReceiver reinicia servicio completo

---

### Caso 3: Error Crítico en ForegroundLocationService
**Situación:**
- ForegroundLocationService encuentra error irrecuperable
- No puede continuar funcionando

**Solución:**
1. Servicio detecta fallo crítico
2. Loguea `GPS_SERVICE_CRITICAL_FAILURE`
3. Llama `FcmApiHelper.restartGpsService()`
4. Servicio se detiene
5. Servidor envía push FCM
6. FcmPushReceiver reinicia servicio limpio

---

## 📝 Ejemplo de Request HTTP

```http
POST https://www.riogas.uy/ica_geos_/appservices/FCMActions
Content-Type: application/json
Accept: application/json

{
  "escenarioid": 1,
  "movil": "MOV123",
  "Accion": "force_gps_execution"
}
```

**Respuesta Exitosa:**
```json
{
  "status": "success",
  "message": "FCM command sent to device MOV123",
  "fcm_message_id": "0:1761924252037062%12bee5cdf9fd7ecd"
}
```

**Respuesta Error:**
```json
{
  "status": "error",
  "message": "Device not found or no FCM token",
  "code": 404
}
```

---

## ✅ Checklist de Implementación

- [x] API `FCMActions` agregada en `RioGasService.dart`
- [x] Helper `FcmApiHelper.kt` creado en Android
- [x] Logging completo en CriticalLogger
- [x] Manejo de errores HTTP y excepciones
- [x] Timeout configurado (15s)
- [x] Callbacks de éxito/error
- [x] Helpers rápidos (`forceGpsExecution`, `restartGpsService`)
- [ ] Integrar en ServiceWatchdog
- [ ] Integrar en CriticalLogUploadWorker
- [ ] Integrar en ForegroundLocationService (opcional)
- [ ] Probar flujo completo end-to-end
- [ ] Verificar logs en n8n

---

## 🎓 Próximos Pasos

1. **Integrar en ServiceWatchdog:**
   - Cuando `watchdog_disabled=true`, llamar `FcmApiHelper.forceGpsExecution()`
   
2. **Integrar en CriticalLogUploadWorker:**
   - Si reinicio local falla, llamar `FcmApiHelper.restartGpsService()`
   
3. **Probar secuencia completa:**
   - Detener servicio con FCM `stop_gps_service`
   - Esperar que watchdog detecte servicio muerto
   - Verificar que watchdog envíe comando FCM
   - Confirmar que FcmPushReceiver reinicia servicio
   - Revisar logs en n8n

4. **Monitorear en producción:**
   - Ver frecuencia de uso de FCM API
   - Detectar patrones de fallo
   - Ajustar timeouts si necesario

---

**¡Sistema de Auto-Recuperación Remota via FCM API implementado! 🚀**
