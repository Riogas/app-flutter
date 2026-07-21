import 'package:flutter/material.dart';

/// 🎨 Tokens de diseño del rediseño 2026 (Home V2)
class V2Colors {
  V2Colors._();

  static const Color fondo = Color(0xFFF2F6FA); // gris azulado muy claro
  static const Color azulOscuro = Color(0xFF0D2B4E);
  static const Color azulMedio = Color(0xFF11406F);
  static const Color accion = Color(0xFF1E88E5); // azul brillante
  static const Color celeste = Color(0xFF29B6F6);
  static const Color celesteClaro = Color(0xFFE3F2FD);
  static const Color verde = Color(0xFF43A047);
  static const Color naranja = Color(0xFFF57C00);
  static const Color rojo = Color(0xFFE53935);
  static const Color textoPrimario = Color(0xFF16324A);
  static const Color textoSecundario = Color(0xFF5A7184);
}

class V2Shadows {
  V2Shadows._();

  static List<BoxShadow> get card => [
        BoxShadow(
          color: V2Colors.azulOscuro.withOpacity(0.08),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get cardElevada => [
        BoxShadow(
          color: V2Colors.azulOscuro.withOpacity(0.16),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ];
}

/// Tarjeta blanca estándar del rediseño
class V2Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow>? shadows;

  const V2Card({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: shadows ?? V2Shadows.card,
      ),
      child: child,
    );
  }
}
