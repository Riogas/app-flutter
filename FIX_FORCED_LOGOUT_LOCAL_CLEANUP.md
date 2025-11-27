# 🔧 FIX: Limpieza Local en Sesión Inválida (v3.0)

**Fecha**: 2025-01-21  
**Archivo**: `lib/pages/login_page.dart` (líneas 570-655)  
**Estado**: ✅ IMPLEMENTADO

---

## 📋 RESUMEN EJECUTIVO

Se corrigió el flujo de **limpieza de sesión inválida** en `login_page.dart`. Cuando HomePage detecta sesión inválida y redirige a LoginPage, ahora se ejecuta **SOLO limpieza LOCAL** (detener servicios, limpiar Hive, cancelar streams) **SIN llamar a servicios backend** como `registrarCierre()` (que ya fueron ejecutados por el otro dispositivo).

---

## 🔍 EVOLUCIÓN DEL PROBLEMA

### **v1.0** - Primera corrección (INCORRECTA)
```dart
// Cambió isRemoteLogout de true a false
await LogoutService.executeLogout(isRemoteLogout: false); // ❌ Aún ejecuta todo
```
**Problema**: Seguía ejecutando `registrarCierre()`, actualizando Firestore, etc.

### **v2.0** - Segunda corrección (INCOMPLETA)
```dart
// Eliminó LogoutService completamente
await _cancelStreams(); // ✅ Solo cancela streams
_showForcedLogoutDialog(); // ✅ Solo muestra diálogo
```
**Problema**: NO detenía servicios GPS ni limpiaba Hive local (podían quedar activos)

### **v3.0** - Corrección FINAL (CORRECTA) ⭐
```dart
// Limpieza LOCAL completa (sin backend calls)
await _cancelStreams(); // ✅ Cancela streams
await stopLocationService(); // ✅ Detiene GPS local
await clearHiveBoxes(); // ✅ Limpia Hive local
await clearSharedPreferences(); // ✅ Limpia SharedPreferences
_showForcedLogoutDialog(); // ✅ Muestra diálogo
```
**Solución**: Hace limpieza LOCAL necesaria, pero NO llama a backend (que ya procesó el otro dispositivo)

---

## 💡 CONCEPTO CLAVE

### **LOGOUT COMPLETO vs LIMPIEZA LOCAL**

| Acción | Logout Manual (Settings) | Logout Remoto FCM | Sesión Inválida (forcedLogout) |
|--------|--------------------------|-------------------|--------------------------------|
| **Archivo que ejecuta** | `settings_page.dart` | `fcm_handler.dart` | `login_page.dart` |
| **Servicio usado** | `LogoutService.executeLogout()` | `LogoutService.executeLogout()` | ❌ NO usa LogoutService |
| **registrarCierre()** | ✅ SÍ (tipo: `Controlado`) | ✅ SÍ (tipo: `Remoto`) | ❌ NO (ya lo hizo otro dispositivo) |
| **Actualizar Firestore** | ✅ SÍ (mover a history) | ✅ SÍ (mover a history) | ❌ NO (ya lo hizo otro dispositivo) |
| **SessionService.cerrarSesion()** | ✅ SÍ | ✅ SÍ | ❌ NO (ya lo hizo otro dispositivo) |
| **Detener GPS local** | ✅ SÍ | ✅ SÍ | ✅ SÍ (puede que aún esté activo) |
| **Limpiar Hive local** | ✅ SÍ | ✅ SÍ | ✅ SÍ (datos ahora inválidos) |
| **Cancelar streams locales** | ✅ SÍ | ✅ SÍ | ✅ SÍ (aún pueden estar activos) |
| **Limpiar SharedPreferences** | ✅ SÍ | ✅ SÍ | ✅ SÍ (sessionActive flag) |
| **Navegación** | → LoginPage | → LoginPage | Ya está en LoginPage |

---

### **🎯 CASOS DE USO EXPLICADOS**

#### 1️⃣ **Logout Manual (Usuario presiona "Cerrar Sesión")**
**Archivo**: `settings_page.dart` línea 166
```dart
await LogoutService.executeLogout(
  isRemoteLogout: false,  // ← Tipo: "Controlado"
  nombreUsuario: nombreUsuario,
  idUsuario: idUsuario,
  deviceId: deviceId,
);
```
**¿Qué hace?**
- ✅ Llama a `registrarCierre()` con tipo `"Controlado"`
- ✅ Actualiza Firestore (mueve sesión a history)
- ✅ Detiene GPS
- ✅ Limpia Hive
- ✅ Limpia SharedPreferences
- ✅ Navega a LoginPage

**¿Por qué?** → Usuario está **activamente cerrando su sesión**, debe registrarse en backend.

---

#### 2️⃣ **Logout Remoto (Servidor envía comando FCM)**
**Archivo**: `fcm_handler.dart`
```dart
await LogoutService.executeLogout(
  isRemoteLogout: true,  // ← Tipo: "Remoto"
);
```
**¿Qué hace?**
- ✅ Llama a `registrarCierre()` con tipo `"Remoto"`
- ✅ Actualiza Firestore (mueve sesión a history)
- ✅ Detiene GPS (si no fue detenido por FCM)
- ✅ Limpia Hive
- ✅ Limpia SharedPreferences
- ✅ Navega a LoginPage

