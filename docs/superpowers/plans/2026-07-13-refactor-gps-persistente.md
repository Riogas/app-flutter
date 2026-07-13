# Refactor GPS Persistente + Limpieza MoveIT — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reemplazar los 8 mecanismos de resurrección GPS por un único Foreground Service persistente con cola durable, eliminar LogRocket/grabación de pantalla y código muerto, agregar eventos de dispositivo de primera clase y cachear catálogos Firestore.

**Architecture:** Un solo FGS (`LocationTrackingService`, package `com.riogas.appmovil`) con `requestLocationUpdates` continuo alimenta una cola Room; flush por lote a track (30 s) y RioGas (3 min) con at-least-once. Los eventos de dispositivo (gps_off, permisos, boot, heartbeats) se reportan al endpoint existente `RegistrarErrores` vía `DeviceEventReporter` (cuando GeneXus publique `RegistrarEventoDispositivo` se cambia 1 constante). Resurrección solo por FCM high-priority (`restart_tracking`) + health-check WorkManager 15 min.

**Tech Stack:** Flutter/Dart (geolocator, Hive, cloud_firestore), Kotlin (FusedLocationProviderClient, Room 2.6.1, WorkManager 2.9.0, OkHttp, coroutines).

## Global Constraints

- Branch de trabajo: `refactor/gps-persistente`. Commit (y push) al final de CADA task. Mensajes de commit terminan con `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Directorio raíz del repo: `C:\Users\jgomez\Documents\Projects\AppTFlutter\appmovil`. Paths del plan relativos a esa raíz. Plataforma Windows (PowerShell); gradle se invoca como `cd android; .\gradlew.bat assembleDebug` o vía `flutter build apk --debug`.
- **Gate de verificación por task** (el repo no tiene infra de tests utilizable — hay 1 solo test que toca Firebase real): `flutter analyze` sin errores NUEVOS (hay warnings preexistentes; anotar el baseline en Task 1) y, para tasks que tocan Kotlin, `flutter build apk --debug` exitoso. Más los greps de AC de cada task.
- NO tocar el backend GeneXus. Endpoints disponibles: `RegistrarErrores`, `RegistrarCoordenadasV2`, `RegistrarSesion`, `RegistrarCierre`, `FCMActions`. Token compartido hardcodeado: `IcA.FwL.1710.!` (mismo esquema que ya usa `LocationHelper.kt:427,1601,2419` — NO cambiar el esquema de auth en este refactor).
- Base URL nativa: SharedPreferences `FlutterSharedPreferences`, key `flutter.baseUrl`, default `https://www.riogas.uy/ica_geos_/appservices/`, normalizando `/appservices/` como hace `LocationHelper.kt:400-410`.
- Track endpoint: `https://track.riogas.com.uy/api/import/gps` (formato actual en `LocationHelper.kt:2379-2509` — copiar tal cual el armado del body).
- Código nativo NUEVO va en package `com.riogas.appmovil` (path `android/app/src/main/kotlin/com/riogas/appmovil/`). El applicationId/namespace sigue siendo `com.example.moveit` — no cambiarlo.
- Strings de UI en español. No introducir i18n.
- Flags de servicio: prefs `"config"`. Dueño único tras Task 3: `ServiceStatusFlags.kt`.
- El sistema Dart `LocationService` + `flutter_background` (GPSMapa) queda FUERA de alcance — no tocarlo salvo lo indicado explícitamente.
- YAGNI: no agregar features no pedidas; DRY: mover código existente en vez de duplicar (armado de bodies HTTP).

---

### Task 1: A.8 — Eliminar LogRocket y grabación de pantalla

**Files:**
- Modify: `pubspec.yaml:60` (quitar `logrocket_flutter: ^1.57.5`)
- Delete: `lib/services/screen_recording_manager.dart`
- Modify: `lib/main.dart` (líneas 44, 243-246, 366-368, 476-477, 575-592, 1970)
- Modify: `lib/services/debug_config_manager.dart` (líneas ~118-120, ~165)
- Modify: `android/app/src/main/AndroidManifest.xml:67-70` (meta-data LOGROCKET_APP_ID)
- Modify: `android/app/build.gradle` (comentarios L90-91 sobre logrocket; si `minSdk 25` tiene comentario "por LogRocket", limpiar el comentario, NO subir minSdk)

**Interfaces:**
- Produces: la app compila sin ninguna referencia a logrocket; el comando FCM `toggle_screen_recording` deja de existir.

- [ ] **Step 1: Registrar baseline de `flutter analyze`**

Run: `flutter analyze 2>&1 | Select-Object -Last 3`
Anotar la cantidad de issues preexistentes (se usa como baseline en todos los tasks).

- [ ] **Step 2: Quitar la dependencia y el archivo**

1. En `pubspec.yaml` borrar la línea `logrocket_flutter: ^1.57.5` (L60).
2. Borrar `lib/services/screen_recording_manager.dart` completo.

- [ ] **Step 3: Limpiar main.dart**

1. Borrar `import 'package:logrocket_flutter/logrocket_flutter.dart';` (L44) y cualquier `import ... screen_recording_manager.dart`.
2. Borrar el bloque comentado de `LogRocket.wrapAndInitialize` (L243-246 y cierres L476-477) y el comentario L366-368 sobre init automático.
3. Borrar el handler FCM completo de `toggle_screen_recording` (L575-592) dentro de `FirebaseMessaging.onMessage.listen`.
4. En el `build()` (L1970): reemplazar `LogRocketWidget(child: X)` por `X` directamente (des-envolver, conservando el child intacto).

- [ ] **Step 4: Limpiar debug_config_manager.dart**

Borrar la lectura de `data['grabarPantalla']` (L118-120), la persistencia de `grabarPantallaEnabled` en Hive (L165) y cualquier referencia restante a grabación de pantalla en ese archivo. El resto del listener de `Moviles-1000` (debug logs) queda intacto.

- [ ] **Step 5: Limpiar manifest y gradle**

1. En `AndroidManifest.xml` borrar el meta-data completo `com.logrocket.LOGROCKET_APP_ID` (L67-70).
2. En `android/app/build.gradle` borrar los comentarios sobre logrocket (L90-91) y el comentario de minSdk si menciona LogRocket (mantener `minSdk 25`).

- [ ] **Step 6: Regenerar y verificar AC**

Run:
```powershell
flutter pub get
Select-String -Path (Get-ChildItem -Recurse -File -Exclude *.lock | Where-Object { $_.FullName -notmatch '\\(build|\.dart_tool|\.git|\.idea)\\' }).FullName -Pattern 'logrocket' -SimpleMatch
```
Expected: sin matches (fuera de `build/`, `.dart_tool/`, `.git/`). También: `Select-String -Path lib\main.dart -Pattern 'toggle_screen_recording'` → sin matches.

Run: `flutter analyze` → sin errores nuevos vs baseline. Run: `flutter build apk --debug` → BUILD SUCCESSFUL.

- [ ] **Step 7: Commit**

```powershell
git add -A -- . ":(exclude).dart_tool"; git commit -m "A.8: eliminar LogRocket y grabacion de pantalla (privacidad Ley 18.331)"; git push
```

---

### Task 2: E.2 — Borrar código muerto

**Files:**
- Delete: `lib/pages/home_page_old.dart`, `lib/services/firebase_service.dart.backup`, `lib/services/session_service_bkp.dart`, `lib/services/stream_manager.dart`, `lib/pages/completed_orders.dart`, `lib/widgets/stream_manager_monitor.dart`, `lib/services/gps_service_manager_examples.dart`, `lib/services/background_services.dart`, `lib/pages/pending_orders_debug.dart`, `lib/widgets/debug_access_widget.dart`, `lib/services/pending_orders_diagnostic.dart`
- Delete: `android/app/src/main/kotlin/com/example/moveit/FirebaseMessagingService.kt` (FMS muerto, no registrado en manifest, solo loguea)
- Modify: `lib/pages/home_page.dart` (quitar imports L4 comentado, L5 `completed_orders.dart`, L32 si no se usa, y el uso comentado L101)
- Modify: `lib/pages/pending_orders.dart:5` (quitar import huérfano de `pending_orders_diagnostic.dart`)
- Modify: `lib/pages/login_page.dart` — NO tocar su import de `utils/stream_manager.dart` (ESE ES EL VIVO)

**Interfaces:**
- Consumes: nada.
- Produces: árbol sin duplicados. **`lib/utils/stream_manager.dart` se CONSERVA** (usado por `login_page.dart:683` → `cancelAllStreams()`).

- [ ] **Step 1: Verificar que nada activo importa los archivos a borrar**

