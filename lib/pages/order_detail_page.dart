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
  final int estadoNro; // Add this parameter to pass the order status

  OrderDetailPage({required this.detalleHtml, required this.estadoNro});

  @override
  _OrderDetailPageState createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  late final WebViewController _controller;
  final FirebaseService _firebaseService = FirebaseService();
  List<Map<String, dynamic>> _subEstados = [];
  String? _selectedSubEstado;

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
        <meta name="viewport" content="width=device-width, initial-scale=0.5, initial-scale=0.5, maximum-scale=0.5, user-scalable=no">
        <style>
          body {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            width: 100vw;
            overflow-x: hidden;
          }
        </style>
      </head>
      <body>
        $html
      </body>
      </html>
    ''';
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
                            content: DropdownButton<String>(
                              hint: Text('Ninguna'),
                              value: _selectedSubEstado,
                              onChanged: (newValue) {
                                setState(() {
                                  _selectedSubEstado = newValue;
                                });
                              },
                              items: _subEstados.map((subEstado) {
                                return DropdownMenuItem<String>(
                                  value: subEstado['SubEstadoCod']
                                      .toString(), // Convert to string
                                  child: Text(subEstado['SubEstadoDesc']),
                                );
                              }).toList(),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                                child: Text('Cancelar'),
                              ),
                              TextButton(
                                onPressed: _selectedSubEstado == null
                                    ? null
                                    : () async {
                                        if (_selectedSubEstado == null) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'Debe seleccionar al menos una acción.'),
                                            ),
                                          );
                                          return;
                                        }

                                        var pedidoBox =
                                            await Hive.openBox('pedidoBox');
                                        var pedido = pedidoBox.get('pedido');
                                        var escenario = pedido['escenario'];
                                        var usuario = pedido['username'];
                                        var pedidoId = pedido['id'];
                                        var tipo = pedido['tipo'];
                                        var pedidoTpo =
                                            tipo == 'Pedidos' ? 1 : 2;
                                        var currentLocation =
                                            await LocationService()
                                                .getCurrentLocation();

                                        if (currentLocation == null) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'No se pudo obtener la ubicación actual.'),
                                            ),
                                          );
                                          return;
                                        }

                                        var response =
                                            await RioGasService.finalizarPedido(
                                          escenario,
                                          pedidoId,
                                          pedidoTpo.toString(),
                                          usuario,
                                          '',
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
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'Pedido finalizado con éxito.'),
                                            ),
                                          );
                                        } else {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'Error al finalizar el pedido.'),
                                            ),
                                          );
                                        }
                                        Navigator.of(context).pop();
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
