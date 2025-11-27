# 🔁 FIX: firstLoginDone Lifecycle - Conflict Dialog Only Shows Once

## 📋 Problema Reportado

**Síntoma:**
```
1. PRIMER LOGIN:
   - Usuario selecciona móvil 693
   - Sistema detecta conflicto (otro usuario en ese móvil)
   - Muestra diálogo: "¿Desea desloguear al usuario actual?"
   - ✅ FUNCIONA CORRECTAMENTE

2. SEGUNDO LOGIN (mismo usuario, mismo móvil):
   - Usuario selecciona móvil 693
   - Sistema detecta conflicto
   - ❌ NO MUESTRA DIÁLOGO
   - Se loguea automáticamente y desloguea al otro usuario
   
3. RESULTADO:
   - Ciclo eterno entre 2 dispositivos
   - Sin confirmación del usuario
   - Comportamiento inconsistente
```

**Logs Observados:**
```
17:19:28 - firstLoginDone: true (guardado en sessionBox)
17:19:33 - ✅ Sesión guardada sin conflicto
17:19:39 - [FCM] Comando Force GPS ignorado (sin sesión activa)

[Segundo intento de login]
17:21:45 - firstLoginDone: true
17:21:45 - [SESSION_SERVICE] Verificando usuario logueado en otro móvil
17:21:46 - [SESSION_SERVICE] ⚠️ Móvil 693 en uso por otro usuario
17:21:46 - ❌ NO MUESTRA DIÁLOGO (firstLoginDone ya es false)
```

---

## 🔍 Root Cause Analysis

### 1. Funcionamiento Normal del Flag

```dart
// PRIMER LOGIN - ✅ FUNCIONA:

Login Page (línea ~2110):
await box.put('firstLoginDone', true);  // Se setea a TRUE
                                        
HomePage initState (línea ~1190):
Timer(Duration(seconds: 10), () {
  box.put('firstLoginDone', false);    // Después de 10s → FALSE
});

// Durante esos 10 segundos:
ValueListenableBuilder<Box>(
  builder: (context, box, _) {
    if (box.get('firstLoginDone', defaultValue: false)) {
      return Container(); // ❌ BLOQUEA validación de sesión
    }
    // Validación normal...
  }
)

// Resultado:
// ✅ Durante 10s: Conflictos pueden detectarse y mostrar diálogo
// ✅ HomePage no ejecuta forced logout
```

### 2. El Bug - Logout NO Reseteaba el Flag

```dart
// PROBLEMA IDENTIFICADO:

Logout Manual/Forzado/Auto-logout:
// ❌ firstLoginDone NUNCA se reseteaba a TRUE
sessionBox.put('logoutControlled', true);
sessionBox.put('sessionActive', false);
// ... limpieza de datos

// Resultado:
// firstLoginDone quedaba en FALSE ← ❌ PROBLEMA
```

### 3. Segundo Login Fallaba

```dart
// SEGUNDO LOGIN - ❌ ROTO:

Login Page (línea ~2110):
await box.put('firstLoginDone', true);  // Se setea a TRUE
                                        
HomePage initState (línea ~1190):
// 🚨 PERO HomePage YA estaba inicializado desde primer login
// Timer YA corrió hace 10s en el primer login
// firstLoginDone YA es FALSE desde antes

// Durante validación de conflicto:
final firstLoginDone = box.get('firstLoginDone', defaultValue: false);
// ← Retorna FALSE (nunca se reseteó en logout)

if (firstLoginDone) {
  return Container(); // 🚨 NUNCA entra aquí
}

// Continúa validación → Detecta conflicto → NO muestra diálogo
// Porque la validación NO está bloqueada (flag es false)
```

---

## 🔧 Solución Implementada

### Cambio 1: Resetear firstLoginDone en LogoutService

**Archivo:** `lib/services/logout_service.dart`