Run (por cada archivo, ejemplo):
```powershell
Select-String -Path lib\**\*.dart -Pattern "home_page_old|session_service_bkp|stream_manager_monitor|gps_service_manager_examples|background_services|pending_orders_debug|debug_access_widget|pending_orders_diagnostic|completed_orders|services/stream_manager"
```
Expected: solo matches dentro de los propios archivos a borrar, en imports comentados, o en los imports que este task elimina. Si aparece un consumidor ACTIVO no listado, DETENERSE y reportar en vez de borrar.

- [ ] **Step 2: Borrar los 12 archivos listados**

`Remove-Item` de cada uno. Cuidado con la distinción: se borra `lib/services/stream_manager.dart` (clase legacy) y se CONSERVA `lib/utils/stream_manager.dart` (funciones top-level vivas).

- [ ] **Step 3: Limpiar imports rotos**

1. `lib/pages/home_page.dart`: quitar import de `completed_orders.dart` (L5), el import comentado L4, y el uso comentado `CompletedOrdersPage()` (L101). Si el import de `utils/stream_manager.dart` (L32) no tiene usos en el archivo, quitarlo también.
2. `lib/pages/pending_orders.dart`: quitar import L5 de `pending_orders_diagnostic.dart`.
3. `lib/widgets/native_log_debug_page.dart`: verificar si quedó huérfano (solo lo importaba `debug_access_widget.dart`); si nadie más lo importa, borrarlo también.

- [ ] **Step 4: Verificar y commit**

Run: `flutter analyze` → sin errores nuevos. Run: `flutter build apk --debug` → BUILD SUCCESSFUL.

```powershell
git add -A -- . ":(exclude).dart_tool"; git commit -m "E.2: borrar codigo muerto (11 archivos Dart + FMS Kotlin muerto)"; git push
```

---

### Task 3: B.7 — Dueño único de flags + limpieza de manifest

**Files:**
- Modify: `android/app/src/main/kotlin/com/riogas/appmovil/ServiceStatusFlags.kt`
- Modify (reemplazar escrituras directas de prefs por llamadas a ServiceStatusFlags): `LocationReceiver.kt:24,69,83`, `ForegroundLocationService.kt:123,145,161,488`, `LocationHelper.kt:631,635,2137`, `ServiceWatchdog.kt:112,366,372`, `BootReceiver.kt:46`, `WorkManagerHelper.kt:158`, `MainActivity.kt`, `FcmPushReceiver.kt:934`
- Modify: `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Produces (API que usan Tasks 5-11):
```kotlin
object ServiceStatusFlags {
    fun isServiceDisabled(context: Context): Boolean
    fun setServiceDisabled(context: Context, disabled: Boolean, reason: String)
    fun isServicePaused(context: Context): Boolean
    fun setServicePaused(context: Context, paused: Boolean, reason: String)
    fun isWatchdogDisabled(context: Context): Boolean
    fun setWatchdogDisabled(context: Context, disabled: Boolean, reason: String)
    // ... los métodos existentes (setServicesNeedRestart, updateGpsServiceStatus, etc.) se conservan
}
```

- [ ] **Step 1: Agregar accessors atómicos en ServiceStatusFlags.kt**

Agregar al object existente (prefs `"config"` ya definido como `PREFS_NAME`):

```kotlin
private const val KEY_SERVICE_DISABLED = "service_disabled"
private const val KEY_SERVICE_PAUSED = "service_paused"
private const val KEY_WATCHDOG_DISABLED = "watchdog_disabled"

@Synchronized
fun isServiceDisabled(context: Context): Boolean =
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getBoolean(KEY_SERVICE_DISABLED, false)

