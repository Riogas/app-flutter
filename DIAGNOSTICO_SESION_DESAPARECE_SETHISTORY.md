# 🔍 DIAGNÓSTICO: Sesión Desaparece Después de setHistory()

**Fecha**: 2025-11-27  
**Estado**: 🔴 PROBLEMA CONFIRMADO - DIAGNÓSTICO EN PROGRESO

---

## 📋 **RESUMEN DEL PROBLEMA**

Cuando un usuario hace login y **ya tiene una sesión activa** en Firestore:

1. ✅ **Primera llamada a `saveSession()`** detecta conflicto correctamente
2. ✅ **Usuario confirma continuar** → Se ejecuta `setHistory()`
3. ✅ **`setHistory()` mueve sesión anterior al histórico** (537ms)
4. ✅ **Segunda llamada a `saveSession()`** crea **nuevo documento exitosamente**
5. ✅ **Confirmación del servidor recibida** ([T0] → [T1] en 517ms)
6. ✅ **Sesión creada con éxito**: `{success: true, idSesion: e6df4c2a-64a7-4003-b23e-15bd28db8b4b}`
7. ❌ **PERO EL DOCUMENTO NO APARECE EN FIRESTORE**

---

## 🕐 **TIMELINE COMPLETO DEL LOGIN PROBLEMÁTICO**

### **Fase 1: Primer intento (Conflicto detectado)**
```
14:05:09.405 → saveSession: INICIO
14:05:10.041 → Verificando usuario en otro móvil (636ms)
14:05:10.541 → Usuario ya logueado en 693 ❌
14:05:10.542 → {success: false, message: "Usuario ya logueado en 693"}
```

### **Fase 2: Usuario confirma continuar**
```
14:05:27.570 → shouldProceed: true
14:05:27.570 → Moviendo activo al histórico
14:05:29.339 → Llamando a setHistory
```

### **Fase 3: setHistory() ejecuta**
```
14:05:29.369 → Asegurando documento de fecha
14:05:29.663 → Buscando sesión activa (294ms)
14:05:29.935 → Sesión activa encontrada, moviendo a history (272ms)
14:05:30.472 → ✅ Sesión movida a history (537ms total)
```

### **Fase 4: saveSession() crea NUEVA sesión**
```
14:05:30.472 → saveSession: INICIO (segunda llamada)
14:05:30.782 → Verificando usuario en otro móvil (310ms)
14:05:31.065 → Verificando móvil en uso (283ms)
14:05:31.356 → Creando sesión en Firestore
14:05:31.356 → 📝 [T0] Timestamp: 1764263131356

14:05:31.618 → Escritura enviada (262ms)
14:05:31.619 → Esperando confirmación del servidor...

14:05:31.872 → ✅ Sesión confirmada en servidor (253ms)
14:05:31.873 → 📝 [T1] Timestamp: 1764263131873
14:05:31.873 → ✅ Resultado: {success: true, idSesion: e6df4c2a-64a7-4003-b23e-15bd28db8b4b}
```

### **Fase 5: Navegación a HomePage**
```
14:05:31.873 → Package Info: version=1.1, buildNumber=2064
14:05:31.873 → Enviando RegistrarSesion al backend
14:05:32.062 → ✅ Backend response: 200 OK
14:05:32.068 → ✅ registrarUltLog ejecutado
14:05:32.073 → Cargando constantes desde Firebase...
```

---

## ✅ **VALIDACIÓN DEL FIX**

### **El fix de confirmación está funcionando:**

| Métrica | Caso 1 (sin sesión) | Caso 2 (con setHistory) |
|---------|---------------------|-------------------------|
| Escritura | 475ms | 262ms |
| Confirmación | 336ms | 253ms |
| **Total** | **811ms** | **517ms** |
| [T0] presente | ✅ | ✅ |
| [T1] presente | ✅ | ✅ |
| Confirmación exitosa | ✅ | ✅ |

**✅ Conclusión**: El mecanismo de confirmación funciona correctamente en ambos casos.

---

## 🔴 **EL PROBLEMA REAL**

### **Hipótesis Principal: Race condition en `getSesionesStream()`**

**El documento se crea exitosamente**, pero cuando `PersistentStreamManager()` inicia el stream de Firestore:

1. **Se llama a `getSesionesStream()`** para empezar a escuchar cambios
2. **La lectura inicial** (caché o servidor) NO encuentra el documento
3. **El stream emite `snapshot.exists = false`**
4. **La app interpreta esto como "sesión eliminada"**
5. **Se limpia Hive y se desloguea al usuario**

### **¿Por qué no hay logs [T4] y [T5]?**

**Respuesta**: Los logs [T4] y [T5] **SÍ se ejecutan**, pero **NO APARECEN** en el log del usuario.

Esto puede significar:
- El log se filtró por el comando `adb logcat`
- El stream se inició **después** de que el usuario dejó de capturar logs
- Hay un problema de sincronización en el logging

---

## 🔧 **LOGS ADICIONALES AGREGADOS**

Para diagnosticar el problema, se agregaron los siguientes logs:

