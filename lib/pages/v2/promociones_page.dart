import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../../services/beneficios_service.dart';
import '../../services/modo_ingreso_codigo.dart';
import '../../services/persistent_stream_manager.dart';
import '../../services/promo_consumos_store.dart';
import '../../services/promo_doc.dart';
import '../../services/promo_uso_store.dart';
import '../../services/proteccion_pantalla.dart';
import 'escaner_codigo_page.dart';
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
  /// Null cuando la página se monta fuera del shell de chofer (modo
  /// restringido): sin contador de mensajes no se dibuja el icono.
  final ValueNotifier<int>? messageCountNotifier;

  /// Null en modo restringido: el comercio no cambia el estado del móvil.
  final Future<void> Function(BuildContext context)? onEstadoTap;

  /// 🏪 Perfil comercio (escenario 9998): header con el nombre del comercio,
  /// sin píldora de móvil, sin mensajes y con el menú del avatar reducido.
  final bool modoRestringido;

  /// 🔒 Si la pantalla está realmente a la vista. Dentro del `IndexedStack`
  /// del home V2 los tres tabs se construyen juntos, así que estar montada no
  /// alcanza para pedir el anti-captura: se pediría desde el arranque y
  /// quedaría bloqueando Pedidos y Mapa también. Default true para los usos
  /// donde la página ES la pantalla (modo restringido / navegación directa).
  final bool enPantalla;

  const PromocionesPage({
    super.key,
    this.messageCountNotifier,
    this.onEstadoTap,
    this.modoRestringido = false,
    this.enPantalla = true,
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

class _PromocionesPageState extends State<PromocionesPage>
    with WidgetsBindingObserver {
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
  bool _opcionalesAbiertos = false;

  // 🌍 Ubicación actual (interna, para la API de validación)
  String? _departamento;
  String? _localidad;
  String? _latitud;
  String? _longitud;

  /// 🏠 Calle y número del punto donde se está consumiendo. Va en
  /// `Mdu_MduAutDir` de ConsumirPromo (el contrato del consumo no tiene
  /// campos de latitud/longitud: viaja la dirección, no las coordenadas).
  String? _direccion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 🔒 Datos sensibles en pantalla (códigos de beneficio, datos del
    // cliente): no se permite screenshot ni grabación mientras se la ve.
    if (widget.enPantalla) {
      _protegiendo = true;
      ProteccionPantalla.adquirir();
    }
    _marcarVistas();
    PromoConsumosStore().init();
    PromoUsoStore().init();
    // Refrescar habilitación del botón Validar al tipear
    for (final c in [_codigoCtrl, _telCtrl, _nombreCtrl, _auxCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  /// Si esta instancia tiene tomado el anti-captura. Necesario para que el
  /// contador quede balanceado: se adquiere y libera al entrar/salir del tab,
  /// no en initState/dispose.
  bool _protegiendo = false;

  @override
  void didUpdateWidget(PromocionesPage old) {
    super.didUpdateWidget(old);
    if (widget.enPantalla && !_protegiendo) {
      _protegiendo = true;
      ProteccionPantalla.adquirir();
    } else if (!widget.enPantalla && _protegiendo) {
      _protegiendo = false;
      ProteccionPantalla.liberar();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_protegiendo) {
      _protegiendo = false;
      ProteccionPantalla.liberar();
    }
    _codigoCtrl.dispose();
    _telCtrl.dispose();
    _nombreCtrl.dispose();
    _auxCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Algunos equipos pierden el FLAG_SECURE al volver de background.
    if (state == AppLifecycleState.resumed) ProteccionPantalla.reaplicar();
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

  /// Los documentos se cargan a mano y la grafía de las claves varía
  /// (`idInterno` vs `IdInterno`), así que la lectura tolera mayúsculas.
  String _label(String? campo) => PromoDoc.texto(_promo, campo ?? '');

  /// Id de la campaña en SGM. Si el documento no lo trae, queda en 0 y el
  /// servicio responde "Esta agencia está incompleta en SGM".
  int get _idCampana => PromoDoc.idInterno(_promo);

  /// 📷 Cómo carga el usuario el código: tecleado, QR o código de barras.
  ModoIngresoCodigo get _modoCodigo =>
      ModoIngresoCodigo.desde(_promo[ModoIngresoCodigo.campoFirestore]);

  /// Con escaneo el campo se muestra SIEMPRE: si la promo pide cámara pero
  /// olvidaron cargar `LabelCodCliente`, ocultarlo dejaría la promo sin forma
  /// de validarse. Para el modo manual se respeta la regla de siempre.
  bool get _tieneCodigo =>
      _label('LabelCodCliente').isNotEmpty || _modoCodigo.esEscaneo;

  /// Label del campo código, con respaldo según el modo.
  String get _labelCodigo {
    final l = _label('LabelCodCliente');
    return l.isNotEmpty ? l : _modoCodigo.labelPorDefecto;
  }

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
      _opcionalesAbiertos = false;
    });
    _obtenerGeo();
  }

  /// 🌍 Obtiene departamento y localidad actuales (GPS + Nominatim propio de
  /// RioGas). Datos INTERNOS: se envían a la API de validación cuando exista;
  /// solo se muestran en pantalla en modo debug.
  Future<void> _obtenerGeo() async {
    try {
      Position? p = await Geolocator.getLastKnownPosition();
      p ??= await Geolocator.getCurrentPosition(
          timeLimit: const Duration(seconds: 8));

      // Las coordenadas van a ValidarPromo aunque el reverse geocode falle
      _latitud = p.latitude.toString();
      _longitud = p.longitude.toString();

      await _reverseGeocode(p.latitude, p.longitude);
    } catch (e) {
      print('⚠️ [PROMOS] Error obteniendo departamento/localidad: $e');
    }
  }

  /// 🌍 Geolocalización inversa contra el Nominatim propio de RioGas:
  /// actualiza departamento/localidad para las coordenadas dadas.
  Future<void> _reverseGeocode(double lat, double lon) async {
    final resp = await http
        .get(Uri.parse(
            'http://nominatim.riogas.uy/reverse?lat=$lat&lon=$lon&format=json'))
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return;

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final addr = (data['address'] as Map<String, dynamic>?) ?? {};
    final dep = (addr['state'] ?? addr['county'] ?? '').toString();
    final loc = (addr['city'] ??
            addr['town'] ??
            addr['village'] ??
            addr['municipality'] ??
            addr['suburb'] ??
            '')
        .toString();

    // 🏠 Calle y número para `Mdu_MduAutDir` del consumo. Si Nominatim no
    // resolvió la calle queda el display_name completo (lo recorta el
    // servicio antes de mandarlo).
    final calle = (addr['road'] ?? '').toString().trim();
    final nro = (addr['house_number'] ?? '').toString().trim();
    final dir = calle.isNotEmpty
        ? (nro.isNotEmpty ? '$calle $nro' : calle)
        : (data['display_name'] ?? '').toString().trim();

    print('🌍 [PROMOS] Ubicación administrativa: $dep / $loc — dir: "$dir"');
    if (mounted) {
      setState(() {
        _departamento = dep;
        _localidad = loc;
        if (dir.isNotEmpty) _direccion = dir;
      });
    }
  }

  /// 📍 Fix FRESCO al apretar Consumir: el usuario pudo validar en un lugar
  /// y consumir en otro, así que acá NO sirve el último conocido — se fuerza
  /// una lectura nueva del GPS y recién si no responde a tiempo se cae al
  /// último conocido (y si tampoco hay, quedan las coordenadas de la
  /// validación). Después refresca departamento/localidad por geoinversa.
  /// Nunca lanza: sin GPS el consumo sigue igual.
  Future<void> _capturarGeoFresca() async {
    try {
      final p = await Geolocator.getCurrentPosition(
          timeLimit: const Duration(seconds: 8));
      _latitud = p.latitude.toString();
      _longitud = p.longitude.toString();
      print('📍 [CONSUMIR] Fix fresco: $_latitud, $_longitud '
          '(±${p.accuracy.toStringAsFixed(0)}m)');
      try {
        await _reverseGeocode(p.latitude, p.longitude);
      } catch (e) {
        print('⚠️ [CONSUMIR] Geoinversa falló ($e); sigo con dep/loc previos');
      }
    } catch (e) {
      print('⚠️ [CONSUMIR] Sin fix fresco ($e); pruebo último conocido');
      try {
        final p = await Geolocator.getLastKnownPosition();
        if (p != null) {
          _latitud = p.latitude.toString();
          _longitud = p.longitude.toString();
        }
      } catch (_) {}
    }
  }

  Future<Map<String, String>> _identidad() async {
    final box = await Hive.openBox('sessionBox');
    return {
      'movil': box.get('movil', defaultValue: '').toString(),
      'usuario': box.get('username', defaultValue: '').toString(),
      'escenario': box.get('escenario', defaultValue: '').toString(),
      'deviceId': box.get('deviceId', defaultValue: '').toString(),
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
      promoIdInterno: _idCampana,
      promoNombre: _label('NombreCombo'),
      codigo: _tieneCodigo ? _codigoCtrl.text.trim() : null,
      telefono: _tieneTel ? _telCtrl.text.trim() : null,
      nombre: _tieneNombre ? _nombreCtrl.text.trim() : null,
      auxIn1: _tieneAux ? _auxCtrl.text.trim() : null,
      movil: ident['movil']!,
      usuario: ident['usuario']!,
      escenario: ident['escenario']!,
      deviceId: ident['deviceId']!,
      departamento: _departamento,
      localidad: _localidad,
      latitud: _latitud,
      longitud: _longitud,
    );

    if (!mounted) return;

    if (!res.ok) {
      setState(() {
        _fase = _Fase.error;
        _mensajeResultado = res.mensaje;
      });
      return;
    }

    // ⭐ Validación OK = uso real: la promo sube a "Últimas usadas" del
    // selector. Seleccionarla sin validar no cuenta.
    PromoUsoStore().registrarUso(_promoDoc?.id ?? '');

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

    // 📍 Fix FRESCO del momento del consumo (no el de la validación) para
    // resolver la dirección exacta del domicilio, que es lo que viaja.
    await _capturarGeoFresca();

    final ident = await _identidad();
    final res = await _service.consumir(
      promoIdInterno: _idCampana,
      promoNombre: _label('NombreCombo'),
      codigo: _codigoCtrl.text.trim(),
      telefono: _telCtrl.text.trim(),
      movil: ident['movil']!,
      usuario: ident['usuario']!,
      escenario: ident['escenario']!,
      deviceId: ident['deviceId']!,
      direccion: _direccion,
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

    // 🧾 Registrar el consumo en el dispositivo (permite anular 30 min)
    if (res.ok) {
      await PromoConsumosStore().registrar(
        promo: _label('NombreCombo'),
        idInterno: _idCampana,
        codigo: _codigoCtrl.text.trim(),
        telefono: _telCtrl.text.trim(),
        cliente: _nombreCtrl.text.trim(),
        beneficio: _mensajeResultado,
        autorizacion: res.codigoAutorizacion ?? '',
        fechaHora: res.fechaHora,
        mduId: res.mduId,
      );
    }
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
      _opcionalesAbiertos = false;
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
                  // 🏪 Comercio: header con su nombre (modo home) en vez del
                  // título de sección y sin píldora. El menú del avatar queda
                  // COMPLETO también para el comercio (Configuración incluida):
                  // decisión 2026-07-31, hay cosas ahí que le sirven; si algún
                  // item molesta se ocultará puntualmente más adelante.
                  titulo: widget.modoRestringido ? null : 'Promos',
                  subtitulo: widget.modoRestringido
                      ? null
                      : 'Validá beneficios del cliente antes de consumirlos',
                  mostrarEstado: !widget.modoRestringido,
                  menuSoloLogout: false,
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
                        const SizedBox(height: 12),
                        _consumosDelDiaRow(),
                        const SizedBox(height: 8),
                        const Text(
                          '⚙️ Validación en línea · PIN y consumo aún simulados',
                          style: TextStyle(
                            color: V2Colors.textoSecundario,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        // Guarda para la barra inferior; en modo restringido
                        // no hay barra, así que alcanza con un margen chico.
                        SizedBox(height: widget.modoRestringido ? 16 : 70),
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
        // 🧪 Solo visible en modo debug: la ubicación administrativa es un
        // dato interno que viajará a la API de validación
        if (kDebugMode &&
            _promoDoc != null &&
            (_departamento ?? '').isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            '🧪 interno: ${_departamento ?? ''} · ${_localidad ?? ''}',
            style: const TextStyle(
              color: V2Colors.textoSecundario,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (_promoDoc != null) ...[
          ..._camposFormulario(),
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
                // Necesario para que el buscador quede por encima del teclado
                isScrollControlled: true,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
                ),
                builder: (ctx) => _SelectorPromosSheet(
                  promos: promos,
                  seleccionadaId: _promoDoc?.id,
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
            if (seleccionado.isNotEmpty && _idCampana > 0) ...[
              const SizedBox(width: 8),
              Text(
                '#$_idCampana',
                style: const TextStyle(
                  color: V2Colors.textoSecundario,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const Icon(Icons.keyboard_arrow_down,
                color: V2Colors.textoSecundario),
          ],
        ),
      ),
    );
  }

  // ── 🧾 Promos del día (consumos locales, anulables por 30 min) ──────────

  Widget _consumosDelDiaRow() {
    return ValueListenableBuilder<List<PromoConsumo>>(
      valueListenable: PromoConsumosStore().consumos,
      builder: (context, _, __) {
        final delDia = PromoConsumosStore().delDia;
        final anulables =
            delDia.where(PromoConsumosStore().puedeAnular).length;
        return V2Card(
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: _mostrarConsumosDelDia,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: V2Colors.celesteClaro,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.receipt_long,
                        color: V2Colors.accion, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          delDia.isEmpty
                              ? 'Promos del día'
                              : 'Promos del día (${delDia.length})',
                          style: const TextStyle(
                            color: V2Colors.textoPrimario,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          delDia.isEmpty
                              ? 'Todavía no consumiste beneficios hoy'
                              : anulables > 0
                                  ? '$anulables ${anulables == 1 ? 'anulable' : 'anulables'} por tiempo limitado'
                                  : 'Consumos confirmados',
                          style: const TextStyle(
                            color: V2Colors.textoSecundario,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (anulables > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: V2Colors.naranja.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$anulables',
                        style: const TextStyle(
                          color: V2Colors.naranja,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  const Icon(Icons.chevron_right,
                      color: V2Colors.textoSecundario),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _mostrarConsumosDelDia() async {
    Timer? refresco;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheet) {
          // ⏱️ Refresco del contador de anulación cada 30s
          refresco ??= Timer.periodic(const Duration(seconds: 30), (_) {
            if (ctx2.mounted) setSheet(() {});
          });
          final delDia = PromoConsumosStore().delDia;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: V2Colors.celesteClaro,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Promos del día',
                    style: TextStyle(
                      color: V2Colors.textoPrimario,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (delDia.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 12, 24, 32),
                    child: Text(
                      'Todavía no consumiste beneficios hoy.',
                      style: TextStyle(
                        color: V2Colors.textoSecundario,
                        fontSize: 13.5,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: delDia.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, i) =>
                          _consumoTile(delDia[i], setSheet),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
    refresco?.cancel();
  }

  Widget _consumoTile(PromoConsumo c, StateSetter setSheet) {
    final store = PromoConsumosStore();
    final anulable = store.puedeAnular(c);
    final minutos = store.minutosParaAnular(c);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.anulada ? const Color(0xFFF7F9FB) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: c.anulada
              ? V2Colors.textoSecundario.withOpacity(0.25)
              : anulable
                  ? V2Colors.naranja.withOpacity(0.5)
                  : V2Colors.celesteClaro,
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                V2Data.fmtHora(c.fechaHora),
                style: const TextStyle(
                  color: V2Colors.textoPrimario,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.promo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: V2Colors.textoPrimario,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (c.anulada)
                _chipEstado('Anulada', V2Colors.textoSecundario)
              else if (anulable)
                _chipEstado('Anulable ${minutos}m', V2Colors.naranja)
              else
                _chipEstado('Confirmada', V2Colors.verde),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            c.beneficio,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: V2Colors.textoSecundario,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (c.autorizacion.isNotEmpty) 'Aut: ${c.autorizacion}',
              if (c.telefono.isNotEmpty) 'Tel: ${c.telefono}',
              if (c.cliente.isNotEmpty) c.cliente,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: V2Colors.textoSecundario,
              fontSize: 11.5,
            ),
          ),
          if (anulable) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                onPressed: () => _anularConsumo(c, setSheet),
                style: OutlinedButton.styleFrom(
                  foregroundColor: V2Colors.rojo,
                  side:
                      BorderSide(color: V2Colors.rojo.withOpacity(0.6)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Anular consumo'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipEstado(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Future<void> _anularConsumo(PromoConsumo c, StateSetter setSheet) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Anular consumo'),
        content: Text(
            '¿Anular el beneficio de ${c.promo} (${c.autorizacion.isNotEmpty ? c.autorizacion : V2Data.fmtHora(c.fechaHora)})?\n\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: V2Colors.rojo,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    final ident = await _identidad();
    final res = await _service.anular(
      autorizacion: c.autorizacion,
      mduId: c.mduId,
      promoIdInterno: c.idInterno,
      promoNombre: c.promo,
      movil: ident['movil']!,
      usuario: ident['usuario']!,
      escenario: ident['escenario']!,
      deviceId: ident['deviceId']!,
    );

    if (res.ok) {
      await PromoConsumosStore().marcarAnulada(c.id);
      setSheet(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.mensaje)),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.mensaje)),
      );
    }
  }

  /// Campos del formulario: los requeridos siempre visibles; los opcionales
  /// agrupados en un colapsable con "+" (por lo general nadie los completa)
  List<Widget> _camposFormulario() {
    final requeridos = <Widget>[];
    final opcionales = <Widget>[];

    void agregar(bool visible, bool req, Widget Function() builder) {
      if (!visible) return;
      (req ? requeridos : opcionales).add(builder());
    }

    agregar(
        _tieneCodigo,
        _codigoReq,
        () => _bloqueCampo(
              label: _labelCodigo,
              requerido: _codigoReq,
              // 📷 Según `ComoSeIngresaElCodigo`: tecleado o cámara. En ambos
              // casos el valor termina en `_codigoCtrl`, así que la validación
              // y el consumo no se enteran de la diferencia.
              campo: _modoCodigo.esEscaneo
                  ? _campoEscaneo()
                  : _campoTexto(
                      controller: _codigoCtrl,
                      hint: 'Ingresá el código de la promoción',
                      icon: Icons.qr_code_2,
                    ),
            ));
    agregar(
        _tieneTel,
        _telReq,
        () => _bloqueCampo(
              label: _label('LabelCodTelCliente'),
              requerido: _telReq,
              campo: _campoTexto(
                controller: _telCtrl,
                hint: 'Ingresá el teléfono del cliente',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                helper: _label('TelValores').isNotEmpty
                    ? _label('TelValores')
                    : null,
              ),
            ));
    agregar(
        _tieneNombre,
        _nombreReq,
        () => _bloqueCampo(
              label: _label('LabelNomCliente'),
              requerido: _nombreReq,
              campo: _campoTexto(
                controller: _nombreCtrl,
                hint: 'Nombre y apellido del cliente',
                icon: Icons.person_outline,
                textCapitalization: TextCapitalization.words,
              ),
            ));
    agregar(
        _tieneAux,
        _auxReq,
        () => _bloqueCampo(
              label: _label('LabelAuxIn1'),
              requerido: _auxReq,
              campo: _campoTexto(
                controller: _auxCtrl,
                hint: 'Agregá cualquier observación relevante',
                icon: Icons.notes_outlined,
                maxLines: 3,
                maxLength: 120,
              ),
            ));

    return [
      ...requeridos,
      if (opcionales.isNotEmpty) ...[
        const SizedBox(height: 16),
        _toggleOpcionales(opcionales.length),
        if (_opcionalesAbiertos) ...opcionales,
      ],
    ];
  }

  Widget _bloqueCampo({
    required String label,
    required bool requerido,
    required Widget campo,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labelCampo(label, requerido: requerido),
          const SizedBox(height: 6),
          campo,
        ],
      ),
    );
  }

  Widget _toggleOpcionales(int cantidad) {
    return InkWell(
      onTap: () => setState(() => _opcionalesAbiertos = !_opcionalesAbiertos),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8FB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: V2Colors.celesteClaro, width: 1.4),
        ),
        child: Row(
          children: [
            Icon(
              _opcionalesAbiertos
                  ? Icons.remove_circle_outline
                  : Icons.add_circle_outline,
              color: V2Colors.accion,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              cantidad == 1
                  ? 'Dato opcional'
                  : 'Datos opcionales ($cantidad)',
              style: const TextStyle(
                color: V2Colors.textoPrimario,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              _opcionalesAbiertos ? 'Ocultar' : 'Agregar',
              style: const TextStyle(
                color: V2Colors.accion,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
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

  // ── Ingreso del código por cámara (QR / código de barras) ───────────────

  /// Abre el escáner y deja lo leído en `_codigoCtrl`, el mismo lugar donde
  /// escribe el campo de texto: para el resto de la pantalla es indistinto de
  /// dónde salió el código.
  Future<void> _escanearCodigo() async {
    final modo = _modoCodigo;
    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EscanerCodigoPage(
          modo: modo,
          promo: _label('NombreCombo'),
        ),
      ),
    );
    if (!mounted || codigo == null) return;

    // Cambiar de promo mientras el escáner estaba abierto invalidaría la
    // lectura: se descarta en vez de escribirla en la promo equivocada.
    if (_modoCodigo != modo) return;

    _codigoCtrl.text = codigo;
    setState(() {
      // Una lectura nueva invalida CUALQUIER resultado anterior, no solo un
      // error: si quedara la tarjeta verde de la validación previa, el botón
      // "Consumir" mandaría el código nuevo contra el beneficio del cliente
      // anterior (y el registro local para anular quedaría cruzado).
      if (_fase != _Fase.consumido) {
        _fase = _Fase.inicial;
        _mensajeResultado = '';
      }
    });
  }

  Widget _campoEscaneo() {
    final modo = _modoCodigo;
    final leido = _codigoCtrl.text.trim();
    final icono = modo == ModoIngresoCodigo.barras
        ? Icons.barcode_reader
        : Icons.qr_code_scanner;

    if (leido.isEmpty) {
      return SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton.icon(
          onPressed: _escanearCodigo,
          style: ElevatedButton.styleFrom(
            backgroundColor: V2Colors.accion,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle:
                const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
          ),
          icon: Icon(icono, size: 22),
          label: Text(modo.textoBoton),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: V2Colors.verde, width: 1.4),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: V2Colors.verde, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Código escaneado',
                  style: TextStyle(
                    color: V2Colors.textoSecundario,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  leido,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: V2Colors.textoPrimario,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Escanear de nuevo',
            onPressed: _escanearCodigo,
            icon: const Icon(Icons.refresh, color: V2Colors.accion),
          ),
        ],
      ),
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
// 🎯 Bottom sheet selector de promoción: buscador + últimas usadas
// ─────────────────────────────────────────────────────────────────────────
class _SelectorPromosSheet extends StatefulWidget {
  final List<DocumentSnapshot> promos;
  final String? seleccionadaId;

  const _SelectorPromosSheet({required this.promos, this.seleccionadaId});

  @override
  State<_SelectorPromosSheet> createState() => _SelectorPromosSheetState();
}

class _SelectorPromosSheetState extends State<_SelectorPromosSheet> {
  final _filtroCtrl = TextEditingController();
  final _usos = PromoUsoStore();

  @override
  void dispose() {
    _filtroCtrl.dispose();
    super.dispose();
  }

  // Los docs de Promociones se cargan a mano y la grafía de las claves varía
  String _nombre(DocumentSnapshot d) =>
      PromoDoc.texto((d.data() as Map<String, dynamic>?) ?? {}, 'NombreCombo');
  String _desc(DocumentSnapshot d) =>
      PromoDoc.texto((d.data() as Map<String, dynamic>?) ?? {}, 'Descripcion');
  int _id(DocumentSnapshot d) =>
      PromoDoc.idInterno((d.data() as Map<String, dynamic>?) ?? {});

  Widget _tituloSeccion(String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            texto.toUpperCase(),
            style: const TextStyle(
              color: V2Colors.textoSecundario,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
      );

  Widget _tile(DocumentSnapshot d, {bool reciente = false}) {
    final nombre = _nombre(d);
    final desc = _desc(d);
    final id = _id(d);
    final seleccionada = widget.seleccionadaId == d.id;
    return ListTile(
      leading: Icon(
        reciente ? Icons.history : Icons.local_offer_outlined,
        color: V2Colors.accion,
      ),
      title: Text(nombre,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: desc.isNotEmpty && desc != nombre ? Text(desc) : null,
      trailing: (id > 0 || seleccionada)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (id > 0)
                  Text(
                    '#$id',
                    style: const TextStyle(
                      color: V2Colors.textoSecundario,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (seleccionada) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle, color: V2Colors.verde),
                ],
              ],
            )
          : null,
      onTap: () => Navigator.pop(context, d),
    );
  }

  List<Widget> _filas() {
    final filtro = _filtroCtrl.text;

    if (filtro.trim().isNotEmpty) {
      // Buscando: lista plana filtrada, con las usadas primero
      final coincidencias = _usos.ordenar(
        widget.promos
            .where((d) => PromoUsoStore.coincide(
                  filtro: filtro,
                  nombre: _nombre(d),
                  descripcion: _desc(d),
                  id: _id(d) > 0 ? '${_id(d)}' : '',
                ))
            .toList(),
        (d) => d.id,
      );
      if (coincidencias.isEmpty) {
        return [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Text(
              'No hay promociones que coincidan con "${filtro.trim()}".',
              textAlign: TextAlign.center,
              style: const TextStyle(color: V2Colors.textoSecundario),
            ),
          ),
        ];
      }
      return coincidencias.map(_tile).toList();
    }

    // Sin filtro: "Últimas usadas" arriba y después la lista completa (las
    // recientes se repiten ahí a propósito: que "Todas" siempre esté entera).
    final recientes = _usos.recientes(widget.promos, (d) => d.id);
    if (recientes.isEmpty) return widget.promos.map(_tile).toList();

    return [
      _tituloSeccion('Últimas usadas'),
      ...recientes.map((d) => _tile(d, reciente: true)),
      _tituloSeccion('Todas'),
      ...widget.promos.map(_tile),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Con el teclado abierto el sheet sube entero (viewInsets) y el alto se
    // achica para no pasarse del borde superior de la pantalla.
    final alturaMax =
        (mq.size.height * 0.85 - mq.viewInsets.bottom).clamp(300.0, 10000.0);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: alturaMax),
        child: SafeArea(
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _filtroCtrl,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Buscar promoción…',
                    hintStyle:
                        const TextStyle(color: V2Colors.textoSecundario),
                    prefixIcon: const Icon(Icons.search,
                        color: V2Colors.textoSecundario, size: 21),
                    suffixIcon: _filtroCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close,
                                color: V2Colors.textoSecundario, size: 20),
                            onPressed: () =>
                                setState(() => _filtroCtrl.clear()),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF5F8FB),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: V2Colors.celesteClaro, width: 1.4),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: V2Colors.accion, width: 1.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _filas(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
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

    // El PIN NO se verifica acá: la API no tiene endpoint para eso. Se guarda
    // y viaja en ConsumirPromo, que lo valida en ese mismo viaje.
    final res = await BeneficiosService().registrarPin(_pin);
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
    final res = await BeneficiosService().reenviarPin();
    if (!mounted) return;

    if (!res.ok) {
      // El server rechazó el reenvío: se muestra su motivo y NO se arranca la
      // cuenta regresiva (si no, el botón queda bloqueado sin haber reenviado).
      setState(() {
        _error = true;
        _mensajeError = res.mensaje;
      });
      return;
    }

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
      SnackBar(content: Text(res.mensaje)),
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
