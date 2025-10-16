# 🐛 Diagnóstico: Problema de "QUIETO" Constante

## 📋 Problema Reportado

El sistema **siempre marca como "QUIETO"** aunque las coordenadas GPS muestran movimiento significativo:

```
-34.7972642 -56.1237669 → Estado: inactive | Mov: QUIETO
-34.8201145 -56.1384725 → Estado: inactive | Mov: QUIETO  (se movió ~2.7 km!)
-34.7643734 -56.1354407 → Estado: active | Mov: QUIETO    (se movió ~6.2 km!)
```

**Distancia real recorrida:** ~50+ km  
**Movimiento detectado:** QUIETO en el 95% de los registros ❌

---

## 🔍 Análisis del Código

### 1. Lógica de Detección de Movimiento

```kotlin
// LocationHelper.kt línea 462-467
movementType = when {
    filteredDistance == 0f -> "QUIETO"          // ❌ Filtros descartaron
    filteredDistance < 5.0f -> "QUIETO"         // ❌ Menos de 5m = ruido
    else -> "MOVIMIENTO"                        // ✅ Más de 5m = movimiento
}
```

**Problema:** Si `filteredDistance` es 0 o menor a 5m, marca como QUIETO.

---

### 2. Filtros GPS Aplicados

El método `filterGPSNoise()` aplica **5 filtros consecutivos**:

#### ✅ Filtro 1: Precisión GPS
```kotlin
if (currentAccuracy > 15.0m || lastAccuracy > 15.0m) {
    return 0.0f  // DESCARTA
}
```
**Riesgo:** Si la señal GPS no es perfecta, descarta todo el movimiento.

#### ✅ Filtro 2: Velocidad Realista
```kotlin
if (calculatedSpeed > 50.0 m/s) {  // ~180 km/h
    return 0.0f  // DESCARTA saltos GPS
}
```
**Riesgo:** Saltos GPS entre lecturas cada 3 minutos pueden parecer velocidades irreales.

#### ✅ Filtro 3: Tiempo Mínimo
```kotlin
if (timeDelta < 1000ms) {  // 1 segundo
    return 0.0f  // DESCARTA lecturas muy seguidas
}
```
**Estado:** ✅ PASA (lecturas cada 3 minutos = 180,000ms)

#### ✅ Filtro 4: Umbral Mínimo
```kotlin
if (rawDistance < 2.0m) {
    return 0.0f  // DESCARTA ruido extremo
}
```
**Riesgo Bajo:** Solo afecta movimientos menores a 2m.

#### ⚠️ Filtro 5: Suavizado Adaptativo
```kotlin
val smoothingFactor = when {
    rawDistance < 5.0f && speed < 0.5f -> 0.85f  // Reduce 15%
    speed < 1.0f -> 0.9f                          // Reduce 10%
    speed < 3.0f -> 0.95f                         // Reduce 5%
    else -> 1.0f                                  // Sin reducción
}

filteredDistance = rawDistance * smoothingFactor
```
**Riesgo Alto:** Si la velocidad es baja, reduce la distancia detectada.

---

## 🎯 Causas Probables

### Causa 1: **Filtro de Accuracy Muy Restrictivo**
```
GPS_ACCURACY_THRESHOLD = 15.0 metros
```

Si el GPS tiene accuracy de 16m-20m (común en ciudad con edificios), **descarta TODO el movimiento**.

**Ejemplo:**
```
Coordenadas: -34.7972642 → -34.8201145 (2700m reales)
Accuracy: 18m > 15m threshold
Resultado: filteredDistance = 0.0f → QUIETO ❌
```

---

### Causa 2: **Cálculo de Velocidad con Lecturas Espaciadas**

Con lecturas cada **3 minutos (180 segundos)**:

```kotlin
timeDelta = 180,000ms
rawDistance = 2,700m
calculatedSpeed = (2700 * 1000) / 180,000 = 15 m/s (~54 km/h)
```

**Esto pasa el filtro** (15 m/s < 50 m/s threshold) ✅

**PERO:** Si hay un salto GPS grande (ej: 10 km en 3 min):
```kotlin
calculatedSpeed = (10000 * 1000) / 180,000 = 55.5 m/s (~200 km/h)
Resultado: 55.5 > 50 → DESCARTADO ❌
```

