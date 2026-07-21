import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import '../../services/beneficios_service.dart';
import '../../services/persistent_stream_manager.dart';
import 'v2_data.dart';
import 'v2_header.dart';
import 'v2_theme.dart';

/// 🎁 Promociones: validación y consumo de beneficios del cliente
/// (Antel, Claro, OCA Metros, etc.).
///
/// La configuración de cada promoción viene de la colección Firestore
/// top-level `Promociones` (GeneXus): labels dinámicos por campo, requeridos,
/// vigencia, escenarios habilitados y labels de botones.
/// Las APIs de validación/PIN/consumo están SIMULADAS en BeneficiosService
/// hasta que existan los endpoints GeneXus.
class PromocionesPage extends StatefulWidget {
  final ValueNotifier<int> messageCountNotifier;
  final Future<void> Function(BuildContext context) onEstadoTap;

  const PromocionesPage({
    super.key,
    required this.messageCountNotifier,
    required this.onEstadoTap,
  });

  @override
  State<PromocionesPage> createState() => _PromocionesPageState();
}

enum _Fase {
  inicial,
  validando,
  beneficioOk,
  pendientePin,
  error,
  consumiendo,
  consumido,
}

class _PromocionesPageState extends State<PromocionesPage> {
  final _streamManager = PersistentStreamManager();
  final _service = BeneficiosService();

  DocumentSnapshot? _promoDoc;
  final _codigoCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _auxCtrl = TextEditingController();

  _Fase _fase = _Fase.inicial;
  String _mensajeResultado = '';
  String? _codigoAutorizacion;
  DateTime? _fechaConsumo;

  @override
  void initState() {
    super.initState();
    _marcarVistas();
    // Refrescar habilitación del botón Validar al tipear
    for (final c in [_codigoCtrl, _telCtrl, _nombreCtrl, _auxCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _telCtrl.dispose();
    _nombreCtrl.dispose();
    _auxCtrl.dispose();
    super.dispose();
  }

  /// Apaga el badge del tab (misma caja que antes)
  Future<void> _marcarVistas() async {
    try {
      final box = await Hive.openBox('promocionesVistasBox');
      for (final doc in _streamManager.promocionesNotifier.value) {
        await box.put(doc.id, true);
      }
    } catch (_) {}
  }

  // ── Config de la promo seleccionada ─────────────────────────────────────

  Map<String, dynamic> get _promo =>
      (_promoDoc?.data() as Map<String, dynamic>?) ?? {};

  String _label(String? campo) => (_promo[campo ?? ''] ?? '').toString().trim();

  bool get _tieneCodigo => _label('LabelCodCliente').isNotEmpty;
  bool get _tieneTel => _label('LabelCodTelCliente').isNotEmpty;
  bool get _tieneNombre => _label('LabelNomCliente').isNotEmpty;
  bool get _tieneAux => _label('LabelAuxIn1').isNotEmpty;

  bool _esRequerido(String campoReq, {required bool porDefecto}) {
    final r = _label(campoReq).toLowerCase();
    if (r.isEmpty) return porDefecto;
    return r == 'requerido';
  }

  bool get _codigoReq => _esRequerido('ReqCodCliente', porDefecto: true);
  bool get _telReq => _esRequerido('ReqCodTelCliente', porDefecto: true);
  bool get _nombreReq => _esRequerido('ReqNomCliente', porDefecto: false);
  bool get _auxReq => _esRequerido('ReqAuxIn1', porDefecto: false);

  bool get _formBloqueado =>
      _fase == _Fase.validando ||
      _fase == _Fase.consumiendo ||
      _fase == _Fase.consumido;

  bool get _puedeValidar {
    if (_promoDoc == null || _formBloqueado) return false;
    if (_tieneCodigo && _codigoReq && _codigoCtrl.text.trim().isEmpty) {
      return false;
    }
    if (_tieneTel && _telReq) {
      final tel = _telCtrl.text.replaceAll(RegExp(r'\D'), '');
      if (tel.length < 8) return false;
    }
    if (_tieneNombre && _nombreReq && _nombreCtrl.text.trim().isEmpty) {
      return false;
    }
    if (_tieneAux && _auxReq && _auxCtrl.text.trim().isEmpty) return false;
    return true;
  }

  // ── Acciones ────────────────────────────────────────────────────────────

  void _seleccionarPromo(DocumentSnapshot doc) {
    setState(() {
      _promoDoc = doc;
      // Al cambiar de promoción se limpian datos y resultados anteriores
      _codigoCtrl.clear();
      _telCtrl.clear();
      _nombreCtrl.clear();
      _auxCtrl.clear();
      _fase = _Fase.inicial;
      _mensajeResultado = '';
      _codigoAutorizacion = null;
      _fechaConsumo = null;
    });
  }

  Future<Map<String, String>> _identidad() async {
    final box = await Hive.openBox('sessionBox');
    return {
      'movil': box.get('movil', defaultValue: '').toString(),
      'usuario': box.get('username', defaultValue: '').toString(),
      'escenario': box.get('escenario', defaultValue: '').toString(),
    };
  }

  Future<void> _validar() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _fase = _Fase.validando;
      _mensajeResultado = '';
    });

