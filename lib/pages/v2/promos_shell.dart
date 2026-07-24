import 'package:flutter/material.dart';

import 'promociones_page.dart';
import 'v2_theme.dart';

/// 🏪 Shell del modo restringido (comercio adherido, escenario 9998).
///
/// Es la raíz completa de la app para ese perfil: una sola pantalla, sin
/// barra inferior, sin tabs de Pedidos ni Mapa. Que esos tabs NO se
/// construyan es parte del requisito: viven en un IndexedStack que los
/// instancia siempre, y PedidosTabV2 arranca un Timer.periodic de 30 s que
/// consulta Geolocator — justo lo que este modo no debe hacer.
///
/// El [Scaffold] no es opcional: PromocionesPage usa ScaffoldMessenger.of()
/// y showModalBottomSheet, que fallan en runtime sin un Scaffold ancestro.
class PromosShell extends StatelessWidget {
  /// Contenido de la pantalla. Por defecto, la página de Promociones en
  /// modo restringido.
  final Widget? child;

  const PromosShell({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // El comercio no tiene a dónde volver: Atrás cerraría la app.
      canPop: false,
      child: Scaffold(
        backgroundColor: V2Colors.fondo,
        body: child ?? const PromocionesPage(modoRestringido: true),
      ),
    );
  }
}
