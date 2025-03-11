import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class OrderDetailPage extends StatefulWidget {
  final String detalleHtml;
  final int estadoNro; // Add this parameter to pass the order status

  OrderDetailPage({required this.detalleHtml, required this.estadoNro});

  @override
  _OrderDetailPageState createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(_getHtmlWithViewport(widget.detalleHtml))
      ..runJavaScript('''
        document.body.style.margin = "0";
        document.body.style.padding = "0";
        document.body.style.overflowX = "hidden"; 
        document.body.style.width = "100%";
      ''');
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
                onPressed: () {
                  // Add your onPressed code here!
                },
                icon: Icon(Icons.check, color: Colors.white),
                label: Text('Finalizar Pedido',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightGreen,
                  minimumSize: Size(double.infinity, 50), // Full width button
                ),
              ),
            ),
        ],
      ),
    );
  }
}
