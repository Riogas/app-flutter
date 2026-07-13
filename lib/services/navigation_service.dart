import 'package:flutter/material.dart';
import '../main.dart'
    show navigatorKey; // Importar el navigatorKey global existente

/// 🧭 NavigationService - Servicio global de navegación
///
/// Permite navegar desde cualquier parte de la app sin BuildContext
/// Útil para navegación desde servicios, callbacks, etc.
/// Usa el navigatorKey existente de main.dart
class NavigationService {
  // Ya no necesitamos crear un nuevo navigatorKey, usamos el de main.dart

  /// Navega a la pantalla de login y limpia el stack de navegación
  static Future<void> navigateToLogin({String? reason}) async {
    print('🧭 [NavigationService] Navegando al login');
    if (reason != null) {
      print('🧭 [NavigationService] Razón: $reason');
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      print('❌ [NavigationService] Navigator no disponible');
      return;
    }

    // Limpiar stack y navegar al login
    navigator.pushNamedAndRemoveUntil('/login', (route) => false);
    print('✅ [NavigationService] Navegación completada');
  }

  /// Muestra un dialog explicativo antes de navegar al login
  static Future<void> showSessionInvalidDialog({
    required String title,
    required String message,
  }) async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      print('❌ [NavigationService] Context no disponible para dialog');
      navigateToLogin(reason: message);
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              child: Text('Aceptar'),
              onPressed: () {
                Navigator.of(context).pop();
                navigateToLogin(reason: message);
              },
            ),
          ],
        );
      },
    );
  }
}
