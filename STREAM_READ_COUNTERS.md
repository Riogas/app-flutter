# StreamManager - Contador de Lecturas de Firestore

## Nuevas Funcionalidades Agregadas

El `StreamManager` ahora incluye contadores detallados de lecturas por cada tipo de stream para monitorear exactamente cuántas veces Firestore envía datos.

## 📊 Contadores de Lecturas

### Logs Automáticos

Cada vez que un stream recibe datos, verás logs como estos:

```
📖 StreamManager: Pedidos read #1 (5 documents)
📖 StreamManager: Mensajes read #3 (2 documents)
📖 StreamManager: Movil read #7 (document exists)
📖 StreamManager: Sesiones read #2 (data received)
📖 StreamManager: SubEstados read #1 (8 items)
```

### Resumen al Cerrar Streams

Cuando un stream se cierra, verás un resumen total:

```
🧹 StreamManager: Cleaning up Pedidos stream (no more listeners)
📊 StreamManager: Pedidos total reads: 12
```

## 🛠️ Métodos de Utilidad

### 1. Obtener Contadores Actuales

```dart
final streamManager = StreamManager();
final readCounters = streamManager.getReadCounters();
print('Lecturas de Pedidos: ${readCounters['pedidos']}');
print('Lecturas de Mensajes: ${readCounters['mensajes']}');
```

### 2. Imprimir Resumen Completo

```dart
streamManager.printReadSummary();
```

Salida esperada:

```
📊 StreamManager Read Summary:
  📖 Pedidos: 12 reads
  📖 Mensajes: 8 reads
  📖 Movil: 15 reads
  📖 Sesiones: 3 reads
  📖 SubEstados: 2 reads
  📖 Total: 40 reads
```

### 3. Resetear Contadores (Para Testing)

```dart
streamManager.resetReadCounters();
```

### 4. Información Completa de Debug

```dart
final debugInfo = streamManager.getDebugInfo();
print('Listeners activos: ${debugInfo['listeners']}');
print('Lecturas por stream: ${debugInfo['reads']}');
print('Streams activos: ${debugInfo['activeStreams']}');
```

## 📈 Interpretación de los Datos

### Qué Indican los Contadores

- **Lectura por Stream**: Cada vez que Firestore envía datos (cambios detectados)
- **Alto número de lecturas**: Puede indicar datos que cambian frecuentemente
- **Lecturas consistentes**: Datos estables, solo actualizaciones necesarias

### Ejemplos de Interpretación

#### Escenario Normal ✅

```
📖 Pedidos: 5 reads    (Pocos pedidos nuevos durante el día)
📖 Mensajes: 2 reads   (Mensajes ocasionales)
📖 Movil: 10 reads     (Estado del móvil actualizado regularmente)
```

#### Posible Problema ⚠️

```
📖 Pedidos: 150 reads  (Demasiadas actualizaciones, posible problema)
📖 Mensajes: 200 reads (Stream muy activo, verificar lógica)
```

## 🎯 Uso Recomendado

### Para Monitoreo Diario

```dart
// Al final del día o sesión de trabajo
streamManager.printReadSummary();
```

### Para Debugging

```dart
// Resetear al inicio de una sesión de debug
streamManager.resetReadCounters();

// ... usar la app normalmente ...

// Verificar después de operaciones específicas
final counters = streamManager.getReadCounters();
if (counters['pedidos']! > 50) {
  print('⚠️ Demasiadas lecturas de Pedidos: ${counters['pedidos']}');
}
```

### Para Optimización

```dart
// Verificar qué streams son más activos
final debugInfo = streamManager.getDebugInfo();
final reads = debugInfo['reads'] as Map<String, int>;

// Identificar el stream más activo
var maxReads = 0;
var maxStream = '';
reads.forEach((stream, count) {
  if (count > maxReads) {
    maxReads = count;
    maxStream = stream;
  }
});

print('Stream más activo: $maxStream con $maxReads lecturas');
```

## 🔍 Comparación Antes vs Después

### Antes de la Optimización

Con múltiples suscripciones duplicadas, cada lectura se multiplicaba:

```
Stream Pedidos:
- HomePage: 1 lectura
- PendingOrdersPage: 1 lectura
- MapPage: 1 lectura
- Direct Firestore: 1 lectura
= 4 lecturas por cada cambio de datos
```

### Después de la Optimización

Con StreamManager, solo una lectura es compartida:

```
Stream Pedidos:
- StreamManager: 1 lectura
- Compartida entre todas las páginas
= 1 lectura por cada cambio de datos
```

## 📋 Checklist de Monitoreo

- [ ] Verificar que los contadores aumenten gradualmente
- [ ] Comprobar que no hay picos excesivos de lecturas
- [ ] Usar `printReadSummary()` al final de sesiones largas
- [ ] Comparar contadores antes/después de optimizaciones
- [ ] Resetear contadores para testing específico

---

Con estos contadores podrás tener un control preciso sobre cuántas lecturas de Firestore está realizando tu app y optimizar aún más el consumo de datos.