---

### Causa 3: **Suavizado Reduce Distancia a < 5m**

Si la velocidad reportada por el GPS es baja:

```kotlin
rawDistance = 4.5m
speed = 0.3 m/s (GPS reporta velocidad baja)
smoothingFactor = 0.85 (por speed < 0.5 m/s)
filteredDistance = 4.5 * 0.85 = 3.825m

Resultado: 3.825m < 5.0m → QUIETO ❌
```

---

## 🔧 Soluciones Implementadas

### Solución 1: **Logs Detallados de Diagnóstico**

Agregué logs en cada punto crítico:

```kotlin
// Al entrar al filtro
Log.i(TAG, "🔍 [FILTRO] RawDistance: ${rawDistance}m | CurrentAccuracy: ${currentAccuracy}m")

// Si falla accuracy
Log.w(TAG, "🔇 [FILTRO_ACCURACY] ❌ DESCARTADO - accuracy > ${GPS_ACCURACY_THRESHOLD}m")

// Si falla velocidad
Log.w(TAG, "🔇 [FILTRO_SPEED] ❌ DESCARTADO - ${calculatedSpeed}m/s > ${MAX_SPEED_THRESHOLD}m/s")

// Si pasa todos los filtros
Log.i(TAG, "✅ [FILTRO_PASSED] ${rawDistance}m → ${filteredDistance}m | Factor: ${smoothingFactor}")

// Resultado final
Log.i(TAG, "✅ [MOVEMENT_TYPE] MOVIMIENTO - Distancia > 5m (${filteredDistance}m)")
```

**Cómo usar:**
```bash
adb logcat | Select-String "FILTRO"
```

Esto mostrará **exactamente qué filtro está descartando el movimiento**.

---

### Solución 2: **Ajustes Propuestos (NO IMPLEMENTADOS AÚN)**

#### Opción A: Relajar Umbral de Accuracy
```kotlin
val GPS_ACCURACY_THRESHOLD = 25.0f  // Antes: 15.0f
```
**Pros:** Acepta GPS con señal moderada (edificios, árboles)  
**Contras:** Puede permitir algo de ruido GPS

---

#### Opción B: Ajustar Umbral de "QUIETO"
```kotlin
movementType = when {
    filteredDistance == 0f -> "QUIETO"
    filteredDistance < 3.0f -> "QUIETO"  // Antes: 5.0f
    else -> "MOVIMIENTO"
}
```
**Pros:** Detecta movimientos de 3-5m como reales  
**Contras:** Puede inflar distancia con ruido GPS

---

#### Opción C: Desactivar Suavizado para Distancias Grandes
```kotlin
val smoothingFactor = when {
    rawDistance > 100.0f -> 1.0f                  // Sin suavizado para grandes distancias
    rawDistance < 5.0f && speed < 0.5f -> 0.85f
    speed < 1.0f -> 0.9f
    speed < 3.0f -> 0.95f
    else -> 1.0f
}
```
**Pros:** No penaliza movimientos largos entre lecturas  
**Contras:** Ninguno significativo

---

## 📊 Próximos Pasos

### Paso 1: **Capturar Logs Reales**

Ejecutar en terminal:
```bash
adb logcat -c  # Limpiar logs
adb logcat | Select-String "FILTRO|MOVEMENT"
```

Esperar a que el servicio envíe coordenadas (cada 3 minutos) y capturar:
```
🔍 [FILTRO] RawDistance: 2700m | CurrentAccuracy: 18m
🔇 [FILTRO_ACCURACY] ❌ DESCARTADO - accuracy > 15m
⚠️ [MOVEMENT_TYPE] QUIETO - Filtros descartaron el movimiento
```

---

### Paso 2: **Identificar Filtro Problemático**

Buscar en logs:
- ¿Cuántos registros tienen `[FILTRO_ACCURACY] ❌`?
- ¿Cuántos tienen `[FILTRO_SPEED] ❌`?
- ¿Cuántos tienen `[FILTRO_PASSED]` pero luego `QUIETO`?

---

### Paso 3: **Aplicar Ajuste Específico**

Según los logs, aplicar **solo UNA** de estas soluciones:

