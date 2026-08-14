import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// ⭐ Memoria local (Hive) de qué promociones validó OK este dispositivo.
///
/// El selector la usa para clavar las "últimas usadas" arriba de la lista:
/// el usuario típico valida siempre las mismas 2 o 3 promos, así las tiene a
/// un tap sin escribir nada. Se registra el uso SOLO cuando la validación
/// contra el servicio da OK — seleccionar una promo equivocada no la sube.
///
/// También concentra la lógica de búsqueda del selector (normalización sin
/// tildes + coincidencia por nombre/descripción) para poder testearla sin
/// Hive ni widgets.
class PromoUsoStore {
  PromoUsoStore._();
  static final PromoUsoStore _instance = PromoUsoStore._();
  factory PromoUsoStore() => _instance;

  @visibleForTesting
  static const String boxName = 'promoUsosBox';

  /// Tope de la sección "Últimas usadas" del selector.
  static const int maxRecientes = 5;

  /// Cache en memoria docId → último uso. El selector es UI síncrona y lee
  /// de acá; el box solo se toca en init() y registrarUso().
  final Map<String, DateTime> _usos = {};

  bool _inicializado = false;

  Future<Box> _box() async => Hive.isBoxOpen(boxName)
      ? Hive.box(boxName)
      : await Hive.openBox(boxName);

  Future<void> init() async {
    if (_inicializado) return;
    _inicializado = true;
    try {
      final box = await _box();
      for (final key in box.keys) {
        final f = DateTime.tryParse(box.get(key)?.toString() ?? '');
        if (f != null) _usos[key.toString()] = f;
      }
    } catch (e) {
      print('⚠️ [PROMO_USOS] Error inicializando: $e');
    }
  }

  /// Registra que la promo validó OK. Nunca lanza: perder el ordenado del
  /// selector no puede romper la validación. La memoria se actualiza aunque
  /// falle la persistencia (el orden vale al menos por esta sesión).
  Future<void> registrarUso(String docId, {DateTime? cuando}) async {
    if (docId.isEmpty) return;
    final momento = cuando ?? DateTime.now();
    _usos[docId] = momento;
    try {
      final box = await _box();
      await box.put(docId, momento.toIso8601String());
    } catch (e) {
      print('⚠️ [PROMO_USOS] Error registrando uso: $e');
    }
  }

  /// Las usadas más recientes primero, tope [maxRecientes]. Solo devuelve
  /// items presentes en `items`: una promo usada que dejó de estar vigente
  /// no aparece.
  List<T> recientes<T>(List<T> items, String Function(T) idDe) {
    final usadas = items.where((it) => _usos.containsKey(idDe(it))).toList()
      ..sort((a, b) => _usos[idDe(b)]!.compareTo(_usos[idDe(a)]!));
    return usadas.take(maxRecientes).toList();
  }

  /// Orden para resultados de búsqueda: primero las usadas (más reciente
  /// arriba), después el resto en su orden original.
  List<T> ordenar<T>(List<T> items, String Function(T) idDe) {
    final usadas = <T>[];
    final resto = <T>[];
    for (final it in items) {
      (_usos.containsKey(idDe(it)) ? usadas : resto).add(it);
    }
    usadas.sort((a, b) => _usos[idDe(b)]!.compareTo(_usos[idDe(a)]!));
    return [...usadas, ...resto];
  }

  @visibleForTesting
  void resetParaTests() {
    _usos.clear();
    _inicializado = false;
  }

  // ── Búsqueda ────────────────────────────────────────────────────────────

  static const Map<String, String> _sinTilde = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    'ñ': 'n', 'ç': 'c',
  };

  /// Minúsculas, sin tildes y sin espacios en los bordes, para comparar.
  static String normalizar(String s) {
    var r = s.toLowerCase().trim();
    _sinTilde.forEach((k, v) => r = r.replaceAll(k, v));
    return r;
  }

  /// ¿La promo matchea lo tipeado? Filtro vacío matchea todo. `id` es el
  /// ID interno de SGM como texto ('' si la promo no lo tiene): se puede
  /// buscar tipeando el número solo o con el numeral ("86" o "#86").
  static bool coincide({
    required String filtro,
    required String nombre,
    String descripcion = '',
    String id = '',
  }) {
    final f = normalizar(filtro);
    if (f.isEmpty) return true;
    if (normalizar(nombre).contains(f) ||
        normalizar(descripcion).contains(f)) {
      return true;
    }
    final fId = f.startsWith('#') ? f.substring(1) : f;
    return id.isNotEmpty && fId.isNotEmpty && id.contains(fId);
  }
}
