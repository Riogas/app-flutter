# 🔧 FIX: Fallo de Reinicio del GPS Service por Watchdog

## 📊 **Problema Detectado**

### **Logs Críticos:**
```json
{
  "timestamp": 1761916496991,
  "tag": "ForegroundLocationService",
  "message": "Servicio GPS iniciado exitosamente",
  "errorType": "SERVICE_STARTED"
},
{
  "timestamp": 1761916496993,
  "tag": "CriticalLogAlarm",
  "message": "GPS Service MUERTO detectado por watchdog",
  "errorType": "GPS_SERVICE_DEAD"
},
{
  "timestamp": 1761916496994,
  "tag": "CriticalLogAlarm",
  "message": "FALLO CRÍTICO: No se pudo reiniciar GPS Service",
  "errorType": "GPS_SERVICE_RESTART_FAILED"
}
```

**Secuencia de eventos:**
1. **10:14:56.991** → Servicio GPS funcionando correctamente
2. **10:14:56.993** → Watchdog detecta servicio MUERTO (2ms después ⚠️)
3. **10:14:56.994** → Fallo al intentar reiniciar (1ms después del intento)

---

## 🔍 **Causa Raíz Identificada**

### **Android 12+ Background Execution Restrictions**

**Problema principal:** Android 12+ (API 31+) **NO permite** iniciar un `ForegroundService` desde background **EXCEPTO** en estos casos:

✅ **Permitido:**
- Desde una actividad visible
- Desde otro ForegroundService activo
- Desde un exact alarm con `PendingIntent`
- Desde high-priority FCM push notification

❌ **NO Permitido:**
- Desde un `BroadcastReceiver` ejecutado por AlarmManager (tu caso actual)
- Desde WorkManager en background
- Desde cualquier contexto en background sin excepciones especiales

### **Tu Caso:**
```kotlin
// CriticalLogAlarmReceiver ejecuta cada 30 segundos
override fun onReceive(context: Context, intent: Intent) {
    // ...
    val restarted = ServiceWatchdog.restartGPSService(context)
    // ❌ FALLA aquí porque la app está en background
}

// ServiceWatchdog.restartGPSService()
context.startForegroundService(serviceIntent) // ❌ IllegalStateException en Android 12+
```

**Excepciones esperadas:**
- `ForegroundServiceStartNotAllowedException` (Android 12+)
- `IllegalStateException` (variante genérica)
- `SecurityException` (si faltan permisos)

---

## 🔧 **Soluciones Implementadas**

### **1. Logging Mejorado** ✅

**Cambio en `ServiceWatchdog.kt`:**

```kotlin
} catch (e: Exception) {
    Log.e(TAG, "❌ [WATCHDOG] Error desconocido reiniciando GPS service", e)
    CriticalLogger.logCritical(
        TAG,
        "WATCHDOG ERROR: Fallo desconocido reiniciando GPS service",
        e,
        mapOf(
            "error_type" to e.javaClass.simpleName,
            "error_message" to (e.message ?: "Sin mensaje"),  // 🆕 NUEVO
            "error_cause" to (e.cause?.javaClass?.simpleName ?: "Sin causa"),  // 🆕 NUEVO
            "android_version" to Build.VERSION.SDK_INT,  // 🆕 NUEVO
            "context" to "CriticalLogWorker_watchdog"
        ),
        "WATCHDOG_RESTART_FAILED"
    )
    false
}
```

**Beneficio:** Ahora el log crítico incluirá el tipo exacto de excepción, mensaje y versión de Android.

---

### **2. Estrategia de Reinicio Compatible con Android 12+** ✅ **PRINCIPAL**

**Cambio en `ServiceWatchdog.restartGPSService()`:**

```kotlin
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
    // 🆕 Android 12+: Usar AlarmManager + PendingIntent
    // Esto SÍ está permitido desde background
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    val intent = Intent(context, LocationReceiver::class.java).apply {
        putExtra("movil", movil)
        putExtra("escenario", escenario)
        putExtra("usuario", usuario)
        putExtra("deviceId", deviceId)
        putExtra("intervalMinutes", intervalMinutes)
    }
    
    val pendingIntent = PendingIntent.getBroadcast(
        context,
        99999, // Request code único para watchdog
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    
    // Alarma INMEDIATA para reiniciar servicio (2 segundos)
    alarmManager.setExactAndAllowWhileIdle(
        AlarmManager.RTC_WAKEUP,
        System.currentTimeMillis() + 2000,
        pendingIntent
    )
    
    Log.i(TAG, "✅ [WATCHDOG] GPS service reinicio programado (AlarmManager)")
    
} else {
    // Android 11 o inferior: Inicio directo funciona
    context.startForegroundService(serviceIntent)
    Log.i(TAG, "✅ [WATCHDOG] GPS service reiniciado exitosamente")
}
```

**¿Por qué funciona?**

1. **AlarmManager con `setExactAndAllowWhileIdle()`:**
   - Es una excepción explícita permitida por Android 12+
   - Puede ejecutarse incluso en Doze mode
   - Tiene permisos para iniciar foreground services