**Cambio:**
```dart
// ANTES (línea 60):
// ❌ NO setear firstLoginDone=true aquí (solo debe setearse en LOGIN)
// sessionBox.put('firstLoginDone', true);  // REMOVED: Causaba que se ignore logout forzado
sessionBox.put('logoutControlled', true);

// DESPUÉS (línea 63-68):
// ✅ Resetear flag firstLoginDone para próximo login
// Este flag debe estar en TRUE cuando NO hay sesión activa
// Cuando se hace login, se setea a true y después de 10s se pone a false
// Al hacer logout (forzado o manual), debe volver a TRUE para el próximo login
await sessionBox.put('firstLoginDone', true);
print('$TAG ✅ firstLoginDone reseteado a TRUE (listo para próximo login)');

// Marcar bandera de logout controlado (para evitar loops de logout forzado)
sessionBox.put('logoutControlled', true);
```

**Propósito:**
- Resetear `firstLoginDone = true` en CADA logout
- Garantiza que próximo login tenga el flag en estado correcto
- Aplica a logout manual, forzado y auto-logout

---

### Cambio 2: Refactorizar Auto-logout por Cambio de Día

**Archivo:** `lib/services/firebase_service.dart`

**Problema:**
```dart
// ANTES - ❌ Implementación duplicada:
Future<void> _performAutoLogout(Box sessionBox) async {
  // 1️⃣ Detener GPS service (código duplicado)
  await platform.invokeMethod("stopLocationService", ...);
  
  // 2️⃣ Registrar cierre (código duplicado)
  await RioGasService.registrarCierre(...);
  
  // 3️⃣ Cancelar streams (código duplicado)
  PersistentStreamManager().dispose();
  
  // 4️⃣ Limpiar Hive (código duplicado)
  await sessionBox.clear();
  
  // ❌ NO resetea firstLoginDone
}
```

**Solución:**
```dart
// DESPUÉS - ✅ Usa LogoutService:
Future<void> _performAutoLogout(Box sessionBox) async {
  try {
    print('$kFirebaseSesionesTag 🛑 AUTO-LOGOUT por cambio de día');
    
    // 🔥 USAR LogoutService.executeLogout() para consistencia
    // Esto garantiza que:
    // 1. firstLoginDone se resetee a true
    // 2. GPS service se detenga correctamente
    // 3. Backend registre el cierre
    // 4. Hive y SharedPreferences se limpien
    await LogoutService.executeLogout(
      isRemoteLogout: false, // Es auto-logout por cambio de día
    );
    
    print('$kFirebaseSesionesTag ✅ AUTO-LOGOUT COMPLETADO (via LogoutService)');
  } catch (e) {
    print('$kFirebaseSesionesTag ❌ Error en auto-logout: $e');
  }
}
```

**Import agregado (línea 14):**
```dart
import 'logout_service.dart'; // 🔥 Para auto-logout por cambio de día
```

**Beneficios:**
- ✅ Elimina código duplicado (~60 líneas)
- ✅ Garantiza consistencia con otros tipos de logout
- ✅ firstLoginDone se resetea correctamente
- ✅ Un solo punto de mantenimiento

---

## 📊 Nuevo Ciclo de Vida del Flag

### Estado Correcto (DESPUÉS del Fix)

```
┌─────────────────────────────────────────────────┐
│ Estado Inicial (Sin sesión activa)              │
│ firstLoginDone = TRUE                            │
└─────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│ LOGIN (login_page.dart línea ~2110)             │
│ firstLoginDone = TRUE                            │
│ ✅ Se sobreescribe con mismo valor (seguro)     │
└─────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│ HomePage initState (home_page.dart ~1190)       │
│ Timer 10s → firstLoginDone = FALSE              │
│ ✅ Durante 10s: Validación BLOQUEADA            │
└─────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│ LOGOUT (manual/forzado/auto)                    │
│ LogoutService.executeLogout()                   │
│ firstLoginDone = TRUE ← 🔥 FIX APLICADO         │
│ ✅ Resetea flag para próximo login              │
└─────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│ SEGUNDO LOGIN (login_page.dart ~2110)           │
│ firstLoginDone = TRUE                            │
│ ✅ Flag estaba en TRUE (correcto)               │
└─────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│ HomePage initState (segunda vez)                │
│ Timer 10s → firstLoginDone = FALSE              │
│ ✅ Durante 10s: Validación BLOQUEADA            │
│ ✅ Diálogo de conflicto PUEDE aparecer          │
└─────────────────────────────────────────────────┘
```

