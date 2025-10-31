# 🔄 Sistema de Watchdog Mutuo (Auto-Recuperación)

## 🎯 Objetivo

Crear un sistema donde **dos servicios se monitorean mutuamente** para garantizar que ambos estén SIEMPRE activos, incluso si Android mata uno de ellos.

---

## 🏗️ Arquitectura del Sistema

### **Servicios Monitoreados:**

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   GPS Service (ForegroundLocationService)                  │
│   ├─ Ejecuta cada 3 minutos (AlarmManager)                 │
│   ├─ Obtiene coordenadas GPS                               │
│   └─ Envía a API de Riogas                                 │
│                                                             │
│                    ⬇️ MONITOREA ⬇️                          │
│                                                             │
│   CriticalLogUploadWorker                                  │
│   ├─ Ejecuta cada 15 minutos (WorkManager)                 │
│   ├─ Envía logs críticos a n8n                             │
│   └─ VERIFICA que GPS service esté activo                  │
│                                                             │
│                    ⬆️ MONITOREA ⬆️                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### **Flujo de Monitoreo Mutuo:**

```
GPS Service ejecuta (cada 3 min)
    ↓
🔍 Verifica: ¿CriticalLogWorker programado?
    ├─ SÍ → ✅ Continúa normal
    └─ NO → ⚠️ Re-programa CriticalLogWorker
              └─ Log crítico a n8n: "WATCHDOG_WORKER_RESTARTED"

CriticalLogWorker ejecuta (cada 15 min)
    ↓
🔍 Verifica: ¿GPS service corriendo?
    ├─ SÍ → ✅ Continúa normal
    └─ NO → ⚠️ Reinicia GPS service
              └─ Log crítico a n8n: "WATCHDOG_SERVICE_RESTARTED"
```

---

## 📦 Implementación

### 1. **ServiceWatchdog.kt** (Nuevo archivo)
📍 `android/app/src/main/kotlin/com/riogas/appmovil/ServiceWatchdog.kt`

**Métodos principales:**

```kotlin
// Verifica si GPS service está corriendo
ServiceWatchdog.isGPSServiceRunning(context): Boolean

// Verifica si AlarmManager tiene alarmas programadas
ServiceWatchdog.isAlarmScheduled(context): Boolean

// Verifica si CriticalLogWorker está programado (WorkManager)
ServiceWatchdog.isCriticalLogWorkerScheduled(context): Boolean

// Reinicia GPS service desde CriticalLogWorker
ServiceWatchdog.restartGPSService(context): Boolean

// Re-programa CriticalLogWorker desde GPS service
ServiceWatchdog.restartCriticalLogWorker(context)
```

---

### 2. **CriticalLogUploadWorker.kt** (Modificado)
📍 `android/app/src/main/kotlin/com/riogas/appmovil/CriticalLogUploadWorker.kt`

**Cambios:**

```kotlin
override fun doWork(): Result {
    Log.d(TAG, "🚀 [WATCHDOG] CriticalLogWorker ejecutándose...")
    
    // 🆕 PASO 1: WATCHDOG - Verificar GPS service
    val isGPSRunning = ServiceWatchdog.isGPSServiceRunning(context)
    val isAlarmScheduled = ServiceWatchdog.isAlarmScheduled(context)
    
    if (!isGPSRunning || !isAlarmScheduled) {
        Log.w(TAG, "⚠️ [WATCHDOG] GPS service MUERTO - Reiniciando...")
        
        val restarted = ServiceWatchdog.restartGPSService(context)
        
        if (restarted) {
            // Log crítico: GPS reiniciado exitosamente
            CriticalLogger.logCritical(
                TAG,
                "WATCHDOG EXITOSO: GPS service reiniciado automáticamente",
                mapOf(
                    "movil" to movil,
                    "restarted_by" to "CriticalLogWorker",
                    "reason" to "service_not_running"
                ),
                "WATCHDOG_SERVICE_RESTARTED"
            )
        } else {
            // Log crítico: No se pudo reiniciar
            CriticalLogger.logCritical(
                TAG,
                "WATCHDOG ERROR: No se pudo reiniciar GPS service",
                mapOf(...),
                "WATCHDOG_RESTART_FAILED"
            )
        }
    }
    
    // 🆕 PASO 2: Enviar logs críticos (si hay)
    if (logCount > 0) {
        // ... envío a n8n
    }
}
```

**Comportamiento:**
- ✅ Se ejecuta SIEMPRE cada 15 minutos (independiente de debugMode)
- ✅ Verifica que GPS service esté activo
- ✅ Si GPS muerto → Intenta reiniciar + Log crítico a n8n
- ✅ Si hay logs críticos → Los envía a n8n

---

### 3. **ForegroundLocationService.kt** (Modificado)
📍 `android/app/src/main/kotlin/com/example/moveit/ForegroundLocationService.kt`

**Cambios:**

