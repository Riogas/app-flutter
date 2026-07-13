# 🚨 Análisis: Logs Críticos del Servicio GPS

## 📋 Resumen Ejecutivo

El usuario pregunta: **"¿Se está logueando cuando el servicio GPS no puede iniciarse o no puede enviar coordenadas?"**

**RESPUESTA:** ✅ Parcialmente SÍ, ❌ pero con LIMITACIONES CRÍTICAS

---

## 🔍 Situación Actual

### ✅ **LO QUE SÍ SE LOGUEA:**

#### 1. **Cuando se descarga/lee un pedido y chequea el servicio**
📍 Archivo: `MainActivity.kt` - `checkAndRestartLocationService()` (líneas 320-550)

```kotlin
✅ Servicio deshabilitado manualmente
✅ Móvil vacío (no se puede validar servicio)
✅ Estado del servicio (isServiceRunning, hasAlarmScheduled)
✅ Parámetros desincronizados (movil en Hive ≠ SharedPreferences)
✅ Servicio reiniciado exitosamente (SERVICE_AUTO_RESTARTED)
✅ Servicio activo y funcionando correctamente
```

**Logs generados:**
- `LocationLogger.logEvent()` → CSV local
- `DebugLogger.i/w()` → Buffer para n8n (solo si debugMode=true)

---

#### 2. **En el servicio ForegroundLocationService**
📍 Archivo: `ForegroundLocationService.kt` - `onStartCommand()` (líneas 12-150)

```kotlin
✅ Servicio iniciado como foreground (Android 10+ con LOCATION type)
✅ Servicio deshabilitado (service_disabled)
✅ Servicio pausado temporalmente (service_paused)
✅ Parámetros recibidos (movil, escenario, usuario, deviceId)
✅ Móvil vacío → recuperación desde SharedPreferences
✅ Parámetros recuperados exitosamente
```

**Logs generados:**
- `LocationLogger.logEvent()` → CSV local
- `Log.d/i/w/e()` → Logcat de Android

---

#### 3. **En llamadas al API de Riogas**
📍 Archivo: `LocationHelper.kt` - `invokeRegistrarCoordenadasV2ApiWithRetry()` (línea 1055+)

```kotlin
✅ Payload completo del request (lat, lon, movil, escenario, etc.)
✅ Request exitoso (código HTTP, tiempo de respuesta, responseBody)
✅ Error HTTP (código, mensaje, responseBody, requestPayload)
✅ Máximo de reintentos alcanzado
✅ Error de conexión (timeout, sin internet)
```

**Logs generados:**
- `DebugLogger.i/w/e()` → Buffer para n8n (solo si debugMode=true)
- `LocationLogger.logError()` → CSV local

---

### ❌ **LO QUE NO SE LOGUEA (CRÍTICO):**

#### 1. **Cuando NO se puede iniciar el servicio por restricciones del sistema**

```kotlin
❌ startForegroundService() lanza SecurityException (sin permisos)
❌ startForegroundService() lanza IllegalStateException (background restrictions)
❌ startForegroundService() lanza ForegroundServiceStartNotAllowedException (Android 12+)
❌ Servicio bloqueado por optimización de batería (Doze mode)
❌ Servicio bloqueado por restricciones de fabricante (Xiaomi, Huawei, etc.)
```

**Ubicaciones afectadas:**
- `MainActivity.kt` línea 492: `startForegroundService(serviceIntent)` - sin try-catch
- `MainActivity.kt` línea 662: `startForegroundService(intent)` - sin try-catch
- `LocationHelper.kt` línea 430: `context.startForegroundService(serviceIntent)` - sin try-catch
- `LocationReceiver.kt` línea 114: `context.startForegroundService(serviceIntent)` - sin try-catch

---

#### 2. **Cuando ForegroundLocationService NO puede llamar a startForeground()**

```kotlin
❌ startForeground() lanza SecurityException (sin permiso FOREGROUND_SERVICE_LOCATION)
❌ startForeground() falla por falta de permiso de notificación
❌ createNotification() falla por restricciones del sistema
```

**Ubicación:** `ForegroundLocationService.kt` líneas 12-25 - sin try-catch

---

#### 3. **Cuando NO se puede obtener ubicación GPS**

```kotlin
❌ LocationManager devuelve null (GPS sin señal)
❌ getCurrentLocation() timeout (45 segundos sin respuesta)
❌ SecurityException al intentar acceder a GPS (permisos revocados en runtime)
```

**Ubicación:** `LocationHelper.kt` - `getCurrentLocation()` - logs existentes pero incompletos

---

## 🔥 PROBLEMA CRÍTICO IDENTIFICADO

