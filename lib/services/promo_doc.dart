/// 🎁 Lectura del documento de una promoción (colección Firestore
/// `Promociones`).
///
/// Los documentos los carga gente a mano desde la consola, así que la grafía
/// de las claves varía: `PROMO MIDES` llegó con `idInterno` mientras que el
/// resto usa `IdInterno`. Firestore distingue mayúsculas, así que la lectura
/// directa devolvía null y la promo viajaba con `idCampana: 0` — GeneXus
/// respondía "Esta agencia está incompleta en SGM" y no había forma de
/// adivinarlo desde la app. Acá se busca primero la clave exacta y, si no
/// está, cualquiera que coincida ignorando mayúsculas.
class PromoDoc {
  PromoDoc._();

  /// Valor crudo de [campo], tolerando diferencias de capitalización.
  static dynamic valor(Map<String, dynamic> doc, String campo) {
    if (doc.containsKey(campo)) return doc[campo];

    final buscado = campo.toLowerCase();
    for (final e in doc.entries) {
      if (e.key.toLowerCase() == buscado) return e.value;
    }
    return null;
  }

  /// [campo] como texto recortado. Vacío si falta (= campo oculto).
  static String texto(Map<String, dynamic> doc, String campo) =>
      (valor(doc, campo) ?? '').toString().trim();

  /// Id de la campaña en SGM (`CMPID`), que viaja como `idCampana` a
  /// `promociones/ValidarPromo`. 0 si falta o no es numérico.
  static int idInterno(Map<String, dynamic> doc) {
    final v = valor(doc, 'IdInterno');
    if (v is num) return v.toInt(); // Firestore puede guardarlo como double
    return int.tryParse(v?.toString().trim() ?? '') ?? 0;
  }

  /// Lista de un campo que en Firestore es un array de strings, pero que a
  /// veces viene cargado como texto ("1000, 9998"). Descarta los vacíos.
  static List<String> lista(Map<String, dynamic> doc, String campo) {
    final v = valor(doc, campo);
    final crudos = v is List
        ? v.map((e) => e?.toString() ?? '')
        : (v ?? '').toString().split(RegExp(r'[,;]'));
    return crudos
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  /// ¿Esta promo se le muestra a alguien de [escenario] y [agencia]?
  ///
  /// Las tres listas de la promo se leen igual: **`*` = todos**, y una lista
  /// vacía (o ausente) también deja pasar — así una promo mal cargada se ve
  /// de más y no desaparece en silencio, que es el error caro acá.
  ///
  /// - `EscenariosHabilitados` / `AgenciasHabitadas`: si tienen valores y no
  ///   está el mío, la promo NO se ve.
  /// - `AgenciasNOHabilitadas`: si está el mío, NO se ve (gana sobre la lista
  ///   de habilitadas). Los centinelas que usa la carga (`99999999`, `""`) no
  ///   necesitan tratamiento: simplemente no coinciden con ninguna agencia.
  ///
  /// [agencia] vacía = la app todavía no sabe a qué agencia pertenece (no
  /// llegó el documento del móvil). En ese caso los dos filtros de agencia se
  /// saltean: es preferible mostrar de más a dejar la pantalla vacía.
  static bool habilitadaPara(
    Map<String, dynamic> doc, {
    required String escenario,
    required String agencia,
  }) {
    bool estaEn(List<String> l, String valor) =>
        l.any((e) => e == valor);

    final escenarios = lista(doc, 'EscenariosHabilitados');
    if (escenarios.isNotEmpty &&
        !estaEn(escenarios, '*') &&
        !estaEn(escenarios, escenario.trim())) {
      return false;
    }

    final ag = agencia.trim();
    if (ag.isEmpty) return true;

    if (estaEn(lista(doc, 'AgenciasNOHabilitadas'), ag)) return false;

    final habilitadas = lista(doc, 'AgenciasHabilitadas');
    if (habilitadas.isNotEmpty &&
        !estaEn(habilitadas, '*') &&
        !estaEn(habilitadas, ag)) {
      return false;
    }
    return true;
  }
}
