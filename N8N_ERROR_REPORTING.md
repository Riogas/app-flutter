# 📡 Feature: Envío de Errores a n8n

## 📋 Descripción

Se implementó un sistema de notificación automática de errores a n8n cuando un request a las APIs de RioGas falla y se guarda en `failedRequestsBox`.

## 🎯 Objetivo

Centralizar el monitoreo de errores en n8n para:
- ✅ Detectar problemas en tiempo real
- ✅ Analizar patrones de fallos
- ✅ Alertar al equipo técnico
- ✅ Generar métricas de disponibilidad
- ✅ Debugging remoto sin acceso a dispositivos

## 🏗️ Implementación

### 1️⃣ Webhook de n8n

**URL:** `https://n8n.riogas.com.uy/webhook/ProcesarErrores`

**Método:** `POST`

**Payload enviado:**
```json
{
  "timestamp": "2025-11-06T15:30:45.123Z",
  "endpoint": "FinalizarPedidoV3",
  "errorMessage": "HTTP 500: Internal Server Error",
  "payload": {
    "EscenarioId": 1000,
    "MovilId": 27861374,
    "PedidoId": 123456,
    ...
  },
  "movilId": "27861374",
  "username": "jgomez",
  "deviceId": "abc123-device-id",
  "escenarioId": "1000",
  "appVersion": "1.0.0"
}
```

### 2️⃣ Función `_sendErrorToN8n()`

Ubicación: `lib/services/riogas_service.dart`

**Responsabilidades:**
1. Construir payload con información completa del error
2. Incluir contexto del usuario (móvil, username, deviceId, escenario)
3. Enviar POST request a n8n
4. Manejar timeout (10 segundos)
5. No interrumpir el guardado en failedRequestsBox si n8n falla

**Código:**
```dart
static Future<void> _sendErrorToN8n(
  String endpoint,
  Map<String, dynamic> payload,
  String errorMessage,
) async {
  try {
    final sessionBox = await Hive.openBox('sessionBox');
    
    final n8nPayload = {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'endpoint': endpoint,
      'errorMessage': errorMessage,
      'payload': payload,
      'movilId': sessionBox.get('movil'),
      'username': sessionBox.get('username'),
      'deviceId': sessionBox.get('deviceId'),
      'escenarioId': sessionBox.get('escenario'),
      'appVersion': '1.0.0',
    };
    
    final response = await http.post(
      Uri.parse('https://n8n.riogas.com.uy/webhook/ProcesarErrores'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(n8nPayload),
    ).timeout(const Duration(seconds: 10));
    
    // Logging del resultado...
  } catch (e) {
    // No lanzar excepción para no interrumpir el guardado
  }
}
```

### 3️⃣ Integración con `_saveFailedRequest()`

**Cambios realizados:**

1. **Nueva firma con errorMessage opcional:**
```dart
static Future<void> _saveFailedRequest(
  String? endpoint,
  Map<String, dynamic>? payload, {
  String? errorMessage, // 🆕 NUEVO PARÁMETRO
}) async {
```

2. **Llamada a n8n después de guardar exitosamente:**
```dart
await failedRequestsBox.add({
  'endpoint': endpoint,
  'payload': payload,
  'signature': newSignature,
  'timestamp': DateTime.now().toIso8601String(),
});

// 🆕 Enviar error a n8n
await _sendErrorToN8n(
  endpoint,
  payload,
  errorMessage ?? 'Error desconocido - request fallido',
);
```

3. **Actualización de todas las llamadas:**
```dart
// Error HTTP
await _saveFailedRequest(
  endpoint,
  body,
  errorMessage: 'HTTP ${response.statusCode}: ${response.body}',
);

// Exception
await _saveFailedRequest(
  endpoint,
  body,
  errorMessage: 'Exception: $e',
);

// Network error
await _saveFailedRequest(
  endpoint,
  body,
  errorMessage: e is SocketException 
    ? 'Network issue: Sin conexión a internet'
    : 'Exception: $e',
);
```

## 📊 Flujo de Funcionamiento

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Request a API de RioGas falla                           │
│    (HTTP error, timeout, sin conexión, etc.)               │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Se ejecuta _saveFailedRequest()                         │
│    - Verifica duplicados (deduplicación)                   │
│    - Si NO es duplicado → continúa                         │
│    - Si ES duplicado → bloquea y termina                   │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Guarda en failedRequestsBox                             │
│    - Agrega endpoint, payload, signature, timestamp        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Llama _sendErrorToN8n()                                 │
│    - Construye payload con contexto completo               │
│    - POST a https://n8n.riogas.com.uy/webhook/ProcesarErrores│
│    - Timeout: 10 segundos                                  │
└────────────────────┬────────────────────────────────────────┘
                     │
            ┌────────┴────────┐
            ▼                 ▼
    ┌──────────────┐  ┌──────────────┐
    │   Success    │  │    Error     │
    │   (200/201)  │  │ (timeout/500)│
    └──────┬───────┘  └──────┬───────┘
           │                  │
           ▼                  ▼
    ✅ Log exitoso    ⚠️ Log error
    (no bloquea)     (no bloquea)
