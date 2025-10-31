# ✅ IMPLEMENTACIÓN COMPLETADA: Sistema de CriticalLogger

## 🎯 Objetivo

Crear un sistema de logging de **errores críticos** que se envíe **SIEMPRE a n8n**, independientemente de si `debugMode` está activado o no.

---

## 📦 Archivos Creados

### 1. **CriticalLogger.kt** 
📍 `android/app/src/main/kotlin/com/riogas/appmovil/CriticalLogger.kt`

**Características:**
- ✅ Se ejecuta SIEMPRE (no depende de `debugMode`)
- ✅ Buffer circular de 50 logs críticos
- ✅ Niveles: Solo errores críticos
- ✅ Thread-safe con `ReentrantReadWriteLock`
- ✅ Exporta a JSON para envío a n8n
- ✅ Genera snapshots del sistema (batería, GPS, permisos)

**Métodos principales:**
```kotlin
CriticalLogger.logCritical(
    tag: String,
    message: String,
    extras: Map<String, Any> = emptyMap(),
    errorType: String = "CRITICAL"
)

CriticalLogger.logCritical(
    tag: String,
    message: String,
    throwable: Throwable,
    extras: Map<String, Any> = emptyMap(),
    errorType: String = "CRITICAL"
)
```

**Tipos de errores soportados:**
- `SERVICE_START_FAILED` - No se puede iniciar servicio GPS
- `API_ERROR` - Error HTTP en API de Riogas
- `API_MAX_RETRIES` - Máximo de reintentos alcanzado
- `API_CONNECTION_ERROR` - Sin internet o timeout
- `GPS_ERROR` - Error obteniendo ubicación
- `CRITICAL` - Error genérico crítico

---

### 2. **CriticalLogUploadWorker.kt**
📍 `android/app/src/main/kotlin/com/riogas/appmovil/CriticalLogUploadWorker.kt`

**Características:**
- ✅ WorkManager periódico cada 15 minutos
- ✅ Se ejecuta SIEMPRE (no depende de `debugMode`)
- ✅ Envía logs a n8n webhook
- ✅ Limpia buffer después de envío exitoso
- ✅ Genera snapshot del sistema después de limpiar
- ✅ Retry automático si falla el envío

**Métodos principales:**
```kotlin
CriticalLogUploadWorker.schedule(context)
CriticalLogUploadWorker.cancel(context)
```

---

## 🔧 Modificaciones en Archivos Existentes

### 1. **MainActivity.kt**

#### **Inicialización (onCreate):**
```kotlin
// Inicializar CriticalLogger (SIEMPRE activo)
com.riogas.appmovil.CriticalLogger.init(applicationContext)

// Programar envío automático cada 15 minutos
com.riogas.appmovil.CriticalLogUploadWorker.schedule(applicationContext)
```

#### **checkAndRestartLocationService() - línea 492:**
Agregado **try-catch** en `startForegroundService()`:
```kotlin
try {
    startForegroundService(serviceIntent)
} catch (e: SecurityException) {
    CriticalLogger.logCritical("MainActivity", "ERROR: Sin permisos...", e, ...)
    result.success(mapOf("status" to "error", "error" to "SecurityException"))
    return
} catch (e: IllegalStateException) {
    CriticalLogger.logCritical("MainActivity", "ERROR: Bloqueado por restrictions...", e, ...)
    // ...
}
```

#### **restartLocationServiceFromForeground() - línea 740:**
Agregado **try-catch** similar al anterior.

**Errores capturados:**
- ✅ `SecurityException` - Sin permisos FOREGROUND_SERVICE_LOCATION
- ✅ `IllegalStateException` - Background restrictions (Android 12+)
- ✅ `Exception` genérica - Cualquier otro error desconocido

---

### 2. **ForegroundLocationService.kt**

#### **onStartCommand() - línea 12:**
Agregado **try-catch** en `startForeground()`:
```kotlin
try {
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
        startForeground(1710, createNotification(), FOREGROUND_SERVICE_TYPE_LOCATION)
    } else {
        startForeground(1710, createNotification())
    }
    
    // Log exitoso
    CriticalLogger.logCritical("ForegroundLocationService", "Servicio GPS iniciado exitosamente", ...)
    
} catch (e: SecurityException) {
    CriticalLogger.logCritical("ForegroundLocationService", "ERROR: Sin permiso...", e, ...)
    stopSelf()
    return START_NOT_STICKY
}
```