    final ident = await _identidad();
    final res = await _service.validar(
      promoIdInterno:
          int.tryParse(_promo['IdInterno']?.toString() ?? '') ?? 0,
      promoNombre: _label('NombreCombo'),
      codigo: _tieneCodigo ? _codigoCtrl.text.trim() : null,
      telefono: _tieneTel ? _telCtrl.text.trim() : null,
      nombre: _tieneNombre ? _nombreCtrl.text.trim() : null,
      auxIn1: _tieneAux ? _auxCtrl.text.trim() : null,
      movil: ident['movil']!,
      usuario: ident['usuario']!,
      escenario: ident['escenario']!,
    );

    if (!mounted) return;

    if (!res.ok) {
      setState(() {
        _fase = _Fase.error;
        _mensajeResultado = res.mensaje;
      });
      return;
    }

    if (res.requierePin) {
      setState(() {
        _fase = _Fase.pendientePin;
        _mensajeResultado = res.mensaje;
      });
      _abrirPinSheet();
      return;
    }

    setState(() {
      _fase = _Fase.beneficioOk;
      _mensajeResultado = res.mensaje;
    });
  }

  Future<void> _abrirPinSheet() async {
    final res = await showModalBottomSheet<BeneficioPinResultado>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PinSheet(telefono: _telCtrl.text.trim()),
    );

    if (!mounted || res == null) return; // canceló: sigue pendiente de PIN

    if (res.ok) {
      setState(() {
        _fase = _Fase.beneficioOk;
        _mensajeResultado = res.mensaje;
      });
    } else if (res.expirado) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.mensaje)),
      );
    }
  }

  Future<void> _consumir() async {
    final labelConsumir = _label('LabelBotonConsumir').isNotEmpty
        ? _label('LabelBotonConsumir')
        : 'Consumir beneficio';

    final cliente = _nombreCtrl.text.trim().isNotEmpty
        ? _nombreCtrl.text.trim()
        : _telCtrl.text.trim();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirmar consumo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Confirmás que querés consumir este beneficio?'),
            const SizedBox(height: 14),
            _lineaConfirm('Promoción', _label('NombreCombo')),
            if (cliente.isNotEmpty) _lineaConfirm('Cliente', cliente),
            _lineaConfirm('Beneficio', _mensajeResultado),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: V2Colors.verde,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(labelConsumir),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _fase = _Fase.consumiendo);

    final ident = await _identidad();
    final res = await _service.consumir(
      promoIdInterno:
          int.tryParse(_promo['IdInterno']?.toString() ?? '') ?? 0,
      promoNombre: _label('NombreCombo'),
      codigo: _codigoCtrl.text.trim(),
      telefono: _telCtrl.text.trim(),
      movil: ident['movil']!,
      usuario: ident['usuario']!,
      escenario: ident['escenario']!,
    );

    if (!mounted) return;
    setState(() {
      if (res.ok) {
        _fase = _Fase.consumido;
        _codigoAutorizacion = res.codigoAutorizacion;
        _fechaConsumo = res.fechaHora;
      } else {
        _fase = _Fase.error;
        _mensajeResultado = res.mensaje;
      }
    });
  }

  void _nuevaValidacion() {
    setState(() {
      _codigoCtrl.clear();
      _telCtrl.clear();
      _nombreCtrl.clear();
      _auxCtrl.clear();
      _fase = _Fase.inicial;
      _mensajeResultado = '';
      _codigoAutorizacion = null;
      _fechaConsumo = null;
    });
  }

  Widget _lineaConfirm(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$k: ',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: V2Colors.textoPrimario),
            ),
            TextSpan(
              text: v,
              style: const TextStyle(color: V2Colors.textoSecundario),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 13.5),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: V2Colors.fondo,
      child: ValueListenableBuilder<List<DocumentSnapshot>>(
        valueListenable: _streamManager.promocionesNotifier,
        builder: (context, promos, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _marcarVistas());

          // Si la promo seleccionada dejó de estar vigente, deseleccionar
          if (_promoDoc != null && !promos.any((d) => d.id == _promoDoc!.id)) {
            _promoDoc = null;
          }

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                V2Header(
                  messageCountNotifier: widget.messageCountNotifier,
                  onEstadoTap: widget.onEstadoTap,
                  titulo: 'Promos',
                  subtitulo: 'Validá beneficios del cliente antes de consumirlos',
                  height: 168,
                  bottomSpace: 40,
                ),
                Transform.translate(
                  offset: const Offset(0, -28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        if (promos.isEmpty)
                          _sinPromos()
                        else
                          _formCard(promos),
                        const SizedBox(height: 12),
                        ..._resultado(),
                        const SizedBox(height: 8),
                        const Text(
                          '⚙️ Modo demostración: validación con servicios simulados',
                          style: TextStyle(
                            color: V2Colors.textoSecundario,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 70),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sinPromos() {
    return V2Card(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              color: V2Colors.celesteClaro,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.card_giftcard,
                color: V2Colors.accion, size: 44),
          ),
          const SizedBox(height: 16),
          const Text(
            'No hay promociones vigentes',
            style: TextStyle(
              color: V2Colors.textoPrimario,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Cuando haya promociones activas vas a poder\nvalidar beneficios de clientes acá.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: V2Colors.textoSecundario,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ── Formulario ──────────────────────────────────────────────────────────

  Widget _formCard(List<DocumentSnapshot> promos) {
    final nombres = promos
        .map((d) =>
            ((d.data() as Map<String, dynamic>?)?['NombreCombo'] ?? '')
                .toString())
        .where((n) => n.isNotEmpty)
        .toList();

    final nota = _label('NotaAnteriorAlBotonValidar');
    final labelValidar = _label('LabelBotonValidar').isNotEmpty
        ? _label('LabelBotonValidar')
        : 'Validar';

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelCampo('Promoción', requerido: true),
        const SizedBox(height: 6),
        _comboPromos(promos),
        const SizedBox(height: 4),
        Text(
          nombres.join(', '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: V2Colors.textoSecundario, fontSize: 11.5),
        ),
        if (_promoDoc != null) ...[
          if (_tieneCodigo) ...[
            const SizedBox(height: 16),
            _labelCampo(_label('LabelCodCliente'), requerido: _codigoReq),
            const SizedBox(height: 6),
            _campoTexto(
              controller: _codigoCtrl,
              hint: 'Ingresá el código de la promoción',
              icon: Icons.qr_code_2,
            ),
          ],
          if (_tieneTel) ...[
            const SizedBox(height: 14),
            _labelCampo(_label('LabelCodTelCliente'), requerido: _telReq),
            const SizedBox(height: 6),
            _campoTexto(
              controller: _telCtrl,
              hint: 'Ingresá el teléfono del cliente',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              helper: _label('TelValores').isNotEmpty
                  ? _label('TelValores')
                  : null,
            ),
          ],
          if (_tieneNombre) ...[
            const SizedBox(height: 14),
            _labelCampo(_label('LabelNomCliente'), requerido: _nombreReq),
            const SizedBox(height: 6),
            _campoTexto(
              controller: _nombreCtrl,
              hint: 'Nombre y apellido del cliente',
              icon: Icons.person_outline,
              textCapitalization: TextCapitalization.words,
            ),
          ],
          if (_tieneAux) ...[
            const SizedBox(height: 14),
            _labelCampo(_label('LabelAuxIn1'), requerido: _auxReq),
            const SizedBox(height: 6),
            _campoTexto(
              controller: _auxCtrl,
              hint: 'Agregá cualquier observación relevante',
              icon: Icons.notes_outlined,
              maxLines: 3,
              maxLength: 120,
            ),
          ],
          if (nota.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: V2Colors.naranja.withOpacity(0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      color: V2Colors.naranja, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nota,
                      style: const TextStyle(
                        color: V2Colors.textoPrimario,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _puedeValidar ? _validar : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: V2Colors.accion,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    V2Colors.accion.withOpacity(0.35),
                disabledForegroundColor: Colors.white70,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                textStyle: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: _fase == _Fase.validando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Icon(Icons.verified_user_outlined, size: 21),
              label: Text(
                  _fase == _Fase.validando ? 'Validando...' : labelValidar),
            ),
          ),
        ],
      ],
    );

    return V2Card(
      shadows: V2Shadows.cardElevada,
      child: _formBloqueado && _fase == _Fase.consumido
          ? Opacity(opacity: 0.55, child: IgnorePointer(child: form))
          : AbsorbPointer(
              absorbing: _fase == _Fase.validando || _fase == _Fase.consumiendo,
              child: form,
            ),
    );
  }

  Widget _comboPromos(List<DocumentSnapshot> promos) {
    final seleccionado = _label('NombreCombo');
    return InkWell(
      onTap: _formBloqueado
          ? null
          : () async {
              final doc = await showModalBottomSheet<DocumentSnapshot>(
                context: context,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
                ),
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          'Elegí la promoción',
                          style: TextStyle(
                            color: V2Colors.textoPrimario,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: promos.length,
                          itemBuilder: (_, i) {
                            final data =
                                promos[i].data() as Map<String, dynamic>;
                            final nombre =
                                (data['NombreCombo'] ?? '').toString();
                            final desc =
                                (data['Descripcion'] ?? '').toString();
                            return ListTile(
                              leading: const Icon(Icons.local_offer_outlined,
                                  color: V2Colors.accion),
                              title: Text(nombre,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle: desc.isNotEmpty && desc != nombre
                                  ? Text(desc)
                                  : null,
                              trailing: _promoDoc?.id == promos[i].id
                                  ? const Icon(Icons.check_circle,
                                      color: V2Colors.verde)
                                  : null,
                              onTap: () => Navigator.pop(ctx, promos[i]),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );
              if (doc != null) _seleccionarPromo(doc);
            },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8FB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: V2Colors.celesteClaro, width: 1.4),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_offer_outlined,
                color: V2Colors.accion, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                seleccionado.isNotEmpty
                    ? seleccionado
                    : 'Seleccioná una promoción',
                style: TextStyle(
                  color: seleccionado.isNotEmpty
                      ? V2Colors.textoPrimario
                      : V2Colors.textoSecundario,
                  fontSize: 15,
                  fontWeight: seleccionado.isNotEmpty
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down,
                color: V2Colors.textoSecundario),
          ],
        ),
      ),
    );
  }

  Widget _labelCampo(String texto, {required bool requerido}) {
    return Row(
      children: [
        Flexible(
          child: Text(
            texto,
            style: const TextStyle(
              color: V2Colors.textoPrimario,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: requerido
                ? V2Colors.rojo.withOpacity(0.10)
                : V2Colors.textoSecundario.withOpacity(0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            requerido ? 'Requerido' : 'Opcional',
            style: TextStyle(
              color: requerido ? V2Colors.rojo : V2Colors.textoSecundario,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _campoTexto({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int maxLines = 1,
    int? maxLength,
    String? helper,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      maxLength: maxLength,
      style: const TextStyle(color: V2Colors.textoPrimario, fontSize: 15),
      cursorColor: V2Colors.accion,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF5F8FB),
        hintText: hint,
        hintStyle:
            const TextStyle(color: V2Colors.textoSecundario, fontSize: 14),
        helperText: helper,
        helperStyle: const TextStyle(
            color: V2Colors.textoSecundario, fontSize: 11.5),
        prefixIcon: Icon(icon, color: V2Colors.textoSecundario, size: 21),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: V2Colors.celesteClaro, width: 1.4),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: V2Colors.accion, width: 1.6),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: V2Colors.celesteClaro, width: 1.4),
        ),
      ),
    );
  }

  // ── Tarjetas de resultado ───────────────────────────────────────────────

  List<Widget> _resultado() {
    final labelConsumir = _label('LabelBotonConsumir').isNotEmpty
        ? _label('LabelBotonConsumir')
        : 'Consumir beneficio';

    switch (_fase) {
      case _Fase.beneficioOk:
        return [
          _cardResultado(
            color: V2Colors.verde,
            fondo: const Color(0xFFE8F5E9),
            icono: Icons.check_circle,
            titulo: 'Beneficio disponible',
            mensaje: _mensajeResultado,
            extra: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _fase == _Fase.consumiendo ? null : _consumir,
                style: ElevatedButton.styleFrom(
                  backgroundColor: V2Colors.verde,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: const Icon(Icons.redeem, size: 20),
                label: Text(labelConsumir),
              ),
            ),
          ),
        ];

      case _Fase.consumiendo:
        return [
          _cardResultado(
            color: V2Colors.verde,
            fondo: const Color(0xFFE8F5E9),
            icono: Icons.hourglass_top,
            titulo: 'Consumiendo beneficio...',
            mensaje: _mensajeResultado,
            extra: const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child:
                    CircularProgressIndicator(color: V2Colors.verde),
              ),
            ),
          ),
        ];

      case _Fase.pendientePin:
        return [
          _cardResultado(
            color: V2Colors.naranja,
            fondo: const Color(0xFFFFF3E0),
            icono: Icons.sms_outlined,
            titulo: 'Resultado de validación',
            mensaje:
                'La promoción requiere validación por PIN.\nSe envió un código SMS al número ingresado.',
            chip: 'Pendiente de PIN',
            extra: Column(
              children: [
                const Text(
                  'Luego de confirmar el PIN se habilitará el consumo del beneficio.',
                  style: TextStyle(
                    color: V2Colors.textoSecundario,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _abrirPinSheet,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: V2Colors.accion,
                      side: const BorderSide(
                          color: V2Colors.accion, width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    icon: const Icon(Icons.pin_outlined, size: 19),
                    label: const Text('Ingresar PIN'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: null, // deshabilitado hasta confirmar PIN
                    style: ElevatedButton.styleFrom(
                      disabledBackgroundColor:
                          V2Colors.verde.withOpacity(0.25),
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    icon: const Icon(Icons.redeem, size: 19),
                    label: Text(labelConsumir),
                  ),
                ),
              ],
            ),
          ),
        ];

      case _Fase.error:
        return [
          _cardResultado(
            color: V2Colors.rojo,
            fondo: const Color(0xFFFDECEA),
            icono: Icons.error_outline,
            titulo: 'No se pudo validar',
            mensaje: _mensajeResultado,
            extra: const Text(
              'Revisá los datos e intentá nuevamente.',
              style: TextStyle(
                color: V2Colors.textoSecundario,
                fontSize: 12.5,
              ),
            ),
          ),
        ];

      case _Fase.consumido:
        return [
          _cardResultado(
            color: V2Colors.verde,
            fondo: const Color(0xFFE8F5E9),
            icono: Icons.verified,
            titulo: 'Beneficio consumido',
            mensaje: 'El beneficio fue utilizado correctamente.',
            extra: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_codigoAutorizacion != null)
                  _lineaConfirm('Autorización', _codigoAutorizacion!),
                if (_fechaConsumo != null)
                  _lineaConfirm(
                    'Fecha',
                    '${_fechaConsumo!.day.toString().padLeft(2, '0')}/${_fechaConsumo!.month.toString().padLeft(2, '0')} ${V2Data.fmtHora(_fechaConsumo!)}',
                  ),
                _lineaConfirm('Promoción', _label('NombreCombo')),
                if (_telCtrl.text.trim().isNotEmpty)
                  _lineaConfirm('Cliente', _telCtrl.text.trim()),
                _lineaConfirm('Beneficio', _mensajeResultado),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _nuevaValidacion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: V2Colors.accion,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('Nueva validación'),
                  ),
                ),
              ],
            ),
          ),
        ];

      case _Fase.inicial:
      case _Fase.validando:
        return [];
    }
  }

  Widget _cardResultado({
    required Color color,
    required Color fondo,
    required IconData icono,
    required String titulo,
    required String mensaje,
    String? chip,
    Widget? extra,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.45), width: 1.4),
        boxShadow: V2Shadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: color, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    color: color,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (chip != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    chip,
                    style: TextStyle(
                      color: color,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            mensaje,
            style: const TextStyle(
              color: V2Colors.textoPrimario,
              fontSize: 14.5,
              height: 1.35,
            ),
          ),
          if (extra != null) ...[
            const SizedBox(height: 14),
            extra,
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 🔐 Bottom sheet de ingreso de PIN
// ─────────────────────────────────────────────────────────────────────────
class _PinSheet extends StatefulWidget {
  final String telefono;

  const _PinSheet({required this.telefono});

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  final List<TextEditingController> _ctrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());

  bool _error = false;
  bool _confirmando = false;
  String _mensajeError = '';
  int _reenvioEn = 30;
  Timer? _reenvioTimer;

  @override
  void initState() {
    super.initState();
    _iniciarCuentaReenvio();
  }

  @override
  void dispose() {
    _reenvioTimer?.cancel();
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _iniciarCuentaReenvio() {
    _reenvioTimer?.cancel();
    setState(() => _reenvioEn = 30);
    _reenvioTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        _reenvioEn--;
        if (_reenvioEn <= 0) t.cancel();
      });
    });
  }

  String get _pin => _ctrls.map((c) => c.text).join();

  String get _telParcial {
    final t = widget.telefono.replaceAll(RegExp(r'\D'), '');
    if (t.length < 6) return widget.telefono;
    return '${t.substring(0, 3)} ${t.substring(3, 6)} ${t.substring(6)}';
  }

  void _onChanged(int i, String v) {
    setState(() => _error = false);
    if (v.length > 1) {
      // 📋 Pegado del código completo
      final digitos = v.replaceAll(RegExp(r'\D'), '');
      for (int j = 0; j < 6; j++) {
        _ctrls[j].text = j < digitos.length ? digitos[j] : '';
      }
      if (digitos.length >= 6) {
        _nodes[5].requestFocus();
      } else if (digitos.isNotEmpty) {
        _nodes[digitos.length.clamp(0, 5)].requestFocus();
      }
      setState(() {});
      return;
    }
    if (v.isNotEmpty && i < 5) {
      _nodes[i + 1].requestFocus();
    } else if (v.isEmpty && i > 0) {
      _nodes[i - 1].requestFocus();
    }
  }

  Future<void> _confirmar() async {
    setState(() {
      _confirmando = true;
      _error = false;
      _mensajeError = '';
    });

    final res = await BeneficiosService().confirmarPin(_pin);
    if (!mounted) return;

    if (res.ok) {
      Navigator.pop(context, res);
      return;
    }

    setState(() {
      _confirmando = false;
      _error = true;
      _mensajeError = res.mensaje;
      if (res.expirado) {
        // expiró: se puede reenviar
        _reenvioEn = 0;
        _reenvioTimer?.cancel();
      }
    });
  }

  Future<void> _reenviar() async {
    await BeneficiosService().reenviarPin();
    if (!mounted) return;
    for (final c in _ctrls) {
      c.clear();
    }
    _nodes[0].requestFocus();
    setState(() {
      _error = false;
      _mensajeError = '';
    });
    _iniciarCuentaReenvio();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Código reenviado por SMS')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: V2Colors.celesteClaro,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 62,
                height: 62,
                decoration: const BoxDecoration(
                  color: V2Colors.celesteClaro,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline,
                    color: V2Colors.accion, size: 30),
              ),
              const SizedBox(height: 14),
              const Text(
                'Ingresar PIN',
                style: TextStyle(
                  color: V2Colors.textoPrimario,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                        text: 'Ingresá el PIN enviado por SMS al teléfono '),
                    TextSpan(
                      text: _telParcial,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: V2Colors.accion,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: V2Colors.textoSecundario,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) {
                  return SizedBox(
                    width: 46,
                    height: 56,
                    child: TextField(
                      controller: _ctrls[i],
                      focusNode: _nodes[i],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: i == 0 ? 6 : 1, // el 1º admite pegado completo
                      onChanged: (v) => _onChanged(i, v),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: V2Colors.textoPrimario,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: const Color(0xFFF5F8FB),
                        contentPadding: EdgeInsets.zero,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _error
                                ? V2Colors.rojo
                                : V2Colors.celesteClaro,
                            width: 1.6,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color:
                                _error ? V2Colors.rojo : V2Colors.accion,
                            width: 1.8,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              if (_error) ...[
                const SizedBox(height: 10),
                Text(
                  _mensajeError,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: V2Colors.rojo,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'El código expira en 5 minutos',
                style: TextStyle(
                  color: V2Colors.textoSecundario,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _reenvioEn <= 0 ? _reenviar : null,
                child: Text(
                  _reenvioEn <= 0
                      ? 'Reenviar código'
                      : 'Reenviar código (${_reenvioEn}s)',
                  style: TextStyle(
                    color: _reenvioEn <= 0
                        ? V2Colors.accion
                        : V2Colors.textoSecundario,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: _confirmando
                            ? null
                            : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: V2Colors.accion,
                          side: const BorderSide(
                              color: V2Colors.accion, width: 1.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _pin.length == 6 && !_confirmando
                            ? _confirmar
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: V2Colors.accion,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              V2Colors.accion.withOpacity(0.35),
                          disabledForegroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        child: _confirmando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Text('Confirmar PIN'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
