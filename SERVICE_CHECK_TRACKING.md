# 📊 Sistema de Tracking del Estado del Servicio de Ubicación

## 🎯 Objetivo

Registrar en Hive el resultado de cada verificación del servicio de ubicación en segundo plano y enviar esta información en el campo `NroSesion` de las peticiones `descargaLecturaPedidos` y `descargaPedidos`.

## 📋 Descripción General

Cada vez que se accede a `order_detail_page.dart`, el sistema verifica automáticamente el estado del servicio de ubicación en segundo plano mediante el método `checkAndRestartLocationService` de Kotlin. El resultado de esta verificación se guarda en Hive en un formato compacto de 13 caracteres.

## 🔧 Formato del Registro

### Estructura: `YYMMDDHHMMSS + StatusCode`

**Ejemplos:**
- `250116143025R` → "16 de enero de 2025, 14:30:25, servicio **Reiniciado**"
- `250116143540A` → "16 de enero de 2025, 14:35:40, servicio **Activo**"
- `250116144012D` → "16 de enero de 2025, 14:40:12, servicio **Deshabilitado**"
- `250116144230E` → "16 de enero de 2025, 14:42:30, **Error** en verificación"
- `NOCHECK` → Valor por defecto si nunca se ha verificado el servicio

### Códigos de Estado

| Código | Estado | Descripción |
|--------|--------|-------------|
| `A` | **Active** | Servicio activo y funcionando correctamente |
| `R` | **Restarted** | Servicio fue reiniciado automáticamente porque estaba detenido |
| `D` | **Disabled** | Servicio deshabilitado al cerrar sesión (manual o automático) |
| `N` | **Never Started** | Servicio nunca fue iniciado por el usuario |
| `E` | **Error** | Error al verificar el estado del servicio |
| `U` | **Unknown** | Estado desconocido (caso excepcional) |

## 📂 Ubicación en Hive

- **Box:** `sessionBox`
- **Key:** `lastServiceCheck`
- **Valor:** String de 13 caracteres (ej: `250116143025R`)

## 🔄 Flujo de Operación

```
┌─────────────────────────────────────────────────────────────────┐
│                   Usuario accede a order_detail_page.dart        │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│  initState() → _checkAndRestartLocationService()                │
│  • Llama a MainActivity.kt (MethodChannel)                      │
│  • Ejecuta checkAndRestartLocationService()                     │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│  Kotlin verifica estado del servicio:                           │
│  1. ¿Está deshabilitado manualmente? → 'D'                      │
│  2. ¿Servicio nunca iniciado? → 'N'                             │
│  3. ¿Servicio corriendo + Alarm activo? → 'A'                   │
│  4. ¿Servicio muerto o alarm cancelado? → Reiniciar → 'R'       │
│  5. ¿Error en verificación? → 'E'                               │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│  order_detail_page.dart (finally block):                        │
│  • Genera timestamp: YYMMDDHHMMSS                               │
│  • Concatena con código: timestamp + statusCode                 │
│  • Guarda en Hive: sessionBox.put('lastServiceCheck', record)   │
│  • Log: "💾 Guardado en Hive: 250116143025R (Reiniciado)"      │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│  Usuario interactúa con pending_orders.dart                     │
│  • Tap en tarjeta de pedido                                     │
│  • Sistema llama a _callDescargaLecturaPedidos()                │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│  _callDescargaLecturaPedidos():                                 │
│  • Abre sessionBox                                              │
│  • Lee lastServiceCheck (ej: "250116143025R")                   │
│  • Log: "🔍 Usando NroSesion desde lastServiceCheck: ..."      │
│  • Llama a RioGasService.descargaLecturaPedidos()               │
│    - NroSesion = lastServiceCheck                               │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│  Servidor recibe petición con NroSesion = "250116143025R"       │
│  • Puede decodificar: Fecha/Hora + Estado del servicio          │
│  • Puede rastrear: ¿Cuándo fue la última verificación?          │
│  • Puede analizar: ¿Cuántas veces se reinició el servicio?      │
└─────────────────────────────────────────────────────────────────┘
```

## 🔍 Casos de Uso

### Caso 1: Servicio Activo (Flujo Normal)

