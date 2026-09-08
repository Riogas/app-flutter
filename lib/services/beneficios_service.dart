import 'dart:async';

import 'riogas_service.dart';

/// Largo del PIN por SMS cuando el server no manda el código en `OUTAux1`.
/// Hoy la API genera códigos de 4 dígitos (verificado contra el SMS real).
const int kLargoPinPorDefecto = 4;

/// Resultado de validar un beneficio contra la API de la promoción
class BeneficioValidacion {
  final bool ok;
  final bool requierePin;
  final String mensaje; // string dinámico devuelto por la API (beneficio o error)
  final int nroTrn; // NroTrn devuelto por promociones/ValidarPromo (0 si no vino)

  /// PIN que el servicio mandó por SMS al cliente, tal como lo devuelve en
  /// `OUTAux1`. Verificado contra un celular real: el SMS que llega dice
  /// exactamente este número ("...el siguiente PIN: 9169." ⇄ OUTAux1 "9169").
  /// Vacío si la promo no pide SMS o si el server dejara de mandarlo.
  final String codigoSms;

  const BeneficioValidacion({
    required this.ok,
    this.requierePin = false,
    required this.mensaje,
    this.nroTrn = 0,
    this.codigoSms = '',
  });

  /// Cuántos dígitos pedirle al usuario. Sale del largo real del código que
  /// mandó el server, así que si mañana pasan a 5 o 6 la pantalla acompaña
  /// sola. [kLargoPinPorDefecto] cuando no vino (no se puede adivinar).
  int get largoPin =>
      codigoSms.isNotEmpty ? codigoSms.length : kLargoPinPorDefecto;

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
      codigoSms: requierePin
          ? (resp['OUTAux1'] ?? '').toString().replaceAll(RegExp(r'\D'), '')
          : '',
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

  /// `Mdu_MDUID` que devuelve ConsumirPromo: identifica el consumo grabado
  /// en SGM y es lo que pide AnularPromo. 0 si el server no lo mandó.
  final int mduId;

  /// Pre-registración que originó el consumo (`NroTrn` de ValidarPromo).
  final int preMduId;

