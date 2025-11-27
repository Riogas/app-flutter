# 🔍 ANÁLISIS: Eliminación Inmediata de Documento de Sesión en Firestore

## 📋 PROBLEMA REPORTADO

El documento de sesión se crea correctamente en:
```
/sessions-1000/20251127/activeSessions/Usuario-49618553
```

**Pero se elimina inmediatamente después de que el login termina exitosamente.**

---

## 🔎 ANÁLISIS DEL FLUJO ACTUAL

### 1️⃣ CREACIÓN DE LA SESIÓN (`login_page.dart` líneas 2302-2330)

```dart
// ✅ Paso 1: Guardar sesión en Firestore
final sessionResult = await _saveSession(currentLocation);

if (sessionResult != null && sessionResult['success']) {
  // ✅ Sesión guardada exitosamente
  
  // Paso 2: Llamar registrarUltLog
  await RioGasService.registrarUltLog(...);
  
  // Paso 3: Navegar a HomePage
  await _onSuccessfulLoginFlow(context);
}
```

### 2️⃣ ESCRITURA EN FIRESTORE (`session_service.dart` líneas 127-137)

```dart
// 3. Crear la sesión si no hay conflictos
await _firestore
    .collection('sessions-$escenarioId')
    .doc(fechaActual)
    .collection('activeSessions')
    .doc('Usuario-$idUsuario')
    .set(sessionData);  // ⚠️ Escritura ASÍNCRONA sin esperar confirmación

return {
  'success': true,
  'message': 'Sesión guardada exitosamente.',
};
```

**⚠️ PROBLEMA:** El método retorna `success: true` INMEDIATAMENTE después de llamar `.set()`, sin esperar confirmación del servidor.

### 3️⃣ RESETEO DEL STREAM MANAGER (`login_page.dart` líneas 2975-2977)

```dart
Future<void> _onSuccessfulLoginFlow(BuildContext context) async {
  // ...
  
  PersistentStreamManager().reset();      // 🔴 Cancela TODOS los listeners
  await PersistentStreamManager().initialize(); // 🔴 Reinicia TODOS los listeners
  
  // ...
}
```

### 4️⃣ LECTURA INICIAL DEL SERVIDOR (`firebase_service.dart` líneas 590-610)

```dart
Stream<Map<String, dynamic>?> getSesionesStream() async* {
  // ...
  
  try {
    // 🔴 LECTURA FORZADA DEL SERVIDOR (NO del caché local)
    DocumentSnapshot snapshot = await usuarioDocRef.get(
      const GetOptions(source: Source.server),  // ⚠️ Fuerza lectura del servidor
    );
    
    if (snapshot.exists) {
      yield data;
    } else {
      // 🔴 Si NO existe en servidor, yield null
      yield null;
    }
  } catch (error) {
    yield null;
  }
  
  // Continúa con el stream reactivo...
}
```

---

## 🐛 CAUSA RAÍZ: **RACE CONDITION**

### Timeline del Problema:

```
T0: saveSession() llama a .set(sessionData)
     ├─> Escritura va al caché local de Firestore
     └─> Escritura se ENCOLA para ir al servidor (asíncrona)

T1: saveSession() retorna {success: true} ← ⚠️ SIN ESPERAR AL SERVIDOR

T2: _onSuccessfulLoginFlow() se ejecuta
     └─> PersistentStreamManager().reset()
         └─> Cancela listeners existentes

T3: PersistentStreamManager().initialize()
     └─> _initializeSesionesListener()
         └─> getSesionesStream().listen(...)

T4: getSesionesStream() hace lectura inicial
     └─> .get(source: Source.server) ← 🔴 FUERZA LECTURA DEL SERVIDOR

T5: Servidor AÚN NO TIENE EL DOCUMENTO
     └─> La escritura de T0 todavía no llegó al servidor
     └─> snapshot.exists = FALSE

T6: getSesionesStream() hace yield null
     └─> Porque el documento no existe en el servidor

T7: Listener reacciona al null
     └─> Posible lógica de "sesión eliminada" se dispara
     └─> Usuario ve el documento desaparecer
```

---

## 🔧 SOLUCIONES PROPUESTAS

### ✅ **SOLUCIÓN 1: Esperar Confirmación del Servidor** (RECOMENDADA)

