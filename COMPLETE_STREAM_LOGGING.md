# StreamManager - Logging y Debugging Completo 📊

## 🆕 Nuevas Funcionalidades Agregadas

Ahora el StreamManager incluye **TODOS** los streams disponibles en tu app con logging detallado y diagnósticos avanzados.

## 📋 Streams Monitoreados

### 1. **Streams Principales**
- ✅ **Pedidos** - Órdenes/pedidos del día
- ✅ **Mensajes** - Mensajes para el móvil  
- ✅ **Movil** - Estado del móvil/vehículo
- ✅ **Sesiones** - Información de sesión de usuario

### 2. **Streams de Sub-Estados** (NUEVOS)
- ✅ **SubEstados** - Sub-estados de finalización de pedidos
- ✅ **SubEstadoMoviles** - Sub-estados específicos de móviles
- ✅ **SubEstadoServices** - Sub-estados de servicios de finalización

## 🔍 Logs Detallados por Stream

### Logs de Creación
```
🔄 StreamManager: Created new Pedidos broadcast stream
🔄 StreamManager: Created new Mensajes broadcast stream
🔄 StreamManager: Created new Movil broadcast stream
🔄 StreamManager: Created new Sesiones broadcast stream
🔄 StreamManager: Created new SubEstados broadcast stream
🔄 StreamManager: Created new SubEstadoMoviles broadcast stream
🔄 StreamManager: Created new SubEstadoServices broadcast stream
```

### Logs de Listeners
```
📊 StreamManager: Pedidos listeners: 1
📊 StreamManager: Mensajes listeners: 2
📊 StreamManager: Movil listeners: 1
```

### Logs de Lecturas MEJORADOS
```
📖 StreamManager: Pedidos read #1
   📦 Documents received: 4
   🕐 Timestamp: 2025-07-10T15:30:45.123Z
   📋 Sample data: pedido-001 ({id: 1, estado: "pendiente"})

📖 StreamManager: Mensajes read #2
   📧 Messages received: 2
   🕐 Timestamp: 2025-07-10T15:30:46.456Z
   📋 Sample message: mensaje-123

📖 StreamManager: Movil read #3
   🚗 Document exists: true
   🕐 Timestamp: 2025-07-10T15:30:47.789Z
   📋 Movil data: {estado: "activo", ubicacion: "..."}

📖 StreamManager: Sesiones read #1
   👤 Session data exists: true
   🕐 Timestamp: 2025-07-10T15:30:48.012Z
   📋 Session keys: [usuario, movil, escenario, timestamp]
```

### Logs de Errores
```
❌ StreamManager: Pedidos error: FirebaseException: Permission denied
❌ StreamManager: SubEstadoMoviles error: NetworkException: Connection timeout
```

## 🛠️ Métodos de Diagnóstico

### 1. **Diagnóstico Completo**
```dart
final streamManager = StreamManager();
streamManager.printStreamDiagnostics();
```

**Output esperado:**
```
🔍 StreamManager Comprehensive Diagnostics:
==================================================
📊 ACTIVE STREAMS SUMMARY:
  🔄 Pedidos: ACTIVE (2 listeners, 5 reads)
  🔄 Mensajes: ACTIVE (1 listeners, 3 reads)
  🔄 Movil: ACTIVE (1 listeners, 7 reads)
  ⭕ Sesiones: INACTIVE
  ⭕ SubEstados: INACTIVE
  ⭕ SubEstadoMoviles: INACTIVE
  ⭕ SubEstadoServices: INACTIVE
==================================================
📈 TOTALS:
  🔄 Active Streams: 3
  👂 Total Listeners: 4
  📖 Total Reads: 15
  🕐 Current Time: 2025-07-10T15:30:50.123Z
==================================================
📊 PERFORMANCE INSIGHTS:
  📊 Average reads per stream: 5.00
  ✅ Read count looks healthy
==================================================
```

### 2. **Resumen de Lecturas**
```dart
streamManager.printReadSummary();
```

