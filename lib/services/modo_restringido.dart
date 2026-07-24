import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// 🏪 Modo restringido: perfil "comercio adherido" (escenario 9998).
///
/// Este es el ÚNICO lugar del repositorio que conoce el número 9998.
/// Nadie más debe compararlo contra un literal.
///
/// El escenario ES el flag: no se guarda un booleano duplicado en Hive,
/// para no tener dos verdades que puedan divergir.
class ModoRestringido {
  ModoRestringido._();

  /// Escenario del comercio adherido: solo ve Promociones, sin GPS continuo.
  static const String escenarioComercio = '9998';

  /// Escenario histórico que muestra matrícula en el combo de móviles.
  static const String escenarioMatricula = '1000';

  /// Escenario por defecto para todo lo demás.
  static const String escenarioPorDefecto = '2000';

  /// Notifier para que la UI reaccione sin releer Hive.
  static final ValueNotifier<bool> activo = ValueNotifier<bool>(false);

  /// Whitelist del escenario que devuelve el backend.
  ///
  /// Históricamente la app aplastaba TODO lo distinto de "1000" a "2000".
  /// Se mantiene ese comportamiento salvo para 9998, que ahora pasa entero.
  /// Es una whitelist a propósito: así ningún usuario existente cambia de
  /// colección Firestore por accidente si el backend devuelve algo inesperado.
  static String normalizarEscenario(dynamic raw) {
    final s = raw?.toString();
    if (s == escenarioMatricula) return escenarioMatricula;
    if (s == escenarioComercio) return escenarioComercio;
    return escenarioPorDefecto;
  }

  static bool esRestringido(String? escenario) =>
      escenario == escenarioComercio;

  /// Setea [activo] a partir de un escenario ya normalizado.
  static void aplicar(String? escenario) {
    activo.value = esRestringido(escenario);
    print('🏪 [MODO_RESTRINGIDO] escenario=$escenario → activo=${activo.value}');
  }

  /// Lee el escenario persistido y setea [activo]. Se llama en el arranque
  /// en frío, donde no hay respuesta de login de la cual derivarlo.
  static Future<void> init() async {
    try {
      final box = Hive.isBoxOpen('sessionBox')
          ? Hive.box('sessionBox')
          : await Hive.openBox('sessionBox');
      aplicar(box.get('escenario')?.toString());
    } catch (e) {
      print('⚠️ [MODO_RESTRINGIDO] No se pudo leer el escenario: $e');
      activo.value = false;
    }
  }
}
