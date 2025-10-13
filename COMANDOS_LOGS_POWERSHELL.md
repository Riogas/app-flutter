# 📱 Comandos PowerShell para Monitorear Logs GPS

## 🎯 Comandos Básicos (Copiar y Pegar en PowerShell)

### 1️⃣ Ver TODOS los logs de GPS en tiempo real
```powershell
adb logcat | Select-String -Pattern "LocationHelper|LocationService|LocationReceiver"
```

### 2️⃣ Ver SOLO ubicaciones GPS recibidas
```powershell
adb logcat | Select-String -Pattern "Ubicación ACTUAL recibida|Coordenadas:"
```

### 3️⃣ Ver SOLO alarmas y reprogramación
```powershell
adb logcat | Select-String -Pattern "AlarmManager|Reprogramando|Alarma"
```

### 4️⃣ Ver SOLO errores y warnings
```powershell
adb logcat | Select-String -Pattern "❌|⚠️" | Select-String -Pattern "Location"
```

### 5️⃣ Ver TODO con emojis (más visual)
```powershell
adb logcat | Select-String -Pattern "🔄|✅|📍|💾|🧹|🔁|⏰|❌|⚠️|📏"
```

### 6️⃣ Ver distancia recorrida
```powershell
adb logcat | Select-String -Pattern "Distancia.*Total|📏"
```

### 7️⃣ Ver cleanup de listeners
```powershell
adb logcat | Select-String -Pattern "LocationListener removido|🧹"
```

### 8️⃣ Ver estado del servicio
```powershell
adb logcat | Select-String -Pattern "Servicio iniciado|Servicio.*detenido|🟢|🛑"
```

---

## 🚀 Script Completo con Colores

Si quieres ver logs con colores, ejecuta:

```powershell
.\monitor-gps-logs.ps1
```

Si no existe, créalo con este contenido:

```powershell
# Limpiar buffer
adb logcat -c

# Monitorear en tiempo real
adb logcat | ForEach-Object {
    $line = $_
    
    if ($line -match "✅.*Ubicación ACTUAL") {
        Write-Host $line -ForegroundColor Green
    }
    elseif ($line -match "📍.*Coordenadas") {
        Write-Host $line -ForegroundColor Cyan
    }
    elseif ($line -match "🔁.*AlarmManager.*EXACTO") {
        Write-Host $line -ForegroundColor Magenta
    }
    elseif ($line -match "🔄.*Reprogramando") {
        Write-Host $line -ForegroundColor Yellow
    }
    elseif ($line -match "❌") {
        Write-Host $line -ForegroundColor Red
    }
    elseif ($line -match "LocationHelper|LocationService") {
        Write-Host $line -ForegroundColor Gray
    }
}
```

---

## 🔍 Filtros Útiles Combinados

### Ver secuencia completa de obtención de GPS
```powershell
adb logcat | Select-String -Pattern "Solicitando ubicación|Ubicación ACTUAL recibida|Coordenadas:|guardada en caché|LocationListener removido"
```

### Ver secuencia completa de alarma
```powershell
adb logcat | Select-String -Pattern "AlarmManager disparado|Servicio iniciado|Reprogramando siguiente alarma|AlarmManager EXACTO"
```

### Ver problemas (timeouts, errores, warnings)
```powershell
adb logcat | Select-String -Pattern "Timeout|Error|⚠️|❌" | Select-String -Pattern "Location"
```

---

## 📊 Ver Estadísticas Rápidas

### Contar ubicaciones recibidas
```powershell
adb logcat -d | Select-String -Pattern "Ubicación ACTUAL recibida" | Measure-Object | Select-Object -ExpandProperty Count
```

### Contar alarmas programadas
```powershell
adb logcat -d | Select-String -Pattern "AlarmManager EXACTO configurado" | Measure-Object | Select-Object -ExpandProperty Count
```

### Contar errores
```powershell
adb logcat -d | Select-String -Pattern "❌" | Select-String -Pattern "Location" | Measure-Object | Select-Object -ExpandProperty Count
```

---

## 🎯 Comandos Más Usados

### Comando Recomendado #1: Monitor General
```powershell
adb logcat | Select-String -Pattern "🔄|✅|📍|🔁|❌"
```

### Comando Recomendado #2: Solo Éxitos
```powershell
adb logcat | Select-String -Pattern "✅|📍" | Select-String -Pattern "Location"
```

### Comando Recomendado #3: Solo Problemas
```powershell
adb logcat | Select-String -Pattern "❌|⚠️|Timeout|Error" | Select-String -Pattern "Location"
```

---

## 💡 Tip: Guardar Logs en Archivo

```powershell
# Guardar 5 minutos de logs
adb logcat | Select-String -Pattern "Location" | Tee-Object -FilePath "gps-logs.txt"
```

Presiona Ctrl+C después de 5 minutos para detener.

---

## 🧪 Secuencia Esperada (Flujo Normal)

Cuando todo funciona correctamente, deberías ver esta secuencia cada X minutos:

```
1. ⏰ AlarmManager disparado
2. 🟢 Servicio iniciado
3. 🔄 Solicitando ubicación ACTUAL desde gps...
4. ✅ Ubicación ACTUAL recibida de gps
5. 📍 Coordenadas: lat=-34.xxx, lon=-56.xxx
6. 💾 Ubicación guardada en caché para fallback
7. 🧹 LocationListener removido correctamente
8. 📏 Distancia filtrada: XXXm → Total: YYYm
9. ✅ API invocada exitosamente
10. 🔄 Reprogramando siguiente alarma en 15 min
11. 🔁 AlarmManager EXACTO (API 23+) configurado para 15 min
```

Si ves esta secuencia repetirse, **TODO ESTÁ FUNCIONANDO CORRECTAMENTE**. ✅

---

## ⚠️ Problemas Comunes

### Si NO ves logs:
```powershell
# Verificar que el dispositivo esté conectado
adb devices

# Verificar que la app esté instalada
adb shell pm list packages | Select-String -Pattern "moveit"
```

### Si ves demasiados logs:
```powershell
# Filtrar solo tu app
adb logcat | Select-String -Pattern "com.example.moveit"
```

---

**Tip:** Abre PowerShell como Administrador para mejor rendimiento.