```
1. Usuario entra a order_detail_page.dart
2. Sistema verifica servicio → está activo
3. Guarda en Hive: "250116143025A"
4. Usuario toca pedido en pending_orders
5. Se envía descargaLectura con NroSesion="250116143025A"
6. Servidor sabe: "El servicio estaba activo a las 14:30:25"
```

### Caso 2: Servicio Reiniciado Automáticamente

```
1. Usuario entra a order_detail_page.dart
2. Sistema verifica servicio → está muerto
3. Sistema reinicia servicio automáticamente
4. Guarda en Hive: "250116143540R"
5. Muestra SnackBar verde: "Servicio de ubicación reiniciado"
6. Usuario toca pedido en pending_orders
7. Se envía descargaLectura con NroSesion="250116143540R"
8. Servidor sabe: "El servicio tuvo que ser reiniciado a las 14:35:40"
```

### Caso 3: Servicio Deshabilitado por Usuario

```
1. Usuario cierra sesión desde settings_page.dart (botón "Cerrar Sesión")
   O sistema hace logout automático (sesión expirada, error auth)
2. Sistema ejecuta stopLocationService() antes de logout
3. Se marca service_disabled = true en SharedPreferences
4. Usuario vuelve a iniciar sesión
5. Usuario entra a order_detail_page.dart
6. Sistema verifica servicio → está deshabilitado
7. NO se reinicia (porque fue detenido intencionalmente al logout)
8. Guarda en Hive: "250116144012D"
9. Usuario toca pedido en pending_orders
10. Se envía descargaLectura con NroSesion="250116144012D"
11. Servidor sabe: "El servicio se detuvo al cerrar sesión (no reiniciado aún)"

NOTA: El servicio se reactivará automáticamente cuando el usuario:
- Entre a pending_orders.dart (inicia servicio al cargar pedidos)
- O cuando el sistema detecte actividad de pedidos
```

### Caso 4: Error en Verificación

```
1. Usuario entra a order_detail_page.dart
2. Sistema intenta verificar servicio → exception/crash
3. Guarda en Hive: "250116144230E"
4. Usuario toca pedido en pending_orders
5. Se envía descargaLectura con NroSesion="250116144230E"
6. Servidor sabe: "Hubo un error al verificar el servicio a las 14:42:30"
```

### Caso 5: Primera Ejecución (Nunca Verificado)

```
1. App instalada por primera vez
2. Usuario entra directo a pending_orders (sin pasar por order_detail)
3. Se intenta leer lastServiceCheck → no existe
4. Se usa valor por defecto: "NOCHECK"
5. Se envía descargaLectura con NroSesion="NOCHECK"
6. Servidor sabe: "Este dispositivo aún no ha verificado el servicio"
```

## 📊 Análisis de Datos en Servidor

El servidor puede usar `NroSesion` para:

### 1. Monitoreo de Salud del Servicio
```python
# Pseudocódigo de análisis
if nro_sesion.endswith('A'):
    # Servicio funcionando bien
    log_healthy_service()
elif nro_sesion.endswith('R'):
    # Servicio tuvo que ser reiniciado
    log_service_restart()
    alert_if_too_many_restarts()
elif nro_sesion.endswith('D'):
    # Usuario deshabilitó servicio
    log_user_disabled_service()
elif nro_sesion.endswith('E'):
    # Error de verificación
    log_verification_error()
    alert_technical_team()
```

### 2. Métricas de Confiabilidad
```sql
-- Porcentaje de servicios activos vs reiniciados
SELECT 
    COUNT(CASE WHEN nro_sesion LIKE '%A' THEN 1 END) * 100.0 / COUNT(*) as pct_activos,
    COUNT(CASE WHEN nro_sesion LIKE '%R' THEN 1 END) * 100.0 / COUNT(*) as pct_reiniciados
FROM pedidos_descargados
WHERE fecha >= '2025-01-01';
```

### 3. Detección de Patrones Problemáticos
```python
# Detectar dispositivos con muchos reinicios
dispositivos_con_reinicios = db.query("""
    SELECT device_id, COUNT(*) as num_reinicios
    FROM pedidos_descargados
    WHERE nro_sesion LIKE '%R'
    GROUP BY device_id
    HAVING num_reinicios > 10
""")
```

