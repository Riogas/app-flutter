import 'dart:async';

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
/// `validar()`, `consumir()` y `reenviarPin()` pegan a los endpoints REALES
/// de GeneXus (`promociones/ValidarPromo`, `ConsumirPromo` y `ReenviarSMS`).
///
/// El PIN por SMS NO tiene endpoint de confirmación: `registrarPin()` solo lo
/// guarda y lo valida el server dentro del consumo (`PreMduCodSMS`).
/// ⚠️ `anular()` SIGUE SIMULADO — no existe endpoint, así que la anulación
/// queda solo en el teléfono mientras el server mantiene el consumo hecho.
class BeneficiosService {
  BeneficiosService._();
  static final BeneficiosService _instance = BeneficiosService._();
  factory BeneficiosService() => _instance;

  String _mensajeBeneficio = '';
  int _ultimoNroTrn = 0;

  /// PIN tecleado por el usuario. NO se verifica contra el server acá: no
  /// existe endpoint para eso, viaja dentro de ConsumirPromo y se valida en
  /// ese mismo viaje.
  String _pinIngresado = '';

  // Identidad de la última validación: ReenviarSMS y ConsumirPromo la piden
  // y se dispararan desde pantallas que no la tienen a mano.
  String _usuario = '';
  String _deviceId = '';
  String _movil = '';

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
    int pedidoId = 0,
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
      // 📦 Pedido al que se asocia la promoción. Va en 0 hasta que se defina
      // de dónde sale el id (decisión pendiente con GeneXus): en el perfil
      // comercio no hay pedido, y en el del chofer habría que tomar el que
      // está en curso. `pedidoId` queda como parámetro para engancharlo sin
      // tocar el resto del cuerpo.
      'PreMduPedId': pedidoId,
      'INAux1': movil,
      'INAux2': '',
      // 🚚 Campo `movil` del contrato (lo declara el servicio desde el build
      // del 2026-08-13). Va como número; `INAux1` se mantiene con el mismo
      // dato en texto para no cambiar lo que GeneXus ya venía consumiendo.
      'movil': _soloDigitos(movil),
    };
  }

  /// El móvil llega como texto y a veces con el prefijo del documento de
  /// Firestore (`Moviles-336`), así que se queda con los dígitos. 0 si no hay.
  static int _soloDigitos(String v) =>
      int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  /// Body de `promociones/ConsumirPromo`, con los campos EXACTOS del contrato
  /// publicado (verificado contra el servicio: manda una propiedad de más y
  /// responde 400).
  ///
  /// - `PreMduId`: el `NroTrn` que devolvió ValidarPromo — es la
  ///   pre-registración que este consumo confirma. Por eso acá no viajan
  ///   campaña, cliente ni teléfono: el server los toma de ella.
  /// - `PreMduCodSMS`: el PIN que llegó por SMS; vacío si la promo no lo pide.
  ///   NO hay endpoint para verificarlo antes: se valida en este mismo viaje.
  /// - `Mdu_MduAutDir`: la dirección del domicilio donde se consume (calle y
  ///   número que devuelve la geoinversa del Nominatim propio).
  /// - `CampoIn1`/`CampoIn2`: libres, reservados (el contrato NO tiene dónde
  ///   poner latitud/longitud, así que las coordenadas no viajan en el consumo
  ///   — sí en ValidarPromo).
  static Map<String, dynamic> buildConsumirPromoBody({
    required String usuario,
    required String deviceId,
    required String movil,
    required int preMduId,
    String? codSms,
    String? direccion,
    String? campoIn1,
    String? campoIn2,
  }) {
    return {
      'usuario': usuario,
      'DeviceId': deviceId,
      'movil': _soloDigitos(movil),
      'PreMduId': preMduId,
      'PreMduCodSMS': codSms ?? '',
      'Mdu_MduAutDir': _recortar(direccion ?? '', 100),
      'CampoIn1': campoIn1 ?? '',
      'CampoIn2': campoIn2 ?? '',
    };
  }

  /// La dirección de Nominatim puede venir larguísima (`display_name` trae
  /// hasta el país). Se recorta para no pasarse del largo del atributo.
  static String _recortar(String v, int max) {
    final t = v.trim();
    return t.length <= max ? t : t.substring(0, max);
  }

  /// GeneXus declara `&ok` en minúscula pero serializa `OK` (verificado contra
  /// ReenviarSMS: `{"OK":99,...}`). Se leen las dos grafías para no depender
  /// de eso. Convención de la API: 0 = todo bien, cualquier otro = rechazo.
  static int _okDe(Map<String, dynamic> resp) => BeneficioValidacion._asInt(
      resp.containsKey('OK') ? resp['OK'] : resp['ok'],
      fallback: -1);

  static String _mensajeDe(Map<String, dynamic> resp) =>
      (resp['message'] ?? resp['Message'] ?? '').toString().trim();

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
      _usuario = usuario;
      _deviceId = deviceId;
      _movil = movil;
      _pinIngresado = '';
      _ultimoNroTrn = res.nroTrn;
      // El mensaje del server es el beneficio: se re-muestra tras el PIN.
      // Si la promo pide SMS el server ya lo mandó; el código se junta en la
      // pantalla y se verifica recién en ConsumirPromo.
      _mensajeBeneficio = (resp?['message'] ?? '').toString().trim().isNotEmpty
          ? (resp!['message'] as Object).toString().trim()
          : res.mensaje;
    }
    return res;
  }

  /// Guarda el PIN tecleado para mandarlo en el consumo.
  ///
  /// ⚠️ NO lo verifica: la API no tiene endpoint de confirmación, el código
  /// viaja en `ConsumirPromo` (`PreMduCodSMS`) y el server lo valida ahí. Si
  /// está mal, el error aparece al consumir. Acá solo se chequea que estén
  /// los 6 dígitos, para no gastar un viaje al pedo.
  Future<BeneficioPinResultado> registrarPin(String pin) async {
    final limpio = pin.replaceAll(RegExp(r'\D'), '');
    if (limpio.length != 6) {
      return const BeneficioPinResultado(
        ok: false,
        mensaje: 'Ingresá los 6 dígitos del código.',
      );
    }
    _pinIngresado = limpio;
    return BeneficioPinResultado(ok: true, mensaje: _mensajeBeneficio);
  }

  /// Reenvía el SMS del código (promociones/ReenviarSMS). Endpoint REAL.
  Future<BeneficioPinResultado> reenviarPin() async {
    final resp = await RioGasService.reenviarSms({
      'usuario': _usuario,
      'DeviceId': _deviceId,
      'NroTrn': _ultimoNroTrn,
    });

    if (resp == null) {
      return const BeneficioPinResultado(
        ok: false,
        mensaje: 'No fue posible conectarse al servicio. Intentá nuevamente.',
      );
    }

    final ok = _okDe(resp) == 0;
    final msg = _mensajeDe(resp);
    return BeneficioPinResultado(
      ok: ok,
      mensaje: msg.isNotEmpty
          ? msg
          : (ok
              ? 'Te reenviamos el código por SMS.'
              : 'No se pudo reenviar el código.'),
    );
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

  /// Consume el beneficio (promociones/ConsumirPromo). Endpoint REAL.
  ///
  /// Confirma la pre-registración que dejó ValidarPromo (`PreMduId` =
  /// `NroTrn`), manda el PIN del SMS si la promo lo pedía y la dirección del
  /// domicilio donde se consume. ⚠️ Es IRREVERSIBLE desde la app: todavía no
  /// hay endpoint de anulación (la anulación de "Promos del día" es local).
  Future<BeneficioConsumo> consumir({
    required int promoIdInterno,
    required String promoNombre,
    String? codigo,
    String? telefono,
    required String movil,
    required String usuario,
    required String escenario,
    String? deviceId,
    // 📍 Dirección del domicilio (geoinversa del fix fresco al consumir)
    String? direccion,
  }) async {
    final body = buildConsumirPromoBody(
      usuario: usuario.isNotEmpty ? usuario : _usuario,
      deviceId: (deviceId?.isNotEmpty ?? false) ? deviceId! : _deviceId,
      movil: movil.isNotEmpty ? movil : _movil,
      preMduId: _ultimoNroTrn,
      codSms: _pinIngresado,
      direccion: direccion,
    );
    print('🎁 [CONSUMIR] POST promociones/ConsumirPromo: $body');

    final resp = await RioGasService.consumirPromo(body);
    if (resp == null) {
      return const BeneficioConsumo(
        ok: false,
        mensaje: 'No fue posible conectarse al servicio. Intentá nuevamente.',
      );
    }

    final ok = _okDe(resp) == 0;
    final msg = _mensajeDe(resp);
    if (!ok) {
      return BeneficioConsumo(
        ok: false,
        mensaje: msg.isNotEmpty
            ? msg
            : 'No se pudo consumir el beneficio. Intentá nuevamente.',
      );
    }

    // La autorización llega en OUTAux1 si el server la manda; si no, se deja
    // el NroTrn para poder cruzar el consumo con GeneXus.
    final outAux1 = (resp['OUTAux1'] ?? '').toString().trim();
    final aut = outAux1.isNotEmpty
        ? outAux1
        : (_ultimoNroTrn > 0 ? 'TRN-$_ultimoNroTrn' : '');
    _pinIngresado = '';
    return BeneficioConsumo(
      ok: true,
      mensaje: msg.isNotEmpty ? msg : 'El beneficio fue utilizado correctamente.',
      codigoAutorizacion: aut,
      fechaHora: DateTime.now(),
    );
  }
}
