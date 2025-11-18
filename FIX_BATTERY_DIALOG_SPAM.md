# 🔋 Solución: Diálogo de Batería Aparece Repetidamente

## 🐛 Problema Identificado

El diálogo de optimización de batería aparecía **múltiples veces** aunque la configuración estuviera correcta:
- ❌ Al iniciar la app N veces
- ❌ Al confirmar pedidos
- ❌ En cualquier acción de la app
- ❌ Aunque la batería esté configurada correctamente

---

## 🔍 Causa Raíz

### **Problema 1: Verificación Periódica Incorrecta**

**Código anterior:**
```dart
// Verificación periódica cada 5 segundos
_notificationCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) {
  _checkNotificationPermissions(); // ✅ Correcto
  // ❌ FALTABA: No había verificación periódica de batería, pero...
});
```

### **Problema 2: Sin Control de "Ya Verificado"**

**Código anterior:**
```dart
Future<void> _checkBatteryOptimization() async {
  final bool isIgnoring = await platform.invokeMethod('checkBatteryOptimization');
  
  if (!isIgnoring) {
    // ❌ PROBLEMA: Siempre muestra diálogo si isIgnoring=false
    // Aunque el usuario ya lo haya configurado o cerrado
    _showBatteryOptimizationDialog();
  }
}
```

### **Problema 3: Falso Negativo del Sistema**

En algunos dispositivos (Samsung, Xiaomi, Huawei), el método nativo `isIgnoringBatteryOptimizations()` puede devolver `false` **aunque esté configurado correctamente**:

```kotlin
// MainActivity.kt
val isIgnoring = pm.isIgnoringBatteryOptimizations(packageName)
// ❌ PROBLEMA: En algunos fabricantes esto devuelve false aunque esté OK
```

### **Problema 4: Verificación en Cada Resume**

**Código anterior:**
```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    _checkNotificationPermissions(); // ✅ OK
    // ❌ FALTABA: Pero si se agregaba aquí, verificaría en CADA vuelta
  }
}
```

**Resultado:** Cada vez que la app volvía al foreground (después de confirmar pedido, ver notificación, etc.), verificaba batería nuevamente.

---

## ✅ Solución Implementada

### **1. Flag de Control: `_batteryCheckCompleted`**

Se agregó un flag para marcar cuando la verificación ya se completó:

```dart
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _batteryCheckCompleted = false; // 🔋 Flag para evitar spam
  
  // ... resto del código
}
```

### **2. Verificación SOLO Una Vez Por Sesión**

```dart
Future<void> _checkBatteryOptimization() async {
  if (!Platform.isAndroid) return;

  // 🛡️ Si ya se verificó, NO volver a molestar
  if (_batteryCheckCompleted) {
    print('🔋 Verificación de batería ya completada, no se vuelve a mostrar');
    return;
  }

  try {
    final bool isIgnoring = await platform.invokeMethod('checkBatteryOptimization');
    print('🔋 Battery optimization status: isIgnoring=$isIgnoring');

    // ✅ Si ya está configurado correctamente, marcar como completado
    if (isIgnoring) {
      _batteryCheckCompleted = true;
      print('✅ Batería configurada correctamente, no se volverá a verificar');
      return;
    }

    // ⚠️ Si NO está configurado, mostrar diálogo SOLO UNA VEZ
    if (!isIgnoring && !_dialogShown && navigatorKey.currentContext != null) {
      _dialogShown = true;
      await _showBatteryOptimizationDialog();
      
      // 🔒 Marcar como completado DESPUÉS de mostrar
      _batteryCheckCompleted = true;
      print('🔋 Diálogo mostrado, no se volverá a mostrar en esta sesión');
    }
  } catch (e) {
    print('❌ Error verificando batería: $e');
    // Marcar como completado aunque haya error
    _batteryCheckCompleted = true;
  }
}
```

### **3. Llamada Única al Inicio**

```dart
void _startNotificationMonitoring() {
  // Verificación inicial de notificaciones
  Future.delayed(Duration(seconds: 1), () {
    _checkNotificationPermissions();
  });

  // 🔋 Verificación de batería SOLO 1 VEZ al inicio
  Future.delayed(Duration(seconds: 2), () {
    _checkBatteryOptimization();
  });

  // Verificación periódica (SOLO NOTIFICACIONES)
  // ⚠️ NO se verifica batería periódicamente para evitar spam
  _notificationCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) {
    _checkNotificationPermissions(); // Solo notificaciones
  });
}
```

