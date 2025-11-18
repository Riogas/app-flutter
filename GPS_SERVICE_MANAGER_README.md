# 🛡️ GPS Service Manager - Sistema Anti Death Loop

## 📋 Resumen

**Archivos creados:**
1. ✅ `lib/services/gps_service_manager.dart` - Manager centralizado
2. ✅ Método nativo `isGpsServiceRunning()` en MainActivity.kt

**Características implementadas:**
- ✅ Verificación de estado del servicio antes de iniciar
- ✅ Rate limiting (5 seg mínimo entre inicios)
- ✅ Circuit breaker (10 inicios en 2 min → pausa 5 min)
- ✅ Métricas por fuente (workmanager, fcm, manual)
- ✅ Soporte para force GPS (comandos remotos)

---

## 🚀 Uso Básico

```dart
import 'services/gps_service_manager.dart';

// Solicitar inicio del GPS
final canStart = await GpsServiceManager.requestGpsStart(
  source: 'fcm_push',  // O 'workmanager', 'manual', etc.
  force: false,         // true solo para force_gps_execution
);

if (canStart) {
  // ✅ Iniciar servicio
  await platform.invokeMethod('startLocationService', {...});
} else {
  // ❌ Bloqueado (ya corriendo, rate limited, o circuit breaker)
  print('Inicio bloqueado');
}
```

---

## 📊 Ver Estadísticas

```dart
final stats = await GpsServiceManager.getStatistics();
print(stats);
// Output:
// {
//   "is_running": true,
//   "last_start_time": "2025-11-17T11:21:31Z",
//   "circuit_breaker_open": false,
//   "starts_in_current_window": 3,
//   "total_starts": 47
// }
```

---

## ⚙️ Configuración

**Ajustar límites en `gps_service_manager.dart`:**
```dart
static const Duration _minTimeBetweenStarts = Duration(seconds: 5);
static const Duration _circuitBreakerWindow = Duration(minutes: 2);
static const int _maxStartsInWindow = 10;
static const Duration _circuitBreakerCooldown = Duration(minutes: 5);
```

---

## ✅ Próximos Pasos

**FASE 2 - Integración (PENDIENTE):**
1. Modificar LocationHelper.dart
2. Modificar FcmPushReceiver.kt
3. Modificar WorkManager/AlarmManager
4. Testing en Xiaomi Android 15

Ver documentación completa en: `FIX_GPS_SERVICE_DEATH_LOOP_FULL.md`
