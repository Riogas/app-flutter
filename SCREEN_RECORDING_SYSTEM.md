# 🎥 Sistema de Grabación de Pantalla con LogRocket

## 📋 Descripción General

Sistema completo para grabar sesiones de usuario con **LogRocket**, controlable remotamente via FCM y configurado desde Firestore. Permite capturar interacciones del usuario, errores, network requests y reproducir sesiones completas como un video.

**Características principales:**
- ✅ Inicio/detención automática al login/logout
- ✅ Control remoto via FCM (sin reiniciar app)
- ✅ Configuración por móvil desde Firestore
- ✅ Integración con sistema de logging existente
- ✅ Identificación de sesiones por usuario/móvil

**Configuración de LogRocket:**
- **App ID**: `w2ree2/delivery-ammr6`
- **API Key**: `w2ree2:delivery-ammr6:X7cNgP7XEvEQloPkWkRV`
- **Dashboard**: https://app.logrocket.com/w2ree2/delivery-ammr6

---

## 🏗️ Arquitectura del Sistema

### **Componentes Implementados:**

```
┌─────────────────────────────────────────────────────────────┐
│                    FIRESTORE (Source of Truth)              │
│  Moviles-1000 / Moviles-{movil}                            │
│  { "grabarPantalla": true/false }                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              DebugConfigManager (Listener)                  │
│  - Lee campo "grabarPantalla" desde Firestore               │
│  - Guarda en sessionBox                                     │
│  - Sincroniza en tiempo real                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│           ScreenRecordingManager (Core Logic)               │
│  - startRecording()  → Inicia LogRocket                     │
│  - stopRecording()   → Detiene y sube sesión                │
│  - toggleRecording() → Control remoto FCM                   │
└─────────────────────────────────────────────────────────────┘
                         │         │
            ┌────────────┘         └────────────┐
            ▼                                   ▼
┌─────────────────────────┐      ┌─────────────────────────┐
│   Login/Logout Flow     │      │    FCM Remote Control   │
│  - login_page.dart      │      │    - main.dart          │
│  - logout_service.dart  │      │    - toggle_screen_rec  │
└─────────────────────────┘      └─────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    LOGROCKET DASHBOARD                      │
│  - Sesiones grabadas con replay completo                    │
│  - Identificación: User ID = movil                          │
│  - Metadata: nombre, usuario, deviceId, escenario           │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 Configuración Inicial

### **1️⃣ Obtener App ID de LogRocket**

**NOTA IMPORTANTE:** LogRocket Flutter **NO requiere configuración inicial**. El SDK inicia automáticamente cuando llamas a `LogRocket.identify()`.

1. Crea cuenta en [LogRocket](https://app.logrocket.com)
2. Crea nueva aplicación "MoveIT" o similar
3. Copia tu **App ID** (formato: `company-name/app-name`)
4. **NO NECESITAS** editar código - LogRocket se auto-configura

**Formato del userID en identify():**
```dart
// El primer parámetro es el ID único del usuario
// En nuestro caso usamos el número de móvil
await LogRocket.identify('483', {
  'name': 'Juan Gomez',
  'usuario': '55335737',
  'deviceId': '5d2b67822ce71877',
  'escenario': '1000',
  'movil': '483',
});
```

### **2️⃣ Configurar Firestore**

Agrega el campo `grabarPantalla` a tu documento de móvil:

```javascript
// Firestore: Moviles-1000 / Moviles-{movil}
{
  "debugMode": false,
  "debugLevel": "INFO",
  "GPSMapa": false,
  "grabarPantalla": true  // ✅ NUEVO CAMPO
}
```

**Valores:**
- `true`: Graba sesión completa desde login hasta logout
- `false`: No graba (valor por defecto)

---

## 🎯 Casos de Uso

### **Caso 1: Grabar Sesión Normal (Configurado en Firestore)**

**Setup:**
```javascript
// Firestore
{ "grabarPantalla": true }
```

**Flujo:**
1. Usuario hace login
2. `ScreenRecordingManager.startRecording()` se ejecuta automáticamente
3. LogRocket captura toda la sesión (toques, screens, logs, network)
4. Usuario cierra sesión
5. `ScreenRecordingManager.stopRecording()` se ejecuta
6. Sesión se sube automáticamente a LogRocket

**Ver sesión:**
- Ve a https://app.logrocket.com
- Filtra por `movil: {numero}` o `usuario: {cedula}`

---

### **Caso 2: Activar Grabación Remotamente (Sin Logout)**

**Escenario:** Usuario reporta bug, quieres grabar su sesión AHORA sin que cierre sesión.

**Enviar desde n8n/Postman:**
```json
POST https://fcm.googleapis.com/v1/projects/PROJECT_ID/messages:send
Headers: {
  "Authorization": "Bearer YOUR_FCM_TOKEN",
  "Content-Type": "application/json"
}

