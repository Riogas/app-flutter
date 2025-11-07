# 🚩 Sistema de Flags de Estado de Servicios

## 📋 Resumen

Se ha implementado un sistema de flags en SharedPreferences que permite a los servicios de Kotlin (GPS y CriticalLog) marcar cuando detectan que algún servicio está apagado. Esta flag es accesible desde Dart a través de `RioGasService`.

## 🎯 Propósito

- **Monitoreo Mutuo**: Los servicios GPS y CriticalLog se verifican entre sí constantemente
- **Flag Centralizada**: Cuando detectan que alguno está apagado, marcan una flag en SharedPreferences
- **Acceso desde Dart**: La flag puede ser consultada desde Flutter/Dart para tomar decisiones
- **Respeto al Cierre de Sesión**: La flag NO se modifica si el servicio fue detenido por FCM `stop_gps_service` (cierre de sesión)

## 🏗️ Arquitectura

### 1. ServiceStatusFlags.kt (Nuevo)
**Ubicación**: `android/app/src/main/kotlin/com/riogas/appmovil/ServiceStatusFlags.kt`

**Funciones principales**:
```kotlin
// Marcar que servicios necesitan reiniciarse
ServiceStatusFlags.setServicesNeedRestart(context, true/false, "ServicioQueVerifica", "razón")

// Obtener estado de la flag
ServiceStatusFlags.getServicesNeedRestart(context)

// Marcar estados individuales
ServiceStatusFlags.setGPSServiceStatus(context, true/false, "QuienVerifica")
ServiceStatusFlags.setCriticalLogServiceStatus(context, true/false, "QuienVerifica")

// Obtener estado completo
ServiceStatusFlags.getFullStatus(context)

// Limpiar todas las flags
ServiceStatusFlags.clearAllFlags(context)
```

**SharedPreferences utilizadas**:
- `services_need_restart` (Boolean): Flag principal - true si algún servicio está apagado
- `services_last_check_timestamp` (Long): Timestamp de última verificación
- `services_check_by` (String): Servicio que hizo la verificación
- `services_check_reason` (String): Razón de la verificación
- `gps_service_status` (Boolean): Estado del GPS Service
- `critical_log_status` (Boolean): Estado del CriticalLog Service

**Validación importante**:
```kotlin
val watchdogDisabled = prefs.getBoolean("watchdog_disabled", false)
if (watchdogDisabled) {
    // NO modificar flags - respeta cierre de sesión FCM
    return false
}
```

### 2. ServiceWatchdog.kt (Modificado)
**Ubicación**: `android/app/src/main/kotlin/com/riogas/appmovil/ServiceWatchdog.kt`

**Cambios**:

#### En `restartGPSService()`:
```kotlin
// Al detectar GPS muerto:
ServiceStatusFlags.setServicesNeedRestart(context, true, "ServiceWatchdog", "GPS service detectado como muerto")
ServiceStatusFlags.setGPSServiceStatus(context, false, "ServiceWatchdog")

// Después de reiniciar exitosamente:
ServiceStatusFlags.setGPSServiceStatus(context, true, "ServiceWatchdog")
```

#### En `restartCriticalLogWorker()`:
```kotlin
// Al detectar CriticalLog no programado:
ServiceStatusFlags.setServicesNeedRestart(context, true, "GPS_Service", "CriticalLogAlarmReceiver no está programada")
ServiceStatusFlags.setCriticalLogServiceStatus(context, false, "GPS_Service")

// Después de re-programar exitosamente:
ServiceStatusFlags.setCriticalLogServiceStatus(context, true, "GPS_Service")
```

### 3. CriticalLogAlarmReceiver.kt (Modificado)
**Ubicación**: `android/app/src/main/kotlin/com/riogas/appmovil/CriticalLogAlarmReceiver.kt`

**Cambios en `performWatchdogCheck()`**:

```kotlin
if (!isGPSRunning || !isAlarmScheduled) {
    // GPS MUERTO
    ServiceStatusFlags.setServicesNeedRestart(context, true, "CriticalLogAlarm", "GPS service detectado como muerto")
    ServiceStatusFlags.setGPSServiceStatus(context, false, "CriticalLogAlarm")
    
    // Intentar reiniciar...
    
    if (restarted) {
        ServiceStatusFlags.setGPSServiceStatus(context, true, "CriticalLogAlarm")
    }
} else {
    // TODO ACTIVO
    ServiceStatusFlags.setServicesNeedRestart(context, false, "CriticalLogAlarm", "GPS service verificado activo y saludable")
    ServiceStatusFlags.setGPSServiceStatus(context, true, "CriticalLogAlarm")
}
```

### 4. ForegroundLocationService.kt (Modificado)
**Ubicación**: `android/app/src/main/kotlin/com/example/moveit/ForegroundLocationService.kt`

**Cambios en verificación de CriticalLogWorker**:

```kotlin
if (!isWorkerScheduled) {
    // CriticalLog NO programado
    ServiceStatusFlags.setServicesNeedRestart(context, true, "ForegroundLocationService", "CriticalLogWorker no está programado")
    ServiceStatusFlags.setCriticalLogServiceStatus(context, false, "ForegroundLocationService")
    
    // Re-programar...
} else {
    // TODO ACTIVO
    ServiceStatusFlags.setServicesNeedRestart(context, false, "ForegroundLocationService", "CriticalLogWorker verificado activo")
    ServiceStatusFlags.setCriticalLogServiceStatus(context, true, "ForegroundLocationService")
}
```

### 5. RioGasService.dart (Modificado)
**Ubicación**: `lib/services/riogas_service.dart`

**Nuevos métodos agregados**:

```dart
// Obtener flag principal
static Future<bool?> getServicesNeedRestart() async {
  try {
    final bool result = await _serviceStatusChannel.invokeMethod('getServicesNeedRestart');
    return result;
  } catch (e) {
    return null;
  }
}

// Obtener estado completo
static Future<Map<String, dynamic>?> getFullServiceStatus() async {
  try {
    final Map<dynamic, dynamic> result = await _serviceStatusChannel.invokeMethod('getFullServiceStatus');
    return Map<String, dynamic>.from(result);
  } catch (e) {
    return null;
  }
}

// Limpiar todas las flags
static Future<bool> clearAllServiceFlags() async {
  try {
    await _serviceStatusChannel.invokeMethod('clearAllServiceFlags');
    return true;
  } catch (e) {
    return false;
  }
}
```

### 6. MainActivity.kt (Modificado)
**Ubicación**: `android/app/src/main/kotlin/com/example/moveit/MainActivity.kt`

**Nuevo MethodChannel agregado**:

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.riogas.appmovil/service_status")
    .setMethodCallHandler { call, result ->
        when (call.method) {
            "getServicesNeedRestart" -> {
                val needRestart = ServiceStatusFlags.getServicesNeedRestart(this)
                result.success(needRestart)
            }
            "getFullServiceStatus" -> {
                val status = ServiceStatusFlags.getFullStatus(this)
                result.success(status)
            }
            "clearAllServiceFlags" -> {
                ServiceStatusFlags.clearAllFlags(this)
                result.success(true)
            }
        }
    }