```kotlin
override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    // ... inicialización ...
    
    // 🆕 WATCHDOG: Verificar CriticalLogWorker
    Thread {
        try {
            Log.d(TAG, "🔍 [WATCHDOG] Verificando CriticalLogWorker...")
            
            val isWorkerScheduled = kotlinx.coroutines.runBlocking {
                ServiceWatchdog.isCriticalLogWorkerScheduled(context)
            }
            
            if (!isWorkerScheduled) {
                Log.w(TAG, "⚠️ [WATCHDOG] CriticalLogWorker NO programado - Reiniciando...")
                
                ServiceWatchdog.restartCriticalLogWorker(context)
                
                // Log crítico: Worker re-programado
                CriticalLogger.logCritical(
                    TAG,
                    "WATCHDOG EXITOSO: CriticalLogWorker re-programado automáticamente",
                    mapOf(
                        "restarted_by" to "GPS_Service",
                        "reason" to "worker_not_scheduled"
                    ),
                    "WATCHDOG_WORKER_RESTARTED"
                )
            }
        } catch (e: Exception) {
            // Log crítico: Error verificando worker
            CriticalLogger.logCritical(
                TAG,
                "WATCHDOG ERROR: No se pudo verificar CriticalLogWorker",
                e,
                mapOf(...),
                "WATCHDOG_CHECK_FAILED"
            )
        }
    }.start()
    
    // ... resto del código ...
}
```

**Comportamiento:**
- ✅ Cada vez que GPS service ejecuta (cada 3 min) verifica CriticalLogWorker
- ✅ Si worker NO programado → Re-programa + Log crítico a n8n
- ✅ Verificación en thread separado (no bloquea GPS)

---

## 📊 Logs Críticos Generados

### **1. GPS Service reiniciado exitosamente:**
```json
{
  "errorType": "WATCHDOG_SERVICE_RESTARTED",
  "tag": "ServiceWatchdog",
  "message": "WATCHDOG EXITOSO: GPS service reiniciado automáticamente",
  "extras": {
    "movil": "693",
    "restarted_by": "CriticalLogWorker",
    "reason": "service_not_running",
    "interval": "3"
  }
}
```

### **2. CriticalLogWorker re-programado exitosamente:**
```json
{
  "errorType": "WATCHDOG_WORKER_RESTARTED",
  "tag": "ServiceWatchdog",
  "message": "WATCHDOG EXITOSO: CriticalLogWorker re-programado automáticamente",
  "extras": {
    "restarted_by": "GPS_Service",
    "reason": "worker_not_scheduled"
  }
}
```

### **3. Error reiniciando GPS service:**
```json
{
  "errorType": "WATCHDOG_RESTART_FAILED",
  "tag": "ServiceWatchdog",
  "message": "WATCHDOG ERROR: Sin permisos para reiniciar GPS service",
  "extras": {
    "context": "CriticalLogWorker_watchdog",
    "error": "SecurityException",
    "errorMessage": "Permission denied"
  }
}
```

### **4. Error re-programando CriticalLogWorker:**
```json
{
  "errorType": "WATCHDOG_RESTART_FAILED",
  "tag": "ServiceWatchdog",
  "message": "WATCHDOG ERROR: No se pudo re-programar CriticalLogWorker",
  "extras": {
    "error_type": "IllegalStateException",
    "context": "GPS_Service_watchdog"
  }
}
```

---

## 🎯 Escenarios de Auto-Recuperación

### **Escenario 1: Android mata GPS service (batería, doze mode)**

```
1. Android mata ForegroundLocationService
   ↓
2. AlarmManager deja de ejecutarse (no hay servicio)
   ↓
3. 15 minutos después: CriticalLogWorker ejecuta
   ↓
4. 🔍 Detecta: GPS service NO corriendo
   ↓
5. ⚠️ Reinicia GPS service
   ↓
6. 📤 Log crítico a n8n: "WATCHDOG_SERVICE_RESTARTED"
   ↓
7. ✅ GPS service activo nuevamente
```

---

### **Escenario 2: Android cancela WorkManager (optimización)**

```
1. Android cancela CriticalLogUploadWorker
   ↓
2. Logs críticos no se envían a n8n
   ↓
3. 3 minutos después: GPS service ejecuta (AlarmManager trigger)
   ↓
4. 🔍 Detecta: CriticalLogWorker NO programado
   ↓
5. ⚠️ Re-programa CriticalLogWorker
   ↓
6. 📤 Log crítico a n8n: "WATCHDOG_WORKER_RESTARTED"
   ↓
7. ✅ CriticalLogWorker activo nuevamente
```

---

### **Escenario 3: Ambos servicios muertos (device restart)**

```
1. Usuario reinicia dispositivo
   ↓
2. MainActivity.onCreate() ejecuta
   ↓
3. restartLocationServiceFromForeground() inicia GPS service
   ↓
4. CriticalLogUploadWorker.schedule() programa worker
   ↓
5. ✅ Ambos servicios activos
   ↓
6. GPS service (cada 3 min) verifica worker
   ↓
7. CriticalLogWorker (cada 15 min) verifica GPS
   ↓
8. ✅ Sistema de watchdog mutuo activo
```

---

## 🔄 Frecuencias de Monitoreo