**¿Por qué?** → Servidor **ordenó cerrar la sesión**, debe registrarse en backend.

---

#### 3️⃣ **Sesión Inválida (Otro dispositivo inició sesión con mismo móvil)**
**Archivo**: `login_page.dart` línea 570
```dart
// ❌ NO ejecuta LogoutService.executeLogout()
// ✅ Solo ejecuta limpieza local:
await _cancelStreams();
await stopLocationService(); // Detener GPS local
await clearHiveBoxes(); // Limpiar Hive local
await clearSharedPreferences(); // Limpiar SharedPreferences
_showForcedLogoutDialog(); // Mostrar diálogo
```
**¿Qué hace?**
- ❌ NO llama a `registrarCierre()` (ya lo hizo el otro dispositivo)
- ❌ NO actualiza Firestore (ya lo hizo el otro dispositivo)
- ✅ Detiene GPS local (puede que aún esté activo)
- ✅ Limpia Hive local (datos ahora inválidos)
- ✅ Cancela streams locales
- ✅ Limpia SharedPreferences
- ✅ Muestra diálogo informativo

**¿Por qué?** → **Otro dispositivo ya cerró la sesión** al loguearse. Este dispositivo solo necesita **limpieza local**.

---

## 🔄 FLUJO DETALLADO

### **Escenario:**
1. **Dispositivo 1** (Usuario A) está logueado en HomePage con móvil 693
2. **Dispositivo 2** (Usuario B) se loguea con móvil 693
3. Dispositivo 2 ejecuta:
   - ✅ `registrarCierre()` para cerrar sesión de Usuario A
   - ✅ Actualiza Firestore (mueve sesión de A a history)
   - ✅ Detiene GPS de Usuario A (si lo puede hacer)
4. **Dispositivo 1** detecta sesión inválida en HomePage
5. Navega a LoginPage con `forcedLogout=true`

### **❌ ANTES (v1.0 y v2.0)**:
```dart
// v1.0: Ejecutaba logout completo (redundante)
await LogoutService.executeLogout(isRemoteLogout: false);
  ├─ registrarCierre() ← ❌ REDUNDANTE (ya lo hizo Dispositivo 2)
  ├─ Actualizar Firestore ← ❌ REDUNDANTE (ya lo hizo Dispositivo 2)
  └─ SessionService.cerrarSesion() ← ❌ REDUNDANTE

// v2.0: Solo streams (incompleto)
await _cancelStreams(); ← ✅ Correcto
// ❌ NO detenía GPS ni limpiaba Hive (podían quedar activos)
```

### **✅ DESPUÉS (v3.0 - CORRECTO)**:
```dart
await _cancelStreams(); // ✅ Cancela streams locales

// ✅ Detiene GPS local (por si quedó activo)
await platform.invokeMethod("stopLocationService", {...});

// ✅ Limpia Hive local (datos ahora inválidos)
await sessionBox.clear();
await constantBox.clear();
await mensajesBox.clear();
await failedRequestsBox.clear();

// ✅ Limpia SharedPreferences local
await prefs.setBool('sessionActive', false);

// ✅ Muestra diálogo informativo
_showForcedLogoutDialog(mensaje: widget.forcedLogoutMessage);

// ❌ NO llama a:
// - registrarCierre() (ya lo hizo Dispositivo 2)
// - Firestore updates (ya lo hizo Dispositivo 2)
// - SessionService.cerrarSesion() (ya lo hizo Dispositivo 2)
```

---

## 🔧 CÓDIGO IMPLEMENTADO

### **Archivo**: `lib/pages/login_page.dart` (líneas 570-655)