**Errores capturados:**
- ✅ `SecurityException` - Sin permiso de notificación o FOREGROUND_SERVICE_LOCATION
- ✅ `Exception` genérica - Cualquier otro error

---

### 3. **LocationHelper.kt**

#### **getCurrentLocation() - línea 430:**
Agregado **try-catch** en `context.startForegroundService()`:
```kotlin
try {
    context.startForegroundService(serviceIntent)
    // ...
} catch (e: SecurityException) {
    CriticalLogger.logCritical(TAG, "ERROR: Sin permisos desde LocationHelper", e, ...)
} catch (e: IllegalStateException) {
    CriticalLogger.logCritical(TAG, "ERROR: Bloqueado por restrictions...", e, ...)
}
```

#### **invokeRegistrarCoordenadasApiWithRetry() - línea 1220:**
Agregado **CriticalLogger** para errores de API:

**Errores HTTP (response.code != 200):**
```kotlin
if (!response.isSuccessful) {
    // DebugLogger (solo si debugMode=true)
    DebugLogger.w(TAG, "API call fallida", ...)
    
    // CriticalLogger (SIEMPRE, independiente de debugMode)
    CriticalLogger.logCritical(
        TAG,
        "ERROR API: No se pudo enviar coordenadas al servidor",
        mapOf(
            "movil" to movil,
            "httpCode" to response.code,
            "httpMessage" to response.message,
            "responseBody" to errorBody.take(200),
            "lat" to lat,
            "lon" to lon
        ),
        "API_ERROR"
    )
}
```

**Máximo de reintentos alcanzado:**
```kotlin
if (currentAttempt >= maxRetries - 1) {
    CriticalLogger.logCritical(
        TAG,
        "ERROR CRÍTICO: Máximo de reintentos alcanzado - Coordenadas NO enviadas",
        mapOf(
            "movil" to movil,
            "maxRetries" to maxRetries,
            "lastHttpCode" to response.code,
            "lat" to lat,
            "lon" to lon
        ),
        "API_MAX_RETRIES"
    )
}
```

**Errores de conexión (timeout, sin internet):**
```kotlin
catch (e: Exception) {
    CriticalLogger.logCritical(
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
}
```

---

### 4. **LocationReceiver.kt**

#### **onReceive() - línea 114:**
Agregado **try-catch** en `context.startForegroundService()`:
```kotlin
try {
    context.startForegroundService(serviceIntent)
    Log.d("LocationReceiver", "✅ Servicio GPS iniciado desde AlarmManager")
    
} catch (e: SecurityException) {
    CriticalLogger.logCritical("LocationReceiver", "ERROR: Sin permisos desde AlarmManager", e, ...)
    return
} catch (e: IllegalStateException) {
    CriticalLogger.logCritical("LocationReceiver", "ERROR: Bloqueado por restrictions...", e, ...)
    return
}
```

---

## 📊 Comparativa: DebugLogger vs CriticalLogger

| Aspecto | DebugLogger | CriticalLogger |
|---------|-------------|----------------|
| **Activación** | Solo si debugMode=true | SIEMPRE activo |
| **Uso** | Debug general (info, warn, error) | Solo ERRORES CRÍTICOS |
| **Buffer** | 100 logs | 50 logs |
| **Frecuencia envío** | 10-15 min (WorkManager) | 15 min (WorkManager) |
| **Webhook n8n** | Mismo URL | Mismo URL |
| **Propósito** | Diagnóstico temporal detallado | Monitoreo permanente de salud |
| **Tipos de logs** | INFO, WARN, ERROR | Solo CRITICAL (errores graves) |

---

## 🎯 Logs Críticos Implementados