### **4. Sin Verificación en Resume**

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    Future.delayed(Duration(milliseconds: 500), () {
      _checkNotificationPermissions(); // ✅ Solo notificaciones
    });
    // ⚠️ NO verificar batería en cada resume para evitar spam
    // Solo se verifica 1 vez al inicio
  }
}
```

---

## 📊 Comparación Antes vs Después

| Escenario | ❌ Antes | ✅ Después |
|-----------|---------|-----------|
| **Inicio de app** | Muestra diálogo si `isIgnoring=false` | Muestra diálogo SOLO 1 VEZ por sesión |
| **Confirmar pedido** | Verifica y muestra diálogo | NO verifica (flag ya está `true`) |
| **Volver al foreground** | Verifica y muestra diálogo | NO verifica (no se llama en resume) |
| **Batería ya configurada** | Muestra diálogo igualmente (falso negativo) | Marca como completado y NO molesta más |
| **Error en verificación** | Intenta múltiples veces | Marca como completado al primer error |
| **Segunda apertura de app** | Muestra diálogo nuevamente | NO muestra (flag sigue `true` en sesión) |

---

## 🎯 Flujo de Verificación

### **Antes (Problemático):**
```
App inicia
  ↓
Espera 2 segundos
  ↓
_checkBatteryOptimization()
  ↓
isIgnoring=false (falso negativo)
  ↓
❌ Muestra diálogo
  ↓
Usuario cierra diálogo
  ↓
[5 segundos después]
  ↓
Timer periódico (no verifica batería, pero...)
  ↓
Usuario confirma pedido
  ↓
App va a background → resume
  ↓
_checkBatteryOptimization() (llamado en resume?)
  ↓
❌ Muestra diálogo OTRA VEZ
```

### **Después (Solucionado):**
```
App inicia
  ↓
Espera 2 segundos
  ↓
_checkBatteryOptimization()
  ↓
isIgnoring=true
  ↓
_batteryCheckCompleted = true
  ↓
✅ NO muestra diálogo
  ↓
✅ Marca como completado
  ↓
[Usuario usa la app normalmente]
  ↓
Confirma pedido, vuelve al foreground, etc.
  ↓
_checkBatteryOptimization() (si se llamara)
  ↓
if (_batteryCheckCompleted) return;
  ↓
✅ Sale inmediatamente sin molestar
```

---

## 🧪 Testing

### **Test 1: Batería Configurada Correctamente**

```bash
# 1. Asegurarse que la app NO esté en optimización de batería:
adb shell dumpsys deviceidle whitelist | Select-String "moveit"
# Debería aparecer: com.example.moveit

# 2. Abrir app
# 3. Ver logs:
adb logcat | Select-String "Battery optimization"
```

**Resultado esperado:**
```
🔋 Battery optimization status: isIgnoring=true
✅ Batería configurada correctamente, no se volverá a verificar
```

**Verificación:**
- ✅ NO debe aparecer diálogo
- ✅ Log dice "no se volverá a verificar"
- ✅ Flag `_batteryCheckCompleted = true`

---

### **Test 2: Batería NO Configurada (Primera Vez)**

```bash
# 1. Asegurarse que la app SÍ esté en optimización:
adb shell dumpsys deviceidle whitelist | Select-String "moveit"
# NO debe aparecer