Modificar `SessionService.saveSession()` para **esperar confirmación real**:

```dart
// 3. Crear la sesión si no hay conflictos
print("$kSessionTag saveSession: Creando sesión en Firestore");
await _firestore
    .collection('sessions-$escenarioId')
    .doc(fechaActual)
    .collection('activeSessions')
    .doc('Usuario-$idUsuario')
    .set(sessionData);

// ✅ NUEVO: Esperar confirmación leyendo del servidor
print("$kSessionTag saveSession: Esperando confirmación del servidor...");
final confirmation = await _firestore
    .collection('sessions-$escenarioId')
    .doc(fechaActual)
    .collection('activeSessions')
    .doc('Usuario-$idUsuario')
    .get(const GetOptions(source: Source.server));

if (!confirmation.exists) {
  print("$kSessionTag saveSession: ERROR - Sesión no confirmada en servidor");
  throw Exception('La sesión no se pudo confirmar en el servidor');
}

print("$kSessionTag saveSession: ✅ Sesión confirmada en servidor");
print("$kSessionTag saveSession: Sesión guardada exitosamente");
return {
  'success': true,
  'message': 'Sesión guardada exitosamente.',
  'idSesion': idSesion,
};
```

**Ventajas:**
- ✅ Garantiza que el documento existe en el servidor antes de continuar
- ✅ Evita la race condition completamente
- ✅ Más robusto ante problemas de red

**Desventajas:**
- ⏱️ Añade ~200-500ms de latencia al login

---

### ✅ **SOLUCIÓN 2: Leer del Caché Local** (MÁS RÁPIDA)

Modificar `FirebaseService.getSesionesStream()` para leer del **caché local** en lugar del servidor:

```dart
try {
  // 🔄 CAMBIO: Leer del caché local primero
  DocumentSnapshot snapshot = await usuarioDocRef.get(
    const GetOptions(source: Source.cache),  // ← Leer del caché local
  );
  
  if (snapshot.exists) {
    var data = snapshot.data() as Map<String, dynamic>;
    print('$kFirebaseSesionesTag ✅ Documento inicial encontrado (caché): $data');
    yield data;
  } else {
    // Si no está en caché, intentar del servidor
    snapshot = await usuarioDocRef.get(
      const GetOptions(source: Source.server),
    );
    
    if (snapshot.exists) {
      var data = snapshot.data() as Map<String, dynamic>;
      print('$kFirebaseSesionesTag ✅ Documento inicial encontrado (servidor): $data');
      yield data;
    } else {
      print('$kFirebaseSesionesTag ⚠️ Documento NO encontrado');
      yield null;
    }
  }
} catch (error) {
  print('$kFirebaseSesionesTag ❌ Error obteniendo documento: $error');
  yield null;
}
```

**Ventajas:**
- ⚡ Más rápido (sin latencia adicional)
- ✅ El documento SÍ existe en el caché local después de `.set()`

**Desventajas:**
- ⚠️ Si el caché local está corrupto o se limpió, podría fallar

---

### ⚠️ **SOLUCIÓN 3: Delay Artificial** (NO RECOMENDADA)

Agregar un delay antes de iniciar listeners:

```dart
final sessionResult = await _saveSession(currentLocation);

if (sessionResult != null && sessionResult['success']) {
  // ⏱️ Esperar a que la escritura se propague al servidor
  await Future.delayed(Duration(seconds: 2));
  
  await _onSuccessfulLoginFlow(context);
}
```

**Ventajas:**
- 🛠️ Fácil de implementar (una sola línea)

**Desventajas:**
- ❌ No es determinístico (podría no ser suficiente en conexiones lentas)
- ❌ Añade latencia innecesaria en conexiones rápidas
- ❌ Mala experiencia de usuario

---

### ✅ **SOLUCIÓN 4: Evitar Reset Innecesario** (COMPLEMENTARIA)

Modificar `_onSuccessfulLoginFlow()` para **NO resetear** si ya está inicializado:

```dart
Future<void> _onSuccessfulLoginFlow(BuildContext context) async {
  // ...
  
  final streamManager = PersistentStreamManager();
  
  // ✅ NUEVO: Solo inicializar si NO está inicializado
  if (!streamManager.isProperlyInitialized) {
    print('🔄 [LOGIN] StreamManager NO inicializado, inicializando...');
    await streamManager.initialize();
  } else {
    print('✅ [LOGIN] StreamManager ya inicializado, reutilizando...');
    // NO hacer reset/initialize si ya funciona
  }
  
  // ...
}
```

