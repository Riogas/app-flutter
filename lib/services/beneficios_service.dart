import 'dart:async';
import 'dart:math';

import 'riogas_service.dart';

/// Resultado de validar un beneficio contra la API de la promoción
class BeneficioValidacion {
  final bool ok;
  final bool requierePin;
  final String mensaje; // string dinámico devuelto por la API (beneficio o error)
  final int nroTrn; // NroTrn devuelto por promociones/ValidarPromo (0 si no vino)

  const BeneficioValidacion({
    required this.ok,
    this.requierePin = false,
    required this.mensaje,
    this.nroTrn = 0,
  });

  /// Mapea la respuesta cruda de `promociones/ValidarPromo`.
  ///
  /// Semántica acordada con GeneXus: `OK == 0` es válido, cualquier otro
  /// valor es rechazo y `message` trae el motivo. `ReqValidacionSMS == 'S'`
  /// exige el PIN por SMS y `LabelSMS` es el texto para esa pantalla.
  /// `null` = sin conexión o HTTP != 200 (RioGasService._post devuelve null).
  factory BeneficioValidacion.fromResponse(Map<String, dynamic>? resp) {
    if (resp == null) {
      return const BeneficioValidacion(
        ok: false,
        mensaje: 'No fue posible conectarse al servicio. Intentá nuevamente.',
      );
    }

    final ok = _asInt(resp['OK'], fallback: -1) == 0;
    final requierePin = ok &&
        (resp['ReqValidacionSMS'] ?? '').toString().trim().toUpperCase() == 'S';
    final message = (resp['message'] ?? '').toString().trim();
    final labelSms = (resp['LabelSMS'] ?? '').toString().trim();

    final String mensaje;
    if (requierePin && labelSms.isNotEmpty) {
      mensaje = labelSms;
    } else if (message.isNotEmpty) {
      mensaje = message;
    } else {
      mensaje = ok
          ? 'Beneficio validado.'
          : 'No se pudo validar el beneficio. Intentá nuevamente.';
    }

    return BeneficioValidacion(
      ok: ok,
      requierePin: requierePin,
      mensaje: mensaje,
      nroTrn: _asInt(resp['NroTrn'], fallback: 0),
    );
  }

  // GeneXus a veces serializa números como string
  static int _asInt(dynamic v, {required int fallback}) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? fallback;
}

/// Resultado de confirmar el PIN por SMS
class BeneficioPinResultado {
  final bool ok;
  final bool expirado;
  final String mensaje;

  const BeneficioPinResultado({
    required this.ok,
    this.expirado = false,
    required this.mensaje,
  });
}

/// Resultado del consumo del beneficio
class BeneficioConsumo {
  final bool ok;
  final String mensaje;
  final String? codigoAutorizacion;
  final DateTime? fechaHora;

  const BeneficioConsumo({
    required this.ok,
    required this.mensaje,
    this.codigoAutorizacion,
    this.fechaHora,
  });
}

/// 🎁 Servicio de validación/consumo de beneficios de promociones
/// (Antel, Claro, OCA Metros, etc.).
///
/// `validar()` pega al endpoint REAL `promociones/ValidarPromo` (GeneXus).
/// ⚠️ Siguen SIMULADOS hasta que existan sus endpoints: la confirmación del
/// PIN por SMS (el server ya manda el SMS cuando ReqValidacionSMS=='S', pero
/// no hay endpoint para verificar el PIN — acá se acepta `123456`), el
/// reenvío del SMS, el consumo y la anulación.
class BeneficiosService {
  BeneficiosService._();
  static final BeneficiosService _instance = BeneficiosService._();
  factory BeneficiosService() => _instance;

  static const Duration _vigenciaPin = Duration(minutes: 5);

  DateTime? _pinEnviadoEn;
  String? _pinEsperado;
  String _mensajeBeneficio = '';
  int _ultimoNroTrn = 0;

  /// Body de `promociones/ValidarPromo` con las claves y el casing EXACTOS
  /// del contrato (ojo: `Latitud` con mayúscula pero `longitud` sin ella).
  /// El `token` no va acá: lo inyecta `RioGasService._post`.
  ///
  /// ⚠️ `escenario` se recibe pero NO viaja: el build deployado del servicio
  /// GX (2026-07-31, verificado contra el bytecode en sgm) no declara
  /// `escenarioid` y GeneXus responde 400 ante propiedades desconocidas.
  /// Cuando GX publique la versión con `escenarioid`, agregarlo al mapa.
  static Map<String, dynamic> buildValidarPromoBody({
    required String escenario,
    required String usuario,
    required String deviceId,
    required String movil,
    required int idCampana,
    String? departamento,
    String? localidad,
    String? latitud,
    String? longitud,
    String? codigoCliente,
    String? nombreCliente,
    String? telCliente,
    String? campoIn1,
  }) {
    return {
      'usuario': usuario,
      'DeviceId': deviceId,
      'Departamento': departamento ?? '',
      'Localidad': localidad ?? '',
      'Latitud': latitud ?? '',
      'longitud': longitud ?? '',
      'idCampana': idCampana,
      'CodigoCliente': codigoCliente ?? '',
      'nombreCliente': nombreCliente ?? '',
      'telCliente': telCliente ?? '',
      'CampoIn1': campoIn1 ?? '',
      'CampoIn2': '',
      'INAux1': movil,
      'INAux2': '',
    };
  }