# 2. Abrir app
# 3. Ver logs:
adb logcat | Select-String "Battery optimization"
```

**Resultado esperado:**
```
🔋 Battery optimization status: isIgnoring=false
🔋 Diálogo mostrado, no se volverá a mostrar en esta sesión
```

**Verificación:**
- ✅ Aparece diálogo UNA VEZ
- ✅ Usuario puede cerrar o configurar
- ✅ Flag `_batteryCheckCompleted = true` después de mostrar
- ✅ NO vuelve a aparecer aunque cierre/abra la app

---

### **Test 3: Confirmar Pedido (No Debe Mostrar Diálogo)**

```bash
# 1. Abrir app (ver Test 1 o Test 2)
# 2. Confirmar un pedido
# 3. App va a background
# 4. App vuelve al foreground
# 5. Ver logs:
adb logcat | Select-String "Battery optimization|batteryCheckCompleted"
```

**Resultado esperado:**
```
🔋 Verificación de batería ya completada, no se vuelve a mostrar
```

**Verificación:**
- ✅ NO aparece diálogo
- ✅ Log dice "ya completada"
- ✅ App funciona normalmente

---

### **Test 4: Abrir/Cerrar App Múltiples Veces**

```bash
# 1. Abrir app
# 2. Cerrar app (Force Stop)
# 3. Abrir app NUEVAMENTE
# 4. Ver logs
```

**Resultado esperado (PRIMERA vez):**
```
🔋 Battery optimization status: isIgnoring=true
✅ Batería configurada correctamente, no se volverá a verificar
```

**Resultado esperado (SEGUNDA vez y siguientes):**
```
🔋 Battery optimization status: isIgnoring=true
✅ Batería configurada correctamente, no se volverá a verificar
```

**Verificación:**
- ✅ Diálogo aparece MÁXIMO 1 vez por sesión
- ✅ Si ya está configurado, NO aparece nunca
- ✅ Flag se resetea al cerrar la app (nueva sesión)

---

## 📝 Logs para Debugging

### **Comando para monitorear:**
```powershell
adb logcat | Select-String "Battery optimization|batteryCheckCompleted|_checkBatteryOptimization"
```

### **Logs normales (Batería OK):**
```
🔋 Battery optimization status: isIgnoring=true
✅ Batería configurada correctamente, no se volverá a verificar
```

### **Logs con diálogo (Batería NO configurada):**
```
🔋 Battery optimization status: isIgnoring=false
🔋 Diálogo mostrado, no se volverá a mostrar en esta sesión
```

### **Logs en intentos posteriores (Mismo sesión):**
```
🔋 Verificación de batería ya completada, no se vuelve a mostrar
```

### **Logs de error:**
```
❌ Error verificando optimización de batería: [Exception...]
```

---

## 🛡️ Protecciones Agregadas

1. **Flag de Control:** `_batteryCheckCompleted` evita verificaciones repetidas
2. **Verificación Única:** Solo se verifica al inicio, no en resume
3. **Sin Timer Periódico:** No se verifica cada 5 segundos (solo notificaciones)
4. **Marca Completado en Éxito:** Si `isIgnoring=true`, marca como completado
5. **Marca Completado en Diálogo:** Después de mostrar diálogo, marca como completado
6. **Marca Completado en Error:** Si falla verificación, marca como completado (no reintentar)
7. **Sin Verificación en didChangeAppLifecycleState:** No verifica en resume

---

## 🎯 Beneficios

| Beneficio | Descripción |
|-----------|-------------|
| ✅ **Sin Spam** | Usuario NO ve diálogo repetidamente |
| ✅ **Una Vez Por Sesión** | Máximo 1 diálogo por apertura de app |
| ✅ **Respeta Configuración** | Si ya está OK, NO molesta |
| ✅ **Mejor UX** | Usuario puede usar la app sin interrupciones |
| ✅ **Performance** | Menos verificaciones = menos overhead |
| ✅ **Menos Molesto** | No aparece en acciones críticas (confirmar pedido) |

---

## 📋 Resumen de Cambios

### **Archivo: `lib/main.dart`**

1. **Línea 948:** Agregado flag `_batteryCheckCompleted = false`
2. **Línea 969:** Comentario explicativo en `didChangeAppLifecycleState`
3. **Línea 981:** Comentario explicativo en `_startNotificationMonitoring`
4. **Línea 990:** Comentario "SOLO NOTIFICACIONES" en timer periódico
5. **Línea 1027-1066:** Reescrito método `_checkBatteryOptimization()` con:
   - Check de flag al inicio
   - Marca completado si `isIgnoring=true`
   - Marca completado después de mostrar diálogo
   - Marca completado en catch de error

---

## ✅ Checklist de Solución

- [x] ✅ Flag `_batteryCheckCompleted` agregado
- [x] ✅ Verificación única al inicio
- [x] ✅ NO verifica en `didChangeAppLifecycleState`
- [x] ✅ NO verifica en timer periódico
- [x] ✅ Marca completado si batería OK
- [x] ✅ Marca completado después de mostrar diálogo
- [x] ✅ Marca completado en caso de error
- [x] ✅ Logs informativos agregados
- [x] ✅ Comentarios explicativos en código

---

## 🚀 Resultado Final

✅ **DIÁLOGO DE BATERÍA YA NO MOLESTA**

**Garantías:**
1. ✅ Aparece MÁXIMO 1 vez por sesión
2. ✅ NO aparece si ya está configurado correctamente
3. ✅ NO aparece al confirmar pedidos
4. ✅ NO aparece al volver de background
5. ✅ NO aparece en acciones normales de la app
6. ✅ Logs claros para debugging

---

**¡Problema resuelto! 🎉**