### **DebugLogger.e() solo funciona si debugMode=true**

📍 Archivo: `DebugLogger.kt` línea 101:

```kotlin
fun e(tag: String, message: String, throwable: Throwable? = null, extras: Map<String, Any> = emptyMap()) {
    if (!isEnabled()) return  // ❌ PROBLEMA: Errores críticos NO se registran si debugMode=false
    
    val extrasWithError = if (throwable != null) {
        extras + mapOf(
            "error" to throwable.javaClass.simpleName,
            "errorMessage" to (throwable.message ?: ""),
            "stackTrace" to throwable.stackTraceToString().take(500)
        )
    } else {
        extras
    }
    
    addLog("ERROR", tag, message, extrasWithError)
    // ...
}
```

**Impacto:**
- ❌ Si móvil 553 tiene debugMode=false y falla startForegroundService(), **NO SE REGISTRA EL ERROR**
- ❌ Si el API devuelve HTTP 500, **NO SE REGISTRA EL ERROR** (a menos que debugMode=true)
- ❌ Si el servicio no puede iniciar por restricciones de batería, **NO SE REGISTRA**

---

## 🎯 Solución Propuesta

### **1. Crear CriticalLogger para errores SIEMPRE visibles**

Nuevo sistema de logging que:
- ✅ Se ejecuta INDEPENDIENTE de `debugMode`
- ✅ Se envía SIEMPRE a n8n
- ✅ Solo registra errores CRÍTICOS (no spam)

```kotlin
object CriticalLogger {
    // Envía a n8n SIEMPRE, sin importar debugMode
    fun logCritical(tag: String, message: String, extras: Map<String, Any> = emptyMap())
}
```

---

### **2. Agregar try-catch en TODOS los startForegroundService()**

```kotlin
// MainActivity.kt línea 492
try {
    startForegroundService(serviceIntent)
    CriticalLogger.logCritical("MainActivity", "Servicio GPS iniciado", mapOf(
        "movil" to movil,
        "interval" to intervalMinutes
    ))
} catch (e: SecurityException) {
    CriticalLogger.logCritical("MainActivity", "ERROR: Sin permisos para iniciar servicio GPS", mapOf(
        "movil" to movil,
        "error" to e.message,
        "permissions" to getLocationPermissionsStatusShort(this)
    ))
} catch (e: IllegalStateException) {
    CriticalLogger.logCritical("MainActivity", "ERROR: Servicio bloqueado por background restrictions", mapOf(
        "movil" to movil,
        "error" to e.message,
        "android_version" to Build.VERSION.SDK_INT
    ))
} catch (e: Exception) {
    CriticalLogger.logCritical("MainActivity", "ERROR: Fallo desconocido iniciando servicio GPS", mapOf(
        "movil" to movil,
        "error" to e.javaClass.simpleName,
        "message" to (e.message ?: "unknown")
    ))
}
```

**Aplicar en:**
- ✅ MainActivity.kt (2 ubicaciones)
- ✅ LocationHelper.kt (1 ubicación)
- ✅ LocationReceiver.kt (1 ubicación)

---

### **3. Agregar try-catch en ForegroundLocationService.onStartCommand()**

```kotlin
// ForegroundLocationService.kt línea 12
override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    try {
        // Llamar a startForeground() INMEDIATAMENTE
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
        
        CriticalLogger.logCritical("ForegroundLocationService", "Servicio GPS iniciado exitosamente", mapOf(
            "android_version" to Build.VERSION.SDK_INT
        ))
        
    } catch (e: SecurityException) {
        CriticalLogger.logCritical("ForegroundLocationService", "ERROR: Sin permiso FOREGROUND_SERVICE_LOCATION", mapOf(
            "error" to e.message,
            "android_version" to Build.VERSION.SDK_INT
        ))
        stopSelf()
        return START_NOT_STICKY
    } catch (e: Exception) {
        CriticalLogger.logCritical("ForegroundLocationService", "ERROR: Fallo al iniciar foreground", mapOf(
            "error" to e.javaClass.simpleName,
            "message" to (e.message ?: "unknown")
        ))
        stopSelf()
        return START_NOT_STICKY
    }
    
    // ... resto del código
}
```

---

### **4. Mejorar logs de API call failures**

```kotlin
// LocationHelper.kt - invokeRegistrarCoordenadasV2ApiWithRetry()
// CAMBIAR de DebugLogger.e() a CriticalLogger.logCritical() para errores HTTP

if (!response.isSuccessful) {
    val errorBody = response.body?.string() ?: "empty"
    
    // 🆕 Enviar a n8n SIEMPRE (no solo si debugMode=true)
    CriticalLogger.logCritical("LocationHelper", "API call fallida", mapOf(
        "movil" to movil,
        "httpCode" to response.code,
        "httpMessage" to response.message,
        "attempt" to (currentAttempt + 1),
        "maxRetries" to maxRetries,
        "responseBody" to errorBody,
        "requestPayload" to jsonBody
    ))
}
```

