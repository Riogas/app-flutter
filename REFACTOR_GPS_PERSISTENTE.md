# Refactor GPS Persistente

Documento de release del refactor de tracking GPS ejecutado en la rama `refactor/gps-persistente` (14 tasks, SDD en `.superpowers/sdd/`). Reemplaza el modelo viejo de 8 mecanismos de "resurrección" (AlarmManager + watchdogs + warm-up polling + LogRocket/grabación de pantalla) por un único Foreground Service persistente con cola local y reportes de eventos al backend.

## 1. Resumen del modelo nuevo

**Antes**: `ForegroundLocationService` + `LocationReceiver` reprogramado vía `AlarmManager` + `ServiceWatchdog` (Thread + `restartGPSService`) + `CriticalLogAlarmReceiver` (`setRepeating` 30 s) + `LocationWorker` (WorkManager) + warm-up de 7 fixes con `Thread.sleep` + colecciones estáticas compartidas + LogRocket/grabación de pantalla remota. Ocho caminos distintos podían (re)arrancar o matar el GPS, sin dueño único.

**Ahora**: un solo Foreground Service persistente, `LocationTrackingService` (`android/app/src/main/kotlin/com/riogas/appmovil/tracking/LocationTrackingService.kt`), con estado 100% en la instancia (sin colecciones estáticas compartidas):

- **Fix continuo**: `FusedLocationProviderClient.requestLocationUpdates` con intervalo configurable (`tracking_interval_seconds`, default 12 s). Cada fix se inserta en una cola local Room (`tracking.db`, `LocationFixEntity`) con UTM, altitud, bearing, velocidad, `isMockLocation`, etc.
- **Flush a Track**: cada **30 s** (`TrackingDatabase` → `LocationBatchUploader.flushTrack`).
- **Flush a RioGas**: cada **3 min** (`LocationBatchUploader.flushRioGas`), seguido de purga de filas ya enviadas (24 h) y retención dura de 7 días (cubre el caso `gpsN8nEnabled=false`, donde `sentTrack` nunca se marca).
- **Auto-monitoreo interno**: cada 30 s chequea si pasaron >90 s sin fix (`heartbeat_no_gps`) y re-registra el callback (`tracking_reregistered` si tuvo éxito).
- **Arranque único**: `LocationTrackingService.start(context, movil, escenario, usuario, deviceId)` — idempotente (Android reutiliza la instancia si ya corre; `onStartCommand` re-registra sin duplicar). Llamado desde `MainActivity` (foreground), FCM `restart_tracking` (con exención de alta prioridad) y `HealthCheckWorker` (si el dispositivo está exento de optimización de batería).
- **Comandos FCM unificados** (`FcmPushReceiver`): `restart_tracking`/`stop_tracking`, con aliases legacy `restart_gps_service`, `force_gps_execution` → restart, y `stop_gps_service` → stop. Sin `Thread.sleep` en el hilo FCM.
- **HealthCheckWorker** (WorkManager, cada **15 min**, NO fuente de GPS): si el service no está corriendo, intenta revivirlo (si hay exención de batería) o reporta `health_fgs_dead` con el motivo; si el permiso de ubicación se perdió, reporta `permission_revoked`.
- **Boot ping**: `BootReceiver` → `BootPingWorker` (expedited WorkManager) reporta `booted` en segundos y re-agenda el `HealthCheckWorker`. **No** arranca el FGS directo desde `BOOT_COMPLETED` (evita `ForegroundServiceStartNotAllowedException` en Android 12+); el backend decide si manda `restart_tracking`.
- **GPS off/on como eventos de primera clase**: `GPSStatusReceiver` reporta `gps_off`/`gps_on` en segundos (dispara por `PROVIDERS_CHANGED`) y muestra/cancela una notificación visible al repartidor cuando el GPS está apagado.
- **Permisos**: `whileInUse` es válido para operaciones puntuales en foreground (login, fix de estado); solo el tracking continuo en background exige `always` — su ausencia la reporta `HealthCheckWorker`/`PermissionChangeReceiver` como `permission_revoked`.
- **Catálogos SubEstado**: los 3 listeners Firestore de 24 h se reemplazaron por `get()` puntual + cache Hive con TTL de 24 h (`catalogCacheBox`), sirviendo la cache al instante y refrescando en background si venció.
- **LogRocket y grabación de pantalla remota** (`toggle_screen_recording`/`grabarPantalla`) fueron eliminados por privacidad (Ley 18.331).

## 2. Eventos de dispositivo (§8.6) y su transporte transitorio

