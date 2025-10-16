# Servicio Autónomo de Coordenadas - Independiente de Flutter

## 🎯 Objetivo

Garantizar que el servicio de envío de coordenadas continúe funcionando **independientemente** de si la aplicación Flutter está activa o no. El servicio debe:

1. ✅ Seguir enviando coordenadas cada 3 minutos aunque Flutter se cierre
2. ✅ Reiniciarse automáticamente después de un reinicio del dispositivo
3. ✅ Reiniciarse automáticamente si la app es actualizada
4. ✅ Ser 100% autónomo - no depender de Flutter para nada

---

## 🔧 Cambios Implementados

### 1. **BootReceiver.kt** (NUEVO)

**Archivo**: `android/app/src/main/kotlin/com/example/moveit/BootReceiver.kt`

**Propósito**: Escuchar eventos del sistema y reiniciar el servicio automáticamente.

**Eventos que escucha**:
- `BOOT_COMPLETED`: Dispositivo completó el reinicio
- `QUICKBOOT_POWERON`: Reinicio rápido (algunos fabricantes)
- `MY_PACKAGE_REPLACED`: App fue actualizada  
- `MY_PACKAGE_RESTARTED`: App fue forzada a reiniciar

**Funcionamiento**:
```kotlin
1. Evento del sistema se dispara (ej: BOOT_COMPLETED)
   ↓
2. BootReceiver.onReceive() se ejecuta
   ↓
3. Verifica si el servicio está deshabilitado
   - Si está deshabilitado → Sale sin hacer nada
   - Si está habilitado → Continúa
   ↓
4. Recupera parámetros guardados (movil, escenario, usuario, deviceId, interval)
   desde SharedPreferences
   ↓
5. Si hay parámetros válidos → Reprograma el AlarmManager
   ↓
6. El servicio continúa funcionando automáticamente
```

**Ejemplo de log**:
```
🔔 Evento recibido: android.intent.action.BOOT_COMPLETED
✅ Reiniciando servicio con:
   movil=693
   escenario=1000
   usuario=49618553
   deviceId=b00a68bef3451313
   interval=3min
✅ Servicio reprogramado exitosamente después de BOOT_COMPLETED
```

---

### 2. **Modificación en LocationHelper.scheduleLocationAlarm()**

**Archivo**: `android/app/src/main/kotlin/com/example/moveit/LocationHelper.kt`

**Cambio**: Ahora **guarda los parámetros** en SharedPreferences cada vez que se programa una alarma.

**Código agregado**:
```kotlin
fun scheduleLocationAlarm(...) {
    // 💾 GUARDAR parámetros para poder reiniciar después de reboot o cierre de app
    val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
    prefs.edit().apply {
        putString("last_movil", movil)
        putString("last_escenario", escenario)
        putString("last_usuario", usuario)
        putString("last_deviceId", deviceId)
        putInt("last_interval", intervalMinutes)
        putLong("last_schedule_time", System.currentTimeMillis())
    }.apply()
    Log.d(TAG, "💾 Parámetros guardados para auto-reinicio: movil=$movil, interval=${intervalMinutes}min")
    
    // ... resto del código de programación de alarma
}
```

**Por qué es importante**: Sin esto, después de un reboot el BootReceiver no sabría qué parámetros usar para reiniciar el servicio.

---

### 3. **Modificación en AndroidManifest.xml**

**Archivo**: `android/app/src/main/AndroidManifest.xml`

**Cambio**: Registrar el BootReceiver para que el sistema Android lo active.

**Código agregado**:
```xml
<!-- 🆕 Receiver para reiniciar servicio después de reboot o cierre de app -->
<receiver
    android:name=".BootReceiver"
    android:exported="true"
    android:enabled="true">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED" />
        <action android:name="android.intent.action.QUICKBOOT_POWERON" />
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
        <action android:name="android.intent.action.MY_PACKAGE_RESTARTED" />
        <category android:name="android.intent.category.DEFAULT" />
    </intent-filter>
</receiver>
```

