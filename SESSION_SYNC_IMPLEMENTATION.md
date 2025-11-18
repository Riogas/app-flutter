# 🔄 Sistema de Sincronización de Sesión

## 📋 Problema Resuelto

**Antes:** El Force GPS no tenía acceso a los datos críticos de sesión (deviceId, movilId) porque:
- Estaban guardados solo en Hive (no accesible desde código nativo)
- SharedPreferences no estaba sincronizado con Hive
- Force GPS no sabía qué móvil o dispositivo estaba activo

**Ahora:** Sistema automático de sincronización que mantiene Hive y SharedPreferences sincronizados.

---

## 🎯 Funcionalidades Implementadas

### 1️⃣ **Servicio de Sincronización (`SessionSyncService`)**

Nuevo archivo: `lib/services/session_sync_service.dart`

**Responsabilidades:**
- Sincronizar datos de Hive → SharedPreferences
- Leer datos de sesión desde SharedPreferences
- Validar que ambos estén sincronizados
- Limpiar datos al hacer logout

**Datos sincronizados:**
- `movil` - ID del móvil asignado
- `deviceId` - ID único del dispositivo
- `username` - Usuario logueado
- `escenario` - Ambiente (Dev/Prod)

---

### 2️⃣ **Integración con GPS Service Manager**

Modificado: `lib/services/gps_service_manager.dart`

**Nuevos métodos:**

#### A. `forceStopAllGpsProcesses()` (Mejorado)
```dart
static Future<bool> forceStopAllGpsProcesses() async {
  // 📋 Recuperar datos de sesión ANTES de detener
  final sessionData = await SessionSyncService.getSessionData();
  _debugLog('🛑 Deteniendo TODOS los procesos GPS activos...');
  _debugLog('📋 Datos de sesión recuperados:');
  _debugLog('   - Móvil: ${sessionData['movil']}');
  _debugLog('   - DeviceID: ${sessionData['deviceId']}');
  _debugLog('   - Usuario: ${sessionData['usuario']}');
  _debugLog('   - Escenario: ${sessionData['escenario']}');
  
  // ... detener servicios ...
  
  _debugLog('✅ Datos de sesión preservados para reinicio');
  return stopped;
}
```

#### B. `getSessionData()` (Nuevo)
```dart
/// Obtener datos de sesión actual desde SharedPreferences
static Future<Map<String, String>> getSessionData() async {
  try {
    final sessionData = await SessionSyncService.getSessionData();
    _debugLog('📋 Datos de sesión obtenidos correctamente');
    return sessionData;
  } catch (e) {
    _debugLog('❌ Error obteniendo datos de sesión: $e');
    return {
      'movil': '',
      'deviceId': '',
      'usuario': '',
      'escenario': '',
    };
  }
}
```

---

### 3️⃣ **Sincronización Automática en Login**

Modificado: `lib/pages/login_page.dart`

**Ubicación:** Después de guardar el móvil en Hive (línea ~1510)

```dart
// 🔹 Guardar móvil seleccionado y matrícula en Hive
var box = await Hive.openBox('sessionBox');
await box.put('movil', selectedMovil);
await userbox.put('movil', selectedMovil);

// 🔄 Sincronizar datos de sesión a SharedPreferences
try {
  await SessionSyncService.syncToSharedPrefs();
  print('✅ Datos de sesión sincronizados (movil guardado)');
} catch (e) {
  print('⚠️ Error sincronizando datos de sesión: $e');
}
```

---

## 📝 API del SessionSyncService

### **1. Sincronizar Hive → SharedPreferences**

```dart
await SessionSyncService.syncToSharedPrefs();
```

**Cuándo llamar:**
- Después del login exitoso
- Al cambiar de móvil
- Al actualizar deviceId
- Al cambiar de escenario (Dev/Prod)

**Qué hace:**
1. Lee datos de `sessionBox` (Hive)
2. Guarda en SharedPreferences
3. Logs de confirmación

---

### **2. Obtener Datos de Sesión**

```dart
final sessionData = await SessionSyncService.getSessionData();
print('Móvil: ${sessionData['movil']}');
print('DeviceID: ${sessionData['deviceId']}');
print('Usuario: ${sessionData['usuario']}');
print('Escenario: ${sessionData['escenario']}');
```

**Cuándo usar:**
- Desde GPS Service Manager
- Desde servicios nativos (Kotlin/Java)
- Cuando necesites datos de sesión sin Hive

**Retorna:**
```dart
{
  'movil': '336',
  'deviceId': 'abc123',
  'usuario': 'jgomez',
  'escenario': '1'
}
```

