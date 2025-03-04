import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class OrderDetailPage extends StatefulWidget {
  final String detalleHtml;

  OrderDetailPage({required this.detalleHtml});

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
      body: WebViewWidget(controller: _controller),
    );
  }
}
