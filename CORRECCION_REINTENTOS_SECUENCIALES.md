# 🔧 Corrección: Reintentos Secuenciales

## 🐛 Problema Original

**Síntoma:** Coordenadas duplicadas enviadas al mismo tiempo
```
2025-10-10 09:37:13.000 ← Mismo segundo
2025-10-10 09:37:13.000 ← Mismo segundo
2025-10-10 09:37:13.000 ← Mismo segundo
```

**Causa:** Los reintentos se ejecutaban en **threads paralelos**, causando:
1. Múltiples envíos simultáneos
2. Delays acumulativos incorrectos
3. No había control de ejecución secuencial

---

## ✅ Solución Implementada

### **Cambio 1: Reintentos Secuenciales en UN SOLO Thread**

**Antes (❌ INCORRECTO):**
```kotlin
Thread {
    // Intento 1
    invokeRegistrarCoordenadasV2ApiWithRetry(..., retryCount + 1) // ← Crea NUEVO thread
}.start()

// Resultado: 3 threads en paralelo = 3 envíos simultáneos
```

**Después (✅ CORRECTO):**
```kotlin
Thread {
    var currentAttempt = 0
    while (currentAttempt < maxRetries && !success) {
        // Intento dentro del MISMO thread
        client.newCall(request).execute()
        
        if (!success && currentAttempt < maxRetries - 1) {
            Thread.sleep(5000) // Esperar 5s
            currentAttempt++
        }
    }
}.start()

// Resultado: 1 solo thread, reintentos secuenciales
```

---

### **Cambio 2: Delay Fijo de 5 Segundos**

**Antes (Backoff Exponencial):**
- Intento 1: 0s
- Intento 2: 1s después
- Intento 3: 2s después
- **Total:** 3 segundos de delay

**Después (Delay Fijo):**
- Intento 1: 0s
- Intento 2: 5s después
- Intento 3: 5s después
- **Total:** 10 segundos de delay máximo

---

### **Cambio 3: Timeouts Reducidos**

**Antes:**
```kotlin
.connectTimeout(15, SECONDS)
.writeTimeout(15, SECONDS)
.readTimeout(30, SECONDS)
// Total: hasta 60 segundos por intento
```

**Después:**
```kotlin
.connectTimeout(10, SECONDS)
.writeTimeout(10, SECONDS)
.readTimeout(10, SECONDS)
// Total: hasta 30 segundos por intento
```

---

## 📊 Comportamiento Esperado Ahora

### **Escenario 1: Envío Exitoso (Primer Intento)**
```
09:51:49 - Obtener GPS
09:51:50 - Intento 1 → ✅ Éxito
09:51:50 - Reprogramar alarma para 10:06:49
```
**Delay:** ~1 segundo

---

### **Escenario 2: Falla + Reintento Exitoso**
```
09:51:49 - Obtener GPS
09:51:50 - Intento 1 → ❌ Error HTTP 500
09:51:55 - Intento 2 (5s después) → ✅ Éxito
09:51:55 - Reprogramar alarma para 10:06:49
```
**Delay:** ~6 segundos

---

### **Escenario 3: Todos los Intentos Fallan**
```
09:51:49 - Obtener GPS
09:51:50 - Intento 1 → ❌ Error
09:51:55 - Intento 2 (5s después) → ❌ Error
09:52:00 - Intento 3 (5s después) → ❌ Error
09:52:00 - 💥 Coordenada PERDIDA
09:52:00 - Reprogramar alarma para 10:06:49
```
**Delay:** ~11 segundos

---

### **Escenario 4: Ejemplo Real con Retraso**
```
08:51:49 - Coordenada 1 enviada (éxito inmediato)
09:06:49 - GPS obtenido
09:06:50 - Intento 1 → ❌ Error
09:06:55 - Intento 2 → ❌ Error
09:07:00 - Intento 3 → ✅ Éxito
09:07:00 - Alarma reprogramada

Resultado visible en base de datos:
- 08:51:49 ← Envío normal
- 09:07:00 ← Retrasado 11 segundos por reintentos
```

---

## 🎯 Ventajas de los Cambios

### ✅ **1. Sin Duplicados**
- Un solo thread = un solo envío por coordenada
- No más coordenadas con el mismo timestamp

### ✅ **2. Reintentos Controlados**
- Máximo 3 intentos
- 5 segundos fijos entre intentos
- Fácil de predecir el tiempo total

### ✅ **3. Coordenadas Perdidas Claras**
```kotlin
if (!success) {
    Log.w(TAG, "📍 Coordenada PERDIDA (lat=$lat, lon=$lon) después de $maxRetries intentos")
}
```

