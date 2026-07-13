# 🚨 FORCE_GPS_EXECUTION - Comando de Emergencia Mejorado

## 🎯 Objetivo

Convertir el comando FCM `force_gps_execution` en un **comando de emergencia absoluto** que pueda recuperar dispositivos en cualquier estado, incluso cuando:
- ❌ No hay sesión activa
- ❌ `service_disabled=true`
- ❌ `watchdog_disabled=true`
- ❌ Datos corruptos en SharedPreferences

## 🔧 Cambios Implementados

### 1️⃣ Eliminada Verificación de Sesión

**ANTES (líneas 485-497):**
```kotlin
// 🔐 VALIDACIÓN #1: Verificar si hay sesión activa
if (!LocationHelper.isSessionActive(this)) {
    Log.w(TAG, "🚫 [FCM] [SESSION] No hay sesión activa, ignorando comando")
    CriticalLogger.logCritical(
        TAG,
        "FCM: Comando force_gps_execution ignorado (sin sesión activa)",
        mapOf("reason" to "No active Firebase session"),
        "FCM_COMMAND_IGNORED_NO_SESSION"
    )
    return  // ❌ BLOQUEABA la ejecución
}
```

**AHORA:**
```kotlin
// 🚨 FUERZA DE EMERGENCIA: NO verificar sesión, este comando SIEMPRE ejecuta
// Este comando está diseñado para recuperar dispositivos en estado corrupto
Log.w(TAG, "🚨 [FORCE_GPS] Comando de emergencia - ignorando verificación de sesión")
```

✅ **El comando SIEMPRE se ejecuta**, sin importar el estado de la sesión.

### 2️⃣ Limpieza Anticipada de Flags de Bloqueo

**NUEVA funcionalidad (agregada al inicio del método):**
```kotlin
// 🚨 PASO 1: LIMPIAR FLAGS DE BLOQUEO
Log.i(TAG, "🧹 [FORCE_GPS] Limpiando flags de bloqueo...")
prefs.edit().apply {
    putBoolean("service_disabled", false)      // ✅ Habilitar servicio
    putBoolean("watchdog_disabled", false)     // ✅ Habilitar watchdog
    remove("stop_reason")
    remove("stop_timestamp")
    remove("auto_stopped")
}.apply()
Log.i(TAG, "✅ [FORCE_GPS] Flags limpiados: service_disabled=false, watchdog_disabled=false")
```

**Efecto:**
- ✅ Elimina `service_disabled=true`
- ✅ Elimina `watchdog_disabled=true`
- ✅ Permite que el servicio GPS se inicie
- ✅ Permite que el watchdog vuelva a funcionar

### 3️⃣ Envío de Coordenada FORZADA Inmediata

**NUEVA funcionalidad:**
```kotlin
// 🚨 PASO 2: ENVIAR COORDENADA FORZADA INMEDIATA
Log.i(TAG, "📍 [FORCE_GPS] Enviando coordenada FORZADA inmediata...")

// Obtener última ubicación conocida
val locationManager = getSystemService(Context.LOCATION_SERVICE) as? android.location.LocationManager
val lastKnownLocation = locationManager?.getLastKnownLocation(GPS_PROVIDER)
    ?: locationManager?.getLastKnownLocation(NETWORK_PROVIDER)

if (lastKnownLocation != null) {
    // Enviar coordenada con móvil "FORZADA"
    LocationHelper.sendCoordinateToServer(
        context = this,
        lat = lastKnownLocation.latitude,
        lon = lastKnownLocation.longitude,
        speed = lastKnownLocation.speed.toDouble(),
        movil = "FORZADA",  // 🚨 Identificador especial
        escenario = escenario,
        usuario = usuario,
        deviceId = deviceId,
        isFirstCoordinate = false,
        accuracy = lastKnownLocation.accuracy.toDouble()
    )
    
    Log.i(TAG, "✅ [FORCE_GPS] Coordenada FORZADA enviada exitosamente")
}
```

