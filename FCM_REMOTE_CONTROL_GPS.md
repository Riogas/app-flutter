# 🔔 Sistema de Control Remoto del GPS via FCM

## 📋 Descripción General

Sistema que permite **controlar remotamente el servicio GPS** desde el servidor mediante push notifications silenciosas de Firebase Cloud Messaging (FCM).

El servidor detecta cuando un dispositivo no envía coordenadas por más de N minutos y puede:
- Reiniciar el servicio GPS automáticamente
- Detener el servicio
- Forzar una ejecución inmediata del GPS
- Consultar el estado actual del servicio

**Todo se loguea en CriticalLogger** y se envía automáticamente a n8n cada 5 minutos.

---

## 🎯 Comandos Disponibles

### 1️⃣ `restart_gps_service` - Reiniciar GPS Service

Reinicia completamente el servicio GPS replicando el mismo flujo que cuando se hace login:
- Limpia todos los estados de deshabilitación/pausa
- Cancela AlarmManager y WorkManager anteriores
- Inicia ForegroundLocationService con todos los datos

**Payload FCM:**
```json
{
  "to": "<FCM_TOKEN_DEL_DISPOSITIVO>",
  "priority": "high",
  "data": {
    "action": "restart_gps_service"
  }
}
```

**Logs en n8n (secuencia esperada):**
```
1. FCM_PUSH_RECEIVED → Push recibido
2. FCM_RESTART_GPS_INITIATED → Validando datos del usuario
3. FCM_RESTART_GPS_STATES_CLEARED → Estados limpiados
4. FCM_RESTART_GPS_ALARM_CANCELLED → AlarmManager cancelado
5. FCM_RESTART_GPS_WORKMANAGER_CANCELLED → WorkManager cancelado
6. FCM_RESTART_GPS_STARTING_SERVICE → Iniciando ForegroundService
7. FCM_RESTART_GPS_SUCCESS → ✅ Reinicio exitoso
```

**Datos logueados:**
- `movil`, `escenario`, `usuario`, `deviceId`, `interval`
- `android_version`, `sdk_int`, `manufacturer`, `model`
- `trigger: "fcm_remote_command"`
- `step`: Indica el paso del flujo (1_validating_data, 2_states_cleared, etc.)

---

### 2️⃣ `stop_gps_service` - Detener GPS Service

Detiene completamente el servicio GPS y marca como `service_disabled`.

**Payload FCM:**
```json
{
  "to": "<FCM_TOKEN_DEL_DISPOSITIVO>",
  "priority": "high",
  "data": {
    "action": "stop_gps_service"
  }
}
```

**Logs en n8n:**
```
1. FCM_PUSH_RECEIVED → Push recibido
2. FCM_STOP_GPS_SUCCESS → Servicio detenido exitosamente
```

**Uso:** Cuando detectas que un móvil está enviando coordenadas erróneas o quieres detener el GPS manualmente desde el servidor.

---

### 3️⃣ `force_gps_execution` - Forzar Ejecución Inmediata

Fuerza una ejecución inmediata del GPS sin esperar el intervalo configurado.
**Si el servicio está muerto, lo reinicia primero automáticamente.**

**Payload FCM:**
```json
{
  "to": "<FCM_TOKEN_DEL_DISPOSITIVO>",
  "priority": "high",
  "data": {
    "action": "force_gps_execution"
  }
}
```

**Comportamiento:**
- **Si el servicio está corriendo:** Envía broadcast a `LocationReceiver` para ejecución inmediata
- **Si el servicio está muerto:** Reinicia el servicio con `EXECUTE_GPS=true` (ejecución inmediata al iniciar)

**Logs en n8n (servicio corriendo):**
```
1. FCM_PUSH_RECEIVED → Push recibido
2. FCM_FORCE_GPS_SUCCESS → GPS execution forzada (broadcast)
```

**Logs en n8n (servicio muerto):**
```
1. FCM_PUSH_RECEIVED → Push recibido
2. FCM_FORCE_GPS_RESTARTING_SERVICE → Servicio muerto detectado
3. FCM_FORCE_GPS_SUCCESS_WITH_RESTART → Servicio reiniciado + GPS ejecutado
```