  Future<BeneficioValidacion> validar({
    required int promoIdInterno,
    required String promoNombre,
    String? codigo,
    String? telefono,
    String? nombre,
    String? auxIn1,
    required String movil,
    required String usuario,
    required String escenario,
    required String deviceId,
    // 🌍 Ubicación del móvil (GPS + Nominatim) — dato interno para la API
    String? departamento,
    String? localidad,
    String? latitud,
    String? longitud,
  }) async {
    final body = buildValidarPromoBody(
      escenario: escenario,
      usuario: usuario,
      deviceId: deviceId,
      movil: movil,
      idCampana: promoIdInterno,
      departamento: departamento,
      localidad: localidad,
      latitud: latitud,
      longitud: longitud,
      codigoCliente: codigo,
      nombreCliente: nombre,
      telCliente: telefono,
      campoIn1: auxIn1,
    );

    final resp = await RioGasService.validarPromo(body);
    final res = BeneficioValidacion.fromResponse(resp);

    if (res.ok) {
      _ultimoNroTrn = res.nroTrn;
      // El mensaje del server es el beneficio: se re-muestra tras el PIN
      _mensajeBeneficio = (resp?['message'] ?? '').toString().trim().isNotEmpty
          ? (resp!['message'] as Object).toString().trim()
          : res.mensaje;
      if (res.requierePin) {
        // TODO(GeneXus): falta el endpoint de verificación del PIN. El SMS
        // real ya lo manda el server; acá seguimos aceptando 123456.
        _pinEsperado = '123456';
        _pinEnviadoEn = DateTime.now();
      }
    }
    return res;
  }

  Future<BeneficioPinResultado> confirmarPin(String pin) async {
    // TODO(GeneXus): llamar al endpoint real de confirmación de PIN
    await Future.delayed(const Duration(milliseconds: 900));

    if (_pinEnviadoEn == null ||
        DateTime.now().difference(_pinEnviadoEn!) > _vigenciaPin) {
      return const BeneficioPinResultado(
        ok: false,
        expirado: true,
        mensaje: 'El código expiró. Solicitá uno nuevo.',
      );
    }
    if (pin == _pinEsperado) {
      return BeneficioPinResultado(ok: true, mensaje: _mensajeBeneficio);
    }
    return const BeneficioPinResultado(
        ok: false, mensaje: 'El PIN ingresado no es correcto.');
  }

  Future<void> reenviarPin() async {
    // TODO(GeneXus): llamar al endpoint real de reenvío de SMS
    await Future.delayed(const Duration(milliseconds: 700));
    _pinEnviadoEn = DateTime.now();
  }

  /// Anula un consumo dentro de la ventana de anulación.
  /// ⚠️ SIMULADO — cuando exista el endpoint GeneXus, además de marcar la
  /// anulación local debe viajar al backend con la autorización.
  Future<BeneficioConsumo> anular({
    required String autorizacion,
    required int promoIdInterno,
    required String promoNombre,
    required String movil,
    required String usuario,
    required String escenario,
  }) async {
    // TODO(GeneXus): llamar al endpoint real de anulación del consumo
    await Future.delayed(const Duration(milliseconds: 1000));
    return BeneficioConsumo(
      ok: true,
      mensaje: 'El consumo fue anulado correctamente.',
      codigoAutorizacion: autorizacion,
      fechaHora: DateTime.now(),
    );
  }

  Future<BeneficioConsumo> consumir({
    required int promoIdInterno,
    required String promoNombre,
    String? codigo,
    String? telefono,
    required String movil,
    required String usuario,
    required String escenario,
  }) async {
    // TODO(GeneXus): llamar al endpoint real de consumo del beneficio.
    // Mientras tanto la autorización local referencia el NroTrn REAL que
    // devolvió ValidarPromo, para poder cruzarlo con GeneXus.
    await Future.delayed(const Duration(milliseconds: 1200));

    final aut = _ultimoNroTrn > 0
        ? 'TRN-$_ultimoNroTrn'
        : 'AUT-${100000 + Random().nextInt(899999)}';
    return BeneficioConsumo(
      ok: true,
      mensaje: 'El beneficio fue utilizado correctamente.',
      codigoAutorizacion: aut,
      fechaHora: DateTime.now(),
    );
  }
}
