import 'package:flutter_test/flutter_test.dart';
import 'package:MoveIT/services/promo_consumos_store.dart';

void main() {
  group('PromoConsumosStore.enmascarar', () {
    test('nunca revela más de la mitad del código', () {
      // Códigos reales de campañas: hay de 3 y 4 caracteres, donde "mostrar
      // los últimos 4" sería mostrarlo entero.
      expect(PromoConsumosStore.enmascarar('A018'), '••18');
      expect(PromoConsumosStore.enmascarar('100'), '••0');
      expect(PromoConsumosStore.enmascarar('1004'), '••04');
      expect(PromoConsumosStore.enmascarar('692757'), '•••757');
      expect(PromoConsumosStore.enmascarar('25929299'), '••••9299');
    });

    test('tope de 4 visibles aunque el código sea largo', () {
      final m = PromoConsumosStore.enmascarar('ABCDEFGHIJKLMNOPQRST');
      expect(m, '••••QRST');
      expect(m.replaceAll('•', '').length, 4);
    });

    test('código vacío no genera máscara', () {
      expect(PromoConsumosStore.enmascarar(''), '');
      expect(PromoConsumosStore.enmascarar('   '), '');
    });

    test('la máscara nunca contiene el código completo', () {
      for (final c in ['A018', '100', '692757', '25929299', 'ABCDLB']) {
        expect(PromoConsumosStore.enmascarar(c).contains(c), isFalse,
            reason: 'se filtró el código "\$c"');
      }
    });
  });

  group('modelo de PromoConsumo', () {
    test('un registro viejo con el código entero se lee enmascarado', () {
      final c = PromoConsumo.fromMap('1', {
        'promo': 'Antel',
        'codigo': '692757', // formato anterior
        'fechaHora': DateTime(2026, 8, 19, 10).toIso8601String(),
      });
      expect(c.codigoMascara, '•••757');
    });

    test('toMap no persiste el código entero', () {
      final c = PromoConsumo(
        id: '1',
        promo: 'Antel',
        idInterno: 17,
        codigoMascara: PromoConsumosStore.enmascarar('692757'),
        telefono: '099',
        cliente: 'X',
        beneficio: 'b',
        autorizacion: 'MDU-9',
        fechaHora: DateTime(2026, 8, 19, 10),
        mduId: 9,
        preMduId: 4512,
      );
      final m = c.toMap();
      expect(m.containsKey('codigo'), isFalse);
      expect(m['codigoMascara'], '•••757');
      expect(m['mduId'], 9);
      expect(m['preMduId'], 4512, reason: 'hilo hacia la validación');
      expect(m.values.join(' ').contains('692757'), isFalse);
    });
  });
}
