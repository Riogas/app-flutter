import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// 🎨 Preferencias de UI persistentes.
/// Viven en `usuarioBox` (misma caja que lastUsername/huella) porque esa caja
/// SOBREVIVE al logout — así la elección de diseño se mantiene entre sesiones.
class UiPrefs {
  UiPrefs._();

  /// true = diseño nuevo (Home V2, rediseño 2026) / false = diseño clásico
  static final ValueNotifier<bool> homeV2 = ValueNotifier<bool>(true);

  static const String _boxName = 'usuarioBox';
  static const String _keyHomeV2 = 'uiHomeV2';

  static bool _loaded = false;

  static Future<void> init() async {
    if (_loaded) return;
    try {
      final box = Hive.isBoxOpen(_boxName)
          ? Hive.box(_boxName)
          : await Hive.openBox(_boxName);
      homeV2.value = box.get(_keyHomeV2, defaultValue: true) as bool;
      _loaded = true;
      print('🎨 [UI_PREFS] homeV2 = ${homeV2.value}');
    } catch (e) {
      print('⚠️ [UI_PREFS] No se pudo leer $_keyHomeV2: $e');
    }
  }

  static Future<void> setHomeV2(bool value) async {
    homeV2.value = value;
    try {
      final box = Hive.isBoxOpen(_boxName)
          ? Hive.box(_boxName)
          : await Hive.openBox(_boxName);
      await box.put(_keyHomeV2, value);
      print('🎨 [UI_PREFS] homeV2 guardado = $value');
    } catch (e) {
      print('⚠️ [UI_PREFS] No se pudo guardar $_keyHomeV2: $e');
    }
  }
}