**Output:**
```
📊 StreamManager Read Summary:
  📖 Pedidos: 5 reads
  📖 Mensajes: 3 reads
  📖 Movil: 7 reads
  📖 Sesiones: 0 reads
  📖 SubEstados: 0 reads
  📖 SubEstadoMoviles: 0 reads
  📖 SubEstadoServices: 0 reads
  📖 Total: 15 reads
```

### 3. **Información de Debug Programática**
```dart
final debugInfo = streamManager.getDebugInfo();
print('Streams activos: ${debugInfo['activeStreams']}');
print('Listeners por stream: ${debugInfo['listeners']}');
print('Lecturas por stream: ${debugInfo['reads']}');
```

### 4. **Contadores de Lecturas**
```dart
final counters = streamManager.getReadCounters();
print('Lecturas de Pedidos: ${counters['pedidos']}');
print('Lecturas de Mensajes: ${counters['mensajes']}');
```

## 📈 Alertas de Rendimiento

El diagnóstico incluye alertas automáticas:

### ✅ **Saludable** (< 50 lecturas)
```
✅ Read count looks healthy
```

### 🔶 **Moderado** (50-100 lecturas)
```
🔶 Moderate read count - monitor closely
```

### ⚠️ **Alto** (> 100 lecturas)
```
⚠️ High read count detected - consider optimization
```

## 🕐 Logs de Limpieza

Cuando los streams se cierran:
```
🧹 StreamManager: Cleaning up Pedidos stream (no more listeners)
📊 StreamManager: Pedidos total reads: 12

🧹 StreamManager: Cleaning up Mensajes stream (no more listeners)
📊 StreamManager: Mensajes total reads: 8
```

## 🎯 Uso Recomendado para Debugging

### 1. **Al Inicio de Sesión**
```dart
// Resetear contadores para una sesión limpia
streamManager.resetReadCounters();
print('🔄 Empezando nueva sesión de monitoreo');
```

### 2. **Durante Desarrollo**
```dart
// Cada 5 minutos o después de operaciones importantes
Timer.periodic(Duration(minutes: 5), (timer) {
  streamManager.printStreamDiagnostics();
});
```

### 3. **Al Detectar Problemas**
```dart
// Si sospechas problemas de rendimiento
final counters = streamManager.getReadCounters();
counters.forEach((stream, reads) {
  if (reads > 50) {
    print('⚠️ $stream tiene demasiadas lecturas: $reads');
  }
});
```

### 4. **Al Final de Sesión**
```dart
// Antes de cerrar la app o cambiar de usuario
streamManager.printReadSummary();
print('📊 Resumen final de la sesión');
```

## 🔍 Qué Buscar en los Logs

### ✅ **Comportamiento Normal**
- Solo 1 stream de cada tipo se crea
- Listeners aumentan/disminuyen según navegación
- Lecturas aumentan gradualmente
- Cleanup automático cuando no hay listeners

### ⚠️ **Posibles Problemas**
- Múltiples streams del mismo tipo creándose
- Listeners que no disminuyen al salir de páginas
- Lecturas excesivas (> 10 por minuto para un stream)
- Streams que no se limpian automáticamente

### 🚨 **Problemas Críticos**
- Errores repetidos en los logs
- Streams que se crean y destruyen constantemente
- Memoria aumentando sin control
- Más de 100 lecturas por stream en una sesión

## 📋 Checklist de Monitoreo

- [ ] Verificar que solo se crean los streams necesarios
- [ ] Confirmar que listeners se gestionan correctamente
- [ ] Monitorear contadores de lecturas regularmente
- [ ] Usar `printStreamDiagnostics()` para revisiones completas
- [ ] Revisar logs de errores si aparecen
- [ ] Comparar lecturas antes/después de optimizaciones

---

¡Con estos logs detallados tendrás **visibilidad completa** de todos tus streams de Firestore y podrás optimizar el rendimiento de tu app al máximo! 🚀
