# 🔐 Lógica de Control del GPS Service - Flags y Estados

## 📊 Flags de Control

### 1️⃣ `service_disabled` (Flag Informativo)
**Propósito:** Indicar que el servicio fue detenido manualmente  
**Ubicación:** SharedPreferences "config"  
**NO impide reinicios automáticos**

- ✅ Se activa con:
  - FCM comando `stop_gps_service`
  - Detención manual desde UI
  - API ok=1 (legacy, si existe)
  
- ✅ Se desactiva con:
  - FCM comando `restart_gps_service`
  - Login exitoso
  - Inicio manual desde UI

- ❌ NO impide:
  - Reinicio por ServiceWatchdog
  - Reinicio por FCM `restart_gps_service`

---

### 2️⃣ `watchdog_disabled` (Control Real)
**Propósito:** Deshabilitar completamente el watchdog de reinicio automático  
**Ubicación:** SharedPreferences "config"  
**SÍ impide reinicios del watchdog**

- ✅ Se activa con:
  - FCM comando `stop_gps_service` (única forma)
  
- ✅ Se desactiva con:
  - FCM comando `restart_gps_service`
  - Login exitoso

- 🚫 SÍ impide:
  - Reinicio por ServiceWatchdog

- ❌ NO impide:
  - Reinicio por FCM `restart_gps_service` (forzado)

---

## 🔄 Flujos de Control

### Flujo 1: Watchdog Detecta Servicio Muerto

```
1. CriticalLogUploadWorker ejecuta cada 30s
2. Verifica si ForegroundLocationService está corriendo
3. Si NO está corriendo:
   ├─ Valida movil no vacío
   ├─ Verifica watchdog_disabled
   │  ├─ Si watchdog_disabled=true → ❌ NO reinicia (log: WATCHDOG_RESTART_BLOCKED)
   │  └─ Si watchdog_disabled=false → ✅ Reinicia (IGNORA service_disabled)
   └─ Ejecuta flujo completo de reinicio:
      ├─ Limpia estados (service_disabled, stop_reason, etc.)
      ├─ Cancela AlarmManager
      ├─ Cancela WorkManager
      ├─ Inicia ForegroundLocationService
      └─ Loguea cada paso (WATCHDOG_RESTART_*)
```

**Logs esperados en n8n:**
```
WATCHDOG_RESTART_INITIATED
WATCHDOG_RESTART_STATE_CLEARED
WATCHDOG_RESTART_ALARM_CANCELLED
WATCHDOG_RESTART_WORKMANAGER_CANCELLED
WATCHDOG_RESTART_STARTING_SERVICE
WATCHDOG_SERVICE_RESTARTED_SUCCESS
```

---

### Flujo 2: FCM Comando `restart_gps_service`

```
1. Servidor envía push FCM con action="restart_gps_service"
2. FcmPushReceiver recibe el mensaje
3. Valida solo movil no vacío (IGNORA service_disabled y watchdog_disabled)
4. Si servicio estaba deshabilitado:
   └─ Loguea que lo está habilitando (FCM_RESTART_GPS_ENABLING_SERVICE)
5. Limpia TODOS los estados:
   ├─ service_disabled = false
   ├─ watchdog_disabled = false ✅ (re-habilita watchdog)
   ├─ stop_reason, stop_timestamp, etc.
   └─ service_paused, resume_time, etc.
6. Cancela AlarmManager y WorkManager
7. Inicia ForegroundLocationService con IS_FCM_RESTART=true
8. Loguea cada paso (FCM_RESTART_GPS_*)
```

**Logs esperados en n8n:**
```
FCM_PUSH_RECEIVED
FCM_RESTART_GPS_INITIATED
(opcional) FCM_RESTART_GPS_ENABLING_SERVICE  // Si estaba deshabilitado
FCM_RESTART_GPS_STATES_CLEARED
FCM_RESTART_GPS_ALARM_CANCELLED
FCM_RESTART_GPS_WORKMANAGER_CANCELLED
FCM_RESTART_GPS_STARTING_SERVICE
FCM_RESTART_GPS_SUCCESS
```

---

### Flujo 3: FCM Comando `force_gps_execution`