### **1. Servicio GPS no puede iniciar:**
```
❌ SERVICE_START_FAILED
Contextos:
- checkAndRestartLocationService (health check desde pedidos)
- restartLocationServiceFromForeground (onCreate MainActivity)
- getCurrentLocation (LocationHelper)
- AlarmManager trigger (LocationReceiver)

Causas detectadas:
- SecurityException (sin permisos)
- IllegalStateException (background restrictions)
- Exception genérica (cualquier otro error)
```

### **2. API de Riogas falla:**
```
❌ API_ERROR
- HTTP 400, 500, 503, etc.
- Incluye código HTTP, mensaje, responseBody

❌ API_MAX_RETRIES
- Se alcanzó el máximo de reintentos (3 intentos)
- Coordenadas NO fueron enviadas al servidor

❌ API_CONNECTION_ERROR
- Sin internet, timeout, DNS error
- Incluye excepción completa
```

### **3. Servicio GPS inicia exitosamente:**
```
✅ SERVICE_STARTED
- Se loguea cuando startForeground() tiene éxito
- Confirma que el servicio está activo
```

---

## 🚀 Flujo de Funcionamiento

### **Ciclo de Vida de Logs Críticos:**

```
1. Error ocurre (ej: startForegroundService falla)
   ↓
2. CriticalLogger.logCritical() captura el error
   ↓
3. Log se agrega al buffer circular (max 50)
   ↓
4. WorkManager ejecuta cada 15 minutos
   ↓
5. CriticalLogUploadWorker.doWork()
   ↓
6. Si hay logs: Envía JSON a n8n webhook
   ↓
7. Si HTTP 200: Limpia buffer + genera snapshot
   ↓
8. Si falla: Reintentar (logs NO se pierden)
```

### **Ejemplo de JSON enviado a n8n:**
```json
{
  "critical_logs": [
    {
      "timestamp": 1730304000000,
      "datetime": "2025-10-30 10:00:00.000",
      "tag": "MainActivity",
      "message": "ERROR: Sin permisos para iniciar servicio GPS",
      "errorType": "SERVICE_START_FAILED",
      "extras": {
        "movil": "693",
        "android_version": "33",
        "context": "checkAndRestartLocationService",
        "error": "SecurityException",
        "errorMessage": "Permission denied",
        "stackTrace": "..."
      }
    },
    {
      "timestamp": 1730304120000,
      "datetime": "2025-10-30 10:02:00.000",
      "tag": "LocationHelper",
      "message": "ERROR API: No se pudo enviar coordenadas al servidor",
      "errorType": "API_ERROR",
      "extras": {
        "movil": "693",
        "httpCode": "500",
        "httpMessage": "Internal Server Error",
        "responseBody": "{\"error\":\"Database unavailable\"}",
        "lat": "-34.1234",
        "lon": "-56.5678"
      }
    }
  ],
  "metadata": {
    "timestamp": 1730304180000,
    "count": 2,
    "system": "CriticalLogger",
    "version": "1.0",
    "android_version": 33
  }
}
```

---

## 🧪 Testing

### **Paso 1: Verificar inicialización**
```bash
adb logcat | Select-String "CriticalLogger"
```

**Logs esperados:**
```
✅ CriticalLogger inicializado (SIEMPRE activo)
✅ CriticalLogUploadWorker programado (cada 15 min)
```

---

### **Paso 2: Provocar error de servicio (revocar permisos)**
```bash
# Revocar permiso de ubicación
adb shell pm revoke com.example.moveit android.permission.ACCESS_FINE_LOCATION

# Intentar descargar pedidos (debería fallar al iniciar servicio)
```

**Logs esperados:**
```
❌ SecurityException iniciando servicio GPS
🚨 [CRITICAL] ERROR: Sin permisos para iniciar servicio GPS
```

---

### **Paso 3: Verificar envío a n8n**
```bash
# Monitorear WorkManager
adb logcat | Select-String "CriticalLogUploadWorker"
```

**Logs esperados (después de 15 minutos):**
```
🚀 Iniciando envío de logs críticos...
📦 Preparando envío de 2 logs críticos...
🌐 Enviando 2 logs críticos a n8n...
✅ Logs críticos enviados exitosamente
   - HTTP Code: 200
   - Logs enviados: 2
   - Tiempo: 245ms
🧹 Buffer de logs críticos limpiado
```

---