  const BeneficioConsumo({
    required this.ok,
    required this.mensaje,
    this.codigoAutorizacion,
    this.fechaHora,
    this.mduId = 0,
    this.preMduId = 0,
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
/// `anular()` pega a `promociones/AnularPromo` con el `Mdu_MDUID` que devolvió
/// el consumo; un consumo sin ese id (anterior al cambio) no se puede anular.
class BeneficiosService {
  BeneficiosService._();
  static final BeneficiosService _instance = BeneficiosService._();
  factory BeneficiosService() => _instance;

  String _mensajeBeneficio = '';
  int _ultimoNroTrn = 0;

  /// PIN tecleado por el usuario, ya verificado contra [_codigoSmsEsperado].
  /// Igual viaja en ConsumirPromo (`PreMduCodSMS`): el server es la autoridad,
  /// esto es solo para no mandarlo mal y comerse un rechazo confuso.
  String _pinIngresado = '';

  /// PIN que ValidarPromo dijo haber mandado por SMS (`OUTAux1`). Es el mismo
  /// número que le llega al cliente, así que la pantalla puede avisar al toque
  /// si tecleó mal en vez de esperar al consumo. Vacío = no se puede chequear.
  String _codigoSmsEsperado = '';

  /// Largo que la pantalla del PIN tiene que pedir.
  int get largoPinEsperado => _codigoSmsEsperado.isNotEmpty
      ? _codigoSmsEsperado.length
      : kLargoPinPorDefecto;

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
    String? campoIn2,
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
      'CampoIn2': campoIn2 ?? '',
      // 📦 Pedido al que se asocia la promoción.
      //
      // Solo se manda cuando hay un pedido de verdad. El servicio TODAVÍA no
      // declara este campo (verificado: con él responde 400, y GeneXus
      // rechaza propiedades desconocidas), así que mandarlo en 0 rompería
      // todas las validaciones. Y mandar 0 es idéntico a no mandarlo, porque
      // GX inicializa los numéricos en 0. Cuando lo publiquen y se defina de
      // dónde sale el id, empieza a viajar solo.
      if (pedidoId != 0) 'PreMduPedId': pedidoId,
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

  static int _mduIdDe(Map<String, dynamic> resp) {
    for (final k in ['Mdu_MDUID', 'Mdu_MduId', 'MduId', 'MDUID']) {
      if (resp.containsKey(k)) {
        return BeneficioValidacion._asInt(resp[k], fallback: 0);
      }
    }
    return 0;
  }

  /// Body de `promociones/AnularPromo`.
  ///
  /// ⚠️ Las claves son `Mdu_MDUID` e `INAux1`/`INAux2`, NO las del texto de
  /// la firma (`Mdu_MduId`, `inAux1`): verificado contra el servicio, con esa
  /// otra grafía responde 400. Es el mismo nombre que devuelve ConsumirPromo.
  static Map<String, dynamic> buildAnularPromoBody({
    required String usuario,
    required String deviceId,
    required String movil,
    required int mduId,
    String? inAux1,
    String? inAux2,
  }) {
    return {
      'usuario': usuario,
      'DeviceId': deviceId,
      'movil': _soloDigitos(movil),
      'Mdu_MDUID': mduId,
      'INAux1': inAux1 ?? '',
      'INAux2': inAux2 ?? '',
    };
  }

  Future<BeneficioValidacion> validar({
    required int promoIdInterno,
    required String promoNombre,
    String? codigo,
    String? telefono,
    String? nombre,
    String? auxIn1,
    String? auxIn2,
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
      campoIn2: auxIn2,
    );

    final resp = await RioGasService.validarPromo(body);
    final res = BeneficioValidacion.fromResponse(resp);

    if (res.ok) {
      _usuario = usuario;
      _deviceId = deviceId;
      _movil = movil;
      _pinIngresado = '';
      _codigoSmsEsperado = res.codigoSms;
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

  /// Verifica el PIN tecleado y lo deja listo para el consumo.
  ///
  /// No hay endpoint de confirmación, pero tampoco hace falta: ValidarPromo
  /// devuelve el código en `OUTAux1` y es exactamente el que recibe el cliente
  /// por SMS (comprobado contra un celular real). Así el error sale acá, con
  /// el texto correcto, en vez de aparecer recién al consumir disfrazado de
  /// "No se pudo localizar la validación" (lo que responde el server ante un
  /// PIN equivocado, y que hace pensar que la validación se perdió).
  ///
  /// El PIN igual viaja en `ConsumirPromo` (`PreMduCodSMS`): el server sigue
  /// siendo la autoridad. Si `OUTAux1` viniera vacío no se puede comparar, así
  /// que se acepta el largo esperado y decide el consumo.
  Future<BeneficioPinResultado> registrarPin(String pin) async {
    final limpio = pin.replaceAll(RegExp(r'\D'), '');
    final largo = largoPinEsperado;
    if (limpio.length != largo) {
      return BeneficioPinResultado(
        ok: false,
        mensaje: 'Ingresá los $largo dígitos del código.',
      );
    }
    if (_codigoSmsEsperado.isNotEmpty && limpio != _codigoSmsEsperado) {
      return const BeneficioPinResultado(
        ok: false,
        mensaje: 'El PIN no coincide con el que se envió por SMS. '
            'Revisalo con el cliente o reenviá el código.',
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

  /// Anula un consumo (promociones/AnularPromo). Endpoint REAL.
  ///
  /// Requiere el `Mdu_MDUID` que devolvió ConsumirPromo. Un consumo grabado
  /// antes de que el server devolviera ese id (mduId 0) NO se puede anular
  /// desde la app: se avisa en vez de mentir con un OK local.
  Future<BeneficioConsumo> anular({
    required String autorizacion,
    required int mduId,
    required int promoIdInterno,
    required String promoNombre,
    required String movil,
    required String usuario,
    required String escenario,
    String? deviceId,
  }) async {
    if (mduId <= 0) {
      return const BeneficioConsumo(
        ok: false,
        mensaje:
            'Este consumo no tiene identificador en SGM y no se puede anular desde la app. Comunicate con Riogas.',
      );
    }
    final body = buildAnularPromoBody(
      usuario: usuario.isNotEmpty ? usuario : _usuario,
      deviceId: (deviceId?.isNotEmpty ?? false) ? deviceId! : _deviceId,
      movil: movil.isNotEmpty ? movil : _movil,
      mduId: mduId,
    );
    print('🎁 [ANULAR] POST promociones/AnularPromo: $body');

    final resp = await RioGasService.anularPromo(body);
    // `_post` devuelve null para TODO lo que no sea un 200: timeout de 30s,
    // 400, 500, sin señal. No se puede distinguir cuál fue, y tampoco se
    // sabe si el server llegó a procesar la anulación — por eso el mensaje
    // dice que el consumo sigue como está y que se reintente, en vez de
    // afirmar que no se anuló.
    if (resp == null) {
      return const BeneficioConsumo(
        ok: false,
        mensaje: 'El servicio no respondió, así que el consumo sigue '
            'figurando como consumido. Revisá la conexión y probá de nuevo '
            'en unos minutos.',
      );
    }
    final ok = _okDe(resp) == 0;
    final msg = _mensajeDe(resp);
    return BeneficioConsumo(
      ok: ok,
      mensaje: msg.isNotEmpty
          ? msg
          : (ok
              ? 'El consumo fue anulado correctamente.'
              : 'El servicio no permitió anular este consumo.'),
      codigoAutorizacion: autorizacion,
      fechaHora: DateTime.now(),
      mduId: mduId,
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
    var msg = _mensajeDe(resp);
    if (!ok) {
      // Ante un PIN equivocado el server contesta "No se pudo localizar la
      // validación", que hace pensar que se perdió la validación. Cuando el
      // PIN no se pudo verificar contra OUTAux1 se aclara la otra posibilidad.
      if (_pinIngresado.isNotEmpty && _codigoSmsEsperado.isEmpty) {
        const aclaracion =
            'Verificá que el PIN del SMS sea el correcto: el servicio '
            'responde lo mismo cuando el código no coincide.';
        msg = msg.isNotEmpty ? '$msg\n\n$aclaracion' : aclaracion;
      }
      return BeneficioConsumo(
        ok: false,
        mensaje: msg.isNotEmpty
            ? msg
            : 'No se pudo consumir el beneficio. Intentá nuevamente.',
      );
    }

    // `Mdu_MDUID` = id del consumo grabado en SGM (lo pide AnularPromo). El
    // servicio lo serializa con esa grafía; se lee tolerante por las dudas.
    final mduId = _mduIdDe(resp);
    // La autorización visible: OUTAux1 si el server la manda; si no, el id
    // del consumo; y como último recurso el NroTrn de la validación.
    final outAux1 = (resp['OUTAux1'] ?? '').toString().trim();
    final aut = outAux1.isNotEmpty
        ? outAux1
        : (mduId > 0
            ? 'MDU-$mduId'
            : (_ultimoNroTrn > 0 ? 'TRN-$_ultimoNroTrn' : ''));
    _pinIngresado = '';
    _codigoSmsEsperado = '';
    return BeneficioConsumo(
      ok: true,
      mensaje: msg.isNotEmpty ? msg : 'El beneficio fue utilizado correctamente.',
      codigoAutorizacion: aut,
      fechaHora: DateTime.now(),
      mduId: mduId,
      preMduId: _ultimoNroTrn,
    );
  }
}