@Synchronized
fun setServiceDisabled(context: Context, disabled: Boolean, reason: String) {
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
        .putBoolean(KEY_SERVICE_DISABLED, disabled)
        .putString("service_disabled_reason", reason)
        .putLong("service_disabled_ts", System.currentTimeMillis())
        .commit() // commit síncrono a propósito: transición atómica visible entre procesos/hilos
    Log.i("ServiceStatusFlags", "service_disabled=$disabled reason=$reason")
}
```
Replicar el mismo patrón para `isServicePaused/setServicePaused` y `isWatchdogDisabled/setWatchdogDisabled` (mismas keys legacy `service_paused` y `watchdog_disabled` para compatibilidad con datos existentes en el teléfono).

- [ ] **Step 2: Reemplazar TODAS las escrituras/lecturas directas**

Buscar cada `getBoolean("service_disabled"`/`putBoolean("service_disabled"` (y paused/watchdog) en los archivos listados y reemplazar por la llamada al accessor, pasando un `reason` descriptivo del contexto (ej. `"stop_gps_service FCM"`, `"logout"`, `"boot check"`).

Run para encontrar todo:
```powershell
Select-String -Path android\app\src\main\kotlin\**\*.kt -Pattern '"(service_disabled|service_paused|watchdog_disabled)"' | Where-Object { $_.Path -notmatch 'ServiceStatusFlags' }
```
Expected tras el cambio: 0 matches fuera de `ServiceStatusFlags.kt`.

- [ ] **Step 3: Limpieza de manifest**

En `AndroidManifest.xml`:
1. Borrar `USE_EXACT_ALARM` (L27) y `SCHEDULE_EXACT_ALARM` (L28) — el modelo persistente no usa alarmas. (NOTA: la cadena AlarmManager se borra recién en Task 7; entre Task 3 y Task 7 la app usará `setExactAndAllowWhileIdle` sin permiso exact → cae al fallback inexacto que YA existe en `LocationHelper.kt:678-724`. Aceptable en la misma release porque los tasks se mergean juntos.)
2. Borrar `QUERY_ALL_PACKAGES` (L41). Antes verificar: `Select-String -Path android\app\src\main\kotlin\**\*.kt -Pattern 'getInstalledPackages|queryIntentActivities'` → si hay uso real, DETENERSE y reportar.
3. Agregar `android:maxSdkVersion="28"` a `WRITE_EXTERNAL_STORAGE` (L16) y `android:maxSdkVersion="32"` a `READ_EXTERNAL_STORAGE` (L17) (no borrar: el FileProvider/apk_installer puede usarlos en APIs viejas).
4. Quitar el duplicado de `ACCESS_NETWORK_STATE` (L38, dejar L32).
5. En `BootReceiver` (L121-132): borrar SOLO la línea del intent-filter `MY_PACKAGE_RESTARTED` (L129) — G28. (BOOT_COMPLETED y MY_PACKAGE_REPLACED quedan.)

- [ ] **Step 4: Verificar y commit**

Run: `flutter build apk --debug` → BUILD SUCCESSFUL.

```powershell
git add -A -- . ":(exclude).dart_tool"; git commit -m "B.7: ServiceStatusFlags dueno unico de flags + limpieza manifest (exact alarm, query_all_packages, storage legacy, MY_PACKAGE_RESTARTED)"; git push
```

---

### Task 4: DeviceEventReporter — transporte de eventos §8.6 sobre RegistrarErrores

**Files:**
- Create: `android/app/src/main/kotlin/com/riogas/appmovil/DeviceEventReporter.kt`

**Interfaces:**
- Produces (usado por Tasks 6, 8, 9, 10, 11):
```kotlin
object DeviceEventReporter {
    // tipos: "gps_off", "gps_on", "permission_revoked", "heartbeat_no_gps",
    //        "booted", "health_fgs_dead", "restart_result", "tracking_reregistered"
    fun report(context: Context, tipo: String, motivo: String = "", extra: Map<String, String> = emptyMap())
}
```
- Fire-and-forget en coroutine IO, 1 reintento, timeout 15 s. NUNCA lanza excepción al caller.

- [ ] **Step 1: Crear DeviceEventReporter.kt**

```kotlin
package com.riogas.appmovil

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Reporta eventos de dispositivo (§8.6) al backend.
 * Transporte transitorio: endpoint RegistrarErrores con campo tipo dentro de data.
 * Cuando GeneXus publique RegistrarEventoDispositivo, cambiar ENDPOINT.
 */
object DeviceEventReporter {
    private const val TAG = "DeviceEventReporter"
    private const val ENDPOINT = "RegistrarErrores" // TODO backend: RegistrarEventoDispositivo
    private const val TOKEN = "IcA.FwL.1710.!"

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    fun report(context: Context, tipo: String, motivo: String = "", extra: Map<String, String> = emptyMap()) {
        val appContext = context.applicationContext
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val flutterPrefs = appContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val config = appContext.getSharedPreferences("config", Context.MODE_PRIVATE)
                var baseUrl = flutterPrefs.getString("flutter.baseUrl", "https://www.riogas.uy/ica_geos_/appservices/")
                    ?: "https://www.riogas.uy/ica_geos_/appservices/"
                if (!baseUrl.contains("/appservices/")) {
                    baseUrl = baseUrl.trimEnd('/') + "/appservices/"
                }
                val movil = config.getString("last_movil", "") ?: ""
                val usuario = config.getString("last_usuario", "") ?: ""
                val deviceId = config.getString("last_deviceId", "") ?: ""

                val data = JSONObject().apply {
                    put("tipo", tipo)
                    put("motivo", motivo)
                    put("ts", System.currentTimeMillis())
                    put("origen", "device_event")
                    extra.forEach { (k, v) -> put(k, v) }
                }
                val payload = JSONObject().apply {
                    put("token", TOKEN)
                    put("movil", movil.toIntOrNull() ?: 0)
                    put("DeviceId", deviceId)
                    put("usuario", usuario)
                    put("data", data.toString())
                }

                val body = payload.toString().toRequestBody("application/json".toMediaType())
                val request = Request.Builder().url("$baseUrl$ENDPOINT").post(body).build()

                var attempts = 0
                while (attempts < 2) {
                    attempts++
                    try {
                        client.newCall(request).execute().use { resp ->
                            if (resp.isSuccessful) {
                                Log.i(TAG, "evento $tipo reportado (intento $attempts)")
                                return@launch
                            }
                            Log.w(TAG, "evento $tipo HTTP ${resp.code} (intento $attempts)")
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "evento $tipo fallo intento $attempts: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "report() error no fatal: ${e.message}")
            }
        }
    }
}
```
Nota: `last_movil/last_usuario/last_deviceId` ya se escriben en prefs `"config"` desde `LocationHelper.scheduleLocationAlarm` (L641-648) y seguirán escribiéndose desde el nuevo servicio (Task 6, Step 2). Verificar el nombre EXACTO de las keys en `LocationHelper.kt:641-648` antes de usarlas (podrían ser `last_deviceid` u otra variante) y ajustar.

- [ ] **Step 2: Compilar y commit**

Run: `flutter build apk --debug` → BUILD SUCCESSFUL.

```powershell
git add -A -- . ":(exclude).dart_tool"; git commit -m "B.2 transporte: DeviceEventReporter sobre RegistrarErrores"; git push
```

---

### Task 5: B.0a — Cola durable Room + uploader por lote

**Files:**
- Modify: `android/app/build.gradle` (Room + kapt)
- Create: `android/app/src/main/kotlin/com/riogas/appmovil/tracking/LocationFixEntity.kt`
- Create: `android/app/src/main/kotlin/com/riogas/appmovil/tracking/LocationFixDao.kt`
- Create: `android/app/src/main/kotlin/com/riogas/appmovil/tracking/TrackingDatabase.kt`
- Create: `android/app/src/main/kotlin/com/riogas/appmovil/tracking/LocationBatchUploader.kt`

**Interfaces:**
- Produces (usa Task 6):
```kotlin
@Entity(tableName = "location_fixes")
data class LocationFixEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val movil: Int, val escenario: Int, val usuario: String, val deviceId: String,
    val latitud: Double, val longitud: Double, val accuracy: Float,
    val fechaHora: String,          // ISO local, mismo formato que hoy manda LocationHelper
    val createdAt: Long,
    val sentRioGas: Boolean = false, val sentTrack: Boolean = false, val attempts: Int = 0
)
interface LocationFixDao { /* insert, getUnsentTrack(limit), getUnsentRioGas(limit),
    markTrackSent(ids), markRioGasSent(ids), incrementAttempts(ids), purgeSent(keepMs), countUnsent() */ }
object LocationBatchUploader {
    suspend fun flushTrack(context: Context): Int   // devuelve cant. enviadas
    suspend fun flushRioGas(context: Context): Int
}
TrackingDatabase.get(context).locationFixDao()
```
- Regla de oro (WS-C): **se marca sent DESPUÉS del 200, nunca se borra antes del POST**. Idempotencia natural: (deviceId, fechaHora) identifican el fix; un duplicado ocasional server-side es aceptable.

- [ ] **Step 1: Agregar Room a build.gradle**

En `android/app/build.gradle`: en el bloque de plugins agregar `id 'kotlin-kapt'` (después del plugin kotlin-android existente; adaptar a la sintaxis que use el archivo, `apply plugin:` o `plugins {}`), y en dependencies:
```groovy
implementation "androidx.room:room-runtime:2.6.1"
implementation "androidx.room:room-ktx:2.6.1"
kapt "androidx.room:room-compiler:2.6.1"
implementation "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1"
```

- [ ] **Step 2: Crear entity, dao y database**

`LocationFixEntity.kt`: el data class del bloque Interfaces (completo, con imports `androidx.room.*`).

`LocationFixDao.kt`:
```kotlin
package com.riogas.appmovil.tracking

import androidx.room.*

@Dao
interface LocationFixDao {
    @Insert
    suspend fun insert(fix: LocationFixEntity): Long

    @Query("SELECT * FROM location_fixes WHERE sentTrack = 0 ORDER BY id ASC LIMIT :limit")
    suspend fun getUnsentTrack(limit: Int): List<LocationFixEntity>

    @Query("SELECT * FROM location_fixes WHERE sentRioGas = 0 ORDER BY id ASC LIMIT :limit")
    suspend fun getUnsentRioGas(limit: Int): List<LocationFixEntity>

    @Query("UPDATE location_fixes SET sentTrack = 1 WHERE id IN (:ids)")
    suspend fun markTrackSent(ids: List<Long>)

    @Query("UPDATE location_fixes SET sentRioGas = 1 WHERE id IN (:ids)")
    suspend fun markRioGasSent(ids: List<Long>)

    @Query("UPDATE location_fixes SET attempts = attempts + 1 WHERE id IN (:ids)")
    suspend fun incrementAttempts(ids: List<Long>)

    @Query("DELETE FROM location_fixes WHERE sentTrack = 1 AND sentRioGas = 1 AND createdAt < :olderThan")
    suspend fun purgeSent(olderThan: Long)

    @Query("SELECT COUNT(*) FROM location_fixes WHERE sentTrack = 0 OR sentRioGas = 0")
    suspend fun countUnsent(): Int
}
```

`TrackingDatabase.kt`:
```kotlin
package com.riogas.appmovil.tracking

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(entities = [LocationFixEntity::class], version = 1, exportSchema = false)
abstract class TrackingDatabase : RoomDatabase() {
    abstract fun locationFixDao(): LocationFixDao

    companion object {
        @Volatile private var INSTANCE: TrackingDatabase? = null
        fun get(context: Context): TrackingDatabase =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext, TrackingDatabase::class.java, "tracking.db"
                ).fallbackToDestructiveMigration().build().also { INSTANCE = it }
            }
    }
}
```

- [ ] **Step 3: Crear LocationBatchUploader.kt**

Estructura (el armado EXACTO de cada body se COPIA de `LocationHelper.kt` — no inventarlo):
```kotlin
package com.riogas.appmovil.tracking

import android.content.Context
import android.util.Log
// + OkHttp / JSONObject imports como en DeviceEventReporter

object LocationBatchUploader {
    private const val TAG = "LocationBatchUploader"
    private const val BATCH_LIMIT = 200

    /** POST batch a https://track.riogas.com.uy/api/import/gps.
     *  Body: COPIAR el armado exacto de LocationHelper.kt:2379-2509 (JSON array de fixes). */
    suspend fun flushTrack(context: Context): Int {
        val dao = TrackingDatabase.get(context).locationFixDao()
        val batch = dao.getUnsentTrack(BATCH_LIMIT)
        if (batch.isEmpty()) return 0
        val ok = postToTrack(batch)          // armar body con los campos de LocationHelper L2379+
        return if (ok) { dao.markTrackSent(batch.map { it.id }); batch.size }
        else { dao.incrementAttempts(batch.map { it.id }); 0 }
    }

