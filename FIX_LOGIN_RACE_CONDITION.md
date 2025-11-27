# 🐛 FIX: Race Condition entre Login y Validación de Sesión Firestore

## 📋 Problema Identificado

**Síntoma:** Usuario se loguea exitosamente, pero inmediatamente después recibe mensaje de "Sesión inválida" o "Su sesión ha expirado o está siendo usada por otro dispositivo".

**Logs del error:**
```
16:56:16 - ✅ Login exitoso (móvil 693, usuario 49618553)
16:56:16 - [FIREBASE_SESIONES] ⚠️ Documento NO existe - Sesión inválida
16:56:16 - 🚫 [HOME_PAGE] Sesión INVÁLIDA detectada - Redirigiendo a login
16:56:21 - 🚨 [FORCED_LOGOUT] Sesión inválida detectada - Ejecutando limpieza LOCAL
```

## 🔍 Causa Raíz

**Race condition** entre la escritura de sesión en Firestore y la validación de sesión en HomePage:

### Secuencia del Bug:

1. **T=0s:** Usuario completa login en `login_page.dart`
   - `_saveSession()` se llama
   - Firestore empieza a escribir el documento de sesión
   - Navigate a HomePage
   
2. **T=0.1s:** HomePage `initState()` se ejecuta
   - `PersistentStreamManager.initialize()` se llama
   - Firestore listener se suscribe a `sessions-{escenario}/{fecha}/activeSessions/{usuario}`
   
3. **T=0.2s:** Listener recibe **snapshot inicial**
   - Firestore aún está escribiendo el documento
   - `data == null` (documento no existe todavía)
   
4. **T=0.3s:** Validación de sesión se ejecuta
   - `firstLoginDone == true` (flag aún no resetado, se resetea a los 10s)
   - `tiempoDesdeInit < 3s` → **NO entra en período de gracia** (el delay era muy corto)
   - `data == null` → Interpreta como "sesión inválida"
   - **Ejecuta forced logout INMEDIATAMENTE**
   
5. **T=1s:** Firestore termina de escribir el documento
   - Ya es tarde, usuario ya fue deslogueado

## ✅ Solución Aplicada

### Cambios en `home_page.dart`:

**ANTES (delay de 3 segundos):**
```dart
if (data == null && tiempoDesdeInit < 3) {
  print('[HOME_SESSION] ⏳ Esperando validación inicial de sesión...');
  return Center(child: CircularProgressIndicator());
} else if (data == null) {
  // ❌ Ejecuta forced logout si pasan 3s y documento aún no existe
  forzarDeslogueoYRedirigir(...);
}
```

**DESPUÉS (delay de 15 segundos):**
```dart
// ⏰ AUMENTADO A 15s: Dar tiempo suficiente para que Firestore termine de escribir la sesión tras login
//    Esto previene forced logout durante el período de gracia de firstLoginDone (10s)
if (data == null && tiempoDesdeInit < 15) {
  print('[HOME_SESSION] ⏳ Esperando validación inicial de sesión (${tiempoDesdeInit}s / 15s)...');
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 20),
        Text('Verificando sesión...'),
        SizedBox(height: 10),
        Text('${tiempoDesdeInit}s / 15s'), // ✅ Indicador de progreso
      ],
    ),
  );
} else if (data == null) {
  // ✅ Solo ejecuta forced logout si pasan 15s Y documento no existe
  forzarDeslogueoYRedirigir(...);
}
```

### Lógica de Protección:

1. **firstLoginDone flag** (líneas ~135-148 en `home_page.dart`)
   - Se setea a `true` durante login (login_page.dart ~2110)
   - Se resetea a `false` después de **10 segundos** (home_page.dart ~145)
   - Bloquea detección de sesión inválida durante ese período
   
2. **tiempoDesdeInit < 15s** (nuevo delay)
   - Muestra loader durante los primeros **15 segundos** si documento no existe
   - Da tiempo a Firestore para terminar escritura de sesión
   - Muestra progreso al usuario: "Verificando sesión... 3s / 15s"
   
3. **data == null solo después de 15s**
   - Si después de 15 segundos el documento sigue sin existir
   - **ENTONCES** es legítimo ejecutar forced logout
   - Porque significa que otro dispositivo tomó el móvil

## 🎯 Archivos Modificados

### `home_page.dart` (2 lugares actualizados):

**Lugar 1: ValueListenableBuilder principal (líneas ~1220-1250)**
```dart
// ⏰ AUMENTADO A 15s: Dar tiempo suficiente para que Firestore termine de escribir la sesión tras login
if (data == null && tiempoDesdeInit < 15) {
  print('[HOME_SESSION] ⏳ Esperando validación inicial de sesión (${tiempoDesdeInit}s / 15s)...');
  return Center(child: CircularProgressIndicator() + timer);
}
```