### 4. Timeline de Estado del Servicio
```python
# Extraer timestamp del registro
def parse_service_check(nro_sesion):
    if len(nro_sesion) != 13:
        return None, None
    
    timestamp = nro_sesion[:12]  # YYMMDDHHMMSS
    status_code = nro_sesion[12]  # A, R, D, E, N, U
    
    # Convertir a fecha
    year = 2000 + int(timestamp[0:2])
    month = int(timestamp[2:4])
    day = int(timestamp[4:6])
    hour = int(timestamp[6:8])
    minute = int(timestamp[8:10])
    second = int(timestamp[10:12])
    
    return datetime(year, month, day, hour, minute, second), status_code

# Ejemplo de uso
timestamp, status = parse_service_check("250116143025R")
# timestamp = datetime(2025, 1, 16, 14, 30, 25)
# status = 'R' (Reiniciado)
```

## 🧪 Testing y Validación

### Logs Esperados

#### En order_detail_page.dart
```dart
🔄[SERVICE_CHECK] Verificando estado del servicio de ubicación...
🔄[SERVICE_CHECK] Estado: active - El servicio está activo
🔄[SERVICE_CHECK] ✅ Servicio activo y funcionando correctamente
🔄[SERVICE_CHECK] 💾 Guardado en Hive: 250116143025A (Activo)
```

#### En pending_orders.dart
```dart
🟠 [_callDescargaLecturaPedidos] Iniciando para pedidoId: 12345
🔍 Usando NroSesion desde lastServiceCheck: 250116143025A
✅ Petición completada con éxito para pedido 12345
```

### Comandos de Verificación

```bash
# Ver logs de verificación del servicio
adb logcat | Select-String "SERVICE_CHECK"

# Ver logs de uso de NroSesion
adb logcat | Select-String "lastServiceCheck"

# Verificar valor en Hive (desde la app)
# En Dart:
final sessionBox = await Hive.openBox('sessionBox');
print('lastServiceCheck: ${sessionBox.get('lastServiceCheck')}');
```

## 🔒 Consideraciones de Seguridad

1. **No contiene información sensible**: Solo timestamp + código de estado
2. **No identifica usuario**: Es solo un indicador técnico
3. **Límite de 13 caracteres**: Cumple con restricciones de campo
4. **Valor por defecto seguro**: "NOCHECK" si no hay dato

## 📝 Mantenimiento

### Evolución del Sistema

Si en el futuro se necesita más información, se pueden agregar códigos adicionales:

```dart
// Ejemplo de expansión futura
'A1' // Activo, GPS con alta precisión
'A2' // Activo, GPS con baja precisión
'R1' // Reiniciado, primera vez
'R2' // Reiniciado, múltiples veces
'D1' // Deshabilitado, batería crítica
'D2' // Deshabilitado, manualmente
```

### Limitaciones del Formato Actual

- **Tamaño fijo**: 13 caracteres (12 timestamp + 1 código)
- **Granularidad**: Hasta segundos, no milisegundos
- **Códigos**: Solo 1 carácter por estado
- **Año**: Formato YY (válido hasta 2099)

## 🎓 Resumen Técnico

| Aspecto | Detalle |
|---------|---------|
| **Trigger** | Acceso a `order_detail_page.dart` |
| **Método** | `_checkAndRestartLocationService()` |
| **Almacenamiento** | Hive `sessionBox`, key `lastServiceCheck` |
| **Formato** | 13 chars: `YYMMDDHHMMSS` + código (A/R/D/N/E/U) |
| **Uso** | Campo `NroSesion` en `descargaLecturaPedidos` y `descargaPedidos` |
| **Default** | `'NOCHECK'` si nunca se verificó |
| **Persistencia** | Se sobrescribe en cada verificación (solo último estado) |
| **Códigos** | A=Activo, R=Reiniciado, D=Deshabilitado, N=Nunca iniciado, E=Error, U=Desconocido |

## 📚 Referencias

- **Archivo principal**: `order_detail_page.dart` (líneas 203-289)
- **Uso en descarga individual**: `pending_orders.dart` (línea 615-627)
- **Uso en descarga masiva**: `pending_orders.dart` (línea 768-770)
- **Verificación Kotlin**: `MainActivity.kt` (método `checkAndRestartLocationService`)
- **Documentación relacionada**: `SERVICIO_AUTO_RESTART.md`

---

**Última actualización:** 16 de enero de 2025  
**Versión:** 1.0  
**Estado:** ✅ Implementado y compilado
