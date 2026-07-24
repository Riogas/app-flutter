import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:MoveIT/pages/v2/promos_shell.dart';

void main() {
  // El test pasa un `child` explícito a propósito: así el shell no construye
  // PromocionesPage, que tocaría Firestore y Hive.
  group('PromosShell', () {
    testWidgets('provee un Scaffold propio', (tester) async {
      // PromocionesPage necesita un Scaffold ancestro porque usa
      // ScaffoldMessenger.of(context) y showModalBottomSheet.
      await tester.pumpWidget(const MaterialApp(
        home: PromosShell(child: Text('contenido')),
      ));

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('contenido'), findsOneWidget);
    });

    testWidgets('no tiene barra de navegacion inferior', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: PromosShell(child: Text('contenido')),
      ));

      expect(find.byType(BottomNavigationBar), findsNothing);
    });

    testWidgets('bloquea el boton Atras para que no cierre la app',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: PromosShell(child: Text('contenido')),
      ));

      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });
  });
}
