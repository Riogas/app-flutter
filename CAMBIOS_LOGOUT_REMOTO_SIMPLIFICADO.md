# 🔄 Cambios Realizados: Logout Remoto Simplificado

## 📋 Resumen de Cambios

Se ha simplificado el sistema de logout remoto para que funcione **igual que `force_gps_execution`**: 
- FCM solo envía la **acción** (`logout_user`)
- **NO** se envían parámetros (movil, escenario, usuario, deviceId)
- Los datos se obtienen automáticamente desde **Hive** (Flutter) y **SharedPreferences** (Kotlin)

---

## ✅ Archivos Modificados

### 1. **FcmPushReceiver.kt**
**Ubicación**: `android/app/src/main/kotlin/com/riogas/appmovil/FcmPushReceiver.kt`

**Cambio**:
```kotlin
// ANTES: Broadcast con parámetros
val intent = Intent("com.riogas.appmovil.REMOTE_LOGOUT").apply {
    putExtra("movil", movil)
    putExtra("escenario", escenario)
    putExtra("usuario", usuario)
    putExtra("deviceId", deviceId)
    putExtra("logout_type", "remote")
}

// DESPUÉS: Broadcast sin parámetros
val intent = Intent("com.riogas.appmovil.REMOTE_LOGOUT")
intent.setPackage(packageName)
// Flutter obtiene datos desde Hive
```

**Razón**: Los datos ya están en SharedPreferences desde el login, no necesitan enviarse por FCM.

---

### 2. **MainActivity.kt**
**Ubicación**: `android/app/src/main/kotlin/com/example/moveit/MainActivity.kt`

**Cambio**:
```kotlin
// ANTES: Enviar parámetros a Flutter
remoteLogoutChannel?.invokeMethod("onRemoteLogout", mapOf(
    "movil" to movil,
    "escenario" to escenario,
    "usuario" to usuario,
    "deviceId" to deviceId,
    "logoutType" to logoutType,
    "timestamp" to System.currentTimeMillis()
))

// DESPUÉS: Solo enviar señal
remoteLogoutChannel?.invokeMethod("onRemoteLogout", mapOf(
    "timestamp" to System.currentTimeMillis()
))
```

**Razón**: Flutter obtiene los datos directamente de Hive, no necesita recibirlos del broadcast.

---

### 3. **RemoteLogoutListener.dart**
**Ubicación**: `lib/services/remote_logout_listener.dart`

**Cambio**:
```dart
// ANTES: Extraer parámetros del evento
final args = call.arguments as Map<dynamic, dynamic>;
final movil = args['movil'] as String? ?? '';
final usuario = args['usuario'] as String? ?? '';
// ...
await LogoutService.executeLogout(
  isRemoteLogout: true,
  nombreUsuario: usuario,
  idUsuario: usuario,
  deviceId: deviceId,
);

// DESPUÉS: Sin parámetros, obtener de Hive
await LogoutService.executeLogout(isRemoteLogout: true);
```

**Razón**: LogoutService internamente lee los datos de Hive.

---

### 4. **LogoutService.dart**
**Ubicación**: `lib/services/logout_service.dart`

**Cambio**:
```dart
// ANTES: Usar parámetros recibidos o fallback a Hive
final usuario = sessionBox.get('username') ?? idUsuario ?? "string";
final idTerminal = sessionBox.get('deviceId') ?? deviceId ?? "";

// DESPUÉS: Siempre usar Hive como source of truth
final usuario = sessionBox.get('username') ?? "string";
final idTerminal = sessionBox.get('deviceId') ?? "";
```

**Razón**: Hive es la fuente de verdad, los parámetros externos son opcionales solo para compatibilidad.

---

### 5. **FCM_REMOTE_LOGOUT_SYSTEM.md**
**Ubicación**: `appmovil/FCM_REMOTE_LOGOUT_SYSTEM.md`

**Cambios**:
- ✅ Actualizado ejemplo de FCM (solo enviar `action: "logout_user"`)
- ✅ Actualizado flujo de ejecución (sin parámetros)
- ✅ Agregadas notas sobre `watchdog_disabled` flag

---

## 🎯 Beneficios de los Cambios

### 1. **Consistencia con `force_gps_execution`**
Ambos comandos FCM funcionan igual:
```json
{ "action": "force_gps_execution" }  // Solo acción
{ "action": "logout_user" }          // Solo acción
```

### 2. **Menos complejidad**
- ❌ **Antes**: 5 parámetros en FCM (movil, escenario, usuario, deviceId, logout_type)
- ✅ **Después**: 0 parámetros, solo la acción

### 3. **Source of truth único**
- **Kotlin**: SharedPreferences (`last_movil`, `last_escenario`, `last_usuario`, `last_deviceId`)
- **Flutter**: Hive (`sessionBox`)
- **Ambos** sincronizados desde el login

### 4. **Menos errores potenciales**
- No hay riesgo de enviar datos incorrectos en FCM
- No hay desincronización entre FCM y Hive
- Simplifica testing (solo enviar acción)

---

## 🔒 Flags de Control de Servicios

### **`service_disabled`**
- **Propósito**: Marcar que los servicios fueron detenidos manualmente
- **Valor**: `true` cuando se ejecuta logout (manual o remoto)
- **Efecto**: Los servicios NO se reinician automáticamente

