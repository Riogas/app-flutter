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
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../utils/constantes.dart';
import '../services/debug_config_manager.dart'; // 🆕 Debug logging

class OrderDetailPage extends StatefulWidget {
  final String detalleHtml;
  final int estadoNro;
  final double totalPedido; // Add this parameter
  final int codPedido;
  final String pedidoTipo;
  final GeoPoint? ubicacion;

  /// 🧭 true = abre directo el flujo de finalización al entrar
  /// (usado por "Devolver pedido" del diseño nuevo)
  final bool autoFinalize;

  OrderDetailPage({
    required this.detalleHtml,
    required this.estadoNro,
    required this.totalPedido, // Initialize it
    required this.codPedido,
    required this.pedidoTipo,
    this.ubicacion,
    this.autoFinalize = false,
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

  @override
  void initState() {
    super.initState();

    // 🔒 El anti-captura por flag `printScreen` lo aplica ProteccionPantalla
    // desde main.dart, para toda la sesión. Acá se hacía otra vez y por fuera
    // del servicio: apagaba el FLAG_SECURE de la Activity a espaldas de las
    // pantallas sensibles (Promociones/escáner) y encima dejaba un listener
    // colgado por cada pedido abierto.

    // 🆕 Verificar y reiniciar servicio de coordenadas si está muerto
    _checkAndRestartLocationService();

    // 🧭 "Devolver pedido" (diseño nuevo): abre directo el flujo de
    // finalización con TODAS las validaciones de siempre
    if (widget.autoFinalize && widget.estadoNro == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _iniciarFlujoFinalizacion();
      });
    }

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
    _movilSubscription?.cancel();
    _observacionesController.dispose();
    super.dispose();
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

  /// 🎨 Envuelve el detalle que manda el backend y lo reconstruye como cards.
  ///
  /// El backend entrega HTML legacy (una tabla de pares etiqueta/valor). Acá
  /// NO se reescribe ese contenido: se lee, se agrupa por secciones y se
  /// vuelve a dibujar. Los enlaces de Waze/Maps/teléfono se **mueven** al
  /// layout nuevo (no se copian), así conservan intactos su `href`, sus
  /// atributos y cualquier handler; el `NavigationDelegate` los sigue
  /// interceptando igual que antes.
  ///
  /// Si el HTML llegara con otra forma y no se reconoce ningún dato, se
  /// muestra el original con un estilo mínimo legible en vez de una pantalla
  /// vacía.
  String _getHtmlWithViewport(String content) {
    return '''
<!DOCTYPE html>
<html lang="es">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <style>
      :root {
        --navy: #08385f;
        --blue: #087cc1;
        --bright: #1598eb;
        --bg: #f4f7fa;
        --card: #ffffff;
        --text: #152e47;
        --text2: #627589;
        --soft: #eaf5ff;
        --border: #dfe8ef;
        --success: #82c63f;
      }
      * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
      html, body {
        margin: 0; padding: 0;
        background: var(--bg);
        color: var(--text);
        font-family: Inter, Roboto, system-ui, -apple-system, "Segoe UI", sans-serif;
        font-size: 15px;
        line-height: 1.45;
        overflow-x: hidden;
        -webkit-text-size-adjust: 100%;
      }
      body { padding: 12px 12px calc(14px + env(safe-area-inset-bottom)); }
      .card {
        background: var(--card);
        border: 1px solid rgba(20,70,110,.06);
        border-radius: 16px;
        box-shadow: 0 3px 10px rgba(15,55,85,.05), 0 1px 2px rgba(15,55,85,.04);
        padding: 11px 13px;
        margin-bottom: 9px;
      }
      .card:last-child { margin-bottom: 0; }
      .head { display: flex; align-items: center; gap: 9px; margin-bottom: 7px; }
      .ico {
        width: 32px; height: 32px; border-radius: 50%;
        background: var(--soft); color: var(--blue);
        display: flex; align-items: center; justify-content: center;
        flex: 0 0 32px;
      }
      .ico svg { width: 18px; height: 18px; }
      .title {
        font-size: 12.5px; font-weight: 700; color: var(--blue);
        letter-spacing: .02em;
      }
      .row { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
      .grow { flex: 1; min-width: 0; }
      .addr {
        font-size: 16px; font-weight: 700; line-height: 1.3;
        color: #142c45; overflow-wrap: anywhere;
      }
      .sub { font-size: 13px; color: var(--text2); overflow-wrap: anywhere; margin-top: 2px; }
      .strong { font-weight: 600; color: var(--text); }
      .main-val {
        font-size: 15px; font-weight: 600; color: var(--text);
        overflow-wrap: anywhere;
      }
      .chips { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 8px; }
      .chip {
        background: #f2f7fc; border-radius: 10px; padding: 6px 10px;
        display: flex; align-items: center; gap: 6px; min-width: 0;
      }
      .chip svg { width: 14px; height: 14px; color: var(--blue); flex: 0 0 14px; }
      .chip-lb { font-size: 11px; color: var(--text2); display: block; line-height: 1.2; }
      .chip-vl { font-size: 13.5px; font-weight: 600; color: var(--text); line-height: 1.25; }
      .badge {
        background: var(--soft); color: #0875c9; font-weight: 600;
        border-radius: 10px; padding: 5px 9px; font-size: 13px;
        white-space: nowrap; flex: 0 0 auto;
      }
      .prod { display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 5px 0; }
      .prod + .prod { border-top: 1px solid #eef3f7; }
      .maps { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 10px; }
      .maps a, a.act {
        height: 38px; padding: 0 12px; border-radius: 10px;
        border: 1px solid #168de2; background: #fff; color: #0875c9;
        font-size: 13.5px; font-weight: 600; text-decoration: none;
        display: flex; align-items: center; justify-content: center; gap: 6px;
        min-width: 0;
      }
      a.act { display: inline-flex; max-width: 100%; }
      .maps a.act { display: flex; }
      /* Hasta ~400px el número no entra en un tercio: el teléfono ocupa su
         propia fila a todo el ancho y Waze/Maps se reparten la de abajo. */
      @media (max-width: 400px) {
        .maps { grid-template-columns: 1fr 1fr !important; }
        .maps a.act { grid-column: 1 / -1; }
      }
      .maps a svg, a.act svg { width: 16px; height: 16px; flex: 0 0 16px; }
      .maps a span, a.act span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .maps a:active, a.act:active { transform: scale(.98); background: var(--soft); }
      .nota {
        margin-top: 8px; padding: 7px 10px; border-radius: 10px;
        background: #fff8e2; border-left: 3px solid #f2c315;
        font-size: 13px; color: #5b4708; overflow-wrap: anywhere;
      }
      .detalle {
        margin-top: 8px; padding-top: 8px; border-top: 1px solid #eef3f7;
        font-size: 12.5px; color: var(--text2); overflow-wrap: anywhere;
      }
      .tot-lb { font-size: 12px; color: var(--text2); text-align: right; }
      .tot-vl { font-size: 21px; font-weight: 700; color: #0877c9; text-align: right; white-space: nowrap; }
      .extra { display: flex; justify-content: space-between; gap: 10px; padding: 4px 0; font-size: 13.5px; }
      .extra + .extra { border-top: 1px solid #eef3f7; }
      .extra .k { color: var(--text2); flex: 0 0 auto; }
      .extra .v { color: var(--text); font-weight: 600; text-align: right; overflow-wrap: anywhere; }
      .legacy { background: #fff; border-radius: 16px; padding: 12px; font-size: 14px; }
      .legacy table { width: 100%; border-collapse: collapse; }
      .legacy td, .legacy th { padding: 4px 6px; text-align: left; }
      #legacy[hidden] { display: none; }
      @media (max-width: 340px) {
        .row { flex-wrap: wrap; }
        .tot-lb, .tot-vl { text-align: left; }
      }
    </style>
  </head>
  <body>
    <main id="app"></main>
    <div id="legacy" class="legacy" hidden>$content</div>
    <script>
    (function () {
      var src = document.getElementById('legacy');
      var app = document.getElementById('app');

      var I = {
        pin: '<path d="M12 21s7-5.4 7-11a7 7 0 1 0-14 0c0 5.6 7 11 7 11z"/><circle cx="12" cy="10" r="2.6"/>',
        clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.2 2"/>',
        box: '<path d="M3 8.5 12 4l9 4.5v7L12 20l-9-4.5z"/><path d="M3 8.5 12 13l9-4.5M12 13v7"/>',
        user: '<circle cx="12" cy="8" r="3.6"/><path d="M4.5 20a7.5 7.5 0 0 1 15 0"/>',
        card: '<rect x="2.5" y="5" width="19" height="14" rx="2.6"/><path d="M2.5 10h19"/>',
        phone: '<path d="M6 3.5h3l1.6 4-2 1.4a12 12 0 0 0 5.5 5.5l1.4-2 4 1.6v3a1.6 1.6 0 0 1-1.8 1.6C10.6 18.2 5.8 13.4 4.4 5.3A1.6 1.6 0 0 1 6 3.5z"/>',
        cal: '<rect x="3.5" y="5" width="17" height="15" rx="2.4"/><path d="M3.5 10h17M8 3.5v3M16 3.5v3"/>',
        nav: '<path d="M12 3 20 20l-8-4-8 4z"/>',
        info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
        check: '<circle cx="12" cy="12" r="9"/><path d="m8.5 12.5 2.3 2.3 4.7-5"/>'
      };

      function svg(d) {
        return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
               'stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' + d + '</svg>';
      }
      function el(tag, cls, txt) {
        var n = document.createElement(tag);
        if (cls) n.className = cls;
        if (txt !== undefined && txt !== null) n.textContent = txt;
        return n;
      }
      function norm(s) {
        var t = (s || '').replace(/\\u00a0/g, ' ').trim();
        if (t.normalize) t = t.normalize('NFD').replace(/[\\u0300-\\u036f]/g, '');
        return t.toLowerCase().replace(/[\\s:.]+\$/, '').replace(/\\s+/g, ' ').trim();
      }
      function txt(node) {
        return (node ? (node.textContent || '') : '').replace(/\\u00a0/g, ' ').replace(/\\s+/g, ' ').trim();
      }
      function vacio(v) {
        var t = (v || '').trim();
        return t === '' || t === '-' || t === '--' || t === 'null' || t === 'undefined';
      }

      // ---- 1. Enlaces funcionales: se MUEVEN, nunca se recrean ----
      var aWaze = src.querySelector('a[href*="waze"]');
      var aMaps = src.querySelector('a[href*="google.com/maps"], a[href*="maps.google"], a[href*="maps.app"]');
      var aTel = src.querySelector('a[href^="tel:"]');

      // ---- 2. Pares etiqueta/valor del HTML legacy ----
      var pares = [];
      var usados = [];
      Array.prototype.forEach.call(src.querySelectorAll('tr'), function (tr) {
        var celdas = tr.querySelectorAll('td, th');
        // El backend mete DOS pares en una misma fila (p. ej. "Total \$" y
        // "F.Pago"), así que se recorre de a dos celdas en vez de tomar solo
        // la primera pareja.
        if (celdas.length >= 2 && celdas.length % 2 === 0) {
          for (var i = 0; i + 1 < celdas.length; i += 2) {
            pares.push({ k: norm(txt(celdas[i])), v: txt(celdas[i + 1]), nodo: celdas[i + 1] });
          }
        } else if (celdas.length >= 2) {
          pares.push({ k: norm(txt(celdas[0])), v: txt(celdas[1]), nodo: celdas[1] });
        } else if (celdas.length === 1) {
          var t = txt(celdas[0]);
          var m = t.match(/^([^:]{2,30}):\\s*(.*)\$/);
          if (m) pares.push({ k: norm(m[1]), v: m[2].trim(), nodo: celdas[0] });
        }
      });
      if (!pares.length) {
        Array.prototype.forEach.call(src.querySelectorAll('p, div, li, span'), function (n) {
          if (n.children.length) return;
          var t = txt(n);
          var m = t.match(/^([^:]{2,30}):\\s*(.+)\$/);
          if (m) pares.push({ k: norm(m[1]), v: m[2].trim(), nodo: n });
        });
      }

      function tomar(claves) {
        for (var i = 0; i < pares.length; i++) {
          if (usados.indexOf(i) !== -1) continue;
          for (var j = 0; j < claves.length; j++) {
            if (pares[i].k === claves[j]) { usados.push(i); return pares[i]; }
          }
        }
        return null;
      }
      function todos(claves) {
        var out = [];
        for (var i = 0; i < pares.length; i++) {
          if (usados.indexOf(i) !== -1) continue;
          for (var j = 0; j < claves.length; j++) {
            if (pares[i].k === claves[j]) { usados.push(i); out.push(pares[i]); break; }
          }
        }
        return out;
      }
      function val(p) { return p ? p.v : ''; }

      var direccion = tomar(['direccion', 'dir']);
      var esquina = tomar(['esquina1', 'esquina', 'esquina 1']);
      var esquina2 = tomar(['esquina2', 'esquina 2']);
      var obsDir = tomar(['obs', 'observaciones']);
      var servicio = tomar(['servicio', 'tipo de servicio']);
      var fecha = tomar(['fecha']);
      var desde = tomar(['desde hora', 'desde', 'hora desde']);
      var hasta = tomar(['hasta', 'hasta hora', 'hora hasta']);
      var obsPedido = tomar(['obs pedido', 'observaciones del pedido']);
      var asignado = tomar(['asignado', 'hora asignado', 'asignacion']);
      var finalizado = tomar(['finalizado', 'hora finalizado', 'entregado']);
      var estadoPed = tomar(['estado del pedido', 'estado']);
      var productos = todos(['producto', 'productos', 'articulo', 'descripcion']);
      var cantidades = todos(['cantidad', 'cant']);
      var cliente = tomar(['cliente', 'nombre', 'razon social']);
      var tel = tomar(['tel', 'telefono', 'celular', 'contacto']);
      var obsCliente = tomar(['obs cliente', 'observaciones del cliente']);
      var total = tomar(['total \$', 'total', 'importe', 'monto']);
      var pago = tomar(['f.pago', 'fpago', 'forma de pago', 'f pago', 'pago']);
      var obsPago = tomar(['obs fpago', 'obs f.pago', 'obs pago']);
      tomar(['pedido', 'nro', 'nro pedido', 'numero de pedido']); // ya va en el header
      tomar(['mapas', 'mapa', 'navegacion']);              // los enlaces ya se movieron

      function card(icono, titulo) {
        var c = el('section', 'card');
        var h = el('div', 'head');
        var i = el('div', 'ico');
        i.innerHTML = svg(icono);
        h.appendChild(i);
        h.appendChild(el('div', 'title', titulo));
        c.appendChild(h);
        return c;
      }
      function chip(icono, rotulo, valor) {
        var c = el('div', 'chip');
        var i = document.createElement('span');
        i.innerHTML = svg(icono);
        c.appendChild(i.firstChild);
        var w = el('div', 'grow');
        w.appendChild(el('span', 'chip-lb', rotulo));
        w.appendChild(el('div', 'chip-vl', valor));
        c.appendChild(w);
        return c;
      }
      function nota(texto) {
        var n = el('div', 'nota');
        n.appendChild(el('span', null, texto));
        return n;
      }
      /// El backend manda producto y cantidad en el MISMO texto
      /// ("GLP Envasado de 13 Kg, Cantidad:2"), así que se separan acá.
      function partirProducto(v) {
        var m = v.match(/^(.*?),?\\s*cantidad\\s*:\\s*(.*)\$/i);
        if (m) return { nombre: m[1].replace(/,\\s*\$/, '').trim(), cant: m[2].trim() };
        return { nombre: v.trim(), cant: '' };
      }
      function botonMapa(a, icono, rotulo) {
        a.textContent = '';
        var i = document.createElement('span');
        i.innerHTML = svg(icono);
        a.appendChild(i.firstChild);
        a.appendChild(el('span', null, rotulo));
        return a;
      }

      var hecho = 0;

      // El backend repite la observación de la dirección DENTRO del texto de
      // la dirección ("... - Obs Dir: CASA VERDE") y además como fila "Obs".
      // Se recorta del texto y se muestra una sola vez, como nota.
      var dirTxt = val(direccion);
      var mObs = dirTxt.match(/^(.*?)\\s*-?\\s*Obs\\.?\\s*Dir\\s*:\\s*(.+)\$/i);
      if (mObs) {
        dirTxt = mObs[1].replace(/[\\s,\\-]+\$/, '').trim();
        if (!obsDir || vacio(val(obsDir))) obsDir = { v: mObs[2].trim() };
      }

      // Botón de llamar: va ARRIBA, junto a la dirección, porque es lo que el
      // repartidor necesita al instante. Se conserva el <a> original si vino.
      var botonTel = null;
      var numero = val(tel);
      if (aTel) {
        aTel.className = 'act';
        botonMapa(aTel, I.phone, txt(aTel) || numero || 'Llamar');
        botonTel = aTel;
      } else if (!vacio(numero)) {
        botonTel = document.createElement('a');
        botonTel.className = 'act';
        botonTel.setAttribute('href', 'tel:' + numero.replace(/[^0-9+]/g, ''));
        botonMapa(botonTel, I.phone, numero);
      }

      // ENTREGA
      if (!vacio(dirTxt) || aWaze || aMaps || botonTel) {
        var c1 = card(I.pin, 'Entrega');
        if (!vacio(dirTxt)) c1.appendChild(el('div', 'addr', dirTxt));
        var refs = [];
        if (esquina && !vacio(val(esquina))) refs.push('Esquina: ' + val(esquina));
        if (esquina2 && !vacio(val(esquina2))) refs.push('y ' + val(esquina2));
        if (refs.length) c1.appendChild(el('div', 'sub', refs.join(' ')));
        if (obsDir && !vacio(val(obsDir))) c1.appendChild(nota(val(obsDir)));
        if (aWaze || aMaps || botonTel) {
          var g = el('div', 'maps');
          if (botonTel) g.appendChild(botonTel);
          if (aWaze) g.appendChild(botonMapa(aWaze, I.nav, 'Waze'));
          if (aMaps) g.appendChild(botonMapa(aMaps, I.pin, 'Maps'));
          var n = g.children.length;
          g.style.gridTemplateColumns = n === 1 ? '1fr' : (n === 2 ? '1fr 1fr' : '1.35fr 1fr 1fr');
          c1.appendChild(g);
        }
        app.appendChild(c1); hecho++;
      }

      // SERVICIO Y HORARIO
      if (!vacio(val(servicio)) || !vacio(val(fecha)) || !vacio(val(desde)) ||
          (asignado && !vacio(val(asignado))) || (finalizado && !vacio(val(finalizado)))) {
        var c2 = card(I.clock, 'Servicio y horario');
        if (!vacio(val(servicio))) c2.appendChild(el('div', 'main-val', val(servicio)));
        var ch = el('div', 'chips');
        if (!vacio(val(fecha))) ch.appendChild(chip(I.cal, 'Fecha', val(fecha)));
        var rango = '';
        if (!vacio(val(desde)) && !vacio(val(hasta))) rango = val(desde) + ' - ' + val(hasta);
        else if (!vacio(val(desde))) rango = 'desde ' + val(desde);
        else if (!vacio(val(hasta))) rango = 'hasta ' + val(hasta);
        if (rango) ch.appendChild(chip(I.clock, 'Horario', rango));
        if (asignado && !vacio(val(asignado))) ch.appendChild(chip(I.user, 'Asignado', val(asignado)));
        if (finalizado && !vacio(val(finalizado))) ch.appendChild(chip(I.check, 'Finalizado', val(finalizado)));
        if (estadoPed && !vacio(val(estadoPed))) ch.appendChild(chip(I.info, 'Estado', val(estadoPed)));
        if (ch.children.length) c2.appendChild(ch);
        if (obsPedido && !vacio(val(obsPedido))) c2.appendChild(nota(val(obsPedido)));
        app.appendChild(c2); hecho++;
      }

      // PRODUCTO(S)
      var items = [];
      productos.forEach(function (p, idx) {
        var d = partirProducto(p.v);
        if (!d.cant && cantidades[idx] && !vacio(cantidades[idx].v)) d.cant = cantidades[idx].v;
        if (!vacio(d.nombre)) items.push(d);
      });
      if (items.length) {
        var c3 = card(I.box, items.length > 1 ? 'Productos' : 'Producto');
        items.forEach(function (d) {
          var f = el('div', 'prod');
          f.appendChild(el('div', 'grow main-val', d.nombre));
          if (!vacio(d.cant)) {
            f.appendChild(el('span', 'badge',
              items.length > 1 ? 'x' + d.cant : 'Cantidad: ' + d.cant));
          }
          c3.appendChild(f);
        });
        app.appendChild(c3); hecho++;
      }

      // CLIENTE (nombre y observaciones; el teléfono ya va arriba, en Entrega)
      if (!vacio(val(cliente)) || (obsCliente && !vacio(val(obsCliente)))) {
        var c4 = card(I.user, 'Cliente');
        if (!vacio(val(cliente))) c4.appendChild(el('div', 'main-val', val(cliente)));
        if (obsCliente && !vacio(val(obsCliente))) c4.appendChild(nota(val(obsCliente)));
        app.appendChild(c4); hecho++;
      }

      // PAGO
      if (!vacio(val(pago)) || !vacio(val(total))) {
        var c5 = card(I.card, 'Pago');
        var r2 = el('div', 'row');
        r2.appendChild(el('div', 'grow main-val', vacio(val(pago)) ? '' : val(pago)));
        if (!vacio(val(total))) {
          var t = el('div');
          t.appendChild(el('div', 'tot-lb', 'Total'));
          var n = val(total).replace(/\\s+/g, '');
          t.appendChild(el('div', 'tot-vl', n.charAt(0) === '\$' ? n : '\$ ' + n));
          r2.appendChild(t);
        }
        c5.appendChild(r2);
        if (obsPago && !vacio(val(obsPago))) c5.appendChild(el('div', 'detalle', val(obsPago)));
        app.appendChild(c5); hecho++;
      }

      // CUALQUIER OTRO DATO QUE MANDE EL BACKEND (no se pierde nada)
      var sobrantes = [];
      for (var i = 0; i < pares.length; i++) {
        if (usados.indexOf(i) !== -1) continue;
        if (vacio(pares[i].v) || !pares[i].k) continue;
        sobrantes.push(pares[i]);
      }
      if (sobrantes.length) {
        var c6 = card(I.info, 'Otros datos');
        sobrantes.forEach(function (p) {
          var f = el('div', 'extra');
          var k = p.k.charAt(0).toUpperCase() + p.k.slice(1);
          f.appendChild(el('span', 'k', k));
          f.appendChild(el('span', 'v', p.v));
          c6.appendChild(f);
        });
        app.appendChild(c6); hecho++;
      }

      // Sin nada reconocible: se muestra el original antes que una pantalla vacía
      if (!hecho) {
        src.hidden = false;
      } else {
        src.parentNode.removeChild(src);
      }
    })();
    </script>
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
        // ✅ VALIDAR RESPUESTA DEL SERVICIO (OK: 99 = sesión inactiva)
        int? okCode;
        String? message;

        if (response is Map<String, dynamic>) {
          okCode = response['OK'] as int?;
          message = response['message'] as String?;
        }

        print("🔍 [RESPONSE] OK: $okCode | Message: $message");

        // Verificar si la sesión está inactiva (OK: 99)
        if (okCode == 99) {
          print("❌ [SESSION] Sesión inactiva detectada (OK: 99)");

          // Cerrar el loading dialog
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }

          // Mostrar mensaje de error
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'No se pudo validar la sesión. La aplicación se cerrará.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );

          // Limpiar sesión y volver al login
          await Future.delayed(Duration(seconds: 2));

          try {
            var sessionBox = await Hive.openBox('sessionBox');
            await sessionBox.clear();
            print("🧹 [SESSION] Sesión limpiada por sesión inactiva");
          } catch (e) {
            print("⚠️ [SESSION] Error limpiando sesión: $e");
          }

          // Navegar al login (reemplazar toda la pila de navegación)
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
          return;
        }

        // Si OK != 99, continuar con flujo normal
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

  /// Etiqueta y color del estado del pedido. `EstadoNro` 1 = pendiente y
  /// 2 = entregado (mismo criterio que V2Data); cualquier otro valor se
  /// muestra tal cual en gris en vez de inventarle un nombre.
  ({String texto, Color fondo, Color texto2}) get _estadoBadge {
    switch (widget.estadoNro) {
      case 1:
        return (
          texto: 'Pendiente',
          fondo: const Color(0xFFF2C315),
          texto2: const Color(0xFF4A3A00)
        );
      case 2:
        return (
          texto: 'Entregado',
          fondo: const Color(0xFF82C63F),
          texto2: const Color(0xFF12340A)
        );
      default:
        return (
          texto: 'Estado ${widget.estadoNro}',
          fondo: const Color(0xFFCBD8E4),
          texto2: const Color(0xFF23384C)
        );
    }
  }

  Widget _buildHeader() {
    final badge = _estadoBadge;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF073B66), Color(0xFF087CC1)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Área táctil de 44px aunque el círculo se vea de 38
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 21),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Detalle del pedido',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Pedido #${widget.codPedido}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.82),
                              fontSize: 13,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: badge.fondo,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            badge.texto,
                            style: TextStyle(
                              color: badge.texto2,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: WebViewWidget(controller: _controller)),
          if (widget.estadoNro == 1) // Show button only if estadoNro is 1
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF4F7FA),
                border: Border(top: BorderSide(color: Color(0xFFE3EAF1))),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.check, color: Colors.white),
                      label: Text(
                        'Finalizar pedido',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 52),
                        backgroundColor: const Color(0xFF82C63F),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      onPressed: _iniciarFlujoFinalizacion,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 🧭 Flujo de finalización (quick check → validación completa → diálogo).
  /// Extraído del botón "Finalizar Pedido" para poder dispararlo también
  /// desde "Devolver pedido" del diseño nuevo (autoFinalize).
  Future<void> _iniciarFlujoFinalizacion() async {
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
  }
}
