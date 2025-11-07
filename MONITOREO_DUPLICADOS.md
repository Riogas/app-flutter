# 🔍 Guía de Monitoreo de Duplicados en failedRequestsBox

## 📋 Descripción

Este documento explica cómo monitorear y verificar que el sistema de deduplicación de requests fallidos está funcionando correctamente en la aplicación.

## 🎯 ¿Qué son los duplicados?

Cuando un request falla (servidor caído, timeout, etc.), se guarda en `failedRequestsBox` para reintentarlo después. El problema es que si el usuario presiona el botón múltiples veces, podríamos guardar el mismo request varias veces, generando **duplicados**.

## 🛡️ Sistema de Protección Implementado

### 1️⃣ Captura de Timestamp Única
Se captura el timestamp **una sola vez** al inicio de la función:
```dart
final String capturedTimestamp = DateTime.now().toUtc().toIso8601String();
```

### 2️⃣ Flags de Control
Se usan flags booleanos para prevenir múltiples ejecuciones simultáneas:
- `_isFinalizing` - Para FinalizarPedido
- `_isMarkingAsRead` - Para DescargaLecturaMensajes  
- `_descargaEnCurso` - Para DescargaPedidos
- `_lecturaEnCurso` - Para DescargaLecturaPedidos

### 3️⃣ Deduplicación por Signature
En `_saveFailedRequest()`, se genera una firma JSON del payload y se compara con requests existentes.

## 📊 Logs para Monitoreo

### Cuando se INTENTA guardar un request:

```
📦 [SAVE_FAILED] Intentando guardar request fallido: FinalizarPedidoV3
📦 [SAVE_FAILED] Total actual en box: 5
```

### Durante la verificación de duplicados:

#### Endpoints V3 (FinalizarPedido, DescargaPedidos, DescargaLecturaMensajes):

```
🔍 [DEDUP_CHECK] Endpoint V3 detectado: FinalizarPedidoV3
🔍 [DEDUP_CHECK] Signature generada: {"EscenarioId":1000,"MovilId":27861374,"PedidoId":123456...
🔍 [DEDUP_CHECK] Buscando duplicados en 5 requests...
```

#### Si encuentra un duplicado:

```
🔍 [DEDUP_CHECK] ⚠️ DUPLICADO ENCONTRADO!
🔍 [DEDUP_CHECK]    - Endpoint guardado: FinalizarPedidoV3
🔍 [DEDUP_CHECK]    - Timestamp guardado: 2025-11-06T15:30:45.123Z
🔍 [DEDUP_CHECK]    - Signature coincide: ✅
⚠️ [DEDUP_BLOCKED] Duplicate FinalizarPedidoV3 detectado, NO se guarda nuevamente.
⚠️ [DEDUP_BLOCKED] ✅ Control de duplicados funcionando correctamente!
```

#### Si NO encuentra duplicado:

```
✅ [SAVED] Request FinalizarPedidoV3 guardado exitosamente
✅ [SAVED] Total en box: 6
✅ [SAVED] Signature: {"EscenarioId":1000,"MovilId":27861374,"PedidoId":123456...
```

### Endpoints no-V3:

```
🔍 [DEDUP_CHECK] Endpoint no-V3: OtroEndpoint
🔍 [DEDUP_CHECK] Buscando duplicados en 6 requests...
```

## 🧪 Cómo Verificar que NO hay Duplicados

### Escenario de Prueba:

1. **Apagar el servidor backend** (o poner el móvil en modo avión)
2. **Finalizar un pedido** en la app
3. **Presionar el botón varias veces** rápidamente (3-4 veces)
4. **Revisar los logs** en la consola

### ✅ Comportamiento CORRECTO (sin duplicados):