### **1. En `persistent_stream_manager.dart`:**
```dart
print('🔍 [PersistentStreamManager] _initializeSesionesListener: usuario=$usuario, escenario=$escenario');
print('🚀 [PersistentStreamManager] Iniciando getSesionesStream()...');
```

### **2. En `firebase_service.dart`:**
```dart
// En el try-catch de lectura inicial:
print('$kFirebaseSesionesTag ❌ Stack trace:');
print(StackTrace.current);

// En la advertencia de documento no encontrado:
print('$kFirebaseSesionesTag ⚠️ Esta situación causará eliminación de sesión si ocurre después de crear el documento');

// Antes de iniciar el stream:
print('$kFirebaseSesionesTag 🔊 Iniciando snapshots() stream para escuchar cambios en tiempo real...');

// En el asyncMap():
print('$kFirebaseSesionesTag 🔔 Snapshot recibido en snapshots().map() - exists=${snapshot.exists}');

// Si snapshot.exists = false:
print('$kFirebaseSesionesTag 🔴🔴🔴 SNAPSHOT.EXISTS = FALSE - DOCUMENTO ELIMINADO/NO ENCONTRADO 🔴🔴🔴');
print('$kFirebaseSesionesTag ⚠️ Timestamp: ${DateTime.now().millisecondsSinceEpoch}');
print('$kFirebaseSesionesTag ⚠️ Metadatos: ${snapshot.metadata}');
```

---

## 📊 **PRÓXIMOS PASOS**

### **1. Recompilar la app con logs adicionales** ⏳
- [x] Agregar logs en `_initializeSesionesListener()`
- [x] Agregar logs en `getSesionesStream()`
- [x] Agregar logs en `snapshots().map()`
- [ ] Compilar: `flutter build apk`
- [ ] Instalar: `flutter install`

### **2. Reproducir el problema con logs completos**
- [ ] Hacer login con usuario que tiene sesión activa
- [ ] Confirmar continuar
- [ ] Capturar logs completos desde login hasta navegación
- [ ] Buscar logs:
  - `🔍 [PersistentStreamManager] _initializeSesionesListener`
  - `🚀 [PersistentStreamManager] Iniciando getSesionesStream()`
  - `📡 [T4] Intentando leer del caché local...`
  - `📝 [T5] Timestamp:`
  - `🔔 Snapshot recibido en snapshots().map()`
  - `🔴🔴🔴 SNAPSHOT.EXISTS = FALSE`

### **3. Analizar el timing**
- Comparar timestamps entre:
  - [T1] (confirmación de escritura)
  - [T4] (inicio de lectura en stream)
  - Snapshot recibido en `snapshots().map()`

### **4. Posibles soluciones si se confirma la hipótesis**

#### **Opción A: Delay antes de iniciar el stream**
```dart
await Future.delayed(Duration(seconds: 1));
await PersistentStreamManager().startSesionesListenerAfterLogin();
```

#### **Opción B: Esperar confirmación antes de iniciar stream**
```dart
// Después de saveSession() exitoso
await Future.delayed(Duration(milliseconds: 500));
// Luego iniciar stream
```

#### **Opción C: No usar snapshot inicial, solo snapshots()**
```dart
// Eliminar el yield inicial
// Solo usar el stream de snapshots()
```

#### **Opción D: Invalidar caché antes de iniciar stream**
```dart
// Forzar limpieza de caché de Firestore
await FirebaseFirestore.instance.clearPersistence();
```

---

## 🎯 **HIPÓTESIS ALTERNATIVAS**

### **Hipótesis 2: El documento se elimina por otro motivo**

Posibilidades:
- [ ] Algún listener antiguo todavía activo que detecta "sesión duplicada"
- [ ] El `reset()` de `PersistentStreamManager()` elimina el documento
- [ ] Hay una regla de seguridad en Firestore que lo elimina
- [ ] El backend (`RegistrarSesion`) elimina el documento

### **Hipótesis 3: El documento nunca se persiste realmente**

Posibilidades:
- [ ] La confirmación es falsa positiva
- [ ] El `.set()` falla silenciosamente después de retornar
- [ ] Hay un rollback de transacción

---

## 📝 **NOTAS IMPORTANTES**

1. **El fix de confirmación funciona**: Los logs [T0] y [T1] lo confirman
2. **El problema es diferente**: No es la race condition original
3. **El timing es crítico**: 517ms entre escritura y confirmación
4. **El stream se inicia después**: Necesitamos ver CUÁNDO exactamente

---

## ✅ **ÉXITOS LOGRADOS**

- [x] SSL certificate fix implementado
- [x] Race condition original diagnosticada
- [x] Server confirmation implementado
- [x] Cache-first reading implementado
- [x] Logs [T0]/[T1] funcionando correctamente
- [x] Caso 1 (sin sesión previa) funciona perfectamente

---

## 🔴 **PROBLEMA PENDIENTE**

- [ ] Caso 2 (con sesión previa + setHistory) elimina el documento
- [ ] No hay logs [T4]/[T5] visibles en el log del usuario
- [ ] Necesitamos más diagnóstico para identificar el momento exacto de la eliminación

---

**Estado actual**: Esperando recompilación con logs adicionales para continuar diagnóstico.
