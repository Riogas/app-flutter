# 🚨 WorkManager NO Ejecuta - Diagnóstico Completo

## ❓ Problema
El proceso automático de envío de logs cada 10 minutos NO se ejecuta en algunos dispositivos (móvil 693), aunque `debugMode=true` en Firestore.

---

## 🔍 Causas Posibles (Ordenadas por Probabilidad)

### 1️⃣ **Restricciones de Batería / Doze Mode** (50% probabilidad)
**Síntoma:** WorkManager programado correctamente pero Android MATA el proceso

#### ¿Por qué ocurre?
- Android 6+ tiene **Doze Mode** que suspende WorkManager en apps en background
- Algunos fabricantes (Huawei, Xiaomi, Samsung, Oppo) tienen **optimizadores agresivos** de batería
- La app NO está en la whitelist de optimización de batería

#### ✅ Cómo verificar
```kotlin
// Agregar al inicio de MainActivity
val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
val isIgnoringBatteryOptimizations = powerManager.isIgnoringBatteryOptimizations(packageName)

Log.i("MainActivity", "🔋 Battery optimization ignored: $isIgnoringBatteryOptimizations")
DebugLogger.i("MainActivity", "Battery status", mapOf(
    "isIgnoringOptimization" to isIgnoringBatteryOptimizations,
    "device" to Build.MANUFACTURER + " " + Build.MODEL,
    "android" to Build.VERSION.RELEASE
))
```

#### 🛠️ Solución
1. **Solicitar whitelist de batería:**
```kotlin
// En MainActivity, agregar método
private fun requestIgnoreBatteryOptimizations() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }
}
```

2. **Llamar al hacer login o activar debugMode:**
```kotlin
// En setDebugMode handler
if (enabled) {
    requestIgnoreBatteryOptimizations()
    scheduleDebugLogUpload()
}
```

---

### 2️⃣ **Restricción de Conectividad** (30% probabilidad)
**Síntoma:** WorkManager espera red pero el dispositivo tiene WiFi/datos apagados

#### ¿Por qué ocurre?
El WorkManager está configurado con:
```kotlin
.setConstraints(
    androidx.work.Constraints.Builder()
        .setRequiredNetworkType(androidx.work.NetworkType.CONNECTED)
        .build()
)
```

Si el dispositivo:
- ✅ Tiene GPS encendido
- ❌ NO tiene WiFi ni datos móviles activos

➡️ **WorkManager NO SE EJECUTA** hasta que haya red

#### ✅ Cómo verificar
```kotlin
// Agregar logs en scheduleDebugLogUpload()
val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
val activeNetwork = connectivityManager.activeNetworkInfo
val hasInternet = activeNetwork?.isConnectedOrConnecting == true

Log.i("MainActivity", "🌐 Network status: hasInternet=$hasInternet, type=${activeNetwork?.typeName}")
DebugLogger.i("MainActivity", "Network check", mapOf(
    "hasInternet" to hasInternet,
    "networkType" to (activeNetwork?.typeName ?: "none"),
    "isConnected" to (activeNetwork?.isConnected ?: false)
))
```

#### 🛠️ Solución
**Opción 1:** Eliminar restricción de red (no recomendado, consume datos)
```kotlin
.setConstraints(
    androidx.work.Constraints.Builder()
        // NO agregar restricción de red
        .build()
)
```

**Opción 2:** Agregar WiFi/Datos como requisito en documentación
```markdown
REQUISITOS para debug logging:
- ✅ debugMode=true en Firestore
- ✅ App en whitelist de batería
- ✅ WiFi o datos móviles ACTIVOS (WorkManager requiere red)
```

---

### 3️⃣ **WorkManager NO Programado** (10% probabilidad)
**Síntoma:** El método `scheduleDebugLogUpload()` NO se ejecuta

