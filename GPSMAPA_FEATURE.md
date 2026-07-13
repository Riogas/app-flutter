# 🗺️ Feature: GPSMapa - Control de Envío de Coordenadas

## 📋 Descripción

Se implementó un nuevo parámetro booleano `GPSMapa` a nivel de móvil en Firestore que permite controlar si las coordenadas GPS se envían al servidor RioGas (y potencialmente a n8n cuando `debugMode=true`).

## 🎯 Objetivo

Permitir activar/desactivar el envío de coordenadas GPS a nivel de móvil sin necesidad de reinstalar la aplicación, de forma similar a cómo funciona `debugMode`.

## 🏗️ Implementación

### 1. Estructura en Firestore

**Colección:** `Moviles-1000`  
**Documento:** `Moviles-{movilId}`  
**Campo nuevo:** `GPSMapa` (boolean)

```json
{
  "debugMode": true/false,
  "debugLevel": "INFO",
  "GPSMapa": true/false  // 🆕 NUEVO CAMPO
}
```

### 2. Archivos Modificados

#### ✅ `lib/services/debug_config_manager.dart`

**Cambios realizados:**
- Importado `package:hive/hive.dart`
- Convertida función `_onDebugConfigChanged` a `async`
- Lectura del campo `GPSMapa` desde Firestore
- Guardado de `GPSMapa` en `sessionBox` como `gpsMapaEnabled`
- Actualizada firma de `_notifyNativeLayer` para incluir `gpsMapaEnabled`
- Envío del parámetro `gpsMapaEnabled` a la capa nativa (Kotlin) via MethodChannel

**Código clave:**
```dart
// Leer flag GPSMapa (por defecto false)
final gpsMapaRaw = data['GPSMapa'];
final bool gpsMapaEnabled = gpsMapaRaw is bool ? gpsMapaRaw : false;

// Guardar en sessionBox para acceso rápido
final sessionBox = await Hive.openBox('sessionBox');
await sessionBox.put('gpsMapaEnabled', gpsMapaEnabled);

// Notificar a Kotlin
_notifyNativeLayer(debugMode, debugLevel, gpsMapaEnabled);
```

#### ✅ `lib/services/location_service.dart`

**Cambios realizados:**
- Verificación del flag `gpsMapaEnabled` antes de enviar coordenadas
- Si `GPSMapa=false`, se omite el envío de coordenadas
- Log informativo cuando se envían coordenadas (GPSMapa=true)

**Código clave:**
```dart
// Timer para RioGas (cada 30 segundos según constante 30)
Timer.periodic(Duration(seconds: rioGasInterval), (rioGasTimer) async {
  // ... obtener posición ...
  
  // 🗺️ Verificar si GPSMapa está habilitado
  bool gpsMapaEnabled = sessionBox.get('gpsMapaEnabled', defaultValue: false);
  
  if (!gpsMapaEnabled) {
    // GPSMapa deshabilitado - NO enviar coordenadas
    return;
  }
  
  // GPSMapa habilitado - enviar coordenadas
  print('🗺️ [GPSMapa] Enviando coordenadas (GPSMapa=true): ...');
  await RioGasService.RegistrarCoordenadasV2(...);
});
```

### 3. Flujo de Funcionamiento

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Firestore: Moviles-1000/Moviles-{movilId}               │
│    - Cambio en campo "GPSMapa" (true/false)                │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. DebugConfigManager (Flutter/Dart)                       │
│    - Listener detecta cambio                               │
│    - Lee GPSMapa de Firestore                              │
│    - Guarda en sessionBox como 'gpsMapaEnabled'            │
│    - Notifica a Kotlin via MethodChannel                   │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. LocationService (Flutter/Dart)                          │
│    - Timer cada 30 segundos (constante 30)                 │
│    - Lee 'gpsMapaEnabled' de sessionBox                    │
│    - Si GPSMapa=false → NO envía coordenadas               │
│    - Si GPSMapa=true → Envía a RioGas/n8n                  │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Uso

