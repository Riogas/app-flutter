import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/pedido_lectura_service.dart';
import '../../services/persistent_stream_manager.dart';
import '../order_detail_page.dart';
import 'v2_cards.dart';
import 'v2_data.dart';
import 'v2_header.dart';
import 'v2_theme.dart';

/// 🚚 Tab principal del rediseño: cabecera + resumen + pedido actual +
/// siguientes + estado técnico.
class PedidosTabV2 extends StatefulWidget {
  final ValueNotifier<int> messageCountNotifier;
  final Future<void> Function(BuildContext context) onEstadoTap;
  final VoidCallback onVerPromos;

  const PedidosTabV2({
    super.key,
    required this.messageCountNotifier,
    required this.onEstadoTap,
    required this.onVerPromos,
  });

  @override
  State<PedidosTabV2> createState() => _PedidosTabV2State();
}

class _PedidosTabV2State extends State<PedidosTabV2> {
  final _streamManager = PersistentStreamManager();

  int _entregadas = 0;
  double _kmHoy = 0.0;
  DateTime? _ultimaActualizacion;
  LatLng? _posicionActual;
  String _tileUrl = 'http://osmtileserver.riogas.uy/tile';

  bool _gpsOk = true;
  bool _conexionOk = true;
  int? _bateria;

  Timer? _refreshTimer;
  VoidCallback? _pedidosListener;

  @override
  void initState() {
    super.initState();

    _pedidosListener = () {
      if (!mounted) return;
      setState(() => _ultimaActualizacion = DateTime.now());
      _cargarEntregadas();
    };
    _streamManager.pedidosNotifier.addListener(_pedidosListener!);

    _cargarTodo();
    // 🔄 Refresco periódico de estado técnico/posición (barato, sin GPS wakeup)
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refrescarEstadoTecnico();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    if (_pedidosListener != null) {
      _streamManager.pedidosNotifier.removeListener(_pedidosListener!);
    }
    super.dispose();
  }

  Future<void> _cargarTodo() async {
    _tileUrl = await V2Data.tileServerUrl();
    await _cargarEntregadas();
    await _refrescarEstadoTecnico();
  }

  Future<void> _cargarEntregadas() async {
    final entregadas = await V2Data.entregadasHoy();
    if (mounted) setState(() => _entregadas = entregadas);
  }

  Future<void> _refrescarEstadoTecnico() async {
    bool gpsOk = _gpsOk;
    bool conexionOk = _conexionOk;
    int? bateria = _bateria;
    LatLng? pos = _posicionActual;
    double km = _kmHoy;

    try {
      gpsOk = await Geolocator.isLocationServiceEnabled();
      if (gpsOk) {
        final perm = await Geolocator.checkPermission();
        gpsOk = perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse;
      }
    } catch (_) {}

    try {
      final conn = await Connectivity().checkConnectivity();
      conexionOk = conn.any((c) => c != ConnectivityResult.none);
    } catch (_) {}

    try {
      bateria = await Battery().batteryLevel;
    } catch (_) {}

    try {
      final p = await Geolocator.getLastKnownPosition();
      if (p != null) pos = LatLng(p.latitude, p.longitude);
    } catch (_) {}

    km = await V2Data.kmRecorridosHoy();

    if (mounted) {
      setState(() {
        _gpsOk = gpsOk;
        _conexionOk = conexionOk;
        _bateria = bateria;
        _posicionActual = pos;
        _kmHoy = km;
      });
    }
  }

  // ── Acciones sobre pedidos ──────────────────────────────────────────────

  int _pedidoIdDe(Map<String, dynamic> pedido) {
    final id = pedido['id'];
    if (id is int) return id;
    return int.tryParse(id?.toString() ?? '') ?? 0;
  }