#### ¿Por qué ocurre?
1. **Firestore listener NO recibe evento:** Documento mal configurado o no existe
2. **MethodChannel falla:** Comunicación Flutter ↔ Kotlin interrumpida
3. **Exception silenciosa:** Error en `scheduleDebugLogUpload()` no visible

#### ✅ Cómo verificar
Buscar en logs (ADB o DebugLogger):
```
[DEBE APARECER]:
✅ "📅 Programando WorkManager para upload de logs..."
✅ "📦 Work Request ID: xxxxxxxxx"
✅ "✅ WorkManager programado: cada 10 min, network required"

[SI NO APARECE]:
❌ WorkManager NO fue programado
```

#### 🛠️ Solución
Verificar con `dumpsys`:
```bash
adb shell dumpsys jobscheduler | grep "debug_log_upload"
```

Si NO aparece:
```
❌ WorkManager NO está programado
➡️ Revisar logs de DebugConfigManager (Flutter)
➡️ Revisar logs de MainActivity (Kotlin)
```

---

### 4️⃣ **WorkManager Cancelado por Android** (5% probabilidad)
**Síntoma:** WorkManager programado pero Android lo elimina

#### ¿Por qué ocurre?
- App forzada a cerrar (Force Stop)
- Actualización de sistema Android
- Límites de WorkManager alcanzados (100 workers simultáneos)
- Bug de fabricante (Xiaomi MIUI, Samsung OneUI)

#### ✅ Cómo verificar
```bash
# Ver estado de WorkManager
adb shell dumpsys jobscheduler | grep -A 30 "debug_log_upload"

# Buscar:
# - State: RUNNING / ENQUEUED / CANCELLED
# - Next run time: (timestamp futuro)
```

#### 🛠️ Solución
1. **Re-programar periódicamente:**
```kotlin
// En MainActivity, agregar método
private fun verifyWorkManagerScheduled() {
    val workManager = androidx.work.WorkManager.getInstance(applicationContext)
    val workInfos = workManager.getWorkInfosForUniqueWork("debug_log_upload").get()
    
    if (workInfos.isEmpty() || workInfos.all { it.state.isFinished }) {
        Log.w("MainActivity", "⚠️ WorkManager NO programado, re-programando...")
        scheduleDebugLogUpload()
    } else {
        Log.i("MainActivity", "✅ WorkManager activo: ${workInfos.first().state}")
    }
}
```

2. **Verificar en cada apertura de app:**
```kotlin
// En onCreate de MainActivity
if (DebugLogger.isEnabled()) {
    verifyWorkManagerScheduled()
}
```

---

### 5️⃣ **DebugLogger NO Habilitado en Kotlin** (3% probabilidad)
**Síntoma:** WorkManager ejecuta pero `DebugLogger.isEnabled()` retorna `false`

#### ¿Por qué ocurre?
El `setDebugMode` de Kotlin NO guarda el estado en SharedPreferences correctamente.

#### ✅ Cómo verificar
```kotlin
// Leer en MainActivity
val prefs = getSharedPreferences("debug_config", Context.MODE_PRIVATE)
val isEnabled = prefs.getBoolean("debug_enabled", false)

Log.i("MainActivity", "🐛 Debug enabled: $isEnabled")
```

#### 🛠️ Solución
Verificar que `setDebugMode` guarde en SharedPreferences:
```kotlin
// En MainActivity, handler de setDebugMode
val enabled = call.argument<Boolean>("enabled") ?: false
val level = call.argument<String>("level") ?: "INFO"

// Guardar en SharedPreferences
val prefs = getSharedPreferences("debug_config", Context.MODE_PRIVATE)
prefs.edit()
    .putBoolean("debug_enabled", enabled)
    .putString("debug_level", level)
    .apply()

// Actualizar DebugLogger
DebugLogger.setEnabled(enabled)
```

---

### 6️⃣ **Worker Falla al Ejecutar** (2% probabilidad)
**Síntoma:** WorkManager ejecuta pero `DebugLogUploadWorker` falla

