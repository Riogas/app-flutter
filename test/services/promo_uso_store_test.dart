import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:MoveIT/services/promo_uso_store.dart';

void main() {
  group('PromoUsoStore.normalizar', () {
    test('minúsculas, sin tildes y sin espacios en los bordes', () {
      expect(PromoUsoStore.normalizar('  Teléfono ANTEL  '), 'telefono antel');
      expect(PromoUsoStore.normalizar('Peñarol'), 'penarol');
      expect(PromoUsoStore.normalizar('Güemes'), 'guemes');
      expect(PromoUsoStore.normalizar(''), '');
    });
  });

  group('PromoUsoStore.coincide', () {
    test('filtro vacío o solo espacios matchea todo', () {
      expect(PromoUsoStore.coincide(filtro: '', nombre: 'Antel'), isTrue);
      expect(PromoUsoStore.coincide(filtro: '   ', nombre: 'Antel'), isTrue);
    });

    test('matchea por nombre sin importar tildes ni mayúsculas', () {
      expect(
        PromoUsoStore.coincide(filtro: 'telefono', nombre: 'Teléfono Antel'),
        isTrue,
      );
      expect(
        PromoUsoStore.coincide(filtro: 'TELÉFONO', nombre: 'telefono antel'),
        isTrue,
      );
    });

    test('matchea por descripción cuando el nombre no alcanza', () {
      expect(
        PromoUsoStore.coincide(
          filtro: 'recarga',
          nombre: 'Promo Antel',
          descripcion: 'Recarga de saldo con descuento',
        ),
        isTrue,
      );
    });

    test('sin coincidencia devuelve false', () {
      expect(
        PromoUsoStore.coincide(
          filtro: 'mides',
          nombre: 'Promo Antel',
          descripcion: 'Recarga de saldo',
        ),
        isFalse,
      );
    });

    test('matchea por ID interno, con o sin numeral', () {
      expect(
        PromoUsoStore.coincide(filtro: '86', nombre: 'Mides', id: '86'),
        isTrue,
      );
      expect(
        PromoUsoStore.coincide(filtro: '#86', nombre: 'Mides', id: '86'),
        isTrue,
      );
      expect(
        PromoUsoStore.coincide(filtro: '8', nombre: 'Mides', id: '86'),
        isTrue,
        reason: 'parcial también filtra',
      );
      expect(
        PromoUsoStore.coincide(filtro: '99', nombre: 'Mides', id: '86'),
        isFalse,
      );
    });

    test('el nombre sigue matcheando aunque se pase id', () {
      expect(
        PromoUsoStore.coincide(filtro: 'mides', nombre: 'Promo Mides', id: '86'),
        isTrue,
      );
    });

    test('promo sin id (id vacío) no matchea por número', () {
      expect(
        PromoUsoStore.coincide(filtro: '86', nombre: 'Promo Antel', id: ''),
        isFalse,
      );
      expect(
        PromoUsoStore.coincide(filtro: '#', nombre: 'Promo Antel', id: '86'),
        isFalse,
        reason: 'numeral solo no matchea todo',
      );
    });
  });

  group('PromoUsoStore recientes/ordenar', () {
    late PromoUsoStore store;
    late Directory tempDir;

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('promo_uso_test');
      Hive.init(tempDir.path);
    });

    tearDownAll(() async {
      await Hive.deleteFromDisk();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      store = PromoUsoStore();
      store.resetParaTests();
      if (Hive.isBoxOpen(PromoUsoStore.boxName)) {
        await Hive.box(PromoUsoStore.boxName).clear();
      }
    });

    test('sin usos: recientes vacío y ordenar respeta el orden original', () {
      final items = ['a', 'b', 'c'];
      expect(store.recientes(items, (s) => s), isEmpty);
      expect(store.ordenar(items, (s) => s), ['a', 'b', 'c']);
    });

    test('las usadas van primero, la más reciente arriba', () async {
      final items = ['a', 'b', 'c', 'd'];
      await store.registrarUso('c', cuando: DateTime(2026, 8, 14, 10));
      await store.registrarUso('a', cuando: DateTime(2026, 8, 14, 12));

      expect(store.recientes(items, (s) => s), ['a', 'c']);
      expect(store.ordenar(items, (s) => s), ['a', 'c', 'b', 'd']);
    });

    test('volver a usar una promo la sube arriba', () async {
      await store.registrarUso('a', cuando: DateTime(2026, 8, 14, 10));
      await store.registrarUso('b', cuando: DateTime(2026, 8, 14, 11));
      await store.registrarUso('a', cuando: DateTime(2026, 8, 14, 12));

      expect(store.recientes(['a', 'b'], (s) => s), ['a', 'b']);
    });

    test('recientes respeta el tope maxRecientes', () async {
      final items = List.generate(10, (i) => 'p$i');
      for (var i = 0; i < 8; i++) {
        await store.registrarUso('p$i', cuando: DateTime(2026, 8, 1 + i));
      }
      final rec = store.recientes(items, (s) => s);
      expect(rec.length, PromoUsoStore.maxRecientes);
      expect(rec.first, 'p7', reason: 'la más reciente primero');
    });

    test('una usada que ya no está vigente no aparece en recientes', () async {
      await store.registrarUso('vieja', cuando: DateTime(2026, 8, 14));
      expect(store.recientes(['a', 'b'], (s) => s), isEmpty);
      expect(store.ordenar(['a', 'b'], (s) => s), ['a', 'b']);
    });

    test('registrarUso con docId vacío no registra nada', () async {
      await store.registrarUso('');
      expect(store.recientes([''], (s) => s), isEmpty);
    });

    test('los usos sobreviven al reinicio de la app (init recarga del box)',
        () async {
      await store.registrarUso('a', cuando: DateTime(2026, 8, 14, 10));
      await store.registrarUso('b', cuando: DateTime(2026, 8, 14, 12));

      store.resetParaTests(); // simula reinicio: memoria vacía
      expect(store.recientes(['a', 'b'], (s) => s), isEmpty);

      await store.init();
      expect(store.recientes(['a', 'b'], (s) => s), ['b', 'a']);
    });
  });
}