### Activar envío de coordenadas GPS:

1. Ir a Firebase Console
2. Firestore Database
3. Colección: `Moviles-1000`
4. Documento: `Moviles-{movilId}`
5. Agregar/Editar campo: `GPSMapa` = `true`

### Desactivar envío de coordenadas GPS:

1. Mismo procedimiento
2. Cambiar campo: `GPSMapa` = `false`

## 📊 Logs para Debugging

Cuando el listener detecta cambios:
```
[DebugConfigManager] 🔍 Campos detectados:
    - GPSMapa (raw): true (tipo: bool)
    - GPSMapa (parsed): true
[DebugConfigManager] 💾 GPSMapa guardado en sessionBox: true
[DebugConfigManager] 📤 Enviando a Kotlin: enabled=true, level=INFO, gpsMapaEnabled=true
```

Cuando se envían coordenadas:
```
🗺️ [GPSMapa] Enviando coordenadas (GPSMapa=true): Lat -34.xxxx, Lng -56.xxxx
```

Cuando GPSMapa está deshabilitado:
```
🗺️ [GPSMapa] Envío de coordenadas deshabilitado (GPSMapa=false)
```

## ⚙️ Configuración en Firestore

### Valores por defecto:
- Si el campo `GPSMapa` no existe: `false` (NO envía coordenadas)
- Si el campo `GPSMapa` existe pero no es boolean: `false` (NO envía coordenadas)

### Validación de tipos:
Si se detecta un tipo incorrecto:
```
[DebugConfigManager] ⚠️ ADVERTENCIA: GPSMapa NO es boolean!
    - Tipo actual: String
    - Valor: "true"
    - Debe ser boolean true/false en Firestore
```

## 🔄 Relación con debugMode

`GPSMapa` y `debugMode` son **independientes**:

| debugMode | GPSMapa | Resultado                                  |
|-----------|---------|-------------------------------------------|
| false     | false   | ❌ NO envía coordenadas                    |
| false     | true    | ✅ Envía coordenadas a RioGas             |
| true      | false   | ❌ NO envía coordenadas (logs activos)    |
| true      | true    | ✅ Envía coordenadas a RioGas/n8n + logs  |

## 📝 Notas Técnicas

1. **Timer de envío:** Cada 30 segundos (según constante 30 en Firestore)
2. **Almacenamiento:** `sessionBox` (Hive) → clave `gpsMapaEnabled`
3. **Sincronización:** El cambio en Firestore se refleja en tiempo real gracias al listener
4. **Kotlin:** Se envía el parámetro `gpsMapaEnabled` al MethodChannel `setDebugMode`

## ✅ Testing

Para probar la funcionalidad:

1. **Activar GPSMapa:**
   - Cambiar `GPSMapa` a `true` en Firestore
   - Verificar logs: `🗺️ [GPSMapa] Enviando coordenadas...`
   - Confirmar que coordenadas llegan a RioGas/n8n

2. **Desactivar GPSMapa:**
   - Cambiar `GPSMapa` a `false` en Firestore
   - Verificar logs: `🗺️ [GPSMapa] Envío de coordenadas deshabilitado`
   - Confirmar que NO llegan coordenadas

3. **Valor por defecto:**
   - Eliminar campo `GPSMapa` de Firestore
   - Debe asumir `false` por defecto

## 🎯 Ventajas

✅ Control remoto sin reinstalar app  
✅ Cambios en tiempo real  
✅ Mismo patrón que `debugMode` (fácil de entender)  
✅ Ahorro de batería cuando está deshabilitado  
✅ Ahorro de ancho de banda  
✅ Logs claros para debugging  

## 📅 Fecha de Implementación

Noviembre 6, 2025

## 👤 Implementado por

GitHub Copilot Assistant