  /// Mismo contrato que el diseño clásico: GPS activo → marcar Leído en Hive
  /// → LECTURA/DESCARGA en background → OrderDetailPage.
  Future<void> _abrirDetalle(Map<String, dynamic> pedido,
      {bool autoFinalize = false}) async {
    final pedidoId = _pedidoIdDe(pedido);

    final gpsActivo = await Geolocator.isLocationServiceEnabled();
    if (!gpsActivo) {
      if (mounted) {
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
      context: mounted ? context : null,
    );

    if (!mounted) return;

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

  /// Abre la navegación externa (Waze si el pedido trae WazeURL, sino Maps)
  Future<void> _iniciarViaje(Map<String, dynamic> pedido) async {
    Uri? uri;

    final wazeUrl = pedido['WazeURL'];
    if (wazeUrl is String && wazeUrl.trim().isNotEmpty) {
      uri = Uri.tryParse(wazeUrl.trim());
    }

    if (uri == null) {
      final u = pedido['ubicacion'];
      if (u is GeoPoint) {
        uri = Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=${u.latitude},${u.longitude}');
      }
    }

    if (uri == null) {
      if (mounted) {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la navegación.')),
        );
      }
    }
  }

  void _mostrarListaCompleta(List<DocumentSnapshot> pedidos) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: V2Colors.celesteClaro,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Tu ruta de hoy',
                  style: TextStyle(
                    color: V2Colors.textoPrimario,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: pedidos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final pedido =
                        pedidos[i].data() as Map<String, dynamic>;
                    final restantes = V2Data.minutosRestantes(pedido);
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: V2Colors.celesteClaro),
                      ),
                      leading: CircleAvatar(
                        backgroundColor: V2Colors.celesteClaro,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: V2Colors.accion,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      title: Text(
                        (pedido['ClienteDireccion'] ?? 'Sin dirección')
                            .toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: V2Colors.textoPrimario,
                        ),
                      ),
                      subtitle: restantes != null
                          ? Text(
                              restantes >= 0
                                  ? 'Quedan $restantes min'
                                  : 'Atrasado ${-restantes} min',
                              style: const TextStyle(fontSize: 12.5),
                            )
                          : null,
                      trailing: const Icon(Icons.chevron_right,
                          color: V2Colors.textoSecundario),
                      onTap: () {
                        Navigator.pop(ctx);
                        _abrirDetalle(pedido);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final problemaTecnico = !_gpsOk || !_conexionOk;

    return ValueListenableBuilder<List<DocumentSnapshot>>(
      valueListenable: _streamManager.pedidosNotifier,
      builder: (context, pedidos, _) {
        return RefreshIndicator(
          color: V2Colors.accion,
          onRefresh: () async {
            await _cargarEntregadas();
            await _refrescarEstadoTecnico();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                // Cabecera + resumen flotante superpuesto
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    V2Header(
                      messageCountNotifier: widget.messageCountNotifier,
                      onEstadoTap: widget.onEstadoTap,
                      problemaTecnico: problemaTecnico,
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: -48,
                      child: V2ResumenCard(
                        pendientes: pedidos.length,
                        entregadas: _entregadas,
                        kmHoy: _kmHoy,
                        ultimaActualizacion: _ultimaActualizacion,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 64),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      if (pedidos.isEmpty)
                        V2AlDiaCard(onVerPromos: widget.onVerPromos)
                      else ...[
                        Builder(builder: (context) {
                          final actual =
                              pedidos.first.data() as Map<String, dynamic>;
                          return V2PedidoActualCard(
                            pedido: actual,
                            pedidoId: _pedidoIdDe(actual),
                            posicionActual: _posicionActual,
                            tileUrl: _tileUrl,
                            onIniciarViaje: () => _iniciarViaje(actual),
                            onVerDetalle: () => _abrirDetalle(actual),
                            onDevolver: () =>
                                _abrirDetalle(actual, autoFinalize: true),
                          );
                        }),
                        if (pedidos.length > 1) ...[
                          const SizedBox(height: 12),
                          Builder(builder: (context) {
                            final siguiente =
                                pedidos[1].data() as Map<String, dynamic>;
                            final actual =
                                pedidos.first.data() as Map<String, dynamic>;
                            return V2SiguientePedidoCard(
                              pedido: siguiente,
                              pedidoId: _pedidoIdDe(siguiente),
                              pedidoAnterior: actual,
                              onTap: () => _abrirDetalle(siguiente),
                            );
                          }),
                        ],
                        if (pedidos.length > 2) ...[
                          const SizedBox(height: 12),
                          V2MasPedidosRow(
                            cantidad: pedidos.length - 2,
                            onTap: () => _mostrarListaCompleta(pedidos),
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                      V2EstadoTecnicoCard(
                        gpsOk: _gpsOk,
                        conexionOk: _conexionOk,
                        minutosSinSync: _ultimaActualizacion != null
                            ? DateTime.now()
                                .difference(_ultimaActualizacion!)
                                .inMinutes
                            : null,
                        bateria: _bateria,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