```
1. Servidor envía push FCM con action="force_gps_execution"
2. FcmPushReceiver recibe el mensaje
3. Verifica si ForegroundLocationService está corriendo:
   
   A) Si está corriendo:
      ├─ Envía broadcast a LocationReceiver
      └─ Loguea FCM_FORCE_GPS_SUCCESS
   
   B) Si está muerto:
      ├─ Loguea FCM_FORCE_GPS_RESTARTING_SERVICE
      ├─ Limpia estados (service_disabled=false, watchdog_disabled=false)
      ├─ Inicia ForegroundLocationService con:
      │  ├─ EXECUTE_GPS=true (ejecutar inmediatamente)
      │  └─ IS_FCM_FORCE=true (marcar origen)
      └─ Loguea FCM_FORCE_GPS_SUCCESS_WITH_RESTART
```

**Resultado:**
- ✅ GPS se ejecuta inmediatamente (sin esperar intervalo)
- ✅ Si servicio estaba muerto, se reinicia automáticamente
- ✅ Watchdog se re-habilita si estaba deshabilitado

**Logs esperados en n8n (servicio corriendo):**
```
FCM_PUSH_RECEIVED
FCM_FORCE_GPS_SUCCESS
```

**Logs esperados en n8n (servicio muerto):**
```
FCM_PUSH_RECEIVED
FCM_FORCE_GPS_RESTARTING_SERVICE
FCM_FORCE_GPS_SUCCESS_WITH_RESTART
```

---

### Flujo 4: FCM Comando `stop_gps_service`

```
1. Servidor envía push FCM con action="stop_gps_service"
2. FcmPushReceiver recibe el mensaje
3. Detiene ForegroundLocationService (stopService)
4. Marca flags:
   ├─ service_disabled = true
   └─ watchdog_disabled = true 🚫 (deshabilita watchdog)
5. Loguea detención (FCM_STOP_GPS_SUCCESS)
```

**Resultado:**
- ✅ Servicio detenido
- ✅ Watchdog NO lo reiniciará (watchdog_disabled=true)
- ✅ Solo `restart_gps_service` puede volver a iniciarlo

**Logs esperados en n8n:**
```
FCM_PUSH_RECEIVED
FCM_STOP_GPS_SUCCESS
```

---

### Flujo 5: Login desde Flutter

```
1. Usuario selecciona móvil y hace login
2. Flutter guarda datos en Hive
3. Flutter envía datos a Android vía MethodChannel:
   └─ saveMovil (guarda en SharedPreferences "user_data")
4. Flutter llama startLocationService vía MethodChannel
5. MainActivity:
   ├─ Limpia estados (service_disabled, watchdog_disabled, etc.)
   ├─ Loguea SERVICE_STARTED_MANUALLY
   └─ Inicia ForegroundLocationService con EXECUTE_GPS=true
6. ForegroundLocationService.onCreate():
   ├─ Programa AlarmManager
   ├─ Programa WorkManager
   └─ Inicia servicio foreground con notificación
```

**Resultado:**
- ✅ Servicio iniciado completo
- ✅ Watchdog habilitado (watchdog_disabled=false)
- ✅ AlarmManager y WorkManager programados

---

## 🎯 Casos de Uso

### Caso 1: Android mata el servicio por optimización de batería
**Situación:**
```
├─ ForegroundLocationService muere
├─ service_disabled = false
└─ watchdog_disabled = false
```
**Resultado:**
```
✅ Watchdog detecta servicio muerto (máximo 30s)
✅ Reinicia automáticamente (WATCHDOG_SERVICE_RESTARTED_SUCCESS)
✅ GPS vuelve a funcionar
```

---

### Caso 2: Usuario detiene el servicio manualmente desde UI
**Situación:**
```
├─ Usuario presiona "Detener GPS" en la app
├─ service_disabled = true
└─ watchdog_disabled = false (por ahora)
```
**Resultado:**
```
⚠️ Watchdog SIGUE reiniciando (porque watchdog_disabled=false)
💡 Para detener completamente, usar FCM stop_gps_service
```

---

### Caso 3: Servidor detecta falta de coordenadas y envía FCM stop
**Situación:**
```
├─ Servidor no recibe coordenadas hace 30 minutos
└─ Envía FCM stop_gps_service
```
**Acción:**
```
1. ForegroundLocationService se detiene
2. service_disabled = true
3. watchdog_disabled = true 🚫
```
**Resultado:**
```
✅ Servicio detenido completamente
✅ Watchdog NO reiniciará
✅ Solo FCM restart_gps_service puede volver a iniciarlo
```

---