#### ¿Por qué ocurre?
- Exception en `doWork()` de `DebugLogUploadWorker`
- n8n webhook NO responde (timeout)
- Buffer de logs vacío (nada que enviar)

#### ✅ Cómo verificar
Ver logs del Worker:
```
[DEBE APARECER CADA 10 MINUTOS]:
✅ "🚀 [RUN:timestamp] Ejecutando DebugLogUploadWorker..."
✅ "📦 [UPLOAD:timestamp] Enviando X logs a n8n..."
✅ "✅ [SUCCESS:timestamp] Logs enviados: X entries"

[SI NO APARECE]:
❌ Worker NO se ejecuta o falla silenciosamente
```

#### 🛠️ Solución
Agregar try-catch exhaustivo en `DebugLogUploadWorker.doWork()`:
```kotlin
override fun doWork(): Result {
    try {
        Log.i("DebugLogUploadWorker", "🚀 [RUN:${System.currentTimeMillis()}] Ejecutando worker...")
        
        // Verificar si debug está habilitado
        if (!DebugLogger.isEnabled()) {
            Log.w("DebugLogUploadWorker", "⚠️ Debug NO habilitado, cancelando...")
            return Result.success()
        }
        
        // Obtener logs del buffer
        val logs = DebugLogger.getBufferedLogs()
        if (logs.isEmpty()) {
            Log.i("DebugLogUploadWorker", "ℹ️ No hay logs para enviar")
            return Result.success()
        }
        
        // Enviar a n8n
        val success = uploadToN8n(logs)
        
        if (success) {
            Log.i("DebugLogUploadWorker", "✅ [SUCCESS:${System.currentTimeMillis()}] ${logs.size} logs enviados")
            return Result.success()
        } else {
            Log.e("DebugLogUploadWorker", "❌ [FAILED:${System.currentTimeMillis()}] Error enviando logs")
            return Result.retry()
        }
    } catch (e: Exception) {
        Log.e("DebugLogUploadWorker", "❌ [ERROR:${System.currentTimeMillis()}] Exception: ${e.message}", e)
        return Result.failure()
    }
}
```

---

## 🎯 Plan de Diagnóstico Paso a Paso

### Paso 1: Verificar si WorkManager está programado
```bash
adb shell dumpsys jobscheduler | grep "debug_log_upload"
```

**Si NO aparece:** ➡️ Problema en Flutter/Firestore (ver Paso 2)  
**Si SÍ aparece:** ➡️ Problema en ejecución (ver Paso 3)

---

### Paso 2: Verificar logs de programación
```bash
adb logcat | grep -E "DebugConfigManager|scheduleDebugLogUpload|WorkManager programado"
```

**Buscar:**
- ✅ `"🔔 Evento recibido desde Firestore"`
- ✅ `"✅ Configuración válida detectada"`
- ✅ `"📤 Enviando a Kotlin: enabled=true"`
- ✅ `"📅 Programando WorkManager para upload de logs..."`

**Si falta alguno:** ➡️ Problema en Firestore o listener

---

### Paso 3: Verificar restricciones de batería
```bash
adb shell dumpsys deviceidle whitelist | grep com.riogas.appmovil
```

**Si NO aparece:** ➡️ App NO está en whitelist
**Solución:** Solicitar ignorar optimización de batería

---

### Paso 4: Verificar conectividad
```bash
adb shell dumpsys connectivity
```

**Verificar:**
- ✅ Active network: WiFi o Mobile
- ✅ State: CONNECTED

**Si NO hay red:** ➡️ WorkManager esperará hasta que haya conexión

---

### Paso 5: Forzar ejecución manual
```bash
# Desde Flutter, llamar:
await DebugConfigManager.uploadLogsNow();
```

**Si funciona:** ➡️ Problema es de WorkManager periódico (restricciones)  
**Si NO funciona:** ➡️ Problema es de n8n o Worker

---

## 🛠️ Solución Definitiva: Logs Exhaustivos

