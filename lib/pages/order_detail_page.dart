import 'package:MoveIT/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_service.dart'; // Import FirebaseService
import 'package:hive/hive.dart';
import '../services/riogas_service.dart';
import 'package:url_launcher/url_launcher.dart'; // Importa para manejar URLs

class OrderDetailPage extends StatefulWidget {
  final String detalleHtml;
  final int estadoNro;
  final double totalPedido; // Add this parameter

  OrderDetailPage({
    required this.detalleHtml,
    required this.estadoNro,
    required this.totalPedido, // Initialize it
  });

  @override
  _OrderDetailPageState createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  late final WebViewController _controller;
  final FirebaseService _firebaseService = FirebaseService();
  List<Map<String, dynamic>> _subEstados = [];
  String? _selectedSubEstado;
  String? _observaciones = '';
  final _observacionesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
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
            // Handle tel: links
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            return NavigationDecision.prevent;
          }

          return NavigationDecision.navigate; // Permite otras URLs
        },
      ))
      ..loadHtmlString(_getHtmlWithViewport(widget.detalleHtml))
      ..runJavaScript('''
        document.body.style.margin = "0";
        document.body.style.padding = "0";
        document.body.style.overflowX = "hidden"; 
        document.body.style.width = "100%";
      ''');

    _firebaseService
        .getSubEstadoFinalizacionPedidosStream()
        .listen((subEstados) {
      if (mounted) {
        setState(() {
          _subEstados = subEstados;
        });
      }
    });
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

  String _getHtmlWithViewport(String html) {
    return '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
          body {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            width: 100%;
            overflow-x: auto; /* Allow horizontal scrolling */
          }
        </style>
      </head>
      <body>
        $html
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
                                items: ['Efectivo', 'Tarjeta', 'Transferencia']
                                    .map((method) {
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
                      final sanitizedValue =
                          value.replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), '');
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

  void _checkConstantAndProceed(BuildContext context) async {
    var box = await Hive.openBox('constantBox');
    var data = box.get('70');

    if (data != null && data['Estado'] == 'A' && data['Valor'] == 'S') {
      _showPaymentModal(context); // Show payment modal if conditions are met
    } else {
      // Execute the service directly if conditions are not met
      if (_selectedSubEstado == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Debe seleccionar al menos una acción.'),
          ),
        );
        return;
      }

      var pedidoBox = await Hive.openBox('pedidoBox');
      var pedido = pedidoBox.get('pedido');
      var escenario = pedido['escenario'];
      var usuario = pedido['username'];
      var pedidoId = pedido['id'];
      var tipo = pedido['tipo'];
      var pedidoTpo = tipo == 'Pedidos' ? 1 : 2;
      var currentLocation = await LocationService().getCurrentLocation();

      if (currentLocation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo obtener la ubicación actual.'),
          ),
        );
        return;
      }

      var response = await RioGasService.finalizarPedido(
        escenario,
        pedidoId,
        pedidoTpo.toString(),
        usuario,
        _observaciones ?? '',
        '',
        2,
        int.parse(_selectedSubEstado!),
        '',
        '',
        DateTime.now().toIso8601String(),
        '',
        '',
        currentLocation.latitude.toString(),
        currentLocation.longitude.toString(),
      );

      if (response != null) {
        var pedidosBox = await Hive.openBox('pedidoBox');
        if (pedidosBox.containsKey(pedidoId)) {
          await pedidosBox.put(
              pedidoId, 'Procesando'); // Update to 'Procesando' on success
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pedido finalizado con éxito.'),
          ),
        );
      } else {
        var pedidosBox = await Hive.openBox('pedidoBox');
        if (pedidosBox.containsKey(pedidoId)) {
          await pedidosBox.put(
              pedidoId, 'Enviando'); // Update to 'Enviando' on failure
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al finalizar el pedido.'),
          ),
        );
      }
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Detalle del Pedido'),
      ),
      body: Column(
        children: [
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
          if (widget.estadoNro == 1) // Show button only if estadoNro is 1
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return StatefulBuilder(
                        builder: (context, setState) {
                          return AlertDialog(
                            title: Text('Seleccione acción'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DropdownButton<String>(
                                  hint: Text('Ninguna'),
                                  value: _selectedSubEstado,
                                  onChanged: (newValue) {
                                    setState(() {
                                      _selectedSubEstado = newValue;
                                    });
                                  },
                                  items: _subEstados.map((subEstado) {
                                    return DropdownMenuItem<String>(
                                      value:
                                          subEstado['SubEstadoCod'].toString(),
                                      child: Text(subEstado['SubEstadoDesc']),
                                    );
                                  }).toList(),
                                ),
                                SizedBox(height: 16),
                                TextField(
                                  controller: _observacionesController,
                                  maxLength: 300,
                                  decoration: InputDecoration(
                                    labelText: 'Observaciones',
                                    hintText:
                                        'Ingrese observaciones (solo letras y números)',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (value) {
                                    final sanitizedValue = value.replaceAll(
                                        RegExp(r'[^a-zA-Z0-9 ]'), '');
                                    if (sanitizedValue != value) {
                                      _observacionesController.text =
                                          sanitizedValue;
                                      _observacionesController.selection =
                                          TextSelection.fromPosition(
                                        TextPosition(
                                            offset: sanitizedValue.length),
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
                                  if (_selectedSubEstado == 'Cumplido') {
                                    debugPrint('Opción seleccionada: Cumplido');
                                    _checkConstantAndProceed(
                                        context); // Check constant 70
                                  } else {
                                    debugPrint(
                                        'Opción seleccionada: $_selectedSubEstado');
                                    _checkConstantAndProceed(
                                        context); // Check constant 70
                                  }
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
        ],
      ),
    );
  }
}
