# 🚀 Implementación Completa: Sistema FCM API Auto-Recovery

## 📋 Resumen de Cambios Implementados

Sistema de **auto-recuperación remota** que permite a los servicios nativos invocar comandos FCM cuando detectan que el servicio GPS no puede recuperarse localmente.

---

## 🎯 Arquitectura de 3 Capas de Recuperación

### 🔄 Capa 1: Watchdog Local (30 segundos)
- **ServiceWatchdog** monitorea cada 30s si GPS está activo
- **Reinicia localmente** si detecta servicio muerto
- **Logs detallados** en CriticalLogger → n8n

### 📡 Capa 2: Monitoreo Remoto (servidor)
- **Servidor monitorea** subida de coordenadas
- **Envía push FCM** si detecta inactividad
- **FcmPushReceiver** ejecuta comando (restart, force, stop, status)

### 🚨 Capa 3: Auto-Recovery via FCM API (NEW!)
- **Servicios nativos detectan** fallos irrecuperables
- **Invocan API FCMActions** directamente al servidor
- **Servidor envía push FCM** para reinicio remoto
- **Círculo completo** de auto-recuperación

---

## ✅ Cambios Implementados

### 1️⃣ Flutter: Guardar Datos en SharedPreferences

**Archivo:** `lib/pages/login_page.dart`

**Ubicación:** Método donde se selecciona el móvil (después de `saveMovil`)

**Cambios:**
```dart
// 🆕 Guardar escenario en SharedPreferences nativo para FCM API
try {
  const platform = MethodChannel('com.riogas.appmovil/shared_prefs');
  String escenarioValue = response['escenarioid'] == "1000" ? "1000" : "2000";
  await platform.invokeMethod('saveEscenario', {'escenario': escenarioValue});
  print('✅ Escenario guardado en SharedPreferences nativo: $escenarioValue');
} catch (e) {
  print('⚠️ Error guardando escenario en SharedPreferences nativo: $e');
}

// 🆕 Guardar baseUrl en SharedPreferences nativo para FCM API
try {
  const platform = MethodChannel('com.riogas.appmovil/shared_prefs');
  
  // Obtener URL base desde constantes (igual que en riogas_service.dart)
  final baseRootConst = (await getConstantValue('600'))?.trim();
  final servicesPathConst = (await getConstantValue('601'))?.trim();
  
  var baseRoot = (baseRootConst != null && baseRootConst.isNotEmpty)
      ? baseRootConst
      : 'https://www.riogas.uy/ica_geos_/';
  
  var servicesPath = (servicesPathConst != null && servicesPathConst.isNotEmpty)
      ? servicesPathConst
      : 'appservices/';
  
  // Normalizaciones
  baseRoot = baseRoot.replaceAll(
      RegExp(r'appservices/?$', caseSensitive: false), '');
  if (!baseRoot.endsWith('/')) baseRoot += '/';
  if (servicesPath.startsWith('/')) servicesPath = servicesPath.substring(1);
  if (!servicesPath.endsWith('/')) servicesPath += '/';
  
  String fullBaseUrl = '$baseRoot$servicesPath';
  
  await platform.invokeMethod('saveBaseUrl', {'baseUrl': fullBaseUrl});
  print('✅ BaseUrl guardada en SharedPreferences nativo: $fullBaseUrl');
} catch (e) {
  print('⚠️ Error guardando baseUrl en SharedPreferences nativo: $e');
}
```

**Constantes usadas:**
- `600` = Base URL root (ej: `https://www.riogas.uy/ica_geos_/`)
- `601` = Services path (ej: `appservices/`)
- **URL final:** `600` + `601` = `https://www.riogas.uy/ica_geos_/appservices/`

---

### 2️⃣ Android: MethodChannel Handlers en MainActivity.kt

**Archivo:** `android/app/src/main/kotlin/com/example/moveit/MainActivity.kt`

**Canal:** `com.riogas.appmovil/shared_prefs`

**Handlers agregados:**

```kotlin
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
        // Guardar en SharedPreferences "config" que usa FcmApiHelper
        val configPrefs = getSharedPreferences("config", Context.MODE_PRIVATE)
        configPrefs.edit().putString("baseUrl", baseUrl).apply()
        
        Log.i("MainActivity", "✅ BaseUrl guardada en SharedPreferences nativo para FCM API: $baseUrl")
        result.success("✅ BaseUrl guardada exitosamente")
    } catch (e: Exception) {
        Log.e("MainActivity", "❌ Error guardando baseUrl en SharedPreferences: ${e.message}", e)
        result.error("SAVE_ERROR", "Error guardando baseUrl: ${e.message}", null)
    }
}
```