### Modificar `scheduleDebugLogUpload()` en MainActivity.kt

```kotlin
private fun scheduleDebugLogUpload() {
    try {
        Log.i("MainActivity", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        Log.i("MainActivity", "📅 PROGRAMANDO WORKMANAGER")
        Log.i("MainActivity", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // 1️⃣ Verificar batería
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        val isIgnoringBatteryOpt = powerManager.isIgnoringBatteryOptimizations(packageName)
        Log.i("MainActivity", "🔋 Batería optimizada: ${!isIgnoringBatteryOpt}")
        Log.i("MainActivity", "   - Whitelist: $isIgnoringBatteryOpt")
        
        if (!isIgnoringBatteryOpt) {
            Log.w("MainActivity", "⚠️ ADVERTENCIA: App NO está en whitelist de batería")
            Log.w("MainActivity", "   - WorkManager puede NO ejecutarse en background")
            Log.w("MainActivity", "   - Solicitar al usuario ignorar optimización")
        }
        
        // 2️⃣ Verificar red
        val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
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
            "device" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "android" to Build.VERSION.RELEASE
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
```

---

## 📊 Tabla de Síntomas vs Causas

| Síntoma | Causa Probable | Solución |
|---------|----------------|----------|
| WorkManager NO aparece en `dumpsys` | Flutter no llama `scheduleLogUpload` | Verificar Firestore listener |
| WorkManager en `dumpsys` pero NO ejecuta | Batería optimizada | Whitelist batería |
| WorkManager ejecuta pero sin logs `[RUN:]` | Worker falla o `isEnabled()=false` | Verificar SharedPreferences |
| Logs `[RUN:]` pero sin `[UPLOAD:]` | Buffer vacío o n8n falla | Verificar red y n8n |
| Solo 1-2 dispositivos afectados | Fabricante agresivo (Xiaomi, Huawei) | Whitelist batería + guide usuario |

---

## ✅ Checklist de Verificación

- [ ] **Firestore:** Documento `Moviles-1000/Moviles-{movil}` existe
- [ ] **Firestore:** Campo `debugMode` es boolean `true` (NO string)
- [ ] **Listener:** Logs `"🔔 Evento recibido desde Firestore"` aparecen
- [ ] **MethodChannel:** Logs `"📤 Enviando a Kotlin"` aparecen
- [ ] **Kotlin:** Logs `"📅 Programando WorkManager"` aparecen
- [ ] **Dumpsys:** `debug_log_upload` aparece en `jobscheduler`
- [ ] **Batería:** App en whitelist (`isIgnoringBatteryOptimizations=true`)
- [ ] **Red:** WiFi o datos móviles activos
- [ ] **SharedPreferences:** `debug_enabled=true` guardado
- [ ] **Worker:** Logs `[RUN:timestamp]` aparecen cada 10 min

---

## 🚀 Próximos Pasos

1. **Agregar logs exhaustivos** a `scheduleDebugLogUpload()` (código arriba)
2. **Compilar APK** con los cambios
3. **Instalar en móvil 693**
4. **Monitorear logs** durante 15 minutos:
   ```bash
   adb logcat | grep -E "MainActivity|DebugLogUploadWorker|WorkManager"
   ```
5. **Verificar WorkManager programado:**
   ```bash
   adb shell dumpsys jobscheduler | grep "debug_log_upload"
   ```
6. **Si NO ejecuta:** Verificar batería y red según tabla de síntomas

---

## 📝 Notas Adicionales

- **WorkManager garantiza ejecución** pero NO garantiza tiempo exacto (puede retrasarse 5-15 min)
- **Android puede postergar** WorkManager si batería baja (<15%)
- **Algunos fabricantes** ignoran whitelist de batería (Xiaomi MIUI aggressive mode)
- **Alternativa:** Usar `AlarmManager` con `setExactAndAllowWhileIdle()` si WorkManager no funciona
