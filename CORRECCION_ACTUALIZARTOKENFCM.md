# 🔧 Corrección: actualizarTokenFCM - DeviceId en lugar de Cedula

## 📋 Cambio Realizado

Se corrigió el método `actualizarTokenFCM` en `RioGasService` para usar `DeviceId` en lugar de `Cedula`.

---

## ❌ Problema Anterior

El método usaba `cedula` como parámetro:

```dart
static Future<Map<String, dynamic>?> actualizarTokenFCM({
  required String cedula,  // ❌ Incorrecto
  required String token,
}) async {
  return _post('ActualizarTokenFCM', {
    'Cedula': cedula,      // ❌ Backend espera DeviceId
    'TokenFCM': token,
  });
}
```

**¿Por qué estaba mal?**
- El token FCM está asociado al **dispositivo**, no al usuario
- Un usuario puede tener múltiples dispositivos (cada uno con su token FCM)
- El backend espera `DeviceId` para identificar el dispositivo específico

---

## ✅ Solución Implementada

Ahora el método usa `deviceId` correctamente:

```dart
static Future<Map<String, dynamic>?> actualizarTokenFCM({
  required String deviceId,  // ✅ Correcto
  required String token,
}) async {
  print('🔑 [RIOGAS_SERVICE] Actualizando token FCM para device: $deviceId');
  print('🔑 [RIOGAS_SERVICE] Token: ${token.substring(0, 20)}...');
  
  return _post('ActualizarTokenFCM', {
    'DeviceId': deviceId,    // ✅ Backend recibe DeviceId
    'TokenFCM': token,
  });
}
```

---

## 📁 Archivos Modificados

### 1. `lib/services/riogas_service.dart`

**Cambio:**
- Parámetro: `cedula` → `deviceId`
- Payload: `'Cedula'` → `'DeviceId'`

**Líneas modificadas:** 1574-1588

---

### 2. `lib/services/fcm_token_manager.dart`

**Cambio en `_syncTokenWithBackend()`:**

```dart
// ❌ Antes
final cedula = sessionBox.get('cedula');
if (cedula == null) {
  print('⚠️ No hay sesión activa...');
  return;
}
final response = await RioGasService.actualizarTokenFCM(
  cedula: cedula.toString(),
  token: token,
);

// ✅ Ahora
final deviceId = sessionBox.get('deviceId');
if (deviceId == null) {
  print('⚠️ No hay deviceId...');
  return;
}
final response = await RioGasService.actualizarTokenFCM(
  deviceId: deviceId.toString(),
  token: token,
);
```

**Líneas modificadas:** 99-118

---

### 3. `FCM_TOKEN_AUTO_RENEWAL.md`

Actualizada la documentación para reflejar el cambio de `cedula` a `deviceId`.

---

## 🎯 Impacto del Cambio

### Ventajas de usar DeviceId

1. **Correcta asociación**: Token FCM ↔ Dispositivo (no Usuario)
2. **Multi-dispositivo**: Un usuario con varios dispositivos tendrá tokens separados
3. **Identificación única**: Cada dispositivo tiene su propio DeviceId único
4. **Coherencia**: Mantiene consistencia con otros endpoints que usan DeviceId

### Casos de Uso

| Escenario | DeviceId | Cedula |
|-----------|----------|--------|
| Usuario con 1 dispositivo | ✅ Funciona | ⚠️ Funciona pero incorrecto |
| Usuario con 2+ dispositivos | ✅ Cada uno su token | ❌ Confusión: ¿cuál token es de cuál? |
| Usuario cambia de cuenta en mismo dispositivo | ✅ Token sigue siendo del device | ❌ Inconsistencia |
| Reinstalación de app | ✅ Mismo DeviceId, token nuevo | ⚠️ Misma cedula, pero ¿cuál device? |

---

## 🔍 Validación

### ¿Cómo verificar que funciona?

1. **Logs al iniciar app:**
```bash
🔑 [FCM_TOKEN_MANAGER] Inicializando...
📲 [FCM_TOKEN_MANAGER] Token FCM actual: ABC123...
🌐 [FCM_TOKEN_MANAGER] Sincronizando token con backend...
🔑 [RIOGAS_SERVICE] Actualizando token FCM para device: <DEVICE_ID>
✅ [FCM_TOKEN_MANAGER] Token sincronizado con backend exitosamente
```

2. **Logs al rotar token:**
```bash
🔄 [FCM_TOKEN_MANAGER] ¡Token renovado por Firebase!
📲 [FCM_TOKEN_MANAGER] Nuevo token: XYZ789...
🔑 [RIOGAS_SERVICE] Actualizando token FCM para device: <DEVICE_ID>
✅ [FCM_TOKEN_MANAGER] Token sincronizado con backend exitosamente
```

3. **Verificar en backend:**
   - El endpoint `ActualizarTokenFCM` debe recibir:
     - `DeviceId`: ID único del dispositivo
     - `TokenFCM`: Token FCM actual

---

## 📊 Comparación Antes/Después

| Aspecto | Antes (Cedula) | Después (DeviceId) |
|---------|---------------|-------------------|
| **Parámetro** | `cedula: String` | `deviceId: String` |
| **Payload Key** | `'Cedula'` | `'DeviceId'` |
| **Obtenido de** | `sessionBox.get('cedula')` | `sessionBox.get('deviceId')` |
| **Log** | "...para cédula: X" | "...para device: X" |
| **Asociación** | Usuario → Token | Dispositivo → Token |
| **Multi-device** | ❌ Problemático | ✅ Funciona correctamente |

---

## 🧪 Testing

### Comandos para validar

```powershell
# Ver logs de sincronización de token
adb logcat | Select-String "FCM_TOKEN_MANAGER|actualizarTokenFCM"

# Ver deviceId usado
adb logcat | Select-String "Actualizando token FCM para device"

# Ver respuesta del backend
adb logcat | Select-String "Token sincronizado con backend"
```

### Escenarios de prueba

1. ✅ **Inicio de app normal**: Token debe sincronizarse con DeviceId
2. ✅ **Rotación de token**: Nuevo token debe enviarse con mismo DeviceId
3. ✅ **Login después de reinstalar**: Token nuevo debe asociarse al DeviceId
4. ✅ **Múltiples dispositivos del mismo usuario**: Cada uno con su token único

---

## 🔐 Seguridad y Privacidad

### Por qué DeviceId es mejor

- **No expone datos personales**: DeviceId es un UUID técnico
- **GDPR Compliance**: No se envía información personal innecesaria
- **Trazabilidad**: Permite rastrear problemas por dispositivo específico
- **Revocación**: Fácil invalidar tokens por dispositivo sin afectar otros

---

## ✅ Checklist de Cambios

- [x] Modificar método `actualizarTokenFCM` en `riogas_service.dart`
- [x] Actualizar `_syncTokenWithBackend` en `fcm_token_manager.dart`
- [x] Actualizar documentación en `FCM_TOKEN_AUTO_RENEWAL.md`
- [x] Compilar e instalar app
- [x] Verificar logs (sin errores de compilación)
- [ ] Probar en dispositivo real (sincronización exitosa)
- [ ] Verificar en backend que recibe DeviceId correctamente

---

## 🎓 Lección Aprendida

**Regla de oro para tokens FCM:**
> Los tokens FCM deben asociarse al **dispositivo** (DeviceId), no al **usuario** (Cedula/Username), ya que cada dispositivo tiene su propio token único asignado por Firebase.

---

**Fecha de corrección:** 6 de noviembre de 2025  
**Estado:** ✅ Implementado y Compilado  
**Próximo paso:** Validar en backend que el endpoint acepta `DeviceId`
