# 🔧 Sistema de Recuperación Automática de MovilId

## 📋 Problema

Cuando el servicio GPS muere y el watchdog intenta reiniciarlo, a veces el `movil` está vacío en SharedPreferences, lo que impide que el servicio pueda reiniciarse automáticamente.

**Error típico:**
```
⚠️ No se puede reiniciar GPS service: movil vacío
❌ [CRITICAL] WATCHDOG: No se puede reiniciar GPS service - movil vacío
```

## ✅ Solución Implementada

Sistema de recuperación automática con **3 niveles de prioridad** para obtener el MovilId:

### 🎯 Estrategia de Recuperación

```
┌─────────────────────────────────────────────┐
│    1️⃣ Flutter SharedPreferences            │
│    (Prioridad más alta)                    │
│                                            │
│    Keys intentadas:                        │
│    - flutter.movil                         │
│    - flutter.Movil                         │
│    - movil                                 │
│    - Movil                                 │
└─────────────────────────────────────────────┘
                    ↓ Si falla
┌─────────────────────────────────────────────┐
│    2️⃣ Native SharedPreferences             │
│    (Prioridad media)                       │
│                                            │
│    Key: config.last_movil                  │
└─────────────────────────────────────────────┘
                    ↓ Si falla
┌─────────────────────────────────────────────┐
│    3️⃣ API /GetMovilActivo                  │
│    (Último recurso)                        │
│                                            │
│    POST /GetMovilActivo                    │
│    Body: {"DeviceId": "xxx"}               │
│    Response: {"MovilId": "693"}            │
└─────────────────────────────────────────────┘
                    ↓ Si recupera exitosamente
┌─────────────────────────────────────────────┐
│    💾 Guardar en ambos SharedPreferences   │
│    Para evitar futuros problemas           │
└─────────────────────────────────────────────┘
```

## 📁 Archivos Creados/Modificados

### 1. **MovilRecoveryHelper.kt** (NUEVO)

Clase helper para recuperar MovilId usando múltiples estrategias:

```kotlin
suspend fun recoverMovilId(context: Context, deviceId: String): String?
```

**Funciones:**
- `tryRecoverFromFlutterPrefs()` - Intenta recuperar desde Flutter
- `tryRecoverFromNativePrefs()` - Intenta recuperar desde nativo
- `tryRecoverFromApi()` - Consulta API /GetMovilActivo
- `saveMovilToPreferences()` - Guarda MovilId recuperado

### 2. **ServiceWatchdog.kt** (MODIFICADO)

Cambios en `restartGPSService()`:

```kotlin
suspend fun restartGPSService(context: Context): Boolean {
    // ...
    
    // Validación 1: Movil vacío - INTENTAR RECUPERAR
    if (movil.isEmpty()) {
        Log.w(TAG, "⚠️ [RECOVERY] Movil vacío, intentando recuperar...")
        
        // 1. Intentar recuperar deviceId si también está vacío
        if (deviceId.isEmpty()) {
            // Recuperar desde Flutter SharedPreferences
        }
        
        // 2. Usar MovilRecoveryHelper para recuperar movil
        val recoveredMovil = MovilRecoveryHelper.recoverMovilId(context, deviceId)
        
        if (recoveredMovil != null) {
            movil = recoveredMovil
            // Guardar y continuar
        } else {
            // Fallo total, no se puede reiniciar
            return false
        }
    }
    
    // Continuar con reinicio normal...
}
```

**Cambio importante:** Función cambió de `fun` a `suspend fun` para permitir llamadas asíncronas a la API.

### 3. **CriticalLogAlarmReceiver.kt** (MODIFICADO)

Cambios en `performWatchdogCheck()` para llamar a `restartGPSService` con coroutines:

