import 'package:flutter_test/flutter_test.dart';
import 'package:MoveIT/services/modo_restringido.dart';

void main() {
  group('normalizarEscenario', () {
    test('deja pasar 1000 sin tocar', () {
      expect(ModoRestringido.normalizarEscenario('1000'), '1000');
    });

    test('deja pasar 9998 sin tocar', () {
      expect(ModoRestringido.normalizarEscenario('9998'), '9998');
    });

    test('aplasta cualquier otro valor a 2000', () {
      expect(ModoRestringido.normalizarEscenario('2000'), '2000');
      expect(ModoRestringido.normalizarEscenario('3000'), '2000');
      expect(ModoRestringido.normalizarEscenario('cualquiera'), '2000');
    });

    test('aplasta null y vacio a 2000', () {
      expect(ModoRestringido.normalizarEscenario(null), '2000');
      expect(ModoRestringido.normalizarEscenario(''), '2000');
    });

    test('acepta el escenario como numero, no solo como String', () {
      expect(ModoRestringido.normalizarEscenario(1000), '1000');
      expect(ModoRestringido.normalizarEscenario(9998), '9998');
      expect(ModoRestringido.normalizarEscenario(2000), '2000');
    });
  });

  group('esRestringido', () {
    test('true solo para 9998', () {
      expect(ModoRestringido.esRestringido('9998'), isTrue);
    });

    test('false para los escenarios normales', () {
      expect(ModoRestringido.esRestringido('1000'), isFalse);
      expect(ModoRestringido.esRestringido('2000'), isFalse);
    });

    test('false para null y vacio', () {
      expect(ModoRestringido.esRestringido(null), isFalse);
      expect(ModoRestringido.esRestringido(''), isFalse);
    });
  });

  group('aplicar', () {
    setUp(() => ModoRestringido.activo.value = false);

    test('enciende el notifier con 9998', () {
      ModoRestringido.aplicar('9998');
      expect(ModoRestringido.activo.value, isTrue);
    });

    test('apaga el notifier con un escenario normal', () {
      ModoRestringido.activo.value = true;
      ModoRestringido.aplicar('2000');
      expect(ModoRestringido.activo.value, isFalse);
    });
  });
}
