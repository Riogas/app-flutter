import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'v2_theme.dart';

/// 📊 Helpers de datos del rediseño Home V2 (sin estado propio de Firestore:
/// todo sale de PersistentStreamManager, Hive o queries one-shot).
class V2Data {
  V2Data._();

  /// Fecha "hoy" operativa en int AAAAMMDD, base UTC-3 (mismo criterio que
  /// firebase_service.getPedidosStream)
  static int hoyInt() {
    final hoy = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    return hoy.year * 10000 + hoy.month * 100 + hoy.day;
  }

  /// Entregas realizadas hoy: query one-shot (mismo patrón que
  /// SettingsPage._loadCompletedOrdersCount)
  static Future<int> entregadasHoy() async {
    try {
      final box = await Hive.openBox('sessionBox');
      final escenario = box.get('escenario', defaultValue: '0').toString();
      final movil =
          int.tryParse(box.get('movil', defaultValue: '0').toString()) ?? 0;
      if (movil == 0) return 0;

      final snap = await FirebaseFirestore.instance
          .collection('Pedidos-$escenario')
          .where('Movil', isEqualTo: movil)
          .where('FchPara', isEqualTo: hoyInt())
          .where('VisibleEnApp', isEqualTo: 'S')
          .get();

      return snap.docs
          .where((d) => (d.data()['EstadoNro'] ?? 0) == 2)
          .length;
    } catch (e) {
      print('❌ [V2_DATA] Error contando entregas de hoy: $e');
      return 0;
    }
  }

  /// Km recorridos hoy según el tracking nativo (locationBox.totalDistance, en metros)
  static Future<double> kmRecorridosHoy() async {
    try {
      final box = await Hive.openBox('locationBox');
      final raw = box.get('totalDistance', defaultValue: 0.0);
      return (raw is num ? raw.toDouble() : 0.0) / 1000.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// URL del servidor de tiles (constante 270, mismo criterio que MapPage)
  static Future<String> tileServerUrl() async {
    try {
      final box = await Hive.openBox('constantBox');
      final data = box.get('270');
      if (data != null && data['Estado'] == 'A') {
        return data['Valor'];
      }
    } catch (_) {}
    return 'http://osmtileserver.riogas.uy/tile';
  }

  /// Info de urgencia según minutos restantes hasta FchHoraMaxEntComp
  /// (constantes 40-43, mismo criterio que getDelayInfo del diseño clásico).
  /// Devuelve {'Color': Color, 'Etiqueta': String} — etiqueta vacía si no aplica.
  static Future<Map<String, dynamic>> prioridadDe(int minutosRestantes) async {
    try {
      final box = await Hive.openBox('constantBox');
      for (int id in [40, 41, 42, 43]) {
        final data = box.get(id.toString());
        if (data != null && data['Estado'] == 'A') {
          final min = data['ValorMin'];
          final max = data['ValorMax'];
          if ((minutosRestantes >= min && minutosRestantes <= max) ||
              (minutosRestantes <= min && minutosRestantes >= max)) {
            return {
              'Color': colorFromName(data['Color']?.toString() ?? ''),
              'Etiqueta': data['Etiqueta'] ?? '',
            };
          }
        }
      }
    } catch (_) {}
    return {'Color': Colors.transparent, 'Etiqueta': ''};
  }

  static Color colorFromName(String name) {
    switch (name.trim().toLowerCase()) {
      case 'rojo':
      case 'red':
        return V2Colors.rojo;
      case 'naranja':
      case 'orange':
        return V2Colors.naranja;
      case 'amarillo':
      case 'yellow':
        return const Color(0xFFF9A825);
      case 'verde':
      case 'green':
        return V2Colors.verde;
      case 'azul':
      case 'blue':
        return V2Colors.accion;
      default:
        return V2Colors.textoSecundario;
    }
  }

  /// Minutos restantes hasta la hora máxima de entrega (negativo = atrasado)
  static int? minutosRestantes(Map<String, dynamic> pedido) {
    final fch = pedido['FchHoraMaxEntComp'];
    if (fch is! Timestamp) return null;
    return fch.toDate().difference(DateTime.now()).inMinutes;
  }

  static String fmtKm(double metros) {
    if (metros >= 1000) {
      return '${(metros / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
    }
    return '${metros.round()} m';
  }

  /// ETA estimada a velocidad urbana (~30 km/h → 500 m/min)
  static String fmtEta(double metros) {
    final minutos = (metros / 500).ceil().clamp(1, 999);
    return '~$minutos min';
  }

  static String fmtHora(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Saludo según hora local del dispositivo
  static String saludo() {
    final h = DateTime.now().hour;
    if (h >= 6 && h < 12) return '¡Buen día';
    if (h >= 12 && h < 19) return '¡Buenas tardes';
    return '¡Buenas noches';
  }

  /// Primer nombre del chofer, capitalizado
  static String primerNombre(String? nombreCompleto) {
    final n = (nombreCompleto ?? '').trim();
    if (n.isEmpty) return 'chofer';
    final primero = n.split(RegExp(r'\s+')).first.toLowerCase();
    return primero[0].toUpperCase() + primero.substring(1);
  }
}