### ✅ **4. Timeouts Razonables**
- 10 segundos por intento
- No bloquea el servicio por mucho tiempo
- Total máximo: ~40 segundos (3 intentos × 10s + 10s delays)

---

## 📝 Logs Esperados

### **Envío Exitoso (Primer Intento)**
```
🌐 Request (intento 1/3): URL=https://www.riogas.uy/...
📤 Body: {...}
✅ API exitosa (intento 1, 523ms): {"OK":0}
```

### **Reintento Exitoso**
```
🌐 Request (intento 1/3): URL=https://www.riogas.uy/...
❌ Error HTTP 500: Internal Server Error (intento 1)
🔄 Reintentando en 5s... (2/3)
✅ API exitosa (intento 2, 1045ms): {"OK":0}
```

### **Coordenada Perdida**
```
🌐 Request (intento 1/3): URL=https://www.riogas.uy/...
❌ Error de conexión: timeout (intento 1)
🔄 Reintentando conexión en 5s... (2/3)
❌ Error de conexión: timeout (intento 2)
🔄 Reintentando conexión en 5s... (3/3)
❌ Error de conexión: timeout (intento 3)
💥 Máximo de reintentos alcanzado (3 intentos)
📍 Coordenada PERDIDA (lat=-34.xxx, lon=-56.xxx) después de 3 intentos
```

---

## 🧪 Cómo Verificar

### **Test 1: Envíos Normales**
```powershell
adb logcat | Select-String -Pattern "API exitosa|Coordenada PERDIDA"
```

**Esperado:** Solo "API exitosa" en la mayoría de los casos

### **Test 2: Verificar Timestamps en Base de Datos**
```sql
SELECT FechaHora, Latitud, Longitud 
FROM Coordenadas 
WHERE movil = X 
ORDER BY FechaHora DESC 
LIMIT 10
```

**Esperado:** 
- Timestamps separados por ~15 minutos
- Si hay retraso de ~5-10 segundos = hubo reintentos
- NO debe haber timestamps duplicados

### **Test 3: Monitorear Reintentos**
```powershell
adb logcat | Select-String -Pattern "Reintentando|Máximo de reintentos"
```

**Esperado:** 
- Ver "Reintentando en 5s" si hay problemas de red
- Ver "Máximo de reintentos" solo en casos extremos

---

## 📊 Comparación: Antes vs Después

| Aspecto | ❌ Antes | ✅ Después |
|---------|----------|-----------|
| **Ejecución** | Threads paralelos | Thread único secuencial |
| **Duplicados** | Sí (3 al mismo tiempo) | No (imposible) |
| **Delay entre reintentos** | 1s, 2s, 4s (exponencial) | 5s fijo |
| **Timeout por intento** | 15-30s | 10s |
| **Tiempo máximo** | ~60s | ~40s |
| **Coordenadas perdidas** | Silencioso | Log explícito |
| **Predecibilidad** | Baja (timestamps variables) | Alta (delays fijos) |

---

## ⚠️ Consideraciones

### **1. Coordenadas Perdidas**
Si hay problemas de red/servidor prolongados, las coordenadas **se perderán** después de 3 intentos.

**Solución futura:** Implementar cola persistente (SQLite) para reenviar después.

### **2. Retraso Visible**
Si hay reintentos, verás timestamps con 5-10 segundos de retraso en la base de datos.

**Esto es NORMAL y esperado** - indica que hubo problemas temporales pero se resolvieron.

### **3. Bloqueo del Thread**
El thread de envío puede bloquearse hasta ~40 segundos en el peor caso (3 intentos fallidos).

**No afecta** al servicio principal ni a la próxima alarma.

---

## 🚀 Para Compilar e Instalar

```powershell
# Compilar
flutter build apk --debug

# Instalar (si tienes dispositivo conectado)
flutter install --debug

# O instalar manualmente el APK
# Archivo: build\app\outputs\flutter-apk\app-debug.apk
```

---

## ✅ Resumen de Cambios

**Archivo:** `LocationHelper.kt`

**Cambios:**
1. ✅ Reintentos secuenciales en UN SOLO thread
2. ✅ Delay fijo de 5 segundos entre reintentos
3. ✅ Timeouts reducidos de 15s → 10s
4. ✅ Log explícito de coordenadas perdidas
5. ✅ Eliminada función `calculateRetryDelay()` (ya no se usa)

**Resultado:**
- ✅ Sin duplicados
- ✅ Timestamps predecibles
- ✅ Máximo 3 intentos en ~40 segundos
- ✅ Coordenadas perdidas después de fallar 3 veces

---

**Fecha de implementación:** 10 de octubre de 2025
**Versión:** Reintentos Secuenciales v1.0
