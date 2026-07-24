import 'package:flutter_test/flutter_test.dart';
import 'package:MoveIT/services/movil_selection.dart';

void main() {
  const unMovil = [
    {'id': '101', 'displayValue': 'Movil 101'}
  ];
  const dosMoviles = [
    {'id': '101', 'displayValue': 'Movil 101'},
    {'id': '102', 'displayValue': 'Movil 102'},
  ];

  group('MovilSelection.decidir', () {
    test('lista vacia → sinMoviles', () {
      expect(
        MovilSelection.decidir(moviles: const [], pideMatricula: false),
        AccionMovil.sinMoviles,
      );
    });

    test('lista vacia con matricula obligatoria tambien → sinMoviles', () {
      expect(
        MovilSelection.decidir(moviles: const [], pideMatricula: true),
        AccionMovil.sinMoviles,
      );
    });

    test('un movil sin matricula → autoSeleccionar', () {
      expect(
        MovilSelection.decidir(moviles: unMovil, pideMatricula: false),
        AccionMovil.autoSeleccionar,
      );
    });

    test('un movil con matricula obligatoria → pedirMatricula', () {
      expect(
        MovilSelection.decidir(moviles: unMovil, pideMatricula: true),
        AccionMovil.pedirMatricula,
      );
    });

    test('varios moviles → mostrarDialogo', () {
      expect(
        MovilSelection.decidir(moviles: dosMoviles, pideMatricula: false),
        AccionMovil.mostrarDialogo,
      );
    });

    test('varios moviles con matricula → mostrarDialogo (el dialogo ya la pide)',
        () {
      expect(
        MovilSelection.decidir(moviles: dosMoviles, pideMatricula: true),
        AccionMovil.mostrarDialogo,
      );
    });
  });

  group('MovilSelection.idUnico', () {
    test('devuelve el id cuando hay exactamente uno', () {
      expect(MovilSelection.idUnico(unMovil), '101');
    });

    test('devuelve null cuando hay cero o mas de uno', () {
      expect(MovilSelection.idUnico(const []), isNull);
      expect(MovilSelection.idUnico(dosMoviles), isNull);
    });
  });
}
