# 🎯 Ejemplos de Uso - Sistema de Flags de Servicios

## 📖 Casos de Uso Prácticos

### 1. Enviar Flag en Registros de Coordenadas

```dart
// En location_service.dart o similar
static Future<void> registrarCoordenadas(...) async {
  // Obtener flag de servicios
  bool? servicesNeedRestart = await RioGasService.getServicesNeedRestart();
  
  // Preparar datos para enviar
  final data = {
    'movil': movil,
    'coordenadas': coordenadas,
    'timestamp': DateTime.now().toIso8601String(),
    // 🚩 Agregar flag de servicios
    'services_need_restart': servicesNeedRestart ?? false,
    'services_status_source': 'location_service',
  };
  
  // Enviar al servidor
  await RioGasService.registrarCoordenadas(...);
}
```

### 2. Enviar Flag en Descarga de Pedidos

```dart
// En pending_orders.dart o riogas_service.dart
static Future<Map<String, dynamic>?> descargaPedidos(...) async {
  // Obtener estado completo de servicios
  Map<String, dynamic>? serviceStatus = await RioGasService.getFullServiceStatus();
  
  final requestBody = {
    'token': token,
    'escenarioid': escenarioId,
    'sdtPedidos': sdtPedidos,
    // ... otros datos ...
    
    // 🚩 Agregar información de servicios
    'services_need_restart': serviceStatus?['services_need_restart'] ?? false,
    'gps_service_active': serviceStatus?['gps_service_status'] ?? false,
    'critical_log_active': serviceStatus?['critical_log_status'] ?? false,
    'watchdog_disabled': serviceStatus?['watchdog_disabled'] ?? false,
    'last_service_check': serviceStatus?['last_check_timestamp'],
  };
  
  return _post('DescargaPedidos', requestBody);
}
```

### 3. Monitorear Estado en Tiempo Real

```dart
// Crear un Timer que verifica periódicamente
class ServiceStatusMonitor {
  Timer? _monitorTimer;
  
  void startMonitoring() {
    _monitorTimer = Timer.periodic(Duration(minutes: 1), (timer) async {
      bool? needRestart = await RioGasService.getServicesNeedRestart();
      
      if (needRestart == true) {
        print('⚠️ Servicios necesitan reiniciarse');
        // Mostrar notificación al usuario
        _showServiceWarning();
        
        // Obtener más detalles
        var status = await RioGasService.getFullServiceStatus();
        print('Detalles: $status');
      } else {
        print('✅ Todos los servicios funcionando correctamente');
      }
    });
  }
  
  void stopMonitoring() {
    _monitorTimer?.cancel();
  }
  
  void _showServiceWarning() {
    // Mostrar alerta al usuario
    // ScaffoldMessenger, Dialog, etc.
  }
}
```

### 4. Validar Servicios Antes de Operaciones Críticas

```dart
// Antes de realizar una operación importante
static Future<bool> validarServiciosActivos() async {
  Map<String, dynamic>? status = await RioGasService.getFullServiceStatus();
  
  if (status == null) {
    print('❌ No se pudo obtener estado de servicios');
    return false;
  }
  
  bool gpsActivo = status['gps_service_status'] ?? false;
  bool criticalLogActivo = status['critical_log_status'] ?? false;
  bool watchdogDeshabilitado = status['watchdog_disabled'] ?? false;
  
  if (watchdogDeshabilitado) {
    print('🚫 Watchdog deshabilitado - Servicios detenidos por cierre de sesión');
    return false;
  }
  
  if (!gpsActivo || !criticalLogActivo) {
    print('⚠️ Servicios no están completamente activos');
    print('   GPS: ${gpsActivo ? "✅" : "❌"}');
    print('   CriticalLog: ${criticalLogActivo ? "✅" : "❌"}');
    return false;
  }
  
  print('✅ Todos los servicios activos');
  return true;
}

// Usar antes de operación crítica
if (await validarServiciosActivos()) {
  // Proceder con operación
  await realizarOperacionCritica();
} else {
  // Mostrar mensaje al usuario
  showDialog(...);
}
```

### 5. Logging Detallado con Estado de Servicios