Todos los eventos se reportan vía `DeviceEventReporter.report(context, tipo, motivo, extra)` (`android/app/src/main/kotlin/com/riogas/appmovil/DeviceEventReporter.kt`), que hace `POST` al endpoint existente **`RegistrarErrores`**, con el tipo de evento viajando **dentro del campo `data`** (`data.tipo`), no como endpoint dedicado. Es un transporte transitorio: cuando GeneXus publique `RegistrarEventoDispositivo`, basta con cambiar la constante `ENDPOINT`.

Payload actual:
```json
{
  "token": "IcA.FwL.1710.!",
  "movil": 123,
  "DeviceId": "...",
  "usuario": "...",
  "data": "{\"tipo\":\"gps_off\",\"motivo\":\"PROVIDERS_CHANGED\",\"ts\":...,\"origen\":\"device_event\", ...extra}"
}
```

| Evento | Disparador | Motivos (`motivo`) observados | Emitido desde |
|---|---|---|---|
| `gps_off` | Proveedor de ubicación pasa a OFF | `PROVIDERS_CHANGED` | `GPSStatusReceiver` |
| `gps_on` | Proveedor de ubicación pasa a ON | `PROVIDERS_CHANGED` | `GPSStatusReceiver` |
| `permission_revoked` | Permiso de ubicación revocado | nombre del permiso detectado; `HEALTH_CHECK` | `PermissionChangeReceiver`, `HealthCheckWorker` |
| `heartbeat_no_gps` | >90 s sin fix nuevo, o registro de updates falló | `NO_PERMISSION`, `GPS_DISABLED_IN_SETTINGS`, `NO_SIGNAL`, `FGS_TIMEOUT_A15` | `LocationTrackingService` (watchJob, `registerLocationUpdates`, `onTimeout`) |
| `booted` | Dispositivo reiniciado con sesión activa | `BOOT_COMPLETED` | `BootPingWorker` |
| `health_fgs_dead` | HealthCheck detecta el FGS caído, o `onCreate` no pudo pasar a foreground | `RESTARTED_BY_HEALTH_CHECK`, `NO_BATTERY_EXEMPTION`, `FGS_START_NOT_ALLOWED`/excepción, `FGS_START_DENIED` | `HealthCheckWorker`, `LocationTrackingService.onCreate` |
| `restart_result` | Resultado de un comando FCM `restart_tracking`/`stop_tracking` | `OK`, `FAILED`, `STOPPED`, `NO_SESSION` | `FcmPushReceiver` |
| `tracking_reregistered` | Re-registro exitoso de `requestLocationUpdates` tras silencio | motivo heredado del `heartbeat_no_gps` que lo disparó | `LocationTrackingService` (watchJob) |

## 3. Pendientes de backend

1. **Endpoint `RegistrarEventoDispositivo` dedicado**: hoy los 8 eventos de §8.6 viajan disfrazados dentro de `RegistrarErrores` (campo `tipo` en `data`). Falta que GeneXus publique un endpoint propio para no mezclar eventos operativos con errores reales, y para poder tipar el campo `tipo` en la tabla destino.
2. **Detección server-side de silencio**: el cliente ya reporta `heartbeat_no_gps`/`health_fgs_dead`, pero nadie del lado servidor dispara automáticamente `restart_tracking` cuando un móvil deja de mandar fixes por X minutos. Falta un job/cron que lea los últimos eventos por móvil y mande el push de restart.
3. **Dedup de coordenadas (opcional)**: la cola Room no dedupea fixes idénticos consecutivos (mismo lat/long) antes de subir a Track/RioGas; queda como optimización de banda ancha/almacenamiento a evaluar, no bloqueante.

## 4. Matriz de pruebas manuales en dispositivo