| Servicio | Frecuencia | Verifica | Acción si muerto |
|----------|-----------|----------|------------------|
| **GPS Service** | Cada 3 minutos | CriticalLogWorker programado | Re-programa worker |
| **CriticalLogWorker** | Cada 15 minutos | GPS service corriendo + AlarmManager programado | Reinicia GPS service |

**Resultado:** Máximo tiempo sin monitoreo = **3 minutos**

---

## 🧪 Testing

### **Paso 1: Verificar watchdog activo**
```bash
adb logcat | Select-String "WATCHDOG"
```

**Logs esperados (normal):**
```
🔍 [WATCHDOG] Verificando CriticalLogWorker...
✅ [WATCHDOG] CriticalLogWorker activo

🔍 [WATCHDOG] Verificando estado GPS...
✅ [WATCHDOG] GPS service activo y saludable
```

---

### **Paso 2: Matar GPS service manualmente**
```bash
# Forzar stop del servicio
adb shell am force-stop com.example.moveit

# Monitorear logs
adb logcat | Select-String "WATCHDOG"
```

**Logs esperados (después de 15 min máximo):**
```
⚠️ [WATCHDOG] GPS service MUERTO detectado - Intentando reiniciar...
🔄 [WATCHDOG] Reiniciando GPS service desde CriticalLogWorker...
✅ [WATCHDOG] GPS service reiniciado exitosamente
🚨 [CRITICAL] WATCHDOG EXITOSO: GPS service reiniciado automáticamente
```

---

### **Paso 3: Cancelar WorkManager manualmente**
```bash
# Entrar al shell
adb shell

# Forzar cancelación de WorkManager
am broadcast -a androidx.work.impl.background.systemjob.SystemJobService.ACTION_CANCEL_WORK \
  --es EXTRA_WORK_SPEC_ID critical_log_upload

# Salir del shell
exit

# Monitorear logs
adb logcat | Select-String "WATCHDOG"
```

**Logs esperados (después de 3 min máximo):**
```
🔍 [WATCHDOG] Verificando CriticalLogWorker...
⚠️ [WATCHDOG] CriticalLogWorker NO programado - Reiniciando...
🔄 [WATCHDOG] Re-programando CriticalLogWorker desde GPS service...
✅ [WATCHDOG] CriticalLogWorker re-programado exitosamente
🚨 [CRITICAL] WATCHDOG EXITOSO: CriticalLogWorker re-programado automáticamente
```

---

### **Paso 4: Verificar logs en n8n**

Esperar 15 minutos después de provocar un error y verificar en n8n que lleguen logs del tipo:
- `WATCHDOG_SERVICE_RESTARTED`
- `WATCHDOG_WORKER_RESTARTED`
- `WATCHDOG_RESTART_FAILED` (si hay problemas)

---

## ✅ Ventajas del Sistema

### **1. Resiliencia máxima:**
- ✅ Si Android mata un servicio, el otro lo detecta y reinicia
- ✅ Tiempo máximo sin monitoreo: 3 minutos

### **2. Auto-recuperación:**
- ✅ No requiere intervención manual
- ✅ Funciona incluso si app está cerrada

### **3. Visibilidad total:**
- ✅ Todos los reinicios se loguean en CriticalLogger
- ✅ Se envían a n8n automáticamente cada 15 minutos
- ✅ Admin puede ver cuántas veces se auto-recuperó

### **4. Independiente de debugMode:**
- ✅ Funciona SIEMPRE (debugMode=true o false)
- ✅ Solo envía logs críticos, no spam

---

## 🔮 Casos de Uso Reales

### **Caso 1: Móvil 553 con Android agresivo (Xiaomi, Huawei)**
**ANTES:** GPS service muere por optimización de batería, no se recupera hasta que usuario abre app  
**DESPUÉS:** CriticalLogWorker detecta muerte del GPS en 15 min máximo y lo reinicia automáticamente

---

### **Caso 2: WorkManager cancelado por sistema**
**ANTES:** Logs críticos dejan de enviarse, admin no sabe qué pasa  
**DESPUÉS:** GPS service detecta que worker no está programado en 3 min máximo y lo re-programa

---

### **Caso 3: Dispositivo en doze mode prolongado**
**ANTES:** Ambos servicios muertos, sin recuperación automática  
**DESPUÉS:** En cuanto dispositivo sale de doze, uno de los dos ejecuta y resucita al otro

---

## 📝 Consideraciones

### **Limitaciones:**
- ⚠️ Si ambos servicios mueren SIMULTÁNEAMENTE, el sistema espera a que uno ejecute naturalmente (próximo trigger de AlarmManager o WorkManager)
- ⚠️ Si dispositivo está en doze mode severo, ambos servicios pueden tardar en ejecutar

### **Solución:**
- ✅ MainActivity.onCreate() SIEMPRE reinicia ambos servicios al abrir app
- ✅ Verificación en checkAndRestartLocationService() cuando se descarga pedido

---

**Fecha:** 30 Oct 2025  
**Autor:** Sistema de Watchdog Mutuo  
**Versión:** 1.0  
**Estado:** ✅ Implementado, pendiente compilación y testing