---

## 📊 Comparativa: Antes vs Después

| Escenario | ANTES | DESPUÉS |
|-----------|-------|---------|
| **Servicio bloqueado por permisos** | ❌ No se registra (solo logcat local) | ✅ Se envía a n8n SIEMPRE |
| **API devuelve HTTP 500** | ⚠️ Solo si debugMode=true | ✅ Se envía a n8n SIEMPRE |
| **startForegroundService() falla** | ❌ No se registra | ✅ Se envía a n8n SIEMPRE |
| **GPS sin señal (timeout)** | ✅ Se registra en CSV local | ✅ Se envía a n8n SIEMPRE |
| **Servicio deshabilitado manualmente** | ✅ Ya se registra correctamente | ✅ (sin cambios) |
| **Móvil 553 no envía coords** | ❌ Difícil diagnosticar sin debugMode | ✅ Errores visibles SIEMPRE |

---

## 🎯 Logs que el Usuario Necesita

Según la pregunta del usuario:

### ✅ **"¿Se loguea cuando se QUIERE iniciar el servicio pero NO SE PUEDE?"**

**ANTES:** ❌ NO se loguea (solo aparece en logcat local, no en n8n)  
**DESPUÉS:** ✅ SÍ se loguea y se envía a n8n SIEMPRE

---

### ✅ **"¿Se loguea cuando NO PUEDE ENVIAR coordenadas al servicio de Riogas?"**

**ANTES:** ⚠️ Solo si debugMode=true (DebugLogger.e())  
**DESPUÉS:** ✅ SÍ se loguea y se envía a n8n SIEMPRE

---

### ✅ **"¿Se loguea cuando se descarga un pedido y chequea si el servicio está vivo?"**

**ANTES:** ✅ SÍ, ya funciona correctamente (LocationLogger.logEvent)  
**DESPUÉS:** ✅ (sin cambios, ya funciona)

---

## 🚀 Plan de Implementación

### **Paso 1: Crear CriticalLogger.kt**
- Sistema de logging INDEPENDIENTE de debugMode
- Buffer circular de 50 errores críticos
- Envío automático a n8n cada 15 minutos (WorkManager)

### **Paso 2: Agregar try-catch en startForegroundService()**
- MainActivity.kt (2 ubicaciones)
- LocationHelper.kt (1 ubicación)
- LocationReceiver.kt (1 ubicación)

### **Paso 3: Agregar try-catch en ForegroundLocationService.onStartCommand()**
- Wrap startForeground() con manejo de excepciones
- Log crítico si falla

### **Paso 4: Cambiar DebugLogger.e() a CriticalLogger en API calls**
- invokeRegistrarCoordenadasV2ApiWithRetry()
- Errores HTTP siempre visibles

### **Paso 5: Testing**
- Revocar permisos de ubicación → Verificar log crítico
- Desactivar GPS → Verificar log crítico
- Simular HTTP 500 → Verificar log crítico
- Verificar que logs llegan a n8n sin debugMode=true

---

## ✅ Checklist de Verificación

- [ ] CriticalLogger.kt creado y funcional
- [ ] try-catch agregado en todos los startForegroundService()
- [ ] try-catch agregado en ForegroundLocationService.onStartCommand()
- [ ] API call errors usan CriticalLogger
- [ ] WorkManager envía logs críticos cada 15 minutos
- [ ] Compilar APK y probar en dispositivo
- [ ] Verificar logs en n8n SIN debugMode=true
- [ ] Probar con móvil 553 (el problemático)

---

## 📝 Notas Importantes

### **Diferencia entre DebugLogger y CriticalLogger:**

| Aspecto | DebugLogger | CriticalLogger |
|---------|-------------|----------------|
| **Activación** | Solo si debugMode=true | SIEMPRE activo |
| **Uso** | Debug general, info, warnings | Solo ERRORES CRÍTICOS |
| **Buffer** | 100 logs | 50 logs (más pequeño) |
| **Frecuencia envío** | 10-15 min (WorkManager) | 15 min (WorkManager separado) |
| **Propósito** | Diagnóstico detallado temporal | Monitoreo permanente de salud del sistema |

---

**Fecha:** 30 Oct 2025  
**Autor:** Análisis del Sistema de Logging GPS  
**Conclusión:** Se requiere implementar CriticalLogger para errores críticos independientes de debugMode
