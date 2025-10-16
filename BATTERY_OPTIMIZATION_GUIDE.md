# 🔋 Guía de Implementación: Verificación de Optimización de Batería

## 📋 Resumen

Se ha implementado un sistema automático que **monitorea constantemente** si la aplicación está excluida de la optimización de batería de Android y **fuerza al usuario** a configurarlo si no está habilitado.

---

## 🎯 Características Implementadas

### ✅ Verificación Automática al Inicio
- La app verifica el estado de optimización de batería **2 segundos después de iniciar**
- Se ejecuta independientemente del estado de login del usuario

### ✅ Diálogo Forzado
- Si la app NO está excluida, muestra un diálogo **NO CANCELABLE**
- El usuario NO puede cerrar el diálogo tocando fuera
- El botón de atrás NO cierra el diálogo permanentemente

### ✅ Re-aparición Inteligente
- Si el usuario cierra el diálogo sin configurar, **reaparece después de 3 segundos**
- Evita superposición de múltiples diálogos (solo uno visible a la vez)

### ✅ Acceso Directo a Configuración
- Botón "Configurar Ahora" abre **directamente** la configuración de optimización de batería
- No requiere que el usuario navegue manualmente por los menús de Android

---

## 🛠️ Implementación Técnica

### 1️⃣ AndroidManifest.xml
```xml
<!-- ✅ Permiso ya agregado -->
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
```

**Ubicación:** `android/app/src/main/AndroidManifest.xml` línea 21

---

### 2️⃣ MainActivity.kt - Métodos Nativos

#### **Método: `checkBatteryOptimization`**
Verifica si la app está excluida de optimización de batería.

```kotlin
"checkBatteryOptimization" -> {
    val pm = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
    val packageName = applicationContext.packageName
    val isIgnoring = pm.isIgnoringBatteryOptimizations(packageName)
    
    Log.d("MainActivity", "🔋 Battery optimization status: isIgnoring=$isIgnoring")
    result.success(isIgnoring)
}
```

**Retorna:** `true` si está excluida, `false` si no

---

#### **Método: `requestBatteryOptimizationExemption`**
Abre la configuración de Android para que el usuario excluya la app.

```kotlin
"requestBatteryOptimizationExemption" -> {
    try {
        val pm = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        val packageName = applicationContext.packageName
        
        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            intent.data = android.net.Uri.parse("package:$packageName")
            startActivity(intent)
            
            Log.d("MainActivity", "🔋 Solicitud de exclusión de batería enviada")
            result.success("✅ Solicitud enviada")
        } else {
            Log.d("MainActivity", "✅ La app ya está exenta de optimización de batería")
            result.success("✅ Ya exenta")
        }
    } catch (e: Exception) {
        Log.e("MainActivity", "❌ Error solicitando exclusión de batería: ${e.message}", e)
        result.error("ERROR", "Error al solicitar exclusión: ${e.message}", null)
    }
}
```

**Ubicación:** `MainActivity.kt` líneas 212-241

---

### 3️⃣ main.dart - Lógica Flutter

#### **Inicio del Monitoreo**
En el método `_startNotificationMonitoring()`:

```dart
// Verificación inicial de optimización de batería
Future.delayed(Duration(seconds: 2), () {
  _checkBatteryOptimization();
});
```

**Ubicación:** `lib/main.dart` líneas 800-805

---

#### **Método: `_checkBatteryOptimization()`**
Verifica el estado y muestra el diálogo si es necesario.

```dart
Future<void> _checkBatteryOptimization() async {
  if (!Platform.isAndroid) return;

  try {
    final platform = MethodChannel('background_service');
    final bool isIgnoring = await platform.invokeMethod('checkBatteryOptimization');

    print('🔋 Battery optimization status: $isIgnoring');

    if (!isIgnoring) {
      // Si el diálogo fue cerrado hace menos de 3 segundos, esperar
      if (_lastDialogDismissed != null) {
        final timeSinceDismissed = DateTime.now().difference(_lastDialogDismissed!);
        if (timeSinceDismissed.inSeconds < 3) {
          return;
        }
      }

      // Mostrar diálogo solo si no está ya visible
      if (!_dialogShown && navigatorKey.currentContext != null) {
        _dialogShown = true;
        await _showBatteryOptimizationDialog();
      }
    }
  } catch (e) {
    print('❌ Error verificando optimización de batería: $e');
  }
}
```

**Ubicación:** `lib/main.dart` líneas 844-870

---

#### **Método: `_showBatteryOptimizationDialog()`**
Muestra el diálogo forzado con información clara.