```kotlin
private fun performWatchdogCheck(context: Context) {
    // ...
    
    // Reiniciar GPS Service usando coroutine (porque ahora es suspend)
    CoroutineScope(Dispatchers.Default).launch {
        try {
            val restarted = ServiceWatchdog.restartGPSService(context)
            
            if (restarted) {
                Log.i(TAG, "✅ [WATCHDOG] GPS Service reiniciado exitosamente")
                // ...
            } else {
                Log.e(TAG, "❌ [WATCHDOG] FALLO al reiniciar GPS Service")
                // ...
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ [WATCHDOG] Excepción al reiniciar GPS Service", e)
            // ...
        }
    }
}
```

## 🌐 API /GetMovilActivo

### Endpoint

```
POST https://www.riogas.uy/ica_geos_/appservices/GetMovilActivo
```

O en desarrollo:
```
POST http://190.64.89.170:8888/ICA_Geos_/appservices/GetMovilActivo
```

### Request

```json
{
  "DeviceId": "ed90b721e7b3444d"
}
```

### Response

```json
{
  "MovilId": "693"
}
```

### Configuración

La URL base se obtiene automáticamente desde `FlutterSharedPreferences.flutter.baseUrl`, respetando el ambiente (desarrollo/producción) configurado en la app.

## 📊 Logging

### Logs de Recuperación Exitosa

```
🔍 [RECOVERY] Iniciando proceso de recuperación de MovilId...
🔍 [RECOVERY] DeviceId: ed90b721e7b3444d
🔍 [RECOVERY] Intentando recuperar desde Flutter SharedPreferences...
   ✅ Encontrado en clave 'flutter.movil': 693
✅ [RECOVERY] MovilId recuperado desde Flutter SharedPreferences: 693
```

### Logs de Recuperación desde API

```
🔍 [RECOVERY] Iniciando proceso de recuperación de MovilId...
🔍 [RECOVERY] Intentando recuperar desde Flutter SharedPreferences...
   ❌ No encontrado en Flutter SharedPreferences
🔍 [RECOVERY] Intentando recuperar desde Native SharedPreferences...
   ❌ No encontrado en Native SharedPreferences
🔍 [RECOVERY] Intentando recuperar desde API /GetMovilActivo...
   📱 DeviceId: ed90b721e7b3444d
   🌐 URL: https://www.riogas.uy/ica_geos_/appservices/GetMovilActivo
   📤 Request body: {"DeviceId":"ed90b721e7b3444d"}
   📥 Response code: 200
   📥 Response: {"MovilId":"693"}
   ✅ MovilId obtenido desde API: 693
✅ [RECOVERY] MovilId recuperado desde API: 693
💾 [RECOVERY] MovilId guardado en Native SharedPreferences
💾 [RECOVERY] MovilId guardado en Flutter SharedPreferences
```

### Logs de Fallo Total

```
🔍 [RECOVERY] Iniciando proceso de recuperación de MovilId...
🔍 [RECOVERY] Intentando recuperar desde Flutter SharedPreferences...
   ❌ No encontrado en Flutter SharedPreferences
🔍 [RECOVERY] Intentando recuperar desde Native SharedPreferences...
   ❌ No encontrado en Native SharedPreferences
🔍 [RECOVERY] Intentando recuperar desde API /GetMovilActivo...
   ❌ Error HTTP 404: Device not found
❌ [RECOVERY] No se pudo recuperar MovilId por ningún método
❌ [RECOVERY] No se pudo recuperar movil después de intentar todos los métodos
```

### CriticalLogger (enviado a n8n)

Todos los intentos de recuperación se loguean en `CriticalLogger` para monitoreo en n8n:

**Recuperación exitosa:**
```json
{
  "tag": "MOVIL_RECOVERY_FLUTTER_SUCCESS",
  "message": "RECOVERY SUCCESS: MovilId recuperado desde Flutter SharedPreferences",
  "movil": "693",
  "deviceId": "ed90b721e7b3444d",
  "recovery_method": "flutter_shared_prefs",
  "priority": "1"
}
```

**Fallo total:**
```json
{
  "tag": "MOVIL_RECOVERY_ALL_FAILED",
  "message": "RECOVERY FAILED: No se pudo recuperar MovilId después de intentar todos los métodos",
  "deviceId": "ed90b721e7b3444d",
  "flutter_prefs": "failed",
  "native_prefs": "failed",
  "api_call": "failed",
  "all_methods_exhausted": "true"
}
```