**Ventajas:**
- ✅ Evita cancelar listeners innecesariamente
- ✅ Más eficiente (no recrea subscripciones)
- ✅ Reduce lecturas de Firestore

**Desventajas:**
- ⚠️ Debe asegurar que el estado previo es válido

---

## 🎯 RECOMENDACIÓN FINAL

**Implementar SOLUCIÓN 1 + SOLUCIÓN 4:**

1. ✅ En `SessionService.saveSession()`: Agregar confirmación de escritura
2. ✅ En `_onSuccessfulLoginFlow()`: Solo inicializar si no está inicializado
3. ✅ Agregar logs detallados para diagnóstico

**Orden de implementación:**
1. Primero: Solución 1 (confirmación)
2. Después: Solución 4 (evitar reset)
3. Monitorear logs para validar

---

## 📊 VALIDACIÓN

Después de implementar las soluciones, verificar:

1. ✅ El documento se crea en Firestore
2. ✅ El documento PERMANECE después del login
3. ✅ No hay mensajes de "Sesión eliminada" o `yield null`
4. ✅ El listener de sesiones funciona correctamente
5. ✅ No hay degradación de performance en el login

---

## 🔬 LOGS DE DIAGNÓSTICO

Para confirmar la causa raíz antes de aplicar soluciones, agregar estos logs:

### En `SessionService.saveSession()` (después de `.set()`):

```dart
await _firestore
    .collection('sessions-$escenarioId')
    .doc(fechaActual)
    .collection('activeSessions')
    .doc('Usuario-$idUsuario')
    .set(sessionData);

print("$kSessionTag 📝 [T0] Escritura enviada a Firestore (caché local)");
print("$kSessionTag ⏱️ Timestamp: ${DateTime.now().millisecondsSinceEpoch}");
```

### En `FirebaseService.getSesionesStream()` (antes de `.get()`):

```dart
print('$kFirebaseSesionesTag 📡 [T4] Iniciando lectura del servidor...');
print('$kFirebaseSesionesTag ⏱️ Timestamp: ${DateTime.now().millisecondsSinceEpoch}');

DocumentSnapshot snapshot = await usuarioDocRef.get(
  const GetOptions(source: Source.server),
);

print('$kFirebaseSesionesTag 📡 [T5] Lectura completada');
print('$kFirebaseSesionesTag ⏱️ Timestamp: ${DateTime.now().millisecondsSinceEpoch}');
print('$kFirebaseSesionesTag 📊 Resultado: exists=${snapshot.exists}');
```

Si los timestamps muestran una diferencia de < 500ms entre T0 y T5, **confirma la race condition**.

---

## ❓ PREGUNTAS PARA EL USUARIO

1. ¿El problema ocurre **siempre** o solo a veces?
2. ¿Ocurre con **todos los usuarios** o solo con algunos?
3. ¿La conexión a internet es **estable** o **intermitente**?
4. ¿Aparece algún mensaje de error en la consola cuando se elimina?
5. ¿El documento se elimina **inmediatamente** o después de unos segundos?

---

## 📝 NOTAS ADICIONALES

### Otras causas potenciales a considerar:

1. **Reglas de seguridad de Firestore:**
   - Verificar que las reglas permiten escribir en `activeSessions`
   - Verificar que no hay reglas de auto-eliminación

2. **Cloud Functions:**
   - ¿Hay alguna Cloud Function que escuche cambios en `activeSessions`?
   - ¿Podría estar eliminando documentos automáticamente?

3. **Listeners heredados:**
   - ¿Hay otros lugares en el código que escuchen `activeSessions`?
   - ¿Algún listener podría estar eliminando el documento por error?

4. **Sesiones anteriores:**
   - Si el usuario hace login rápido después de logout, ¿podría haber conflicto?

---

**Fecha del análisis:** 27 de noviembre de 2025  
**Archivos analizados:**
- `lib/services/session_service.dart`
- `lib/services/firebase_service.dart`
- `lib/services/persistent_stream_manager.dart`
- `lib/pages/login_page.dart`