**Uso:** Cuando necesitas la ubicación actual del móvil inmediatamente sin esperar el próximo ciclo programado. **Garantiza** que el GPS se ejecutará incluso si el servicio estaba muerto.

---

### 4️⃣ `get_status` - Consultar Estado del Servicio

Reporta el estado actual del servicio GPS del dispositivo.

**Payload FCM:**
```json
{
  "to": "<FCM_TOKEN_DEL_DISPOSITIVO>",
  "priority": "high",
  "data": {
    "action": "get_status"
  }
}
```

**Logs en n8n:**
```
1. FCM_PUSH_RECEIVED → Push recibido
2. FCM_GET_STATUS_REPORT → Reporte completo del estado
```

**Datos del reporte:**
- `movil`, `escenario`, `usuario`
- `service_disabled`: Si el servicio está deshabilitado manualmente
- `service_paused`: Si el servicio está pausado temporalmente
- `interval_minutes`: Intervalo configurado
- `android_version`, `manufacturer`, `model`

**Uso:** Para diagnóstico remoto cuando un móvil no reporta correctamente.

---

## 🔑 Obtener el FCM Token del Dispositivo

El token FCM se guarda automáticamente en `SharedPreferences` cuando la app se registra en Firebase:

```kotlin
// En FcmPushReceiver.kt
override fun onNewToken(token: String) {
    val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
    prefs.edit().putString("fcm_token", token).apply()
    
    // Se loguea como FCM_NEW_TOKEN en n8n
}
```

**Desde Flutter puedes recuperar el token y enviarlo al servidor:**
```dart
import 'package:firebase_messaging/firebase_messaging.dart';

final fcmToken = await FirebaseMessaging.instance.getToken();
// Enviar 'fcmToken' al servidor junto con 'movil'
```

---

## 📊 Monitoreo en n8n

### Flujo de Detección y Reinicio Automático

1. **Servidor recibe coordenadas** del móvil periódicamente
2. **Si pasan más de X minutos sin recibir coordenadas:**
   - Consulta la base de datos para obtener el `fcm_token` del móvil
   - Envía push FCM con `action: "restart_gps_service"`
3. **Dispositivo recibe el push:**
   - Ejecuta el flujo completo de reinicio
   - Loguea cada paso en CriticalLogger
4. **n8n recibe los logs** automáticamente cada 5 minutos:
   - `FCM_RESTART_GPS_INITIATED`
   - `FCM_RESTART_GPS_STATES_CLEARED`
   - `FCM_RESTART_GPS_ALARM_CANCELLED`
   - `FCM_RESTART_GPS_WORKMANAGER_CANCELLED`
   - `FCM_RESTART_GPS_STARTING_SERVICE`
   - `FCM_RESTART_GPS_SUCCESS`
5. **GPS service reiniciado** → Comienza a enviar coordenadas nuevamente

---

## 🛠️ Ejemplo de Workflow en n8n

```javascript
// 1. Detectar dispositivos sin reporte
const dispositivosSinReporte = await db.query(`
  SELECT movil, fcm_token, last_location_time
  FROM dispositivos
  WHERE last_location_time < NOW() - INTERVAL '10 minutes'
  AND fcm_token IS NOT NULL
`);

// 2. Enviar push FCM a cada dispositivo
for (const dispositivo of dispositivosSinReporte) {
  await fetch('https://fcm.googleapis.com/fcm/send', {
    method: 'POST',
    headers: {
      'Authorization': 'key=YOUR_SERVER_KEY',
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      to: dispositivo.fcm_token,
      priority: 'high',
      data: {
        action: 'restart_gps_service'
      }
    })
  });
  
  console.log(`✅ Push enviado a móvil ${dispositivo.movil}`);
}

// 3. Esperar 5 minutos y verificar logs de n8n
// Buscar logs con tipo: FCM_RESTART_GPS_SUCCESS
```

---

## ⚠️ Manejo de Errores

### Si el reinicio falla

El sistema loguea errores específicos en cada paso:

**Errores de validación:**
- `FCM_RESTART_GPS_FAILED` → `reason: "movil_empty"` o `"service_disabled"`

**Errores de cancelación:**
- `FCM_RESTART_GPS_ALARM_ERROR` → Error cancelando AlarmManager
- `FCM_RESTART_GPS_WORKMANAGER_ERROR` → Error cancelando WorkManager