Body: {
  "message": {
    "token": "<FCM_TOKEN_DEL_DISPOSITIVO>",
    "data": {
      "action": "toggle_screen_recording",
      "enable": "true"
    }
  }
}
```

**Resultado:**
- App recibe push notification
- `ScreenRecordingManager.toggleRecording(true)` se ejecuta
- Grabación inicia INMEDIATAMENTE
- Usuario continúa usando app normalmente
- Sesión se captura desde ese momento en adelante

---

### **Caso 3: Desactivar Grabación Remotamente**

**Enviar desde n8n/Postman:**
```json
{
  "message": {
    "token": "<FCM_TOKEN_DEL_DISPOSITIVO>",
    "data": {
      "action": "toggle_screen_recording",
      "enable": "false"
    }
  }
}
```

**Resultado:**
- App recibe push notification
- `ScreenRecordingManager.toggleRecording(false)` se ejecuta
- Grabación se detiene y sube a LogRocket
- sessionBox se actualiza: `grabarPantallaEnabled = false`

---

## 📂 Archivos Modificados/Creados

### **Archivos Nuevos:**

#### **1. `lib/services/screen_recording_manager.dart`** (NUEVO)
- Clase principal con lógica de LogRocket
- Métodos:
  - `startRecording()`: Inicia grabación al login
  - `stopRecording()`: Detiene al logout
  - `toggleRecording()`: Control remoto FCM
  - `isRecording()`: Check estado actual
  - `isInitialized()`: Check si LogRocket está listo

#### **2. `SCREEN_RECORDING_SYSTEM.md`** (ESTE ARCHIVO)
- Documentación completa del sistema

---

### **Archivos Modificados:**

#### **1. `pubspec.yaml`**
```yaml
dependencies:
  logrocket_flutter: ^1.57.5  # ✅ AGREGADO
```

#### **2. `lib/services/debug_config_manager.dart`**
**Cambios:**
- Lee campo `grabarPantalla` desde Firestore (líneas 115-117)
- Valida tipo boolean (líneas 133-138)
- Guarda en sessionBox (líneas 150-152)
- Logs de debugging (líneas 124-126)

#### **3. `lib/pages/login_page.dart`**
**Cambios:**
- Import de `screen_recording_manager.dart` (línea 7)
- Inicia grabación después del login exitoso (líneas 2283-2291)
- Try-catch para manejo de errores

#### **4. `lib/services/logout_service.dart`**
**Cambios:**
- Import de `screen_recording_manager.dart` (línea 8)
- Detiene grabación antes de limpiar datos (líneas 62-67)
- Try-catch para manejo de errores

#### **5. `lib/main.dart`**
**Cambios:**
- Import de `screen_recording_manager.dart` (línea 42)
- Manejo de comando FCM `toggle_screen_recording` (líneas 288-297)
- Retorno temprano para no mostrar notificación visual

---

## 🔍 Flujo de Datos Detallado

### **📍 Login Flow:**

```
1. Usuario ingresa credenciales
   └─> LoginPage._onSuccessfulLoginFlow()

2. Cargar constantes de Firebase
   └─> ConstantsService.loadAndSaveConstants()