**Nota**: `exported="true"` permite que el sistema Android active el receiver.

---

## 📊 Flujo Completo del Sistema

### Escenario 1: Uso Normal (App Flutter activa)

```
Flutter App activa
    ↓
Usuario hace login
    ↓
Flutter llama startLocationUpdates() con parámetros
    ↓
LocationHelper.scheduleLocationAlarm() se ejecuta
    ↓
💾 Parámetros guardados en SharedPreferences
    ↓
AlarmManager programado para cada 3 minutos
    ↓
Cada 3 minutos:
    ├─ AlarmManager dispara LocationReceiver
    ├─ LocationReceiver inicia ForegroundLocationService (con EXECUTE_GPS=true)
    ├─ ForegroundLocationService ejecuta getCurrentLocation()
    ├─ Coordenadas obtenidas y enviadas a API
    ├─ LocationReceiver reprograma siguiente alarma
    └─ Servicio se detiene hasta próxima alarma
```

### Escenario 2: Flutter se Cierra (Nueva Implementación ✅)

```
Coordenadas enviándose cada 3 min ✅
    ↓
Usuario cierra la app Flutter (10:56)
    ↓
❌ Flutter VM muere (11:16)
    ↓
✅ AlarmManager sigue activo (NO depende de Flutter)
    ↓
✅ A las 10:59 (3 min después):
    ├─ AlarmManager dispara LocationReceiver
    ├─ LocationReceiver inicia ForegroundLocationService
    ├─ Coordenadas obtenidas y enviadas
    ├─ Alarma reprogramada para 11:02
    └─ Servicio se detiene
    ↓
✅ A las 11:02:
    ├─ AlarmManager dispara LocationReceiver
    ├─ Coordenadas obtenidas y enviadas
    └─ ... continúa indefinidamente
```

**Resultado**: Las coordenadas siguen enviándose cada 3 minutos **aunque Flutter esté muerto**.

### Escenario 3: Dispositivo Reinicia

```
Dispositivo reinicia
    ↓
Sistema Android carga
    ↓
🔔 Sistema dispara intent: BOOT_COMPLETED
    ↓
BootReceiver.onReceive() se activa automáticamente
    ↓
BootReceiver recupera parámetros guardados:
    ├─ movil = "693"
    ├─ escenario = "1000"
    ├─ usuario = "49618553"
    ├─ deviceId = "b00a68bef3451313"
    └─ interval = 3
    ↓
BootReceiver llama LocationHelper.scheduleLocationAlarm()
    ↓
✅ AlarmManager programado nuevamente
    ↓
✅ Servicio continúa enviando coordenadas cada 3 min
```

**Resultado**: Después del reinicio, el servicio **se reactiva automáticamente** sin tocar la app.

### Escenario 4: App Actualizada

```
Usuario actualiza la app desde Play Store
    ↓
Sistema instala nueva versión
    ↓
🔔 Sistema dispara intent: MY_PACKAGE_REPLACED
    ↓
BootReceiver.onReceive() se activa
    ↓
BootReceiver reprograma AlarmManager con parámetros guardados
    ↓
✅ Servicio continúa funcionando con la nueva versión
```

---

## 🔍 Verificación y Testing

### Cómo Verificar que Funciona

#### 1. **Test: Cerrar Flutter y verificar que sigue enviando**