```
📦 [SAVE_FAILED] Intentando guardar request fallido: FinalizarPedidoV3
📦 [SAVE_FAILED] Total actual en box: 0
🔍 [DEDUP_CHECK] Endpoint V3 detectado: FinalizarPedidoV3
🔍 [DEDUP_CHECK] Signature generada: {"EscenarioId":1000,"MovilId":27861374...
🔍 [DEDUP_CHECK] Buscando duplicados en 0 requests...
✅ [SAVED] Request FinalizarPedidoV3 guardado exitosamente
✅ [SAVED] Total en box: 1
✅ [SAVED] Signature: {"EscenarioId":1000,"MovilId":27861374...

[Usuario presiona botón otra vez]

⚠️ [LECTURA] Ya hay una lectura en curso, ignorando...  // ← FLAG funcionando!

[Usuario presiona botón otra vez después de que termine]

📦 [SAVE_FAILED] Intentando guardar request fallido: FinalizarPedidoV3
📦 [SAVE_FAILED] Total actual en box: 1
🔍 [DEDUP_CHECK] Endpoint V3 detectado: FinalizarPedidoV3
🔍 [DEDUP_CHECK] Signature generada: {"EscenarioId":1000,"MovilId":27861374...
🔍 [DEDUP_CHECK] Buscando duplicados en 1 requests...
🔍 [DEDUP_CHECK] ⚠️ DUPLICADO ENCONTRADO!  // ← DEDUPLICACIÓN funcionando!
🔍 [DEDUP_CHECK]    - Endpoint guardado: FinalizarPedidoV3
🔍 [DEDUP_CHECK]    - Timestamp guardado: 2025-11-06T15:30:45.123Z
🔍 [DEDUP_CHECK]    - Signature coincide: ✅
⚠️ [DEDUP_BLOCKED] Duplicate FinalizarPedidoV3 detectado, NO se guarda nuevamente.
⚠️ [DEDUP_BLOCKED] ✅ Control de duplicados funcionando correctamente!
```

**Resultado:** Solo 1 request en la box, a pesar de múltiples intentos ✅

### ❌ Comportamiento INCORRECTO (con duplicados):

```
📦 [SAVE_FAILED] Intentando guardar request fallido: FinalizarPedidoV3
📦 [SAVE_FAILED] Total actual en box: 0
✅ [SAVED] Request FinalizarPedidoV3 guardado exitosamente
✅ [SAVED] Total en box: 1

[Usuario presiona botón otra vez]

📦 [SAVE_FAILED] Intentando guardar request fallido: FinalizarPedidoV3
📦 [SAVE_FAILED] Total actual en box: 1
✅ [SAVED] Request FinalizarPedidoV3 guardado exitosamente  // ⚠️ NO debería guardarse!
✅ [SAVED] Total en box: 2  // ⚠️ Total aumentó cuando no debía!

[Usuario presiona botón otra vez]

📦 [SAVE_FAILED] Intentando guardar request fallido: FinalizarPedidoV3
📦 [SAVE_FAILED] Total actual en box: 2
✅ [SAVED] Request FinalizarPedidoV3 guardado exitosamente  // ⚠️ NO debería guardarse!
✅ [SAVED] Total en box: 3  // ⚠️ Total aumentó cuando no debía!
```

**Resultado:** Múltiples requests duplicados en la box ❌

## 🔎 Comandos PowerShell para Monitorear

### Filtrar solo logs de deduplicación:

```powershell
flutter run | Select-String -Pattern "\[DEDUP_CHECK\]|\[DEDUP_BLOCKED\]|\[SAVED\]|\[SAVE_FAILED\]"
```

### Ver solo cuando se bloquean duplicados:

```powershell
flutter run | Select-String -Pattern "DEDUP_BLOCKED|DUPLICADO ENCONTRADO"
```

### Contar cuántos duplicados se bloquearon:

```powershell
flutter run | Select-String -Pattern "DEDUP_BLOCKED" | Measure-Object
```

### Ver total en box después de cada operación:

```powershell
flutter run | Select-String -Pattern "Total en box:"
```

## 📈 Métricas a Monitorear

### ✅ Indicadores de que TODO funciona bien:

