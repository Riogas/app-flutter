# 🔍 Script de Monitoreo de GPS Service Manager
# Guarda este archivo como: monitor-gps-service-manager.ps1
# Uso: .\monitor-gps-service-manager.ps1

Write-Host "🔍 Iniciando monitoreo del GPS Service Manager..." -ForegroundColor Cyan
Write-Host "📱 Dispositivo conectado:" -ForegroundColor Yellow
adb devices
Write-Host ""
Write-Host "🐞 Filtrando logs con tag: [GPS_SERVICE_MANAGER]" -ForegroundColor Green
Write-Host "💡 Presiona Ctrl+C para detener" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor DarkGray
Write-Host ""

# Limpiar logcat antes de empezar
adb logcat -c

# Colores para diferentes tipos de mensajes
$colors = @{
    "📥" = "Cyan"        # Solicitud recibida
    "✅" = "Green"       # Éxito
    "❌" = "Red"         # Error
    "⚠️" = "Yellow"      # Advertencia
    "🚨" = "Magenta"     # Circuit breaker
    "🛑" = "Red"         # Force stop
    "🔍" = "Blue"        # Verificación
    "⏱️" = "Yellow"      # Rate limiting
    "⏭️" = "DarkYellow"  # Omitido
    "💾" = "Gray"        # Guardado
}

# Función para colorear logs según emoji
function Write-ColoredLog {
    param($line)
    
    $colored = $false
    foreach ($emoji in $colors.Keys) {
        if ($line -match [regex]::Escape($emoji)) {
            Write-Host $line -ForegroundColor $colors[$emoji]
            $colored = $true
            break
        }
    }
    
    if (-not $colored) {
        Write-Host $line
    }
}

# Monitorear logs en tiempo real
adb logcat | ForEach-Object {
    if ($_ -match "GPS_SERVICE_MANAGER|forceStopGpsService") {
        $timestamp = Get-Date -Format "HH:mm:ss.fff"
        $logLine = "[$timestamp] $_"
        Write-ColoredLog $logLine
    }
}