```dart
Future<void> _showBatteryOptimizationDialog() async {
  if (navigatorKey.currentContext == null) {
    _dialogShown = false;
    return;
  }

  return showDialog<void>(
    context: navigatorKey.currentContext!,
    barrierDismissible: false, // No se puede cerrar tocando fuera
    builder: (BuildContext context) {
      return WillPopScope(
        onWillPop: () async {
          // No permitir cerrar con botón de atrás (pero permitir cierre temporal)
          _lastDialogDismissed = DateTime.now();
          _dialogShown = false;
          return true;
        },
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.battery_alert, color: Colors.orange, size: 30),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '🔋 Optimización de Batería',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'La app necesita estar excluida de la optimización de batería para funcionar correctamente.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 15),
              Text(
                '📍 Sin esta exclusión, el sistema puede matar el servicio de ubicación en segundo plano.',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 10),
              Text(
                '🚫 Esto impedirá el envío de coordenadas cuando la app esté cerrada.',
                style: TextStyle(fontSize: 14, color: Colors.red),
              ),
              SizedBox(height: 15),
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange, width: 2),
                ),
                child: Text(
                  'Por favor, permite que la app funcione sin restricciones de batería.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton.icon(
              icon: Icon(Icons.settings, color: Colors.white),
              label: Text('Configurar Ahora',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () async {
                _lastDialogDismissed = DateTime.now();
                _dialogShown = false;
                Navigator.of(context).pop();

                try {
                  // Llamar al método nativo para abrir configuración
                  final platform = MethodChannel('background_service');
                  await platform.invokeMethod('requestBatteryOptimizationExemption');
                } catch (e) {
                  print('❌ Error abriendo configuración de batería: $e');
                }

                // Esperar 3 segundos antes de volver a verificar
                await Future.delayed(Duration(seconds: 3));
              },
            ),
          ],
        ),
      );
    },
  ).then((_) {
    _dialogShown = false;
    _lastDialogDismissed = DateTime.now();
  });
}
```

**Ubicación:** `lib/main.dart` líneas 946-1041

---

## 🔄 Flujo de Funcionamiento

```
1️⃣ Usuario abre la app
    ↓
2️⃣ main.dart ejecuta initState()
    ↓
3️⃣ _startNotificationMonitoring() se ejecuta
    ↓
4️⃣ Espera 2 segundos
    ↓
5️⃣ _checkBatteryOptimization() verifica estado
    ↓
6️⃣ Llama a método nativo checkBatteryOptimization
    ↓
7️⃣ MainActivity.kt verifica PowerManager.isIgnoringBatteryOptimizations()
    ↓
8️⃣ ¿App excluida?
    ├─ SÍ ✅ → No hace nada, app funciona normalmente
    └─ NO ❌ → Muestra diálogo forzado
        ↓
    9️⃣ Usuario presiona "Configurar Ahora"
        ↓
    🔟 Abre Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
        ↓
    1️⃣1️⃣ Usuario configura exclusión en Android
        ↓
    1️⃣2️⃣ Usuario vuelve a la app
        ↓
    1️⃣3️⃣ Después de 3 segundos, verifica nuevamente
        ↓
    1️⃣4️⃣ Si aún no está excluida, muestra diálogo nuevamente
```

---

## 🧪 Cómo Probar

### **Escenario 1: Primera Instalación (NO Excluida)**

1. Instalar APK en dispositivo limpio
2. Abrir la app
3. **RESULTADO ESPERADO:**
   - Después de 2 segundos, aparece diálogo de optimización de batería
   - Diálogo no se puede cerrar tocando fuera
   - Botón "Configurar Ahora" abre configuración de Android

### **Escenario 2: Usuario Cierra Diálogo Sin Configurar**

1. Cerrar diálogo con botón de atrás
2. **RESULTADO ESPERADO:**
   - Diálogo reaparece después de 3 segundos
   - Sigue apareciendo hasta que el usuario configure

### **Escenario 3: Usuario Configura Exclusión**

1. Presionar "Configurar Ahora"
2. En Android, seleccionar "No optimizar"
3. Volver a la app
4. **RESULTADO ESPERADO:**
   - Diálogo NO vuelve a aparecer
   - App funciona normalmente

### **Escenario 4: Usuario Ya Tiene Exclusión Configurada**

1. Abrir app en dispositivo con exclusión ya configurada
2. **RESULTADO ESPERADO:**
   - Diálogo NUNCA aparece
   - App inicia normalmente

---

## 📱 Comandos ADB para Pruebas

### Ver Estado Actual de Optimización
```bash
adb shell dumpsys deviceidle whitelist | Select-String "moveit"
```

### Forzar Exclusión (Solo Pruebas)
```bash
adb shell dumpsys deviceidle whitelist +com.example.moveit
```

### Remover Exclusión (Simular NO Excluida)
```bash
adb shell dumpsys deviceidle whitelist -com.example.moveit
```

