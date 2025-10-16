# ⚠️ PROBLEMA CRÍTICO DESCUBIERTO - Android 12+ Restriction

## 🔴 Problema Identificado

**Fecha**: 14 de Octubre, 2025 - 12:48  
**Logs Críticos**:
```
10-14 12:29:21 W ActivityManager: Foreground service started from background 
                                   can not have location/camera/microphone access

10-14 12:30:46 I ActivityManager: Killing 21885:com.example.moveit/u0a447 (adj 925): 
                                   kill background
```

### ¿Qué Pasó?

1. ✅ El servicio funcionó correctamente de **10:41 a 12:29** (1 hora 48 minutos)
2. ✅ Se enviaron coordenadas cada 3 minutos exitosamente
3. ❌ A las **12:29**, Android detectó que el `ForegroundLocationService` se estaba iniciando desde un `BroadcastReceiver` en background
4. ❌ **Android 12+ NO PERMITE** que servicios iniciados desde background accedan a ubicación
5. ❌ El sistema **MATÓ LA APP** (`kill background`)
6. ❌ No se programaron más alarmas

### Restricción de Android 12+

**Documentación Oficial**: [Background Location Limits](https://developer.android.com/about/versions/12/behavior-changes-12#background-location)

```
Starting in Android 12 (API level 31), if your app starts a foreground service 
while running in the background, the foreground service has limitations on 
accessing location, camera, and microphone.
```

**Traducción**: Si tu app inicia un ForegroundService mientras corre en background, ese servicio **NO puede acceder** a ubicación, cámara o micrófono.

---

## 🛠️ SOLUCIÓN IMPLEMENTADA: WorkManager

### ¿Por Qué WorkManager?

Google recomienda **WorkManager** para tareas periódicas en background porque:

| Característica | AlarmManager + FGS | WorkManager |
|----------------|-------------------|-------------|
| **Android 12+ Compatible** | ❌ Restricciones de FGS | ✅ Sin restricciones |
| **Auto-reinicio después de reboot** | ⚠️ Requiere BootReceiver | ✅ Automático |
| **Respeta Doze Mode** | ⚠️ Requiere `setExactAndAllowWhileIdle()` | ✅ Automático |
| **Reintentos automáticos** | ❌ Manual | ✅ Automático |
| **Persistencia garantizada** | ⚠️ Manual (SharedPreferences) | ✅ Automático |
| **Acceso a ubicación en background** | ❌ Bloqueado en Android 12+ | ✅ Permitido |

### Archivos Creados

1. **`LocationWorker.kt`** (130 líneas)
   - Worker que ejecuta en background
   - Llama a `LocationHelper.getCurrentLocation()` directamente
   - Maneja errores con retry automático
   - Compatible con Android 12+

2. **`WorkManagerHelper.kt`** (180 líneas)
   - Helper para programar/cancelar workers
   - Persistencia de parámetros en SharedPreferences
   - Soporte para intervalos >= 15 minutos (limitación de WorkManager)

3. **Modificación en `build.gradle`**:
   ```gradle
   implementation 'androidx.work:work-runtime-ktx:2.9.0'
   ```

---

## ⚠️ LIMITACIÓN IMPORTANTE: Intervalo Mínimo de 15 Minutos

WorkManager tiene una **restricción de diseño**:
- **PeriodicWorkRequest**: Mínimo 15 minutos entre ejecuciones
- Esto es para optimizar batería y rendimiento

### Opciones para Intervalo de 3 Minutos:

#### Opción 1: Usar WorkManager con OneTimeWork + Re-schedule ⚠️
```kotlin
// Programar un OneTimeWork que se repite cada 3 minutos
// PROBLEMA: No es tan confiable como PeriodicWork
scheduleOneTimeWork(context, 3, inputData)
```

**Pros**:
- ✅ Compatible con Android 12+
- ✅ Sin restricciones de FGS

**Contras**:
- ❌ Menos confiable que PeriodicWork
- ❌ Puede no ejecutarse exactamente cada 3 minutos (Doze Mode lo puede retrasar)

#### Opción 2: Mantener la App en Foreground + AlarmManager ✅ (RECOMENDADO)
```kotlin
// 1. Iniciar ForegroundService DESDE LA APP (cuando está activa)
startForegroundService(intent)

// 2. Desde el ForegroundService, programar AlarmManager
scheduleLocationAlarm(context, 3, ...)

// 3. LocationReceiver inicia el MISMO ForegroundService (ya está en foreground)
```

**Pros**:
- ✅ Permite intervalos de 3 minutos
- ✅ Confiable (AlarmManager garantiza ejecución)
- ✅ Compatible con Android 12+ (si el servicio se inició desde foreground)

**Contras**:
- ⚠️ Requiere que el usuario **abra la app** al menos una vez después de reboot
- ⚠️ Si Android mata el servicio completamente, no se reinicia automáticamente

#### Opción 3: Cambiar Intervalo a 15 Minutos ✅ (MÁS CONFIABLE)
```kotlin
// Usar WorkManager con PeriodicWorkRequest
schedulePeriodicWork(context, 15, inputData)
```

**Pros**:
- ✅ Máxima confiabilidad
- ✅ Compatible con Android 12+
- ✅ Auto-reinicio después de reboot
- ✅ Respeta Doze Mode correctamente

**Contras**:
- ⚠️ Intervalo más largo (15 min en lugar de 3 min)

---

## 🚀 NUEVA ESTRATEGIA HÍBRIDA RECOMENDADA

Combinar ambos enfoques para máxima confiabilidad:

### Cuando la App está Activa (Foreground):
```kotlin
// Usar AlarmManager + ForegroundService para intervalos cortos (3 min)
startForegroundService(intent) // Desde MainActivity
scheduleLocationAlarm(context, 3, ...) // Desde ForegroundService
```

### Cuando la App está en Background o después de Reboot:
```kotlin
// Usar WorkManager para mantener el servicio vivo (15 min)
WorkManagerHelper.schedulePeriodicLocationWork(context, 15, ...)
```

### Flujo Completo:

```
1. Usuario abre app → MainActivity.onCreate()
   ↓
2. Iniciar ForegroundService (desde foreground, permitido)
   ↓
3. ForegroundService programa AlarmManager cada 3 min
   ↓
4. AlarmManager dispara LocationReceiver cada 3 min
   ↓
5. LocationReceiver inicia ForegroundService (ya existe, permitido)
   ↓
6. Coordenadas enviadas cada 3 min ✅

SI Android mata el servicio:
   ↓
7. WorkManager (programado como backup) ejecuta cada 15 min
   ↓
8. LocationWorker envía coordenadas
   ↓
9. Si el usuario vuelve a abrir la app, volver al paso 1
```

---

## 📝 Cambios Necesarios en el Código Actual

### 1. Modificar `MainActivity.kt` para iniciar el servicio desde foreground:

```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    
    // Verificar si ya hay parámetros guardados
    val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
    val movil = prefs.getString("last_movil", "")
    
    if (!movil.isNullOrEmpty()) {
        // Re-iniciar el servicio desde foreground
        val intent = Intent(this, ForegroundLocationService::class.java).apply {
            putExtra("movil", movil)
            putExtra("escenario", prefs.getString("last_escenario", ""))
            putExtra("usuario", prefs.getString("last_usuario", ""))
            putExtra("deviceId", prefs.getString("last_deviceId", ""))
            putExtra("intervalMinutes", prefs.getInt("last_interval", 3))
            putExtra("EXECUTE_GPS", false) // Modo foreground
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        
        Log.d("MainActivity", "✅ Servicio re-iniciado desde foreground")
    }
}
```

### 2. Modificar `ForegroundLocationService.onStartCommand()`:

```kotlin
override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    // ... código existente ...
    
    if (!executeGps) {
        // Modo FOREGROUND: programar AlarmManager para intervalos cortos
        LocationHelper.scheduleLocationAlarm(
            this, intervalMinutes, movil, escenario, usuario, deviceId
        )
        
        // TAMBIÉN programar WorkManager como backup (intervalo más largo)
        WorkManagerHelper.schedulePeriodicLocationWork(
            this, 15, movil, escenario, usuario, deviceId
        )
        
        Log.d(TAG, "✅ Dual mode: AlarmManager (3min) + WorkManager (15min)")
    }
    
    return START_STICKY
}
```

### 3. Probar con logs:

```bash
# Verificar que WorkManager se programó correctamente
adb shell dumpsys jobscheduler | Select-String "LocationWorker"

# Debería mostrar algo como:
# JOB #u0a447/123: com.example.moveit/androidx.work.impl.background.systemjob.SystemJobService
```

---

## ✅ PRÓXIMOS PASOS

1. **Compilar con WorkManager agregado**:
   ```bash
   flutter build apk --release
   ```

2. **Instalar y probar**:
   ```bash
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```

3. **Abrir la app** (para iniciar el servicio desde foreground)

4. **Cerrar la app completamente**:
   ```bash
   adb shell am force-stop com.example.moveit
   ```

5. **Verificar que WorkManager sigue activo**:
   ```bash
   adb shell dumpsys jobscheduler | Select-String "moveit"
   ```

6. **Esperar 15 minutos** y ver logs:
   ```bash
   adb logcat | Select-String "LocationWorker|WorkManagerHelper"
   ```

---

## 🎯 Decisión Final

**¿Qué estrategia usar?**

### Si necesitas **envíos cada 3 minutos** de forma crítica:
→ **Opción 2** (Híbrido): Mantener ForegroundService activo + AlarmManager  
→ Requiere que el usuario abra la app después de reboot

### Si puedes aceptar **envíos cada 15 minutos**:
→ **Opción 3** (WorkManager puro): Máxima confiabilidad  
→ Funciona incluso sin que el usuario abra la app

### **RECOMENDACIÓN**: Usar estrategia híbrida (ambas):
- **AlarmManager para 3 min** cuando la app está activa
- **WorkManager para 15 min** como backup cuando la app está cerrada
- Esto garantiza que SIEMPRE haya coordenadas, aunque sea a diferentes intervalos

---

**Fecha de Documentación**: 14 de Octubre, 2025  
**Status**: ⚠️ Solución WorkManager implementada, falta integrar en MainActivity  
**Próximo paso**: Decidir estrategia final e implementar cambios en MainActivity.kt