```dart
Future<void> _handleForcedLogoutAndShowDialog() async {
  try {
    print('🚨 [FORCED_LOGOUT] Sesión inválida detectada - Ejecutando limpieza LOCAL');
    
    // ⚠️ IMPORTANTE: NO ejecutar LogoutService.executeLogout() completo porque:
    // 1. La sesión YA FUE CERRADA por el otro dispositivo que se logueó
    // 2. registrarCierre YA FUE LLAMADO por el otro dispositivo
    // 3. Firestore YA FUE ACTUALIZADO por el otro dispositivo
    //
    // ✅ Solo necesitamos hacer LIMPIEZA LOCAL:
    // - Detener servicios GPS/background (si quedaron activos)
    // - Cancelar streams locales
    // - Limpiar datos de Hive local
    // - Limpiar SharedPreferences
    
    print('🧹 [FORCED_LOGOUT] Iniciando limpieza local (sin llamar a registrarCierre)');

    // 1️⃣ Cancelar streams locales
    await _cancelStreams();

    // 2️⃣ Detener servicio GPS/background si quedó activo
    try {
      var sessionBox = await Hive.openBox('sessionBox');
      final movil = sessionBox.get('movil') ?? "0";
      final escenario = sessionBox.get('escenario') ?? "0";
      final usuario = sessionBox.get('username') ?? "string";
      final idTerminal = sessionBox.get('deviceId') ?? "";

      final platform = MethodChannel("background_service");
      await platform.invokeMethod("stopLocationService", {
        "movil": movil,
        "escenario": escenario,
        "usuario": usuario,
        "deviceId": idTerminal,
      });
      print("🛑 [FORCED_LOGOUT] Servicio GPS detenido localmente");
    } catch (e) {
      print('⚠️ [FORCED_LOGOUT] Error deteniendo GPS (puede que ya esté detenido): $e');
    }

    // 3️⃣ Limpiar datos locales de Hive (NO afecta backend ni Firestore)
    try {
      var sessionBox = await Hive.openBox('sessionBox');
      var constantBox = await Hive.openBox('constantBox');
      var mensajesBox = await Hive.openBox('mensajesBox');
      var failedRequestsBox = await Hive.openBox('failedRequestsBox');

      await sessionBox.clear();
      await constantBox.clear();
      await mensajesBox.clear();
      await failedRequestsBox.clear();

      // Marcar flags de logout controlado
      sessionBox.put('firstLoginDone', true);
      sessionBox.put('logoutControlled', true);

      print('🧹 [FORCED_LOGOUT] Hive boxes limpiados localmente');
    } catch (e) {
      print('❌ [FORCED_LOGOUT] Error limpiando Hive: $e');
    }

    // 4️⃣ Limpiar SharedPreferences (sessionActive flag)
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sessionActive', false);
      print("🧹 [FORCED_LOGOUT] SharedPreferences limpiado (sessionActive=false)");
    } catch (e) {
      print('❌ [FORCED_LOGOUT] Error limpiando SharedPreferences: $e');
    }

    // 5️⃣ Mostrar diálogo informativo al usuario
    if (mounted) {
      _showForcedLogoutDialog(
        mensaje: widget.forcedLogoutMessage ??
            'Su sesión ha sido cerrada. Por favor, inicie sesión nuevamente.',
      );
    }

    print('✅ [FORCED_LOGOUT] Limpieza local completada (SIN llamar a registrarCierre)');
  } catch (e) {
    print('❌ Error en limpieza local de sesión inválida: $e');
  }
}
```

---

## ✅ BENEFICIOS DE v3.0

1. **✅ Limpieza Completa**: Detiene GPS, limpia Hive, cancela streams
2. **✅ Sin Redundancia**: NO llama a `registrarCierre` (ya lo hizo otro dispositivo)
3. **✅ Métricas Correctas**: NO registra doble cierre
4. **✅ Performance**: NO hace llamadas innecesarias al backend
5. **✅ Estado Limpio**: Dispositivo queda listo para re-login inmediato

---

## 🧪 TESTING

### **Logs Esperados**:
```
🚨 [FORCED_LOGOUT] Sesión inválida detectada - Ejecutando limpieza LOCAL
🧹 [FORCED_LOGOUT] Iniciando limpieza local (sin llamar a registrarCierre)
🔴 Todos los streams cancelados.
🛑 [FORCED_LOGOUT] Servicio GPS detenido localmente
🧹 [FORCED_LOGOUT] Hive boxes limpiados localmente
🧹 [FORCED_LOGOUT] SharedPreferences limpiado (sessionActive=false)
✅ [FORCED_LOGOUT] Limpieza local completada (SIN llamar a registrarCierre)
```

### **Validar en Backend**:
```sql
-- Solo debería haber 1 registro de cierre (del Dispositivo 2 que hizo login)
SELECT * FROM cierres_sesion WHERE movil = 693 ORDER BY fecha DESC LIMIT 2;
-- Resultado esperado: 1 fila con tipo "Controlado" (del Dispositivo 2)
```

### **Validar en Firestore**:
```javascript
// Solo debería haber 1 documento en history (movido por Dispositivo 2)
db.collection('Sesiones-{escenarioId}')
  .doc('{fechaActual}')
  .collection('Movil-693')
  .where('logout', '!=', null)
  .get()
// Resultado esperado: 1 documento con logout="Controlado" (del Dispositivo 2)
```

---

## 📚 ARCHIVOS RELACIONADOS

- `lib/pages/login_page.dart` (líneas 570-655) - **MODIFICADO**
- `lib/pages/home_page.dart` (línea 320-350) - Detecta sesión inválida
- `lib/services/logout_service.dart` - NO usado en forcedLogout (solo en logout real)

---

## 🔗 HISTORIAL DE VERSIONES

| Versión | Fecha | Cambio | Estado |
|---------|-------|--------|--------|
| v1.0 | 2025-01-21 | Cambió `isRemoteLogout: true` → `false` | ❌ Incorrecto |
| v2.0 | 2025-01-21 | Eliminó `LogoutService.executeLogout()` completamente | ⚠️ Incompleto |
| v3.0 | 2025-01-21 | Agregó limpieza local (GPS, Hive, SharedPreferences) | ✅ Correcto |

---

**Autor**: Sistema AI Assistant  
**Revisado por**: Usuario (jgomez)  
**Última actualización**: 2025-01-21 18:45 UTC-3
