# Script de Monitoreo GPS - Logs en Tiempo Real con Colores
# Ejecutar: .\monitor-gps-logs.ps1

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "🔍 Monitor GPS - Optimizaciones" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Verificar dispositivo conectado
Write-Host "📱 Verificando dispositivo conectado..." -ForegroundColor Yellow
$devices = adb devices
if ($devices -match "device$") {
    Write-Host "✅ Dispositivo detectado" -ForegroundColor Green
} else {
    Write-Host "❌ No hay dispositivos conectados" -ForegroundColor Red
    Write-Host "Conecta tu dispositivo y ejecuta: adb devices" -ForegroundColor Yellow
    exit
}

Write-Host ""
Write-Host "🧹 Limpiando buffer de logs..." -ForegroundColor Yellow
adb logcat -c
Start-Sleep -Milliseconds 500

Write-Host "✅ Listo. Monitoreando logs GPS..." -ForegroundColor Green
Write-Host ""
Write-Host "Presiona Ctrl+C para detener" -ForegroundColor Gray
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Contador de eventos
$ubicacionesRecibidas = 0
$alarmasDisparadas = 0
$enviosExitosos = 0

try {
    adb logcat | ForEach-Object {
        $line = $_
        
        # Filtrar solo logs relevantes
        if ($line -match "LocationHelper|LocationService|LocationReceiver|ForegroundLocationService") {
            
            # Logs de ÉXITO (Verde)
            if ($line -match "✅|Ubicación ACTUAL recibida|API invocada exitosamente|LocationListener removido correctamente") {
                Write-Host $line -ForegroundColor Green
                
                if ($line -match "Ubicación ACTUAL recibida") {
                    $ubicacionesRecibidas++
                }
                if ($line -match "API invocada exitosamente") {
                    $enviosExitosos++
                }
            }
            
            # Logs de UBICACIÓN (Cyan)
            elseif ($line -match "📍|📌|Coordenadas:|Solicitando ubicación ACTUAL") {
                Write-Host $line -ForegroundColor Cyan
            }
            
            # Logs de ALARMAS (Magenta)
            elseif ($line -match "🔁|⏰|AlarmManager|Reprogramando|disparado") {
                Write-Host $line -ForegroundColor Magenta
                
                if ($line -match "AlarmManager disparado") {
                    $alarmasDisparadas++
                }
            }
            
            # Logs de CLEANUP (Blue)
            elseif ($line -match "🧹|LocationListener removido") {
                Write-Host $line -ForegroundColor Blue
            }
            
            # Logs de CACHÉ (DarkGray)
            elseif ($line -match "💾|guardada en caché") {
                Write-Host $line -ForegroundColor DarkGray
            }
            
            # Logs de SERVIDOR (White)
            elseif ($line -match "🌐|Request|Body:|📤") {
                Write-Host $line -ForegroundColor White
            }
            
            # Logs de WARNINGS (Yellow)
            elseif ($line -match "⚠️|⏱️|Timeout|última conocida|No se pudo") {
                Write-Host $line -ForegroundColor Yellow
            }
            
            # Logs de ERRORES (Red)
            elseif ($line -match "❌|🚫|Error|error|ERROR|Exception") {
                Write-Host $line -ForegroundColor Red
            }
            
            # Logs de INICIO (Green claro)
            elseif ($line -match "🟢|Servicio iniciado|Parámetros recibidos") {
                Write-Host $line -ForegroundColor Green
            }
            
            # Otros logs relevantes (Gray)
            else {
                Write-Host $line -ForegroundColor Gray
            }
            
            # Mostrar estadísticas cada 10 eventos
            $totalEventos = $ubicacionesRecibidas + $alarmasDisparadas + $enviosExitosos
            if ($totalEventos % 10 -eq 0 -and $totalEventos -gt 0) {
                Write-Host ""
                Write-Host "📊 Estadísticas:" -ForegroundColor Cyan
                Write-Host "   📍 Ubicaciones recibidas: $ubicacionesRecibidas" -ForegroundColor Green
                Write-Host "   ⏰ Alarmas disparadas: $alarmasDisparadas" -ForegroundColor Magenta
                Write-Host "   ✅ Envíos exitosos: $enviosExitosos" -ForegroundColor Green
                Write-Host ""
            }
        }
    }
} catch {
    Write-Host ""
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "📊 Resumen Final:" -ForegroundColor Cyan
    Write-Host "   📍 Ubicaciones recibidas: $ubicacionesRecibidas" -ForegroundColor Green
    Write-Host "   ⏰ Alarmas disparadas: $alarmasDisparadas" -ForegroundColor Magenta
    Write-Host "   ✅ Envíos exitosos: $enviosExitosos" -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Cyan
}