**Características:**
- ✅ Envía coordenada **ANTES** de reiniciar el servicio GPS
- ✅ Usa `movil="FORZADA"` para identificarla en el servidor
- ✅ Obtiene la última ubicación conocida (GPS o Network)
- ✅ Loguea el evento en CriticalLogger
- ✅ Continúa aunque no haya ubicación disponible

### 4️⃣ Reinicio del Servicio GPS (sin cambios)

El resto del flujo continúa igual:
- Verifica si el servicio está corriendo
- Si está muerto, lo reinicia
- Si está vivo, lo mata y reinicia con datos frescos
- Ejecuta GPS inmediatamente con `EXECUTE_GPS=true`

## 📊 Flujo Completo del Comando

```
FCM Push: {action: "force_gps_execution"}
        ↓
┌───────────────────────────────────────────────┐
│ 1. IGNORAR verificación de sesión            │ 🆕
│    ✅ No importa si hay sesión o no           │
└───────────────────────────────────────────────┘
        ↓
┌───────────────────────────────────────────────┐
│ 2. LIMPIAR flags de bloqueo                  │ 🆕
│    ✅ service_disabled = false                │
│    ✅ watchdog_disabled = false               │
│    ✅ Eliminar stop_reason, stop_timestamp    │
└───────────────────────────────────────────────┘
        ↓
┌───────────────────────────────────────────────┐
│ 3. RECUPERAR datos desde SharedPreferences    │
│    • movil (config o flutter)                 │
│    • escenario (config o flutter)             │
│    • usuario (config o flutter)               │
│    • deviceId (config o flutter)              │
└───────────────────────────────────────────────┘
        ↓
┌───────────────────────────────────────────────┐
│ 4. OBTENER ubicación actual                  │ 🆕
│    • LastKnownLocation (GPS o Network)        │
│    • lat, lon, speed, accuracy                │
└───────────────────────────────────────────────┘
        ↓
┌───────────────────────────────────────────────┐
│ 5. ENVIAR coordenada FORZADA                 │ 🆕
│    ✅ movil = "FORZADA"                        │
│    ✅ Coordenada inmediata                    │
│    ✅ Log en CriticalLogger                   │
└───────────────────────────────────────────────┘
        ↓
┌───────────────────────────────────────────────┐
│ 6. VERIFICAR estado del servicio GPS         │
│    ¿Está corriendo?                           │
│    ├─ NO → Iniciar servicio con EXECUTE_GPS  │
│    └─ SÍ → Matar y reiniciar con datos frescos│
└───────────────────────────────────────────────┘
        ↓
┌───────────────────────────────────────────────┐
│ 7. INICIAR servicio GPS                      │
│    ✅ Servicio foreground iniciado            │
│    ✅ EXECUTE_GPS = true (ejecución inmediata)│
│    ✅ IS_FCM_FORCE = true (marca especial)    │
└───────────────────────────────────────────────┘
        ↓
┌───────────────────────────────────────────────┐
│ 8. LOGS de confirmación                      │
│    ✅ CriticalLogger: FORCE_GPS_SUCCESS       │
│    ✅ Watchdog habilitado de nuevo            │
│    ✅ Servicio GPS reportando                 │
└───────────────────────────────────────────────┘
```

## 🎯 Casos de Uso

### Caso 1: Dispositivo con `watchdog_disabled=true`
**Antes:**
```
1. Watchdog detecta servicio muerto
2. No puede reiniciar (watchdog_disabled=true)
3. Envía comando FCM force_gps_execution
4. FCM verifica sesión → NO HAY SESIÓN
5. IGNORA el comando ❌
6. GPS sigue muerto ❌
```

**Ahora:**
```
1. Watchdog detecta servicio muerto
2. No puede reiniciar (watchdog_disabled=true)
3. Envía comando FCM force_gps_execution
4. FCM IGNORA verificación de sesión ✅
5. LIMPIA watchdog_disabled=false ✅
6. ENVÍA coordenada FORZADA ✅
7. REINICIA servicio GPS ✅
8. GPS vuelve a reportar ✅
```