2. **PendingIntent con `FLAG_IMMUTABLE`:**
   - Requerido por Android 12+ para seguridad
   - Permite que el sistema ejecute el intent posteriormente

3. **LocationReceiver:**
   - Ya existe en tu código
   - Es un `BroadcastReceiver` que inicia el `ForegroundLocationService`
   - Cuando es llamado por AlarmManager, tiene permisos necesarios

---

## 📋 **Flujo de Recuperación Actualizado**

### **Android 12+ (API 31+):**

```
1. CriticalLogAlarmReceiver detecta servicio muerto
   ↓
2. Llama a ServiceWatchdog.restartGPSService()
   ↓
3. 🆕 En lugar de iniciar servicio directamente:
   - Programa alarma INMEDIATA (2 segundos)
   - Alarma ejecutará LocationReceiver
   ↓
4. LocationReceiver recibe alarma
   - Tiene permisos de AlarmManager
   - Inicia ForegroundLocationService exitosamente
   ↓
5. ✅ Servicio GPS activo nuevamente
```

### **Android 11 o inferior:**

```
1. CriticalLogAlarmReceiver detecta servicio muerto
   ↓
2. Llama a ServiceWatchdog.restartGPSService()
   ↓
3. Inicia servicio directamente (sin restricciones)
   ↓
4. ✅ Servicio GPS activo nuevamente
```

---

## 🧪 **Testing**

### **Paso 1: Compilar y desplegar**
```powershell
cd appmovil
flutter build apk --release
flutter install
```

### **Paso 2: Forzar muerte del servicio**
```powershell
# Matar app
adb shell am force-stop com.example.moveit

# Monitorear logs
adb logcat | Select-String "WATCHDOG"
```

### **Paso 3: Verificar logs críticos en n8n**

**Logs esperados (después de máximo 30 segundos):**

```json
{
  "errorType": "GPS_SERVICE_DEAD",
  "message": "GPS Service MUERTO detectado por watchdog"
}
```

**Luego (2 segundos después):**

```json
{
  "errorType": "WATCHDOG_SERVICE_RESTARTED",
  "message": "WATCHDOG EXITOSO: GPS service reiniciado automáticamente",
  "extras": {
    "movil": "693",
    "restarted_by": "CriticalLogWorker",
    "restart_method": "AlarmManager_pending_intent",
    "android_version": 34
  }
}
```

**Si sigue fallando:**

```json
{
  "errorType": "WATCHDOG_RESTART_FAILED",
  "message": "WATCHDOG ERROR: Fallo desconocido reiniciando GPS service",
  "extras": {
    "error_type": "ForegroundServiceStartNotAllowedException",  // 🆕 AHORA SE VERÁ
    "error_message": "Not allowed to start service...",  // 🆕 AHORA SE VERÁ
    "error_cause": "...",  // 🆕 AHORA SE VERÁ
    "android_version": 34
  }
}
```

---

## ⚠️ **Posibles Causas Secundarias**

Si el problema persiste después de esta solución, considera:

### **1. Permisos Faltantes**

**Verificar en `AndroidManifest.xml`:**
```xml
<!-- Android 12+: Permiso para alarmas exactas -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />

<!-- Android 13+: Permiso para notificaciones -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- Foreground service con tipo LOCATION -->
<service
    android:name=".ForegroundLocationService"
    android:foregroundServiceType="location" />
```

### **2. Battery Optimization**

**Solicitar al usuario desactivar optimización de batería:**
```kotlin
// En MainActivity.kt
val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
intent.data = Uri.parse("package:$packageName")
startActivity(intent)
```

### **3. Manufacturer Restrictions (Xiaomi, Huawei, etc.)**

Algunos fabricantes tienen restricciones adicionales que requieren configuración manual en la app de ajustes del sistema.

---

## 📊 **Impacto Esperado**

### **Antes:**
- ❌ Watchdog detecta servicio muerto
- ❌ Intento de reinicio falla inmediatamente (Android 12+ restrictions)
- ❌ Servicio permanece muerto hasta intervención manual

### **Después:**
- ✅ Watchdog detecta servicio muerto
- ✅ Programa alarma inmediata con AlarmManager
- ✅ AlarmManager ejecuta LocationReceiver con permisos adecuados
- ✅ Servicio se reinicia automáticamente en 2-3 segundos

---

## 📝 **Archivos Modificados**

1. **`ServiceWatchdog.kt`:**
   - Mejorado logging con más detalles de excepción
   - Estrategia de reinicio condicional por versión de Android
   - Uso de AlarmManager para Android 12+

---

## 🔗 **Referencias**

- [Android Developers: Background execution limits](https://developer.android.com/guide/components/foreground-services#background-restrictions)
- [Android 12 behavior changes: FGS restrictions](https://developer.android.com/about/versions/12/foreground-services)
- [AlarmManager best practices](https://developer.android.com/training/scheduling/alarms)

---

**Fecha:** 2025-10-31  
**Versión Android del dispositivo:** 14 (API 34)  
**Autor:** GitHub Copilot