```

## 🔄 Flujo de Funcionamiento

### Ciclo Normal (Servicios Activos)

1. **CriticalLogAlarmReceiver** se ejecuta cada 30 segundos
2. Verifica que GPS Service esté corriendo
3. Si GPS está activo:
   - Marca `services_need_restart = false`
   - Marca `gps_service_status = true`
   - Log: "GPS service verificado activo y saludable"

4. **ForegroundLocationService** también verifica CriticalLog
5. Si CriticalLog está programado:
   - Marca `services_need_restart = false`
   - Marca `critical_log_status = true`
   - Log: "CriticalLogWorker verificado activo"

### Ciclo de Detección de Fallo

1. **CriticalLogAlarmReceiver** detecta GPS muerto
2. Marca `services_need_restart = true`
3. Marca `gps_service_status = false`
4. Llama a `ServiceWatchdog.restartGPSService()`
5. Si reinicio exitoso:
   - Marca `gps_service_status = true`
6. En próxima verificación (30 seg después):
   - Si GPS está activo: marca `services_need_restart = false`

### Respeto al Cierre de Sesión FCM

Cuando `stop_gps_service` es recibido via FCM:

```kotlin
// En FcmPushReceiver
prefs.edit().apply {
    putBoolean("service_disabled", true)
    putBoolean("watchdog_disabled", true)  // 🚫 Desactiva watchdog
}.apply()
```

Todas las funciones de `ServiceStatusFlags` validan:
```kotlin
val watchdogDisabled = prefs.getBoolean("watchdog_disabled", false)
if (watchdogDisabled) {
    // NO modificar flags
    return false
}
```

Esto significa:
- ✅ La flag NO se actualiza si el servicio fue detenido por cierre de sesión
- ✅ Solo `restart_gps_service` (FCM) puede volver a habilitar el watchdog
- ✅ Solo al iniciar sesión nuevamente se reactiva todo el sistema

## 📱 Uso desde Dart/Flutter

### Ejemplo básico:

```dart
// Verificar si servicios necesitan reiniciarse
bool? needRestart = await RioGasService.getServicesNeedRestart();
if (needRestart == true) {
  print('⚠️ Servicios necesitan reiniciarse');
  // Tomar acción...
}

// Obtener estado completo
Map<String, dynamic>? status = await RioGasService.getFullServiceStatus();
if (status != null) {
  print('GPS Status: ${status['gps_service_status']}');
  print('CriticalLog Status: ${status['critical_log_status']}');
  print('Watchdog Disabled: ${status['watchdog_disabled']}');
  print('Last Check: ${status['checked_by']}');
}

// Limpiar flags (ej: al iniciar sesión)
await RioGasService.clearAllServiceFlags();
```

### Ejemplo en algún servicio:

```dart
// En algún método que envíe datos al servidor
static Future<void> enviarDatosServidor(Map<String, dynamic> data) async {
  // Agregar flag de estado de servicios
  bool? servicesNeedRestart = await getServicesNeedRestart();
  
  data['services_need_restart'] = servicesNeedRestart ?? false;
  data['services_checked_by'] = 'FlutterService';
  
  // Enviar datos...
  await _post('AlgunEndpoint', data);
}
```

## 🔍 Logs para Debugging

Todos los cambios de flag se loguean automáticamente:

```
🚩 Flag actualizada: services_need_restart = true
   - Verificado por: CriticalLogAlarm
   - Razón: GPS service detectado como muerto
   - Timestamp: 14:35:20

🚩 Flag actualizada: services_need_restart = false
   - Verificado por: CriticalLogAlarm
   - Razón: GPS service verificado activo y saludable
   - Timestamp: 14:35:50
```

También se envían logs críticos a n8n:
```
"FLAG_UPDATED" - Estado de servicios actualizado
"FLAG_UPDATE_BLOCKED" - Intento bloqueado por watchdog_disabled
```

## 📝 Notas Importantes

1. **La flag se actualiza automáticamente**: No necesitas llamar manualmente desde Dart para actualizarla
2. **Solo consulta desde Dart**: Usa los métodos de RioGasService para LEER el estado
3. **Respeta cierre de sesión**: Si `watchdog_disabled=true`, las flags no se modifican
4. **Verificación constante**: Se verifica cada 30 segundos automáticamente
5. **Auto-recuperación**: Si un servicio muere, el otro lo detecta y reinicia

## ✅ Testing

Para probar el sistema:

1. **Ver estado actual**:
```dart
var status = await RioGasService.getFullServiceStatus();
print(status);
```

2. **Simular fallo**: Detener manualmente un servicio desde Android
3. **Verificar logs**: Buscar logs con tag `[FLAGS]` o `[WATCHDOG]`
4. **Verificar auto-recuperación**: El servicio debería reiniciarse automáticamente en ~30 segundos

## 🎉 Conclusión

El sistema está completamente implementado y listo para usar. La flag `services_need_restart` se puede acceder desde `RioGasService` y utilizarla en cualquier servicio que necesite saber si los servicios de background están funcionando correctamente.

**NO se modificaron los servicios que envían datos** - como solicitaste, solo se agregaron los métodos para acceder a la flag, pero no se modificó ningún servicio que envíe datos al servidor.