```dart
// Wrapper para logging que incluye estado de servicios
class LoggingHelper {
  static Future<void> logConEstadoServicios(
    String mensaje,
    Map<String, dynamic> datos
  ) async {
    // Obtener estado de servicios
    Map<String, dynamic>? serviceStatus = await RioGasService.getFullServiceStatus();
    
    // Agregar estado de servicios al log
    final logData = {
      ...datos,
      'timestamp': DateTime.now().toIso8601String(),
      'service_status': serviceStatus,
    };
    
    // Enviar log con toda la información
    await _enviarLog(mensaje, logData);
  }
}

// Uso:
await LoggingHelper.logConEstadoServicios(
  'Operación completada',
  {
    'operacion': 'descarga_pedidos',
    'pedidos_count': 15,
    'duracion_ms': 1250,
  }
);
```

### 6. Dashboard de Estado en UI

```dart
// Widget que muestra el estado de servicios
class ServiceStatusWidget extends StatefulWidget {
  @override
  _ServiceStatusWidgetState createState() => _ServiceStatusWidgetState();
}

class _ServiceStatusWidgetState extends State<ServiceStatusWidget> {
  Map<String, dynamic>? _serviceStatus;
  Timer? _refreshTimer;
  
  @override
  void initState() {
    super.initState();
    _loadServiceStatus();
    
    // Refrescar cada 30 segundos
    _refreshTimer = Timer.periodic(Duration(seconds: 30), (_) {
      _loadServiceStatus();
    });
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
  
  Future<void> _loadServiceStatus() async {
    final status = await RioGasService.getFullServiceStatus();
    setState(() {
      _serviceStatus = status;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    if (_serviceStatus == null) {
      return CircularProgressIndicator();
    }
    
    bool needRestart = _serviceStatus!['services_need_restart'] ?? false;
    bool gpsActive = _serviceStatus!['gps_service_status'] ?? false;
    bool logActive = _serviceStatus!['critical_log_status'] ?? false;
    String checkedBy = _serviceStatus!['checked_by'] ?? 'Unknown';
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Estado de Servicios', 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
            ),
            SizedBox(height: 12),
            _buildStatusRow('GPS Service', gpsActive),
            _buildStatusRow('CriticalLog Service', logActive),
            SizedBox(height: 8),
            Text('Verificado por: $checkedBy', 
              style: TextStyle(fontSize: 12, color: Colors.grey)
            ),
            if (needRestart)
              Container(
                margin: EdgeInsets.only(top: 12),
                padding: EdgeInsets.all(8),
                color: Colors.orange.shade100,
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Servicios en reinicio automático'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusRow(String label, bool active) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_circle : Icons.error,
            color: active ? Colors.green : Colors.red,
            size: 20,
          ),
          SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
```

### 7. Integrar con Sistema de Alertas

```dart
class AlertSystem {
  static Timer? _alertTimer;
  static bool _lastServiceStatus = true;
  
  static void startMonitoring() {
    _alertTimer = Timer.periodic(Duration(minutes: 2), (timer) async {
      bool? needRestart = await RioGasService.getServicesNeedRestart();
      
      // Solo alertar cuando cambia de activo a necesita reinicio
      if (needRestart == true && _lastServiceStatus == true) {
        _sendAlert();
      }
      
      _lastServiceStatus = needRestart ?? true;
    });
  }
  
  static Future<void> _sendAlert() async {
    var status = await RioGasService.getFullServiceStatus();
    
    String mensaje = 'Servicios de background requieren atención';
    String detalles = '';
    
    if (status?['gps_service_status'] == false) {
      detalles += 'GPS Service está inactivo. ';
    }
    if (status?['critical_log_status'] == false) {
      detalles += 'CriticalLog Service está inactivo. ';
    }
    
    // Enviar notificación push local
    await LocalNotificationService.show(
      title: mensaje,
      body: detalles + 'El sistema intentará reiniciar automáticamente.',
    );
    
    // O mostrar alerta en UI si app está abierta
    if (navigatorKey.currentContext != null) {
      showDialog(
        context: navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          title: Text('⚠️ Alerta de Servicios'),
          content: Text(mensaje + '\n\n' + detalles),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}
```

### 8. Limpiar Flags al Iniciar Sesión