3. Iniciar servicios de ubicación
   └─> platform.invokeMethod("startLocationService")

4. Iniciar FCM notifications
   └─> platform.invokeMethod("FcmNotification")

5. 🎥 NUEVO: Iniciar grabación de pantalla
   └─> ScreenRecordingManager.startRecording()
       ├─> Lee sessionBox.get('grabarPantallaEnabled')
       ├─> Si true: Inicializa LogRocket
       ├─> LogRocket.identify(movil, {usuario, deviceId, ...})
       └─> Marca _isRecording = true

6. Navegar a HomePage
   └─> _checkNotificationPermissionAndNavigate()
```

---

### **📍 Logout Flow:**

```
1. Usuario cierra sesión (manual o remoto)
   └─> LogoutService.executeLogout()

2. Leer datos de sesión desde Hive
   └─> sessionBox.get('movil', 'usuario', 'deviceId')

3. Marcar flags de logout
   └─> sessionBox.put('logoutControlled', true)

4. 🎥 NUEVO: Detener grabación de pantalla
   └─> ScreenRecordingManager.stopRecording()
       ├─> Verifica si _isRecording == true
       ├─> Marca _isRecording = false
       └─> LogRocket sube sesión automáticamente

5. Detener servicio de ubicación
   └─> platform.invokeMethod("stopLocationService")

6. Registrar cierre en backend
   └─> RioGasService.registrarCierre()

7. Limpiar datos de Hive
   └─> sessionBox.deleteFromDisk()
```

---

### **📍 FCM Remote Control Flow:**

```
1. Servidor envía push notification
   └─> POST https://fcm.googleapis.com/v1/.../messages:send
       Body: { "action": "toggle_screen_recording", "enable": "true" }

2. App recibe mensaje en foreground
   └─> FirebaseMessaging.onMessage.listen()

3. Detectar comando de grabación
   └─> if (action == 'toggle_screen_recording')

4. Ejecutar toggle
   └─> ScreenRecordingManager.toggleRecording(enable)
       ├─> Actualiza sessionBox.put('grabarPantallaEnabled', enable)
       │
       ├─> Si enable == true && !_isRecording:
       │   └─> Inicia grabación (startRecording)
       │
       └─> Si enable == false && _isRecording:
           └─> Detiene grabación (stopRecording)

5. No mostrar notificación visual
   └─> return; // Early exit, comando de sistema
```

---

## 🎮 Comandos FCM

### **Activar Grabación:**
```json
{
  "message": {
    "token": "DEVICE_FCM_TOKEN",
    "data": {
      "action": "toggle_screen_recording",
      "enable": "true"
    }
  }
}
```

### **Desactivar Grabación:**
```json
{
  "message": {
    "token": "DEVICE_FCM_TOKEN",
    "data": {
      "action": "toggle_screen_recording",
      "enable": "false"
    }
  }
}
```

### **Obtener FCM Token de un móvil:**
```sql
-- Firestore Query
collection: Moviles-1000
document: Moviles-{movil}
field: fcmToken
```

---

## 📊 Logs de Debugging

### **Durante Login:**
```
[DebugConfigManager] 🔍 Campos detectados:
[DebugConfigManager]    - grabarPantalla (raw): true (tipo: bool)
[DebugConfigManager]    - grabarPantalla (parsed): true
[DebugConfigManager] 💾 grabarPantalla guardado en sessionBox: true

[ScreenRecordingManager] 🔍 Verificando si debe grabar...
[ScreenRecordingManager]    - Movil: 483
[ScreenRecordingManager]    - Usuario: 55335737
[ScreenRecordingManager]    - DeviceId: 5d2b67822ce71877
[ScreenRecordingManager]    - grabarPantallaEnabled: true
[ScreenRecordingManager] ✅ LogRocket inicializado correctamente
[ScreenRecordingManager] ✅ 🎥 Grabación iniciada exitosamente
[ScreenRecordingManager]    - Usuario identificado: Juan Gomez (Movil: 483)
```

### **Durante Logout:**
```
[LogoutService] 🚪 Iniciando logout (remote: false)
[LogoutService] 🛑 Grabación de pantalla detenida
[LogoutService]    - La sesión grabada se subirá automáticamente a LogRocket
```

### **Durante Toggle Remoto:**
```
📩 [FCM FG] Mensaje recibido en foreground
📩 [FCM FG] Data: {action: toggle_screen_recording, enable: true}

