import 'package:flutter/foundation.dart';

import '../utils/constantes.dart';

/// 🎁 Interruptor remoto de Promociones: constante **604** de
/// `Constantes-1000` (`S` habilitadas / `N` deshabilitadas).
///
/// Existe para poder apagar la sección desde Firestore sin publicar una
/// versión nueva, si algo del lado de SGM se rompe.
///
/// Ante la duda queda HABILITADO. Si la constante falta, está inactiva o el
/// `constantBox` todavía no se cargó, `getConstantValue` devuelve null: no
/// corresponde dejar sin promos a quien las tiene funcionando por una lectura
/// que no salió. Apagarlas es una acción deliberada, y para eso hay que
/// escribir "N".
class PromosHabilitadas {
  PromosHabilitadas._();

  /// Id de la constante en `Constantes-1000`.
  static const String constante = '604';

  /// Para que la UI reaccione sin releer Hive en cada build.
  static final ValueNotifier<bool> activas = ValueNotifier<bool>(true);

  /// Valores que apagan la sección. Se aceptan varias grafías porque la
  /// constante se carga a mano y el día que alguien escriba "false" o "0"
  /// tiene que apagarse igual.
  static const _apagados = {'N', 'NO', 'FALSE', '0'};

  /// Relee la constante del `constantBox`. Se llama al arrancar y después de
  /// que el login refresca las constantes desde Firestore.
  static Future<void> refrescar() async {
    try {
      final v = (await getConstantValue(constante))?.trim().toUpperCase();
      activas.value = !_apagados.contains(v ?? '');
      print('🎁 [PROMOS] constante $constante = "${v ?? ''}" '
          '→ activas = ${activas.value}');
    } catch (e) {
      print('⚠️ [PROMOS] No se pudo leer la constante $constante: $e');
    }
  }
}
