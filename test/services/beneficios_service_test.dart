import 'package:flutter_test/flutter_test.dart';
import 'package:MoveIT/services/beneficios_service.dart';
import 'package:MoveIT/services/riogas_service.dart';

void main() {
  group('BeneficiosService.buildValidarPromoBody', () {
    test('arma el body con las claves y casing EXACTOS del contrato', () {
      final body = BeneficiosService.buildValidarPromoBody(
        escenario: '9998',
        usuario: '49618553',
        deviceId: 'b00a68bef3451313',
        departamento: 'Montevideo',
        localidad: 'Montevideo',
        latitud: '-34.87',
        longitud: '-56.19',
        idCampana: 7,
        codigoCliente: 'ABC123',
        nombreCliente: 'Juan Pérez',
        telCliente: '099123456',
        campoIn1: 'aux',
        movil: '9998',
      );

      expect(body, {
        'usuario': '49618553',
        'DeviceId': 'b00a68bef3451313',
        'Departamento': 'Montevideo',
        'Localidad': 'Montevideo',
        'Latitud': '-34.87',
        'longitud': '-56.19',
        'idCampana': 7,
        'CodigoCliente': 'ABC123',
        'nombreCliente': 'Juan Pérez',
        'telCliente': '099123456',
        'CampoIn1': 'aux',
        'CampoIn2': '',
        'INAux1': '9998',
        'INAux2': '',
        'movil': 9998,
      });
      // El token NO va acá: lo inyecta RioGasService._post.
      expect(body.containsKey('token'), isFalse);
      // ⚠️ El build DEPLOYADO del servicio GX (2026-07-31) no declara
      // escenarioid y GeneXus responde 400 ante propiedades desconocidas.
      // Cuando GX publique la versión con escenarioid, re-agregarlo acá.
      expect(body.containsKey('escenarioid'), isFalse);
    });

    test('PreMduPedId solo viaja cuando hay un pedido de verdad', () {
      // El servicio todavía no declara el campo y GeneXus responde 400 ante
      // propiedades desconocidas: sin pedido NO se manda (0 es su default).
      final sinPedido = BeneficiosService.buildValidarPromoBody(
        escenario: '9998', usuario: 'u', deviceId: 'd', movil: '336',
        idCampana: 86,
      );
      expect(sinPedido.containsKey('PreMduPedId'), isFalse);

      final conPedido = BeneficiosService.buildValidarPromoBody(
        escenario: '9998', usuario: 'u', deviceId: 'd', movil: '336',
        idCampana: 86, pedidoId: 45123,
      );
      expect(conPedido['PreMduPedId'], 45123);
    });

    test('movil viaja como número, además del INAux1 histórico', () {
      final body = BeneficiosService.buildValidarPromoBody(
        escenario: '9998', usuario: 'u', deviceId: 'd', movil: '336',
        idCampana: 86,
      );
      expect(body['movil'], 336);
      expect(body['INAux1'], '336', reason: 'INAux1 se mantiene como estaba');
    });

    test('movil tolera el id del documento de Firestore ("Moviles-336")', () {
      final body = BeneficiosService.buildValidarPromoBody(
        escenario: '9998', usuario: 'u', deviceId: 'd', movil: 'Moviles-336',
        idCampana: 86,
      );
      expect(body['movil'], 336);
    });

    test('movil vacío o no numérico → 0', () {
      for (final m in ['', '  ', 'sin numero']) {
        final body = BeneficiosService.buildValidarPromoBody(
          escenario: '9998', usuario: 'u', deviceId: 'd', movil: m,
          idCampana: 86,
        );
        expect(body['movil'], 0, reason: 'movil: "$m"');
      }
    });

    test('opcionales null → ""', () {
      final body = BeneficiosService.buildValidarPromoBody(
        escenario: '',
        usuario: 'u',
        deviceId: 'd',
        movil: 'm',
        idCampana: 0,
      );

      expect(body['Departamento'], '');
      expect(body['Localidad'], '');
      expect(body['Latitud'], '');
      expect(body['longitud'], '');
      expect(body['CodigoCliente'], '');
      expect(body['nombreCliente'], '');
      expect(body['telCliente'], '');
      expect(body['CampoIn1'], '');
    });
  });

  group('BeneficiosService.buildConsumirPromoBody', () {
    test('manda EXACTAMENTE los campos del contrato, sin ninguno de más', () {
      final body = BeneficiosService.buildConsumirPromoBody(
        usuario: '49618553',
        deviceId: 'b00a68bef3451313',
        movil: '336',
        preMduId: 4512,
        codSms: '123456',
        direccion: 'Av. Italia 2345',
      );

      expect(body, {
        'usuario': '49618553',
        'DeviceId': 'b00a68bef3451313',
        'movil': 336,
        'PreMduId': 4512,
        'PreMduCodSMS': '123456',
        'Mdu_MduAutDir': 'Av. Italia 2345',
        'CampoIn1': '',
        'CampoIn2': '',
      });
      // El token NO va acá: lo inyecta RioGasService._post.
      expect(body.containsKey('token'), isFalse);
      // GeneXus responde 400 ante propiedades desconocidas (verificado contra
      // el servicio): nada de lo que pedía ValidarPromo puede colarse acá.
      for (final ajeno in [
        'escenarioid',
        'idCampana',
        'CodigoCliente',
        'telCliente',
        'nombreCliente',
        'NroTrn',
        'Latitud',
        'longitud',
        'Departamento',
        'Localidad',
        'INAux1',
        'INAux2',
      ]) {
        expect(body.containsKey(ajeno), isFalse, reason: 'sobra "$ajeno"');
      }
    });

    test('sin PIN ni dirección los campos van vacíos, no nulos', () {
      final body = BeneficiosService.buildConsumirPromoBody(
        usuario: 'u',
        deviceId: 'd',
        movil: 'Moviles-336',
        preMduId: 0,
      );
      expect(body['PreMduCodSMS'], '');
      expect(body['Mdu_MduAutDir'], '');
      expect(body['movil'], 336, reason: 'tolera el id del doc de Firestore');
      expect(body['PreMduId'], 0);
    });

    test('la dirección se recorta a 100 caracteres', () {
      final larga = 'Avenida Muy Larga ' * 20; // 360 chars
      final body = BeneficiosService.buildConsumirPromoBody(
        usuario: 'u',
        deviceId: 'd',
        movil: '1',
        preMduId: 1,
        direccion: larga,
      );
      expect((body['Mdu_MduAutDir'] as String).length, 100);
      expect(body['Mdu_MduAutDir'], larga.trim().substring(0, 100));
    });
  });

  group('BeneficiosService.buildAnularPromoBody', () {
    test('manda EXACTAMENTE los campos del contrato de AnularPromo', () {
      final body = BeneficiosService.buildAnularPromoBody(
        usuario: '49618553',
        deviceId: 'b00a68bef3451313',
        movil: 'Moviles-336',
        mduId: 4512,
      );
      expect(body, {
        'usuario': '49618553',
        'DeviceId': 'b00a68bef3451313',
        'movil': 336,
        'Mdu_MDUID': 4512,
        'INAux1': '',
        'INAux2': '',
      });
      expect(body.containsKey('token'), isFalse);
      // La firma del contrato dice `Mdu_MduId`/`inAux1`, pero el servicio
      // REAL solo acepta esta grafía: con la otra devuelve 400 (verificado).
      expect(body.containsKey('Mdu_MduId'), isFalse);
      expect(body.containsKey('inAux1'), isFalse);
    });
  });

  group('RioGasService.gxRootFromBaseUrl', () {
    test('recorta el segmento de servicios en dev y prod', () {
      expect(
        RioGasService.gxRootFromBaseUrl('https://sgm.riogas.com.uy/appservices/'),
        'https://sgm.riogas.com.uy/',
      );
      expect(
        RioGasService.gxRootFromBaseUrl(
            'https://www.riogas.uy/ica_geos_/appservices/'),
        'https://www.riogas.uy/ica_geos_/',
      );
    });

    test('tolera baseUrl sin barra final', () {
      expect(
        RioGasService.gxRootFromBaseUrl('https://sgm.riogas.com.uy/appservices'),
        'https://sgm.riogas.com.uy/',
      );
    });
  });

  group('BeneficioValidacion.fromResponse', () {
    test('respuesta null (sin conexión / HTTP != 200) → error de conexión',
        () {
      final r = BeneficioValidacion.fromResponse(null);
      expect(r.ok, isFalse);
      expect(r.requierePin, isFalse);
      expect(r.mensaje, contains('conect'));
    });

    test('OK:0 sin SMS → válido con el mensaje del server y NroTrn', () {
      final r = BeneficioValidacion.fromResponse({
        'OK': 0,
        'message': 'El cliente tiene un 20% de descuento.',
        'ReqValidacionSMS': 'N',
        'LabelSMS': '',
        'NroTrn': 4512,
        'OUTAux1': '',
        'OUTAux2': '',
      });
      expect(r.ok, isTrue);
      expect(r.requierePin, isFalse);
      expect(r.mensaje, 'El cliente tiene un 20% de descuento.');
      expect(r.nroTrn, 4512);
    });

    test('OK:0 con ReqValidacionSMS "S" → requiere PIN con LabelSMS', () {
      final r = BeneficioValidacion.fromResponse({
        'OK': 0,
        'message': 'Beneficio disponible.',
        'ReqValidacionSMS': 'S',
        'LabelSMS': 'Ingresá el PIN enviado al celular del cliente',
        'NroTrn': 88,
      });
      expect(r.ok, isTrue);
      expect(r.requierePin, isTrue);
      expect(r.mensaje, 'Ingresá el PIN enviado al celular del cliente');
      expect(r.nroTrn, 88);
    });

    test('ReqValidacionSMS tolera minúsculas y espacios', () {
      final r = BeneficioValidacion.fromResponse({
        'OK': 0,
        'message': 'm',
        'ReqValidacionSMS': ' s ',
        'LabelSMS': '',
      });
      expect(r.requierePin, isTrue);
      // Sin LabelSMS cae al message
      expect(r.mensaje, 'm');
    });

    test('OK distinto de 0 → inválido con el mensaje del server', () {
      final r = BeneficioValidacion.fromResponse({
        'OK': 3,
        'message': 'El beneficio ya fue utilizado.',
        'ReqValidacionSMS': 'N',
      });
      expect(r.ok, isFalse);
      expect(r.requierePin, isFalse);
      expect(r.mensaje, 'El beneficio ya fue utilizado.');
    });

    test('OK != 0 sin message → mensaje genérico no vacío', () {
      final r = BeneficioValidacion.fromResponse({'OK': 1, 'message': ''});
      expect(r.ok, isFalse);
      expect(r.mensaje.trim(), isNotEmpty);
    });

    test('campos ausentes o con tipos raros no explotan', () {
      final r = BeneficioValidacion.fromResponse({
        'OK': '0', // GeneXus a veces manda números como string
        'NroTrn': '77',
      });
      expect(r.ok, isTrue);
      expect(r.nroTrn, 77);
    });
  });
}
