/// 📷 Cómo carga el usuario el código de la promoción.
///
/// Sale del campo `ComoSeIngresaElCodigo` de la colección Firestore
/// `Promociones` (lo configura GeneXus). El código termina viajando SIEMPRE
/// en `CodigoCliente` de `promociones/ValidarPromo`: lo único que cambia es
/// cómo lo obtiene el usuario (tecleado vs. cámara).
enum ModoIngresoCodigo {
  /// Campo de texto, como fue siempre.
  manual,

  /// Escaneo de QR con la cámara.
  qr,

  /// Escaneo de código de barras (EAN/UPC/Code128/…).
  barras;

  /// Valor de `ComoSeIngresaElCodigo` que representa a este modo.
  static const String campoFirestore = 'ComoSeIngresaElCodigo';

  /// Interpreta el valor crudo de Firestore.
  ///
  /// Es deliberadamente tolerante (mayúsculas, acentos, espacios, guiones) y
  /// cae en [manual] ante null/vacío/desconocido: tipear siempre funciona, así
  /// que un valor mal cargado degrada a la pantalla de hoy en vez de dejar la
  /// promoción inusable.
  static ModoIngresoCodigo desde(dynamic valor) {
    final v = _normalizar(valor?.toString());
    if (v.isEmpty) return manual;

    if (v.contains('barra') || v.contains('barcode') || v.contains('ean')) {
      return barras;
    }
    if (v.contains('qr')) return qr;
    return manual;
  }

  /// minúsculas, sin acentos y sin separadores: "Código de Barras" → "codigodebarras"
  static String _normalizar(String? raw) {
    if (raw == null) return '';
    var v = raw.trim().toLowerCase();
    const acentos = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    };
    acentos.forEach((k, r) => v = v.replaceAll(k, r));
    return v.replaceAll(RegExp(r'[\s._\-/]'), '');
  }

  /// Limpia una lectura de la cámara. Devuelve null si no quedó nada útil.
  ///
  /// NO valida el contenido: un QR puede traer una URL, un JSON o un número,
  /// y quien decide si sirve es `ValidarPromo`, no la app.
  static String? normalizarLectura(String? raw) {
    final v = (raw ?? '').trim();
    return v.isEmpty ? null : v;
  }

  bool get esEscaneo => this != ModoIngresoCodigo.manual;

  /// Texto del botón que abre la cámara.
  String get textoBoton {
    switch (this) {
      case ModoIngresoCodigo.qr:
        return 'Escanear código QR';
      case ModoIngresoCodigo.barras:
        return 'Escanear código de barras';
      case ModoIngresoCodigo.manual:
        return 'Ingresar código';
    }
  }

  /// Label del campo cuando la promo no trae `LabelCodCliente`.
  String get labelPorDefecto {
    switch (this) {
      case ModoIngresoCodigo.qr:
        return 'Código QR de la promoción';
      case ModoIngresoCodigo.barras:
        return 'Código de barras de la promoción';
      case ModoIngresoCodigo.manual:
        return 'Código de la promoción';
    }
  }

  /// Ayuda que se muestra sobre el visor de la cámara.
  String get instruccion {
    switch (this) {
      case ModoIngresoCodigo.qr:
        return 'Apuntá al código QR del cliente';
      case ModoIngresoCodigo.barras:
        return 'Apuntá al código de barras del cliente';
      case ModoIngresoCodigo.manual:
        return 'Ingresá el código de la promoción';
    }
  }

  /// Título de la pantalla de escaneo.
  String get tituloEscaner =>
      this == ModoIngresoCodigo.barras ? 'Escanear barras' : 'Escanear QR';
}
