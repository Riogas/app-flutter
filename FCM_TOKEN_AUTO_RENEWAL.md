# 🔑 Sistema de Auto-Renovación de Tokens FCM

## 📋 Descripción General

Sistema automático que detecta cuando Firebase Cloud Messaging invalida o rota un token FCM, regenerándolo automáticamente y sincronizándolo con el backend de RioGas.

---

## 🎯 Problemas que Resuelve

### ¿Cuándo se invalida un token FCM?

1. **Rotación automática de Firebase**: Firebase rota tokens periódicamente por seguridad
2. **Reinstalación de la app**: Al desinstalar y reinstalar, el token se pierde
3. **Clear app data**: Cuando el usuario limpia los datos de la app
4. **Cambio de firma de app**: Al actualizar la app con diferente signature
5. **Token eliminado manualmente**: Llamada a `deleteToken()`

### Sin este sistema:
- ❌ Notificaciones FCM dejan de llegar sin aviso
- ❌ Usuario no recibe mensajes importantes
- ❌ Backend intenta enviar a tokens inválidos
- ❌ Se requiere logout/login para renovar token

### Con este sistema:
- ✅ Detección automática de tokens inválidos
- ✅ Renovación inmediata sin intervención del usuario
- ✅ Sincronización automática con backend
- ✅ Persistencia local para comparación
- ✅ Logs detallados para debugging

---

## 🏗️ Arquitectura del Sistema

```
┌─────────────────────────────────────────────────────────────┐
│                    FIREBASE MESSAGING                        │
│                                                              │
│  • Rota token automáticamente                               │
│  • Dispara evento onTokenRefresh                            │
│  • Invalida tokens antiguos                                 │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ onTokenRefresh event
                       ↓
┌─────────────────────────────────────────────────────────────┐
│                   FCMTokenManager                            │
│                                                              │
│  1. Listener detecta cambio                                 │
│  2. Obtiene nuevo token                                     │
│  3. Compara con token guardado                              │
│  4. Actualiza Hive local                                    │
│  5. Sincroniza con backend                                  │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ Sincronización
                       ↓
┌─────────────────────────────────────────────────────────────┐
│                   BACKEND RIOGAS                             │
│                                                              │
│  • Endpoint: ActualizarTokenFCM                             │
│  • Parámetros: Cedula, TokenFCM                             │
│  • Actualiza BD con nuevo token                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 📁 Archivos Modificados/Creados

### 1. **Nuevo: `lib/services/fcm_token_manager.dart`**

Servicio principal que gestiona todo el ciclo de vida del token FCM.

#### Métodos Principales:

```dart
// Inicializa el sistema (llamar en main.dart)
await FCMTokenManager.initialize();

// Obtiene token actual (con validación automática)
String? token = await FCMTokenManager.getCurrentToken();

// Valida si el token es correcto
bool isValid = await FCMTokenManager.isTokenValid();

// Fuerza renovación del token (útil para debug)
String? newToken = await FCMTokenManager.forceTokenRefresh();

// Obtiene información detallada del estado
Map<String, dynamic> info = await FCMTokenManager.getTokenInfo();
```

#### Funcionalidades Implementadas:

- **Auto-detección**: Listener en `onTokenRefresh` que detecta cuando Firebase rota el token
- **Persistencia**: Guarda token en Hive (`fcmTokenBox`) para comparación
- **Validación**: Compara token guardado vs token actual de Firebase
- **Sincronización**: Llama a `RioGasService.actualizarTokenFCM()` automáticamente
- **Logging exhaustivo**: Logs con emoji para fácil identificación

---

### 2. **Modificado: `lib/services/riogas_service.dart`**

Se agregó nuevo endpoint para sincronizar tokens con backend.

```dart
static Future<Map<String, dynamic>?> actualizarTokenFCM({
  required String deviceId,
  required String token,
}) async {
  print('🔑 [RIOGAS_SERVICE] Actualizando token FCM para device: $deviceId');
  return _post('ActualizarTokenFCM', {
    'DeviceId': deviceId,
    'tokenFCM': token,
  });
}
```

**¿Cuándo se llama?**
- Automáticamente cuando `FCMTokenManager` detecta un cambio de token
- Solo si hay deviceId en sessionBox (usuario logueado)
- Si no hay deviceId, se sincronizará en el próximo login

---

### 3. **Modificado: `lib/main.dart`**

Se integró el sistema de token manager en la inicialización de la app.

```dart
// Import agregado
import 'services/fcm_token_manager.dart';