### **Paso 4: Provocar error de API (simular HTTP 500)**
```bash
# Desconectar internet del dispositivo
adb shell svc data disable
adb shell svc wifi disable

# Esperar trigger de AlarmManager (cada 3 minutos)
```

**Logs esperados:**
```
❌ Error de conexión: Unable to resolve host
🚨 [CRITICAL] ERROR CRÍTICO: Error de conexión al API - Sin internet o timeout
```

---

## ✅ Checklist de Implementación

- [x] `CriticalLogger.kt` creado
- [x] `CriticalLogUploadWorker.kt` creado
- [x] CriticalLogger inicializado en `MainActivity.onCreate()`
- [x] CriticalLogUploadWorker programado en `MainActivity.onCreate()`
- [x] try-catch en `MainActivity.checkAndRestartLocationService()`
- [x] try-catch en `MainActivity.restartLocationServiceFromForeground()`
- [x] try-catch en `ForegroundLocationService.onStartCommand()`
- [x] try-catch en `LocationHelper.getCurrentLocation()`
- [x] try-catch en `LocationReceiver.onReceive()`
- [x] CriticalLogger en errores de API (HTTP errors)
- [x] CriticalLogger en máximo de reintentos
- [x] CriticalLogger en errores de conexión
- [ ] Compilar APK con cambios
- [ ] Probar en dispositivo real
- [ ] Verificar logs en n8n sin debugMode=true

---

## 📝 Próximos Pasos

### **1. Compilar APK**
```powershell
cd C:\Users\jgomez\Documents\Projects\AppTFlutter\appmovil
flutter build apk --release
```

### **2. Instalar en dispositivo de prueba**
```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### **3. Monitorear logs críticos**
```bash
adb logcat | Select-String "CriticalLogger|CriticalLogUploadWorker|CRITICAL"
```

### **4. Verificar en n8n**
- Acceder al webhook: https://jgomezweb.com.uy/webhook/8f3fb866-b0b2-4bd8-bdbb-7a5ee7e0aaa3
- Verificar que lleguen logs críticos cada 15 minutos
- Confirmar que se envían SIN necesidad de activar debugMode

---

## 🎉 Beneficios Esperados

### **Para el Usuario:**
1. ✅ **Visibilidad total de errores críticos** sin necesidad de activar debugMode
2. ✅ **Diagnóstico remoto** de por qué móvil 553 no envía coordenadas
3. ✅ **Alertas proactivas** cuando servicio GPS no puede iniciar
4. ✅ **Monitoreo permanente** de salud del sistema

### **Para el Sistema:**
1. ✅ **Logs persistentes** que NO se pierden si debugMode=false
2. ✅ **Envío automático** cada 15 minutos a n8n
3. ✅ **Buffer circular** que no consume memoria excesiva
4. ✅ **Retry automático** si falla el envío

---

## 🔮 Casos de Uso Reales

### **Caso 1: Móvil 553 no envía coordenadas**
**ANTES:** No había forma de saber por qué (debugMode=false, sin logs remotos)  
**DESPUÉS:** CriticalLogger captura el error exacto:
- `SERVICE_START_FAILED` → Sin permisos o bloqueado por batería
- `API_ERROR` → Servidor caído o HTTP 500
- `API_CONNECTION_ERROR` → Sin internet en la zona

---

### **Caso 2: Admin activa debugMode pero dispositivo no responde**
**ANTES:** Difícil diagnosticar sin acceso físico al dispositivo  
**DESPUÉS:** CriticalLogger ya está enviando logs de errores críticos, incluso sin debugMode

---

### **Caso 3: Servicio GPS se detiene inesperadamente**
**ANTES:** Solo se detectaba cuando usuario reportaba falta de coordenadas  
**DESPUÉS:** CriticalLogger captura:
- `SERVICE_START_FAILED` cuando Android mata el servicio
- `API_MAX_RETRIES` cuando acumula errores de envío
- `API_CONNECTION_ERROR` cuando pierde conectividad

---

**Fecha:** 30 Oct 2025  
**Autor:** Sistema de CriticalLogger  
**Versión:** 1.0  
**Estado:** ✅ Implementación completa, pendiente compilación y testing