    /** POST a {baseUrl}RegistrarCoordenadasV2, un fix por request (formato actual).
     *  Body: COPIAR el armado exacto de LocationHelper.kt:1578-1663 (token, movil, Latitud,
     *  longitud, FechaHora, DeviceId, usuario, escenario...). Cortar el loop al primer fallo. */
    suspend fun flushRioGas(context: Context): Int {
        val dao = TrackingDatabase.get(context).locationFixDao()
        val batch = dao.getUnsentRioGas(BATCH_LIMIT)
        var sent = 0
        for (fix in batch) {
            if (postToRioGas(context, fix)) { dao.markRioGasSent(listOf(fix.id)); sent++ }
            else { dao.incrementAttempts(listOf(fix.id)); break }
        }
        return sent
    }
}
```
El implementer debe leer `LocationHelper.kt:1560-1663` y `LocationHelper.kt:2379-2520` y transplantar el armado de bodies/headers/URL tal cual (incluida la normalización de baseUrl y el token). Sin `Thread.sleep`: los reintentos quedan a cargo del próximo tick de flush.

- [ ] **Step 4: Compilar y commit**

Run: `flutter build apk --debug` → BUILD SUCCESSFUL (valida kapt/Room).

```powershell
git add -A -- . ":(exclude).dart_tool"; git commit -m "B.0a: cola durable Room + uploader por lote (track 30s / RioGas 3min, at-least-once)"; git push
```

---

### Task 6: B.0b — LocationTrackingService (el FGS único persistente)

**Files:**
- Create: `android/app/src/main/kotlin/com/riogas/appmovil/tracking/LocationTrackingService.kt`
- Modify: `android/app/src/main/AndroidManifest.xml` (declarar el service)

**Interfaces:**
- Consumes: `TrackingDatabase`, `LocationBatchUploader`, `DeviceEventReporter`, `ServiceStatusFlags`.
- Produces (usa Tasks 7-11):
```kotlin
class LocationTrackingService : Service() {
    companion object {
        @Volatile var isRunning = false; private set
        /** Idempotente: si ya corre, solo actualiza extras. Llamar SOLO desde foreground
         *  (Activity) o desde FCM high-priority / health-check con exención. */
        fun start(context: Context, movil: String, escenario: String, usuario: String, deviceId: String)
        fun stop(context: Context)
    }
}
```
- B.6 incluido: NO usa colecciones estáticas compartidas; todo el estado vive en la instancia del service + Room.

- [ ] **Step 1: Crear LocationTrackingService.kt**

```kotlin
package com.riogas.appmovil.tracking

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import com.riogas.appmovil.DeviceEventReporter
import com.riogas.appmovil.ServiceStatusFlags
import kotlinx.coroutines.*
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class LocationTrackingService : Service() {

    companion object {
        private const val TAG = "LocationTrackingService"
        private const val NOTIF_ID = 1710
        private const val CHANNEL_ID = "location_channel"
        private const val SILENCE_THRESHOLD_MS = 90_000L
        private const val TRACK_FLUSH_MS = 30_000L
        private const val RIOGAS_FLUSH_MS = 180_000L
        private const val WATCH_TICK_MS = 30_000L
        private const val MIN_UPDATE_MS = 5_000L
        private const val DEFAULT_INTERVAL_S = 12

        @Volatile var isRunning = false
            private set

        fun start(context: Context, movil: String, escenario: String, usuario: String, deviceId: String) {
            val intent = Intent(context, LocationTrackingService::class.java).apply {
                putExtra("movil", movil); putExtra("escenario", escenario)
                putExtra("usuario", usuario); putExtra("deviceId", deviceId)
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LocationTrackingService::class.java))
        }
    }

    private lateinit var fusedClient: FusedLocationProviderClient
    private var locationCallback: LocationCallback? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    @Volatile private var lastFixElapsed = 0L
    private var movil = ""; private var escenario = "0"; private var usuario = ""; private var deviceId = ""

    override fun onCreate() {
        super.onCreate()
        fusedClient = LocationServices.getFusedLocationProviderClient(this)
        startInForeground()
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let {
            it.getStringExtra("movil")?.takeIf { s -> s.isNotBlank() }?.let { s -> movil = s }
            it.getStringExtra("escenario")?.takeIf { s -> s.isNotBlank() }?.let { s -> escenario = s }
            it.getStringExtra("usuario")?.takeIf { s -> s.isNotBlank() }?.let { s -> usuario = s }
            it.getStringExtra("deviceId")?.takeIf { s -> s.isNotBlank() }?.let { s -> deviceId = s }
        }
        if (movil.isBlank()) restoreIdentityFromPrefs()
        persistIdentityToPrefs()

        if (ServiceStatusFlags.isServiceDisabled(this)) {
            Log.w(TAG, "service_disabled=true → no arranca tracking")
            stopSelf(); return START_NOT_STICKY
        }

        registerLocationUpdates()   // idempotente: remueve callback previo antes de registrar
        startLoops()                // idempotente: cancela jobs previos
        return START_STICKY
    }

    private fun startInForeground() {
        val channel = NotificationChannel(CHANNEL_ID, "Ubicación", NotificationManager.IMPORTANCE_DEFAULT)
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MoveIT")
            .setContentText("Rastreo de ubicación activo")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else startForeground(NOTIF_ID, notif)
    }

    private fun intervalSeconds(): Int {
        val v = getSharedPreferences("config", MODE_PRIVATE).getInt("tracking_interval_seconds", DEFAULT_INTERVAL_S)
        return if (v > 0) v else DEFAULT_INTERVAL_S   // constante validada >0
    }

    private fun registerLocationUpdates() {
        if (!hasLocationPermission()) {
            DeviceEventReporter.report(this, "heartbeat_no_gps", "NO_PERMISSION")
            return
        }
        locationCallback?.let { fusedClient.removeLocationUpdates(it) }
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, intervalSeconds() * 1000L)
            .setMinUpdateIntervalMillis(MIN_UPDATE_MS)
            .build()
        val callback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val loc = result.lastLocation ?: return
                lastFixElapsed = android.os.SystemClock.elapsedRealtime()
                val fechaHora = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(Date())
                scope.launch {
                    try {
                        TrackingDatabase.get(this@LocationTrackingService).locationFixDao().insert(
                            LocationFixEntity(
                                movil = movil.toIntOrNull() ?: 0,
                                escenario = escenario.toIntOrNull() ?: 0,
                                usuario = usuario, deviceId = deviceId,
                                latitud = loc.latitude, longitud = loc.longitude,
                                accuracy = loc.accuracy, fechaHora = fechaHora,
                                createdAt = System.currentTimeMillis()
                            )
                        )
                    } catch (e: Exception) { Log.e(TAG, "insert fix: ${e.message}") }
                }
            }
        }
        try {
            fusedClient.requestLocationUpdates(request, callback, Looper.getMainLooper())
            locationCallback = callback
            lastFixElapsed = android.os.SystemClock.elapsedRealtime()
            Log.i(TAG, "requestLocationUpdates registrado (intervalo ${intervalSeconds()}s)")
        } catch (e: SecurityException) {
            DeviceEventReporter.report(this, "heartbeat_no_gps", "NO_PERMISSION", mapOf("error" to (e.message ?: "")))
        }
    }

    private var flushTrackJob: Job? = null
    private var flushRioGasJob: Job? = null
    private var watchJob: Job? = null

    private fun startLoops() {
        flushTrackJob?.cancel(); flushRioGasJob?.cancel(); watchJob?.cancel()
        flushTrackJob = scope.launch {
            while (isActive) { delay(TRACK_FLUSH_MS)
                try { LocationBatchUploader.flushTrack(this@LocationTrackingService) }
                catch (e: Exception) { Log.e(TAG, "flushTrack: ${e.message}") } }
        }
        flushRioGasJob = scope.launch {
            while (isActive) { delay(RIOGAS_FLUSH_MS)
                try {
                    LocationBatchUploader.flushRioGas(this@LocationTrackingService)
                    TrackingDatabase.get(this@LocationTrackingService).locationFixDao()
                        .purgeSent(System.currentTimeMillis() - 24 * 3600_000L)
                } catch (e: Exception) { Log.e(TAG, "flushRioGas: ${e.message}") } }
        }
        // Auto-monitoreo interno: ¿recibí un fix en los últimos 90 s?
        watchJob = scope.launch {
            while (isActive) { delay(WATCH_TICK_MS)
                val silence = android.os.SystemClock.elapsedRealtime() - lastFixElapsed
                if (silence > SILENCE_THRESHOLD_MS) {
                    val motivo = when {
                        !hasLocationPermission() -> "NO_PERMISSION"
                        !isGpsProviderEnabled() -> "GPS_DISABLED_IN_SETTINGS"
                        else -> "NO_SIGNAL"
                    }
                    Log.w(TAG, "silencio ${silence}ms → re-registrando callback ($motivo)")
                    DeviceEventReporter.report(this@LocationTrackingService, "heartbeat_no_gps", motivo,
                        mapOf("silence_ms" to silence.toString()))
                    withContext(Dispatchers.Main) { registerLocationUpdates() }
                    DeviceEventReporter.report(this@LocationTrackingService, "tracking_reregistered", motivo)
                }
            }
        }
    }

    private fun hasLocationPermission(): Boolean =
        checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun isGpsProviderEnabled(): Boolean =
        (getSystemService(LOCATION_SERVICE) as android.location.LocationManager)
            .isProviderEnabled(android.location.LocationManager.GPS_PROVIDER)

    private fun restoreIdentityFromPrefs() {
        val p = getSharedPreferences("config", MODE_PRIVATE)
        movil = p.getString("last_movil", "") ?: ""
        escenario = p.getString("last_escenario", "0") ?: "0"
        usuario = p.getString("last_usuario", "") ?: ""
        deviceId = p.getString("last_deviceId", "") ?: ""
    }

    private fun persistIdentityToPrefs() {
        getSharedPreferences("config", MODE_PRIVATE).edit()
            .putString("last_movil", movil).putString("last_escenario", escenario)
            .putString("last_usuario", usuario).putString("last_deviceId", deviceId)
            .apply()
    }

    // Android 15: el sistema puede dar timeout a FGS location de larga duración
    override fun onTimeout(startId: Int) {
        DeviceEventReporter.report(this, "heartbeat_no_gps", "FGS_TIMEOUT_A15")
        stopSelf()
    }

    override fun onDestroy() {
        isRunning = false
        locationCallback?.let { fusedClient.removeLocationUpdates(it) }
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
```
IMPORTANTE (verificaciones del implementer):
1. Confirmar los nombres reales de keys `last_*` en `LocationHelper.kt:641-648` y alinear `restoreIdentityFromPrefs` + `DeviceEventReporter`.
2. `onTimeout(startId: Int)`: existe desde API 35 en `Service`. Como compileSdk=35 compila; si la firma difiere (`onTimeout(startId: Int, fgsType: Int)`), usar la que compile.
3. El canal `location_channel` ya existe (lo creaba `ForegroundLocationService`); reusar mismo id/canal está OK.

- [ ] **Step 2: Declarar el service en el manifest**

En `AndroidManifest.xml`, junto al service viejo (L105-108), agregar:
```xml
<service
    android:name="com.riogas.appmovil.tracking.LocationTrackingService"
    android:foregroundServiceType="location"
    android:exported="false" />
```
(El viejo `.ForegroundLocationService` se elimina en Task 7.)

- [ ] **Step 3: Compilar y commit**

Run: `flutter build apk --debug` → BUILD SUCCESSFUL.

```powershell
git add -A -- . ":(exclude).dart_tool"; git commit -m "B.0b: LocationTrackingService FGS unico persistente (fix continuo + cola Room + auto-monitoreo 90s + onTimeout A15)"; git push
```

---

### Task 7: B.1 — Retirar los 8 mecanismos y recablear el arranque

**Files:**
- Delete: `android/app/src/main/kotlin/com/example/moveit/LocationReceiver.kt`
- Delete: `android/app/src/main/kotlin/com/example/moveit/ForegroundLocationService.kt`
- Delete: `android/app/src/main/kotlin/com/example/moveit/LocationWorker.kt` (Task 10 crea HealthCheckWorker nuevo)
- Modify: `android/app/src/main/kotlin/com/example/moveit/LocationHelper.kt`
- Modify: `android/app/src/main/kotlin/com/riogas/appmovil/ServiceWatchdog.kt`
- Modify: `android/app/src/main/kotlin/com/riogas/appmovil/CriticalLogAlarmReceiver.kt`
- Modify: `android/app/src/main/kotlin/com/example/moveit/WorkManagerHelper.kt`
- Modify: `android/app/src/main/kotlin/com/example/moveit/MainActivity.kt`
- Modify: `android/app/src/main/kotlin/com/example/moveit/LocationServiceController.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes: `LocationTrackingService.start/stop/isRunning` (Task 6).
- Produces: `MainActivity` channel `background_service` → `startLocationService` arranca el FGS nuevo; `stopLocationService`/`forceStopGpsService` lo paran. `LocationHelper` queda como utilitario (UTM, RegistrarCierre, getCurrentLocation puntual SIN warm-up ni arranque redundante).

- [ ] **Step 1: Borrar la cadena AlarmManager**

1. Borrar `LocationReceiver.kt` completo y su `<receiver>` del manifest (L110-112).
2. En `LocationHelper.kt`: borrar `scheduleLocationAlarm` (L622-748), `rescheduleNextAlarm` (L754-762) y todo código que arme PendingIntents hacia LocationReceiver (requestCode 1710). Borrar las escrituras de `last_interval`/`last_schedule_time` (el resto de keys `last_*` ahora las escribe el service — Task 6).
3. Buscar y limpiar TODOS los callers: `Select-String -Path android\app\src\main\kotlin\**\*.kt -Pattern 'scheduleLocationAlarm|rescheduleNextAlarm|LocationReceiver'` → 0 matches al terminar.

- [ ] **Step 2: Borrar warm-up + Thread.sleep + arranque redundante en LocationHelper**

1. `getCurrentLocation`: borrar el arranque redundante del FGS (L787-805, incluye `Thread.sleep(500)` L805).
2. Borrar el warm-up de 7 fixes completo: request L943-951, callback L990-1001, `requestLocationUpdates` L1005-1009, loop de polling con `Thread.sleep(500)` L1017-1025, `removeLocationUpdates` L1028, filtro/promedio L1033-1129. Reemplazar por UN fix simple:
```kotlin
// Fix puntual: el chip GPS ya está caliente por el tracking continuo del FGS.
val cts = CancellationTokenSource()
val location = Tasks.await(
    fusedLocationClient.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, cts.token),
    15, TimeUnit.SECONDS
)
```
(adaptar al estilo del método existente; conservar la conversión UTM y el resto del pipeline de envío que siga usándose).
3. B.6: borrar las colecciones estáticas compartidas del warm-up (`receivedLocations`, `locationBuffer`, `totalDistance`, `lastLocation` — buscar sus declaraciones en LocationHelper y eliminar; si alguna se usa fuera del warm-up, protegerla con `synchronized` o migrarla a variable local).
4. Revisar los `Thread.sleep` restantes de LocationHelper (L1351, L1401, L1747, L1819): los de retry de API (5000ms) reemplazar por `delay()` si el método es suspend, o eliminar el retry (la cola Room ya reintenta); los demás eliminar.

- [ ] **Step 3: Desactivar watchdogs como reiniciadores**

1. `ServiceWatchdog.kt`: eliminar `restartGPSService` completo (L103-646) y `isAlarmScheduled` (L62-84). Si `getFullStatus`/health-log se usa desde MainActivity, conservar solo lectura de estado (`isGPSServiceRunning` puede quedar para reporting, cambiándolo a `LocationTrackingService.isRunning`). Objetivo: el archivo NO contiene ningún `startForegroundService`.
2. `CriticalLogAlarmReceiver.kt`: eliminar `performWatchdogCheck` (L142-238) y el `setRepeating` de 30 s (L60-65). El upload de logs críticos YA lo cubre `CriticalLogUploadWorker` — cambiar su período de 30 s a **15 min** (`CriticalLogUploadWorker.kt:44-46`). Si tras esto el receiver queda vacío, borrarlo + su entrada de manifest (L115-118) + los callers (`ServiceWatchdog.restartCriticalLogWorker` L653-697 y el Thread watchdog dentro del difunto ForegroundLocationService).
3. `WorkManagerHelper.kt`: eliminar `schedulePeriodicLocationWork` y el fallback OneTimeWork (queda solo `cancelPeriodicWork`, sin el side-effect de `service_disabled` L158 — usar ServiceStatusFlags si se conserva). Task 10 lo reemplaza por el health-check.

- [ ] **Step 4: Recablear MainActivity y LocationServiceController**

1. `MainActivity.kt` channel `background_service`:
   - `startLocationService` (L377+, el que hoy hace `startForegroundService` L421): reemplazar por `LocationTrackingService.start(this, movil, escenario, usuario, deviceId)` con los mismos argumentos que hoy llegan de Flutter.
   - `stopLocationService` / `forceStopGpsService` / `forceStopService`: reemplazar por `LocationTrackingService.stop(this)` + `ServiceStatusFlags.setServiceDisabled(...)` según semántica actual (force → disabled=true).
   - `isGpsServiceRunning` → devolver `LocationTrackingService.isRunning`.
   - `checkAndRestartLocationService` (L801) y el tercer start (L1096): mismos reemplazos; si eran parte del flujo REMOTE_LOGOUT, conservar la semántica pero apuntando al service nuevo.
2. `LocationServiceController.kt`: `stopLocationServiceFromBackground` → cancelar WorkManager health-check + `LocationTrackingService.stop` + flags vía ServiceStatusFlags (ya sin alarmas que cancelar).
3. Borrar `ForegroundLocationService.kt` + su `<service>` del manifest (L105-108).

- [ ] **Step 5: AC de B.1 y compilación**

Run:
```powershell
Select-String -Path android\app\src\main\kotlin\**\*.kt -Pattern 'startForegroundService'
```
Expected: matches SOLO en `LocationTrackingService.kt` (companion start), `FcmPushReceiver.kt` (resurrección remota B.3 — se ajusta en Task 8) y (tras Task 10) `HealthCheckWorker.kt`. Ninguno en receivers/workers de background sin documentar.

```powershell
Select-String -Path android\app\src\main\kotlin\**\*.kt -Pattern 'Thread\.sleep'
```
Expected: 0 matches en el flujo GPS (LocationHelper/FcmPushReceiver quedan; FcmPushReceiver se limpia en Task 8 — anotar los que queden).

Run: `flutter build apk --debug` → BUILD SUCCESSFUL.

- [ ] **Step 6: Commit**

```powershell
git add -A -- . ":(exclude).dart_tool"; git commit -m "B.1: retirar los 8 mecanismos de resurreccion GPS; arranque unico via LocationTrackingService"; git push
```

---

### Task 8: B.3 — FCM restart_tracking / stop_tracking unificados

**Files:**
- Modify: `android/app/src/main/kotlin/com/riogas/appmovil/FcmPushReceiver.kt`
- Modify: `lib/main.dart` (líneas 553-572)

**Interfaces:**
- Consumes: `LocationTrackingService`, `DeviceEventReporter`, `ServiceStatusFlags`.
- Produces: comandos FCM `restart_tracking` y `stop_tracking`; aliases legacy `restart_gps_service`, `force_gps_execution` → restart; `stop_gps_service` → stop. `get_status` y `logout_user` se conservan (logout apuntando al service nuevo).

- [ ] **Step 1: Reescribir el dispatcher de FcmPushReceiver**

En el `when(action)` (L71-76):
```kotlin
when (action) {
    "restart_tracking", "restart_gps_service", "force_gps_execution" -> handleRestartTracking(data)
    "stop_tracking", "stop_gps_service" -> handleStopTracking(data)
    "get_status" -> handleGetStatus(data)
    "logout_user" -> handleLogoutUser(data)
}
```

`handleRestartTracking` (reemplaza `handleRestartGpsService` L115+ y `handleForceGpsExecution` L482+; conservar la validación de sesión existente de L120):
```kotlin
private fun handleRestartTracking(data: Map<String, String>) {
    try {
        if (!isSessionValid()) {   // reusar la validación existente de handleRestartGpsService
            DeviceEventReporter.report(this, "restart_result", "NO_SESSION")
            return
        }
        ServiceStatusFlags.setServiceDisabled(this, false, "restart_tracking FCM")
        ServiceStatusFlags.setServicePaused(this, false, "restart_tracking FCM")
        // Idempotente: si ya corre, start() solo re-entrega extras y re-registra si hace falta
        LocationTrackingService.start(this, movilFromPrefs(), escenarioFromPrefs(), usuarioFromPrefs(), deviceIdFromPrefs())
        DeviceEventReporter.report(this, "restart_result", "OK",
            mapOf("already_running" to LocationTrackingService.isRunning.toString()))
    } catch (e: Exception) {
        // FGS denegado / permiso / GPS off → el server marca "requiere intervencion"
        DeviceEventReporter.report(this, "restart_result", "FAILED", mapOf("error" to (e.message ?: e.javaClass.simpleName)))
    }
}
```
(FCM high-priority otorga la exención para `startForegroundService` en 12+; capturar `ForegroundServiceStartNotAllowedException` dentro del catch genérico ya lo cubre.) Los helpers `movilFromPrefs()` etc. leen las keys `last_*` de prefs `"config"` — reusar lo que ya hace el receiver en L135+ con FlutterSharedPreferences como fallback.

`handleStopTracking` (reemplaza `handleStopGpsService` L430): `LocationTrackingService.stop(this)` + `ServiceStatusFlags.setServiceDisabled(this, true, "stop_tracking FCM")` + `DeviceEventReporter.report(this, "restart_result", "STOPPED")`. Sin alarmas que cancelar (ya no existen) → no queda loop G3.

`handleLogoutUser` (L848): conservar el flujo pero: parar `LocationTrackingService` en vez del viejo (L883), quitar la cancelación de CriticalLogAlarm si se borró en Task 7 (L919), flags vía ServiceStatusFlags (L934).

2. **Eliminar los `Thread.sleep` del hilo FCM** (L347 y L731 desaparecen con los handlers viejos; verificar `Select-String -Path android\app\src\main\kotlin\com\riogas\appmovil\FcmPushReceiver.kt -Pattern 'Thread\.sleep'` → 0 matches).

- [ ] **Step 2: Limpiar el handler Dart de force_gps_execution**

En `lib/main.dart:553-572`: borrar el handler completo de `force_gps_execution` (el "kill sin restart" G4). El comando ahora lo maneja SOLO el nativo como alias de restart. Verificar si `GpsServiceManager` queda sin usos reales (su único caller activo era este handler + battery checks usan el channel directo); si `gps_service_manager.dart` queda huérfano, borrarlo y quitar su import.

- [ ] **Step 3: Test de idempotencia manual + AC**

AC (documentado para prueba en dispositivo, no automatizable acá): dos `restart_tracking` seguidos no duplican el servicio — garantizado por diseño (Android reutiliza la instancia de un Service ya corriendo; `onStartCommand` re-registra callback sin duplicar porque `registerLocationUpdates` remueve el callback previo y `startLoops` cancela jobs previos).

Run: `flutter build apk --debug` → BUILD SUCCESSFUL. `flutter analyze` → sin errores nuevos.

- [ ] **Step 4: Commit**

```powershell
git add -A -- . ":(exclude).dart_tool"; git commit -m "B.3: FCM restart_tracking/stop_tracking unificados e idempotentes, sin Thread.sleep, con reporte de resultado"; git push
```

---

### Task 9: B.2 — GPS-off / permisos como evento de primera clase

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/moveit/receivers/GPSStatusReceiver.kt`
- Modify: `android/app/src/main/kotlin/com/example/moveit/receivers/PermissionChangeReceiver.kt`
- Modify: `lib/main.dart` (onResume → chequeo de permisos ya existe; agregar reporte)

**Interfaces:**
- Consumes: `DeviceEventReporter`.
- Produces: al apagar GPS → `gps_off` al backend en <30 s + notificación visible; al encender → `gps_on` + se cancela la notificación.

- [ ] **Step 1: GPSStatusReceiver reporta y notifica**

En `GPSStatusReceiver.kt`, donde hoy solo loguea (L79 OFF / L91-97 ON):
```kotlin
// GPS pasó a OFF
DeviceEventReporter.report(context, "gps_off", "PROVIDERS_CHANGED")
showGpsOffNotification(context)

// GPS pasó a ON
DeviceEventReporter.report(context, "gps_on", "PROVIDERS_CHANGED")
cancelGpsOffNotification(context)
```
Agregar en el mismo archivo:
```kotlin
private const val GPS_ALERT_NOTIF_ID = 4210

private fun showGpsOffNotification(context: Context) {
    val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val channel = NotificationChannel("gps_alert", "Alertas de GPS", NotificationManager.IMPORTANCE_HIGH)
    nm.createNotificationChannel(channel)
    val intent = Intent(android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS)
    val pi = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)
    val notif = NotificationCompat.Builder(context, "gps_alert")
        .setSmallIcon(context.applicationInfo.icon)
        .setContentTitle("Ubicación desactivada")
        .setContentText("Activá la ubicación para que MoveIT funcione correctamente.")
        .setPriority(NotificationCompat.PRIORITY_HIGH)
        .setContentIntent(pi)
        .setAutoCancel(true)
        .setOngoing(true)
        .build()
    nm.notify(GPS_ALERT_NOTIF_ID, notif)
}