```bash
# 1. Instalar APK
flutter install

# 2. Hacer login en la app

# 3. Ver logs y esperar primer envío de coordenadas
adb logcat | Select-String "LocationHelper|COORDINATES_SENT"

# Deberías ver algo como:
# 11:00:10 ✅ API exitosa: {"OK":0,"message":""}

# 4. Cerrar la app completamente (forzar cierre desde Settings)
adb shell am force-stop uy.riogas.delivery

# 5. Verificar que Flutter está muerto
adb logcat | Select-String "flutter"  # No deberías ver nada

# 6. Esperar 3 minutos y ver logs
adb logcat | Select-String "LocationHelper"

# Deberías ver:
# 11:03:10 ⏰ AlarmManager disparado
# 11:03:10 🔄 Modo ALARMMANAGER: Ejecutando getCurrentLocation()...
# 11:03:11 📍 Coordenadas obtenidas: ...
# 11:03:14 ✅ API exitosa: {"OK":0,"message":""}

# 7. Esperar otros 3 minutos
# 11:06:10 ⏰ AlarmManager disparado
# ... se repite
```

**Resultado esperado**: Las coordenadas siguen enviándose cada 3 minutos aunque Flutter esté muerto.

#### 2. **Test: Reiniciar dispositivo**

```bash
# 1. Con el servicio activo, reiniciar dispositivo
adb reboot

# 2. Esperar que el dispositivo reinicie y ver logs
adb logcat | Select-String "BootReceiver|LocationHelper"

# Deberías ver:
# 🔔 Evento recibido: android.intent.action.BOOT_COMPLETED
# ✅ Reiniciando servicio con: movil=693, interval=3min
# ✅ Servicio reprogramado exitosamente después de BOOT_COMPLETED
# 💾 Parámetros guardados para auto-reinicio: movil=693, interval=3min
# 🔁 AlarmManager EXACTO (Android 12+) configurado para 3 min

# 3. Esperar 3 minutos desde el reboot
# Deberías ver:
# ⏰ AlarmManager disparado
# 📍 Coordenadas obtenidas: ...
# ✅ API exitosa: {"OK":0,"message":""}
```

**Resultado esperado**: El servicio se reactiva automáticamente después del reboot.

#### 3. **Test: Verificar parámetros guardados**

```bash
# Ver SharedPreferences guardados
adb shell "run-as uy.riogas.delivery cat /data/data/uy.riogas.delivery/shared_prefs/config.xml"

# Deberías ver algo como:
# <map>
#   <string name="last_movil">693</string>
#   <string name="last_escenario">1000</string>
#   <string name="last_usuario">49618553</string>
#   <string name="last_deviceId">b00a68bef3451313</string>
#   <int name="last_interval" value="3" />
#   <long name="last_schedule_time" value="1760451234567" />
# </map>
```

---

## 🆘 Troubleshooting

### Problema: El servicio no se reinicia después de reboot

**Posibles causas**:

1. **Permisos de batería**: Algunos fabricantes (Samsung, Xiaomi, Huawei) tienen optimizaciones agresivas.
   
   **Solución**: 
   - Ir a Settings → Apps → RioGas Delivery → Battery
   - Seleccionar "Unrestricted" o "No optimization"

2. **Permisos de alarmas exactas**: Android 12+ requiere permiso especial.
   
   **Verificar**:
   ```bash
   adb shell dumpsys alarm | Select-String "uy.riogas"
   ```
   
   **Si no aparece nada**, el usuario debe ir a:
   - Settings → Apps → RioGas Delivery → Alarms & reminders
   - Activar "Allow setting alarms and reminders"

3. **Boot Receiver no registrado**: Verificar que el BootReceiver esté en el manifest.
   
   **Verificar**:
   ```bash
   adb shell dumpsys package uy.riogas.delivery | Select-String "BootReceiver"
   ```
   
   Debería mostrar:
   ```
   Receiver #0:
     com.example.moveit.BootReceiver filter 12345
       Action: android.intent.action.BOOT_COMPLETED
       Action: android.intent.action.QUICKBOOT_POWERON
       ...
   ```

### Problema: El servicio se detiene después de 1 hora

**Causa**: Probablemente Firebase Auth expiró y la app Flutter crasheó, pero el servicio Kotlin **debería seguir funcionando**.