### Comparación - Antes vs Después

| Evento | ANTES (ROTO ❌) | DESPUÉS (FIX ✅) |
|--------|-----------------|------------------|
| Estado inicial | TRUE | TRUE |
| Primer login | TRUE | TRUE |
| HomePage timer (10s) | FALSE | FALSE |
| **Logout manual** | **FALSE** (sin cambio) | **TRUE** (reseteado) |
| **Logout forzado** | **FALSE** (sin cambio) | **TRUE** (reseteado) |
| **Auto-logout día** | **FALSE** (sin cambio) | **TRUE** (reseteado) |
| Segundo login | TRUE | TRUE |
| HomePage timer (10s) | **FALSE** (YA era false) | FALSE (correcto) |
| **Diálogo conflicto** | **❌ NO aparece** | **✅ SÍ aparece** |

---

## 🧪 Plan de Testing

### Escenario 1: Login → Logout Manual → Login

**Pasos:**
1. **Dispositivo A**: Login usuario 49618553, móvil 693
2. **Dispositivo A**: Logout manual desde Settings
3. **Dispositivo A**: Login de nuevo usuario 49618553, móvil 693

**Logs Esperados:**
```
[Primer login]
17:19:28 - firstLoginDone: true (login_page.dart)
17:19:33 - ✅ Sesión guardada sin conflicto
17:19:38 - (Timer: firstLoginDone = false)

[Logout manual]
17:20:00 - LogoutService ✅ firstLoginDone reseteado a TRUE
17:20:00 - LogoutService 🛑 Servicio GPS detenido
17:20:00 - LogoutService 🧹 Hive boxes limpiados

[Segundo login]
17:20:30 - firstLoginDone: true (login_page.dart)
17:20:30 - [SESSION_SERVICE] Verificando usuario logueado en otro móvil
17:20:31 - [SESSION_SERVICE] ⚠️ Móvil 693 en uso por otro usuario
17:20:31 - 🔔 CONFLICT DIALOG SHOWN ← ✅ DEBE APARECER
```

**Resultado Esperado:**
- ✅ Diálogo de conflicto APARECE
- ✅ Usuario puede confirmar o cancelar

---

### Escenario 2: Login → Forced Logout → Login

**Pasos:**
1. **Dispositivo A**: Login usuario 49618553, móvil 693
2. **Dispositivo B**: Login usuario 27861374, móvil 693 (kicks A)
3. **Dispositivo A**: Login de nuevo usuario 49618553, móvil 693

**Logs Esperados:**
```
[Dispositivo A - Primer login]
17:25:00 - firstLoginDone: true
17:25:05 - ✅ Sesión activa

[Dispositivo B - Login que desloguea A]
17:25:30 - [SESSION_SERVICE] Móvil 693 tomado por usuario 27861374

[Dispositivo A - Forced logout]
17:25:31 - [HOME_SESSION] 🚨 Sesión inválida detectada
17:25:31 - LogoutService ✅ firstLoginDone reseteado a TRUE
17:25:31 - LogoutService ✅ Limpieza completada

[Dispositivo A - Segundo login]
17:26:00 - firstLoginDone: true (login_page.dart)
17:26:01 - [SESSION_SERVICE] ⚠️ Móvil 693 en uso por usuario 27861374
17:26:01 - 🔔 CONFLICT DIALOG SHOWN ← ✅ DEBE APARECER
```

