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
}
