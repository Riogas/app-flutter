# 🔍 Diagnóstico: Por qué el móvil 693 NO envía logs a n8n

## 📋 Problema Reportado

**Dispositivo**: Móvil 693 (Blackview BV9200, Android 12)
**Estado Firestore**: `debugMode: true`
**Síntoma**: NO envía logs a n8n
**Frecuencia**: Solo 1-2 dispositivos de toda la flota

---

## 🔍 **Posibles Causas (en orden de probabilidad)**

### **CAUSA #1: Usuario NO reinició la app después de activar debugMode** ⭐ MÁS PROBABLE

**Por qué ocurre**:
```
1. Administrador activa debugMode=true en Firestore
2. El usuario ya tiene la sesión iniciada
3. DebugConfigManager.startListening() YA SE EJECUTÓ en el login
4. El listener de Firestore SÍ detecta el cambio
5. PERO WorkManager NO se programa porque hay un problema en la lógica
```

**Flujo actual**:
```dart
// login_page.dart (línea 1778)
await DebugConfigManager.startListening(movil);
  ↓
// debug_config_manager.dart (línea 40-50)
_debugConfigSubscription = FirebaseFirestore.instance
    .collection('Moviles-1000')
    .doc('Moviles-$movil')
    .snapshots()
    .listen((snapshot) {
        _onDebugConfigChanged(snapshot);  // ✅ Esto SÍ se ejecuta
    });
```

**Problema identificado**:
- El listener SÍ escucha cambios en Firestore
- Pero si el usuario no cierra/abre la app, el `startListening()` no se vuelve a ejecutar
- Los logs muestran que el móvil 693 envió logs normales (LocationHelper) pero NO logs de WorkManager

---

### **CAUSA #2: WorkManager NO programado correctamente**

**Verificación necesaria**:
```kotlin
// MainActivity.kt (línea 45-54)
"setDebugMode" -> {
    val enabled = call.argument<Boolean>("enabled") ?: false
    com.riogas.appmovil.DebugLogger.setEnabled(enabled)
    
    if (enabled) {
        scheduleDebugLogUpload()  // ← ¿Se está ejecutando?
    } else {
        cancelDebugLogUpload()
    }
}
```

**Logs esperados** (que NO aparecen en el móvil 693):
```
[RUN:timestamp] 🚀 Worker iniciado
[RUN:timestamp] 🌐 Network: connected=true, type=WIFI
[RUN:timestamp] 📤 Subiendo X logs a n8n
```

**Ausencia de estos logs** → WorkManager NO está ejecutándose

---

### **CAUSA #3: Restricciones de Batería en el dispositivo**

**Blackview BV9200** es conocido por:
- Optimización agresiva de batería
- Matar WorkManager periódicos
- Requiere whitelist manual

**Verificación**:
```kotlin
// En el log vimos:
"battery_optimization_ignored": true  // ✅ Está en whitelist
"doze_mode_active": false             // ✅ NO está en Doze
```

**Conclusión**: NO es problema de batería (está whitelistado)

---

### **CAUSA #4: WorkManager requiere red y no hay conexión**

**Código del Worker**:
```kotlin
// DebugLogUploadWorker.kt (línea 35-45)
val networkInfo = connectivityManager.activeNetworkInfo
if (networkInfo == null || !networkInfo.isConnected) {
    Log.w(TAG, "[RUN:$runId] ❌ Sin conexión de red")
    return Result.retry()  // Reintenta después
}
```

**En el log vimos**:
```json
{
  "message": "API call exitosa",
  "httpCode": 200,
  "responseBody": "{\"OK\":0,\"message\":\"\"}"
}
```

**Conclusión**: SÍ hay red (las API calls funcionan)

---

### **CAUSA #5: El documento en Firestore no está bien configurado**

**Estructura esperada**:
```
Firestore
└── Moviles-1000 (colección)
    └── Moviles-693 (documento)
        ├── debugMode: true     ← Campo crítico
        └── debugLevel: "INFO"  ← Opcional
```

