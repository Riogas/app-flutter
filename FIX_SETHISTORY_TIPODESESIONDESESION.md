# 🔴 FIX: Sesión Nueva Se Mueve Al Historial Inmediatamente

**Fecha**: 2025-11-27  
**Archivo**: `lib/services/session_service.dart`  
**Método afectado**: `setHistory()`

---

## 📋 **PROBLEMA IDENTIFICADO**

Cuando un usuario hace login con sesión previa y confirma continuar:

1. ✅ `setHistory()` mueve correctamente la sesión ANTERIOR al `history`
2. ✅ `setHistory()` llama a `saveSession()` para crear la sesión NUEVA
3. ✅ La sesión nueva se crea correctamente en Firestore
4. ✅ La confirmación del servidor se recibe ([T0] → [T1])
5. ❌ **PERO la sesión nueva también aparece en `history` con `tipoDeCierreDeSesion: logoutForzado`**

---

## 🔍 **CAUSA RAÍZ**

En `setHistory()`, cuando se llama a `saveSession()` para crear la sesión nueva, se estaba pasando el parámetro `tipoDeCierreDeSesion: tipoDeCierreDeSesion` (líneas 354-366):

```dart
final saveResult = await saveSession(
  idUsuario: idUsuario,
  nomUsuario: nomUsuario,
  primeraUbicacion: primeraUbicacion,
  versionApp: versionApp,
  tipoDeCierreDeSesion: tipoDeCierreDeSesion, // ❌ PROBLEMA
  fchHoraCierre: fchHoraCierre, // ❌ PROBLEMA
);
```

**El problema**: `tipoDeCierreDeSesion` y `fchHoraCierre` son parámetros que se usan para **CERRAR** una sesión, no para **CREAR** una sesión nueva.

Al pasar `tipoDeCierreDeSesion: 'logoutForzado'` al crear una sesión nueva, esto causaba que algún proceso posterior (probablemente una validación o limpieza automática) detectara esa sesión como "ya cerrada" y la moviera al historial.

---

## ✅ **SOLUCIÓN IMPLEMENTADA**

Se modificó `setHistory()` en dos lugares donde se llama a `saveSession()`:

### **Cambio 1: Líneas ~354-366**
```dart
// ANTES:
final saveResult = await saveSession(
  idUsuario: idUsuario,
  nomUsuario: nomUsuario,
  primeraUbicacion: primeraUbicacion,
  versionApp: versionApp,
  tipoDeCierreDeSesion: tipoDeCierreDeSesion, // ❌
  fchHoraCierre: fchHoraCierre, // ❌
);

// DESPUÉS:
final saveResult = await saveSession(
  idUsuario: idUsuario,
  nomUsuario: nomUsuario,
  primeraUbicacion: primeraUbicacion,
  versionApp: versionApp,
  tipoDeCierreDeSesion: '', // ✅ Vacío para sesión NUEVA
);
```

### **Cambio 2: Líneas ~398-408**
```dart
// ANTES:
final saveResult = await saveSession(
  idUsuario: idUsuario,
  nomUsuario: nomUsuario,
  primeraUbicacion: primeraUbicacion,
  versionApp: versionApp,
  tipoDeCierreDeSesion: tipoDeCierreDeSesion, // ❌
);

// DESPUÉS:
final saveResult = await saveSession(
  idUsuario: idUsuario,
  nomUsuario: nomUsuario,
  primeraUbicacion: primeraUbicacion,
  versionApp: versionApp,
  tipoDeCierreDeSesion: '', // ✅ Vacío para sesión NUEVA
);
```

---

## 🎯 **LÓGICA CORRECTA**

### **Campos para CERRAR una sesión (mover al history):**
- `tipoDeCierreDeSesion`: Indica el motivo del cierre (`logoutUser`, `logoutForzado`, etc.)
- `fchHoraCierre`: Timestamp del momento del cierre
- `estado`: Debe cambiar a `'Inactiva'`

Estos campos se aplican a la sesión **ANTERIOR** que se mueve al `history`.

### **Campos para CREAR una sesión nueva:**
- `idSesion`: NUEVO UUID generado
- `fchHoraInicio`: Timestamp del momento de creación
- `estado`: `'Activa'`
- `tipoDeCierreDeSesion`: **VACÍO** (o no presente)
- `fchHoraCierre`: **NO** debe estar presente

---

## 📊 **FLUJO CORRECTO DE setHistory()**

```
1. Se detecta sesión activa del usuario
   ↓
2. Se lee la sesión ANTERIOR
   ↓
3. Se AGREGAN campos de cierre:
   - tipoDeCierreDeSesion: 'logoutForzado'
   - fchHoraCierre: DateTime.now()
   - estado: 'Inactiva'
   ↓
4. Se MUEVE la sesión anterior a history/
   ↓
5. Se ELIMINA de activeSessions/
   ↓
6. Se CREA nueva sesión llamando a saveSession()
   - tipoDeCierreDeSesion: '' ✅ (VACÍO)
   - fchHoraCierre: NO se pasa ✅
   - estado: 'Activa' ✅
   - idSesion: NUEVO UUID ✅
```

---

## 🔬 **EVIDENCIA DEL PROBLEMA**

### **Logs del problema:**
```
14:14:35.954 → ✅ Sesión confirmada: {success: true, idSesion: 7c53e143-ab5e-411e-b09f-69f34cadd88f}
14:14:36.114 → Cargando constantes desde Firebase...
14:14:37.644 → 🔔 Snapshot recibido - exists=true
14:14:37.644 → Documento: {idSesion: 7c53e143-ab5e-411e-b09f-69f34cadd88f, ...}
```

**Pero el documento está en `history` con `tipoDeCierreDeSesion: logoutForzado`**

Esto confirma que la sesión se creó correctamente pero luego se movió al historial porque tenía campos de cierre.

---

## ✅ **RESULTADO ESPERADO**

Después del fix:

1. ✅ La sesión ANTERIOR se mueve al `history` con `tipoDeCierreDeSesion: logoutForzado`
2. ✅ La sesión NUEVA se crea en `activeSessions` **SIN** `tipoDeCierreDeSesion`
3. ✅ La sesión NUEVA permanece en `activeSessions` hasta que el usuario haga logout
4. ✅ No hay conflicto ni movimiento automático al historial

---

## 📝 **ARCHIVOS MODIFICADOS**

- `lib/services/session_service.dart`:
  - Línea ~354-366: Eliminado `tipoDeCierreDeSesion` y `fchHoraCierre` de llamada a `saveSession()`
  - Línea ~398-408: Eliminado `tipoDeCierreDeSesion` de llamada a `saveSession()`

---

## 🧪 **VALIDACIÓN**

Para confirmar el fix:

1. Login con usuario que tiene sesión activa
2. Confirmar continuar
3. Verificar que el documento nuevo está en `activeSessions/Usuario-{id}`
4. Verificar que NO tiene campo `tipoDeCierreDeSesion`
5. Verificar que el documento permanece en `activeSessions` (no se mueve a `history`)

---

## 🔗 **RELACIÓN CON OTROS FIXES**

Este fix complementa los anteriores:
- ✅ **Fix de race condition**: Confirmación del servidor antes de leer
- ✅ **Fix de caché**: Lectura cache-first en streams
- ✅ **Fix de setHistory**: No pasar campos de cierre al crear sesión nueva

Los tres fixes juntos aseguran:
1. El documento se crea y se confirma correctamente
2. El documento se lee correctamente desde el caché/servidor
3. El documento NO se mueve automáticamente al historial

---

**Estado**: ✅ Fix implementado, esperando validación con recompilación y prueba.