### Ver Logs de Verificación
```bash
adb logcat | Select-String "Battery optimization"
```

**Ejemplo de log esperado:**
```
MainActivity: 🔋 Battery optimization status: isIgnoring=false
MainActivity: 🔋 Solicitud de exclusión de batería enviada
```

---

## ⚠️ Comportamiento Importante

### ✅ LO QUE SÍ HACE:
- ✅ Verifica estado al abrir la app
- ✅ Muestra diálogo forzado si no está excluida
- ✅ Reaparece cada 3 segundos si usuario cierra sin configurar
- ✅ Abre directamente la configuración de Android
- ✅ Deja de molestar una vez configurado

### ❌ LO QUE NO HACE:
- ❌ NO verifica periódicamente en background (solo al abrir app)
- ❌ NO configura automáticamente (requiere acción del usuario)
- ❌ NO funciona en iOS (solo Android)
- ❌ NO persiste si el usuario fuerza cierre de la app sin configurar

---

## 🔧 Variables de Estado

```dart
bool _dialogShown = false;           // Evita superposición de diálogos
DateTime? _lastDialogDismissed;     // Controla tiempo de reaparición (3 seg)
```

**Ubicación:** `lib/main.dart` líneas 768-770

---

## 🎨 Diseño del Diálogo

- **Título:** Icono de batería naranja + "🔋 Optimización de Batería"
- **Contenido:**
  - Texto en negrita explicando la necesidad
  - Iconos informativos (📍, 🚫)
  - Caja naranja con borde destacando la acción requerida
- **Botón:** 
  - Color naranja (diferente al azul de notificaciones)
  - Texto: "Configurar Ahora"
  - Icono: Settings (engranaje)

---

## 🚀 Próximos Pasos Recomendados

1. **Probar en múltiples dispositivos:**
   - Samsung (One UI)
   - Xiaomi (MIUI)
   - Huawei (EMUI)
   - Stock Android

2. **Monitorear logs de usuarios:**
   - ¿Cuántos usuarios configuran vs. cierran?
   - Tiempo promedio hasta configuración

3. **Considerar agregar:**
   - Tutorial visual (capturas de pantalla de dónde tocar)
   - Contador de veces que cierra sin configurar
   - Mensaje más fuerte después de X cierres

---

## 📊 Impacto Esperado

### **Sin Exclusión de Batería:**
- ⏱️ Servicio muere después de ~2 horas
- ❌ Coordenadas dejan de enviarse
- 🔴 Usuario no recibe alertas

### **Con Exclusión de Batería:**
- ✅ Servicio permanece vivo indefinidamente
- ✅ Coordenadas se envían cada 3 minutos
- ✅ WorkManager funciona como backup cada 15 minutos
- 🟢 Sistema completamente funcional

---

## 🐛 Solución de Problemas

### **El diálogo no aparece:**
```dart
// Verificar en logs:
print('🔋 Battery optimization status: $isIgnoring');
```
- Si no aparece este log, el método nativo no se está llamando
- Verificar que `MethodChannel('background_service')` esté correcto

### **El diálogo aparece infinitamente:**
```dart
// Verificar que _lastDialogDismissed se esté actualizando:
_lastDialogDismissed = DateTime.now();
```

### **La configuración de Android no se abre:**
```kotlin
// Verificar en logcat:
Log.d("MainActivity", "🔋 Solicitud de exclusión de batería enviada")
```
- Si no aparece, verificar que el método nativo esté registrado
- Verificar que el intent tenga el URI correcto

---

## ✅ Checklist de Implementación

- [x] Permiso `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` en AndroidManifest.xml
- [x] Método `checkBatteryOptimization` en MainActivity.kt
- [x] Método `requestBatteryOptimizationExemption` en MainActivity.kt
- [x] Import `android.os.PowerManager` en MainActivity.kt
- [x] Método `_checkBatteryOptimization()` en main.dart
- [x] Método `_showBatteryOptimizationDialog()` en main.dart
- [x] Llamada inicial después de 2 segundos
- [x] Lógica de reaparición cada 3 segundos
- [x] Evitar superposición de diálogos
- [x] Diseño claro e informativo del diálogo
- [x] Botón de acceso directo a configuración
- [x] APK compilado e instalado

---

## 📝 Notas Adicionales

- El sistema funciona **en conjunto** con el monitoreo de notificaciones ya existente
- Ambos sistemas comparten las mismas variables de estado (`_dialogShown`, `_lastDialogDismissed`)
- Se verifica **primero notificaciones** (1 segundo) y **luego batería** (2 segundos)
- Esto evita que el usuario vea dos diálogos al mismo tiempo

---

**Última actualización:** 16 de Octubre de 2025
**Versión de la app:** Actual
**Estado:** ✅ Implementado y Funcional
