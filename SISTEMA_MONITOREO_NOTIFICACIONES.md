# 🔔 Sistema de Monitoreo de Permisos de Notificaciones

## 📋 Descripción General

Sistema implementado en `main.dart` que **fuerza al usuario** a mantener las notificaciones activas. Es una **restricción obligatoria** para el funcionamiento de la aplicación.

---

## ⚙️ Características Implementadas

### 1️⃣ **Monitoreo Continuo**
- ✅ Verificación **cada 5 segundos** en segundo plano
- ✅ Verificación **inmediata** cuando la app vuelve al foreground (AppLifecycleState.resumed)
- ✅ Verificación **inicial** 1 segundo después de iniciar la app

### 2️⃣ **Diálogo No Cancelable**
- 🚫 **No se puede cerrar** tocando fuera del diálogo
- 🚫 **No se puede cerrar** con el botón "Atrás" de Android (se vuelve a mostrar)
- 🔄 Si el usuario lo cierra sin activar las notificaciones, **se vuelve a mostrar a los 3 segundos**
- ✅ Solo desaparece cuando las notificaciones están **realmente activadas**

### 3️⃣ **Prevención de Solapamiento**
- 🛡️ Usa flags `_dialogShown` para evitar múltiples diálogos superpuestos
- ⏱️ Usa `_lastDialogDismissed` para controlar el tiempo entre cierres y reaperturas
- 🔒 Usa `_isCheckingPermissions` para evitar verificaciones concurrentes

### 4️⃣ **Botón de Configuración**
- ⚙️ Botón grande y visible: **"Abrir Configuración"**
- 📱 Abre directamente la configuración de la app en Android
- ⏳ Espera 3 segundos antes de volver a verificar (da tiempo al usuario)

---

## 🎨 Diseño del Diálogo

```
┌─────────────────────────────────────────┐
│ 🔔 ⚠️ Notificaciones Deshabilitadas     │
├─────────────────────────────────────────┤
│                                         │
│ Las notificaciones son OBLIGATORIAS    │
│ para el funcionamiento de la           │
│ aplicación.                             │
│                                         │
│ 📍 Sin notificaciones activas, el       │
│ servicio de ubicación NO funcionará    │
│ correctamente.                          │
│                                         │
│ 🚫 La aplicación no puede continuar    │
│ sin este permiso.                       │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ Por favor, activa las              │ │
│ │ notificaciones en la configuración │ │
│ │ de Android.                        │ │
│ └─────────────────────────────────────┘ │
│                                         │
│         [⚙️ Abrir Configuración]        │
│                                         │
└─────────────────────────────────────────┘
```

---

## 🔄 Flujo de Funcionamiento

```
┌─────────────────────────────────────────────────────┐
│ 1. App inicia → Timer inicia (cada 5 seg)          │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ 2. Verificar permisos de notificaciones            │
│    - permission_handler.Permission.notification     │
└──────────────────┬──────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
        ▼                     ▼
  ✅ GRANTED            ❌ DENIED/RESTRICTED
  (Continuar)           │
                        ▼
              ┌─────────────────────┐
              │ ¿Diálogo visible?   │
              └────┬────────────┬───┘
                   │            │
                   NO          YES
                   │            │
                   ▼            ▼
          ┌────────────┐  (No hacer nada)
          │ Mostrar    │
          │ Diálogo    │
          └──────┬─────┘
                 │
                 ▼
      ┌──────────────────────┐
      │ Usuario presiona:    │
      │ "Abrir Configuración"│
      └──────────┬───────────┘
                 │
                 ▼
      ┌──────────────────────┐
      │ Abrir Settings de    │
      │ Android              │
      └──────────┬───────────┘
                 │
                 ▼
      ┌──────────────────────┐
      │ Usuario activa o no  │
      │ las notificaciones   │
      └──────────┬───────────┘
                 │
        ┌────────┴────────┐
        │                 │
        ▼                 ▼
    ✅ ACTIVÓ        ❌ NO ACTIVÓ
    (Diálogo        (Espera 3 seg
     desaparece)     y vuelve a
                     mostrar diálogo)
```

---

## 📱 Cómo Probar

### **Prueba 1: Notificaciones Deshabilitadas al Iniciar**

```bash
# 1. Deshabilitar notificaciones de la app
adb shell pm revoke com.example.moveit android.permission.POST_NOTIFICATIONS

# 2. Abrir la app
adb shell am start -n com.example.moveit/.MainActivity

# 3. Resultado esperado:
# ✅ Diálogo aparece inmediatamente (1 segundo después)
# ✅ No se puede cerrar fácilmente
# ✅ Usuario debe ir a configuración
```

### **Prueba 2: Cerrar Diálogo sin Activar**

```bash
# 1. Cuando el diálogo aparece, presionar "Atrás" o tocar fuera
# 2. Resultado esperado:
# ✅ Diálogo se cierra
# ⏱️ Espera exactamente 3 segundos
# ✅ Diálogo vuelve a aparecer automáticamente
```

### **Prueba 3: Activar Notificaciones**

```bash
# 1. Presionar "Abrir Configuración"
# 2. En Settings de Android, activar notificaciones
# 3. Volver a la app (con botón "Atrás")
# 4. Resultado esperado:
# ✅ Diálogo NO vuelve a aparecer
# ✅ App funciona normalmente
```

### **Prueba 4: Desactivar Notificaciones con App Abierta**

```bash
# 1. Con la app funcionando normalmente
# 2. Ir a Settings de Android y desactivar notificaciones
# 3. Volver a la app
# 4. Resultado esperado:
# ✅ En máximo 5 segundos (próxima verificación), diálogo aparece
# ✅ Usuario forzado a reactivarlas
```