private fun cancelGpsOffNotification(context: Context) {
    (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(GPS_ALERT_NOTIF_ID)
}
```
(el receiver ya se dispara por PROVIDERS_CHANGED — manifest L135-142 — así que la latencia es de segundos, cumple <30 s).

- [ ] **Step 2: permission_revoked**

1. `PermissionChangeReceiver.kt`: donde hoy solo loguea revocación (L57,71), agregar `DeviceEventReporter.report(context, "permission_revoked", permisoDetectado)`.
2. `lib/main.dart`: en `didChangeAppLifecycleState` → `AppLifecycleState.resumed` (buscar el observer existente), tras el chequeo de permisos que ya corre, si `permission == LocationPermission.denied || deniedForever`, invocar reporte vía el MethodChannel nativo NO es necesario: el health-check nativo (Task 10) ya cubre el reporte periódico. En Dart solo asegurar que el chequeo existente en onResume siga corriendo (no agregar código nuevo si ya está — verificar y documentar).
3. El `heartbeat_no_gps` con motivo ya quedó implementado dentro del service (Task 6, watchJob).

- [ ] **Step 3: Compilar, AC y commit**

AC manual documentado: con GPS apagado a mano, backend recibe `gps_off` (payload RegistrarErrores con tipo=gps_off) en <30 s y el usuario ve la notificación.

Run: `flutter build apk --debug` → BUILD SUCCESSFUL.

```powershell
git add -A -- . ":(exclude).dart_tool"; git commit -m "B.2: gps_off/gps_on/permission_revoked como eventos de primera clase + notificacion al repartidor"; git push
```

---

### Task 10: B.4 — Health-check WorkManager (15 min, NO fuente de GPS)

**Files:**
- Create: `android/app/src/main/kotlin/com/riogas/appmovil/tracking/HealthCheckWorker.kt`
- Modify: `android/app/src/main/kotlin/com/example/moveit/WorkManagerHelper.kt` (o reemplazo directo)
- Modify: `android/app/src/main/kotlin/com/example/moveit/MainActivity.kt` (programarlo al arrancar tracking)

**Interfaces:**
- Consumes: `LocationTrackingService.isRunning/start`, `DeviceEventReporter`, `ServiceStatusFlags`.
- Produces: PeriodicWork `tracking_health_check` cada 15 min.

- [ ] **Step 1: Crear HealthCheckWorker.kt**

```kotlin
package com.riogas.appmovil.tracking

import android.app.ForegroundServiceStartNotAllowedException
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import androidx.work.*
import com.riogas.appmovil.DeviceEventReporter
import com.riogas.appmovil.ServiceStatusFlags
import java.util.concurrent.TimeUnit

class HealthCheckWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val ctx = applicationContext
        if (ServiceStatusFlags.isServiceDisabled(ctx)) return Result.success()

        // permission_revoked check (B.2)
        if (ctx.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED) {
            DeviceEventReporter.report(ctx, "permission_revoked", "HEALTH_CHECK")
            return Result.success()
        }

        if (LocationTrackingService.isRunning) return Result.success()

        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        val exempt = pm.isIgnoringBatteryOptimizations(ctx.packageName)
        return try {
            if (exempt) {
                val p = ctx.getSharedPreferences("config", Context.MODE_PRIVATE)
                LocationTrackingService.start(ctx,
                    p.getString("last_movil", "") ?: "", p.getString("last_escenario", "0") ?: "0",
                    p.getString("last_usuario", "") ?: "", p.getString("last_deviceId", "") ?: "")
                DeviceEventReporter.report(ctx, "health_fgs_dead", "RESTARTED_BY_HEALTH_CHECK")
            } else {
                DeviceEventReporter.report(ctx, "health_fgs_dead", "NO_BATTERY_EXEMPTION")
            }
            Result.success()
        } catch (e: Exception) {
            val motivo = if (Build.VERSION.SDK_INT >= 31 && e is ForegroundServiceStartNotAllowedException)
                "FGS_START_NOT_ALLOWED" else e.javaClass.simpleName
            // aviso HTTP simple, legal desde background → el server puede disparar B.3
            DeviceEventReporter.report(ctx, "health_fgs_dead", motivo)
            Result.success()
        }
    }

    companion object {
        const val WORK_NAME = "tracking_health_check"
        fun schedule(context: Context) {
            val req = PeriodicWorkRequestBuilder<HealthCheckWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, req)
        }
        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }
}
```

- [ ] **Step 2: Programar y cancelar en los lugares correctos**

1. `MainActivity.startLocationService` (Task 7 lo recableó): después de `LocationTrackingService.start(...)` agregar `HealthCheckWorker.schedule(this)`.
2. En stop/logout (`handleLogoutUser`, `stopLocationService`, `LocationServiceController`): `HealthCheckWorker.cancel(context)`.
3. Borrar los restos de `WorkManagerHelper.schedulePeriodicLocationWork` si quedó algo (WORK_NAME viejo `LocationPeriodicWork` → cancelarlo una vez en `MainActivity.onCreate` para limpiar teléfonos actualizados: `WorkManager.getInstance(this).cancelUniqueWork("LocationPeriodicWork")`).

- [ ] **Step 3: Compilar y commit**

Run: `flutter build apk --debug` → BUILD SUCCESSFUL.

```powershell
git add -A -- . ":(exclude).dart_tool"; git commit -m "B.4: HealthCheckWorker 15min (revive FGS con exencion o avisa al backend; NO toma fixes)"; git push
```

---

### Task 11: B.5 — Boot ping

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/moveit/BootReceiver.kt`
- Create: `android/app/src/main/kotlin/com/riogas/appmovil/tracking/BootPingWorker.kt`

