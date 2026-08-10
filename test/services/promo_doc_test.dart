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
}