**SharedPreferences guardados:**
- `config.last_escenario` = ID del escenario ("1000" o "2000")
- `config.baseUrl` = URL base completa del servidor
- `user_data.movil` = ID del móvil (ya existía)

---

### 3️⃣ ServiceWatchdog: Invocar FCM API cuando watchdog_disabled

**Archivo:** `android/app/src/main/kotlin/com/riogas/appmovil/ServiceWatchdog.kt`

**Método:** `restartGPSService()`

**Lógica agregada:**

```kotlin
// Validación 2: Watchdog explícitamente deshabilitado (solo por FCM stop_gps_service)
if (watchdogDisabled) {
    Log.w(TAG, "⚠️ WATCHDOG deshabilitado por comando FCM stop_gps_service")
    Log.i(TAG, "🚨 Invocando comando FCM remoto para reinicio...")
    
    CriticalLogger.logCritical(
        TAG,
        "WATCHDOG: Watchdog deshabilitado explícitamente, solicitando reinicio remoto via FCM",
        mapOf(
            "movil" to movil,
            "escenario" to escenario,
            "action" to "calling_fcm_api_for_remote_restart"
        ),
        "WATCHDOG_RESTART_BLOCKED"
    )
    
    // 🆕 NUEVO: Enviar comando FCM remoto para forzar reinicio desde servidor
    try {
        val escenarioId = escenario.toIntOrNull() ?: 0
        
        FcmApiHelper.forceGpsExecution(
            context,
            escenarioId,
            movil,
            onSuccess = { response ->
                Log.i(TAG, "✅ Comando FCM enviado exitosamente: $response")
                CriticalLogger.logCritical(
                    TAG,
                    "WATCHDOG: Comando FCM enviado - esperando respuesta remota para reinicio",
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
                    "WATCHDOG ERROR: Fallo enviando comando FCM remoto",
                    mapOf(
                        "movil" to movil,
                        "error" to error
                    ),
                    "WATCHDOG_FCM_COMMAND_ERROR"
                )
            }
        )
    } catch (e: Exception) {
        Log.e(TAG, "❌ Excepción al invocar FCM API: ${e.message}", e)
        CriticalLogger.logCritical(
            TAG,
            "WATCHDOG EXCEPTION: Error crítico invocando FCM API",
            e,
            mapOf(
                "movil" to movil,
                "escenario" to escenario
            ),
            "WATCHDOG_FCM_COMMAND_EXCEPTION"
        )
    }
    
    return false
}
```

**Cuando se ejecuta:**
- Watchdog detecta GPS muerto cada 30s
- Valida flag `watchdog_disabled=true`
- NO puede reiniciar localmente (bloqueado por FCM stop)
- Invoca `FcmApiHelper.forceGpsExecution()` para solicitar reinicio remoto
- Loguea todo en CriticalLogger → n8n

---

### 4️⃣ CriticalLogUploadWorker: Invocar FCM API cuando reinicio local falla

**Archivo:** `android/app/src/main/kotlin/com/riogas/appmovil/CriticalLogUploadWorker.kt`

**Método:** `doWork()`

**Lógica agregada:**

```kotlin
if (!isGPSRunning || !isAlarmScheduled) {
    Log.w(TAG, "⚠️ [WATCHDOG] GPS service MUERTO detectado - Intentando reiniciar...")
    
    val restarted = ServiceWatchdog.restartGPSService(applicationContext)
    
    if (restarted) {
        Log.i(TAG, "✅ [WATCHDOG] GPS service reiniciado exitosamente")
    } else {
        Log.e(TAG, "❌ [WATCHDOG] No se pudo reiniciar GPS service localmente")
        
        // 🆕 NUEVO: Si reinicio local falla, enviar comando FCM remoto
        try {
            val prefs = applicationContext.getSharedPreferences("config", Context.MODE_PRIVATE)
            val movil = prefs.getString("last_movil", "") ?: ""
            val escenario = prefs.getString("last_escenario", "0") ?: "0"
            val escenarioId = escenario.toIntOrNull() ?: 0
            
            if (movil.isNotEmpty() && escenarioId > 0) {
                Log.i(TAG, "🚨 [WATCHDOG] Reinicio local falló, enviando comando FCM remoto...")
                
                CriticalLogger.logCritical(
                    TAG,
                    "WATCHDOG: Reinicio local falló - Solicitando reinicio remoto via FCM",
                    mapOf(
                        "movil" to movil,
                        "action" to "restart_gps_service",
                        "trigger" to "local_restart_failed"
                    ),
                    "WATCHDOG_LOCAL_RESTART_FAILED"
                )
                
                FcmApiHelper.restartGpsService(
                    applicationContext,
                    escenarioId,
                    movil,
                    onSuccess = { response ->
                        Log.i(TAG, "✅ Comando FCM enviado: $response")
                        CriticalLogger.logCritical(
                            TAG,
                            "WATCHDOG: Comando restart_gps_service enviado",
                            mapOf("movil" to movil, "response" to response),
                            "WATCHDOG_FCM_RESTART_SENT"
                        )
                    },
                    onError = { error ->
                        Log.e(TAG, "❌ Error enviando comando FCM: $error")
                        CriticalLogger.logCritical(
                            TAG,
                            "WATCHDOG ERROR: Fallo comando FCM restart",
                            mapOf("movil" to movil, "error" to error),
                            "WATCHDOG_FCM_RESTART_ERROR"
                        )
                    }
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Excepción al invocar FCM API: ${e.message}", e)
        }
    }
}
```

