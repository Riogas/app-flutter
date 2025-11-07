# 🚨 Sistema de Logout Remoto via FCM - Documentación Completa

## 📋 Índice
1. [Descripción General](#descripción-general)
2. [Arquitectura](#arquitectura)
3. [Componentes Implementados](#componentes-implementados)
4. [Flujo de Ejecución](#flujo-de-ejecución)
5. [Código Implementado](#código-implementado)
6. [Cómo Usar](#cómo-usar)
7. [Testing](#testing)
8. [Troubleshooting](#troubleshooting)

---

## 📝 Descripción General

El **Sistema de Logout Remoto via FCM** permite cerrar sesiones de usuarios remotamente desde el servidor mediante notificaciones push de Firebase Cloud Messaging (FCM). Cuando el servidor envía el comando `logout_user`, la aplicación:

1. **Detiene todos los servicios** (GPS y CriticalLog)
2. **Setea flags de control** (`service_disabled=true`, `watchdog_disabled=true`)
3. **Ejecuta el mismo flujo de logout manual** (RegistrarCierre, Firestore, SessionService, Hive)
4. **Cierra la aplicación automáticamente**

---

## 🏗️ Arquitectura

### Diagrama de Flujo

```
FCM Push Notification          FcmPushReceiver.kt           MainActivity.kt
"logout_user" command      →   handleLogoutUser()      →   BroadcastReceiver
       ↓                              ↓                          ↓
1. Stop GPS Service             2. Stop CriticalLog        3. Send Broadcast
2. Cancel Alarms                3. Set flags               4. Notify Flutter
3. Set watchdog_disabled=true   4. Log actions                  ↓
                                                        RemoteLogoutListener.dart
                                                                ↓
                                                        LogoutService.executeLogout()
                                                                ↓
                                                   (7 pasos de cierre de sesión)
                                                                ↓
                                                        Exit App (exit(0))
```

### Capas del Sistema

1. **Capa de Red (FCM)**: Recibe notificaciones push
2. **Capa Nativa (Kotlin)**: Detiene servicios, setea flags, notifica
3. **Capa de Comunicación (MethodChannel)**: Kotlin ↔ Flutter
4. **Capa de Lógica (Dart)**: Ejecuta logout completo
5. **Capa de Datos (Firestore/Hive)**: Registra cierre, limpia datos

---

## 🔧 Componentes Implementados

### 1. **FcmPushReceiver.kt** (Kotlin)
**Ubicación**: `android/app/src/main/kotlin/com/riogas/appmovil/FcmPushReceiver.kt`

**Responsabilidad**: Captura el mensaje FCM "logout_user" y ejecuta `handleLogoutUser()`

**Métodos principales**:
```kotlin
private fun handleLogoutUser(movil: String, escenario: String, usuario: String, deviceId: String)
```

**Acciones**:
- ✅ Detiene `ForegroundLocationService`
- ✅ Cancela alarmas de `LocationReceiver` y `CriticalLogAlarmReceiver`
- ✅ Setea `service_disabled=true` y `watchdog_disabled=true`
- ✅ Envía broadcast `com.riogas.appmovil.REMOTE_LOGOUT`
- ✅ Loguea todos los pasos en `CriticalLogger`

---

### 2. **MainActivity.kt** (Kotlin)
**Ubicación**: `android/app/src/main/kotlin/com/example/moveit/MainActivity.kt`

**Responsabilidad**: Registra un `BroadcastReceiver` y notifica a Flutter

**Propiedades agregadas**:
```kotlin
private val REMOTE_LOGOUT_CHANNEL = "com.riogas.appmovil/remote_logout"
private var remoteLogoutChannel: MethodChannel? = null
private var remoteLogoutReceiver: BroadcastReceiver? = null
```

**Métodos agregados**:
- `setupRemoteLogoutReceiver()`: Registra el BroadcastReceiver
- `onDestroy()`: Desregistra el receiver (evita memory leaks)

**Flujo**:
1. Recibe broadcast `com.riogas.appmovil.REMOTE_LOGOUT`
2. Extrae datos del Intent (movil, escenario, usuario, deviceId)
3. Notifica a Flutter via `remoteLogoutChannel.invokeMethod("onRemoteLogout", data)`

---

### 3. **RemoteLogoutListener.dart** (Flutter)
**Ubicación**: `lib/services/remote_logout_listener.dart`

**Responsabilidad**: Escucha eventos del MethodChannel y ejecuta `LogoutService`

**Método principal**:
```dart
static Future<void> initialize()
```

**Handler**:
```dart
static Future<void> _handleMethodCall(MethodCall call)
```

**Flujo**:
1. Recibe evento `onRemoteLogout` desde Kotlin
2. Valida datos (movil, usuario no vacíos)
3. Ejecuta `LogoutService.executeLogout(isRemoteLogout: true)`

---

### 4. **LogoutService.dart** (Flutter)
**Ubicación**: `lib/services/logout_service.dart`

**Responsabilidad**: Centraliza la lógica de logout (manual y remoto)

**Método principal**:
```dart
static Future<void> executeLogout({
  required bool isRemoteLogout,
  String? nombreUsuario,
  String? idUsuario,
  String? deviceId,
})
```

**7 Pasos de Cierre de Sesión**:
1. ✅ **Detener servicios** (solo si logout manual, en remoto ya fueron detenidos por Kotlin)
2. ✅ **RegistrarCierre** (llamar a API con tipo 'Controlado')
3. ✅ **Actualizar documentos Firestore** (agregar campo 'logout', mover 'activo' a timestamp)
4. ✅ **SessionService.saveSession** (registrar cierre)
5. ✅ **SessionService.cerrarSesion** (finalizar sesión)
6. ✅ **Limpiar flags de servicio** (ServiceStatusFlags)
7. ✅ **Eliminar Hive boxes** (sessionBox, constantBox, mensajesBox, failedRequestsBox)
8. ✅ **Cerrar aplicación** (`exit(0)`)

---

### 5. **settings_page.dart** (Refactorizado)
**Ubicación**: `lib/pages/settings_page.dart`

**Cambio principal**: Método `_logout()` refactorizado para usar `LogoutService`

**Antes** (120+ líneas de código duplicado):
```dart
Future<void> _logout() async {
  // 120+ líneas de lógica de logout...
}
```

**Después** (5 líneas):
```dart
Future<void> _logout() async {
  bool? confirmLogout = await _showLogoutConfirmationDialog();
  if (confirmLogout == true) {
    await LogoutService.executeLogout(
      isRemoteLogout: false,
      nombreUsuario: nombreUsuario,
      idUsuario: idUsuario,
      deviceId: deviceId,
    );
  }
}
```

---

## 🔄 Flujo de Ejecución Completo

### Paso a Paso

#### 1. **Servidor envía FCM push notification**
```json
{
  "to": "<fcm_token>",
  "data": {
    "action": "logout_user"
  }
}
```

**⚠️ Importante**: Solo se envía la acción, sin parámetros. Los datos se obtienen de SharedPreferences/Hive.

#### 2. **FcmPushReceiver.kt recibe el mensaje**
```kotlin
when (action) {
    "logout_user" -> {
        handleLogoutUser(remoteMessage)  // Sin parámetros
    }
}
```

#### 3. **handleLogoutUser() ejecuta acciones nativas**
```kotlin
// Obtener datos de SharedPreferences (ya están guardados desde el login)
val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
val movil = prefs.getString("last_movil", "") ?: ""
val escenario = prefs.getString("last_escenario", "") ?: ""
val usuario = prefs.getString("last_usuario", "") ?: ""
val deviceId = prefs.getString("last_deviceId", "") ?: ""

// 1. Detener GPS Service
context.stopService(Intent(context, ForegroundLocationService::class.java))

// 2. Cancelar alarmas
alarmManager.cancel(locationIntent)
alarmManager.cancel(criticalLogIntent)

// 3. Setear flags (🚫 CRÍTICO: esto inhabilita reinicio automático)
prefs.edit().apply {
    putBoolean("service_disabled", true)
    putBoolean("watchdog_disabled", true)  // 🔒 Bloquea watchdog hasta nuevo login
    apply()
}

// 4. Enviar broadcast (sin parámetros, Flutter obtiene de Hive)
val intent = Intent("com.riogas.appmovil.REMOTE_LOGOUT")
context.sendBroadcast(intent)
```

#### 4. **MainActivity.kt recibe el broadcast**
```kotlin
remoteLogoutReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        // Solo envía señal, sin parámetros
        remoteLogoutChannel?.invokeMethod("onRemoteLogout", mapOf(
            "timestamp" to System.currentTimeMillis()
        ))
    }
}
```

#### 5. **RemoteLogoutListener.dart recibe el evento**
```dart
static Future<void> _handleMethodCall(MethodCall call) async {
  if (call.method == 'onRemoteLogout') {
    // Sin parámetros, LogoutService obtiene todo de Hive
    await LogoutService.executeLogout(isRemoteLogout: true);
  }
}
```

#### 6. **LogoutService.executeLogout() completa el cierre**
```dart
// 0. Obtener datos de Hive (source of truth)
var sessionBox = await Hive.openBox('sessionBox');
final movil = sessionBox.get('movil') ?? "0";
final escenario = sessionBox.get('escenario') ?? "0";
final usuario = sessionBox.get('username') ?? "string";
final deviceId = sessionBox.get('deviceId') ?? "";

// 1. Skip detener servicios (ya detenidos por Kotlin)
// 2. RegistrarCierre
await RioGasService.registrarCierre(movil, deviceId, usuario, timestamp, 'Remoto')

// 3. Firestore updates
await movilActivoDocRef.delete();
await usuarioActivoDocRef.delete();

// 4. SessionService
await sessionService.saveSession(...)
await sessionService.cerrarSesion(...)

// 5. Clear flags
await RioGasService.clearAllServiceFlags()

// 6. Delete Hive
await sessionBox.deleteFromDisk()
await constantBox.deleteFromDisk()
await mensajesBox.deleteFromDisk()
await failedRequestsBox.deleteFromDisk()

// 7. Exit app
exit(0)
```

---

## 💻 Código Implementado

### FcmPushReceiver.kt - handleLogoutUser()
```kotlin
private fun handleLogoutUser(movil: String, escenario: String, usuario: String, deviceId: String) {
    val context = applicationContext
    Log.d("FCM", "🚨 [LOGOUT_USER] Cerrando sesión remotamente...")
    
    com.riogas.appmovil.CriticalLogger.i(
        "FcmPushReceiver",
        "REMOTE_LOGOUT_INITIATED",
        mapOf(
            "movil" to movil,
            "escenario" to escenario,
            "usuario" to usuario,
            "deviceId" to deviceId
        )
    )
    
    // 1. Detener ForegroundLocationService (GPS)
    try {
        val stopServiceIntent = Intent(context, com.example.moveit.ForegroundLocationService::class.java)
        context.stopService(stopServiceIntent)
        Log.d("FCM", "✅ GPS Service detenido")
    } catch (e: Exception) {
        Log.e("FCM", "❌ Error deteniendo GPS Service", e)
    }
    
    // 2. Cancelar alarma de LocationReceiver
    try {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val locationIntent = Intent(context, com.example.moveit.LocationReceiver::class.java)
        val locationPendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            locationIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(locationPendingIntent)
        Log.d("FCM", "✅ Alarma de LocationReceiver cancelada")
    } catch (e: Exception) {
        Log.e("FCM", "❌ Error cancelando alarma de LocationReceiver", e)
    }
    
    // 3. Cancelar alarma de CriticalLogAlarmReceiver
    try {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val criticalLogIntent = Intent(context, com.riogas.appmovil.CriticalLogAlarmReceiver::class.java)
        val criticalLogPendingIntent = PendingIntent.getBroadcast(
            context,
            com.riogas.appmovil.CriticalLogAlarmReceiver.REQUEST_CODE,
            criticalLogIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(criticalLogPendingIntent)
        Log.d("FCM", "✅ Alarma de CriticalLogAlarmReceiver cancelada")
    } catch (e: Exception) {
        Log.e("FCM", "❌ Error cancelando alarma de CriticalLog", e)
    }
    
    // 4. Setear flags en SharedPreferences
    try {
        val prefs = context.getSharedPreferences("config", Context.MODE_PRIVATE)
        prefs.edit().apply {
            putBoolean("service_disabled", true)
            putBoolean("watchdog_disabled", true)
            apply()
        }
        Log.d("FCM", "✅ Flags service_disabled y watchdog_disabled seteadas")
    } catch (e: Exception) {
        Log.e("FCM", "❌ Error seteando flags", e)
    }
    
    // 5. Enviar broadcast a Flutter
    try {
        val broadcastIntent = Intent("com.riogas.appmovil.REMOTE_LOGOUT").apply {
            putExtra("movil", movil)
            putExtra("escenario", escenario)
            putExtra("usuario", usuario)
            putExtra("deviceId", deviceId)
            putExtra("logout_type", "remote_fcm")
        }
        context.sendBroadcast(broadcastIntent)
        Log.d("FCM", "✅ Broadcast REMOTE_LOGOUT enviado a Flutter")
        
        com.riogas.appmovil.CriticalLogger.i(
            "FcmPushReceiver",
            "REMOTE_LOGOUT_BROADCAST_SENT",
            mapOf(
                "broadcast_action" to "com.riogas.appmovil.REMOTE_LOGOUT",
                "movil" to movil,
                "usuario" to usuario
            )
        )
    } catch (e: Exception) {
        Log.e("FCM", "❌ Error enviando broadcast", e)
    }
    
    Log.d("FCM", "🚨 [LOGOUT_USER] Proceso de logout remoto completado")
}
```

---

### MainActivity.kt - setupRemoteLogoutReceiver()
```kotlin
private fun setupRemoteLogoutReceiver() {
    remoteLogoutReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.riogas.appmovil.REMOTE_LOGOUT") {
                Log.d("MainActivity", "🚨 [REMOTE_LOGOUT] Broadcast recibido desde FcmPushReceiver")
                
                val movil = intent.getStringExtra("movil") ?: ""
                val escenario = intent.getStringExtra("escenario") ?: ""
                val usuario = intent.getStringExtra("usuario") ?: ""
                val deviceId = intent.getStringExtra("deviceId") ?: ""
                val logoutType = intent.getStringExtra("logout_type") ?: "remote_fcm"
                
                remoteLogoutChannel?.invokeMethod("onRemoteLogout", mapOf(
                    "movil" to movil,
                    "escenario" to escenario,
                    "usuario" to usuario,
                    "deviceId" to deviceId,
                    "logoutType" to logoutType,
                    "timestamp" to System.currentTimeMillis()
                ))
                
                Log.d("MainActivity", "🚨 [REMOTE_LOGOUT] Notificación enviada a Flutter")
            }
        }
    }
    
    val intentFilter = IntentFilter("com.riogas.appmovil.REMOTE_LOGOUT")
    registerReceiver(remoteLogoutReceiver, intentFilter)
    Log.d("MainActivity", "✅ BroadcastReceiver de logout remoto registrado")
}
```

---

## 🚀 Cómo Usar

### 1. **Enviar comando FCM desde el servidor**

**IMPORTANTE**: Solo se envía la acción `logout_user`, sin parámetros adicionales.
Los datos (movil, escenario, usuario, deviceId) se obtienen de Hive en la app.

**Ejemplo con Firebase Admin SDK (Node.js)**:
```javascript
const admin = require('firebase-admin');

async function sendRemoteLogout(fcmToken) {
  const message = {
    token: fcmToken,
    data: {
      action: 'logout_user'  // Solo la acción, igual que force_gps_execution
    }
  };
  
  try {
    const response = await admin.messaging().send(message);
    console.log('✅ Logout remoto enviado:', response);
  } catch (error) {
    console.error('❌ Error enviando logout remoto:', error);
  }
}

// Uso
sendRemoteLogout('fcm_token_del_usuario');
```

**Ejemplo con cURL**:
```bash
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=YOUR_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "fcm_token_del_usuario",
    "data": {
      "action": "logout_user"
    }
  }'
```

**⚠️ Nota importante**: Al igual que `force_gps_execution`, solo se envía la acción. La app obtiene automáticamente todos los datos necesarios (movil, escenario, usuario, deviceId) desde Hive.

---

### 2. **Verificar logs**

#### Kotlin (Logcat):
```
D/FCM: 🚨 [LOGOUT_USER] Cerrando sesión remotamente...
D/FCM: ✅ GPS Service detenido
D/FCM: ✅ Alarma de LocationReceiver cancelada
D/FCM: ✅ Alarma de CriticalLogAlarmReceiver cancelada
D/FCM: ✅ Flags service_disabled y watchdog_disabled seteadas
D/FCM: ✅ Broadcast REMOTE_LOGOUT enviado a Flutter
D/MainActivity: 🚨 [REMOTE_LOGOUT] Broadcast recibido desde FcmPushReceiver
D/MainActivity: 🚨 [REMOTE_LOGOUT] Notificación enviada a Flutter
```

#### Flutter (Console):
```
🚨 [REMOTE_LOGOUT] Evento recibido desde Kotlin
🚨 [REMOTE_LOGOUT] Datos recibidos:
   - movil: 123
   - escenario: 456
   - usuario: juan.gomez
   - deviceId: android-abc123
   - logoutType: remote_fcm
🚨 [REMOTE_LOGOUT] Ejecutando LogoutService.executeLogout()...
🚨 [LOGOUT_SERVICE] Iniciando logout (remoto)...
🚨 [LOGOUT_SERVICE] Paso 2/7: Llamando a RegistrarCierre...
🚨 [LOGOUT_SERVICE] Paso 3/7: Actualizando documentos Firestore...
🚨 [LOGOUT_SERVICE] Paso 4/7: Guardando sesión en SessionService...
🚨 [LOGOUT_SERVICE] Paso 5/7: Cerrando sesión en SessionService...
🚨 [LOGOUT_SERVICE] Paso 6/7: Limpiando flags de servicio...
🚨 [LOGOUT_SERVICE] Paso 7/7: Eliminando Hive boxes y cerrando app...
✅ [REMOTE_LOGOUT] Logout completado exitosamente
```

---

## 🧪 Testing

### Test Manual

1. **Login en la app** con usuario de prueba
2. **Obtener FCM token** del dispositivo (desde logs o Firestore)
3. **Enviar comando FCM** desde servidor/Postman
4. **Verificar**:
   - ✅ GPS Service se detiene
   - ✅ Alarmas se cancelan
   - ✅ Flags se setean (`service_disabled=true`, `watchdog_disabled=true`)
   - ✅ Broadcast se envía y se recibe en Flutter
   - ✅ LogoutService ejecuta los 7 pasos
   - ✅ App se cierra automáticamente
5. **Reabrir app** y verificar:
   - ✅ Redirige a LoginPage
   - ✅ Hive boxes vacías
   - ✅ Firestore: documento "activo" eliminado y movido a timestamp

---

### Test de Integración

```dart
// test/services/logout_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:appmovil/services/logout_service.dart';

void main() {
  group('LogoutService', () {
    test('executeLogout con isRemoteLogout=true debe ejecutar 7 pasos', () async {
      // TODO: Implementar mock de RioGasService, SessionService, Hive
      // Verificar que cada paso se ejecute correctamente
    });
  });
}
```

---

## 🐛 Troubleshooting

### Problema 1: Broadcast no se recibe en Flutter
**Causa**: MainActivity no está en foreground o BroadcastReceiver no registrado

**Solución**:
1. Verificar que `setupRemoteLogoutReceiver()` se llama en `onCreate()`
2. Verificar logs de Kotlin: "✅ BroadcastReceiver de logout remoto registrado"
3. Si la app está en background, el broadcast igualmente se recibe

---

### Problema 2: App no se cierra después de logout
**Causa**: `exit(0)` bloqueado o error en pasos anteriores

**Solución**:
1. Verificar logs de Flutter para ver en qué paso falla
2. Revisar permisos de Firestore y Hive
3. Agregar try-catch más específicos en `LogoutService.executeLogout()`

---

### Problema 3: Servicios no se detienen
**Causa**: Flags `service_disabled` o `watchdog_disabled` no se setean

**Solución**:
1. Verificar en Kotlin que `prefs.edit().apply()` se ejecuta
2. Verificar en Logcat: "✅ Flags service_disabled y watchdog_disabled seteadas"
3. Verificar en Firestore que el documento "activo" se elimina correctamente

---

### Problema 4: FCM no llega a la app
**Causa**: Token FCM inválido, servidor mal configurado, o app en Doze mode

**Solución**:
1. Verificar que el token FCM del usuario esté actualizado en Firestore
2. Verificar que el servidor usa el Server Key correcto
3. Si la app está en Doze mode, FCM puede tardar en llegar (usar alta prioridad)

---

## 📊 Monitoreo y Logs

### CriticalLogger (Kotlin)
Todos los pasos del logout remoto se loguean en CriticalLogger:

```kotlin
com.riogas.appmovil.CriticalLogger.i(
    "FcmPushReceiver",
    "REMOTE_LOGOUT_INITIATED",
    mapOf(
        "movil" to movil,
        "usuario" to usuario,
        "timestamp" to System.currentTimeMillis().toString()
    )
)
```

Estos logs se envían automáticamente a Firestore en `CriticalLogs-{escenario}` cada 30 segundos.

---

### Firestore Documents
Al cerrar sesión, se crea un documento timestamped en Firestore:

**Antes del logout**:
```
Sesiones-456/
  20250122/
    Movil-123/
      activo { movil: "123", usuario: "juan.gomez", ... }
```

**Después del logout**:
```
Sesiones-456/
  20250122/
    Movil-123/
      14:35:42 { movil: "123", usuario: "juan.gomez", logout: "Controlado", ... }
```

---

## ✅ Checklist de Implementación

- [x] FcmPushReceiver.kt - handleLogoutUser() agregado
- [x] MainActivity.kt - BroadcastReceiver configurado
- [x] RemoteLogoutListener.dart - Listener de MethodChannel creado
- [x] LogoutService.dart - Servicio centralizado de logout
- [x] settings_page.dart - Refactorizado para usar LogoutService
- [x] main.dart - RemoteLogoutListener inicializado
- [x] Documentación completa (este archivo)

---

## 🔮 Mejoras Futuras

1. **Confirmación de logout**: Enviar un evento de vuelta al servidor confirmando que el logout se completó
2. **Retry automático**: Si el logout falla (ej. sin internet), reintentar cuando haya conexión
3. **Analytics**: Registrar métricas de cuántos logouts remotos se ejecutaron exitosamente
4. **Notificación al usuario**: Mostrar un toast/dialog indicando "Sesión cerrada remotamente por el administrador"

---

## 📚 Referencias

- [Firebase Cloud Messaging](https://firebase.google.com/docs/cloud-messaging)
- [MethodChannel Flutter](https://docs.flutter.dev/platform-integration/platform-channels)
- [BroadcastReceiver Android](https://developer.android.com/guide/components/broadcasts)
- [Hive Flutter](https://docs.hivedb.dev/)

---

**Última actualización**: 2025-01-22  
**Versión**: 1.0.0  
**Autor**: Sistema de Flags y Logout Remoto