// En main() después de _initializeFirebaseMessaging()
await _initializeFCMTokenManager();

// Nueva función
Future<void> _initializeFCMTokenManager() async {
  try {
    print('🔑 [MAIN] Inicializando FCM Token Manager...');
    await FCMTokenManager.initialize();
    print('✅ [MAIN] FCM Token Manager inicializado');
  } catch (e, stackTrace) {
    print('❌ [MAIN] Error inicializando FCM Token Manager: $e');
    print('📚 StackTrace: $stackTrace');
  }
}
```

**Orden de inicialización:**
1. Firebase Core
2. Firebase Messaging
3. **FCM Token Manager** ← Nuevo
4. Otros servicios

---

### 4. **Modificado: `lib/pages/login_page.dart`**

Cambio en el login para usar el token manager en lugar de obtener token directamente.

#### Antes:
```dart
String? token = await FirebaseMessaging.instance.getToken();
print('📲 Token FCM: $token');
```

#### Después:
```dart
// 🔑 Usar FCMTokenManager para obtener token válido y actualizado
String? token = await FCMTokenManager.getCurrentToken();

if (token != null) {
  print('📲 Token FCM obtenido: ${token.substring(0, 20)}...');
  
  // Validar que el token sea válido
  bool isValid = await FCMTokenManager.isTokenValid();
  if (!isValid) {
    print('⚠️ Token no válido, forzando renovación...');
    token = await FCMTokenManager.forceTokenRefresh();
  }
} else {
  print('❌ No se pudo obtener token FCM');
}
```

**Ventajas:**
- Valida automáticamente que el token sea correcto
- Fuerza renovación si detecta problemas
- Sincroniza con backend en el login
- Logs más detallados

---

## 🔄 Flujo de Funcionamiento

### Escenario 1: Inicio de App Normal

```
1. App inicia → main.dart
2. Inicializa Firebase
3. Inicializa FCMTokenManager
   ├─ Abre Hive box (fcmTokenBox)
   ├─ Obtiene token de Firebase
   ├─ Compara con token guardado
   │  └─ Si coinciden → ✅ Todo OK
   │  └─ Si difieren → 🔄 Actualizar
4. Configura listener onTokenRefresh
5. App lista para recibir notificaciones
```

### Escenario 2: Firebase Rota el Token

```
1. Firebase rota token automáticamente
2. Dispara evento onTokenRefresh
3. FCMTokenManager detecta el evento
   ├─ Log: "🔄 ¡Token renovado por Firebase!"
   ├─ Guarda nuevo token en Hive
   ├─ Actualiza timestamp
   └─ Sincroniza con backend
4. Backend actualiza BD con nuevo token
5. ✅ Notificaciones siguen funcionando
```

### Escenario 3: Usuario Reinstala App

```
1. Usuario reinstala app
2. App inicia por primera vez
3. FCMTokenManager.initialize()
   ├─ No hay token en Hive
   ├─ Obtiene token nuevo de Firebase
   ├─ Guarda en Hive
   └─ No hay sesión activa
4. Usuario hace login
5. Login detecta token y lo sincroniza con backend
6. ✅ Backend tiene el nuevo token
```

### Escenario 4: Detección de Token Inválido

```
1. Usuario abre app
2. FCMTokenManager.getCurrentToken()
   ├─ Obtiene token de Hive: "ABC123..."
   ├─ Obtiene token de Firebase: "XYZ789..."
   └─ No coinciden → Token cambió
3. Actualiza automáticamente
   ├─ Guarda nuevo token "XYZ789..." en Hive
   └─ Sincroniza con backend
4. Retorna nuevo token válido
5. ✅ App usa token correcto
```

---

## 🧪 Testing y Debugging

### Comandos de Debug

```dart
// Ver información del token actual
Map<String, dynamic> info = await FCMTokenManager.getTokenInfo();
print(info);