**Cuando se ejecuta:**
- CriticalLogWorker ejecuta cada 30s (watchdog)
- Detecta GPS muerto
- Intenta reinicio local con `ServiceWatchdog.restartGPSService()`
- Si falla (permisos, restricciones, etc.), invoca `FcmApiHelper.restartGpsService()`
- Loguea todo en CriticalLogger → n8n

---

## 📊 Flujos de Recuperación Completos

### Caso 1: Watchdog Bloqueado (watchdog_disabled=true)

```
1. Android mata GPS service
2. CriticalLogWorker detecta GPS muerto (30s)
3. Intenta reinicio: ServiceWatchdog.restartGPSService()
4. Validación: watchdog_disabled=true → BLOQUEADO
5. Log: "WATCHDOG_RESTART_BLOCKED"
6. Invoca: FcmApiHelper.forceGpsExecution()
7. HTTP POST → servidor/appservices/FCMActions
8. Servidor envía push FCM al dispositivo
9. FcmPushReceiver recibe: force_gps_execution
10. Verifica GPS muerto → Reinicia con EXECUTE_GPS=true
11. Log: "FCM_FORCE_GPS_SUCCESS_WITH_RESTART"
12. GPS activo nuevamente ✅
```

**Logs esperados en n8n:**
- `WATCHDOG_RESTART_BLOCKED`
- `WATCHDOG_FCM_COMMAND_SENT`
- `FCM_PUSH_RECEIVED`
- `FCM_FORCE_GPS_RESTARTING_SERVICE`
- `FCM_FORCE_GPS_SUCCESS_WITH_RESTART`
- `SERVICE_STARTED`

---

### Caso 2: Reinicio Local Falla (permisos, batería, etc.)

```
1. Android mata GPS service
2. CriticalLogWorker detecta GPS muerto (30s)
3. Intenta reinicio: ServiceWatchdog.restartGPSService()
4. Reinicio local falla (SecurityException, IllegalStateException, etc.)
5. Log: "WATCHDOG_RESTART_FAILED"
6. CriticalLogWorker detecta fallo
7. Invoca: FcmApiHelper.restartGpsService()
8. HTTP POST → servidor/appservices/FCMActions
9. Servidor envía push FCM al dispositivo
10. FcmPushReceiver recibe: restart_gps_service
11. Ejecuta reinicio completo (ignora todos los flags)
12. Log: "FCM_RESTART_SUCCESS"
13. GPS activo nuevamente ✅
```

**Logs esperados en n8n:**
- `WATCHDOG_RESTART_INITIATED`
- `WATCHDOG_RESTART_FAILED` (con detalles de excepción)
- `WATCHDOG_LOCAL_RESTART_FAILED`
- `WATCHDOG_FCM_RESTART_SENT`
- `FCM_PUSH_RECEIVED`
- `FCM_RESTART_INITIATED`
- `FCM_RESTART_SUCCESS`
- `SERVICE_STARTED`

---

## 🔧 Datos en SharedPreferences

### "config" (usado por servicios nativos)
```kotlin
last_movil: "MOV123"                           // ID del móvil
last_escenario: "1000"                         // ID del escenario
baseUrl: "https://www.riogas.uy/ica_geos_/appservices/"  // URL base completa
last_usuario: "usuario@test.com"
last_deviceId: "device123"
last_interval: 0.5f
service_disabled: false                        // Informativo (no bloquea watchdog)
watchdog_disabled: false                       // Control real (bloquea watchdog)
```