**Resultado Esperado:**
- ✅ Forced logout resetea flag
- ✅ Segundo login muestra diálogo
- ✅ Usuario puede recuperar su sesión con confirmación

---

### Escenario 3: Login → Auto-logout (Cambio Día) → Login

**Pasos:**
1. **Dispositivo A**: Login usuario 49618553, móvil 693 (día 1)
2. **Sistema**: Detecta cambio de día (día 2)
3. **Dispositivo A**: Login de nuevo usuario 49618553, móvil 693

**Logs Esperados:**
```
[Día 1 - Login]
08:00:00 - firstLoginDone: true
08:00:00 - 📅 Fecha de login guardada: 2025-01-20
08:00:05 - ✅ Sesión activa

[Día 2 - 00:00:00 - Auto-logout]
00:00:00 - [FIREBASE_SESIONES] 🌅 CAMBIO DE DÍA DETECTADO
00:00:00 - [FIREBASE_SESIONES]    Login: 2025-01-20
00:00:00 - [FIREBASE_SESIONES]    Hoy: 2025-01-21
00:00:00 - [FIREBASE_SESIONES] 🛑 AUTO-LOGOUT por cambio de día
00:00:00 - LogoutService ✅ firstLoginDone reseteado a TRUE
00:00:00 - [FIREBASE_SESIONES] ✅ AUTO-LOGOUT COMPLETADO (via LogoutService)

[Día 2 - Login]
08:00:00 - firstLoginDone: true (login_page.dart)
08:00:01 - [SESSION_SERVICE] Verificando usuario logueado en otro móvil
08:00:01 - 🔔 CONFLICT DIALOG SHOWN (si hay conflicto) ← ✅ DEBE APARECER
```

**Resultado Esperado:**
- ✅ Auto-logout resetea flag
- ✅ LogoutService se usa (no código duplicado)
- ✅ Próximo login funciona correctamente

---

### Escenario 4: Múltiples Intentos de Login

**Pasos:**
1. Repetir Escenario 1 o 2 **cinco veces consecutivas**

**Resultado Esperado:**
- ✅ Diálogo aparece en TODOS los intentos
- ✅ NO solo en el primero
- ✅ Comportamiento consistente

---

## ✅ Checklist de Validación

### Flags y Estados
- [ ] firstLoginDone = TRUE en estado inicial (sin sesión)
- [ ] firstLoginDone = TRUE tras login
- [ ] firstLoginDone = FALSE después de 10s (timer en HomePage)
- [ ] **firstLoginDone = TRUE tras logout manual**
- [ ] **firstLoginDone = TRUE tras logout forzado**
- [ ] **firstLoginDone = TRUE tras auto-logout cambio día**

### Diálogos de Conflicto
- [ ] Diálogo aparece en primer login con conflicto
- [ ] **Diálogo aparece en segundo login con conflicto**
- [ ] **Diálogo aparece en tercer+ login con conflicto**
- [ ] Diálogo NO aparece cuando no hay conflicto

### Integración de LogoutService
- [ ] Settings manual logout usa LogoutService
- [ ] Forced logout (home_page.dart) usa LogoutService
- [ ] Auto-logout cambio día usa LogoutService
- [ ] Todos resetean firstLoginDone correctamente

### Race Condition (Fix anterior - Fase 12)
- [ ] Login exitoso NO causa forced logout inmediato
- [ ] Delay de 15s funciona correctamente
- [ ] Progress indicator muestra "Verificando sesión... Xs / 15s"

---

## 📁 Archivos Modificados

### 1. `lib/services/logout_service.dart`
- **Línea 63-68**: Agregado reseteo de firstLoginDone
- **Propósito**: Garantizar flag correcto para próximo login

### 2. `lib/services/firebase_service.dart`
- **Línea 14**: Import de logout_service.dart
- **Línea 1070-1090**: Refactorizado _performAutoLogout()
- **Propósito**: Usar LogoutService en lugar de código duplicado

---

