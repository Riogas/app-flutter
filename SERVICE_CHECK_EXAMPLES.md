# 📊 Ejemplos de Tracking del Estado del Servicio

## 🎯 Escenarios Reales de Uso

### Escenario 1: Día Normal de Operación
```
Timeline del dispositivo 001:

08:30 AM → Usuario abre app, entra a ver pedido #1001
          lastServiceCheck = "250116083000A" (Activo)
          Se envía descargaLectura con NroSesion="250116083000A"

09:15 AM → Usuario entra a ver pedido #1002  
          lastServiceCheck = "250116091500A" (Activo)
          Se envía descargaLectura con NroSesion="250116091500A"

10:45 AM → Usuario entra a ver pedido #1003
          lastServiceCheck = "250116104500A" (Activo)
          Se envía descargaLectura con NroSesion="250116104500A"

12:20 PM → Usuario entra a ver pedido #1004
          lastServiceCheck = "250116122000A" (Activo)
          Se envía descargaLectura con NroSesion="250116122000A"

Análisis: ✅ Servicio estable todo el día, sin interrupciones
```

---

### Escenario 2: Servicio Se Cae y Se Recupera Automáticamente
```
Timeline del dispositivo 002:

09:00 AM → Usuario abre app, entra a ver pedido #2001
          lastServiceCheck = "250116090000A" (Activo)
          Se envía descargaLectura con NroSesion="250116090000A"

11:30 AM → Android mata el servicio por falta de memoria
          (No hay registro porque no se verificó)

11:45 AM → Usuario entra a ver pedido #2002
          Sistema detecta: servicio muerto
          Sistema reinicia: servicio automáticamente
          lastServiceCheck = "250116114500R" (Reiniciado) ⚠️
          SnackBar verde: "Servicio de ubicación reiniciado"
          Se envía descargaLectura con NroSesion="250116114500R"

12:00 PM → Usuario entra a ver pedido #2003
          lastServiceCheck = "250116120000A" (Activo)
          Se envía descargaLectura con NroSesion="250116120000A"

Análisis: ⚠️ Servicio tuvo un fallo a las 11:45, se recuperó automáticamente
```

---

### Escenario 3: Usuario Deshabilita el Servicio
```
Timeline del dispositivo 003:

10:00 AM → Usuario abre app, entra a ver pedido #3001
          lastServiceCheck = "250116100000A" (Activo)
          Se envía descargaLectura con NroSesion="250116100000A"

11:00 AM → Usuario va a Configuración y deshabilita el servicio
          (Se guarda service_disabled=true en SharedPreferences)

11:30 AM → Usuario entra a ver pedido #3002
          Sistema detecta: service_disabled=true
          Sistema NO reinicia (respeta decisión del usuario)
          lastServiceCheck = "250116113000D" (Deshabilitado) 🚫
          Se envía descargaLectura con NroSesion="250116113000D"

12:00 PM → Usuario entra a ver pedido #3003
          lastServiceCheck = "250116120000D" (Deshabilitado) 🚫
          Se envía descargaLectura con NroSesion="250116120000D"

Análisis: 🚫 Usuario deshabilitó el servicio intencionalmente a las 11:00
```

---

### Escenario 4: Error en la Verificación
```
Timeline del dispositivo 004:

09:00 AM → Usuario abre app, entra a ver pedido #4001
          lastServiceCheck = "250116090000A" (Activo)
          Se envía descargaLectura con NroSesion="250116090000A"

10:30 AM → Corrupción en SharedPreferences / Error de sistema
          Usuario entra a ver pedido #4002
          Sistema intenta verificar → Exception/Crash
          lastServiceCheck = "250116103000E" (Error) ❌
          Se envía descargaLectura con NroSesion="250116103000E"

11:00 AM → Usuario reinicia la app
          Usuario entra a ver pedido #4003
          lastServiceCheck = "250116110000A" (Activo)
          Se envía descargaLectura con NroSesion="250116110000A"

Análisis: ❌ Error transitorio a las 10:30, se recuperó al reiniciar
```

---