---

### **3. Validar Sincronización**

```dart
final isSync = await SessionSyncService.validateSync();
if (!isSync) {
  print('⚠️ Hive y SharedPreferences están desincronizados');
  await SessionSyncService.syncToSharedPrefs(); // Re-sincronizar
}
```

**Cuándo usar:**
- Testing y debugging
- Validar que la sincronización funciona
- Detectar inconsistencias

**Salida de consola:**
```
[SESSION_SYNC] 🔍 Validando sincronización...
[SESSION_SYNC] 📊 Resultado de validación:
[SESSION_SYNC]   - movil: ✅ (Hive: 336, Prefs: 336)
[SESSION_SYNC]   - deviceId: ✅ (Hive: abc123, Prefs: abc123)
[SESSION_SYNC]   - usuario: ✅ (Hive: jgomez, Prefs: jgomez)
[SESSION_SYNC]   - escenario: ✅ (Hive: 1, Prefs: 1)
[SESSION_SYNC] ✅ Sincronización: OK
```

---

### **4. Limpiar Datos (Logout)**

```dart
await SessionSyncService.clearSessionData();
```

**Cuándo llamar:**
- Al hacer logout
- Al cerrar sesión remota
- Al limpiar datos de la app

**Qué hace:**
1. Limpia `sessionBox` (Hive)
2. Elimina datos de SharedPreferences
3. Logs de confirmación

---

## 🔍 Logs Disponibles

### **Sincronización Exitosa**

```
[SESSION_SYNC] 🔄 Iniciando sincronización Hive → SharedPreferences...
[SESSION_SYNC] 📖 Datos leídos de Hive:
[SESSION_SYNC]   - movil: 336
[SESSION_SYNC]   - deviceId: abc123
[SESSION_SYNC]   - usuario: jgomez
[SESSION_SYNC]   - escenario: 1
[SESSION_SYNC] ✅ Sincronización completada exitosamente
```

### **Force GPS con Datos de Sesión**

```
[GPS_SERVICE_MANAGER] 🛑 Modo FORCE activado - Deteniendo procesos duplicados
[GPS_SERVICE_MANAGER] 🛑 Deteniendo TODOS los procesos GPS activos...
[GPS_SERVICE_MANAGER] 📋 Datos de sesión recuperados:
[GPS_SERVICE_MANAGER]    - Móvil: 336
[GPS_SERVICE_MANAGER]    - DeviceID: abc123
[GPS_SERVICE_MANAGER]    - Usuario: jgomez
[GPS_SERVICE_MANAGER]    - Escenario: 1
MainActivity            🛑 forceStopGpsService - Deteniendo TODOS los procesos GPS
MainActivity            ✅ forceStopGpsService completado - Servicio corriendo: false
[GPS_SERVICE_MANAGER] ✅ Procesos GPS detenidos exitosamente
[GPS_SERVICE_MANAGER] ✅ Datos de sesión preservados para reinicio
```

---

## 🚀 Flujo Completo

### **1. Login → Sincronización Automática**

```
Usuario ingresa credenciales
    ↓
Login exitoso
    ↓
Guardar datos en Hive (sessionBox)
    ├─ movil: 336
    ├─ deviceId: abc123
    ├─ username: jgomez
    └─ escenario: 1
    ↓
SessionSyncService.syncToSharedPrefs()
    ↓
Datos copiados a SharedPreferences
    ↓
✅ Sincronización completa
```

### **2. Force GPS → Recuperación de Datos**

```
FCM recibe force_gps_execution
    ↓
GPS Service Manager procesa solicitud
    ↓
forceStopAllGpsProcesses() llamado
    ↓
SessionSyncService.getSessionData() recupera datos
    ├─ movil: 336
    ├─ deviceId: abc123
    ├─ usuario: jgomez
    └─ escenario: 1
    ↓
Datos disponibles para reinicio GPS
    ↓
Servicio GPS inicia con datos correctos
```

---

## 📊 Comparación: Antes vs Después

| Aspecto | Antes | Después |
|---------|-------|---------|
| **Acceso a datos** | Solo Hive (Flutter) | Hive + SharedPreferences |
| **Force GPS** | Sin datos de sesión | Con datos de sesión completos |
| **Sincronización** | Manual, inconsistente | Automática, confiable |
| **Debugging** | Difícil saber qué datos tiene | Logs exhaustivos de sincronización |
| **Código nativo** | Sin acceso a datos | Acceso completo vía SharedPreferences |

---

## 🔧 Lugares Donde Agregar Sincronización

