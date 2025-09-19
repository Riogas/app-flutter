import 'package:MoveIT/services/location_service.dart';
import 'package:flutter/material.dart';
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

  VoidCallback? _movilShieldListener; // para remover listener

  @override
  void initState() {
    super.initState();

    // ✅ Bloquear capturas (FLAG_SECURE) controlado por printScreen (solo Android)
    _enableScreenShield();

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
  Future<bool> _validateBeforeShowingDialog() async {
    print("🔍 [PRE-VALIDATION] Iniciando validación previa...");

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
      // Obtener datos necesarios para validación
      var sessionBox = await Hive.openBox('sessionBox');
      var usuario = sessionBox.get('username');
      String movil = sessionBox.get('movil').toString();

      String lat = '0.0';
      String lng = '0.0';

      // Obtener ubicación actual
      print("📍 [PRE-GPS] Solicitando ubicación actual...");
      try {
        var currentLocation = await LocationService()
            .getCurrentLocation()
            .timeout(Duration(seconds: 5));
        if (currentLocation != null) {
          lat = currentLocation['latitude'].toString();
          lng = currentLocation['longitude'].toString();
          print("✅ [PRE-GPS] Ubicación obtenida: Lat: $lat, Lng: $lng");
        } else {
          print(
              "⚠️ [PRE-GPS] No se obtuvo ubicación, se usará 0.0 por defecto.");
        }
      } catch (e) {
        print(
            "❌ [PRE-GPS] Error al obtener ubicación: $e. Se continuará sin GPS.");
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

      // ===== VALIDACIÓN MEJORADA DE DISTANCIA =====
      print("🔍 [PRE-VALIDACIÓN] Iniciando validación de distancia...");
      print("📏 [PRE-DATOS] Distancia actual: $distanciaEnMetros m");
      print(
          "📋 [PRE-DATOS] Distancia máxima permitida: $_distanciaMaxMtsCumpPedidos m");
      print(
          "⚙️ [PRE-DATOS] CalculoDistancia (Constante 260): '$CalculoDistancia'");
      print(
          "📱 [PRE-DATOS] PedidoID: ${widget.codPedido} | Usuario: $usuario | Móvil: $movil");
      print(
          "🎯 [PRE-ESTADO] ¿Dentro del rango?: ${_distanciaMaxMtsCumpPedidos != null && distanciaEnMetros <= _distanciaMaxMtsCumpPedidos! ? 'SÍ' : 'NO'}");

      // Verificar si debe validar distancia
      bool debeValidarDistancia = CalculoDistancia == 'S';
      print("🔧 [PRE-CONTROL] ¿Debe validar distancia? $debeValidarDistancia");

      if (debeValidarDistancia) {
        // Solo validar si tenemos una configuración válida de distancia máxima
        if (_distanciaMaxMtsCumpPedidos != null &&
            _distanciaMaxMtsCumpPedidos! > 0) {
          // Verificar primero que tengamos ubicación GPS válida (sin GPS no podemos validar distancia)
          if (lat == '0.0' || lng == '0.0') {
            print(
                "❌ [PRE-ERROR] GPS desactivado o no disponible para validación de distancia");
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'No se puede geolocalizar el móvil para finalizar el pedido. Por favor verifique que el GPS esté activado.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
            return false;
          }

          // Verificar que tengamos ubicación GPS válida para calcular distancia
          if (distanciaEnMetros <= 0) {
            print("❌ [PRE-ERROR] No se pudo calcular distancia al cliente");
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Error: No se pudo calcular la distancia al cliente para validar la ubicación.'),
                backgroundColor: Colors.red,
              ),
            );
            return false;
          }

          // Validar distancia máxima permitida
          if (distanciaEnMetros > _distanciaMaxMtsCumpPedidos!) {
            print(
                "❌ [PRE-VALIDACIÓN FALLIDA] Distancia excedida: $distanciaEnMetros > $_distanciaMaxMtsCumpPedidos");
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'No puede finalizar el pedido. Su distancia al cliente (${distanciaEnMetros.toStringAsFixed(0)}m) supera el máximo permitido.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
            return false;
          }

          print(
              "✅ [PRE-VALIDACIÓN EXITOSA] Distancia dentro del rango permitido");
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
      return true;
    } catch (e) {
      print("❌ [PRE-ERROR] Error en validación previa: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error interno al validar. Inténtelo nuevamente.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  void _finalizeOrder() async {
    print("🟢 [INIT] Iniciando verificación de constante 70...");

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

      print("📍 [GPS] Solicitando ubicación actual...");
      try {
        var currentLocation = await LocationService()
            .getCurrentLocation()
            .timeout(Duration(seconds: 5));
        if (currentLocation != null) {
          lat = currentLocation['latitude'].toString();
          lng = currentLocation['longitude'].toString();
          utmx = currentLocation['utmX'].toString();
          utmy = currentLocation['utmY'].toString();

          print(
              "✅ [GPS] Ubicación obtenida: Lat: $lat, Lng: $lng, UTMX: $utmx, UTMY: $utmy");
        } else {
          print("⚠️ [GPS] No se obtuvo ubicación, se usará 0.0 por defecto.");
        }
      } catch (e) {
        print("❌ [GPS] Error al obtener ubicación: $e. Se continuará sin GPS.");
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
                "FULL(FINE+COARSE+BACK)"; // Si tenemos ubicación, asumimos permisos completos
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
            "MoveITEstado: $appState | Notificaciones: $notificaciones | Permisos: $permisos | GPS: $gpsState | Retry: $retry | Reset: $reset";

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
        DateTime.now().toUtc().toIso8601String(),
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

                    // Ejecutar validación de distancia y permisos primero
                    bool canProceed = await _validateBeforeShowingDialog();

                    if (!canProceed) {
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
                                    // Ya no necesitamos validación aquí, se hizo antes
                                    print(
                                        'Opción seleccionada: $_selectedSubEstado');
                                    Navigator.of(context)
                                        .pop(); // Cerrar diálogo
                                    _finalizeOrder(); // Proceder con finalización
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