**Error crítico:**
- `FCM_RESTART_GPS_EXCEPTION` → Excepción no controlada con stack trace completo

**Ejemplo de log de error:**
```json
{
  "type": "FCM_RESTART_GPS_EXCEPTION",
  "message": "FCM ERROR CRÍTICO: Error reiniciando GPS service",
  "data": {
    "movil": "MOV123",
    "error_type": "SecurityException",
    "error_message": "Permission denied",
    "stack_trace": "...",
    "trigger": "fcm_remote_command",
    "android_version": 31,
    "manufacturer": "Samsung",
    "model": "SM-G991B"
  }
}
```

---

## 🔄 Comparación: Watchdog vs FCM

| Característica | ServiceWatchdog | FCM Remote Control |
|---------------|-----------------|-------------------|
| **Trigger** | Local (CriticalLogWorker cada 30s) | Remoto (servidor via push) |
| **Detección** | Verifica si servicio está corriendo | Servidor detecta falta de coordenadas |
| **Alcance** | Solo dispositivo local | Todos los dispositivos desde servidor |
| **Latencia** | Máximo 30 segundos | Depende de FCM (~1-5 segundos) |
| **Logging** | WATCHDOG_* | FCM_* |
| **Uso** | Reinicio automático local | Control remoto centralizado |
| **Respeta service_disabled** | ❌ No (siempre reinicia) | ❌ No en restart (✅ Sí en stop) |
| **Puede deshabilitarse** | ✅ Sí (watchdog_disabled) | N/A |

**Ambos sistemas son complementarios:**
- **Watchdog**: Protección local contra crashes/kills del servicio - **SIEMPRE activo** (excepto si se desactiva con `stop_gps_service`)
- **FCM**: Control remoto desde servidor - puede forzar reinicio o detener completamente

## 🔐 Control de Estados

### **`service_disabled`** (Flag informativo)
- ✅ Se activa con: FCM `stop_gps_service` o detención manual desde UI
- ❌ **NO impide** reinicio por Watchdog
- ❌ **NO impide** reinicio por FCM `restart_gps_service`
- 📊 Solo informa que el servicio fue detenido manualmente

### **`watchdog_disabled`** (Control real)
- ✅ Se activa con: FCM `stop_gps_service`
- ✅ Se desactiva con: FCM `restart_gps_service` o login
- 🚫 **SÍ impide** reinicio por Watchdog
- ❌ **NO impide** reinicio por FCM `restart_gps_service`

### **Flujo de Control:**

```
Estado Normal:
├── service_disabled = false
├── watchdog_disabled = false
└── ✅ Watchdog protege el servicio (reinicia si muere)

Usuario/Servidor detiene GPS (FCM stop_gps_service):
├── service_disabled = true
├── watchdog_disabled = true
└── 🚫 Watchdog NO reiniciará (servicio detenido intencionalmente)

Servidor reinicia GPS (FCM restart_gps_service):
├── service_disabled = false
├── watchdog_disabled = false
└── ✅ Watchdog vuelve a proteger el servicio
```

---

## 🚀 Ventajas del Sistema FCM

✅ **Control centralizado** desde el servidor  
✅ **Diagnóstico remoto** sin intervención del usuario  
✅ **Reinicio selectivo** de dispositivos específicos  
✅ **Monitoreo proactivo** detectando problemas antes que el usuario  
✅ **Comandos adicionales** (stop, force execution, get status)  
✅ **Logging completo** de cada operación en n8n  
✅ **Recuperación automática** cuando GPS deja de reportar  

---

## 📱 Implementación en el Código

### Archivos Involucrados

1. **`FcmPushReceiver.kt`** - Servicio que recibe y procesa los push FCM
2. **`AndroidManifest.xml`** - Registro del servicio FCM
3. **`CriticalLogger.kt`** - Sistema de logging a n8n
4. **`ForegroundLocationService.kt`** - Servicio GPS que se reinicia

### Flujo de Código