### Caso 2: Dispositivo sin sesión activa
**Antes:**
```
1. Usuario cierra app sin hacer logout
2. SharedPreferences quedan vacíos/corruptos
3. FCM force_gps_execution llega
4. isSessionActive() → false
5. IGNORA el comando ❌
```

**Ahora:**
```
1. Usuario cierra app sin hacer logout
2. SharedPreferences quedan vacíos/corruptos
3. FCM force_gps_execution llega
4. IGNORA isSessionActive() ✅
5. RECUPERA datos desde Flutter prefs ✅
6. ENVÍA coordenada FORZADA ✅
7. REINICIA servicio GPS ✅
```

### Caso 3: Servicio detenido manualmente
**Antes:**
```
1. Usuario detiene GPS desde la app
2. service_disabled=true, watchdog_disabled=true
3. FCM force_gps_execution llega
4. Verifica sesión, pero flags siguen activos
5. Servicio NO se inicia ❌
```

**Ahora:**
```
1. Usuario detiene GPS desde la app
2. service_disabled=true, watchdog_disabled=true
3. FCM force_gps_execution llega
4. LIMPIA TODOS los flags ✅
5. ENVÍA coordenada FORZADA ✅
6. REINICIA servicio GPS ✅
7. Watchdog vuelve a funcionar ✅
```

## 🔍 Identificación de Coordenadas FORZADAS

### En los Logs (CriticalLogger):
```json
{
  "tag": "FcmPushReceiver",
  "message": "FORCE_GPS: Coordenada FORZADA enviada",
  "errorType": "FORCE_GPS_COORDINATE_SENT",
  "extras": {
    "movil": "FORZADA",           // 🔑 Identificador clave
    "escenario": "1000",
    "lat": "-34.9011",
    "lon": "-56.1645",
    "speed": "0.0",
    "accuracy": "15.5",
    "trigger": "fcm_force_gps_execution"
  }
}
```

### En el Servidor (RegistrarCoordenadasV2):
```json
{
  "movil": "FORZADA",             // 🚨 Móvil especial
  "escenarioid": 1000,
  "lat": -34.9011,
  "lon": -56.1645,
  "velocidad": 0.0,
  "usuario": "49618553",
  "deviceId": "d50fc0701739e437",
  "timestamp": "2025-12-01T14:30:45.123Z"
}
```

**Consulta SQL para buscar coordenadas forzadas:**
```sql
SELECT * 
FROM coordenadas 
WHERE movil = 'FORZADA'
ORDER BY timestamp DESC;
```

## 📋 Logs Esperados

### Logs Exitosos:
```
🚨 [FORCE_GPS] Comando de emergencia - ignorando verificación de sesión
🧹 [FORCE_GPS] Limpiando flags de bloqueo...
✅ [FORCE_GPS] Flags limpiados: service_disabled=false, watchdog_disabled=false
📍 [FORCE_GPS] Enviando coordenada FORZADA inmediata...
📍 [FORCE_GPS] Ubicación obtenida: lat=-34.9011, lon=-56.1645, speed=0.0, accuracy=15.5
✅ [FORCE_GPS] Coordenada FORZADA enviada exitosamente
⚠️ [FCM] Servicio GPS muerto, reiniciándolo primero...
🔧 [FCM] Ambiente: DESARROLLO
🔧 [FCM] URL a usar: https://sgm.riogas.com.uy/appservices/
✅ [FCM] BaseUrl actualizada según ambiente antes de reiniciar servicio
✅ [FCM] Servicio reiniciado con ejecución inmediata
```