### Escenario 5: Primera Instalación
```
Timeline del dispositivo 005:

Primera vez - 08:00 AM → Usuario instala la app

08:15 AM → Usuario abre la app
          Usuario ve lista de pedidos en pending_orders
          Hace tap en pedido #5001
          Sistema intenta leer lastServiceCheck → No existe
          Se usa valor por defecto: "NOCHECK"
          Se envía descargaLectura con NroSesion="NOCHECK"

08:20 AM → Usuario entra a ver pedido #5002
          Sistema verifica servicio por primera vez
          lastServiceCheck = "250116082000A" (Activo) ✅
          Se envía descargaLectura con NroSesion="250116082000A"

Análisis: ℹ️ Primera ejecución, aún no se había verificado el servicio
```

---

### Escenario 6: Múltiples Reinicios (Problema Grave)
```
Timeline del dispositivo 006:

09:00 AM → lastServiceCheck = "250116090000A" (Activo)
09:30 AM → lastServiceCheck = "250116093000R" (Reiniciado) ⚠️
10:00 AM → lastServiceCheck = "250116100000R" (Reiniciado) ⚠️
10:30 AM → lastServiceCheck = "250116103000R" (Reiniciado) ⚠️
11:00 AM → lastServiceCheck = "250116110000R" (Reiniciado) ⚠️
11:30 AM → lastServiceCheck = "250116113000R" (Reiniciado) ⚠️

Análisis: 🚨 5 reinicios en 2.5 horas → Problema crítico de memoria/batería
          El servidor debe alertar al equipo técnico
          Posibles causas:
          - Android agresivo con la gestión de memoria
          - Batería baja constante
          - Conflicto con otra app
          - Bug en el servicio
```

---

## 📊 Análisis de Patrones en Base de Datos

### Consulta 1: Dispositivos con Servicio Estable
```sql
-- Dispositivos que nunca tuvieron un reinicio en los últimos 7 días
SELECT 
    device_id,
    COUNT(*) as total_peticiones,
    COUNT(CASE WHEN nro_sesion LIKE '%A' THEN 1 END) as activo_count
FROM pedidos_descargados
WHERE fecha >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY device_id
HAVING activo_count = total_peticiones
ORDER BY total_peticiones DESC;
```

**Resultado Ejemplo:**
```
device_id       | total_peticiones | activo_count
----------------|------------------|-------------
DEVICE_001      | 45               | 45
DEVICE_003      | 38               | 38
DEVICE_005      | 52               | 52
```
**Interpretación:** ✅ Estos dispositivos tienen servicio 100% estable

---

### Consulta 2: Dispositivos con Problemas Frecuentes
```sql
-- Dispositivos con más del 30% de reinicios
SELECT 
    device_id,
    COUNT(*) as total_peticiones,
    COUNT(CASE WHEN nro_sesion LIKE '%R' THEN 1 END) as reiniciado_count,
    ROUND(COUNT(CASE WHEN nro_sesion LIKE '%R' THEN 1 END) * 100.0 / COUNT(*), 2) as pct_reinicios
FROM pedidos_descargados
WHERE fecha >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY device_id
HAVING pct_reinicios > 30
ORDER BY pct_reinicios DESC;
```

**Resultado Ejemplo:**
```
device_id       | total_peticiones | reiniciado_count | pct_reinicios
----------------|------------------|------------------|---------------
DEVICE_006      | 40               | 25               | 62.50%
DEVICE_012      | 35               | 18               | 51.43%
DEVICE_008      | 30               | 12               | 40.00%
```
**Interpretación:** 🚨 Estos dispositivos necesitan atención urgente

---

### Consulta 3: Usuarios que Deshabilitaron el Servicio
```sql
-- Última vez que cada dispositivo tuvo estado 'D' (Deshabilitado)
SELECT 
    device_id,
    MAX(fecha) as ultima_vez_deshabilitado,
    COUNT(*) as veces_deshabilitado
FROM pedidos_descargados
WHERE nro_sesion LIKE '%D'
GROUP BY device_id
ORDER BY ultima_vez_deshabilitado DESC;
```

**Resultado Ejemplo:**
```
device_id       | ultima_vez_deshabilitado | veces_deshabilitado
----------------|--------------------------|--------------------
DEVICE_010      | 2025-01-16 14:30:00      | 3
DEVICE_015      | 2025-01-15 16:20:00      | 1
DEVICE_007      | 2025-01-14 09:45:00      | 2
```
**Interpretación:** ℹ️ Estos usuarios deshabilitaron manualmente el servicio