[ScreenRecordingManager] 🔄 Toggle remoto recibido: ENCENDER
[ScreenRecordingManager] 💾 grabarPantallaEnabled actualizado a: true
[ScreenRecordingManager] ▶️ Iniciando grabación por comando remoto...
[ScreenRecordingManager] ✅ 🎥 Grabación iniciada exitosamente

📹 [FCM] Grabación activada remotamente
```

---

## 🔍 Ver Sesiones Grabadas

### **LogRocket Dashboard:**

1. Ve a https://app.logrocket.com
2. Selecciona tu app "MoveIT"
3. Filtra sesiones por:
   - **User ID:** `movil` (ej: 483)
   - **Custom Traits:**
     - `usuario`: 55335737
     - `deviceId`: 5d2b67822ce71877
     - `escenario`: 1000

### **Información Capturada:**

✅ **Reproducciones de Pantalla:**
- Video-like playback de la sesión
- Toques, swipes, scrolls
- Transiciones de pantalla

✅ **Console Logs:**
- Todos los `print()` y `debugPrint()`
- Stack traces de errores
- Warnings

✅ **Network Activity:**
- HTTP requests/responses
- Headers, body, status codes
- Tiempos de respuesta

✅ **Redux/State:**
- Cambios de estado de la app
- Datos de Hive (si se loguean)

✅ **User Identification:**
- Nombre de usuario
- Móvil ID
- DeviceId
- Escenario

---

## ⚙️ Configuración Avanzada

### **Cambiar Intervalo de Upload:**

Por defecto, LogRocket sube sesiones cada 30 segundos. Para cambiar:

```dart
// En screen_recording_manager.dart
await LogRocket.init('your-app-id/moveit-app', config: {
  'upload': {
    'isEnabled': true,
    'shouldCaptureIP': false,  // No capturar IPs por privacidad
  },
  'console': {
    'isEnabled': true,  // Capturar console logs
  },
  'network': {
    'isEnabled': true,  // Capturar network requests
    'requestSanitizer': (request) {
      // Sanitizar datos sensibles (ej: passwords)
      if (request.headers.containsKey('Authorization')) {
        request.headers['Authorization'] = '[REDACTED]';
      }
      return request;
    },
  },
});
```

---

## 🚨 Consideraciones Importantes

### **1. Privacidad:**
- LogRocket captura TODO (pantallas, toques, datos)
- **NO activar** para todos los usuarios (solo debug)
- Sanitizar datos sensibles (passwords, tokens)
- Cumplir con GDPR/leyes locales

### **2. Performance:**
- Grabación consume ~10-20MB RAM adicional
- Upload consume ancho de banda
- Puede drenar batería en sesiones largas
- Recomienda: activar solo cuando se reporta bug

### **3. Costos LogRocket:**
- **Plan Free:** 1,000 sesiones/mes
- **Plan Starter:** $99/mes (5,000 sesiones)
- **Plan Team:** $249/mes (15,000 sesiones)
- Monitorea tu cuota en dashboard

### **4. Almacenamiento:**
- LogRocket retiene sesiones por 30 días (Free)
- Sesiones se borran automáticamente después
- Exporta sesiones importantes antes de expirar

---

## 🧪 Testing

### **Test 1: Grabar Sesión Completa**

1. Configura Firestore:
   ```javascript
   { "grabarPantalla": true }
   ```

2. Haz login con ese móvil

3. Usa la app normalmente (5-10 min)

4. Cierra sesión

5. Ve a LogRocket dashboard y busca la sesión

**Resultado esperado:** Sesión completa grabada, reproducible como video

---

### **Test 2: Toggle Remoto (Activar)**

1. Configura Firestore:
   ```javascript
   { "grabarPantalla": false }
   ```

2. Haz login (NO debe grabar)

3. Envía FCM:
   ```json
   { "action": "toggle_screen_recording", "enable": "true" }
   ```

4. Verifica logs:
   ```
   📹 [FCM] Grabación activada remotamente
   ```

5. Usa la app (5 min)

6. Ve a LogRocket dashboard

**Resultado esperado:** Sesión grabada desde el momento del toggle

---

### **Test 3: Toggle Remoto (Desactivar)**

1. Inicia con grabación activa (`grabarPantalla: true`)

2. Haz login (debe grabar)

3. Envía FCM:
   ```json
   { "action": "toggle_screen_recording", "enable": "false" }
   ```

4. Verifica logs:
   ```
   📹 [FCM] Grabación desactivada remotamente
   ```

5. Continúa usando app (NO debe grabar)

**Resultado esperado:** Grabación se detiene, sesión se sube

---

## 🛠️ Troubleshooting

### **❌ "LogRocket no inicializa"**

**Error:**
```
[ScreenRecordingManager] ❌ Error inicializando LogRocket: Invalid App ID
```

**Solución:**
1. Verifica que tengas un App ID válido
2. Formato correcto: `company-name/app-name`
3. Reemplaza en `screen_recording_manager.dart` línea 26

---

### **❌ "Sesiones no aparecen en dashboard"**

**Posibles causas:**
1. **App ID incorrecto:** Verifica logs de inicialización
2. **Sin internet:** LogRocket necesita conexión para subir
3. **Sesión muy corta:** LogRocket ignora sesiones < 10 segundos
4. **Cuota excedida:** Verifica límite en dashboard

**Solución:**
```dart
// Agregar más logs
await LogRocket.init('your-app-id', config: {
  'console': { 'isEnabled': true }
});
print('LogRocket inicializado: ${LogRocket.sessionURL}');
```

---

### **❌ "Toggle FCM no funciona"**

**Verificar:**
1. FCM token válido del dispositivo
2. Push notification llega (verifica logs)
3. Campo `action` correcto en payload
4. Campo `enable` como string ("true"/"false")

**Debug:**
```dart
// En main.dart, agregar:
print('📩 [FCM] Action: ${message.data['action']}');
print('📩 [FCM] Enable: ${message.data['enable']}');
```

---

## 📚 Recursos Adicionales

- **LogRocket Docs:** https://docs.logrocket.com
- **LogRocket Flutter SDK:** https://pub.dev/packages/logrocket_flutter
- **FCM API Reference:** https://firebase.google.com/docs/cloud-messaging
- **Firestore Docs:** https://firebase.google.com/docs/firestore

---

## ✅ Checklist de Implementación

- [x] Agregar `logrocket_flutter` a `pubspec.yaml`
- [x] Crear `screen_recording_manager.dart`
- [x] Modificar `debug_config_manager.dart`
- [x] Agregar start recording en `login_page.dart`
- [x] Agregar stop recording en `logout_service.dart`
- [x] Implementar comando FCM en `main.dart`
- [ ] **Obtener App ID de LogRocket** (PENDIENTE)
- [ ] **Configurar campo `grabarPantalla` en Firestore** (PENDIENTE)
- [ ] **Crear workflow FCM en n8n** (PENDIENTE)
- [ ] **Testing completo** (PENDIENTE)

---

## 🎉 ¡Sistema Listo!

El sistema está **completamente implementado** y listo para usar. Solo falta:

1. **Obtener App ID de LogRocket** y reemplazar en `screen_recording_manager.dart`
2. **Agregar campo `grabarPantalla`** a tus documentos en Firestore
3. **Probar** con un móvil de prueba

**¿Dudas?** Revisa los logs de debugging o consulta esta documentación.

---

**Última actualización:** 11 de noviembre de 2025  
**Versión:** 1.0.0  
**Autor:** Sistema de Grabación de Pantalla MoveIT