**Verificación**:
```bash
# Ver si hay errores de Flutter
adb logcat | Select-String "flutter|FATAL"

# Ver si el servicio Kotlin sigue activo
adb logcat | Select-String "LocationReceiver|ForegroundLocationService"
```

**Solución**: 
- Si el problema es Flutter (Firebase Auth), eso ya lo arreglamos antes con el refresh proactivo del token.
- El servicio Kotlin ahora es **independiente** y no debería verse afectado por problemas de Flutter.

### Problema: No hay logs de LocationReceiver después de cerrar Flutter

**Causa**: El AlarmManager fue cancelado o no se programó correctamente.

**Verificación**:
```bash
# Ver alarmas activas
adb shell dumpsys alarm | Select-String -Context 5 "LocationReceiver"
```

Debería mostrar algo como:
```
RTC_WAKEUP #0: Alarm{abc123 type 0 when 1760451234567 uy.riogas.delivery}
  tag=*alarm*:android.intent.action.BOOT_COMPLETED
  type=0 whenElapsed=+3m0s0ms when=2025-10-14 11:03:10
  window=0 repeatInterval=0 count=0 flags=0x5
  operation=PendingIntent{def456: PendingIntentRecord{789 uy.riogas.delivery broadcastIntent}}
```

**Si NO aparece**, ejecutar manualmente desde la app:
```dart
// En Flutter
await _locationChannel.invokeMethod('startLocationUpdates', {
  'movil': '693',
  'escenario': '1000',
  'usuario': '49618553',
  'deviceId': 'b00a68bef3451313',
  'intervalMinutes': 3,
});
```

---

## 📝 Resumen de Cambios

| Archivo | Cambio | Propósito |
|---------|--------|-----------|
| `BootReceiver.kt` | **NUEVO** | Escuchar eventos del sistema y reiniciar servicio |
| `LocationHelper.kt` | Guardar parámetros en SharedPreferences | Persistir configuración para reinicio automático |
| `AndroidManifest.xml` | Registrar BootReceiver | Permitir que Android active el receiver |

---

## ✅ Resultado Final

**ANTES** (Problema):
```
10:47 → Coordenadas enviadas ✅
10:50 → Coordenadas enviadas ✅
10:53 → Coordenadas enviadas ✅
10:56 → Coordenadas enviadas ✅
11:16 → Flutter se cierra ❌
11:19 → ❌ NO HAY COORDENADAS (servicio muerto)
11:22 → ❌ NO HAY COORDENADAS
11:45 → ❌ NO HAY COORDENADAS
```

**DESPUÉS** (Solución):
```
10:47 → Coordenadas enviadas ✅
10:50 → Coordenadas enviadas ✅
10:53 → Coordenadas enviadas ✅
10:56 → Coordenadas enviadas ✅
11:16 → Flutter se cierra (pero servicio sigue activo)
11:19 → ✅ Coordenadas enviadas (AlarmManager sigue funcionando)
11:22 → ✅ Coordenadas enviadas
11:45 → ✅ Coordenadas enviadas
... continúa indefinidamente ...
```

---

## 🚀 Próximos Pasos

1. **Compilar APK** con estos cambios:
   ```bash
   cd C:\Users\jgomez\Documents\Projects\AppTFlutter\appmovil
   flutter build apk --release
   ```

2. **Instalar en dispositivo**:
   ```bash
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```

3. **Hacer login** en la app

4. **Cerrar la app completamente**:
   ```bash
   adb shell am force-stop uy.riogas.delivery
   ```

5. **Esperar 3 minutos** y verificar logs:
   ```bash
   adb logcat | Select-String "LocationReceiver|LocationHelper|COORDINATES"
   ```

6. **Deberías ver** que las coordenadas siguen enviándose aunque Flutter esté muerto.

---

**Fecha de Implementación**: 14 de Octubre, 2025  
**Autor**: GitHub Copilot + jgomez  
**Status**: ✅ Implementado, listo para testing