**Interfaces:**
- Consumes: `DeviceEventReporter`, `HealthCheckWorker`.
- Produces: tras reboot con sesión activa, el backend recibe `booted` en segundos y decide si manda `restart_tracking`.

- [ ] **Step 1: BootPingWorker**

```kotlin
package com.riogas.appmovil.tracking

import android.content.Context
import androidx.work.*
import com.riogas.appmovil.DeviceEventReporter

class BootPingWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        DeviceEventReporter.report(applicationContext, "booted", "BOOT_COMPLETED")
        HealthCheckWorker.schedule(applicationContext)   // re-asegurar el health-check tras reboot
        return Result.success()
    }

    companion object {
        fun enqueue(context: Context) {
            val req = OneTimeWorkRequestBuilder<BootPingWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork("boot_ping", ExistingWorkPolicy.REPLACE, req)
        }
    }
}
```

- [ ] **Step 2: Reescribir BootReceiver**

Conservar las validaciones existentes (sesión activa L35, service_disabled L46 → migrar a `ServiceStatusFlags.isServiceDisabled`); reemplazar el cuerpo que reprogramaba la alarma (L93-100, ya inexistente tras Task 7) por `BootPingWorker.enqueue(context)`. **NO** arrancar FGS de ubicación directo desde BOOT_COMPLETED. Eliminar la lectura de `last_interval` (L63) — la key muere con las alarmas (G11 resuelto por eliminación: dueño único = nadie). Verificar que `ServiceWatchdog` tampoco la lea ya (L110 — se fue en Task 7).