1. **Flag control activo:**
   ```
   ⚠️ [LECTURA] Ya hay una lectura en curso, ignorando...
   ```

2. **Deduplicación bloqueando correctos:**
   ```
   ⚠️ [DEDUP_BLOCKED] Duplicate detectado, NO se guarda nuevamente.
   ```

3. **Total en box estable:**
   ```
   Total en box: 1  // Se mantiene en 1 a pesar de múltiples presiones
   ```

4. **Signature coincidiendo:**
   ```
   🔍 [DEDUP_CHECK]    - Signature coincide: ✅
   ```

### ❌ Indicadores de PROBLEMA:

1. **Total en box creciendo indefinidamente:**
   ```
   Total en box: 1
   Total en box: 2  // ⚠️ Aumentó!
   Total en box: 3  // ⚠️ Sigue aumentando!
   ```

2. **No aparecen logs de DEDUP_BLOCKED cuando debería:**
   - Usuario presiona 3 veces el mismo botón
   - Solo sale `✅ [SAVED]` sin `⚠️ [DEDUP_BLOCKED]`

3. **Signature diferente para mismo payload:**
   ```
   Signature: {"FechaHoraCmbEst":"2025-11-06T15:30:45.123Z"...
   Signature: {"FechaHoraCmbEst":"2025-11-06T15:30:47.456Z"...  // ⚠️ Timestamp diferente!
   ```

## 🛠️ Solución si hay Duplicados

Si detectas que se están guardando duplicados:

1. **Verificar timestamps:**
   - Asegurarse de que se usa `capturedTimestamp` y NO `DateTime.now()` inline

2. **Verificar flags:**
   - Confirmar que el flag se setea ANTES del try
   - Confirmar que el flag se resetea en el `finally`

3. **Verificar signature:**
   - El payload debe ser exactamente el mismo
   - No debe haber campos dinámicos no capturados

## 📝 Ejemplo Completo de Sesión de Monitoreo

```powershell
# Terminal 1: Ejecutar la app
cd C:\Users\jgomez\Documents\Projects\AppTFlutter\appmovil
flutter run

# Terminal 2: Monitorear logs de deduplicación
flutter logs | Select-String -Pattern "DEDUP|SAVE_FAILED|SAVED"
```

**Logs esperados:**

```
[15:30:45] 📦 [SAVE_FAILED] Intentando guardar request fallido: FinalizarPedidoV3
[15:30:45] 📦 [SAVE_FAILED] Total actual en box: 0
[15:30:45] 🔍 [DEDUP_CHECK] Endpoint V3 detectado: FinalizarPedidoV3
[15:30:45] 🔍 [DEDUP_CHECK] Signature generada: {"EscenarioId":1000...
[15:30:45] 🔍 [DEDUP_CHECK] Buscando duplicados en 0 requests...
[15:30:45] ✅ [SAVED] Request FinalizarPedidoV3 guardado exitosamente
[15:30:45] ✅ [SAVED] Total en box: 1

[15:30:46] ⚠️ [FINALIZAR] Ya hay una finalización en curso, ignorando...

[15:30:50] 📦 [SAVE_FAILED] Intentando guardar request fallido: FinalizarPedidoV3
[15:30:50] 📦 [SAVE_FAILED] Total actual en box: 1
[15:30:50] 🔍 [DEDUP_CHECK] Endpoint V3 detectado: FinalizarPedidoV3
[15:30:50] 🔍 [DEDUP_CHECK] Buscando duplicados en 1 requests...
[15:30:50] 🔍 [DEDUP_CHECK] ⚠️ DUPLICADO ENCONTRADO!
[15:30:50] ⚠️ [DEDUP_BLOCKED] Duplicate FinalizarPedidoV3 detectado, NO se guarda nuevamente.
[15:30:50] ⚠️ [DEDUP_BLOCKED] ✅ Control de duplicados funcionando correctamente!
```

## 📅 Última Actualización

Noviembre 6, 2025

## 👤 Documentado por

GitHub Copilot Assistant