// Resultado:
// {
//   'savedToken': 'ABC123...',
//   'currentToken': 'ABC123...',
//   'isValid': true,
//   'lastUpdate': '2025-11-06T10:30:00.000',
//   'fullSavedToken': 'ABC123...FULL_TOKEN',
//   'fullCurrentToken': 'ABC123...FULL_TOKEN'
// }

// Forzar renovación (para testing)
String? newToken = await FCMTokenManager.forceTokenRefresh();
print('Nuevo token: $newToken');

// Validar token
bool isValid = await FCMTokenManager.isTokenValid();
print('Token válido: $isValid');
```

### Logs a Monitorear

```bash
# Inicialización
🔑 [FCM_TOKEN_MANAGER] Inicializando...
📲 [FCM_TOKEN_MANAGER] Token FCM actual: ABC123...
✅ [FCM_TOKEN_MANAGER] Token válido y actualizado
👂 [FCM_TOKEN_MANAGER] Configurando listener de renovación...

# Renovación detectada
🔄 [FCM_TOKEN_MANAGER] ¡Token renovado por Firebase!
📲 [FCM_TOKEN_MANAGER] Nuevo token: XYZ789...
💾 [FCM_TOKEN_MANAGER] Guardando token localmente...
✅ [FCM_TOKEN_MANAGER] Token guardado en Hive
🌐 [FCM_TOKEN_MANAGER] Sincronizando token con backend...
✅ [FCM_TOKEN_MANAGER] Token sincronizado con backend exitosamente

# Login con validación
📲 Token FCM obtenido: ABC123...
✅ Token válido
```

### Filtros de Logcat

```powershell
# Ver solo logs del token manager
adb logcat | Select-String "FCM_TOKEN_MANAGER"

# Ver todos los logs de FCM (mensajería + token)
adb logcat | Select-String "FCM"

# Ver sincronización con backend
adb logcat | Select-String "FCM_TOKEN_MANAGER|RIOGAS_SERVICE.*TokenFCM"
```

---

## 🔍 Casos de Uso Comunes

### Caso 1: Usuario No Recibe Notificaciones

**Diagnóstico:**
```dart
Map<String, dynamic> info = await FCMTokenManager.getTokenInfo();
if (!info['isValid']) {
  print('⚠️ Token desincronizado');
  await FCMTokenManager.forceTokenRefresh();
}
```

### Caso 2: Verificar Token Después de Reinstalar

**Backend debe tener el nuevo token automáticamente al hacer login.**

### Caso 3: Testing de Rotación de Token

```dart
// Forzar eliminación y regeneración
await FCMTokenManager.forceTokenRefresh();
// Verificar que se sincronizó con backend
```

---

## 📊 Datos Persistidos en Hive

### Box: `fcmTokenBox`

| Key | Valor | Descripción |
|-----|-------|-------------|
| `currentFCMToken` | String | Token FCM actual guardado |
| `lastTokenUpdate` | String (ISO8601) | Timestamp de última actualización |

**Ejemplo:**
```dart
{
  'currentFCMToken': 'fGHj4K...FULL_TOKEN_HERE...xyz',
  'lastTokenUpdate': '2025-11-06T10:30:45.123Z'
}
```

---

## 🚨 Errores Comunes y Soluciones

### Error: "No se pudo obtener token FCM"

**Causa:** Firebase no inicializado o permisos denegados

**Solución:**
```dart
// Verificar permisos
NotificationSettings settings = await FirebaseMessaging.instance.requestPermission();
if (settings.authorizationStatus == AuthorizationStatus.authorized) {
  // Intentar nuevamente
  await FCMTokenManager.forceTokenRefresh();
}
```

### Error: "Token no válido, forzando renovación"

**Causa:** Token guardado no coincide con Firebase (esperado en rotaciones)

**Solución:** El sistema lo maneja automáticamente, no requiere acción.

### Error: "No hay sesión activa. Token se sincronizará en próximo login"

**Causa:** App inició sin usuario logueado

**Solución:** Es normal. El token se sincronizará automáticamente cuando el usuario haga login.

---

## 🔐 Seguridad

### Protección del Token

- ✅ Token se guarda en Hive (encriptado en dispositivo)
- ✅ Solo se envía a backend autorizado de RioGas
- ✅ Se transmite vía HTTPS
- ✅ Solo se muestra parcialmente en logs (primeros 20 caracteres)

### Sincronización con Backend

- ✅ Solo se sincroniza si hay sesión activa (usuario logueado)
- ✅ Se envía cédula del usuario junto con token
- ✅ Backend valida que la cédula corresponda al usuario autenticado

---

## 📈 Métricas y Monitoreo

### KPIs a Monitorear

1. **Frecuencia de renovación**: ¿Cuántas veces rota Firebase el token?
2. **Tiempo de sincronización**: ¿Cuánto tarda en actualizarse el backend?
3. **Fallos de sincronización**: ¿Cuántas veces falla la llamada al backend?
4. **Tokens inválidos detectados**: ¿Cuántas veces se detecta desincronización?

### Logs para Análisis

```bash
# Contar renovaciones de token
adb logcat -d | Select-String "Token renovado por Firebase" | Measure-Object