| # | Escenario | Pasos | Resultado esperado |
|---|---|---|---|
| 1 | GPS off < 30 s | Con la app en tracking activo, apagar la ubicación del dispositivo | Notificación "Ubicación desactivada" visible en <30 s; backend recibe `gps_off` (`RegistrarErrores`, `data.tipo=gps_off`) |
| 2 | GPS on tras off | Re-activar la ubicación | Notificación se cancela; backend recibe `gps_on` |
| 3 | Matar proceso + push restart | Forzar cierre de la app desde Ajustes → Apps (o swipe + "no mantener actividades"); enviar FCM `restart_tracking` desde el backend/panel | El FGS vuelve a arrancar (exención de FCM alta prioridad); backend recibe `restart_result=OK` |
| 4 | Dos `restart_tracking` seguidos | Enviar el push dos veces consecutivas | No se duplica el servicio ni los loops (idempotencia: `onStartCommand` re-registra callback y cancela jobs previos antes de re-crear) |
| 5 | Reboot con sesión activa | Reiniciar el dispositivo con sesión logueada | En segundos, backend recibe `booted`; `HealthCheckWorker` queda re-agendado; **no** arranca el FGS solo por el boot (esperar `restart_tracking` del backend o que la app se abra) |
| 6 | Permiso `whileInUse` en login | Setear el permiso de ubicación a "mientras se usa la app" (no "todo el tiempo"), abrir la app y loguear | El login entra y el chequeo de estado puntual (fix de ubicación en foreground) funciona; el tracking en background eventualmente reporta `permission_revoked`/`heartbeat_no_gps=NO_PERMISSION` cuando la app pasa a background |
| 7 | Update de app | Instalar una nueva versión (APK) sobre la sesión activa existente | Tras el update, el `HealthCheckWorker` o el próximo `restart_tracking` reviven el tracking sin intervención manual; no quedan servicios/alarmas huérfanos del build anterior |
| 8 | Batería: consumo GPS continuo | Dejar el móvil trackeando 2+ horas en el modelo nuevo vs. una sesión equivalente del modelo viejo (build anterior a este refactor) | Consumo de batería igual o menor: se eliminó el warm-up de 7 fixes por ciclo, el polling con `Thread.sleep`, el `AlarmManager` de reprogramación constante y el `CriticalLogAlarmReceiver` de 30 s (ahora 15 min vía `CriticalLogUploadWorker`) |

## 5. Deferred conocidos (avisar a operaciones)

- **`distanciaRecorrida` / `movementType` / `executionCounter` quedan en 0/DESCONOCIDO**: el acumulador legado de estas columnas dependía de filtrado cross-fix (warm-up + estado compartido) que no se replicó en el modelo nuevo. `LocationFixEntity` las persiste con default. Task futuro si se necesitan.
- **`onTimeout(startId: Int)` de Android 15**: la firma usada compila contra `compileSdk=35`; su semántica real para FGS de tipo `location` de larga duración no está 100% validada en campo (puede que el sistema nunca la dispare para este tipo de servicio en la práctica). Código inofensivo si no se invoca.
- **`force_gps_execution` pierde su semántica de emergencia**: antes era un comando "kill sin restart" (G4) manejado en Dart; ahora es simplemente un alias de `restart_tracking` manejado 100% del lado nativo. Avisar a operaciones/soporte que ya no existe un modo de "matar el GPS sin reiniciarlo" vía ese comando — usar `stop_tracking` para eso.
- **`get_status` no incluye `LocationTrackingService.isRunning`**: pendiente de un ajuste menor si operaciones lo necesita para diagnóstico remoto.

## 6. Verificación de ACs (sweep final)

Ejecutado sobre el HEAD de `refactor/gps-persistente` antes del commit de este documento:

- `logrocket` (case-insensitive) en `lib/` y `android/app/src/main/`: **0 matches**.
- `toggle_screen_recording` / `grabarPantalla` en `lib/**/*.dart`: **0 matches**.
- `startForegroundService` en `android/app/src/main/kotlin/**/*.kt`: **1 match**, en `LocationTrackingService.kt` (companion `start`). Los handlers de FCM (`FcmPushReceiver`) y el health-check (`HealthCheckWorker`) delegan en `LocationTrackingService.start`, no llaman `startForegroundService` directo.
- `Thread\.sleep` en `android/app/src/main/kotlin/**/*.kt`: **0 usos reales** (solo 3 comentarios que documentan su ausencia, en `LocationBatchUploader.kt` y `LocationHelper.kt`).
- `AlarmManager` en `android/app/src/main/kotlin/**/*.kt`: **0 usos reales** (solo 3 comentarios residuales que documentan su retiro, en `LocationHelper.kt`, `MainActivity.kt` y `FcmPushReceiver.kt`). No hay `AlarmManager` activo en ningún dominio de la app.
- `MY_PACKAGE_RESTARTED|USE_EXACT_ALARM|SCHEDULE_EXACT_ALARM|QUERY_ALL_PACKAGES|LOGROCKET` en `AndroidManifest.xml`: **0 matches**.
- `last_interval` en `android/app/src/main/kotlin/**/*.kt`: **0 matches**.
- `"service_disabled"|"service_paused"|"watchdog_disabled"` fuera de `ServiceStatusFlags.kt`: **0 matches** (todas las apariciones están confinadas a ese archivo).
- `getSubEstado.*Stream` en `lib/**/*.dart`: **0 matches**.
- `flutter analyze`: **172 issues, 0 errores** (baseline exacto de Task 1).
- `flutter build apk --debug`: **BUILD SUCCESSFUL**.

Detalle completo del sweep (comandos y output real): `.superpowers/sdd/task-14-report.md`.