---

### Consulta 4: Timeline de un Dispositivo Específico
```sql
-- Ver historial completo de verificaciones de un dispositivo
SELECT 
    fecha,
    nro_sesion,
    pedido_id,
    CASE 
        WHEN nro_sesion LIKE '%A' THEN '✅ Activo'
        WHEN nro_sesion LIKE '%R' THEN '⚠️ Reiniciado'
        WHEN nro_sesion LIKE '%D' THEN '🚫 Deshabilitado'
        WHEN nro_sesion LIKE '%E' THEN '❌ Error'
        WHEN nro_sesion LIKE '%N' THEN 'ℹ️ Nunca iniciado'
        WHEN nro_sesion = 'NOCHECK' THEN '❓ Sin verificar'
        ELSE '❓ Desconocido'
    END as estado
FROM pedidos_descargados
WHERE device_id = 'DEVICE_006'
ORDER BY fecha DESC
LIMIT 20;
```

**Resultado Ejemplo:**
```
fecha                   | nro_sesion     | pedido_id | estado
------------------------|----------------|-----------|------------------
2025-01-16 14:30:00     | 250116143000R  | 6015      | ⚠️ Reiniciado
2025-01-16 14:00:00     | 250116140000R  | 6014      | ⚠️ Reiniciado
2025-01-16 13:30:00     | 250116133000A  | 6013      | ✅ Activo
2025-01-16 13:00:00     | 250116130000R  | 6012      | ⚠️ Reiniciado
2025-01-16 12:30:00     | 250116123000A  | 6011      | ✅ Activo
```
**Interpretación:** ⚠️ Dispositivo con problemas intermitentes de estabilidad

---

## 📈 Dashboards Sugeridos

### Dashboard 1: Estado General de Flota
```
┌─────────────────────────────────────────────────────────────┐
│  Estado del Servicio de Ubicación - Últimas 24 Horas        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ✅ Activo:           85% ████████████████████░░░░          │
│  ⚠️ Reiniciado:       10% ██░░░░░░░░░░░░░░░░░░░░          │
│  🚫 Deshabilitado:     3% █░░░░░░░░░░░░░░░░░░░░░          │
│  ❌ Error:             2% █░░░░░░░░░░░░░░░░░░░░░          │
│                                                              │
│  Total de dispositivos activos: 45                          │
│  Total de verificaciones: 1,234                             │
│  Promedio de verificaciones/dispositivo: 27.4               │
└─────────────────────────────────────────────────────────────┘
```

### Dashboard 2: Top 10 Dispositivos Problemáticos
```
┌─────────────────────────────────────────────────────────────┐
│  Dispositivos con Mayor Tasa de Reinicios                   │
├──────────────┬───────────────┬──────────────┬───────────────┤
│  Device ID   │  Verificac.   │  Reinicios   │  % Reinicios  │
├──────────────┼───────────────┼──────────────┼───────────────┤
│  DEVICE_006  │      40       │      25      │    62.5%      │
│  DEVICE_012  │      35       │      18      │    51.4%      │
│  DEVICE_008  │      30       │      12      │    40.0%      │
│  DEVICE_019  │      28       │      11      │    39.3%      │
│  DEVICE_023  │      32       │      12      │    37.5%      │
└──────────────┴───────────────┴──────────────┴───────────────┘
```

### Dashboard 3: Timeline de un Dispositivo
```
┌─────────────────────────────────────────────────────────────┐
│  DEVICE_006 - Timeline de Estado del Servicio               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  08:00  ✅──────────────────────────────────                │
│  09:00  ✅──────────────────────────────────                │
│  10:00  ⚠️──────────────────────────────────                │
│  11:00  ✅──────────────────────────────────                │
│  12:00  ⚠️──────────────────────────────────                │
│  13:00  ✅──────────────────────────────────                │
│  14:00  ⚠️──────────────────────────────────                │
│  15:00  ⚠️──────────────────────────────────                │
│  16:00  ✅──────────────────────────────────                │
│                                                              │
│  Eventos: 2 reinicios en últimas 3 horas                    │
│  Recomendación: Verificar batería y memoria del dispositivo │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎓 Interpretación de Códigos en Contexto

### Código "A" (Activo)
```
250116143025A

