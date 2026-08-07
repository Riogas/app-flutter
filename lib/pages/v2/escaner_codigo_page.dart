import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/modo_ingreso_codigo.dart';
import '../../services/proteccion_pantalla.dart';
import 'v2_theme.dart';

/// 📷 Escaneo del código de la promoción (QR o código de barras).
///
/// Devuelve por `Navigator.pop` el texto leído, o `null` si el usuario salió
/// sin escanear. NO interpreta el contenido: quien decide si el código sirve
/// es `promociones/ValidarPromo`.
///
/// El permiso de cámara se pide ACÁ, antes de montar el visor, para poder
/// explicar el motivo y ofrecer los ajustes del sistema si quedó denegado
/// para siempre (si se dejara al plugin, el usuario vería una pantalla negra).
class EscanerCodigoPage extends StatefulWidget {
  final ModoIngresoCodigo modo;

  /// Nombre de la promoción, para que el usuario sepa qué está escaneando.
  final String promo;

  const EscanerCodigoPage({
    super.key,
    required this.modo,
    this.promo = '',
  });

  @override
  State<EscanerCodigoPage> createState() => _EscanerCodigoPageState();
}

enum _EstadoPermiso { consultando, concedido, denegado, bloqueado }

class _EscanerCodigoPageState extends State<EscanerCodigoPage>
    with WidgetsBindingObserver {
  static const List<BarcodeFormat> _formatosQr = [BarcodeFormat.qrCode];

  /// Los 1D habituales en cupones/tickets. Se restringe a propósito: cuanto
  /// menos formatos, más rápido y menos lecturas cruzadas.
  static const List<BarcodeFormat> _formatosBarras = [
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.code93,
    BarcodeFormat.codabar,
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.itf,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
  ];

  MobileScannerController? _controller;
  _EstadoPermiso _permiso = _EstadoPermiso.consultando;

  /// `onDetect` puede disparar varias veces antes de que se desmonte la
  /// pantalla: sin esta guarda se harían varios pop y se cerraría Promos.
  bool _yaDevolvio = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 🔒 El visor muestra el código del cliente: no se puede capturar.
    ProteccionPantalla.adquirir();
    _pedirPermiso();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ProteccionPantalla.liberar();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Android puede perder el FLAG_SECURE al volver de background.
      ProteccionPantalla.reaplicar();
      // Si el usuario fue a Ajustes a conceder el permiso, reintentar.
      if (_permiso != _EstadoPermiso.concedido) _pedirPermiso();
    }
  }

  Future<void> _pedirPermiso() async {
    var estado = await Permission.camera.status;
    if (estado.isDenied) estado = await Permission.camera.request();
    if (!mounted) return;

    final nuevo = estado.isGranted || estado.isLimited
        ? _EstadoPermiso.concedido
        : (estado.isPermanentlyDenied || estado.isRestricted)
            ? _EstadoPermiso.bloqueado
            : _EstadoPermiso.denegado;

    if (nuevo == _EstadoPermiso.concedido && _controller == null) {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        formats: widget.modo == ModoIngresoCodigo.barras
            ? _formatosBarras
            : _formatosQr,
        facing: CameraFacing.back,
      );
    }
    if (nuevo != _permiso) setState(() => _permiso = nuevo);
  }

  void _onDetect(BarcodeCapture captura) {
    if (_yaDevolvio) return;

    for (final b in captura.barcodes) {
      final codigo = ModoIngresoCodigo.normalizarLectura(
        b.rawValue ?? b.displayValue,
      );
      if (codigo == null) continue;

      _yaDevolvio = true;
      HapticFeedback.mediumImpact();
      _controller?.stop();
      if (mounted) Navigator.of(context).pop(codigo);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.modo.tituloEscaner,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          if (_permiso == _EstadoPermiso.concedido && _controller != null)
            _botonLinterna(),
        ],
      ),
      body: switch (_permiso) {
        _EstadoPermiso.consultando => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        _EstadoPermiso.concedido => _visor(),
        _EstadoPermiso.denegado => _sinPermiso(bloqueado: false),
        _EstadoPermiso.bloqueado => _sinPermiso(bloqueado: true),
      },
    );
  }

  Widget _botonLinterna() {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _controller!,
      builder: (context, estado, _) {
        if (estado.torchState == TorchState.unavailable) {
          return const SizedBox.shrink();
        }
        final prendida = estado.torchState == TorchState.on;
        return IconButton(
          tooltip: prendida ? 'Apagar linterna' : 'Encender linterna',
          onPressed: () => _controller?.toggleTorch(),
          icon: Icon(
            prendida ? Icons.flash_on : Icons.flash_off,
            color: prendida ? V2Colors.celeste : Colors.white,
          ),
        );
      },
    );
  }

  Widget _visor() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error, child) => _mensajeCentral(
            icono: Icons.videocam_off_outlined,
            titulo: 'No se pudo abrir la cámara',
            detalle: error.errorDetails?.message ??
                'Cerrá otras apps que la estén usando y volvé a intentar.',
          ),
        ),
        _recorte(),
        Positioned(
          left: 24,
          right: 24,
          bottom: 48,
          child: Column(
            children: [
              Text(
                widget.modo.instruccion,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (widget.promo.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  widget.promo,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 13.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Marco guía. El alto es menor en barras porque el símbolo es apaisado.
  Widget _recorte() {
    final esBarras = widget.modo == ModoIngresoCodigo.barras;
    return IgnorePointer(
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ancho = constraints.maxWidth * 0.78;
            return Container(
              width: ancho,
              height: esBarras ? ancho * 0.55 : ancho,
              decoration: BoxDecoration(
                border: Border.all(color: V2Colors.celeste, width: 3),
                borderRadius: BorderRadius.circular(18),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sinPermiso({required bool bloqueado}) {
    return _mensajeCentral(
      icono: Icons.no_photography_outlined,
      titulo: 'Necesitamos la cámara',
      detalle: bloqueado
          ? 'El permiso está denegado. Activá "Cámara" en los ajustes de la app para poder escanear.'
          : 'Sin el permiso de cámara no se puede escanear el código de la promoción.',
      accion: SizedBox(
        height: 48,
        child: ElevatedButton.icon(
          onPressed: bloqueado ? openAppSettings : _pedirPermiso,
          style: ElevatedButton.styleFrom(
            backgroundColor: V2Colors.accion,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: Icon(bloqueado ? Icons.settings : Icons.camera_alt_outlined),
          label: Text(bloqueado ? 'Abrir ajustes' : 'Permitir cámara'),
        ),
      ),
    );
  }

  Widget _mensajeCentral({
    required IconData icono,
    required String titulo,
    required String detalle,
    Widget? accion,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (accion != null) ...[
              const SizedBox(height: 20),
              accion,
            ],
          ],
        ),
      ),
    );
  }
}
