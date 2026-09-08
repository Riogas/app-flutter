import 'package:flutter_test/flutter_test.dart';
import 'package:MoveIT/services/promo_doc.dart';

void main() {
  group('PromoDoc.valor — tolerante a la grafía de la clave', () {
    test('encuentra la clave tal cual está escrita', () {
      expect(PromoDoc.valor({'IdInterno': 86}, 'IdInterno'), 86);
    });

    test('encuentra la clave aunque cambie la capitalización', () {
      // Caso real: el doc de PROMO MIDES vino con "idInterno" y la app
      // buscaba "IdInterno", así que mandaba idCampana 0.
      expect(PromoDoc.valor({'idInterno': 86}, 'IdInterno'), 86);
      expect(PromoDoc.valor({'IDINTERNO': 86}, 'IdInterno'), 86);
      expect(PromoDoc.valor({'labelcodcliente': 'PIN'}, 'LabelCodCliente'),
          'PIN');
    });

    test('si están las dos grafías, gana la exacta', () {
      final doc = {'IdInterno': 86, 'idInterno': 99};
      expect(PromoDoc.valor(doc, 'IdInterno'), 86);
    });

    test('clave ausente → null', () {
      expect(PromoDoc.valor({'Otra': 1}, 'IdInterno'), isNull);
      expect(PromoDoc.valor(const {}, 'IdInterno'), isNull);
    });
  });

  group('PromoDoc.texto', () {
    test('recorta espacios', () {
      expect(PromoDoc.texto({'LabelCodCliente': '  PIN Antel '},
          'LabelCodCliente'), 'PIN Antel');
    });

    test('ausente o null → cadena vacía (campo oculto, como siempre)', () {
      expect(PromoDoc.texto(const {}, 'LabelCodCliente'), '');
      expect(PromoDoc.texto({'LabelCodCliente': null}, 'LabelCodCliente'), '');
    });

    test('respeta la grafía alternativa', () {
      expect(PromoDoc.texto({'labelNomCliente': 'Nombre'}, 'LabelNomCliente'),
          'Nombre');
    });
  });

  group('PromoDoc.idInterno', () {
    test('lee el id con cualquiera de las dos grafías', () {
      expect(PromoDoc.idInterno({'IdInterno': 86}), 86);
      expect(PromoDoc.idInterno({'idInterno': 86}), 86);
    });

    test('acepta el número como string', () {
      expect(PromoDoc.idInterno({'idInterno': '86'}), 86);
      expect(PromoDoc.idInterno({'idInterno': ' 86 '}), 86);
    });

    test('acepta un double (Firestore guarda números como double)', () {
      expect(PromoDoc.idInterno({'idInterno': 86.0}), 86);
    });

    test('ausente, vacío o no numérico → 0', () {
      expect(PromoDoc.idInterno(const {}), 0);
      expect(PromoDoc.idInterno({'idInterno': ''}), 0);
      expect(PromoDoc.idInterno({'idInterno': 'ochenta y seis'}), 0);
      expect(PromoDoc.idInterno({'idInterno': null}), 0);
    });
  });

  group('PromoDoc.habilitadaPara', () {
    // Valores REALES de la colección: 26 de 27 promos traen ['*'] en
    // habilitadas y ['99999999'] en NO habilitadas (centinela de "ninguna").
    Map<String, dynamic> promo({
      dynamic esc = const ['*'],
      dynamic ok = const ['*'],
      dynamic no = const ['99999999'],
    }) =>
        {
          'EscenariosHabilitados': esc,
          'AgenciasHabilitadas': ok,
          'AgenciasNOHabilitadas': no,
        };

    test('la promo abierta ("*" en todo) se ve siempre', () {
      expect(
          PromoDoc.habilitadaPara(promo(), escenario: '1000', agencia: '1'),
          isTrue);
    });

    test('escenario que no está en la lista la oculta', () {
      final p = promo(esc: ['9998']);
      expect(PromoDoc.habilitadaPara(p, escenario: '1000', agencia: '1'),
          isFalse);
      expect(PromoDoc.habilitadaPara(p, escenario: '9998', agencia: '1'),
          isTrue);
    });

    test('solo la agencia habilitada la ve (caso real de la promo 53)', () {
      // MERCEDES: AgenciasHabilitadas ['10000141','113'].
      final p = promo(ok: ['10000141', '113']);
      expect(PromoDoc.habilitadaPara(p, escenario: '1000', agencia: '113'),
          isTrue);
      expect(PromoDoc.habilitadaPara(p, escenario: '1000', agencia: '1'),
          isFalse, reason: 'RIOGAS PLANTA no es Mercedes');
    });

    test('estar en NO habilitadas gana sobre el "*" de habilitadas', () {
      final p = promo(no: ['7']);
      expect(PromoDoc.habilitadaPara(p, escenario: '1000', agencia: '7'),
          isFalse);
      expect(PromoDoc.habilitadaPara(p, escenario: '1000', agencia: '8'),
          isTrue);
    });

    test('los centinelas de la carga no bloquean a nadie', () {
      for (final n in [
        ['99999999'],
        [''],
        <String>[],
      ]) {
        expect(PromoDoc.habilitadaPara(promo(no: n),
            escenario: '1000', agencia: '1'), isTrue,
            reason: 'NO habilitadas: $n');
      }
    });

    test('sin agencia conocida NO se esconde nada por agencia', () {
      // El doc del móvil todavía no llegó: mostrar de más es preferible a
      // dejar la pantalla vacía sin que nadie entienda por qué.
      final p = promo(ok: ['113'], no: ['1']);
      expect(PromoDoc.habilitadaPara(p, escenario: '1000', agencia: ''),
          isTrue);
      expect(PromoDoc.habilitadaPara(p, escenario: '1000', agencia: '  '),
          isTrue);
    });

    test('el escenario SÍ se aplica aunque no se sepa la agencia', () {
      expect(
          PromoDoc.habilitadaPara(promo(esc: ['9998']),
              escenario: '1000', agencia: ''),
          isFalse);
    });

    test('listas ausentes o vacías dejan pasar (promo mal cargada se ve)', () {
      expect(PromoDoc.habilitadaPara(<String, dynamic>{},
          escenario: '1000', agencia: '1'), isTrue);
      expect(
          PromoDoc.habilitadaPara(promo(esc: <String>[], ok: <String>[]),
              escenario: '1000', agencia: '1'),
          isTrue);
    });

    test('tolera que la lista venga como texto separado por comas', () {
      final p = promo(esc: '1000, 9998', ok: '113;10000141');
      expect(PromoDoc.habilitadaPara(p, escenario: '9998', agencia: '113'),
          isTrue);
      expect(PromoDoc.habilitadaPara(p, escenario: '2000', agencia: '113'),
          isFalse);
      expect(PromoDoc.habilitadaPara(p, escenario: '1000', agencia: '7'),
          isFalse);
    });

    test('PromoDoc.lista descarta vacíos y recorta', () {
      expect(PromoDoc.lista({'x': [' 1 ', '', '  ', '2']}, 'x'), ['1', '2']);
      expect(PromoDoc.lista(<String, dynamic>{}, 'x'), isEmpty);
    });
  });

  group('PromoDoc.requisito', () {
    Map<String, dynamic> doc(String label, String req) =>
        {'LabelAuxIn1': label, 'ReqAuxIn1': req};

    RequisitoCampo leer(Map<String, dynamic> d,
            {RequisitoCampo porDefecto = RequisitoCampo.opcional}) =>
        PromoDoc.requisito(d,
            campoLabel: 'LabelAuxIn1',
            campoReq: 'ReqAuxIn1',
            porDefecto: porDefecto);

    test('los tres valores que escriben en los documentos', () {
      // Antel llega con "Obligatorio"/"No"; antes se comparaba contra
      // "Requerido" y el campo obligatorio caía entre los opcionales.
      expect(leer(doc('Observaciones', 'Obligatorio')),
          RequisitoCampo.obligatorio);
      expect(leer(doc('Observaciones', 'Opcional')), RequisitoCampo.opcional);
      expect(leer(doc('Obs2', 'No')), RequisitoCampo.no);
    });

    test('tolera mayúsculas y las grafías viejas', () {
      expect(leer(doc('Obs', 'OBLIGATORIO')), RequisitoCampo.obligatorio);
      expect(leer(doc('Obs', 'Requerido')), RequisitoCampo.obligatorio);
      expect(leer(doc('Obs', 'S')), RequisitoCampo.obligatorio);
      expect(leer(doc('Obs', ' opcional ')), RequisitoCampo.opcional);
      expect(leer(doc('Obs', 'N')), RequisitoCampo.no);
    });

    test('sin rótulo no hay campo, aunque el Req diga que es obligatorio', () {
      expect(leer(doc('', 'Obligatorio')), RequisitoCampo.no);
      expect(leer(doc('   ', 'Obligatorio')), RequisitoCampo.no);
    });

    test('un Req vacío o desconocido cae al valor por defecto', () {
      expect(leer(doc('Obs', '')), RequisitoCampo.opcional);
      expect(leer(doc('Obs', 'cualquier cosa')), RequisitoCampo.opcional);
      expect(leer(doc('Obs', ''), porDefecto: RequisitoCampo.obligatorio),
          RequisitoCampo.obligatorio);
    });

    test('el Req también tolera la grafía de la clave', () {
      final d = {'LabelAuxIn1': 'Obs', 'reqauxin1': 'Obligatorio'};
      expect(leer(d), RequisitoCampo.obligatorio);
    });
  });
}
