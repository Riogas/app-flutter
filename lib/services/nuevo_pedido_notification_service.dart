import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show flutterLocalNotificationsPlugin;
import 'persistent_stream_manager.dart';

/// 🔔 Notificaciones de pedidos nuevos con acciones de navegación.
///
/// Escucha el stream de pedidos (PersistentStreamManager) y cuando aparece
/// un pedido nuevo dispara una notificación heads-up (visible incluso sobre
/// Waze/Maps) con dos acciones:
///  - "Navegar ahora": abre Waze (o Maps) directo al pedido nuevo.
///    En Waze REEMPLAZA el destino actual (Waze no soporta paradas por API).
///  - "Ruta completa": abre Google Maps con TODAS las paradas pendientes
///    en orden (multi-parada, hasta 9 waypoints).
class NuevoPedidoNotificationService {
  NuevoPedidoNotificationService._();
  static final NuevoPedidoNotificationService _instance =
      NuevoPedidoNotificationService._();
  factory NuevoPedidoNotificationService() => _instance;

  static const String _channelId = 'nuevos_pedidos_channel';
  static const String accionNavegar = 'nav_nuevo';
  static const String accionRutaCompleta = 'ruta_completa';

  final PersistentStreamManager _streamManager = PersistentStreamManager();

  bool _initialized = false;
  bool _seeded = false;
  DateTime? _initTime;
  final Set<int> _conocidos = {};
  final Set<int> _notificados = {};

  /// ⏳ Ventana de gracia post-arranque: las emisiones iniciales de Firestore
  /// (pedidos que YA estaban asignados al abrir la app) solo siembran, no
  /// notifican. Sin esto, cada apertura de la app notificaba lo ya conocido.
  static const Duration _graciaInicial = Duration(seconds: 25);

  bool get _enGracia =>
      _initTime == null ||
      DateTime.now().difference(_initTime!) < _graciaInicial;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _initTime = DateTime.now();

    // Canal propio, heads-up, mismo sonido que las notificaciones de la app
    const channel = AndroidNotificationChannel(
      _channelId,
      'Nuevos pedidos',
      description: 'Aviso cuando se asigna un pedido nuevo al móvil',
      importance: Importance.high,
      sound: RawResourceAndroidNotificationSound('iphone_notification'),
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _streamManager.pedidosNotifier.addListener(_onPedidosChanged);
    // Sembrar con lo que ya haya (no notificar el estado inicial del login)
    _onPedidosChanged();
    print('🔔 [NUEVO_PEDIDO] Servicio de notificaciones inicializado');
  }

  int? _idDe(Map<String, dynamic> data) {
    final id = data['id'];
    if (id is int) return id;
    return int.tryParse(id?.toString() ?? '');
  }

  void _onPedidosChanged() {
    final pedidos = _streamManager.pedidosNotifier.value;
    final actuales = <int>{};
    final nuevos = <Map<String, dynamic>>[];

    for (final doc in pedidos) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final id = _idDe(data);
      if (id == null) continue;
      actuales.add(id);
      if (_seeded && !_enGracia && !_conocidos.contains(id)) {
        nuevos.add(data);
      }
    }

    // Cancelar notificaciones de pedidos que ya no están pendientes
    for (final id in _notificados.toList()) {
      if (!actuales.contains(id)) {
        flutterLocalNotificationsPlugin.cancel(id);
        _notificados.remove(id);
      }
    }

    _conocidos
      ..clear()
      ..addAll(actuales);

    if (!_seeded) {
      // Primera emisión después del login: solo sembrar
      _seeded = true;
      return;
    }

    if (nuevos.isEmpty) return;

