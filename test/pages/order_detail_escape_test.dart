import 'package:flutter_test/flutter_test.dart';
import 'package:MoveIT/pages/order_detail_page.dart';

void main() {
  group('escaparPseudoEtiquetas', () {
    test('rescata el texto de autorización que el WebView se tragaba', () {
      // Caso REAL del pedido 17077291: GeneXus manda esto sin escapar y el
      // parser del WebView lo tomaba como una etiqueta, dejando un "<>".
      const crudo =
          '<B><<ASOFUNPOR: AUT-1322469 \$1341.00 #1(Tarj.7207)>></B>';
      final out = escaparPseudoEtiquetas(crudo);
      expect(out, '<B>&lt;&lt;ASOFUNPOR: AUT-1322469 \$1341.00 #1(Tarj.7207)>></B>');
      expect(out, startsWith('<B>'), reason: 'el <B> real no se toca');
    });

    test('no toca las etiquetas que el backend usa de verdad', () {
      const html = "<table><tr><th scope='row'>Tel:</th>"
          "<td><a href='tel:+59823236658'>+59823236658</a></td></tr></table>"
          "<center><img src='https://x/y.png'/></center><br><hr/>";
      expect(escaparPseudoEtiquetas(html), html);
    });

    test('escapa un "<" suelto usado como signo de menor', () {
      expect(escaparPseudoEtiquetas('Cant < 7 y 9 > 2'),
          'Cant &lt; 7 y 9 > 2');
    });

    test('respeta comentarios y doctype', () {
      expect(escaparPseudoEtiquetas('<!-- nota --><!DOCTYPE html>'),
          '<!-- nota --><!DOCTYPE html>');
    });

    test('cierres con barra tampoco se rompen', () {
      expect(escaparPseudoEtiquetas('<b>x</b></tr>'), '<b>x</b></tr>');
    });

    test('una etiqueta inventada se escapa (no se traga el contenido)', () {
      expect(escaparPseudoEtiquetas('<FOO>hola</FOO>'),
          '&lt;FOO>hola&lt;/FOO>');
    });
  });
}
