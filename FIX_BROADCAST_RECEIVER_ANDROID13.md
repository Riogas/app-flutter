# 🔒 Fix: BroadcastReceiver Crash en Android 13+

## 🚨 Problema Detectado

**Crash al iniciar la app** con el siguiente error:

```
E AndroidRuntime: FATAL EXCEPTION: main
E AndroidRuntime: Caused by: java.lang.SecurityException: 
com.example.moveit: One of RECEIVER_EXPORTED or RECEIVER_NOT_EXPORTED 
should be specified when a receiver isn't being registered exclusively 
for system broadcasts

E AndroidRuntime: at com.example.moveit.MainActivity.setupRemoteLogoutReceiver(MainActivity.kt:1057)
E AndroidRuntime: at com.example.moveit.MainActivity.onCreate(MainActivity.kt:1013)
```

---

## 📋 Causa del Error

### Android 13 (API 33) - Nueva Política de Seguridad

Desde **Android 13 (API 33 / TIRAMISU)**, cuando registras un `BroadcastReceiver` **dinámicamente** (en runtime con `registerReceiver()`), **DEBES especificar** uno de estos flags:

1. **`Context.RECEIVER_EXPORTED`**
   - El receiver puede recibir broadcasts de **otras aplicaciones**
   - Uso: Cuando necesitas comunicación inter-app
   - ⚠️ Mayor riesgo de seguridad

2. **`Context.RECEIVER_NOT_EXPORTED`**
   - El receiver **SOLO** puede recibir broadcasts **internos** de tu propia app
   - Uso: Comunicación interna (como nuestro caso)
   - ✅ Más seguro

### ¿Por qué falló en tu app?

En `MainActivity.kt`, el método `setupRemoteLogoutReceiver()` registraba el receiver así:

```kotlin
val intentFilter = IntentFilter("com.riogas.appmovil.REMOTE_LOGOUT")
registerReceiver(remoteLogoutReceiver, intentFilter) // ❌ Sin flag
```

Esto funcionaba en **Android 12 y anteriores**, pero en **Android 13+** causa un `SecurityException`.

---

## ✅ Solución Implementada

### Código Corregido

```kotlin
private fun setupRemoteLogoutReceiver() {
    remoteLogoutReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.riogas.appmovil.REMOTE_LOGOUT") {
                Log.d("MainActivity", "🚨 [REMOTE_LOGOUT] Broadcast recibido desde FcmPushReceiver")
                
                // Notificar a Flutter via MethodChannel
                remoteLogoutChannel?.invokeMethod("onRemoteLogout", mapOf(
                    "timestamp" to System.currentTimeMillis()
                ))
                
                Log.d("MainActivity", "🚨 [REMOTE_LOGOUT] Notificación enviada a Flutter")
            }
        }
    }
    
    val intentFilter = IntentFilter("com.riogas.appmovil.REMOTE_LOGOUT")
    
    // 🔒 Android 13+ requiere especificar RECEIVER_NOT_EXPORTED
    // Este receiver solo recibe broadcasts internos de FcmPushReceiver
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
        registerReceiver(remoteLogoutReceiver, intentFilter, Context.RECEIVER_NOT_EXPORTED)
    } else {
        registerReceiver(remoteLogoutReceiver, intentFilter)
    }
    
    Log.d("MainActivity", "✅ BroadcastReceiver de logout remoto registrado")
}
```

### Cambios Realizados

1. **Verificación de versión Android**:
   ```kotlin
   if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU)
   ```
   - `TIRAMISU` = Android 13 (API 33)

2. **Registro con flag en Android 13+**:
   ```kotlin
   registerReceiver(remoteLogoutReceiver, intentFilter, Context.RECEIVER_NOT_EXPORTED)
   ```
   - Usa `RECEIVER_NOT_EXPORTED` porque este receiver **solo recibe broadcasts internos**
   - El broadcast viene de `FcmPushReceiver` (misma app)

3. **Compatibilidad con versiones anteriores**:
   ```kotlin
   else {
       registerReceiver(remoteLogoutReceiver, intentFilter)
   }
   ```
   - Mantiene compatibilidad con Android 12 y anteriores

---

## 🎯 ¿Por qué RECEIVER_NOT_EXPORTED?

Este receiver es usado para **comunicación interna** entre componentes de la misma app:

```
FCM Push Notification
        ↓
FcmPushReceiver.handleLogoutUser()
        ↓
sendBroadcast("com.riogas.appmovil.REMOTE_LOGOUT")
        ↓
MainActivity.remoteLogoutReceiver ← Solo broadcasts internos
        ↓
RemoteLogoutListener (Flutter)
```