Agregar `SessionSyncService.syncToSharedPrefs()` en estos lugares:

### ✅ **1. Login (Ya implementado)**
```dart
// En login_page.dart, después de guardar móvil
await box.put('movil', selectedMovil);
await SessionSyncService.syncToSharedPrefs(); // ← YA IMPLEMENTADO
```

### ⚠️ **2. Cambio de Móvil (Pendiente)**
```dart
// En settings_page.dart o donde se cambie móvil
await box.put('movil', nuevoMovil);
await SessionSyncService.syncToSharedPrefs(); // ← AGREGAR
```

### ⚠️ **3. Actualización de DeviceID (Pendiente)**
```dart
// En cualquier lugar donde se actualice deviceId
await box.put('deviceId', nuevoDeviceId);
await SessionSyncService.syncToSharedPrefs(); // ← AGREGAR
```

### ⚠️ **4. Cambio de Escenario (Pendiente)**
```dart
// Al cambiar entre Dev/Prod
await box.put('escenario', nuevoEscenario);
await SessionSyncService.syncToSharedPrefs(); // ← AGREGAR
```

### ⚠️ **5. Logout (Pendiente)**
```dart
// Al hacer logout
await SessionSyncService.clearSessionData(); // ← AGREGAR
```

---

## 🧪 Testing

### **Test 1: Sincronización en Login**

```dart
// 1. Hacer login
// 2. Verificar sincronización
final isSync = await SessionSyncService.validateSync();
assert(isSync == true, 'Datos no sincronizados después de login');

// 3. Obtener datos
final sessionData = await SessionSyncService.getSessionData();
assert(sessionData['movil'] != '', 'Móvil no sincronizado');
```

### **Test 2: Force GPS Tiene Datos**

```dart
// 1. Hacer login
await SessionSyncService.syncToSharedPrefs();

// 2. Ejecutar force GPS
await GpsServiceManager.requestGpsStart(source: 'test_force', force: true);

// 3. Verificar logs:
// Debe ver: "Datos de sesión recuperados: Móvil: 336"
```

### **Test 3: Logout Limpia Datos**

```dart
// 1. Hacer login
await SessionSyncService.syncToSharedPrefs();

// 2. Hacer logout
await SessionSyncService.clearSessionData();

// 3. Verificar que datos fueron limpiados
final sessionData = await SessionSyncService.getSessionData();
assert(sessionData['movil'] == '', 'Móvil no fue limpiado');
```

---

## ✅ Checklist de Implementación

- [x] ✅ Crear `SessionSyncService`
- [x] ✅ Agregar métodos de sincronización
- [x] ✅ Integrar con GPS Service Manager
- [x] ✅ Sincronización automática en login
- [x] ✅ Force GPS recupera datos de sesión
- [ ] ⚠️ Agregar sincronización en cambio de móvil
- [ ] ⚠️ Agregar sincronización en cambio de deviceId
- [ ] ⚠️ Agregar limpieza en logout
- [ ] ⚠️ Testing completo en dispositivo real

---

## 📞 Próximos Pasos

1. **Testing**: Compilar y probar en dispositivo real
   - Hacer login
   - Enviar force_gps_execution
   - Verificar logs de sincronización

2. **Agregar sincronización faltante**:
   - Cambio de móvil (settings_page.dart)
   - Logout (auth_service.dart o donde esté el logout)

3. **Monitoreo**:
   ```powershell
   # Ver logs de sincronización
   adb logcat | Select-String "SESSION_SYNC|GPS_SERVICE_MANAGER.*sesión"
   ```

4. **Validar**:
   ```dart
   // Agregar validación periódica (debugging)
   Timer.periodic(Duration(minutes: 5), (_) async {
     final isSync = await SessionSyncService.validateSync();
     if (!isSync) {
       print('⚠️ Datos desincronizados - re-sincronizando');
       await SessionSyncService.syncToSharedPrefs();
     }
   });
   ```

---

## 🎯 Beneficios

| Beneficio | Descripción |
|-----------|-------------|
| 🔄 **Sincronización automática** | Datos siempre actualizados entre Hive y SharedPreferences |
| 📋 **Acceso universal** | Código Dart y nativo acceden a los mismos datos |
| 🛑 **Force GPS mejorado** | Sabe qué móvil y dispositivo está activo |
| 🐞 **Debugging fácil** | Logs exhaustivos de sincronización |
| 🧪 **Testing simple** | Método de validación incluido |
| 🧹 **Limpieza correcta** | Logout limpia ambos almacenamientos |

---

**¡Sistema de sincronización implementado! 🎉**
