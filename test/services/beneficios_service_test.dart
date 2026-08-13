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