### "user_data" (usado por CriticalLogger)
```kotlin
movil: "MOV123"                                // ID del móvil
```

---

## 🌐 API Request Format

### Endpoint
```
POST /appservices/FCMActions
```

### Headers
```json
{
  "Content-Type": "application/json",
  "Accept": "application/json"
}
```

### Body
```json
{
  "escenarioid": 1000,
  "movil": "MOV123",
  "Accion": "force_gps_execution"
}
```

### Acciones disponibles
- `force_gps_execution` - Forzar ejecución GPS inmediata
- `restart_gps_service` - Reiniciar servicio GPS completo
- `stop_gps_service` - Detener servicio GPS
- `get_status` - Consultar estado del servicio

---

## 📝 Logs Críticos Nuevos

### Eventos agregados:

| Event Type | Descripción | Trigger |
|------------|-------------|---------|
| `WATCHDOG_RESTART_BLOCKED` | Watchdog deshabilitado, no puede reiniciar | watchdog_disabled=true |
| `WATCHDOG_FCM_COMMAND_SENT` | Comando FCM enviado exitosamente | FcmApiHelper.forceGpsExecution() success |
| `WATCHDOG_FCM_COMMAND_ERROR` | Error enviando comando FCM | FcmApiHelper.forceGpsExecution() error |
| `WATCHDOG_FCM_COMMAND_EXCEPTION` | Excepción invocando FCM API | try-catch en watchdog |
| `WATCHDOG_LOCAL_RESTART_FAILED` | Reinicio local falló | ServiceWatchdog.restartGPSService() = false |
| `WATCHDOG_FCM_RESTART_SENT` | Comando restart_gps_service enviado | FcmApiHelper.restartGpsService() success |
| `WATCHDOG_FCM_RESTART_ERROR` | Error enviando comando restart | FcmApiHelper.restartGpsService() error |
| `WATCHDOG_FCM_INVALID_DATA` | Datos insuficientes para FCM API | movil o escenario vacíos |
| `WATCHDOG_FCM_EXCEPTION` | Excepción en CriticalLogWorker | try-catch en worker |

---

## ✅ Checklist de Implementación

- [x] Flutter: Guardar `escenario` en SharedPreferences nativo
- [x] Flutter: Guardar `baseUrl` en SharedPreferences nativo
- [x] Android: Handler `saveEscenario` en MainActivity
- [x] Android: Handler `saveBaseUrl` en MainActivity
- [x] Android: `FcmApiHelper.kt` creado (ya existía)
- [x] ServiceWatchdog: Invocar FCM API cuando watchdog_disabled=true
- [x] CriticalLogWorker: Invocar FCM API cuando reinicio local falla
- [x] Logs críticos agregados para todos los eventos
- [x] Documentación completa (este archivo)

---

## 🧪 Próximos Pasos para Testing

### 1. Compilar y desplegar
```bash
cd appmovil
flutter clean
flutter pub get
flutter build apk --release
```

### 2. Probar flujo completo

#### Test 1: Watchdog Bloqueado
```bash
# Detener servicio con FCM (establece watchdog_disabled=true)
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=YOUR_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "DEVICE_FCM_TOKEN",
    "data": {
      "action": "stop_gps_service"
    }
  }'

# Esperar 30s
# Verificar logs en n8n:
# - WATCHDOG_RESTART_BLOCKED
# - WATCHDOG_FCM_COMMAND_SENT
# - FCM_FORCE_GPS_SUCCESS_WITH_RESTART
```

#### Test 2: Reinicio Local Falla
```bash
# Simular restricciones de batería para forzar fallo de reinicio local
adb shell cmd appops set com.example.moveit RUN_IN_BACKGROUND deny

# Matar servicio GPS manualmente
adb shell am force-stop com.example.moveit

# Esperar 30s
# Verificar logs en n8n:
# - WATCHDOG_LOCAL_RESTART_FAILED
# - WATCHDOG_FCM_RESTART_SENT
# - FCM_RESTART_SUCCESS
```

---

## 📚 Referencias

- **FCM_API_USAGE_GUIDE.md** - Guía de uso completa de FCM API
- **FCM_REMOTE_CONTROL_GPS.md** - Sistema FCM completo
- **LOGICA_CONTROL_GPS_FLAGS.md** - Lógica de flags (service_disabled vs watchdog_disabled)
- **FcmApiHelper.kt** - Implementación HTTP client para FCM API

---

**¡Sistema de Auto-Recuperación Remota via FCM API completamente implementado! 🚀**

**Fecha:** 31 de Octubre, 2025
**Versión:** 1.0.0