### Caso 4: Servidor quiere reiniciar GPS de móvil específico
**Situación:**
```
├─ Móvil "MOV123" no envía coordenadas hace 10 minutos
├─ service_disabled = true (detenido previamente)
└─ watchdog_disabled = true (detenido por FCM stop)
```
**Acción:**
```
Servidor envía FCM restart_gps_service
```
**Resultado:**
```
✅ Ignora service_disabled y watchdog_disabled
✅ Limpia TODOS los estados
✅ Re-habilita watchdog (watchdog_disabled=false)
✅ Reinicia servicio completo
✅ GPS vuelve a funcionar + Watchdog lo protege
```

---

## 🔐 Matriz de Decisiones

| Estado Actual | Evento | Acción |
|--------------|--------|--------|
| service_disabled=false, watchdog_disabled=false | Servicio muere | ✅ Watchdog reinicia |
| service_disabled=true, watchdog_disabled=false | Servicio muere | ✅ Watchdog reinicia (ignora service_disabled) |
| service_disabled=false, watchdog_disabled=true | Servicio muere | ❌ Watchdog NO reinicia |
| service_disabled=true, watchdog_disabled=true | Servicio muere | ❌ Watchdog NO reinicia |
| Cualquier estado | FCM restart_gps_service | ✅ SIEMPRE reinicia + habilita watchdog |
| Cualquier estado | FCM force_gps_execution (servicio muerto) | ✅ Reinicia + ejecuta GPS inmediatamente + habilita watchdog |
| Cualquier estado | FCM force_gps_execution (servicio vivo) | ✅ Envía broadcast para ejecución inmediata |
| Cualquier estado | FCM stop_gps_service | ✅ Detiene + deshabilita watchdog |
| Cualquier estado | Login desde Flutter | ✅ Inicia + habilita watchdog |

---

## 🚨 Reglas Críticas

### ✅ SIEMPRE reinician (sin validar flags):
1. FCM `restart_gps_service` (forzado desde servidor)
2. FCM `force_gps_execution` **si servicio está muerto** (forzado desde servidor)
3. Login desde Flutter (inicio manual usuario)
4. ServiceWatchdog **si watchdog_disabled=false** (protección local)

### 🚫 NUNCA reinician (respetan watchdog_disabled=true):
1. ServiceWatchdog **si watchdog_disabled=true**

### 🔄 Habilitan watchdog automáticamente:
1. FCM `restart_gps_service`
2. Login desde Flutter

### 🚫 Deshabilitan watchdog:
1. FCM `stop_gps_service` (única forma)

---

## 📝 Notas Técnicas

### ¿Por qué service_disabled no impide reinicio del watchdog?

**Antes (comportamiento erróneo):**
```kotlin
if (isDisabled) {
    // ❌ No reiniciar si service_disabled=true
    return false
}
```
**Problema:** Si el servicio moría por error de Android, el watchdog NO lo reiniciaba solo porque había un flag "disabled" que podría estar en true por muchas razones (detención temporal, error anterior, etc.).

**Ahora (comportamiento correcto):**
```kotlin
if (watchdogDisabled) {
    // ✅ Solo respetar watchdog_disabled (flag específico)
    return false
}
// service_disabled es solo informativo, no impide reinicio
```
**Ventaja:** El watchdog SIEMPRE protege el servicio a menos que se deshabilite explícitamente con `stop_gps_service` desde FCM.

---

### ¿Por qué FCM restart_gps_service ignora TODOS los flags?

**Razón:** Es un **comando remoto explícito del servidor**. Si el servidor envía este comando, es porque:
1. Detectó que el dispositivo no está enviando coordenadas
2. Necesita que el GPS se reinicie AHORA
3. No le importa el estado anterior del servicio

**Comportamiento:**
```kotlin
// FCM restart SIEMPRE reinicia, sin importar flags
if (isDisabled) {
    Log.i(TAG, "Habilitando servicio por comando FCM")
}
// Limpiar TODOS los flags y reiniciar
```

---

## ✅ Checklist de Validación

Después de implementar estos cambios, validar:

- [ ] Watchdog reinicia servicio si muere (con watchdog_disabled=false)
- [ ] Watchdog NO reinicia servicio si watchdog_disabled=true
- [ ] FCM restart_gps_service SIEMPRE reinicia (ignora flags)
- [ ] FCM stop_gps_service detiene servicio Y deshabilita watchdog
- [ ] Login desde Flutter habilita watchdog
- [ ] Todos los logs se envían correctamente a n8n
- [ ] Probar secuencia: stop → esperar → restart → verificar que watchdog vuelve a proteger

---

**Sistema de flags corregido e implementado! 🚀**
