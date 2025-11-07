import 'package:MoveIT/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_service.dart';
import '../services/persistent_stream_manager.dart';
import 'package:hive/hive.dart';
import '../services/riogas_service.dart';
import 'package:url_launcher/url_launcher.dart'; // Importa para manejar URLs
import 'package:MoveIT/pages/home_page.dart';
import '../utils/screenBlock.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../utils/constantes.dart';
import 'dart:io' show Platform;
import 'package:screen_protector/screen_protector.dart';
import '../services/debug_config_manager.dart'; // 🆕 Debug logging

class OrderDetailPage extends StatefulWidget {
  final String detalleHtml;
  final int estadoNro;
  final double totalPedido; // Add this parameter
  final int codPedido;
  final String pedidoTipo;
  final GeoPoint? ubicacion;

  OrderDetailPage({
    required this.detalleHtml,
    required this.estadoNro,
    required this.totalPedido, // Initialize it
    required this.codPedido,
    required this.pedidoTipo,
    this.ubicacion,
  });

  @override
  _OrderDetailPageState createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  late final WebViewController _controller;
  final FirebaseService _firebaseService = FirebaseService();
  final PersistentStreamManager _persistentStreamManager =
      PersistentStreamManager();
  // ValueNotifier para subestados de finalización de pedidos
  ValueNotifier<List<Map<String, dynamic>>>
      get _subEstadosFinalizacionNotifier =>
          _persistentStreamManager.subEstadoFinalizacionPedidosNotifier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Imprime los subestados de finalización cada vez que cambian
    _subEstadosFinalizacionNotifier.addListener(() {
      final subestados = _subEstadosFinalizacionNotifier.value;
      print('Subestados de finalización encontrados:');
      for (var sub in subestados) {
        print(sub);
      }
    });
  }

  // Ya no se necesita _subEstados, se usará el ValueNotifier
  String? _selectedSubEstado;
  String? _observaciones = '';
  final _observacionesController = TextEditingController();

  int? _distanciaMaxMtsCumpPedidos; // Variable para guardar el valor del stream
  Stream<DocumentSnapshot?>? _movilStream;
  StreamSubscription<DocumentSnapshot?>? _movilSubscription;

  // ✅ Flag para prevenir múltiples llamadas simultáneas de finalización
  bool _isFinalizing = false;

  VoidCallback? _movilShieldListener; // para remover listener

  @override
  void initState() {
    super.initState();

    // ✅ Bloquear capturas (FLAG_SECURE) controlado por printScreen (solo Android)
    _enableScreenShield();

    // 🆕 Verificar y reiniciar servicio de coordenadas si está muerto
    _checkAndRestartLocationService();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) async {
            final url = request.url;

            if (url.startsWith("https://waze.com/ul")) {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            } else if (url.startsWith("https://www.google.com/maps")) {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            } else if (url.startsWith("tel:")) {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(_getHtmlWithViewport(widget.detalleHtml));

    // Ya no se necesita escuchar el stream manualmente, se usará ValueNotifier
    _calcularDistanciaDesdeUbicacionCliente(); // llamada a función

    // Suscribirse al stream de moviles para obtener DistanciaMaxMtsCumpPedidos
    // Si necesitas la distancia máxima, puedes obtenerla del movilNotifier
    print("🚀 [INIT] Inicializando listener de movilNotifier...");

    // Log del estado inicial
    final initialSnapshot = _persistentStreamManager.movilNotifier.value;
    print(
        "🔍 [INIT] Estado inicial del movilNotifier: ${initialSnapshot?.exists}");

    _persistentStreamManager.movilNotifier.addListener(() {
      final movilSnapshot = _persistentStreamManager.movilNotifier.value;
      print(
          "🔍 [FIRESTORE DEBUG] Movil snapshot existe: ${movilSnapshot?.exists}");

      if (movilSnapshot != null && movilSnapshot.exists) {
        final data = movilSnapshot.data() as Map<String, dynamic>?;
        print("🔍 [FIRESTORE DEBUG] Data completa: $data");
        print(
            "🔍 [FIRESTORE DEBUG] Claves disponibles: ${data?.keys.toList()}");

        if (data != null && data.containsKey('DistanciaMaxMtsCumpPedidos')) {
          final value = data['DistanciaMaxMtsCumpPedidos'];
          print(
              "🔍 [FIRESTORE DEBUG] DistanciaMaxMtsCumpPedidos encontrado: $value (tipo: ${value.runtimeType})");

          // Intentar convertir el valor a int, aceptando int, double o string
          int? distanciaInt;
          if (value is int) {
            distanciaInt = value;
            print("🔍 [FIRESTORE DEBUG] Valor es int directo: $distanciaInt");
          } else if (value is double) {
            distanciaInt = value.toInt();
            print(
                "🔍 [FIRESTORE DEBUG] Valor es double, convertido a int: $distanciaInt");
          } else if (value is String) {
            distanciaInt = int.tryParse(value);
            print(
                "🔍 [FIRESTORE DEBUG] Valor es string, parseado a int: $distanciaInt");
          } else {
            print(
                "🔍 [FIRESTORE DEBUG] Valor es de tipo no esperado: ${value.runtimeType}");
          }

          if (distanciaInt != null && distanciaInt > 0) {
            if (mounted) {
              setState(() {
                _distanciaMaxMtsCumpPedidos = distanciaInt;
              });
              print(
                  "✅ [FIRESTORE] DistanciaMaxMtsCumpPedidos configurado: $distanciaInt metros");
            }
          } else {
            if (mounted) {
              setState(() {
                _distanciaMaxMtsCumpPedidos = null;
              });
              print(
                  "⚠️ [FIRESTORE] DistanciaMaxMtsCumpPedidos inválido o <= 0: $value");
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _distanciaMaxMtsCumpPedidos = null;
            });
            print(
                "⚠️ [FIRESTORE] DistanciaMaxMtsCumpPedidos no encontrado en documento");
            print(
                "🔍 [FIRESTORE DEBUG] Campos disponibles: ${data?.keys.join(', ') ?? 'ninguno'}");
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _distanciaMaxMtsCumpPedidos = null;
          });
          print("❌ [FIRESTORE] Documento de móvil no existe o es null");
        }
      }
    });
  }

  // 🆕 Método para verificar y reiniciar el servicio de coordenadas si está muerto
  Future<void> _checkAndRestartLocationService() async {
    const tag = '🔄[SERVICE_CHECK]';
    String statusCode = 'E'; // E = Error por defecto

    try {
      print('$tag Verificando estado del servicio de ubicación...');

      // ✅ Obtener parámetros desde Hive (source of truth)
      final sessionBox = await Hive.openBox('sessionBox');
      final movil = sessionBox.get('movil')?.toString() ?? '';
      final escenario = sessionBox.get('escenario')?.toString() ?? '';
      final usuario = sessionBox.get('usuario')?.toString() ?? '';
      final deviceId = sessionBox.get('deviceId')?.toString() ?? '';
      final intervalMinutes = sessionBox.get('intervalMinutes') ?? 3;

      // Validar que movil no esté vacío
      if (movil.isEmpty) {
        print(
            '$tag ❌ CRITICAL: movil vacío en Hive, no se puede validar servicio');
        statusCode = 'E'; // E = Error
        return;
      }

      print('$tag Validando servicio con movil: $movil');

      const platform = MethodChannel('background_service');
      final result =
          await platform.invokeMethod('checkAndRestartLocationService', {
        'movil': movil,
        'escenario': escenario,
        'usuario': usuario,
        'deviceId': deviceId,
        'interval': intervalMinutes,
      });

      if (result is Map) {
        final status = result['status'];
        final message = result['message'];
        final restarted = result['restarted'] ?? false;
        final movilValidated = result['movil_validated'] ?? false;
        final restartReason = result['restart_reason'] ?? '';

        print(
            '$tag Estado: $status - $message (movil_validated: $movilValidated)');
        if (restartReason.isNotEmpty) {
          print('$tag Razón de reinicio: $restartReason');
        }

        // Determinar código de estado
        if (status == 'disabled') {
          statusCode = 'D'; // D = Disabled
        } else if (restarted == true) {
          statusCode = 'R'; // R = Restarted
        } else if (status == 'active') {
          statusCode = 'A'; // A = Active
        } else if (status == 'never_started') {
          statusCode = 'N'; // N = Never started
        } else {
          statusCode = 'U'; // U = Unknown
        }

        if (restarted == true) {
          print('$tag ✅ Servicio reiniciado automáticamente');
          // Mostrar un SnackBar al usuario
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('Servicio de ubicación reiniciado'),
                    ),
                  ],
                ),
                duration: Duration(seconds: 3),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else if (status == 'active') {
          print('$tag ✅ Servicio activo y funcionando correctamente');
        } else if (status == 'disabled') {
          print('$tag ⚠️ Servicio deshabilitado manualmente, no se reinicia');
        } else if (status == 'never_started') {
          print(
              '$tag ⚠️ Servicio nunca iniciado, usuario debe activarlo manualmente');
        }
      }
    } catch (e) {
      print('$tag ❌ Error verificando servicio: $e');
      statusCode = 'E'; // E = Error
    } finally {
      // Guardar registro compacto en Hive (15 caracteres: timestamp + código)
      try {
        final now = DateTime.now();
        final timestamp =
            '${now.year.toString().substring(2)}${now.month.toString().padLeft(2, '0')}'
            '${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}'
            '${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
        final checkRecord =
            '$timestamp$statusCode'; // Ej: "250116143025R" (13 chars)

        final sessionBox = await Hive.openBox('sessionBox');
        await sessionBox.put('lastServiceCheck', checkRecord);

        final statusDesc = {
              'A': 'Activo',
              'R': 'Reiniciado',
              'D': 'Deshabilitado',
              'N': 'Nunca iniciado',
              'E': 'Error',
              'U': 'Desconocido'
            }[statusCode] ??
            'Desconocido';

        print('$tag 💾 Guardado en Hive: $checkRecord ($statusDesc)');
      } catch (e) {
        print('$tag ❌ Error guardando en Hive: $e');
      }
    }
  }

  @override
  void dispose() {
    // Remueve listener de printScreen
    if (_movilShieldListener != null) {
      _persistentStreamManager.movilNotifier
          .removeListener(_movilShieldListener!);
      _movilShieldListener = null;
    }
    _movilSubscription?.cancel();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _enableScreenShield() async {
    if (!Platform.isAndroid) return;

    final manager = _persistentStreamManager;

    Future<void> apply(DocumentSnapshot? doc) async {
      try {
        dynamic val;
        if (doc != null) {
          try {
            val = doc.get('printScreen');
          } catch (_) {
            final data = doc.data();
            if (data is Map<String, dynamic>) val = data['printScreen'];
          }
        }
        // 'S' => permitir (OFF), 'N' => bloquear (ON), null/otros => permitir (OFF)
        final bool shouldBlock = (val == 'N');
        if (shouldBlock) {
          await ScreenProtector.preventScreenshotOn();
          print('🛡️ Screenshot bloqueado (Android)');
        } else {
          await ScreenProtector.preventScreenshotOff();
          print('🛡️ Screenshot permitido (Android)');
        }
      } catch (e) {
        print('❌ Error toggling ScreenProtector: $e');
      }
    }

    await apply(manager.movilNotifier.value);
    manager.movilNotifier.addListener(() {
      apply(manager.movilNotifier.value);
    });
  }

  void _calcularDistanciaDesdeUbicacionCliente() async {
    try {
      var currentLocation = await LocationService().getCurrentLocation();
      if (currentLocation != null) {
        double latActual = currentLocation['latitude'];
        double lngActual = currentLocation['longitude'];
        double distanciaEnMetros = 0;
        if (widget.ubicacion != null) {
          double latCliente = widget.ubicacion!.latitude;
          double lngCliente = widget.ubicacion!.longitude;
          distanciaEnMetros = Geolocator.distanceBetween(
            latActual,
            lngActual,
            latCliente,
            lngCliente,
          );
          print(
              '📏 Distancia hasta cliente: ${distanciaEnMetros.toStringAsFixed(2)} metros');
        } else {
          print('⚠️ Ubicación del cliente no disponible, distanciaEnMetros=0');
        }
      } else {
        print('❌ No se pudo obtener la ubicación actual.');
      }
    } catch (e) {
      print('⚠️ Error al calcular distancia: $e');
    }
  }

  void injectCSS() {
    String css = '''
    document.body.style.margin = "0";
    document.body.style.padding = "0";
    document.body.style.overflowX = "hidden"; 
    document.body.style.width = "100%";
  ''';

    _controller.runJavaScript(css);
  }

  String _getHtmlWithViewport(String content) {
    return '''
  <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        html, body {
          margin: 0;
          padding: 0;
          width: 100vw;
          overflow-x: hidden;
          box-sizing: border-box;
        }
        * {
          box-sizing: border-box !important;
        }
        div, section, article, main, p {
          margin: 10 !important;
          padding: 0 !important;
          width: 100% !important;
        }
        img, iframe {
          max-width: 100%;
          height: auto;
          display: block;
        }
      </style>
    </head>
    <body>
      $content
    </body>
  </html>
  ''';
  }

  void _showPaymentModal(BuildContext context) {
    double totalPedido = widget.totalPedido; // Use the passed totalPedido
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        List<Map<String, dynamic>> paymentMethods = [];
        double totalEntered = 0;

        void addPaymentMethod() {
          if (paymentMethods.length < 3) {
            setState(() {
              paymentMethods.add({'method': null, 'amount': 0.0});
            });
          }
        }

        void removePaymentMethod(int index) {
          setState(() {
            totalEntered -= paymentMethods[index]['amount'];
            paymentMethods.removeAt(index);
          });
        }

        void updatePaymentAmount(int index, double amount) {
          setState(() {
            totalEntered -= paymentMethods[index]['amount'];
            paymentMethods[index]['amount'] = amount;
            totalEntered += amount;
          });
        }

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 16,
                left: 16,
                right: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total: \$${totalPedido.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed:
                        paymentMethods.length < 3 ? addPaymentMethod : null,
                    icon: Icon(Icons.add),
                    label: Text('Agregar forma de pago'),
                  ),
                  ...paymentMethods.asMap().entries.map((entry) {
                    int index = entry.key;
                    Map<String, dynamic> method = entry.value;
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButton<String>(
                                hint: Text('Forma de pago'),
                                value: method['method'],
                                onChanged: (newValue) {
                                  setState(() {
                                    paymentMethods[index]['method'] = newValue;
                                  });
                                },
                                items: [
                                  'Efectivo',
                                  'Tarjeta',
                                  'Transferencia',
                                ].map((method) {
                                  return DropdownMenuItem<String>(
                                    value: method,
                                    child: Text(method),
                                  );
                                }).toList(),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, color: Colors.red),
                              onPressed: () => removePaymentMethod(index),
                            ),
                          ],
                        ),
                        TextField(
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Monto \$',
                            errorText:
                                paymentMethods[index]['amount'] > totalPedido
                                    ? 'Excede el total'
                                    : null,
                          ),
                          onChanged: (value) {
                            double amount = double.tryParse(value) ?? 0.0;
                            if (totalEntered -
                                    paymentMethods[index]['amount'] +
                                    amount <=
                                totalPedido) {
                              updatePaymentAmount(index, amount);
                            }
                          },
                        ),
                        SizedBox(height: 8),
                      ],
                    );
                  }).toList(),
                  Text(
                    totalEntered < totalPedido
                        ? 'Faltan: \$${(totalPedido - totalEntered).toStringAsFixed(2)}'
                        : totalEntered == totalPedido
                            ? '¡Listo! Total completo.'
                            : 'Excede el total',
                    style: TextStyle(
                      color: totalEntered > totalPedido
                          ? Colors.red
                          : totalEntered == totalPedido
                              ? Colors.green
                              : Colors.grey,
                    ),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: _observacionesController,
                    maxLength: 300,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Observaciones',
                      hintText: 'Ingrese observaciones (solo letras y números)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      final sanitizedValue = value.replaceAll(
                        RegExp(r'[^a-zA-Z0-9 ]'),
                        '',
                      );
                      if (sanitizedValue != value) {
                        _observacionesController.text = sanitizedValue;
                        _observacionesController.selection =
                            TextSelection.fromPosition(
                          TextPosition(offset: sanitizedValue.length),
                        );
                      }
                      _observaciones = sanitizedValue;
                    },
                  ),
                  SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Cancelar'),
                      ),
                      ElevatedButton(
                        onPressed: totalEntered == totalPedido &&
                                paymentMethods.isNotEmpty
                            ? () async {
                                // Call finalizarPedido service here
                                Navigator.of(context).pop();
                              }
                            : null,
                        child: Text('Confirmar'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /**
   * Valida distancia y permisos ANTES de mostrar el diálogo de finalización
   * Retorna true si puede proceder, false si debe bloquear
   */
  // Resultado de validación con mensaje de error
  // quickCheck: si es true, solo verifica GPS/permisos sin geolocalizar (más rápido)
  Future<Map<String, dynamic>> _validateBeforeShowingDialog(
      {bool showErrors = true, bool quickCheck = false}) async {
    print(
        "🔍 [PRE-VALIDATION] Iniciando validación previa... (showErrors: $showErrors, quickCheck: $quickCheck)");

    // 🆕 VERIFICAR ESTADO ACTUAL DE LA VARIABLE ANTES DE VALIDAR
    print(
        "🔍 [PRE-STATE] Estado actual de _distanciaMaxMtsCumpPedidos: $_distanciaMaxMtsCumpPedidos");
    print(
        "🔍 [PRE-STATE] Tipo de _distanciaMaxMtsCumpPedidos: ${_distanciaMaxMtsCumpPedidos.runtimeType}");

    // 🆕 VERIFICAR ESTADO DEL MOVILNOTIFIER
    final currentSnapshot = _persistentStreamManager.movilNotifier.value;
    print(
        "🔍 [PRE-STATE] movilNotifier snapshot existe: ${currentSnapshot?.exists}");
    if (currentSnapshot?.exists == true) {
      final data = currentSnapshot!.data() as Map<String, dynamic>?;
      print("🔍 [PRE-STATE] Datos actuales del documento: $data");
      if (data?.containsKey('DistanciaMaxMtsCumpPedidos') == true) {
        print(
            "🔍 [PRE-STATE] DistanciaMaxMtsCumpPedidos en Firestore: ${data!['DistanciaMaxMtsCumpPedidos']}");

        // 🆕 FORZAR ACTUALIZACIÓN SI HAY DISCREPANCIA
        if (_distanciaMaxMtsCumpPedidos == null &&
            data['DistanciaMaxMtsCumpPedidos'] != null) {
          print(
              "🔧 [PRE-FIX] Detectada discrepancia, forzando actualización...");
          final value = data['DistanciaMaxMtsCumpPedidos'];
          int? distanciaInt;
          if (value is int) {
            distanciaInt = value;
          } else if (value is double) {
            distanciaInt = value.toInt();
          } else if (value is String) {
            distanciaInt = int.tryParse(value);
          }

          if (distanciaInt != null && distanciaInt > 0) {
            setState(() {
              _distanciaMaxMtsCumpPedidos = distanciaInt;
            });
            print(
                "✅ [PRE-FIX] _distanciaMaxMtsCumpPedidos actualizado a: $distanciaInt");
          }
        }
      }
    }

    try {
      // ===========
      // 💥 PASO 1: VERIFICAR GPS Y PERMISOS PRIMERO (antes de pedir ubicación)
      // ===========
      print("🔍 [PRE-GPS-CHECK] Verificando estado del GPS...");
      bool isGpsEnabled = await Geolocator.isLocationServiceEnabled();
      print(
          "📍 [PRE-GPS-STATUS] Servicios de ubicación habilitados: $isGpsEnabled");

      if (!isGpsEnabled) {
        // GPS desactivado por el usuario - BLOQUEAR
        print("❌ [PRE-GPS-BLOCKED] GPS desactivado por el usuario");
        String errorMsg =
            'Para finalizar el pedido debe activar el GPS en la configuración de su dispositivo.';
        if (showErrors) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return {'success': false, 'errorMessage': errorMsg};
      }

      // GPS está activado - verificar permisos
      LocationPermission permission = await Geolocator.checkPermission();
      print("🔐 [PRE-PERMISSION] Permisos de ubicación: $permission");

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        print(
            "🔐 [PRE-PERMISSION-REQUESTED] Permisos solicitados: $permission");
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        print("❌ [PRE-PERMISSION-BLOCKED] Permisos denegados permanentemente");
        String errorMsg =
            'Los permisos de ubicación están denegados. Debe habilitarlos en configuración para finalizar el pedido.';
        if (showErrors) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return {'success': false, 'errorMessage': errorMsg};
      }

      // ===========
      // 💥 PASO 2: Si es quickCheck, salir aquí SIN pedir ubicación
      // ===========
      if (quickCheck) {
        print(
            "✅ [QUICK-CHECK] GPS activo y permisos OK - saltando geolocalización");
        return {'success': true, 'errorMessage': ''};
      }

      // ===========
      // 💥 PASO 3: Ahora sí, pedir ubicación (solo si pasaron GPS y permisos)
      // ===========
      var sessionBox = await Hive.openBox('sessionBox');
      var usuario = sessionBox.get('username');
      String movil = sessionBox.get('movil').toString();

      String lat = '0.0';
      String lng = '0.0';

      print("📍 [PRE-GPS] Solicitando ubicación actual (timeout: 8s)...");
      try {
        var currentLocation = await LocationService()
            .getCurrentLocation()
            .timeout(Duration(seconds: 8));
        if (currentLocation != null) {
          lat = currentLocation['latitude'].toString();
          lng = currentLocation['longitude'].toString();
          print("✅ [PRE-GPS] Ubicación obtenida: Lat: $lat, Lng: $lng");
        } else {
          print(
              "⚠️ [PRE-GPS] No se obtuvo ubicación (null). Continuamos sin bloquear.");
        }
      } on TimeoutException {
        print(
            "⏳ [PRE-GPS] Timeout al obtener ubicación. Continuamos sin bloquear.");
      } catch (e) {
        print(
            "❌ [PRE-GPS] Error al obtener ubicación: $e. Continuamos sin bloquear.");
      }

      // Calcular distancia al cliente
      double distanciaEnMetros = 0;
      if (widget.ubicacion != null && lat != '0.0' && lng != '0.0') {
        double latCliente = widget.ubicacion!.latitude;
        double lngCliente = widget.ubicacion!.longitude;
        double latActual = double.tryParse(lat) ?? 0.0;
        double lngActual = double.tryParse(lng) ?? 0.0;

        distanciaEnMetros = Geolocator.distanceBetween(
          latActual,
          lngActual,
          latCliente,
          lngCliente,
        );
        print("📏 [PRE-DISTANCIA] Distancia al cliente: $distanciaEnMetros m");
        print(
            "📍 [PRE-COORDENADAS] Cliente: ($latCliente, $lngCliente) | Actual: ($latActual, $lngActual)");
      } else {
        print(
            "⚠️ [PRE-DISTANCIA] No se puede calcular distancia al cliente sin GPS.");
        print(
            "📍 [PRE-COORDENADAS] Cliente: ${widget.ubicacion?.latitude ?? 'N/A'}, ${widget.ubicacion?.longitude ?? 'N/A'} | GPS: $lat, $lng");
      }

      String? CalculoDistancia = await getConstantValue('260');
      print("📐 [PRE-VALOR 260] CalculoDistancia = $CalculoDistancia");

      String? mensajeDistancia = await getConstantValue('610');
      print("📝 [PRE-VALOR 610] mensajeDistancia = $mensajeDistancia");

      // ===== VALIDACIÓN DE DISTANCIA =====
      print("🔍 [PRE-VALIDACIÓN] Iniciando validación de distancia...");
      print("📏 [PRE-DATOS] Distancia actual: $distanciaEnMetros m");
      print(
          "📋 [PRE-DATOS] Distancia máxima permitida: $_distanciaMaxMtsCumpPedidos m");
      print(
          "⚙️ [PRE-DATOS] CalculoDistancia (Constante 260): '$CalculoDistancia'");
      print(
          "📱 [PRE-DATOS] PedidoID: ${widget.codPedido} | Usuario: $usuario | Móvil: $movil");

      // Verificar si debe validar distancia
      bool debeValidarDistancia = CalculoDistancia == 'S';
      print("🔧 [PRE-CONTROL] ¿Debe validar distancia? $debeValidarDistancia");

      if (debeValidarDistancia) {
        // Solo validar si tenemos una configuración válida de distancia máxima
        if (_distanciaMaxMtsCumpPedidos != null &&
            _distanciaMaxMtsCumpPedidos! > 0) {
          // GPS activado y con permisos - ahora verificar coordenadas
          if (lat == '0.0' || lng == '0.0') {
            print(
                "⚠️ [PRE-GPS-NO-COORDS] GPS activo pero sin coordenadas válidas - se permitirá finalizar");
            // GPS está activo pero no se obtuvieron coordenadas - PERMITIR
          } else {
            // GPS activo con coordenadas válidas - validar distancia
            print(
                "📍 [PRE-GPS-VALID] GPS activo con coordenadas válidas - validando distancia");

            // Verificar que se pudo calcular distancia al cliente
            if (distanciaEnMetros <= 0) {
              print(
                  "⚠️ [PRE-WARNING] No se pudo calcular distancia al cliente - se permitirá finalizar");
            } else {
              // Validar distancia máxima permitida
              if (distanciaEnMetros > _distanciaMaxMtsCumpPedidos!) {
                print(
                    "❌ [PRE-VALIDACIÓN FALLIDA] Distancia excedida: $distanciaEnMetros > $_distanciaMaxMtsCumpPedidos");

                // Obtener mensaje desde constante 610
                String mensaje = mensajeDistancia ??
                    'No puede finalizar el pedido. Su distancia al cliente (${distanciaEnMetros.toStringAsFixed(0)}m) supera el máximo permitido.';

                // Reemplazar placeholder {distancia} con el valor real si existe
                mensaje = mensaje.replaceAll(
                    '{distancia}', distanciaEnMetros.toStringAsFixed(0));

                if (showErrors) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(mensaje),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 5),
                    ),
                  );
                }
                return {'success': false, 'errorMessage': mensaje};
              }

              print(
                  "✅ [PRE-VALIDACIÓN EXITOSA] Distancia dentro del rango permitido");
            }
          }
        } else {
          print(
              "⚠️ [PRE-OMITIDO] Validación de distancia omitida: DistanciaMaxMtsCumpPedidos es null o <= 0 ($_distanciaMaxMtsCumpPedidos)");
        }
      } else {
        print(
            "⚠️ [PRE-OMITIDO] Validación de distancia deshabilitada por configuración");
      }

      print(
          "🚀 [PRE-CONTINUAR] Todas las validaciones pasaron, puede proceder");
      return {'success': true, 'errorMessage': ''};
    } catch (e) {
      print("❌ [PRE-ERROR] Error en validación previa: $e");
      String errorMsg = 'Error interno al validar. Inténtelo nuevamente.';
      if (showErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
          ),
        );
      }
      return {'success': false, 'errorMessage': errorMsg};
    }
  }

  void _finalizeOrder() async {
    // ✅ Prevenir múltiples llamadas simultáneas
    if (_isFinalizing) {
      print("⚠️ [FINALIZE] Ya hay una finalización en curso, ignorando...");
      return;
    }

    setState(() => _isFinalizing = true);
    print("🟢 [INIT] Iniciando verificación de constante 70...");

    // ✅ Capturar timestamp AL INICIO para evitar duplicados
    final String capturedTimestamp = DateTime.now().toUtc().toIso8601String();
    print("🕒 [TIMESTAMP] Capturado timestamp único: $capturedTimestamp");

    // Debug: Verificar estado de distancia máxima
    print(
        "🔍 [DEBUG] Estado actual de _distanciaMaxMtsCumpPedidos: $_distanciaMaxMtsCumpPedidos");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(child: CircularProgressIndicator());
      },
    );

    try {
      print("📦 [HIVE] Abriendo cajas Hive...");
      var box = await Hive.openBox('constantBox');
      var sessionBox = await Hive.openBox('sessionBox');
      var escenario = sessionBox.get('escenario');
      var data = box.get('70');

      String? valorEscenarioKey = 'ValorEscenario$escenario';
      String? valorFinal;

      if (data != null) {
        print("🧾 [DATA] Constante 70 leída: $data");
        if (data.containsKey(valorEscenarioKey) &&
            data[valorEscenarioKey] != null) {
          valorFinal = data[valorEscenarioKey];
          print(
              "🟣 [ESCENARIO] Se usará valor por escenario: $valorEscenarioKey => $valorFinal");
        } else {
          valorFinal = data['Valor'];
          print("🔵 [DEFAULT] Se usará valor general: $valorFinal");
        }
      }

      if (data != null && data['Estado'] == 'A' && valorFinal == 'S') {
        print("✅ [MODAL] Condiciones cumplidas, mostrando modal de pago...");
        Navigator.of(context).pop();
        _showPaymentModal(context);
        return;
      }

      if (_selectedSubEstado == null) {
        print("❌ [ERROR] SubEstado no seleccionado");
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Debe seleccionar al menos una acción.')),
        );
        return;
      }

      print("🗃️ [HIVE] Reuniendo datos adicionales...");
      var pedidosBox = await Hive.openBox('pedidosBox');
      var usuario = sessionBox.get('username');
      var pedidoId = widget.codPedido;
      var pedidoTpo = widget.pedidoTipo;
      String movil = sessionBox.get('movil').toString();
      String deviceId = sessionBox.get('deviceId');

      String lat = '0.0';
      String lng = '0.0';
      String utmx = '0.0';
      String utmy = '0.0';

      print("📍 [GPS] Solicitando ubicación actual (timeout: 15s)...");
      try {
        var currentLocation = await LocationService()
            .getCurrentLocation()
            .timeout(Duration(seconds: 15));
        if (currentLocation != null) {
          lat = currentLocation['latitude'].toString();
          lng = currentLocation['longitude'].toString();
          utmx = currentLocation['utmX'].toString();
          utmy = currentLocation['utmY'].toString();

          print(
              "✅ [GPS] Ubicación obtenida: Lat: $lat, Lng: $lng, UTMX: $utmx, UTMY: $utmy");
        } else {
          print(
              "⚠️ [GPS] No se obtuvo ubicación después de 15 segundos, se usará 0.0 por defecto.");
        }
      } catch (e) {
        print(
            "❌ [GPS] Error/Timeout al obtener ubicación después de 15 segundos: $e. Se continuará sin GPS.");
      }

      var locationBox = await Hive.openBox('locationBox');

      // 🆕 DEBUGGING DETALLADO DE SINCRONIZACIÓN
      print("🔍 [FINALIZE_SYNC] Verificando contenido de locationBox...");
      final allKeys = locationBox.keys.toList();
      print("🔍 [FINALIZE_SYNC] Claves disponibles en locationBox: $allKeys");

      final rawSpeed = locationBox.get('lastSpeed', defaultValue: 0.0);
      final rawDistance = locationBox.get('totalDistance', defaultValue: 0.0);

      print(
          "🔍 [FINALIZE_SYNC] Valor crudo lastSpeed: $rawSpeed (tipo: ${rawSpeed.runtimeType})");
      print(
          "🔍 [FINALIZE_SYNC] Valor crudo totalDistance: $rawDistance (tipo: ${rawDistance.runtimeType})");

      double velocidad = double.parse(rawSpeed.toStringAsFixed(2));
      double distanciaRecorrida = double.parse(rawDistance.toStringAsFixed(6));

      print("🔍 [FINALIZE_SYNC] Velocidad procesada: $velocidad");
      print("🔍 [FINALIZE_SYNC] Distancia procesada: $distanciaRecorrida");

      // 🆕 VERIFICAR SI EXISTEN OTROS POSIBLES NOMBRES DE CLAVES
      for (String key in allKeys) {
        if (key.toLowerCase().contains('distance') ||
            key.toLowerCase().contains('speed')) {
          final value = locationBox.get(key);
          print(
              "🔍 [FINALIZE_SYNC] Clave relacionada encontrada: $key = $value");
        }
      }

      print(
          "🚗 [MOVIMIENTO] Velocidad: $velocidad m/s | Distancia: $distanciaRecorrida m");

      // Cálculo de distancia al cliente para el API (la validación ya se hizo)
      double distanciaEnMetros = 0;
      if (widget.ubicacion != null && lat != '0.0' && lng != '0.0') {
        double latCliente = widget.ubicacion!.latitude;
        double lngCliente = widget.ubicacion!.longitude;
        double latActual = double.tryParse(lat) ?? 0.0;
        double lngActual = double.tryParse(lng) ?? 0.0;

        distanciaEnMetros = Geolocator.distanceBetween(
          latActual,
          lngActual,
          latCliente,
          lngCliente,
        );
        print(
            "📏 [DISTANCIA] Distancia al cliente para API: $distanciaEnMetros m");
      }

      String? CalculoDistancia = await getConstantValue('260');
      print("📐 [VALOR 260] CalculoDistancia = $CalculoDistancia");

      // La validación de distancia ya se hizo en _validateBeforeShowingDialog()
      print(
          "🚀 [CONTINUAR] Procediendo con finalización del pedido (validación previa exitosa)...");

      // 🆕 GENERAR INAUX1 E INAUX2 PARA FINALIZACIÓN
      String inAux1 = movil; // Número del móvil
      String inAux2 = '';

      try {
        print(
            "🔧 [FINALIZE] Generando string de estado del móvil para INAux2...");

        // Estado de la aplicación
        String appState =
            "active"; // Siempre active cuando la app está funcionando

        // Estado de notificaciones
        String notificaciones = "ON";

        // Estado de permisos de ubicación
        String permisos = "UNKNOWN";
        try {
          if (lat != '0.0' && lng != '0.0') {
            permisos =
                "FULL"; // Si tenemos ubicación, asumimos permisos completos
          } else {
            permisos = "DENIED";
          }
        } catch (e) {
          permisos = "UNKNOWN";
        }

        // Estado del GPS
        String gpsState = (lat != '0.0' && lng != '0.0') ? "ON" : "OFF";

        // Retry y Reset
        String retry = "0";
        String reset = "No";

        // Construir el string completo
        inAux2 =
            "Estado: $appState | Notificaciones: $notificaciones | Permisos: $permisos | GPS: $gpsState | Retry: $retry | Reset: $reset";

        print("✅ [FINALIZE] INAux2 generado: $inAux2");
      } catch (e) {
        print("❌ [FINALIZE] Error generando string de estado: $e");
        inAux2 = "Error generando estado";
      }

      print("📤 [API] Enviando datos a RioGasService.finalizarPedido...");
      var response = await RioGasService.finalizarPedido(
        int.parse(escenario.toString()),
        pedidoId,
        pedidoTpo,
        usuario,
        '',
        deviceId,
        2,
        int.parse(_selectedSubEstado!),
        '',
        _observaciones ?? '',
        capturedTimestamp, // ✅ Usar timestamp capturado al inicio
        movil,
        distanciaEnMetros,
        inAux1,
        inAux2,
        lat,
        lng,
        utmx,
        utmy,
        velocidad,
        distanciaRecorrida,
      );

      if (response != null) {
        print("✅ [SERVICIO] Finalización exitosa para pedidoId $pedidoId");
        if (pedidosBox.containsKey(pedidoId)) {
          await pedidosBox.put(pedidoId, 'Procesando');
          print("📥 [HIVE] Pedido $pedidoId marcado como 'Procesando'");
        }

        // 🆕 ENVÍO DE LOGS DESPUÉS DE FINALIZAR PEDIDO
        // Envía logs a n8n solo si han pasado 10 minutos desde el último envío
        // Esto sirve como respaldo cuando WorkManager de Kotlin no puede ejecutarse
        try {
          print(
              "📤 [DEBUG] Intentando enviar logs después de finalizar pedido...");
          final logsSent = await DebugConfigManager.uploadLogsNow();
          if (logsSent) {
            print("✅ [DEBUG] Logs enviados exitosamente a n8n");
          } else {
            final minutesRemaining =
                DebugConfigManager.getMinutesUntilNextUpload();
            if (minutesRemaining != null && minutesRemaining > 0) {
              print(
                  "⏳ [DEBUG] Logs NO enviados (throttle activo: faltan $minutesRemaining min)");
            } else {
              print("⚠️ [DEBUG] Logs NO enviados (error o throttle en 0 min)");
            }
          }
        } catch (e) {
          print("⚠️ [DEBUG] Error enviando logs: $e");
          // No afecta el flujo del usuario, el error es silencioso
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Visita finalizada con éxito.')),
        );
      } else {
        print(
            "⚠️ [SERVICIO] No hubo respuesta del servicio. Pedido en estado 'Enviando'");
        if (pedidosBox.containsKey(pedidoId)) {
          await pedidosBox.put(pedidoId, 'Enviando');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enviando finalización de la visita.')),
        );
      }
    } catch (e, st) {
      print("❌ [ERROR] Excepción durante el flujo: $e");
      print(st);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ocurrió un error inesperado.')),
      );
    } finally {
      // ✅ Liberar flag de finalización
      setState(() => _isFinalizing = false);
      print("🔓 [FLAG] _isFinalizing liberado");

      Navigator.of(context).pop();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => HomePage()),
      );
      print("🔚 [FIN] Flujo de finalización completado.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detalle')),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _controller)),
          if (widget.estadoNro == 1) // Show button only if estadoNro is 1
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // ===== VALIDACIÓN PREVIA ANTES DEL POPUP =====
                    print("🟢 [BUTTON] Botón 'Finalizar Pedido' presionado");

                    // 1️⃣ QUICK CHECK PRIMERO: Verificar GPS y permisos (instantáneo)
                    print('⚡ [QUICK-CHECK] Verificando GPS y permisos...');
                    Map<String, dynamic> quickCheckResult =
                        await _validateBeforeShowingDialog(
                            showErrors: true, quickCheck: true);

                    if (!quickCheckResult['success']) {
                      print(
                          '❌ [QUICK-CHECK FALLIDO] GPS desactivado o permisos denegados');
                      // El error ya se mostró con showErrors: true
                      return;
                    }

                    print('✅ [QUICK-CHECK OK] GPS activo y permisos OK');

                    // 2️⃣ Mostrar loading SOLO para la geolocalización
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (BuildContext context) {
                        return Center(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 16),
                                  Text(
                                    'Validando ubicación GPS...',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Por favor espere',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );

                    // 3️⃣ FULL CHECK: Ejecutar validación completa (geolocalización + distancia)
                    Map<String, dynamic> validationResult =
                        await _validateBeforeShowingDialog(showErrors: true);

                    // Cerrar el loading de forma segura
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }

                    if (!validationResult['success']) {
                      print(
                          "❌ [VALIDATION] Validación falló, no se mostrará el diálogo");
                      return; // No mostrar el diálogo si la validación falla
                    }

                    print(
                        "✅ [VALIDATION] Validación exitosa, mostrando diálogo de selección");

                    // Si la validación pasó, mostrar el diálogo
                    await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return StatefulBuilder(
                          builder: (context, setState) {
                            return AlertDialog(
                              title: Text('Seleccione estado'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ValueListenableBuilder<
                                      List<Map<String, dynamic>>>(
                                    valueListenable:
                                        _subEstadosFinalizacionNotifier,
                                    builder: (context, subEstados, child) {
                                      return DropdownButton<String>(
                                        hint: Text('Seleccione'),
                                        value: _selectedSubEstado,
                                        onChanged: (newValue) {
                                          setState(() {
                                            _selectedSubEstado = newValue;
                                          });
                                        },
                                        items: subEstados.map((subEstado) {
                                          return DropdownMenuItem<String>(
                                            value: subEstado['SubEstadoCod']
                                                .toString(),
                                            child: Text(
                                                subEstado['SubEstadoDesc']),
                                          );
                                        }).toList(),
                                      );
                                    },
                                  ),
                                  SizedBox(height: 16),
                                  TextField(
                                    controller: _observacionesController,
                                    maxLength: 100,
                                    maxLines:
                                        3, // Allow the field to occupy 2 or 3 rows
                                    decoration: InputDecoration(
                                      labelText: 'Observaciones',
                                      hintText: 'Observaciones',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (value) {
                                      final sanitizedValue = value.replaceAll(
                                        RegExp(r'[^a-zA-Z0-9 ]'),
                                        '',
                                      );
                                      if (sanitizedValue != value) {
                                        _observacionesController.text =
                                            sanitizedValue;
                                        _observacionesController.selection =
                                            TextSelection.fromPosition(
                                          TextPosition(
                                            offset: sanitizedValue.length,
                                          ),
                                        );
                                      }
                                      _observaciones = sanitizedValue;
                                    },
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                  child: Text('Cancelar'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    print(
                                        '🔄 [REVALIDACIÓN] Iniciando validación en popup de confirmación...');
                                    print(
                                        '📋 [POPUP-DATA] Opción seleccionada: $_selectedSubEstado');

                                    // Cerrar el popup primero
                                    Navigator.of(context).pop();

                                    // 1️⃣ QUICK CHECK: Verificar GPS y permisos PRIMERO (instantáneo, sin loading)
                                    print(
                                        '⚡ [QUICK-CHECK] Verificando GPS y permisos...');
                                    Map<String, dynamic> quickCheckResult =
                                        await _validateBeforeShowingDialog(
                                            showErrors: true, quickCheck: true);

                                    if (!quickCheckResult['success']) {
                                      print(
                                          '❌ [QUICK-CHECK FALLIDO] GPS desactivado o permisos denegados');
                                      // El error ya se mostró con showErrors: true
                                      return;
                                    }

                                    print(
                                        '✅ [QUICK-CHECK OK] GPS activo y permisos OK');

                                    // 2️⃣ FULL CHECK: Ahora sí, geolocalizar y validar distancia (sin loading también)
                                    print(
                                        '📍 [FULL-CHECK] Geolocalizando y validando distancia...');
                                    Map<String, dynamic> fullCheckResult =
                                        await _validateBeforeShowingDialog(
                                            showErrors: true);

                                    if (!fullCheckResult['success']) {
                                      print(
                                          '❌ [FULL-CHECK FALLIDO] Validación de distancia falló');
                                      // El error ya se mostró con showErrors: true
                                      return;
                                    }

                                    // Si todo OK, proceder con finalización
                                    print(
                                        '✅ [REVALIDACIÓN EXITOSA] Procediendo con finalización...');
                                    _finalizeOrder();
                                  },
                                  child: Text('Confirmar'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                  icon: Icon(Icons.check, color: Colors.white),
                  label: Text('Finalizar Pedido'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(double.infinity, 50), // Full width button
                    backgroundColor: Colors.lightGreen,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