### Logs de Error (sin ubicación):
```
🚨 [FORCE_GPS] Comando de emergencia - ignorando verificación de sesión
🧹 [FORCE_GPS] Limpiando flags de bloqueo...
✅ [FORCE_GPS] Flags limpiados: service_disabled=false, watchdog_disabled=false
📍 [FORCE_GPS] Enviando coordenada FORZADA inmediata...
⚠️ [FORCE_GPS] No se pudo obtener ubicación, continuando con reinicio del servicio
✅ [FCM] Servicio reiniciado con ejecución inmediata
```

## ⚠️ Consideraciones Importantes

### 1. Permisos de Ubicación
- Si la app NO tiene permisos de ubicación, `lastKnownLocation` será `null`
- El comando CONTINÚA y reinicia el servicio GPS de todas formas
- La próxima coordenada vendrá con el móvil correcto

### 2. Móvil "FORZADA"
- **Ventaja**: Fácil de identificar en el servidor
- **Desventaja**: Si el servidor valida móviles, puede rechazar "FORZADA"
- **Solución alternativa**: Agregar sufijo al móvil real, ej: "134-FORZADA"

### 3. Coordenada de Red vs GPS
- `lastKnownLocation` puede venir de:
  - GPS (alta precisión, ~5-50m)
  - Network (baja precisión, ~100-1000m)
- La coordenada incluye `accuracy` para identificar la fuente

### 4. Sin Sesión en Firestore
- El comando FUNCIONA aunque no haya sesión en Firestore
- Recupera datos desde `FlutterSharedPreferences`
- Si NO hay datos, usa defaults: movil="0", escenario="0"

## 🚀 Deployment

### Compilar APK:
```bash
cd appmovil
flutter build apk --release
```

### Instalar en dispositivo:
```bash
flutter install
```

### Enviar comando desde servidor:
```bash
POST https://riogas.uy/ica_geos_/appservices/FCMActions
Content-Type: application/json

{
  "escenarioid": 1000,
  "movil": "134",
  "Accion": "force_gps_execution"
}
```

## 🧪 Testing

### Test 1: Dispositivo bloqueado
1. Detener GPS desde la app
2. Verificar flags: `service_disabled=true`, `watchdog_disabled=true`
3. Enviar comando `force_gps_execution`
4. Verificar:
   - ✅ Flags limpiados
   - ✅ Coordenada FORZADA enviada
   - ✅ Servicio GPS reiniciado

### Test 2: Sin sesión activa
1. Limpiar SharedPreferences: `adb shell pm clear com.example.moveit`
2. Enviar comando `force_gps_execution`
3. Verificar:
   - ✅ Comando ejecutado (no ignorado)
   - ✅ Datos recuperados desde Flutter prefs
   - ✅ Servicio GPS iniciado

### Test 3: Dispositivo en la calle
1. Enviar comando `force_gps_execution`
2. Esperar 30 segundos
3. Verificar en servidor:
   - ✅ Coordenada con movil="FORZADA" recibida
   - ✅ Coordenadas normales empiezan a llegar después

## 📝 Archivos Modificados

- **android/app/src/main/kotlin/com/riogas/appmovil/FcmPushReceiver.kt**
  - Líneas 482-640: `handleForceGpsExecution()` completamente rediseñado
  - Eliminada verificación de sesión
  - Agregada limpieza de flags al inicio
  - Agregado envío de coordenada FORZADA

## 🔗 Comandos Relacionados

- `restart_gps_service`: SÍ verifica sesión, reinicia servicio completo
- `stop_gps_service`: Detiene servicio y establece flags de bloqueo
- `force_gps_execution`: **NO verifica sesión**, limpia flags, envía coordenada, reinicia servicio

## ✅ Resultado Final

**El comando `force_gps_execution` es ahora un comando de EMERGENCIA ABSOLUTO que:**

✅ SIEMPRE se ejecuta (no importa el estado)
✅ LIMPIA todos los flags de bloqueo
✅ ENVÍA coordenada FORZADA inmediata
✅ REINICIA el servicio GPS
✅ RESTAURA el watchdog automático
✅ FUNCIONA sin sesión activa

**Es el comando de "último recurso" para recuperar dispositivos en cualquier estado.**