### **Prueba 5: Minimizar y Maximizar App**

```bash
# 1. Con notificaciones deshabilitadas, minimizar la app
# 2. Abrir otras apps
# 3. Volver a MoveIT
# 4. Resultado esperado:
# ✅ Diálogo aparece inmediatamente (500ms después)
# ✅ didChangeAppLifecycleState detecta el resume
```

---

## 🛠️ Código Técnico

### **Archivo Modificado**

- `lib/main.dart` → Clase `MyApp` convertida de `StatelessWidget` a `StatefulWidget`

### **Nuevos Componentes**

1. **`_MyAppState`** (Estado del widget principal)
   - Mantiene el estado del monitoreo
   - Implementa `WidgetsBindingObserver` para detectar cambios de lifecycle

2. **Variables de Control**
   ```dart
   Timer? _notificationCheckTimer;           // Timer periódico (5 seg)
   bool _isCheckingPermissions = false;      // Previene verificaciones concurrentes
   bool _dialogShown = false;                // Previene diálogos superpuestos
   DateTime? _lastDialogDismissed;           // Control de tiempo entre diálogos
   ```

3. **Métodos Principales**
   - `_startNotificationMonitoring()` → Inicia verificación periódica
   - `_checkNotificationPermissions()` → Verifica estado actual
   - `_showNotificationPermissionDialog()` → Muestra diálogo forzado
   - `didChangeAppLifecycleState()` → Detecta cuando app vuelve al foreground

---

## ⚡ Características Técnicas Avanzadas

### **1. Prevención de Race Conditions**
```dart
if (_isCheckingPermissions) return;
_isCheckingPermissions = true;
// ... código de verificación ...
finally {
  _isCheckingPermissions = false;
}
```

### **2. Control de Tiempo entre Diálogos**
```dart
if (_lastDialogDismissed != null) {
  final timeSinceDismissed = DateTime.now().difference(_lastDialogDismissed!);
  if (timeSinceDismissed.inSeconds < 3) {
    return; // Esperar 3 segundos
  }
}
```

### **3. Diálogo No Cancelable**
```dart
barrierDismissible: false,  // No cerrar al tocar fuera
WillPopScope(
  onWillPop: () async {
    _lastDialogDismissed = DateTime.now();
    return true; // Permitir cerrar pero guardar timestamp
  },
  // ...
)
```

### **4. Verificación en Resume**
```dart
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    Future.delayed(Duration(milliseconds: 500), () {
      _checkNotificationPermissions();
    });
  }
}
```

---

## 🔒 Por Qué Es Necesario

1. **Servicio de Ubicación en Background**
   - Android 12+ requiere notificación persistente para acceder al GPS en background
   - Sin notificaciones, el `ForegroundLocationService` no puede funcionar

2. **Visibilidad para el Usuario**
   - La notificación muestra que el servicio está activo
   - Evita que Android mate la app silenciosamente

3. **Cumplimiento de Políticas de Android**
   - Google Play exige que apps con tracking de ubicación muestren notificación visible
   - Es un requisito de seguridad y privacidad

---

## 🐛 Debugging

### **Ver Logs de Monitoreo**
```bash
adb logcat | Select-String "Error verificando permisos|Notificaciones Deshabilitadas"
```

### **Ver Estado de Permisos**
```bash
adb shell dumpsys package com.example.moveit | Select-String "POST_NOTIFICATIONS"
```

### **Forzar Estado de Permiso**
```bash
# Revocar permiso
adb shell pm revoke com.example.moveit android.permission.POST_NOTIFICATIONS

# Otorgar permiso
adb shell pm grant com.example.moveit android.permission.POST_NOTIFICATIONS
```

---

## ✅ Checklist de Funcionamiento

- [ ] Diálogo aparece si las notificaciones están deshabilitadas
- [ ] Diálogo NO se puede cerrar tocando fuera
- [ ] Diálogo se vuelve a mostrar a los 3 segundos si se cierra sin activar
- [ ] No se apilan múltiples diálogos (solo uno a la vez)
- [ ] Botón "Abrir Configuración" funciona correctamente
- [ ] Diálogo desaparece cuando se activan las notificaciones
- [ ] Monitoreo funciona cada 5 segundos
- [ ] Monitoreo se activa al volver al foreground
- [ ] Usuario puede usar la app normalmente con notificaciones activas

---

## 📈 Mejoras Futuras Posibles

1. **Contador de Rechazos**
   - Contar cuántas veces el usuario cierra el diálogo
   - Mostrar mensaje más enfático después de X intentos

2. **Tutorial Visual**
   - Mostrar capturas de pantalla de cómo activar notificaciones
   - Guía paso a paso animada

3. **Notificación de Recordatorio**
   - Si usuario cierra el diálogo, mostrar notificación de sistema
   - "Recuerda activar las notificaciones para continuar usando MoveIT"

4. **Analytics**
   - Registrar en Firebase Analytics cuántas veces se muestra el diálogo
   - Identificar usuarios que rechazan persistentemente el permiso

---

## 🎯 Resumen Ejecutivo

Este sistema garantiza que **las notificaciones SIEMPRE estén activas** cuando la app está en uso. Es una **restricción obligatoria** que:

- ✅ Se verifica automáticamente cada 5 segundos
- ✅ Fuerza al usuario a activar las notificaciones
- ✅ No permite continuar sin el permiso
- ✅ Evita solapamiento de diálogos
- ✅ Respeta el flujo del usuario (espera 3 seg entre diálogos)
- ✅ Es compatible con el ciclo de vida de la app (resume/pause)

**El usuario NO puede usar la app sin notificaciones activas.** 🔒
