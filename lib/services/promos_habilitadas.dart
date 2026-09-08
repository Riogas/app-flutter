import 'package:flutter/foundation.dart';

import '../utils/constantes.dart';

/// 🎁 Interruptor remoto de Promociones: constante **604** de
/// `Constantes-1000` (`S` habilitadas / `N` deshabilitadas).
///
/// Existe para poder apagar la sección desde Firestore sin publicar una
/// versión nueva, si algo del lado de SGM se rompe.
///
/// **En DESARROLLO la constante se ignora y las promos quedan siempre
/// habilitadas.** El interruptor está para proteger a la flota, no para
/// impedir probar: quien entra eligiendo el servidor de desarrollo necesita
/// poder usar la funcionalidad aunque esté apagada para todos los demás.
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

  /// Lo que dijo la constante la última vez que se leyó, sin considerar el
  /// ambiente.
  static bool _porConstante = true;

  static bool _escuchando = false;

  /// Relee la constante del `constantBox`. Se llama al arrancar y después de
  /// que el login refresca las constantes desde Firestore.
  static Future<void> refrescar() async {
    _escuchar();
    try {
      final v = (await getConstantValue(constante))?.trim().toUpperCase();
      _porConstante = !_apagados.contains(v ?? '');
      print('🎁 [PROMOS] constante $constante = "${v ?? ''}" '
          '→ por constante: $_porConstante');
    } catch (e) {
      print('⚠️ [PROMOS] No se pudo leer la constante $constante: $e');
    }
    _recalcular();
  }

  /// El ambiente se elige DESPUÉS de leer las constantes (en el login, y
  /// también desde Configuración), así que hay que recalcular cuando cambia.
  /// Se engancha una sola vez al notifier de `AppEnvironment` para no tener
  /// que acordarse de llamar a esto en cada lugar que lo cambia.
  static void _escuchar() {
    if (_escuchando) return;
    _escuchando = true;
    AppEnvironment.cambios.addListener(_recalcular);
  }

  static void _recalcular() {
    final enDesarrollo = AppEnvironment.isDevelopment;
    final valor = _porConstante || enDesarrollo;
    if (activas.value != valor) {
      print('🎁 [PROMOS] activas = $valor '
          '(constante: $_porConstante, desarrollo: $enDesarrollo)');
    }
    activas.value = valor;
  }
}
