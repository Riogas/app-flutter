# 🐞 GPS Service Manager - Guía de Debug

## 📋 Índice
1. [Activar/Desactivar Debug Mode](#activar-debug-mode)
2. [Logs Disponibles](#logs-disponibles)
3. [Filtrar Logs en PowerShell](#filtrar-logs-powershell)
4. [Monitorear Circuit Breaker](#monitorear-circuit-breaker)
5. [Logs del Force GPS](#logs-force-gps)

---

## 🔧 Activar Debug Mode

### 1️⃣ **Desde el `main.dart` (Inicio de la app)**

Agregar al inicio de la función `main()`:

```dart
import 'services/gps_service_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 🐞 ACTIVAR DEBUG MODE DEL GPS SERVICE MANAGER
  GpsServiceManager.setDebugMode(true); // ← AGREGAR ESTA LÍNEA
  
  await Firebase.initializeApp(...);
  // ... resto del código
}
```

### 2️⃣ **Desde un Widget de Configuración (Toggle on/off)**

Crear un switch en `settings_page.dart`:

```dart
import 'package:flutter/material.dart';
import '../services/gps_service_manager.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _gpsDebugMode = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Configuración')),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text('🐞 Debug GPS Service Manager'),
            subtitle: Text('Muestra logs detallados del GPS'),
            value: _gpsDebugMode,
            onChanged: (bool value) {
              setState(() {
                _gpsDebugMode = value;
                GpsServiceManager.setDebugMode(value);
              });
              
              // Mostrar confirmación
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Debug GPS ${value ? "ACTIVADO" : "DESACTIVADO"}',
                  ),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
```

### 3️⃣ **Desde un Comando FCM (Remoto)**

En `FcmPushReceiver.kt`, agregar nuevo comando:

```kotlin
"toggle_gps_debug" -> {
    val enable = data["enable"]?.toBoolean() ?: false
    
    // Activar debug mode via MethodChannel
    val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "background_service")
    channel.invokeMethod("setGpsDebugMode", mapOf("enable" to enable))
    
    Log.d("FCM", "🐞 GPS Debug mode: $enable")
}
```

Y en `main.dart`, agregar handler:

```dart
case "setGpsDebugMode":
  final enable = call.arguments['enable'] as bool;
  GpsServiceManager.setDebugMode(enable);
  result.success(null);
  break;
```

---

## 📝 Logs Disponibles

Cuando **Debug Mode está ACTIVADO**, verás estos logs:

### ✅ **Inicio Exitoso**
```
[GPS_SERVICE_MANAGER] 📥 Solicitud de inicio recibida (source: manual, force: false)
[GPS_SERVICE_MANAGER] 🔍 Estado del servicio GPS: DETENIDO
[GPS_SERVICE_MANAGER] ✅ Inicio GPS PERMITIDO (source: manual)
[GPS_SERVICE_MANAGER] 💾 Métricas guardadas: manual=1, total=15
```

### ⏭️ **Inicio Bloqueado (Ya Corriendo)**
```
[GPS_SERVICE_MANAGER] 📥 Solicitud de inicio recibida (source: workmanager, force: false)
[GPS_SERVICE_MANAGER] 🔍 Estado del servicio GPS: CORRIENDO
[GPS_SERVICE_MANAGER] ⏭️ Servicio GPS ya está corriendo - Inicio omitido (source: workmanager)
```

### ⏱️ **Rate Limiting Activo**
```
[GPS_SERVICE_MANAGER] 📥 Solicitud de inicio recibida (source: fcm_push, force: false)
[GPS_SERVICE_MANAGER] ⏱️ Rate limit activo - Último inicio hace 2s
[GPS_SERVICE_MANAGER] ⏭️ Esperar 3s más (source: fcm_push)
```

### 🚨 **Circuit Breaker Abierto**
```
[GPS_SERVICE_MANAGER] 📥 Solicitud de inicio recibida (source: alarm_manager, force: false)
[GPS_SERVICE_MANAGER] 🚨 CIRCUIT BREAKER ABIERTO - Pausado por 4 min más
[GPS_SERVICE_MANAGER] ℹ️ Razón: Detectado loop infinito (10 inicios en 2 min)
```

### 🛑 **Force GPS (Deteniendo Duplicados)**
```
[GPS_SERVICE_MANAGER] 📥 Solicitud de inicio recibida (source: fcm_force, force: true)
[GPS_SERVICE_MANAGER] 🛑 Modo FORCE activado - Deteniendo todos los procesos GPS duplicados
[GPS_SERVICE_MANAGER] 🛑 Deteniendo TODOS los procesos GPS activos...
MainActivity         🛑 forceStopGpsService - Deteniendo TODOS los procesos GPS
MainActivity         ✅ forceStopGpsService completado - Servicio corriendo: false
[GPS_SERVICE_MANAGER] ✅ Procesos GPS detenidos exitosamente
[GPS_SERVICE_MANAGER] ✅ Procesos duplicados eliminados - Preparado para inicio limpio
[GPS_SERVICE_MANAGER] 🔍 Estado del servicio GPS: DETENIDO
[GPS_SERVICE_MANAGER] ✅ Inicio GPS PERMITIDO (source: fcm_force)
```

---

## 🔍 Filtrar Logs en PowerShell

### 1️⃣ **Ver SOLO logs del GPS Service Manager**

```powershell
adb logcat | Select-String "GPS_SERVICE_MANAGER"
```

### 2️⃣ **Ver logs del GPS Service Manager + MainActivity**

```powershell
adb logcat | Select-String "GPS_SERVICE_MANAGER|MainActivity.*GPS"
```

### 3️⃣ **Ver SOLO eventos de Circuit Breaker**

```powershell
adb logcat | Select-String "GPS_SERVICE_MANAGER.*CIRCUIT BREAKER"
```

### 4️⃣ **Ver Force GPS en acción**

```powershell
adb logcat | Select-String "GPS_SERVICE_MANAGER.*FORCE|forceStopGpsService"
```

### 5️⃣ **Contar inicios GPS en tiempo real**

```powershell
adb logcat | Select-String "GPS_SERVICE_MANAGER.*PERMITIDO" | Measure-Object -Line
```

---

## 📊 Monitorear Circuit Breaker

### Obtener Estadísticas del Circuit Breaker

```dart
// En cualquier parte de tu código Dart
final stats = await GpsServiceManager.getStatistics();

print('🔴 Circuit breaker abierto: ${stats['circuit_breaker_open']}');
print('📊 Inicios en ventana actual: ${stats['starts_in_current_window']}');
print('🚨 Total eventos circuit breaker: ${stats['circuit_breaker_events']}');
print('📈 Total inicios GPS: ${stats['total_starts']}');
print('⏰ Último inicio: ${stats['last_start_time']}');
print('🏷️ Última fuente: ${stats['last_start_source']}');
```

### Widget de Monitoreo en Tiempo Real

```dart
import 'package:flutter/material.dart';
import 'dart:async';
import '../services/gps_service_manager.dart';

class GpsMonitorWidget extends StatefulWidget {
  @override
  _GpsMonitorWidgetState createState() => _GpsMonitorWidgetState();
}

class _GpsMonitorWidgetState extends State<GpsMonitorWidget> {
  Timer? _timer;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
    _timer = Timer.periodic(Duration(seconds: 2), (_) => _loadStats());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final stats = await GpsServiceManager.getStatistics();
    setState(() {
      _stats = stats;
    });
  }

  @override
  Widget build(BuildContext context) {
    final circuitBreakerOpen = _stats['circuit_breaker_open'] ?? false;
    final startsInWindow = _stats['starts_in_current_window'] ?? 0;
    final totalStarts = _stats['total_starts'] ?? 0;

    return Card(
      color: circuitBreakerOpen ? Colors.red[100] : Colors.green[100],
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'GPS Service Manager',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('🔴 Circuit Breaker: ${circuitBreakerOpen ? "ABIERTO" : "Cerrado"}'),
            Text('📊 Inicios (ventana 2min): $startsInWindow / 10'),
            Text('📈 Total inicios: $totalStarts'),
            Text('⏰ Último: ${_stats['last_start_time'] ?? "N/A"}'),
            Text('🏷️ Fuente: ${_stats['last_start_source'] ?? "N/A"}'),
          ],
        ),
      ),
    );
  }
}
```

---

## 🛑 Logs del Force GPS

### Secuencia Completa de Force GPS

```
// 1. FCM recibe comando force_gps_execution
FcmPushReceiver      📱 [FCM] Mensaje data recibido: {action=force_gps_execution}

// 2. GPS Service Manager procesa la solicitud
[GPS_SERVICE_MANAGER] 📥 Solicitud de inicio recibida (source: fcm_force, force: true)

// 3. Detiene TODOS los procesos GPS activos
[GPS_SERVICE_MANAGER] 🛑 Modo FORCE activado - Deteniendo todos los procesos GPS duplicados
[GPS_SERVICE_MANAGER] 🛑 Deteniendo TODOS los procesos GPS activos...

// 4. MainActivity ejecuta stopService nativo
MainActivity         🛑 forceStopGpsService - Deteniendo TODOS los procesos GPS
MainActivity         ✅ forceStopGpsService completado - Servicio corriendo: false

// 5. GPS Service Manager confirma detención
[GPS_SERVICE_MANAGER] ✅ Procesos GPS detenidos exitosamente
[GPS_SERVICE_MANAGER] ✅ Procesos duplicados eliminados - Preparado para inicio limpio

// 6. Verifica estado del servicio
[GPS_SERVICE_MANAGER] 🔍 Estado del servicio GPS: DETENIDO

// 7. Permite el inicio limpio
[GPS_SERVICE_MANAGER] ✅ Inicio GPS PERMITIDO (source: fcm_force)
[GPS_SERVICE_MANAGER] 💾 Métricas guardadas: fcm_force=1, total=16

// 8. Inicia el servicio GPS limpio (sin duplicados)
ForegroundLocationService ✅ Servicio GPS iniciado correctamente
```

### Detectar Duplicados Eliminados

Si ves este patrón en los logs:

```
MainActivity         ⚠️ Servicio GPS aún corriendo después de stopService()
```

Significa que había un proceso duplicado "zombie" que no se detuvo con `stopService()` normal. El force GPS envía un broadcast adicional para matarlo.

---

## 🔧 Testing Manual del Sistema

### Test 1: Verificar Debug Mode

```dart
// Activa debug mode
GpsServiceManager.setDebugMode(true);

// Intenta iniciar GPS manualmente
final canStart = await GpsServiceManager.requestGpsStart(source: 'test');

// Deberías ver logs detallados en consola
```

### Test 2: Simular Death Loop

```dart
// Hacer 15 inicios rápidos para activar circuit breaker
for (int i = 0; i < 15; i++) {
  await GpsServiceManager.requestGpsStart(source: 'test_loop');
  await Future.delayed(Duration(milliseconds: 100));
}

// Verificar si circuit breaker se abrió
final stats = await GpsServiceManager.getStatistics();
print('Circuit breaker abierto: ${stats['circuit_breaker_open']}');
```

### Test 3: Force GPS Mata Duplicados

```dart
// Simular inicio duplicado
await platform.invokeMethod('startLocationService', {...});
await Future.delayed(Duration(milliseconds: 100));
await platform.invokeMethod('startLocationService', {...}); // Duplicado

// Verificar estado
var isRunning = await GpsServiceManager.isGpsServiceRunning();
print('GPS corriendo (con duplicado): $isRunning'); // true

// Hacer force GPS
final canForce = await GpsServiceManager.requestGpsStart(
  source: 'test_force',
  force: true,
);

// Verificar que mató duplicados
await Future.delayed(Duration(seconds: 2));
isRunning = await GpsServiceManager.isGpsServiceRunning();
print('GPS corriendo (después de force): $isRunning'); // false o un solo proceso
```

---

## 📋 Checklist de Debugging

- [ ] Debug mode activado en `main.dart`
- [ ] Logs visibles en `adb logcat`
- [ ] Force GPS detiene duplicados correctamente
- [ ] Circuit breaker se abre cuando hay loops
- [ ] Rate limiting funciona (5 seg mínimo entre starts)
- [ ] Estadísticas accesibles vía `getStatistics()`
- [ ] Widget de monitoreo implementado (opcional)

---

## 🚨 Problemas Comunes

### Problema: No veo logs del GPS Service Manager

**Solución:**
```dart
// Verificar que debug mode está activado
GpsServiceManager.setDebugMode(true);

// Verificar tag en logcat
adb logcat | Select-String "GPS_SERVICE_MANAGER"
```

### Problema: Force GPS no detiene duplicados

**Solución:**
1. Verificar que el método nativo `forceStopGpsService` está implementado en `MainActivity.kt`
2. Verificar logs nativos:
   ```powershell
   adb logcat | Select-String "forceStopGpsService"
   ```
3. Si persiste, verificar permisos del servicio en `AndroidManifest.xml`

### Problema: Circuit breaker no se activa

**Solución:**
1. Verificar configuración en `gps_service_manager.dart`:
   - `_maxStartsInWindow = 10`
   - `_circuitBreakerWindow = Duration(minutes: 2)`
2. Hacer test manual con 15 inicios rápidos
3. Verificar estadísticas:
   ```dart
   final stats = await GpsServiceManager.getStatistics();
   print(stats);
   ```

---

## 📞 Soporte

Si después de seguir esta guía sigues teniendo problemas con el GPS Service Manager, proporciona:

1. Logs de `adb logcat | Select-String "GPS_SERVICE_MANAGER"`
2. Logs de `adb logcat | Select-String "forceStopGpsService"`
3. Estadísticas del sistema: `GpsServiceManager.getStatistics()`
4. Descripción del problema específico