```dart
// En login_page.dart o similar
Future<void> _onLoginSuccess() async {
  // ... proceso de login ...
  
  // Limpiar todas las flags de servicios
  await RioGasService.clearAllServiceFlags();
  print('🧹 Flags de servicios limpiadas al iniciar sesión');
  
  // Continuar con el flujo normal
  Navigator.pushReplacement(context, ...);
}
```

### 9. Enviar Flag Solo Si Está en True

```dart
// Optimización: solo incluir flag si es relevante
static Future<void> enviarDatos(Map<String, dynamic> datos) async {
  bool? needRestart = await RioGasService.getServicesNeedRestart();
  
  // Solo agregar flag si servicios necesitan reinicio
  if (needRestart == true) {
    datos['services_need_restart'] = true;
    datos['services_alert'] = 'Servicios en proceso de reinicio';
    
    // Obtener más detalles
    var status = await RioGasService.getFullServiceStatus();
    datos['service_details'] = {
      'checked_by': status?['checked_by'],
      'gps_active': status?['gps_service_status'],
      'log_active': status?['critical_log_status'],
    };
  }
  
  await _post('Endpoint', datos);
}
```

### 10. Verificar Antes de Operaciones en Background

```dart
// En un Worker o Background Task
class BackgroundTask {
  static Future<void> ejecutarTarea() async {
    print('🔄 Iniciando tarea en background');
    
    // Verificar que servicios estén activos
    bool? needRestart = await RioGasService.getServicesNeedRestart();
    
    if (needRestart == true) {
      print('⚠️ Servicios no están completamente activos');
      print('⏸️ Esperando a que servicios se recuperen...');
      
      // Esperar un poco y reintentar
      await Future.delayed(Duration(seconds: 45));
      
      // Verificar de nuevo
      needRestart = await RioGasService.getServicesNeedRestart();
      
      if (needRestart == true) {
        print('❌ Servicios aún no activos, abortando tarea');
        return;
      }
    }
    
    print('✅ Servicios activos, ejecutando tarea');
    // Proceder con la tarea...
  }
}
```

## 🎓 Mejores Prácticas

1. **No abusar de las consultas**: La flag se actualiza cada 30 segundos automáticamente, no necesitas consultarla constantemente

2. **Manejar valores null**: Siempre usa el operador `??` para manejar cuando la flag no se pueda obtener

3. **Logging apropiado**: Incluye la flag en logs importantes para debugging

4. **No modificar desde Dart**: Las flags se actualizan automáticamente desde Kotlin, solo léelas desde Dart

5. **Respetar cierre de sesión**: Si `watchdog_disabled=true`, no intentes forzar reinicios desde Dart

## 📊 Ejemplo Completo de Servicio con Flag

```dart
class MiServicio {
  // Enviar datos con información completa de servicios
  static Future<Map<String, dynamic>?> enviarDatosCompletos({
    required String movil,
    required Map<String, dynamic> datos,
  }) async {
    try {
      // Obtener estado completo de servicios
      Map<String, dynamic>? serviceStatus = 
        await RioGasService.getFullServiceStatus();
      
      // Preparar body con toda la información
      final body = {
        'movil': movil,
        'timestamp': DateTime.now().toIso8601String(),
        'datos': datos,
        
        // 🚩 Información de servicios
        'service_monitoring': {
          'need_restart': serviceStatus?['services_need_restart'] ?? false,
          'gps_active': serviceStatus?['gps_service_status'] ?? false,
          'log_active': serviceStatus?['critical_log_status'] ?? false,
          'watchdog_disabled': serviceStatus?['watchdog_disabled'] ?? false,
          'last_check': serviceStatus?['last_check_timestamp'],
          'checked_by': serviceStatus?['checked_by'] ?? 'Unknown',
          'check_reason': serviceStatus?['check_reason'] ?? '',
        },
      };
      
      // Enviar al servidor
      final response = await RioGasService._post('MiEndpoint', body);
      
      return response;
      
    } catch (e) {
      print('❌ Error enviando datos: $e');
      return null;
    }
  }
}
```

---

**Nota**: Estos son ejemplos de cómo USAR la flag desde Dart. Recuerda que NO debes modificar ningún servicio existente a menos que sea específicamente necesario. La flag está disponible para cuando la necesites usar.