### Ventajas de RECEIVER_NOT_EXPORTED

- ✅ **Más seguro**: Otras apps no pueden enviar broadcasts falsos
- ✅ **Mejores prácticas**: Google recomienda usar `NOT_EXPORTED` por defecto
- ✅ **Protección**: Previene ataques de broadcast injection

---

## 📊 Comparación de Flags

| Flag | Visibilidad | Seguridad | Uso |
|------|-------------|-----------|-----|
| `RECEIVER_EXPORTED` | Público (todas las apps) | ⚠️ Bajo | Comunicación inter-app necesaria |
| `RECEIVER_NOT_EXPORTED` | Privado (solo tu app) | ✅ Alto | Comunicación interna (recomendado) |
| Sin flag (Android 13+) | ❌ **CRASH** | N/A | No permitido |

---

## 🧪 Testing

### Antes del Fix
```bash
adb logcat | Select-String "AndroidRuntime"

# Output:
E AndroidRuntime: FATAL EXCEPTION: main
E AndroidRuntime: Caused by: java.lang.SecurityException: 
One of RECEIVER_EXPORTED or RECEIVER_NOT_EXPORTED should be specified
```

### Después del Fix
```bash
adb logcat | Select-String "MainActivity|REMOTE_LOGOUT"

# Output esperado:
D MainActivity: ✅ BroadcastReceiver de logout remoto registrado
```

---

## 🔍 Otros BroadcastReceivers en la App

### Revisar si hay más receivers con este problema

Busca en tu código otros lugares donde se registren receivers dinámicamente:

```kotlin
// ❌ Patrón que necesita corrección (Android 13+)
registerReceiver(receiver, intentFilter)

// ✅ Patrón corregido
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    registerReceiver(receiver, intentFilter, Context.RECEIVER_NOT_EXPORTED)
} else {
    registerReceiver(receiver, intentFilter)
}
```

### Receivers en AndroidManifest.xml

Los receivers **declarados en el manifest** NO necesitan el flag:

```xml
<!-- ✅ Estos NO necesitan cambios -->
<receiver android:name=".receivers.GPSStatusReceiver" 
          android:exported="false">
    <intent-filter>
        <action android:name="android.location.PROVIDERS_CHANGED" />
    </intent-filter>
</receiver>
```

Solo afecta a receivers registrados con `registerReceiver()` en **runtime**.

---

## 📝 Documentación de Referencia

### Android Developer Docs
- [BroadcastReceiver Security](https://developer.android.com/guide/components/broadcasts#security-considerations)
- [Context.RECEIVER_NOT_EXPORTED](https://developer.android.com/reference/android/content/Context#RECEIVER_NOT_EXPORTED)
- [Android 13 Behavior Changes](https://developer.android.com/about/versions/13/behavior-changes-13#runtime-receivers)

### Stack Overflow
- [SecurityException: One of RECEIVER_EXPORTED or RECEIVER_NOT_EXPORTED](https://stackoverflow.com/questions/72628696)

---

## ✅ Checklist de Verificación

- [x] Identificar el crash en logcat
- [x] Localizar el receiver problemático (`setupRemoteLogoutReceiver`)
- [x] Agregar verificación de versión Android
- [x] Usar `RECEIVER_NOT_EXPORTED` (broadcast interno)
- [x] Mantener compatibilidad con Android 12-
- [x] Documentar el cambio
- [ ] Testing en dispositivo Android 13+
- [ ] Testing en dispositivo Android 12-
- [ ] Verificar otros receivers dinámicos en la app

---

## 🚀 Próximos Pasos

1. **Compilar la app** con el fix
   ```bash
   flutter clean
   flutter pub get
   flutter build apk
   ```

2. **Instalar en dispositivo**
   ```bash
   flutter install
   ```

3. **Verificar logs**
   ```bash
   adb logcat -c
   adb logcat | Select-String "MainActivity|REMOTE_LOGOUT"
   ```

4. **Testing del logout remoto**
   - Enviar FCM con action `logout_user`
   - Verificar que el broadcast se recibe correctamente
   - Confirmar que la app no crashea

---

**Archivo modificado**: `MainActivity.kt`  
**Línea**: 1057 (método `setupRemoteLogoutReceiver`)  
**Fecha del fix**: 4 de noviembre de 2025  
**Android mínimo afectado**: Android 13 (API 33)  
**Estado**: ✅ Corregido