### **`watchdog_disabled`** 🚫 **CRÍTICO**
- **Propósito**: **INHABILITAR el watchdog** que reinicia servicios cada 30 segundos
- **Valor**: `true` cuando se ejecuta logout remoto
- **Efecto**: 
  - ✅ ServiceWatchdog NO reinicia GPS cuando detecta que está muerto
  - ✅ CriticalLogAlarmReceiver NO reinicia CriticalLog cuando detecta que no está programado
  - ✅ ForegroundLocationService NO reinicia CriticalLog en sus verificaciones
  - ✅ Los servicios permanecen detenidos hasta que el usuario **inicie sesión de nuevo**

### Flujo de flags:

```
Logout (manual o remoto)
    ↓
service_disabled = true       // Marcar como detenido
watchdog_disabled = true      // 🔒 BLOQUEAR watchdog
    ↓
ServiceWatchdog verifica cada 30 seg
    ↓
¿watchdog_disabled == true?
    └─ SÍ → 🛑 NO reiniciar servicios (respetar logout)
    └─ NO → ✅ Reiniciar servicios normalmente
    ↓
Usuario inicia sesión de nuevo
    ↓
service_disabled = false      // Habilitar servicios
watchdog_disabled = false     // 🔓 DESBLOQUEAR watchdog
    ↓
Servicios inician normalmente
```

---

## 📨 Ejemplo de Uso (FCM desde Servidor)

### Node.js (Firebase Admin SDK)
```javascript
const admin = require('firebase-admin');

async function sendRemoteLogout(fcmToken) {
  const message = {
    token: fcmToken,
    data: {
      action: 'logout_user'  // Solo la acción
    }
  };
  
  const response = await admin.messaging().send(message);
  console.log('✅ Logout remoto enviado:', response);
}

// Uso
sendRemoteLogout('fcm_token_del_usuario_a_cerrar_sesion');
```

### cURL
```bash
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=YOUR_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "fcm_token_del_usuario",
    "data": {
      "action": "logout_user"
    }
  }'
```

---

## 🧪 Testing

### 1. **Test Manual**
```bash
# 1. Login en la app con usuario de prueba
# 2. Obtener FCM token del dispositivo (desde logs o Firestore)
# 3. Enviar comando FCM:

curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=YOUR_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "fcm_token_aqui",
    "data": { "action": "logout_user" }
  }'

# 4. Verificar en Logcat:
#    ✅ GPS Service detenido
#    ✅ Alarmas canceladas
#    ✅ service_disabled=true
#    ✅ watchdog_disabled=true  <-- CRÍTICO
#    ✅ Broadcast enviado
#    ✅ Flutter ejecuta logout
#    ✅ App se cierra

# 5. Reabrir app:
#    ✅ Redirige a LoginPage
#    ✅ Hive boxes vacías
#    ✅ Servicios NO se reinician automáticamente (watchdog_disabled=true)

# 6. Login de nuevo:
#    ✅ Servicios inician normalmente
#    ✅ watchdog_disabled=false (watchdog reactivado)
```

### 2. **Verificar Flags**
```kotlin
// En Logcat, buscar:
D/FCM: 🚫 [FCM] Servicios deshabilitados + Watchdog deshabilitado
D/ServiceWatchdog: 🚫 Watchdog deshabilitado, no se reinician servicios
```

---

## 📊 Comparación: Antes vs Después

| Aspecto | Antes | Después |
|---------|-------|---------|
| **FCM payload** | 5 parámetros (movil, escenario, usuario, deviceId, logout_type) | 1 parámetro (action) |
| **Broadcast (Kotlin)** | Con 5 extras | Sin extras |
| **MethodChannel (Flutter)** | Con 6 campos | Solo timestamp |
| **LogoutService** | Usa parámetros recibidos | Usa Hive (source of truth) |
| **Consistencia** | Diferente a `force_gps_execution` | Igual que `force_gps_execution` |
| **Complejidad** | Alta (múltiples puntos de datos) | Baja (solo acción) |
| **Riesgo de error** | Alto (datos pueden desincronizarse) | Bajo (un solo source of truth) |

---

## ✅ Checklist de Validación

- [x] FcmPushReceiver.kt - Broadcast sin parámetros
- [x] MainActivity.kt - MethodChannel sin parámetros
- [x] RemoteLogoutListener.dart - Sin extraer parámetros
- [x] LogoutService.dart - Obtiene datos de Hive
- [x] FCM_REMOTE_LOGOUT_SYSTEM.md - Documentación actualizada
- [x] settings_page.dart - Usa LogoutService (sin cambios necesarios)
- [x] **watchdog_disabled flag** - Inhabilita watchdog correctamente

---

## 🎯 Próximos Pasos

1. **Testing exhaustivo**:
   - Probar logout remoto con usuario activo
   - Verificar que servicios NO se reinician automáticamente
   - Verificar que flags `watchdog_disabled` se respetan
   - Probar que después de login los servicios funcionan normalmente

2. **Monitoreo**:
   - Verificar logs en CriticalLogger
   - Revisar documentos en Firestore
   - Confirmar que Hive se limpia correctamente

3. **Documentación adicional**:
   - Agregar ejemplos de integración con n8n
   - Documentar casos edge (app en background, sin internet, etc.)

---

**Última actualización**: 2025-01-22  
**Versión**: 2.0.0 (Simplificado)  
**Cambio principal**: FCM solo envía acción, datos desde Hive
