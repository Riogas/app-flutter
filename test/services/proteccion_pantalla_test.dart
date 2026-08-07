import 'package:flutter_test/flutter_test.dart';
import 'package:MoveIT/services/proteccion_pantalla.dart';

void main() {
  late List<bool> aplicado;

  setUp(() {
    aplicado = [];
    ProteccionPantalla.resetParaTests(
      aplicador: (bloquear) async => aplicado.add(bloquear),
    );
  });

  group('estado base (flag printScreen del móvil)', () {
    test('arranca sin bloquear', () {
      expect(ProteccionPantalla.bloqueando, isFalse);
    });

    test('la base enciende y apaga el bloqueo', () async {
      await ProteccionPantalla.configurarBase(true);
      expect(ProteccionPantalla.bloqueando, isTrue);
      expect(aplicado, [true]);

      await ProteccionPantalla.configurarBase(false);
      expect(ProteccionPantalla.bloqueando, isFalse);
      expect(aplicado, [true, false]);
    });
  });

  group('pantallas sensibles', () {
    test('adquirir bloquea y liberar desbloquea', () async {
      await ProteccionPantalla.adquirir();
      expect(ProteccionPantalla.bloqueando, isTrue);

      await ProteccionPantalla.liberar();
      expect(ProteccionPantalla.bloqueando, isFalse);
      expect(aplicado, [true, false]);
    });

    test(
        'salir de una pantalla sensible NO apaga la protección del flag global',
        () async {
      await ProteccionPantalla.configurarBase(true);
      await ProteccionPantalla.adquirir();
      await ProteccionPantalla.liberar();

      expect(ProteccionPantalla.bloqueando, isTrue,
          reason: 'el chofer con printScreen=N debe seguir protegido');
      expect(aplicado, isNot(contains(false)),
          reason: 'nunca se le debe soltar el flag a la plataforma');
    });

    test('dos pantallas anidadas: recién con la última se libera', () async {
      await ProteccionPantalla.adquirir(); // Promos
      await ProteccionPantalla.adquirir(); // Escáner encima
      await ProteccionPantalla.liberar(); // cierra el escáner
      expect(ProteccionPantalla.bloqueando, isTrue);
      expect(aplicado, isNot(contains(false)),
          reason: 'cerrar el escáner no puede desproteger Promos');

      await ProteccionPantalla.liberar(); // sale de Promos
      expect(ProteccionPantalla.bloqueando, isFalse);
      expect(aplicado.last, isFalse);
    });

    test('liberar de más no deja el contador en negativo', () async {
      await ProteccionPantalla.liberar();
      await ProteccionPantalla.liberar();
      await ProteccionPantalla.adquirir();

      expect(ProteccionPantalla.bloqueando, isTrue,
          reason: 'un liberar huérfano no puede desarmar el próximo bloqueo');
    });
  });

  group('efectos sobre la plataforma', () {
    test('configurarBase no re-aplica si el estado efectivo no cambió',
        () async {
      await ProteccionPantalla.adquirir();
      await ProteccionPantalla.configurarBase(true);
      await ProteccionPantalla.configurarBase(true);

      expect(aplicado, [true]);
    });

    test(
        'entrar a una pantalla sensible SIEMPRE empuja el flag, aunque el '
        'contador diga que ya estaba bloqueando', () async {
      // En Android el FLAG_SECURE es de la Activity: cualquier código ajeno
      // puede apagarlo por atrás. Si adquirir() confiara en el cache, la
      // pantalla sensible se abriría desprotegida y en silencio.
      await ProteccionPantalla.adquirir(); // Promos
      aplicado.clear();

      await ProteccionPantalla.adquirir(); // el escáner encima

      expect(aplicado, [true]);
    });

    test('reaplicar() fuerza la llamada aunque el estado no haya cambiado',
        () async {
      await ProteccionPantalla.adquirir();
      await ProteccionPantalla.reaplicar();

      expect(aplicado, [true, true],
          reason: 'al volver de background Android puede haber perdido el flag');
    });

    test('un fallo de la plataforma no propaga la excepción', () async {
      ProteccionPantalla.resetParaTests(
        aplicador: (_) async => throw Exception('sin plugin'),
      );
      await expectLater(ProteccionPantalla.adquirir(), completes);
    });
  });
}
