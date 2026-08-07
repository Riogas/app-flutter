import 'package:flutter_test/flutter_test.dart';
import 'package:MoveIT/services/modo_ingreso_codigo.dart';

void main() {
  group('ModoIngresoCodigo.desde — valores del contrato', () {
    test('"Manual" → manual', () {
      expect(ModoIngresoCodigo.desde('Manual'), ModoIngresoCodigo.manual);
    });

    test('"QR" → qr', () {
      expect(ModoIngresoCodigo.desde('QR'), ModoIngresoCodigo.qr);
    });

    test('"CodigoBarras" → codigoBarras', () {
      expect(
          ModoIngresoCodigo.desde('CodigoBarras'), ModoIngresoCodigo.barras);
    });
  });

  group('ModoIngresoCodigo.desde — tolerancia a como lo cargue GeneXus', () {
    test('ignora mayúsculas, espacios, guiones y acentos', () {
      for (final v in ['manual', ' MANUAL ', 'Manual ']) {
        expect(ModoIngresoCodigo.desde(v), ModoIngresoCodigo.manual,
            reason: 'valor: "$v"');
      }
      for (final v in ['qr', ' Qr ', 'Codigo QR', 'código_qr', 'QR-Code']) {
        expect(ModoIngresoCodigo.desde(v), ModoIngresoCodigo.qr,
            reason: 'valor: "$v"');
      }
      for (final v in [
        'codigobarras',
        'Codigo de Barras',
        'código-de-barras',
        'CODIGO_BARRAS',
        'Barras',
        'Barcode',
      ]) {
        expect(ModoIngresoCodigo.desde(v), ModoIngresoCodigo.barras,
            reason: 'valor: "$v"');
      }
    });

    test('null, vacío o desconocido → manual (nunca deja la promo inusable)',
        () {
      expect(ModoIngresoCodigo.desde(null), ModoIngresoCodigo.manual);
      expect(ModoIngresoCodigo.desde(''), ModoIngresoCodigo.manual);
      expect(ModoIngresoCodigo.desde('   '), ModoIngresoCodigo.manual);
      expect(ModoIngresoCodigo.desde('NFC'), ModoIngresoCodigo.manual);
      expect(ModoIngresoCodigo.desde('cualquier cosa'),
          ModoIngresoCodigo.manual);
    });

    test('acepta un valor no-String (GeneXus a veces manda números)', () {
      expect(ModoIngresoCodigo.desde(123), ModoIngresoCodigo.manual);
    });
  });

  group('ModoIngresoCodigo — propiedades de presentación', () {
    test('esEscaneo distingue manual de los modos con cámara', () {
      expect(ModoIngresoCodigo.manual.esEscaneo, isFalse);
      expect(ModoIngresoCodigo.qr.esEscaneo, isTrue);
      expect(ModoIngresoCodigo.barras.esEscaneo, isTrue);
    });

    test('cada modo de escaneo trae su texto de botón y su label por defecto',
        () {
      for (final m in [ModoIngresoCodigo.qr, ModoIngresoCodigo.barras]) {
        expect(m.textoBoton.trim(), isNotEmpty);
        expect(m.labelPorDefecto.trim(), isNotEmpty);
        expect(m.instruccion.trim(), isNotEmpty);
      }
    });
  });

  group('ModoIngresoCodigo.normalizarLectura', () {
    test('recorta espacios y saltos de línea que vienen en el símbolo', () {
      expect(ModoIngresoCodigo.normalizarLectura('  ABC-123 \n'), 'ABC-123');
    });

    test('null o vacío → null (no se acepta una lectura vacía)', () {
      expect(ModoIngresoCodigo.normalizarLectura(null), isNull);
      expect(ModoIngresoCodigo.normalizarLectura('   '), isNull);
      expect(ModoIngresoCodigo.normalizarLectura('\n'), isNull);
    });

    test('conserva el contenido tal cual: el server valida, no la app', () {
      const url = 'https://promos.antel.com.uy/c/9F2K-4471';
      expect(ModoIngresoCodigo.normalizarLectura(url), url);
    });
  });
}
