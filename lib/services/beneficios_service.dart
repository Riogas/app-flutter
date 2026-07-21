import 'dart:async';
import 'dart:math';

/// Resultado de validar un beneficio contra la API de la promoción
class BeneficioValidacion {
  final bool ok;
  final bool requierePin;
  final String mensaje; // string dinámico devuelto por la API (beneficio o error)

  const BeneficioValidacion({
    required this.ok,
    this.requierePin = false,
    required this.mensaje,
  });
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
/// ⚠️ IMPLEMENTACIÓN SIMULADA — el contrato queda definido para cuando
/// existan los endpoints GeneXus (reemplazar el cuerpo de cada método por
/// la llamada real vía RioGasService). Reglas de simulación para demo:
///  - Código `0000` → "código no válido"
///  - Código `1111` → "cliente sin beneficios"
///  - Código `2222` → "beneficio ya consumido"
///  - Código `9999` → error de conexión
///  - Código que empieza con `9` → requiere PIN (el PIN correcto es `123456`)
///  - Cualquier otro código → beneficio directo (20% de descuento)
class BeneficiosService {
  BeneficiosService._();
  static final BeneficiosService _instance = BeneficiosService._();
  factory BeneficiosService() => _instance;

  static const Duration _vigenciaPin = Duration(minutes: 5);

  DateTime? _pinEnviadoEn;
  String? _pinEsperado;
  String _mensajeBeneficio = '';

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
  }) async {
    // TODO(GeneXus): llamar al endpoint real de validación de la promo
    await Future.delayed(const Duration(milliseconds: 1400));

    final cod = (codigo ?? '').trim();
    switch (cod) {
      case '0000':
        return const BeneficioValidacion(
            ok: false, mensaje: 'El código ingresado no es válido.');
      case '1111':
        return const BeneficioValidacion(
            ok: false,
            mensaje:
                'El cliente no tiene beneficios disponibles para esta promoción.');
      case '2222':
        return const BeneficioValidacion(
            ok: false, mensaje: 'El beneficio ya fue utilizado anteriormente.');
      case '9999':
        return const BeneficioValidacion(
            ok: false,
            mensaje:
                'No fue posible conectarse al servicio. Intentá nuevamente.');
    }

    if (cod.startsWith('9')) {
      // La promo exige confirmación por PIN vía SMS
      _pinEsperado = '123456';
      _pinEnviadoEn = DateTime.now();
      _mensajeBeneficio =
          'El cliente tiene un 20% de descuento en la compra.';
      return const BeneficioValidacion(
        ok: true,
        requierePin: true,
        mensaje: 'La promoción requiere validación por PIN.',
      );
    }

    _mensajeBeneficio = 'El cliente tiene un 20% de descuento en la compra.';
    return BeneficioValidacion(ok: true, mensaje: _mensajeBeneficio);
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

  Future<BeneficioConsumo> consumir({
    required int promoIdInterno,
    required String promoNombre,
    String? codigo,
    String? telefono,
    required String movil,
    required String usuario,
    required String escenario,
  }) async {
    // TODO(GeneXus): llamar al endpoint real de consumo del beneficio
    await Future.delayed(const Duration(milliseconds: 1200));

    final aut = 'AUT-${100000 + Random().nextInt(899999)}';
    return BeneficioConsumo(
      ok: true,
      mensaje: 'El beneficio fue utilizado correctamente.',
      codigoAutorizacion: aut,
      fechaHora: DateTime.now(),
    );
  }
}
