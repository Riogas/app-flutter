import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:MoveIT/pages/v2/v2_header.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  // ⚠️ LÍMITE DEL ENTORNO DE TEST — leer antes de agregar casos.
  //
  // Solo se pueden pumpear variantes con `mostrarEstado: false`. Con la
  // píldora visible, V2Header construye PersistentStreamManager →
  // FirebaseService → FirebaseFirestore.instance, y en un test eso explota
  // con `[core/no-app] No Firebase App '[DEFAULT]' has been created`.
  // Mockear firebase_core NO es viable: migró a Pigeon y el mock por
  // MethodChannel falla con `channel-error` (probado y descartado).
  //
  // El camino del chofer queda cubierto por el test de defaults de abajo,
  // que NO pumpea nada, más la verificación manual en dispositivo.

  group('V2Header — defaults (regresion del camino del chofer)', () {
    test('los flags nuevos preservan el comportamiento actual', () {
      const header = V2Header();

      expect(header.mostrarEstado, isTrue,
          reason: 'la pildora de movil/estado debe seguir apareciendo');
      expect(header.menuSoloLogout, isFalse,
          reason: 'el menu del avatar debe seguir teniendo Configuracion');
      expect(header.showActions, isTrue);
      expect(header.messageCountNotifier, isNull);
      expect(header.onEstadoTap, isNull);
      expect(header.titulo, isNull);
      expect(header.height, 182);
      expect(header.bottomSpace, 82);
    });
  });

  group('V2Header — modo restringido', () {
    testWidgets('mostrarEstado:false oculta la pildora en modo home',
        (tester) async {
      await tester.pumpWidget(_wrap(const V2Header(mostrarEstado: false)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('v2-estado-pill')), findsNothing);
    });

    testWidgets('mostrarEstado:false oculta la pildora tambien en modo seccion',
        (tester) async {
      await tester.pumpWidget(
          _wrap(const V2Header(titulo: 'Promos', mostrarEstado: false)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('v2-estado-pill')), findsNothing);
      expect(find.text('Promos'), findsOneWidget);
    });

    testWidgets('sin notifier no se dibuja el icono de mensajes',
        (tester) async {
      await tester.pumpWidget(_wrap(const V2Header(mostrarEstado: false)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('v2-mensajes-icon')), findsNothing);
      // El avatar SÍ tiene que estar: es el único acceso a Cerrar sesión.
      expect(find.byKey(const Key('v2-avatar-menu')), findsOneWidget);
    });

    testWidgets('con notifier si se dibuja el icono de mensajes',
        (tester) async {
      await tester.pumpWidget(_wrap(V2Header(
        mostrarEstado: false,
        messageCountNotifier: ValueNotifier<int>(0),
      )));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('v2-mensajes-icon')), findsOneWidget);
    });

    testWidgets('showActions:false oculta mensajes y avatar', (tester) async {
      await tester.pumpWidget(_wrap(V2Header(
        mostrarEstado: false,
        showActions: false,
        messageCountNotifier: ValueNotifier<int>(3),
      )));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('v2-mensajes-icon')), findsNothing);
      expect(find.byKey(const Key('v2-avatar-menu')), findsNothing);
    });

    testWidgets('menu por defecto tiene Configuracion y Cerrar sesion',
        (tester) async {
      await tester.pumpWidget(_wrap(const V2Header(mostrarEstado: false)));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('v2-avatar-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Configuración'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
    });

    testWidgets('menuSoloLogout:true deja solo Cerrar sesion', (tester) async {
      await tester.pumpWidget(
          _wrap(const V2Header(mostrarEstado: false, menuSoloLogout: true)));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('v2-avatar-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Configuración'), findsNothing);
      expect(find.text('Cerrar sesión'), findsOneWidget);
    });
  });
}
