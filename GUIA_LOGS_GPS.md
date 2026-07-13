# 🔍 Guía de Logs - GPS Optimizado

## 📱 Logs Principales que Deberías Ver

### ✅ **1. Inicio del Servicio**
```
🟢 Servicio iniciado
📦 Parámetros recibidos: movil=123, escenario=456, usuario=Juan, deviceId=ABC123
📱 Estado de la aplicación: active
```

### ✅ **2. Solicitud de Ubicación en Tiempo Real**
```
🔄 Solicitando ubicación ACTUAL desde gps...
```
Este log indica que el sistema está pidiendo una ubicación **fresca** del GPS (no caché).

### ✅ **3. Ubicación Recibida**
```
✅ Ubicación ACTUAL recibida de gps
📍 Ubicación obtenida de gps
💾 Ubicación guardada en caché para fallback
📌 Coordenadas: lat=-34.1234567, lon=-56.1234567, utmX=1234.56, utmY=5678.90, velocidad=2.5m/s, distancia total=1234.5m
```

### ✅ **4. Cleanup de Listener**
```
🧹 LocationListener removido correctamente
```
Este log confirma que no hay memory leaks.

### ✅ **5. Filtrado de Distancia**
```
📏 Distancia bruta: 15.2m → Filtrada: 12.5m → Total: 1234.5m
```
o
```
🔇 Distancia descartada por filtro de ruido: 2.1m (velocidad: 0.1m/s)
```

### ✅ **6. Envío al Servidor**
```
🌐 Request (intento 1/3): URL=https://www.riogas.uy/ica_geos_/appservices/RegistrarCoordenadasV2
📤 Body: {"token":"IcA.FwL.1710.!","movil":123,...}
✅ API invocada exitosamente (intento 1): {...}
```

### ✅ **7. Alarmas Exactas**
```
🔁 AlarmManager EXACTO (API 23+) configurado para 15 min (movil=123)
```

### ✅ **8. Reprogramación Automática**
```
⏰ AlarmManager disparado
🔄 Reprogramando siguiente alarma en 15 min
🔄 Reprogramando siguiente alarma para 15 min
```

### ⚠️ **9. Warnings (Esperados en Algunos Casos)**
```
⏱️ Timeout esperando ubicación actual (15s)
⚠️ No se obtuvo ubicación actual, intentando última conocida...
⏰ Usando ubicación de caché (25s de antigüedad)
```

### ❌ **10. Errores (Solo si hay problemas)**
```
🚫 Sin permisos de ubicación (ni FINE ni COARSE). Intentando IP o datos previos...
❌ Error HTTP 500: Internal Server Error
❌ Error de conexión: timeout
```

---

## 🔍 Comandos para Filtrar Logs

### **Opción 1: Ver TODO (Recomendado para primera vez)**
```powershell
adb logcat -c; adb logcat | Select-String -Pattern "LocationHelper|LocationService|LocationReceiver|LocationWorker"
```

### **Opción 2: Solo Logs Importantes (Emojis + Palabras Clave)**
```powershell
adb logcat | Select-String -Pattern "📍|🔄|✅|🔁|⏰|🧹|💾|🌐|📤"
```

### **Opción 3: Solo Coordenadas GPS**
```powershell
adb logcat | Select-String -Pattern "Ubicación ACTUAL|Coordenadas:|📍|📌"
```

### **Opción 4: Solo Alarmas y Reprogramación**
```powershell
adb logcat | Select-String -Pattern "AlarmManager|Reprogramando|⏰|🔁|🔄"
```

### **Opción 5: Solo Errores y Warnings**
```powershell
adb logcat *:E | Select-String -Pattern "LocationHelper|LocationService|LocationReceiver"
```

### **Opción 6: Filtro por TAG específico**
```powershell
adb logcat LocationHelper:V LocationService:V LocationReceiver:V *:S
```

### **Opción 7: Guardar logs en archivo para análisis**
```powershell
adb logcat -c
adb logcat | Select-String -Pattern "LocationHelper|LocationService|LocationReceiver" | Tee-Object -FilePath "gps_logs.txt"
```

---

## 📊 Frecuencia de Logs Esperada

| Evento | Frecuencia | Log |
|--------|-----------|-----|
| **Solicitud GPS** | Cada X min (según configuración) | `🔄 Solicitando ubicación ACTUAL` |
| **GPS recibido** | Cada X min | `✅ Ubicación ACTUAL recibida` |
| **Cleanup listener** | Cada X min | `🧹 LocationListener removido` |
| **Envío al servidor** | Cada X min | `✅ API invocada exitosamente` |
| **Alarma disparada** | Cada X min | `⏰ AlarmManager disparado` |
| **Reprogramación** | Cada X min | `🔄 Reprogramando siguiente alarma` |
| **Filtrado distancia** | Solo cuando te mueves | `📏 Distancia bruta: ... → Filtrada:` |

---

## 🧪 Test Práctico: Qué Deberías Ver Ahora

### **Escenario 1: Primera ejecución (Login)**
```
🟢 Servicio iniciado
📦 Parámetros recibidos: movil=123, escenario=456, usuario=Juan, deviceId=ABC123
🔄 Solicitando ubicación ACTUAL desde gps...
✅ Ubicación ACTUAL recibida de gps
💾 Ubicación guardada en caché para fallback
📌 Coordenadas: lat=-34.xxx, lon=-56.xxx, ...
🧹 LocationListener removido correctamente
🌐 Request (intento 1/3): URL=...
✅ API invocada exitosamente
🔁 AlarmManager EXACTO (API 23+) configurado para 15 min
```