Run: `Select-String -Path android\app\src\main\kotlin\**\*.kt -Pattern 'last_interval'` → 0 matches.

- [ ] **Step 3: Compilar y commit**

Run: `flutter build apk --debug` → BUILD SUCCESSFUL.

```powershell
git add -A -- . ":(exclude).dart_tool"; git commit -m "B.5: boot ping via expedited work (booted -> backend decide restart_tracking); muere last_interval"; git push
```

---

### Task 12: B.8 — whileInUse como permiso válido en foreground

**Files:**
- Modify: `lib/pages/login_page.dart` (gate de permisos del login, ~L700-790)
- Modify: `lib/main.dart` (checks periódicos que exigen `always`)
- Modify: `lib/pages/home_page.dart` (`_showGpsPermissionDialog` y usos)

**Interfaces:**
- Produces: con permiso "mientras se usa", el login y el reporte puntual de estado funcionan; el diálogo pide `always` pero deja continuar con `whileInUse` (solo el tracking background sigue exigiendo `always`, y su ausencia la reporta el health-check como `permission_revoked`/`NO_PERMISSION`).

- [ ] **Step 1: Relajar los gates de foreground**

Patrón a aplicar en cada gate que hoy exige `LocationPermission.always` para operaciones PUNTUALES (login check, fix de estado, getCurrentLocation):
```dart
final ok = permission == LocationPermission.always ||
           permission == LocationPermission.whileInUse;
```
1. `login_page.dart` (~L760, el check que retorna `false` y bloquea login): si `whileInUse` → permitir continuar, mostrar el diálogo de `always` UNA vez de forma no bloqueante (el diálogo existente pero con botón "Continuar igual"), y loguear `print('[PERMISOS] whileInUse aceptado para login; tracking background requiere always')`.
2. `main.dart` `_checkLocationPermissions` / timer de 5 s: no disparar el diálogo bloqueante si el permiso es `whileInUse` Y la app está en foreground — mostrar como recordatorio no bloqueante máximo 1 vez por sesión (usar un flag `_whileInUseWarned`).
3. `home_page.dart` `_showGpsPermissionDialog`: agregar un segundo botón "Continuar con permiso limitado" que cierra el diálogo devolviendo `true` cuando `checkPermission()` es al menos `whileInUse` (esto además corta el `while(true)` infinito para ese caso).

