/// Qué hacer con la lista de móviles que devuelve ValidarUsuario.
enum AccionMovil {
  /// El backend no devolvió ningún móvil: hay que avisarle al usuario.
  /// Antes de esta feature el login moría en silencio.
  sinMoviles,

  /// Un solo móvil y no hace falta matrícula: se entra directo.
  autoSeleccionar,

  /// Un solo móvil pero la matrícula es obligatoria (constante 180 == 'S'):
  /// se muestra un diálogo reducido, con el móvil fijo.
  pedirMatricula,

  /// Varios móviles: diálogo de selección completo, como siempre.
  mostrarDialogo,
}

/// Decisión pura sobre la lista de móviles. Sin Hive, sin red, sin contexto.
class MovilSelection {
  MovilSelection._();

  static AccionMovil decidir({
    required List<Map<String, String>> moviles,
    required bool pideMatricula,
  }) {
    if (moviles.isEmpty) return AccionMovil.sinMoviles;
    if (moviles.length > 1) return AccionMovil.mostrarDialogo;
    return pideMatricula
        ? AccionMovil.pedirMatricula
        : AccionMovil.autoSeleccionar;
  }

  /// El id del móvil cuando hay exactamente uno; null en cualquier otro caso.
  static String? idUnico(List<Map<String, String>> moviles) =>
      moviles.length == 1 ? moviles.first['id'] : null;
}