| Si el problema es... | Aplicar solución... |
|----------------------|---------------------|
| Accuracy > 15m frecuente | Opción A: Aumentar threshold a 25m |
| Distancias 3-5m marcadas QUIETO | Opción B: Bajar umbral a 3m |
| Suavizado reduce mucho | Opción C: Desactivar para distancias grandes |
| Velocidad calculada > 50m/s | Aumentar MAX_SPEED_THRESHOLD a 70m/s |

---

## 🎓 Resumen Técnico

| Aspecto | Estado Actual | Acción |
|---------|---------------|--------|
| **Logs de diagnóstico** | ✅ Implementados | Capturar logs reales |
| **Filtro Accuracy (15m)** | ⚠️ Muy restrictivo | Considerar aumentar a 25m |
| **Filtro Velocidad (50 m/s)** | ⚠️ Puede ser bajo para 3 min | Considerar aumentar a 70 m/s |
| **Umbral QUIETO (5m)** | ⚠️ Puede ser alto | Considerar bajar a 3m |
| **Suavizado adaptativo** | ⚠️ Penaliza movimientos lentos | Desactivar para distancias > 100m |
| **Distancia acumulada** | ❓ Sin verificar | Verificar con logs |

---

## 📝 Ejemplo de Logs Esperados

### Caso 1: Movimiento Real Detectado ✅
```
🔍 [FILTRO] RawDistance: 2700m | CurrentAccuracy: 12m | LastAccuracy: 14m
🔍 [FILTRO] TimeDelta: 180000ms | CalculatedSpeed: 15.0m/s
✅ [FILTRO_PASSED] Distancia: 2700m → 2700m | Factor: 1.0 | Speed: 15.0m/s
✅ [MOVEMENT_TYPE] MOVIMIENTO - Distancia > 5m (2700m)
✅ Movimiento real: 2700m → Sumado: 2700m (Total: 15432m)
```

---

### Caso 2: Descartado por Accuracy ❌
```
🔍 [FILTRO] RawDistance: 2700m | CurrentAccuracy: 18m | LastAccuracy: 16m
🔇 [FILTRO_ACCURACY] ❌ DESCARTADO - current=18m > 15m
⚠️ [MOVEMENT_TYPE] QUIETO - Filtros descartaron el movimiento (filteredDistance = 0)
🔇 Distancia descartada por filtros: 2700m | Tipo: QUIETO
```

---

### Caso 3: Descartado por Velocidad ❌
```
🔍 [FILTRO] RawDistance: 12000m | CurrentAccuracy: 10m | LastAccuracy: 12m
🔍 [FILTRO] TimeDelta: 180000ms | CalculatedSpeed: 66.67m/s
🔇 [FILTRO_SPEED] ❌ DESCARTADO - 66.67m/s > 50m/s (Salto GPS)
⚠️ [MOVEMENT_TYPE] QUIETO - Filtros descartaron el movimiento (filteredDistance = 0)
```

---

### Caso 4: Reducido por Suavizado ❌
```
🔍 [FILTRO] RawDistance: 4.8m | CurrentAccuracy: 10m | LastAccuracy: 12m
🔍 [FILTRO] TimeDelta: 180000ms | CalculatedSpeed: 0.027m/s
✅ [FILTRO_PASSED] Distancia: 4.8m → 4.08m | Factor: 0.85 | Speed: 0.3m/s
ℹ️ [MOVEMENT_TYPE] QUIETO - Movimiento menor a 5m (4.08m = Ruido GPS)
💡 Ruido GPS: 4.8m → 4.08m → Sumado: 0.1m (Total: 15432m)
```

---

## 🚀 Comando para Monitoreo en Tiempo Real

```bash
# Monitoreo completo
adb logcat | Select-String "FILTRO|MOVEMENT|Coordenadas"

# Solo ver descartados
adb logcat | Select-String "DESCARTADO"

# Solo ver movimientos detectados
adb logcat | Select-String "MOVIMIENTO - Distancia"

# Ver acumulado de distancia
adb logcat | Select-String "Total:"
```

---

**Última actualización:** 16 de octubre de 2025  
**Versión:** 1.0  
**Estado:** ✅ Logs implementados, esperando diagnóstico real