**Lugar 2: ValueListenableBuilder post-future (líneas ~1310-1340)**
```dart
// ⏰ PROTECCIÓN: Mismo delay de 15s que el primer ValueListenableBuilder
if (data == null && tiempoDesdeInit < 15) {
  print('[HOME_SESSION] ⏳ (POST-FUTURE) Esperando validación inicial de sesión (${tiempoDesdeInit}s / 15s)...');
  return Center(child: CircularProgressIndicator() + timer);
}
```

## 📊 Flujo Corregido

### ANTES (Bug):
```
Login → Navigate → Listener subscribe (0.1s)
                    ↓
              Snapshot inicial: data=null
                    ↓
              Wait 3s → TIMEOUT → Forced Logout ❌
                    ↓
              Firestore termina escritura (demasiado tarde)
```

### DESPUÉS (Fix):
```
Login → Navigate → Listener subscribe (0.1s)
                    ↓
              Snapshot inicial: data=null
                    ↓
              Wait 15s → Mostrar loader + timer
                    ↓
              Firestore termina escritura (1-3s)
                    ↓
              Snapshot actualizado: data!=null
                    ↓
              HomePage carga normalmente ✅
```

## 🧪 Testing

### Escenario 1: Login Normal (Sin Conflicto)
**Esperado:** Usuario ve loader "Verificando sesión... 1s / 15s" por ~2-3 segundos, luego HomePage carga.

**Logs esperados:**
```
16:56:16 - ✅ Login exitoso
16:56:16 - [HOME_SESSION] ⏳ Esperando validación inicial de sesión (1s / 15s)...
16:56:17 - [HOME_SESSION] ⏳ Esperando validación inicial de sesión (2s / 15s)...
16:56:18 - [HOME_SESSION] ✅ Datos recibidos desde sesionesNotifier
16:56:18 - HomePage cargada exitosamente
```

### Escenario 2: Login con Conflicto (Otro Dispositivo Tomó Móvil)
**Esperado:** Usuario ve loader por 15 segundos completos, luego forced logout.

**Logs esperados:**
```
16:56:16 - ✅ Login exitoso
16:56:16 - [HOME_SESSION] ⏳ Esperando validación inicial de sesión (1s / 15s)...
...
16:56:31 - [HOME_SESSION] ⏳ Esperando validación inicial de sesión (15s / 15s)...
16:56:31 - [HOME_SESSION] ❌ Documento eliminado o null desde sesionesNotifier
16:56:31 - [FORCED_LOGOUT] Sesión inválida detectada - Ejecutando limpieza LOCAL
```

### Escenario 3: firstLoginDone Flag (10s)
**Esperado:** Durante los primeros 10s tras login, validación de sesión completamente bloqueada.

**Logs esperados:**
```
16:56:16 - ✅ Login exitoso (firstLoginDone=true)
16:56:17 - [HOME_SESSION] Ignorando logout forzado por primer login manual...
...
16:56:26 - (Timer de 10s completa, firstLoginDone=false)
16:56:27 - [HOME_SESSION] Validación de sesión habilitada
```

## 📝 Notas Adicionales

### ¿Por qué 15 segundos y no 5?

1. **Latencia de Firestore:** En conexiones lentas, escritura puede tomar 3-5s
2. **Buffer de seguridad:** firstLoginDone se resetea a los 10s → 15s da margen adicional
3. **UX:** Loader con timer da feedback al usuario (no parece freeze)
4. **Worst case:** Forced logout legítimo solo se retrasa 12s adicionales (15s vs 3s anterior)

### Flags de Protección:

| Flag | Duración | Propósito |
|------|----------|-----------|
| `firstLoginDone` | 10s | Bloquea totalmente validación post-login |
| `tiempoDesdeInit < 15s` | 15s | Muestra loader si documento no existe aún |
| `logoutControlled` | Permanente | Previene forced logout si logout fue manual |

### Orden de Prioridad:

1. **firstLoginDone** (más restrictivo) → Ignora CUALQUIER validación
2. **tiempoDesdeInit < 15s** → Muestra loader, no ejecuta logout
3. **data == null** → Solo ejecuta logout si ambos anteriores son false

## ✅ Status

- ✅ Fix aplicado en `home_page.dart` (2 lugares)
- ✅ Delay aumentado de 3s a 15s
- ✅ Indicador de progreso agregado (timer visible)
- ✅ Logs mejorados con contador de tiempo
- 🧪 **Pendiente:** Testing en dispositivo real

## 🔗 Relacionado

- `FIX_FORCED_LOGOUT_LOCAL_CLEANUP.md` (v3.0) - Limpieza inmediata pre-navegación
- `logout_service.dart` (línea 60 removed) - firstLoginDone no se setea en logout
- `login_page.dart` (línea ~2110) - firstLoginDone se setea en login

---

**Fecha:** 2025-11-21  
**Issue:** Login exitoso seguido de forced logout inmediato  
**Root Cause:** Race condition Firestore write vs listener validation  
**Solution:** Aumentar delay de gracia de 3s a 15s + indicador de progreso
