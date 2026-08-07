import 'package:screen_protector/screen_protector.dart';

/// Función que efectivamente prende/apaga la protección en la plataforma.
/// Se inyecta en tests para no depender del plugin.
typedef AplicadorProteccion = Future<void> Function(bool bloquear);

/// 🔒 Dueño único del anti-captura (screenshot y grabación de pantalla).
///
/// Hay DOS fuentes que pueden pedir el bloqueo y antes se pisaban entre sí:
///
/// 1. **Base**: el flag `printScreen` del documento `Moviles-{escenario}/
///    Moviles-{movil}` (lo configura operaciones; `'N'` = bloquear). Aplica a
///    toda la sesión del chofer.
/// 2. **Pantallas sensibles**: Promociones y el escáner, que manejan códigos
///    de beneficios y datos del cliente. Bloquean mientras están montadas,
///    sin importar el flag (el comercio 9998 ni siquiera tiene documento de
///    móvil, así que la base nunca se le enciende).
///
/// En Android el `FLAG_SECURE` es de la Activity, no de la ruta: si Promos
/// apagara el bloqueo al salir, dejaría descubierto al chofer que lo tenía
/// encendido por el flag. Por eso acá se lleva un contador y se aplica el OR
/// de ambas fuentes.
class ProteccionPantalla {
  ProteccionPantalla._();

  static Future<void> _aplicadorReal(bool bloquear) => bloquear
      ? ScreenProtector.preventScreenshotOn()
      : ScreenProtector.preventScreenshotOff();

  static AplicadorProteccion _aplicador = _aplicadorReal;

  static bool _base = false;
  static int _pantallas = 0;
  static bool? _ultimoAplicado;

  /// Estado efectivo: alcanza con que UNA de las fuentes lo pida.
  static bool get bloqueando => _base || _pantallas > 0;

  /// Flag `printScreen` del móvil. Lo llama el listener de Firestore.
  static Future<void> configurarBase(bool activa) async {
    _base = activa;
    await _sincronizar();
  }

  /// Entra una pantalla sensible.
  static Future<void> adquirir() async {
    _pantallas++;
    await _sincronizar();
  }

  /// Sale una pantalla sensible. Nunca baja de cero: un `liberar()` huérfano
  /// (doble dispose, pantalla que se cierra dos veces) dejaría el contador en
  /// negativo y el próximo `adquirir()` no bloquearía.
  static Future<void> liberar() async {
    if (_pantallas > 0) _pantallas--;
    await _sincronizar();
  }

  /// Vuelve a empujar el estado a la plataforma aunque no haya cambiado.
  /// Al volver de background algunos equipos pierden el `FLAG_SECURE`.
  static Future<void> reaplicar() async {
    _ultimoAplicado = null;
    await _sincronizar();
  }

  static Future<void> _sincronizar() async {
    final objetivo = bloqueando;
    if (_ultimoAplicado == objetivo) return;
    _ultimoAplicado = objetivo;
    try {
      await _aplicador(objetivo);
    } catch (e) {
      // Nunca romper la pantalla por el anti-captura: si el plugin falla, se
      // registra y se sigue. Se limpia el cache para reintentar la próxima.
      _ultimoAplicado = null;
      print('⚠️ [PROTECCION_PANTALLA] No se pudo aplicar ($objetivo): $e');
    }
  }

  static void resetParaTests({required AplicadorProteccion aplicador}) {
    _aplicador = aplicador;
    _base = false;
    _pantallas = 0;
    _ultimoAplicado = null;
  }
}