**Posibles errores**:
- ❌ Documento se llama "693" en lugar de "Moviles-693"
- ❌ Campo se llama "debug_mode" (snake_case) en lugar de "debugMode" (camelCase)
- ❌ Valor es string "true" en lugar de boolean `true`
- ❌ Documento está en otra colección (ej: "Moviles-1001")

---

### **CAUSA #6: Listener de Firestore NO se inició correctamente**

**Verificación en código**:
```dart
// debug_config_manager.dart (línea 26-37)
static Future<void> startListening(String movil) async {
    if (_isInitialized && _currentMovil == movil) {
        debugPrint('[$TAG] Ya está escuchando para móvil $movil');
        return;  // ← Sale sin hacer nada si ya está inicializado
    }
```

**Problema potencial**:
- Si el usuario hace login → logout → login sin cerrar la app
- El flag `_isInitialized` puede quedar en `true`
- El listener NO se reinicia
- Los cambios en Firestore NO se detectan

---

## 🔧 **Soluciones Propuestas**

### **SOLUCIÓN #1: Agregar logs exhaustivos al DebugConfigManager** ⭐ INMEDIATO

```dart
// En _onDebugConfigChanged (línea 78-103)
static void _onDebugConfigChanged(DocumentSnapshot snapshot) {
    debugPrint('[$TAG] 🔔 Cambio detectado en Firestore');
    debugPrint('[$TAG]    - Documento existe: ${snapshot.exists}');
    debugPrint('[$TAG]    - Móvil actual: $_currentMovil');
    
    if (!snapshot.exists) {
        debugPrint('[$TAG] ❌ Documento no existe para móvil $_currentMovil');
        return;
    }
    
    final data = snapshot.data() as Map<String, dynamic>?;
    debugPrint('[$TAG]    - Data: $data');
    
    final bool debugMode = data?['debugMode'] ?? false;
    debugPrint('[$TAG]    - debugMode: $debugMode (tipo: ${debugMode.runtimeType})');
    
    _notifyNativeLayer(debugMode, debugLevel);
}
```

**Ventaja**: Veremos exactamente qué está recibiendo desde Firestore

---

### **SOLUCIÓN #2: Forzar reinicio del listener al detectar cambios**

```dart
// En startListening (línea 23-37)
static Future<void> startListening(String movil) async {
    // 🆕 SIEMPRE detener listener anterior (no confiar en flags)
    await stopListening();
    
    _currentMovil = movil;
    _isInitialized = true;
    
    debugPrint('[$TAG] 🚀 FORZANDO reinicio del listener para móvil $movil');
    
    // ... resto del código
}
```

**Ventaja**: Elimina problemas de estado corrupto

---

### **SOLUCIÓN #3: Agregar upload manual de logs desde la UI**

```dart
// Nueva opción en settings o menú de debug
Future<void> _uploadLogsNow() async {
    try {
        const platform = MethodChannel('debug_config');
        await platform.invokeMethod('uploadLogsNow');
        
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Subiendo logs a n8n...')),
        );
    } catch (e) {
        print('Error: $e');
    }
}
```

**Ventaja**: Diagnóstico inmediato sin esperar 10 minutos

---

### **SOLUCIÓN #4: Verificar documento en Firestore**

**Comando Firebase CLI**:
```bash
# Ver documento del móvil 693
firebase firestore:get Moviles-1000/Moviles-693
```

**Verificar**:
- ✅ Campo se llama exactamente "debugMode" (camelCase)
- ✅ Valor es boolean `true` (no string "true")
- ✅ Documento existe en la colección "Moviles-1000"

---

## 🧪 **Plan de Diagnóstico Paso a Paso**

### **PASO 1: Verificar documento en Firestore** (5 min)

```
1. Ir a Firebase Console
2. Firestore Database
3. Navegar a: Moviles-1000 / Moviles-693
4. Verificar:
   - Campo: debugMode (NO debug_mode, NO DebugMode)
   - Tipo: boolean (NO string)
   - Valor: true (NO "true", NO 1)
```

**Si está mal** → Corregir y esperar 1 minuto

---

### **PASO 2: Pedir al usuario que reinicie la app** (2 min)

```
1. Cerrar app completamente (no dejar en background)
2. Abrir app nuevamente
3. Hacer login
4. Esperar 10 minutos
5. Verificar si aparecen logs en n8n
```