    if (nuevos.length == 1) {
      _notificarPedido(nuevos.first);
    } else {
      // Varios a la vez: una sola notificación resumen
      _notificarVarios(nuevos.length);
    }
  }

  Future<void> _notificarPedido(Map<String, dynamic> pedido) async {
    final id = _idDe(pedido) ?? 0;
    final direccion =
        (pedido['ClienteDireccion'] ?? 'Nueva dirección').toString();

    // Datos para las acciones (viajan en el payload)
    String lat = '', lng = '';
    final u = pedido['ubicacion'];
    if (u is GeoPoint) {
      lat = u.latitude.toString();
      lng = u.longitude.toString();
    }
    final wazeUrl = (pedido['WazeURL'] is String)
        ? (pedido['WazeURL'] as String).trim()
        : '';
    final payload = jsonEncode({'lat': lat, 'lng': lng, 'waze': wazeUrl});

    await flutterLocalNotificationsPlugin.show(
      id,
      '📦 Nuevo pedido asignado',
      direccion,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Nuevos pedidos',
          channelDescription:
              'Aviso cuando se asigna un pedido nuevo al móvil',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.navigation,
          sound: const RawResourceAndroidNotificationSound(
              'iphone_notification'),
          styleInformation: BigTextStyleInformation(direccion),
          actions: const [
            AndroidNotificationAction(
              accionNavegar,
              '🧭 Navegar ahora',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              accionRutaCompleta,
              '🗺️ Ruta completa',
              showsUserInterface: true,
            ),
          ],
        ),
      ),
      payload: payload,
    );
    _notificados.add(id);
    print('🔔 [NUEVO_PEDIDO] Notificado pedido $id ($direccion)');
  }

  Future<void> _notificarVarios(int cantidad) async {
    await flutterLocalNotificationsPlugin.show(
      777001,
      '📦 $cantidad pedidos nuevos asignados',
      'Tocá "Ruta completa" para armar el recorrido en Google Maps',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Nuevos pedidos',
          channelDescription:
              'Aviso cuando se asigna un pedido nuevo al móvil',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.navigation,
          sound: const RawResourceAndroidNotificationSound(
              'iphone_notification'),
          actions: const [
            AndroidNotificationAction(
              accionRutaCompleta,
              '🗺️ Ruta completa',
              showsUserInterface: true,
            ),
          ],
        ),
      ),
      payload: jsonEncode({'lat': '', 'lng': '', 'waze': ''}),
    );
  }

  // ── Acciones ────────────────────────────────────────────────────────────

  /// Handler global de taps en notificaciones (registrado en main.dart).
  /// Nota: con showsUserInterface=true la app pasa a foreground y este
  /// callback corre en el isolate principal → launchUrl funciona siempre.
  static Future<void> onNotificationResponse(
      NotificationResponse response) async {
    try {
      final payload = response.payload;
      if (payload == null || payload.isEmpty) return;
      final data = jsonDecode(payload) as Map<String, dynamic>;

      switch (response.actionId) {
        case accionNavegar:
          await _navegarAlNuevo(data);
          break;
        case accionRutaCompleta:
          await abrirRutaCompleta();
          break;
        default:
          // Tap en el cuerpo de la notificación: solo abre la app
          break;
      }
    } catch (e) {
      print('❌ [NUEVO_PEDIDO] Error manejando acción de notificación: $e');
    }
  }

  static Future<void> _navegarAlNuevo(Map<String, dynamic> data) async {
    Uri? uri;
    final waze = (data['waze'] ?? '').toString();
    final lat = (data['lat'] ?? '').toString();
    final lng = (data['lng'] ?? '').toString();

    if (waze.isNotEmpty) {
      uri = Uri.tryParse(waze);
    }
    if (uri == null && lat.isNotEmpty && lng.isNotEmpty) {
      // Universal link: abre Waze si está instalado, sino el navegador
      uri = Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes');
    }
    if (uri == null) return;

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 🗺️ Abre Google Maps con TODAS las paradas pendientes en orden.
  /// Reutilizable desde la notificación y desde el botón de la pantalla.
  static Future<bool> abrirRutaCompleta() async {
    final uri = rutaCompletaUri(PersistentStreamManager().pedidosNotifier.value);
    if (uri == null) return false;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return true;
  }

  /// Construye la URL multi-parada de Google Maps (máx. 9 waypoints + destino)
  static Uri? rutaCompletaUri(List<DocumentSnapshot> pedidos) {
    final puntos = <String>[];
    for (final doc in pedidos) {
      final data = doc.data() as Map<String, dynamic>?;
      final u = data?['ubicacion'];
      if (u is GeoPoint) {
        puntos.add('${u.latitude},${u.longitude}');
      }
    }
    if (puntos.isEmpty) return null;

    // Google Maps soporta hasta 9 waypoints + destino en la URL
    if (puntos.length > 10) {
      puntos.removeRange(10, puntos.length);
    }

    final destino = puntos.removeLast();
    final params = <String, String>{
      'api': '1',
      'destination': destino,
      'travelmode': 'driving',
    };
    if (puntos.isNotEmpty) {
      params['waypoints'] = puntos.join('|');
    }
    return Uri.https('www.google.com', '/maps/dir/', params);
  }
}