```

## 📝 Logs de Monitoreo

### ✅ Cuando se envía exitosamente a n8n:

```
📦 [SAVE_FAILED] Intentando guardar request fallido: FinalizarPedidoV3
📦 [SAVE_FAILED] Total actual en box: 5
📦 [SAVE_FAILED] Error: HTTP 500: Internal Server Error
✅ [SAVED] Request FinalizarPedidoV3 guardado exitosamente
✅ [SAVED] Total en box: 6
📤 [N8N_ERROR] Enviando error a n8n: FinalizarPedidoV3
✅ [N8N_ERROR] Error enviado exitosamente a n8n
✅ [N8N_ERROR] Response: {"success": true, "message": "Error received"}
```

### ⚠️ Cuando n8n falla (pero no bloquea el guardado):

```
📦 [SAVE_FAILED] Intentando guardar request fallido: DescargaPedidos
✅ [SAVED] Request DescargaPedidos guardado exitosamente
📤 [N8N_ERROR] Enviando error a n8n: DescargaPedidos
⏰ [N8N_ERROR] Timeout enviando error a n8n (10s)
```

```
✅ [SAVED] Request guardado exitosamente
📤 [N8N_ERROR] Enviando error a n8n: FinalizarPedidoV3
❌ [N8N_ERROR] Sin conexión a internet para enviar a n8n
```

### 🔍 Cuando se bloquea un duplicado (NO se envía a n8n):

```
📦 [SAVE_FAILED] Intentando guardar request fallido: FinalizarPedidoV3
🔍 [DEDUP_CHECK] Buscando duplicados...
🔍 [DEDUP_CHECK] ⚠️ DUPLICADO ENCONTRADO!
⚠️ [DEDUP_BLOCKED] Duplicate detectado, NO se guarda nuevamente.
⚠️ [DEDUP_BLOCKED] ✅ Control de duplicados funcionando correctamente!
```
**Nota:** Como NO se guarda, tampoco se envía a n8n (evita duplicados en n8n también)

## 🎯 Casos de Uso

### 1. Error HTTP (servidor devuelve 500)
```
errorMessage: "HTTP 500: Internal Server Error"
```

### 2. Exception (error en código)
```
errorMessage: "Exception: FormatException: Invalid JSON"
```

### 3. Timeout
```
errorMessage: "Exception: TimeoutException after 30 seconds"
```

### 4. Sin conexión
```
errorMessage: "Network issue: Sin conexión a internet"
```

## 🛡️ Protecciones Implementadas

### 1️⃣ **No bloquea el guardado en failedRequestsBox**

Si n8n falla, el error se guarda igualmente en Hive para reintento posterior.

```dart
try {
  // Enviar a n8n...
} catch (e) {
  print('❌ [N8N_ERROR] Error enviando a n8n: $e');
  // NO lanzamos excepción → no interrumpe el guardado
}
```

### 2️⃣ **Timeout de 10 segundos**

Evita que un n8n lento bloquee la aplicación.

```dart
await http.post(...).timeout(const Duration(seconds: 10));
```

### 3️⃣ **Manejo de excepciones**

```dart
on TimeoutException {
  print('⏰ [N8N_ERROR] Timeout enviando error a n8n (10s)');
}
on SocketException {
  print('❌ [N8N_ERROR] Sin conexión a internet para enviar a n8n');
}
catch (e) {
  print('❌ [N8N_ERROR] Error enviando a n8n: $e');
}
```

### 4️⃣ **Solo envía si se guarda exitosamente**

Si el request es duplicado y se bloquea, NO se envía a n8n (evita spam).

## 🔧 Configuración en n8n

Para que este webhook funcione, se debe configurar en n8n:

### Webhook Node:

- **Path:** `/webhook/ProcesarErrores`
- **Method:** `POST`
- **Response:** `Respond to Webhook` con status 200/201

### Procesamiento Sugerido:

1. **Validar payload**
2. **Guardar en base de datos** (PostgreSQL, MongoDB, etc.)
3. **Enviar notificación** (Email, Slack, Telegram, etc.)
4. **Generar métricas** (Grafana, Datadog, etc.)
5. **Trigger alertas** si hay muchos errores del mismo tipo

### Ejemplo de flujo n8n:

```
Webhook Trigger
    ↓
Validar Payload
    ↓
Guardar en DB
    ↓
    ├─→ Enviar Email (si error crítico)
    ├─→ Notificar Slack (si > 10 errores/min)
    └─→ Actualizar Dashboard (Grafana)
```

## 📊 Datos Enviados a n8n

| Campo | Descripción | Ejemplo |
|-------|-------------|---------|
| `timestamp` | Timestamp UTC del error | `2025-11-06T15:30:45.123Z` |
| `endpoint` | Endpoint que falló | `FinalizarPedidoV3` |
| `errorMessage` | Mensaje descriptivo del error | `HTTP 500: Internal Server Error` |
| `payload` | Payload completo del request fallido | `{EscenarioId: 1000, ...}` |
| `movilId` | ID del móvil | `27861374` |
| `username` | Usuario autenticado | `jgomez` |
| `deviceId` | ID único del dispositivo | `abc123-device-id` |
| `escenarioId` | ID del escenario | `1000` |
| `appVersion` | Versión de la app | `1.0.0` |

## 🧪 Testing

### Prueba 1: Error HTTP
```
1. Apagar servidor RioGas
2. Finalizar un pedido
3. Verificar logs: "✅ [N8N_ERROR] Error enviado exitosamente a n8n"
4. Verificar en n8n que llegó el error
```

### Prueba 2: Sin conexión
```
1. Poner móvil en modo avión
2. Descargar pedidos
3. Verificar logs: "❌ [N8N_ERROR] Sin conexión a internet para enviar a n8n"
4. Verificar que el request SE guardó en failedRequestsBox de todas formas
```

### Prueba 3: n8n caído
```
1. Apagar n8n temporalmente
2. Marcar mensaje como leído con servidor caído
3. Verificar logs: "⏰ [N8N_ERROR] Timeout enviando error a n8n"
4. Verificar que el request SE guardó en failedRequestsBox de todas formas
```

## 📅 Última Actualización

Noviembre 6, 2025

## 👤 Implementado por

GitHub Copilot Assistant