- [ ] **Step 2: AC, analyze y commit**

AC manual: con permiso "mientras se usa" (revocando "todo el tiempo" en settings), el login entra y el cambio de estado puntual funciona con la app abierta.

Run: `flutter analyze` → sin errores nuevos.

```powershell
git add -A -- . ":(exclude).dart_tool"; git commit -m "B.8: whileInUse valido para operaciones foreground; solo el tracking continuo exige always"; git push
```

---

### Task 13: Cache de catálogos SubEstado (get() + Hive, fin de listeners 24 h)

**Files:**
- Modify: `lib/services/firebase_service.dart` (1114-1230)
- Modify: `lib/services/persistent_stream_manager.dart` (405-505 aprox: los 3 listeners)

**Interfaces:**
- Consumes: nada nuevo.
- Produces: los notifiers EXISTENTES conservan nombre y tipo (`subEstadosNotifier`? — verificar getter exacto, `subEstadoMovilesNotifier` L737, `subEstadoFinalizacionPedidosNotifier` L754-757) para que `home_page.dart:1059` y `order_detail_page.dart:49` no cambien.

- [ ] **Step 1: Métodos get() en firebase_service.dart**

Junto a los streams existentes, agregar (patrón para los 2 catálogos usados; el de Services NO se migra porque no tiene consumidor — borrar `getSubEstadoFinalizacionServicesStream` L1210-1230 ya que su único caller murió en Task 2):
```dart
/// Lectura única del catálogo (reemplaza el listener 24h; cache en Hive).
Future<List<Map<String, dynamic>>> getSubEstadoMovilesOnce() async {
  final escenario = sessionBox.get('escenario', defaultValue: '0');
  final snapshot = await FirebaseFirestore.instance
      .collection('SubEstadoMoviles-$escenario')
      .get();
  return snapshot.docs.map((doc) {
    final data = doc.data();
    data['id'] = doc.id;
    return data;
  }).toList();
}

Future<List<Map<String, dynamic>>> getSubEstadoFinalizacionPedidosOnce() async {
  final escenario = sessionBox.get('escenario', defaultValue: '0');
  final snapshot = await FirebaseFirestore.instance
      .collection('SubEstadoFinalizacionPedidos-$escenario')
      .orderBy('Orden')
      .get();
  return snapshot.docs.map((doc) {
    final data = doc.data();
    data['id'] = doc.id;
    return data;
  }).toList();
}
```
(adaptar `sessionBox` al acceso real usado por los streams actuales L1120; borrar los 3 métodos `*Stream()` L1114-1230 una vez migrados los consumidores en Step 2).

- [ ] **Step 2: PersistentStreamManager: cache Hive + carga única**

Reemplazar los 3 listeners (`_initializeSubEstadosListener` L438, `_initializeSubEstadoMovilesListener` L466 — que además duplicaban la MISMA colección — y el de FinalizacionPedidos L495) por:
```dart
static const _catalogTtlHours = 24;

Future<void> _loadCatalog({
  required String cacheKey,
  required Future<List<Map<String, dynamic>>> Function() fetch,
  required void Function(List<Map<String, dynamic>>) apply,
}) async {
  final box = await Hive.openBox('catalogCacheBox');
  final escenario = Hive.box('sessionBox').get('escenario', defaultValue: '0');
  final key = '$cacheKey-$escenario';

  // 1) servir cache al instante si existe
  final cached = box.get(key);
  if (cached != null) {
    apply(List<Map<String, dynamic>>.from(
        (cached['data'] as List).map((e) => Map<String, dynamic>.from(e))));
  }

  // 2) refrescar desde server solo si venció el TTL o no había cache
  final ts = cached?['ts'] as int?;
  final expired = ts == null ||
      DateTime.now().millisecondsSinceEpoch - ts > _catalogTtlHours * 3600000;
  if (expired) {
    try {
      final fresh = await fetch();
      apply(fresh);
      await box.put(key, {'data': fresh, 'ts': DateTime.now().millisecondsSinceEpoch});
    } catch (e) {
      print('⚠️ [CatalogCache] refresh $key falló (sirviendo cache): $e');
    }
  }
}
```
Y en la inicialización donde estaban los listeners:
```dart
await _loadCatalog(
  cacheKey: 'subEstadoMoviles',
  fetch: _firebaseService.getSubEstadoMovilesOnce,
  apply: (list) {
    _subEstadosNotifier.value = list;        // ambos notifiers, misma fuente:
    _subEstadoMovilesNotifier.value = list;  // elimina la doble lectura L438+L466
  },
);
await _loadCatalog(
  cacheKey: 'subEstadoFinalizacionPedidos',
  fetch: _firebaseService.getSubEstadoFinalizacionPedidosOnce,
  apply: (list) => _subEstadoFinalizacionPedidosNotifier.value = list,
);
```
Ajustar nombres exactos de notifiers privados a los reales del archivo. Quitar las suscripciones/`StreamSubscription` correspondientes de dispose y los contadores `_subEstadosReads/_subEstadoMovilesReads` si quedaron sin fuente (o dejarlos en 0 — decisión del implementer, mínimo cambio).

- [ ] **Step 3: Verificar consumidores intactos, analyze y commit**

1. `home_page.dart:1059` y `order_detail_page.dart:49` deben seguir compilando sin cambios.
2. Run: `Select-String -Path lib\**\*.dart -Pattern 'getSubEstado.*Stream'` → 0 matches.
3. Run: `flutter analyze` → sin errores nuevos. `flutter build apk --debug` → BUILD SUCCESSFUL.

```powershell
git add -A -- . ":(exclude).dart_tool"; git commit -m "Catalogos SubEstado: get() + cache Hive TTL 24h; fin de listeners permanentes y doble lectura"; git push
```

---

### Task 14: Verificación final de ACs + documentación

**Files:**
- Create: `REFACTOR_GPS_PERSISTENTE.md` (raíz del repo — doc de la release, estilo de los docs existentes)

- [ ] **Step 1: Sweep de ACs global**

```powershell
# A.8
Select-String -Path lib\**\*,android\app\src\main\** -Pattern 'logrocket' -SimpleMatch   # → 0
Select-String -Path lib\**\*.dart -Pattern 'toggle_screen_recording|grabarPantalla'      # → 0
# B.1
Select-String -Path android\app\src\main\kotlin\**\*.kt -Pattern 'startForegroundService' # → solo LocationTrackingService/FcmPushReceiver/HealthCheckWorker
Select-String -Path android\app\src\main\kotlin\**\*.kt -Pattern 'Thread\.sleep'          # → 0 en flujo GPS/FCM
Select-String -Path android\app\src\main\kotlin\**\*.kt -Pattern 'AlarmManager'           # → 0 relacionados a GPS (documentar restos si son de otros dominios)
# B.5 / B.7
Select-String -Path android\app\src\main\AndroidManifest.xml -Pattern 'MY_PACKAGE_RESTARTED|USE_EXACT_ALARM|SCHEDULE_EXACT_ALARM|QUERY_ALL_PACKAGES|LOGROCKET' # → 0
Select-String -Path android\app\src\main\kotlin\**\*.kt -Pattern 'last_interval'          # → 0
# B.7 flags
Select-String -Path android\app\src\main\kotlin\**\*.kt -Pattern '"(service_disabled|service_paused|watchdog_disabled)"' | Where-Object { $_.Path -notmatch 'ServiceStatusFlags' } # → 0
# Catalogos
Select-String -Path lib\**\*.dart -Pattern 'getSubEstado.*Stream'                          # → 0
```
Cualquier hallazgo → volver al task correspondiente y corregir antes de seguir.

- [ ] **Step 2: Build final**

Run: `flutter analyze` (sin errores nuevos vs baseline de Task 1) y `flutter build apk --debug` → BUILD SUCCESSFUL.

- [ ] **Step 3: Escribir REFACTOR_GPS_PERSISTENTE.md**

Contenido: resumen del modelo nuevo (1 FGS + cola Room + FCM restart_tracking + health-check 15 min + boot ping), tabla de eventos §8.6 y su transporte transitorio por `RegistrarErrores` (campo `tipo` dentro de `data`), los 3 pendientes de backend (endpoint dedicado, detección server-side de silencio, dedup), y la matriz de pruebas manuales en dispositivo (GPS off <30 s, matar proceso + push restart, reboot, permiso whileInUse, dos restart seguidos).

- [ ] **Step 4: Commit final**

```powershell
git add -A -- . ":(exclude).dart_tool"; git commit -m "Refactor GPS persistente: verificacion final de ACs + doc de release"; git push
```