```kotlin
// 1. FCM recibe el push
override fun onMessageReceived(remoteMessage: RemoteMessage) {
    val action = remoteMessage.data["action"]
    
    // 2. Loguea la recepción
    CriticalLogger.logCritical(..., "FCM_PUSH_RECEIVED")
    
    // 3. Ejecuta el comando
    when (action) {
        "restart_gps_service" -> handleRestartGpsService(remoteMessage)
        "stop_gps_service" -> handleStopGpsService(remoteMessage)
        "force_gps_execution" -> handleForceGpsExecution(remoteMessage)
        "get_status" -> handleGetStatus(remoteMessage)
    }
}

// 4. Reinicio completo (igual que login)
private fun handleRestartGpsService(...) {
    // Limpiar estados
    // Cancelar alarmas/workers
    // Iniciar ForegroundService
    // Loguear cada paso
}
```

---

## 🎓 Casos de Uso Reales

### Caso 1: GPS Muere por Restricción de Android
**Problema:** Android mata el servicio por optimización de batería  
**Solución:** Servidor detecta falta de coordenadas → Envía `restart_gps_service`  
**Resultado:** Servicio se reinicia automáticamente sin intervención del usuario

### Caso 2: Ubicación Urgente
**Problema:** Necesitas saber dónde está un móvil AHORA  
**Solución:** Envías `force_gps_execution` desde el servidor  
**Resultado:** 
- Si servicio está corriendo → GPS ejecuta inmediatamente
- Si servicio está muerto → Reinicia servicio + ejecuta GPS inmediatamente
- **Garantiza** obtención de coordenadas actuales

### Caso 3: Diagnóstico de Móvil Problemático
**Problema:** Un móvil reporta comportamiento extraño  
**Solución:** Envías `get_status` para ver su configuración actual  
**Resultado:** Recibes en n8n todos los detalles del estado del servicio

### Caso 4: Mantenimiento Programado
**Problema:** Necesitas detener temporalmente el GPS de varios móviles  
**Solución:** Envías `stop_gps_service` a los dispositivos seleccionados  
**Resultado:** Servicios detenidos sin que los usuarios tengan que hacerlo manualmente

---

## 🔒 Seguridad

- ✅ Los push son **data messages** (silenciosos), no se muestran notificaciones al usuario
- ✅ Solo el servidor con la **FCM Server Key** puede enviar comandos
- ✅ Cada comando se **loguea con timestamp** y detalles del dispositivo
- ✅ Validaciones de `movil` vacío y `service_disabled` antes de ejecutar comandos
- ✅ **Stack traces completos** en caso de errores para debugging

---

## 📝 Notas Técnicas

### ¿Por qué "high" priority?

```json
"priority": "high"
```

Los **data messages con prioridad alta** tienen mayor probabilidad de despertar la app aunque esté en Doze Mode o App Standby.

### ¿Funciona con la app cerrada?

**Sí**, FCM puede despertar la app incluso si está completamente cerrada (force-stopped por el sistema, no por el usuario manualmente).

### ¿Qué pasa si el dispositivo está offline?

FCM guardará el mensaje hasta **4 semanas** (TTL por defecto) y lo entregará cuando el dispositivo se conecte.

Puedes personalizar el TTL:
```json
{
  "to": "<token>",
  "priority": "high",
  "time_to_live": 3600,  // 1 hora
  "data": { "action": "restart_gps_service" }
}
```

---

## ✅ Checklist de Implementación

- [x] Crear `FcmPushReceiver.kt` con los 4 comandos
- [x] Registrar servicio en `AndroidManifest.xml`
- [x] Implementar logging completo en cada comando
- [x] Replicar flujo completo de login en `restart_gps_service`
- [x] Guardar `fcm_token` en SharedPreferences
- [x] Loguear generación de nuevo token FCM
- [ ] Enviar `fcm_token` al servidor desde Flutter al login
- [ ] Implementar workflow en n8n para detección de dispositivos sin reporte
- [ ] Probar cada comando y verificar logs en n8n

---

## 🎯 Próximos Pasos

1. **Obtener el token FCM desde Flutter y enviarlo al servidor:**
```dart
final token = await FirebaseMessaging.instance.getToken();
// POST al servidor con movil + token
```

2. **Crear workflow en n8n** para monitorear dispositivos y enviar push automáticamente

3. **Probar el sistema:**
   - Detener manualmente el GPS service
   - Enviar push FCM con `restart_gps_service`
   - Verificar logs en n8n
   - Confirmar que el servicio se reinicia correctamente

---

**¡Sistema FCM de Control Remoto del GPS implementado y documentado! 🚀**