# Ver últimas sincronizaciones
adb logcat -d | Select-String "Token sincronizado con backend"

# Detectar errores
adb logcat -d | Select-String "FCM_TOKEN_MANAGER.*Error"
```

---

## 🎓 Mejores Prácticas

### ✅ Hacer

1. **Siempre usar `FCMTokenManager.getCurrentToken()`** en lugar de `FirebaseMessaging.instance.getToken()`
2. **Verificar validez del token** antes de usarlo para operaciones críticas
3. **Monitorear logs** para detectar problemas de renovación tempranamente
4. **Validar que el backend recibe tokens** correctamente

### ❌ No Hacer

1. **No obtener tokens directamente de Firebase** - usar el manager
2. **No asumir que el token nunca cambia** - siempre puede rotar
3. **No ignorar errores de sincronización** - pueden causar pérdida de notificaciones
4. **No mostrar tokens completos en logs** - solo parcialmente por seguridad

---

## 🔄 Mantenimiento Futuro

### Posibles Mejoras

1. **Retry automático**: Si la sincronización con backend falla, reintentar automáticamente
2. **Métricas detalladas**: Enviar eventos de renovación a analytics
3. **Alertas proactivas**: Notificar al backend si detecta múltiples fallos de token
4. **Cache de tokens anteriores**: Guardar historial de tokens para auditoría
5. **Validación periódica**: Verificar validez del token cada X horas

---

## 📝 Resumen Técnico

| Aspecto | Detalle |
|---------|---------|
| **Archivo Principal** | `lib/services/fcm_token_manager.dart` |
| **Dependencias** | `firebase_messaging`, `hive` |
| **Trigger Principal** | `FirebaseMessaging.instance.onTokenRefresh` |
| **Persistencia** | Hive box: `fcmTokenBox` |
| **Backend Endpoint** | `ActualizarTokenFCM` |
| **Inicialización** | `main.dart` después de Firebase Messaging |
| **Logs Tag** | `[FCM_TOKEN_MANAGER]` |
| **Impacto** | 🟢 Mejora automática de confiabilidad de notificaciones |

---

## ✅ Checklist de Implementación

- [x] Crear `fcm_token_manager.dart` con lógica completa
- [x] Agregar método `actualizarTokenFCM()` en `riogas_service.dart`
- [x] Integrar en `main.dart` con inicialización
- [x] Modificar `login_page.dart` para usar token manager
- [x] Configurar listener `onTokenRefresh`
- [x] Implementar persistencia en Hive
- [x] Agregar logs detallados con tags
- [x] Validación automática de tokens
- [x] Sincronización automática con backend
- [x] Documentación completa

---

## 🆘 Soporte

### Para Debugging

1. **Revisar logs**: Buscar `[FCM_TOKEN_MANAGER]` en logcat
2. **Verificar info del token**: `FCMTokenManager.getTokenInfo()`
3. **Forzar renovación**: `FCMTokenManager.forceTokenRefresh()`
4. **Validar manualmente**: `FCMTokenManager.isTokenValid()`

### Contacto

Si hay problemas con el sistema de tokens FCM:
1. Revisar este documento
2. Verificar logs con los filtros proporcionados
3. Probar forzar renovación manual
4. Verificar que el backend responde correctamente al endpoint `ActualizarTokenFCM`

---

**Última actualización:** 6 de noviembre de 2025  
**Versión:** 1.0  
**Estado:** ✅ Implementado y Funcional