## 🔍 Comandos de Monitoreo

### Filtrar logs de recuperación

```powershell
adb logcat | Select-String "RECOVERY|MovilRecoveryHelper"
```

### Ver solo recuperaciones exitosas

```powershell
adb logcat | Select-String "RECOVERY.*recuperado|MovilId obtenido"
```

### Ver fallos de recuperación

```powershell
adb logcat *:E | Select-String "RECOVERY|movil"
```

### Monitor completo del watchdog con recuperación

```powershell
adb logcat -v time | Select-String "WATCHDOG|RECOVERY|MovilRecoveryHelper|GPS Service MUERTO"
```

## 🎯 Beneficios

1. **Auto-recuperación:** El servicio GPS puede reiniciarse incluso si SharedPreferences se corrompe
2. **Triple redundancia:** 3 métodos independientes de recuperación
3. **Priorización inteligente:** Intenta fuentes locales antes de llamar a la API
4. **Sin intervención manual:** El sistema se auto-repara sin necesidad de reinstalar o reloguearse
5. **Monitoreo completo:** Todos los intentos se loguean en n8n para análisis
6. **Persistencia:** Guarda el MovilId recuperado para evitar futuras recuperaciones

## ⚠️ Consideraciones

### Seguridad
- La API `/GetMovilActivo` debe validar que el DeviceId existe y tiene una sesión activa
- Considerar rate limiting si hay muchas llamadas fallidas

### Performance
- Los intentos de recuperación son secuenciales (no paralelos) para evitar conflictos
- Si la API es lenta, puede demorar hasta 10 segundos (timeout configurado)
- La recuperación solo se intenta cuando el watchdog detecta servicio muerto (no en cada verificación)

### Casos Edge
- Si el dispositivo no tiene sesión activa, la API debe retornar error 404
- Si Flutter SharedPreferences no está inicializado, se salta ese paso automáticamente
- Si no hay conexión a internet, la API fallará y se reportará el error

## 📝 Pruebas Recomendadas

### Prueba 1: Borrar SharedPreferences y verificar recuperación
```bash
# Borrar SharedPreferences nativo
adb shell run-as com.example.moveit rm /data/data/com.example.moveit/shared_prefs/config.xml

# Monitorear logs
adb logcat -c && adb logcat | Select-String "RECOVERY|WATCHDOG"
```

### Prueba 2: Simular muerte del servicio GPS
```bash
# Detener servicio GPS
adb shell am force-stop com.example.moveit

# Esperar 30 segundos (próxima verificación del watchdog)
# Monitorear recuperación automática
adb logcat | Select-String "GPS Service MUERTO|RECOVERY"
```

### Prueba 3: Verificar respuesta de API
```bash
# Llamar API manualmente (reemplazar DeviceId)
curl -X POST https://www.riogas.uy/ica_geos_/appservices/GetMovilActivo \
  -H "Content-Type: application/json" \
  -d '{"DeviceId":"ed90b721e7b3444d"}'
```

## 🚀 Próximos Pasos

1. ✅ Implementar recuperación de MovilId (COMPLETADO)
2. ✅ Integrar con ServiceWatchdog (COMPLETADO)
3. ✅ Logging exhaustivo en CriticalLogger (COMPLETADO)
4. ⏳ Implementar endpoint `/GetMovilActivo` en backend
5. ⏳ Configurar alertas en n8n para fallos de recuperación
6. ⏳ Monitorear en producción durante 1 semana
7. ⏳ Analizar logs y ajustar timeouts si es necesario

## 📚 Referencias

- [ServiceWatchdog.kt](./ServiceWatchdog.kt) - Lógica de watchdog
- [MovilRecoveryHelper.kt](./MovilRecoveryHelper.kt) - Helper de recuperación
- [CriticalLogAlarmReceiver.kt](./CriticalLogAlarmReceiver.kt) - Alarma de verificación
- [CriticalLogger.kt](./CriticalLogger.kt) - Logger para n8n
