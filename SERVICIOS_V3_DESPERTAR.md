# 🚀 Migración de Servicios a V3 con Parámetro "Despertar"

## 📋 Resumen

Se han actualizado **4 servicios** de la versión V2 a V3, agregando el parámetro booleano `Despertar` que indica al backend si los servicios GPS y CriticalLog necesitan ser reiniciados.

---

## 🔄 Servicios Actualizados

### 1. **DescargaPedidosV3** (antes DescargaPedidos)
- **Método Dart**: `descargaPedidos()`
- **Endpoint**: `DescargaPedidosV3`
- **Nuevo parámetro**: `'Despertar': despertar` (después de `DistanciaRecorrida`)

### 2. **DescargaLecturaMensajesV3** (antes DescargaLecturaMensajes)
- **Método Dart**: `descargaLecturaMensajes()`
- **Endpoint**: `DescargaLecturaMensajesV3`
- **Nuevo parámetro**: `'Despertar': despertar` (después de `DistanciaRecorrida`)

### 3. **DescargaLecturaPedidosV3** (antes DescargaLecturaPedidos)
- **Método Dart**: `descargaLecturaPedidos()`
- **Endpoint**: `DescargaLecturaPedidosV3`
- **Nuevo parámetro**: `'Despertar': despertar` (después de `DistanciaRecorrida`)

### 4. **FinalizarPedidoV3** (antes FinalizarPedidoV2)
- **Método Dart**: `finalizarPedido()`
- **Endpoint**: `FinalizarPedidoV3`
- **Nuevo parámetro**: `'Despertar': despertar` (después de `DistanciaRecorrida`)

---

## 🎯 Lógica del Parámetro "Despertar"

### Obtención del Flag
Cada uno de los 4 servicios ahora ejecuta esta lógica antes de hacer el POST:

```dart
// 🚩 Obtener flag 'services_need_restart' desde SharedPreferences nativo
bool despertar = false;
try {
  final servicesNeedRestart = await getServicesNeedRestart();
  despertar = servicesNeedRestart ?? false;
  print('🚩 [NombreServicioV3] Despertar servicios: $despertar');
} catch (e) {
  print('❌ [NombreServicioV3] Error obteniendo flag despertar: $e');
}
```

### Estructura del Request Body
El parámetro `Despertar` se agrega **después** de `DistanciaRecorrida`:

```dart
return _post('NombreServicioV3', {
  // ... otros parámetros ...
  'Velocidad': velocidad,
  'DistanciaRecorrida': distanciaRecorrida,
  'Despertar': despertar // 🆕 Flag para despertar servicios
});
```

---

## 🔍 Flujo Completo del Sistema

### 1. **Watchdog detecta servicio caído**
```kotlin
// ServiceWatchdog.kt o CriticalLogAlarmReceiver.kt
ServiceStatusFlags.setServicesNeedRestart(
    context, 
    needRestart = true, 
    checkerService = "GPS Service", 
    reason = "CriticalLog worker no está activo"
)
```

### 2. **Flag se guarda en SharedPreferences**
```kotlin
// ServiceStatusFlags.kt
val prefs = context.getSharedPreferences("ServiceStatusPrefs", Context.MODE_PRIVATE)
prefs.edit()
    .putBoolean("services_need_restart", true)
    .putString("services_need_restart_reason", reason)
    .putString("services_need_restart_checker", checkerService)
    .apply()
```

### 3. **Flutter realiza llamada a servicio**
```dart
// Usuario finaliza pedido, descarga mensaje, etc.
await RioGasService.finalizarPedido(
  escenarioId: 1,
  pedidoId: 123,
  // ... otros parámetros ...
);
```

### 4. **Servicio lee el flag desde Kotlin**
```dart
// riogas_service.dart
final servicesNeedRestart = await getServicesNeedRestart();
despertar = servicesNeedRestart ?? false;
```

### 5. **MethodChannel lee SharedPreferences**
```kotlin
// MainActivity.kt
"getServicesNeedRestart" -> {
    val prefs = getSharedPreferences("ServiceStatusPrefs", Context.MODE_PRIVATE)
    val needRestart = prefs.getBoolean("services_need_restart", false)
    result.success(needRestart)
}
```

### 6. **Request se envía al backend con Despertar**
```json
{
  "escenarioid": 1,
  "PedidoId": 123,
  "Velocidad": 45.67,
  "DistanciaRecorrida": 1234.56,
  "Despertar": true  // 🔥 Backend recibe señal
}
```

### 7. **Backend puede tomar acción**
- Si `Despertar = true`: Backend puede enviar FCM para reiniciar servicios
- Si `Despertar = false`: No hay acción necesaria

---

## 🛡️ Sistema de Deduplicación Actualizado