Significado:
- Fecha: 16 de enero de 2025
- Hora: 14:30:25
- Estado: Servicio ACTIVO y funcionando correctamente

Contexto:
✅ Todo está bien, el servicio no necesitó intervención
✅ El GPS está enviando coordenadas cada 3 minutos
✅ El usuario puede confiar en el tracking
```

### Código "R" (Reiniciado)
```
250116143025R

Significado:
- Fecha: 16 de enero de 2025
- Hora: 14:30:25
- Estado: Servicio fue REINICIADO automáticamente

Contexto:
⚠️ El servicio estaba muerto y se recuperó automáticamente
⚠️ Hubo un gap de tiempo sin envío de coordenadas
⚠️ Puede haber perdido eventos de ubicación
⚠️ Si es frecuente, indica problema de memoria/batería
```

### Código "D" (Deshabilitado)
```
250116143025D

Significado:
- Fecha: 16 de enero de 2025
- Hora: 14:30:25
- Estado: Servicio DESHABILITADO por el usuario

Contexto:
🚫 El usuario apagó el servicio intencionalmente
🚫 No hay envío de coordenadas
🚫 El sistema respeta esta decisión y NO lo reinicia
🚫 El usuario debe habilitarlo manualmente para reactivar
```

### Código "E" (Error)
```
250116143025E

Significado:
- Fecha: 16 de enero de 2025
- Hora: 14:30:25
- Estado: ERROR al verificar el servicio

Contexto:
❌ Exception/crash durante la verificación
❌ Estado del servicio desconocido
❌ Posible bug o corrupción de datos
❌ Requiere investigación técnica
```

### Código "NOCHECK"
```
NOCHECK

Significado:
- Nunca se ha verificado el estado del servicio

Contexto:
ℹ️ Primera ejecución de la app
ℹ️ Usuario fue directo a pending_orders sin pasar por order_detail
ℹ️ Es un estado temporal, se actualizará en la próxima verificación
```

---

## 🔍 Casos de Uso del Servidor

### Caso 1: Alerta Automática por Múltiples Reinicios
```python
# Pseudocódigo de backend
def check_service_health(device_id):
    last_20_checks = get_last_checks(device_id, limit=20)
    restart_count = sum(1 for check in last_20_checks if check.endswith('R'))
    
    if restart_count > 10:  # Más del 50% de reinicios
        send_alert(
            title="⚠️ Servicio inestable",
            message=f"Dispositivo {device_id} tuvo {restart_count} reinicios en últimas 20 verificaciones",
            severity="HIGH"
        )
```

### Caso 2: Reportes Automáticos al Cliente
```python
# Generar reporte semanal
def generate_weekly_report(device_id):
    checks = get_checks_last_7_days(device_id)
    
    report = {
        "device_id": device_id,
        "total_verificaciones": len(checks),
        "servicio_activo": sum(1 for c in checks if c.endswith('A')),
        "servicio_reiniciado": sum(1 for c in checks if c.endswith('R')),
        "servicio_deshabilitado": sum(1 for c in checks if c.endswith('D')),
        "errores": sum(1 for c in checks if c.endswith('E')),
        "confiabilidad": calculate_reliability(checks),
        "recomendaciones": generate_recommendations(checks)
    }
    
    send_email_report(device_id, report)
```

### Caso 3: Predicción de Fallos
```python
# Machine Learning para predecir fallos
def predict_service_failure(device_id):
    # Obtener últimos 100 checks
    history = get_last_checks(device_id, limit=100)
    
    # Extraer features
    features = {
        "restart_frequency": calculate_restart_frequency(history),
        "error_rate": calculate_error_rate(history),
        "time_since_last_restart": time_since_last_restart(history),
        "battery_level": get_battery_level(device_id),
        "memory_usage": get_memory_usage(device_id)
    }
    
    # Usar modelo ML
    failure_probability = ml_model.predict(features)
    
    if failure_probability > 0.7:
        send_proactive_alert(device_id, failure_probability)
```

---

**Última actualización:** 16 de enero de 2025  
**Versión:** 1.0  
**Estado:** ✅ Ejemplos documentados