### **Escenario 2: Alarma periódica (cada X minutos)**
```
⏰ AlarmManager disparado
📱 Estado de la aplicación: background
🔄 Solicitando ubicación ACTUAL desde gps...
✅ Ubicación ACTUAL recibida de gps
💾 Ubicación guardada en caché para fallback
📏 Distancia bruta: 15.2m → Filtrada: 12.5m → Total: 1234.5m
📌 Coordenadas: lat=-34.yyy, lon=-56.yyy, ...  ← DIFERENTES a las anteriores ✅
🧹 LocationListener removido correctamente
🌐 Request (intento 1/3): URL=...
✅ API invocada exitosamente
🔄 Reprogramando siguiente alarma en 15 min
🔁 AlarmManager EXACTO (API 23+) configurado para 15 min
```

### **Escenario 3: GPS lento (interiores)**
```
🔄 Solicitando ubicación ACTUAL desde gps...
⏱️ Timeout esperando ubicación actual (15s)  ← Esperó 15 segundos
⚠️ No se obtuvo ubicación actual, intentando última conocida...
⏰ Usando ubicación de caché (25s de antigüedad)
💾 Ubicación guardada en caché para fallback
📌 Coordenadas: lat=-34.zzz, lon=-56.zzz, ...
🧹 LocationListener removido correctamente
```

---

## ⚠️ Si NO Ves Estos Logs

### **Problema 1: No ves NINGÚN log**
```powershell
# Verificar que el dispositivo esté conectado
adb devices

# Verificar que la app esté instalada
adb shell pm list packages | Select-String moveit

# Reiniciar logcat
adb logcat -c
adb logcat
```

### **Problema 2: Ves logs VIEJOS (caché)**
```powershell
# Limpiar buffer de logcat
adb logcat -c

# Reiniciar la app
adb shell am force-stop com.example.moveit
adb shell am start -n com.example.moveit/.MainActivity
```

### **Problema 3: Logs muy rápidos (se pierden)**
```powershell
# Aumentar tamaño del buffer
adb logcat -G 16M

# Guardar en archivo
adb logcat | Tee-Object -FilePath "full_logs.txt"
```

---

## 🎯 Logs Clave para Validar Optimizaciones

### ✅ **Ubicación en Tiempo Real**
Busca: `✅ Ubicación ACTUAL recibida`
- Si lo ves: GPS está obteniendo ubicación fresca ✅
- Si NO lo ves: GPS puede estar usando caché viejo ❌

### ✅ **Alarmas Exactas**
Busca: `🔁 AlarmManager EXACTO (API 23+)`
- Si lo ves: Alarmas exactas activadas ✅
- Si ves `setRepeating`: Alarmas inexactas (código viejo) ❌

### ✅ **Reprogramación**
Busca: `🔄 Reprogramando siguiente alarma`
- Si lo ves cada X min: Reprogramación funciona ✅
- Si NO lo ves: Alarmas pueden no repetirse ❌

### ✅ **Cleanup**
Busca: `🧹 LocationListener removido`
- Si lo ves siempre: No hay memory leaks ✅
- Si NO lo ves: Possible memory leak ❌

### ✅ **Coordenadas Diferentes**
Compara: `📌 Coordenadas: lat=-34.xxx` entre envíos
- Si cambian cuando te mueves: ✅ RESUELTO
- Si son idénticas: ❌ Todavía usando caché

---

## 📋 Checklist de Validación

Ejecuta esto y marca lo que ves:

```powershell
# 1. Limpiar logs
adb logcat -c

# 2. Hacer login en la app (inicia servicio)

# 3. Ver logs en tiempo real
adb logcat | Select-String -Pattern "📍|🔄|✅|🔁|⏰|🧹"
```

**Marca lo que VES:**
- [ ] `🔄 Solicitando ubicación ACTUAL desde gps...`
- [ ] `✅ Ubicación ACTUAL recibida de gps`
- [ ] `💾 Ubicación guardada en caché para fallback`
- [ ] `📌 Coordenadas: lat=...`
- [ ] `🧹 LocationListener removido correctamente`
- [ ] `✅ API invocada exitosamente`
- [ ] `🔁 AlarmManager EXACTO (API 23+) configurado`

**Si marcaste TODOS:** Las optimizaciones están funcionando ✅

**Si falta alguno:** Hay un problema, comparte los logs que SÍ ves.

---

## 💡 Tip: Configurar Filtro Permanente

Crea un archivo `gps-logs.ps1`:

```powershell
# gps-logs.ps1
adb logcat -c
Write-Host "🔍 Monitoreando logs GPS..." -ForegroundColor Green
adb logcat | Select-String -Pattern "LocationHelper|LocationService|LocationReceiver|📍|🔄|✅|🔁|⏰|🧹|💾|🌐" | ForEach-Object {
    $line = $_.Line
    if ($line -match "✅|📍|💾") {
        Write-Host $line -ForegroundColor Green
    } elseif ($line -match "⚠️|⏱️") {
        Write-Host $line -ForegroundColor Yellow
    } elseif ($line -match "❌|🚫") {
        Write-Host $line -ForegroundColor Red
    } else {
        Write-Host $line
    }
}
```

Ejecuta:
```powershell
.\gps-logs.ps1
```

---

**¿Qué logs específicos quieres ver? ¿O cuál NO estás viendo que esperabas?** 🔍
