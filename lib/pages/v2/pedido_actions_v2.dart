import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/pedido_lectura_service.dart';
import '../../services/ui_prefs.dart';
import '../order_detail_page.dart';

/// 🚚 Acciones compartidas sobre pedidos en el rediseño V2
/// (usadas por la pantalla de Pedidos y por el Mapa).
class PedidoActionsV2 {
  PedidoActionsV2._();

  static int idDe(Map<String, dynamic> pedido) {
    final id = pedido['id'];
    if (id is int) return id;
    return int.tryParse(id?.toString() ?? '') ?? 0;
  }

  /// Mismo contrato que el diseño clásico: GPS activo → marcar Leído en Hive
  /// → LECTURA/DESCARGA en background → OrderDetailPage.
  static Future<void> abrirDetalle(
    BuildContext context,
    Map<String, dynamic> pedido, {
    bool autoFinalize = false,
  }) async {
    final pedidoId = idDe(pedido);

    final gpsActivo = await Geolocator.isLocationServiceEnabled();
    if (!gpsActivo) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Por favor, activá el GPS para continuar.')),
        );
      }
      return;
    }

    try {
      final pedidosBox = await Hive.openBox('pedidosBox');
      await pedidosBox.put(pedidoId, 'Leído');
    } catch (e) {
      print('⚠️ [V2] No se pudo marcar Leído en pedidosBox: $e');
    }

    // Fire-and-forget (idéntico al diseño clásico)
    PedidoLecturaService().marcarLecturaSiCorresponde(
      pedido: pedido,
      pedidoId: pedidoId,
      context: context.mounted ? context : null,
    );

    if (!context.mounted) return;

    final ubicacion =
        (pedido.containsKey('ubicacion') && pedido['ubicacion'] is GeoPoint)
            ? pedido['ubicacion'] as GeoPoint
            : null;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailPage(
          detalleHtml: pedido['DetalleHTML'],
          estadoNro: pedido['EstadoNro'],
          totalPedido: (pedido['Precio'] is double)
              ? pedido['Precio']
              : (pedido['Precio'] is int)
                  ? (pedido['Precio'] as int).toDouble()
                  : (pedido['Precio'] is String)
                      ? double.tryParse(pedido['Precio']) ?? 0.0
                      : 0.0,
          codPedido: pedidoId,
          pedidoTipo: pedido['Tipo'],
          ubicacion: ubicacion,
          autoFinalize: autoFinalize,
        ),
      ),
    );
  }

  /// Abre la navegación externa según el navegador preferido:
  /// Waze (WazeURL del pedido o link universal) o Google Maps.
  static Future<void> iniciarViaje(
    BuildContext context,
    Map<String, dynamic> pedido,
  ) async {
    Uri? uri;
    final u = pedido['ubicacion'];
    final usarMaps = UiPrefs.navegador.value == 'maps';

    if (!usarMaps) {
      final wazeUrl = pedido['WazeURL'];
      if (wazeUrl is String && wazeUrl.trim().isNotEmpty) {
        uri = Uri.tryParse(wazeUrl.trim());
      }
      if (uri == null && u is GeoPoint) {
        uri = Uri.parse(
            'https://waze.com/ul?ll=${u.latitude},${u.longitude}&navigate=yes');
      }
    }

    if (uri == null && u is GeoPoint) {
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=${u.latitude},${u.longitude}');
    }

    if (uri == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('El pedido no tiene ubicación para navegar.')),
        );
      }
      return;
    }

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      print('❌ [V2] Error abriendo navegación: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la navegación.')),
        );
      }
    }
  }
}