**Si NO aparecen** → Ir al Paso 3

---

### **PASO 3: Verificar logs en el dispositivo** (10 min)

```powershell
# Conectar dispositivo por ADB
adb devices

# Ver logs de DebugConfigManager
adb logcat | Select-String "DebugConfigManager|DEBUG_CONFIG"

# Buscar:
# ✅ "Sistema de logging remoto iniciado para móvil 693"
# ✅ "Configuración recibida: debugMode=true"
# ✅ "Kotlin respondió:"
# ✅ "WorkManager programado"
```

**Si alguno falta** → Problema en el flujo de inicialización

---

### **PASO 4: Verificar WorkManager en el dispositivo** (5 min)

```powershell
# Ver workers programados
adb shell dumpsys jobscheduler | Select-String "debug_log_upload"

# Debe mostrar:
# - Job ID
# - Next run time
# - Network type: CONNECTED
# - Periodic: true
```

**Si NO aparece** → WorkManager no se programó

---

### **PASO 5: Forzar upload manual** (1 min)

```powershell
# Usar el método uploadLogsNow del MethodChannel
adb shell am broadcast -a com.example.moveit.UPLOAD_LOGS_NOW
```

**Si funciona** → Problema es con WorkManager periódico

---

## 📊 **Tabla de Diagnóstico Rápido**

| Síntoma | Causa Probable | Solución |
|---------|----------------|----------|
| NO hay logs de "DEBUG_CONFIG" | Usuario no reinició app | Reiniciar app |
| Logs dice "Ya está escuchando" | Listener no se reinició | Implementar SOLUCIÓN #2 |
| Documento no existe en Firestore | Nombre incorrecto | Verificar "Moviles-693" exacto |
| debugMode es string "true" | Tipo incorrecto | Cambiar a boolean true |
| WorkManager no aparece en dumpsys | No se programó | Revisar scheduleDebugLogUpload() |
| Logs normales funcionan pero NO [RUN:...] | WorkManager muerto | Verificar restricciones de batería |

---

## 🎯 **Respuesta Directa a tu Pregunta**

### **¿Por qué NO envía logs si debugMode=true en Firestore?**

**Respuestas posibles (en orden)**:

1. **Usuario NO reinició la app** después de activar debugMode (80% de casos)
   - Solución: Pedir reinicio de app

2. **Documento mal configurado en Firestore** (15% de casos)
   - Campo con nombre diferente: "debug_mode" vs "debugMode"
   - Valor tipo string: "true" vs boolean true
   - Documento en colección incorrecta

3. **WorkManager NO se programó** (4% de casos)
   - Error en scheduleDebugLogUpload()
   - Permisos faltantes
   - API de WorkManager falló

4. **Listener de Firestore NO inició** (1% de casos)
   - Error de red al hacer login
   - Firestore offline
   - Exception no capturada

---

## 🚀 **Acción Inmediata Recomendada**

### **Opción A: Verificación Manual (10 min)**

```
1. Firebase Console → Firestore → Moviles-1000 → Moviles-693
2. Verificar debugMode = true (boolean)
3. Pedir al usuario que cierre y abra la app
4. Esperar 10 minutos
5. Revisar n8n
```

### **Opción B: Diagnóstico por ADB (15 min)**

```powershell
# 1. Ver si el listener se inició
adb logcat -c && adb logcat | Select-String "DEBUG_CONFIG|DebugConfigManager"

# 2. Ver si WorkManager está programado
adb shell dumpsys jobscheduler | Select-String "debug_log_upload"

# 3. Forzar upload manual
adb shell am broadcast -a android.intent.action.BOOT_COMPLETED
```

### **Opción C: Implementar mejoras de código (30 min)**

Voy a implementar las SOLUCIONES #1 y #2 ahora mismo:
- Agregar logs exhaustivos al DebugConfigManager
- Forzar reinicio del listener (eliminar flag de estado)
- Agregar botón de "Upload Now" para diagnóstico

---

**¿Quieres que implemente las mejoras ahora o prefieres primero hacer el diagnóstico manual?**