## 🎯 Impacto del Fix

### Antes (ROTO ❌)
```
Usuario: "Me logueo → me desloguean → intento loguearme de nuevo"
Sistema: Se loguea automáticamente sin preguntar
Usuario: "El otro dispositivo es deslogueado sin avisar"
Sistema: [Ciclo infinito entre dispositivos]
Usuario: "Nunca más me sale el cartel de confirmación"
```

### Después (FIX ✅)
```
Usuario: "Me logueo → me desloguean → intento loguearme de nuevo"
Sistema: "⚠️ El móvil 693 está en uso por otro usuario"
Sistema: "¿Desea desloguear al usuario actual?"
Usuario: [Presiona SÍ]
Sistema: Desloguea al otro usuario con confirmación
Usuario: "Perfecto, siempre me pide confirmación"
```

---

## 🔗 Fixes Relacionados

1. **FIX_LOGIN_RACE_CONDITION.md** (Fase 12)
   - Problema: Login exitoso → Immediate forced logout
   - Solución: Delay de 15s para escritura Firestore
   - Estado: ✅ Deployed, working

2. **FIX_LOGOUT_TYPE_CORRECTION.md** (Fase 9)
   - Problema: firstLoginDone bloqueaba forced logout
   - Solución: Remover seteo incorrecto en logout_service
   - Estado: ✅ Fixed, pero incompleto (no reseteaba flag)

3. **FIX_FIRSTLOGINDONE_LIFECYCLE.md** (ESTE - Fase 14)
   - Problema: Flag nunca se reseteaba en logout
   - Solución: Resetear a TRUE en logout_service + refactor auto-logout
   - Estado: ✅ Deployed, pending testing

---

## 📝 Notas de Implementación

### Filosofía del Flag

**firstLoginDone representa:** "¿Hay una sesión activa que NO necesita validarse inmediatamente?"

**Estados válidos:**
```
TRUE  = NO hay sesión activa (logout completo)
TRUE  = Login recién iniciado (primeros 10s)
FALSE = Sesión establecida (después de 10s)
```

**Regla de oro:**
> El flag debe estar en TRUE cuando NO hay sesión activa. 
> Esto garantiza que el próximo login tenga 10s de protección 
> contra validaciones prematuras.

### Por Qué 3 Lugares Usan LogoutService

Todos los tipos de logout comparten el mismo flujo:
1. Stop GPS service
2. Registrar cierre en backend
3. Limpiar Hive boxes
4. Limpiar SharedPreferences
5. **Resetear firstLoginDone** ← CRÍTICO

Tener código duplicado causó el bug original. La centralización en `LogoutService` garantiza consistencia.

---

## 🚀 Deployment

```powershell
# Deploy del fix
cd C:\Users\jgomez\Documents\Projects\AppTFlutter\appmovil
flutter install

# Monitor logs durante testing
adb logcat | Select-String "firstLoginDone|SESSION_SERVICE|LogoutService|CONFLICT"
```

**Build Time:** ~6.6s
**Status:** ✅ Deployed to Blade10 Pro

---

## 📊 Resumen Ejecutivo

| Aspecto | Estado |
|---------|--------|
| **Problema** | Diálogo de conflicto solo aparecía una vez |
| **Root Cause** | firstLoginDone nunca se reseteaba en logout |
| **Solución** | Resetear flag en LogoutService.executeLogout() |
| **Archivos Modificados** | 2 (logout_service.dart, firebase_service.dart) |
| **Líneas Agregadas** | ~10 |
| **Líneas Eliminadas** | ~60 (código duplicado) |
| **Testing** | Pending device validation |
| **Risk** | Low (refactor consolidates logic) |
| **Impact** | High (fixes critical UX bug) |

---

**Fecha:** 2025-01-20
**Autor:** AI Assistant
**Fase:** 14 - firstLoginDone Lifecycle Fix
**Status:** ✅ Code Complete, 🧪 Pending Testing