La lógica de deduplicación ahora soporta **todos los endpoints V3 y sus versiones legacy V2**:

```dart
// Lista de endpoints que usan firma JSON para deduplicación
final v3Endpoints = [
  'FinalizarPedidoV3', 'FinalizarPedidoV2',
  'DescargaPedidosV3', 'DescargaPedidos',
  'DescargaLecturaMensajesV3', 'DescargaLecturaMensajes',
  'DescargaLecturaPedidosV3', 'DescargaLecturaPedidos'
];
```

### Ventajas
- ✅ Evita duplicados entre versiones V2 y V3
- ✅ Usa firma JSON del payload completo (incluye `Despertar`)
- ✅ Mantiene compatibilidad con requests antiguos pendientes

---

## 🔧 Función `_shouldSkipFailedSave` Actualizada

Se agregaron los nuevos endpoints V3 a la lista de servicios que **NO deben guardarse** si fallan:

```dart
static bool _shouldSkipFailedSave(String endpoint) {
  return endpoint == 'DescargaLecturaPedidos' ||
      endpoint == 'DescargaLecturaPedidosV3' ||
      endpoint == 'RegistrarCoordenadas' ||
      endpoint == 'RegistrarCoordenadasBatch' ||
      endpoint == 'RegistrarCierre' ||
      endpoint == 'DescargaPedidos' ||
      endpoint == 'DescargaPedidosV3';
}
```

---

## 📊 Estado de los Servicios

| Servicio Original | Versión Actual | Parámetro Despertar | Estado |
|------------------|----------------|---------------------|--------|
| `DescargaPedidos` | `DescargaPedidosV3` | ✅ Sí | ✅ Implementado |
| `DescargaLecturaMensajes` | `DescargaLecturaMensajesV3` | ✅ Sí | ✅ Implementado |
| `DescargaLecturaPedidos` | `DescargaLecturaPedidosV3` | ✅ Sí | ✅ Implementado |
| `FinalizarPedidoV2` | `FinalizarPedidoV3` | ✅ Sí | ✅ Implementado |

---

## 🧪 Testing

### Escenario de Prueba

1. **Detener manualmente el servicio GPS**
   ```bash
   adb shell am force-stop com.riogas.appmovil
   ```

2. **Verificar que el watchdog detecta la caída**
   ```bash
   adb logcat | Select-String "services_need_restart"
   ```
   Debe mostrar: `services_need_restart=true`

3. **Ejecutar uno de los 4 servicios desde la app**
   - Finalizar un pedido
   - Descargar un mensaje
   - Descargar pedidos
   - etc.

4. **Verificar logs del servicio**
   ```bash
   adb logcat | Select-String "DescargaPedidosV3|FinalizarPedidoV3|DescargaLecturaMensajesV3|DescargaLecturaPedidosV3"
   ```
   Debe mostrar: `🚩 [NombreServicioV3] Despertar servicios: true`

5. **Verificar request en backend**
   - Backend debe recibir `"Despertar": true` en el body

---

## 📝 Archivos Modificados

### `riogas_service.dart`
- ✅ `descargaPedidos()` → DescargaPedidosV3 con Despertar
- ✅ `descargaLecturaMensajes()` → DescargaLecturaMensajesV3 con Despertar
- ✅ `descargaLecturaPedidos()` → DescargaLecturaPedidosV3 con Despertar
- ✅ `finalizarPedido()` → FinalizarPedidoV3 con Despertar
- ✅ Sistema de deduplicación actualizado
- ✅ `_shouldSkipFailedSave()` actualizado

---

## 🎯 Próximos Pasos

1. **Testing completo**: Probar cada uno de los 4 servicios con el flag activado
2. **Validación backend**: Confirmar que backend procesa correctamente el parámetro `Despertar`
3. **Monitoreo**: Revisar logs de producción para detectar patrones de servicios caídos
4. **Optimización**: Ajustar la lógica de reinicio basada en datos reales

---

## 🔗 Documentación Relacionada

- [SISTEMA_FLAGS_SERVICIOS.md](./SISTEMA_FLAGS_SERVICIOS.md) - Sistema de flags completo
- [EJEMPLOS_USO_FLAGS_SERVICIOS.md](./EJEMPLOS_USO_FLAGS_SERVICIOS.md) - Ejemplos prácticos
- [FCM_REMOTE_LOGOUT_SYSTEM.md](./FCM_REMOTE_LOGOUT_SYSTEM.md) - Sistema de logout remoto
- [CAMBIOS_LOGOUT_REMOTO_SIMPLIFICADO.md](./CAMBIOS_LOGOUT_REMOTO_SIMPLIFICADO.md) - Simplificación FCM

---

**Fecha de implementación**: 4 de noviembre de 2025  
**Versión**: V3  
**Estado**: ✅ Completado
