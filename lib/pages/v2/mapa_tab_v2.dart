import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';

import '../../services/osrm_service.dart';
import '../../services/persistent_stream_manager.dart';
import 'pedido_actions_v2.dart';
import 'v2_data.dart';
import 'v2_header.dart';
import 'v2_theme.dart';

/// 🗺️ Mapa del rediseño 2026: ruta y entregas sobre el mapa propio de
/// RioGas (tiles OSM + cache FMTC), con panel de ruta y controles flotantes.
/// La ruta es línea recta por ahora (punto de extensión para OSRM cuando
/// haya un endpoint público de routing).
class MapaTabV2 extends StatefulWidget {
  final ValueNotifier<int> messageCountNotifier;
  final Future<void> Function(BuildContext context) onEstadoTap;

  const MapaTabV2({
    super.key,
    required this.messageCountNotifier,
    required this.onEstadoTap,
  });

  @override
  State<MapaTabV2> createState() => _MapaTabV2State();
}

class _MapaTabV2State extends State<MapaTabV2> {
  final _streamManager = PersistentStreamManager();
  final MapController _mapController = MapController();

  bool _mapaActivo = false;
  bool _fmtcListo = false;
  String _tileUrl = 'http://osmtileserver.riogas.uy/tile';
  int _cacheDias = 7;

  LatLng? _pos;
  double _heading = 0;
  DateTime? _posAt;
  bool _gpsOk = true;
  bool _conexionOk = true;
  DateTime? _ultimaSync;

  bool _mostrarPedidos = true; // capa de pines de pedidos
  OsrmRuta? _rutaOsrm; // ruta real por calles (null = fallback línea recta)
  int? _paradaSeleccionada; // índice del marker tocado
  bool _mapListo = false;
  bool _centradoInicial = false;

  Timer? _timer;
  VoidCallback? _pedidosListener;

  @override
  void initState() {
    super.initState();

    _pedidosListener = () {
      if (mounted) setState(() => _ultimaSync = DateTime.now());
      _actualizarRutaOsrm();
    };
    _streamManager.pedidosNotifier.addListener(_pedidosListener!);

    _inicializar();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refrescarPosicion();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_pedidosListener != null) {
      _streamManager.pedidosNotifier.removeListener(_pedidosListener!);
    }
    super.dispose();
  }

  Future<void> _inicializar() async {
    // FMTC (idéntico al mapa clásico, idempotente)
    try {
      await FMTCObjectBoxBackend().initialise();
    } catch (e) {
      if (e is! RootAlreadyInitialised) {
        print('🟥 [MAPA_V2] Error inicializando FMTC: $e');
      }
    }
    try {
      await FMTCStore('mapCache').manage.create();
      _fmtcListo = true;
    } catch (e) {
      print('🟥 [MAPA_V2] Error creando store de tiles: $e');
    }

    _tileUrl = await V2Data.tileServerUrl();
    _cacheDias = await _diasCacheTiles();

    // Gate de activación (misma preferencia que el mapa clásico)
    try {
      final sessionBox = await Hive.openBox('sessionBox');
      _mapaActivo = sessionBox.get('isMapActive', defaultValue: false);
    } catch (_) {}

    await _refrescarPosicion();
    if (mounted) setState(() {});
  }

  Future<int> _diasCacheTiles() async {
    try {
      final box = await Hive.openBox('constantBox');
      final data = box.get('300');
      if (data != null && data['Estado'] == 'A') {
        return int.tryParse(data['Valor'].toString()) ?? 7;
      }
    } catch (_) {}
    return 7;
  }

  Future<void> _refrescarPosicion() async {
    bool gpsOk = _gpsOk;
    bool connOk = _conexionOk;
    LatLng? pos = _pos;
    double heading = _heading;
    DateTime? posAt = _posAt;

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
      connOk = conn.any((c) => c != ConnectivityResult.none);
    } catch (_) {}

    try {
      final p = await Geolocator.getLastKnownPosition();
      if (p != null) {
        pos = LatLng(p.latitude, p.longitude);
        heading = p.heading;
        posAt = p.timestamp;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _gpsOk = gpsOk;
        _conexionOk = connOk;
        _pos = pos;
        _heading = heading;
        _posAt = posAt;
      });
      _centrarInicialSiCorresponde();
      _actualizarRutaOsrm();
    }
  }

  /// 🛣️ Ruta real por calles vía OSRM propio (cache + dedupe en el servicio);
  /// si no responde queda null y se dibuja la línea recta punteada
  Future<void> _actualizarRutaOsrm() async {
    final destino = _destinoActual;
    if (_pos == null || destino == null) {
      if (_rutaOsrm != null && mounted) setState(() => _rutaOsrm = null);
      return;
    }
    final ruta = await OsrmService().ruta(_pos!, destino);
    if (mounted) setState(() => _rutaOsrm = ruta);
  }

  bool get _posDesactualizada =>
      _posAt == null ||
      DateTime.now().difference(_posAt!) > const Duration(minutes: 2);

  void _centrarInicialSiCorresponde() {
    if (_centradoInicial || !_mapListo || !_mapaActivo) return;
    final destino = _destinoActual ?? _pos;
    if (destino == null) return;
    _centradoInicial = true;
    _mapController.move(destino, 14.5);
  }

  LatLng? get _destinoActual {
    final pedidos = _streamManager.pedidosNotifier.value;
    if (pedidos.isEmpty) return null;
    final u = (pedidos.first.data() as Map<String, dynamic>)['ubicacion'];
    if (u is GeoPoint) return LatLng(u.latitude, u.longitude);
    return null;
  }

  void _recentrar() {
    if (_pos != null) {
      _mapController.move(_pos!, 16);
    } else if (_destinoActual != null) {
      _mapController.move(_destinoActual!, 15);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todavía no hay ubicación disponible.')),
      );
    }
  }

  void _activarMapa() async {
    try {
      final sessionBox = await Hive.openBox('sessionBox');
      await sessionBox.put('isMapActive', true);
    } catch (_) {}
    setState(() => _mapaActivo = true);
  }

  void _mostrarCapas() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Capas del mapa',
                style: TextStyle(
                  color: V2Colors.textoPrimario,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              StatefulBuilder(
                builder: (ctx2, setSheet) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: V2Colors.accion,
                  title: const Text('Pines de pedidos',
                      style: TextStyle(fontSize: 14.5)),
                  subtitle: const Text('Mostrar los pedidos asignados',
                      style: TextStyle(fontSize: 12)),
                  value: _mostrarPedidos,
                  onChanged: (v) {
                    setSheet(() {});
                    setState(() => _mostrarPedidos = v);
                  },
                ),
              ),
              const Text(
                'Vista satelital, tránsito y zonas: próximamente',
                style: TextStyle(
                  color: V2Colors.textoSecundario,
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 🔒 Privacidad: la dirección se muestra recortada en el mapa para no
  /// exponer la dirección completa del cliente
  String _direccionCorta(String dir) {
    final d = dir.trim();
    return d.length <= 10 ? d : '${d.substring(0, 10)}…';
  }

  /// Distancia + ETA desde la posición actual hasta el pedido
  String _distanciaEta(Map<String, dynamic> pedido) {
    final u = pedido['ubicacion'];
    if (u is GeoPoint && _pos != null) {
      final m = const Distance()
          .as(LengthUnit.Meter, _pos!, LatLng(u.latitude, u.longitude));
      return '${V2Data.fmtKm(m)} · ${V2Data.fmtEta(m)}';
    }
    return '';
  }

  Color _colorParada(int index, Map<String, dynamic> pedido) {
    final restantes = V2Data.minutosRestantes(pedido);
    if (restantes != null && restantes < 15) return V2Colors.naranja;
    if (index == 0) return V2Colors.accion;
    if (index == 1) return V2Colors.celeste;
    return const Color(0xFF90A4AE);
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: V2Colors.fondo,
      child: Column(
        children: [
          V2Header(
            messageCountNotifier: widget.messageCountNotifier,
            onEstadoTap: widget.onEstadoTap,
            titulo: 'Mapa',
            subtitulo: 'Seguimiento de ruta y entregas',
            height: 158,
            bottomSpace: 18,
            problemaTecnico: !_gpsOk || !_conexionOk,
          ),
          Expanded(
            child: !_mapaActivo ? _gateActivacion() : _mapaConPaneles(),
          ),
        ],
      ),
    );
  }

  // Gate de activación (ahorro de datos, igual criterio que el clásico)
  Widget _gateActivacion() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: V2Card(
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  color: V2Colors.celesteClaro,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.map_outlined,
                    color: V2Colors.accion, size: 44),
              ),
              const SizedBox(height: 16),
              const Text(
                'Mapa desactivado',
                style: TextStyle(
                  color: V2Colors.textoPrimario,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'El mapa consume datos móviles.\nActivalo cuando lo necesites.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: V2Colors.textoSecundario,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _activarMapa,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: V2Colors.accion,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: const Icon(Icons.map, size: 20),
                  label: const Text('Activar mapa'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapaConPaneles() {
    return ValueListenableBuilder<List<DocumentSnapshot>>(
      valueListenable: _streamManager.pedidosNotifier,
      builder: (context, pedidos, _) {
        // Índice seleccionado fuera de rango → limpiar
        if (_paradaSeleccionada != null &&
            _paradaSeleccionada! >= pedidos.length) {
          _paradaSeleccionada = null;
        }

        return Stack(
          children: [
            // ── Mapa ──
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter:
                      _destinoActual ?? _pos ?? const LatLng(-34.9011, -56.1645),
                  initialZoom: 13.5,
                  minZoom: 5,
                  maxZoom: 18,
                  onMapReady: () {
                    _mapListo = true;
                    _centrarInicialSiCorresponde();
                  },
                  onTap: (_, __) =>
                      setState(() => _paradaSeleccionada = null),
                ),
                children: [
                  TileLayer(
                    urlTemplate: '$_tileUrl/{z}/{x}/{y}.png',
                    tileProvider: _fmtcListo
                        ? FMTCTileProvider(
                            stores: {'mapCache': BrowseStoreStrategy.read},
                            cachedValidDuration: Duration(days: _cacheDias),
                          )
                        : NetworkTileProvider(),
                    userAgentPackageName: 'com.example.moveit',
                  ),
                  // 🛣️ Ruta al destino actual: por calles (OSRM riogas) o
                  // línea recta punteada como fallback si OSRM no responde
                  if (_mostrarPedidos && _pos != null && pedidos.isNotEmpty)
                    Builder(builder: (context) {
                      final destino = _destinoActual;
                      if (destino == null) return const SizedBox.shrink();
                      final rutaReal = _rutaOsrm != null &&
                          _rutaOsrm!.puntos.length >= 2;
                      return PolylineLayer(
                        polylines: [
                          if (rutaReal)
                            Polyline(
                              points: _rutaOsrm!.puntos,
                              color: V2Colors.accion.withOpacity(0.9),
                              strokeWidth: 5,
                              borderColor: Colors.white,
                              borderStrokeWidth: 1.5,
                            )
                          else
                            Polyline(
                              points: [_pos!, destino],
                              color: V2Colors.accion.withOpacity(0.85),
                              strokeWidth: 4.5,
                              pattern: const StrokePattern.dotted(),
                            ),
                        ],
                      );
                    }),
                  MarkerLayer(
                    markers: [
                      // Paradas
                      if (_mostrarPedidos)
                        ...List.generate(pedidos.length, (i) {
                          final data =
                              pedidos[i].data() as Map<String, dynamic>;
                          final u = data['ubicacion'];
                          if (u is! GeoPoint) {
                            return null;
                          }
                          final color = _colorParada(i, data);
                          return Marker(
                            point: LatLng(u.latitude, u.longitude),
                            width: 46,
                            height: 52,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              onTap: () => setState(
                                  () => _paradaSeleccionada = i),
                              child: Stack(
                                alignment: Alignment.topCenter,
                                children: [
                                  Icon(Icons.location_on,
                                      color: i == 0
                                          ? V2Colors.rojo
                                          : color,
                                      size: 42),
                                  Positioned(
                                    top: 7,
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${i + 1}',
                                          style: TextStyle(
                                            color: i == 0
                                                ? V2Colors.rojo
                                                : color,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).whereType<Marker>(),
                      // Móvil (posición actual)
                      if (_pos != null)
                        Marker(
                          point: _pos!,
                          width: 44,
                          height: 44,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Halo de precisión
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: (_posDesactualizada
                                          ? V2Colors.naranja
                                          : V2Colors.accion)
                                      .withOpacity(0.18),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Transform.rotate(
                                angle: _heading * math.pi / 180,
                                child: Icon(
                                  Icons.navigation,
                                  color: _posDesactualizada
                                      ? V2Colors.naranja
                                      : V2Colors.accion,
                                  size: 26,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Franja sin conexión ──
            if (!_conexionOk)
              Positioned(
                top: 10,
                left: 12,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: V2Colors.naranja.withOpacity(0.5)),
                    boxShadow: V2Shadows.card,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off,
                          color: V2Colors.naranja, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sin conexión. Mostrando la última información disponible'
                          '${_ultimaSync != null ? ' (${V2Data.fmtHora(_ultimaSync!)})' : ''}.',
                          style: const TextStyle(
                            color: V2Colors.textoPrimario,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Tarjeta sin GPS ──
            if (!_gpsOk)
              Positioned(
                top: _conexionOk ? 10 : 62,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: V2Colors.naranja.withOpacity(0.5)),
                    boxShadow: V2Shadows.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.location_off,
                              color: V2Colors.naranja, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No podemos obtener tu ubicación',
                              style: TextStyle(
                                color: V2Colors.textoPrimario,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Activá la ubicación del dispositivo para ver tu ruta.',
                        style: TextStyle(
                          color: V2Colors.textoSecundario,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        child: ElevatedButton(
                          onPressed: () => Geolocator.openLocationSettings(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: V2Colors.naranja,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Activar ubicación'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Tarjeta de parada seleccionada ──
            if (_paradaSeleccionada != null &&
                _paradaSeleccionada! < pedidos.length)
              Positioned(
                top: (!_conexionOk || !_gpsOk) ? 120 : 10,
                left: 12,
                right: 12,
                child: _cardParadaSeleccionada(
                    pedidos[_paradaSeleccionada!].data()
                        as Map<String, dynamic>,
                    _paradaSeleccionada!),
              ),

            // ── Controles flotantes ──
            Positioned(
              right: 12,
              bottom: pedidos.isEmpty ? 190 : 235,
              child: Column(
                children: [
                  _fabMapa(Icons.my_location, 'Centrar', _recentrar),
                  const SizedBox(height: 10),
                  _fabMapa(Icons.layers_outlined, 'Capas', _mostrarCapas),
                ],
              ),
            ),

            // ── Panel inferior ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: pedidos.isEmpty
                  ? _panelSinRuta()
                  : _panelRuta(pedidos),
            ),
          ],
        );
      },
    );
  }

  Widget _fabMapa(IconData icon, String tooltip, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: V2Colors.azulOscuro, size: 23),
        ),
      ),
    );
  }

  Widget _cardParadaSeleccionada(Map<String, dynamic> pedido, int index) {
    final direccion = (pedido['ClienteDireccion'] ?? 'Sin dirección').toString();
    final extra = _distanciaEta(pedido);
    return V2Card(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shadows: V2Shadows.cardElevada,
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: V2Colors.celesteClaro,
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: V2Colors.accion,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _direccionCorta(direccion),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: V2Colors.textoPrimario,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Parada ${index + 1}${extra.isNotEmpty ? ' · $extra' : ''}',
                  style: const TextStyle(
                    color: V2Colors.textoSecundario,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () =>
                PedidoActionsV2.abrirDetalle(context, pedido),
            child: const Text(
              'Detalle',
              style: TextStyle(
                color: V2Colors.accion,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _paradaSeleccionada = null),
            child: const Icon(Icons.close,
                color: V2Colors.textoSecundario, size: 19),
          ),
        ],
      ),
    );
  }

  // ── Panel inferior: ruta actual ──
  Widget _panelRuta(List<DocumentSnapshot> pedidos) {
    final actual = pedidos.first.data() as Map<String, dynamic>;
    final siguiente = pedidos.length > 1
        ? pedidos[1].data() as Map<String, dynamic>
        : null;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F0D2B4E),
            blurRadius: 18,
            offset: Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: V2Colors.celesteClaro,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Ruta actual',
                style: TextStyle(
                  color: V2Colors.textoPrimario,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: V2Colors.celesteClaro,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  pedidos.length == 1
                      ? '1 parada restante'
                      : '${pedidos.length} paradas restantes',
                  style: const TextStyle(
                    color: V2Colors.accion,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _filaParada(
            color: V2Colors.rojo,
            etiqueta: 'Parada actual',
            direccion: _direccionCorta(
                (actual['ClienteDireccion'] ?? 'Sin dirección').toString()),
            // Con OSRM: distancia y tiempo REALES por calles
            extra: _rutaOsrm != null
                ? '${V2Data.fmtKm(_rutaOsrm!.distanciaM)} · ${V2Data.fmtEtaSeg(_rutaOsrm!.duracionSeg)}'
                : _distanciaEta(actual),
          ),
          if (siguiente != null) ...[
            const SizedBox(height: 6),
            _filaParada(
              color: V2Colors.celeste,
              etiqueta: 'Próxima parada',
              direccion: _direccionCorta(
                  (siguiente['ClienteDireccion'] ?? 'Sin dirección')
                      .toString()),
              extra: _distanciaEta(siguiente),
            ),
          ],
          if (pedidos.length > 2) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => _mostrarListaParadas(pedidos),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 30),
                    Text(
                      '+${pedidos.length - 2} pedidos más en tu ruta',
                      style: const TextStyle(
                        color: V2Colors.accion,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: V2Colors.accion, size: 17),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        PedidoActionsV2.iniciarViaje(context, actual),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: V2Colors.accion,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    icon: const Icon(Icons.navigation_outlined, size: 19),
                    label: const Text('Iniciar navegación'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        PedidoActionsV2.abrirDetalle(context, actual),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: V2Colors.accion,
                      side: const BorderSide(
                          color: V2Colors.accion, width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text(
                      'Detalle',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filaParada({
    required Color color,
    required String etiqueta,
    required String direccion,
    String extra = '',
  }) {
    return Row(
      children: [
        Icon(Icons.location_on, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                etiqueta,
                style: const TextStyle(
                  color: V2Colors.textoSecundario,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              Row(
                children: [
                  Text(
                    direccion,
                    style: const TextStyle(
                      color: V2Colors.textoPrimario,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (extra.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        extra,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: V2Colors.textoSecundario,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _mostrarListaParadas(List<DocumentSnapshot> pedidos) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
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
                  final pedido = pedidos[i].data() as Map<String, dynamic>;
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
                      _direccionCorta(
                          (pedido['ClienteDireccion'] ?? 'Sin dirección')
                              .toString()),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: V2Colors.textoPrimario,
                      ),
                    ),
                    subtitle: _distanciaEta(pedido).isNotEmpty
                        ? Text(
                            _distanciaEta(pedido),
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                    trailing: const Icon(Icons.chevron_right,
                        color: V2Colors.textoSecundario),
                    onTap: () {
                      Navigator.pop(ctx);
                      final u = pedido['ubicacion'];
                      if (u is GeoPoint) {
                        _mapController.move(
                            LatLng(u.latitude, u.longitude), 16);
                        setState(() => _paradaSeleccionada = i);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Panel inferior: sin ruta activa ──
  Widget _panelSinRuta() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F0D2B4E),
            blurRadius: 18,
            offset: Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No tenés una ruta activa',
            style: TextStyle(
              color: V2Colors.textoPrimario,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Cuando recibas un pedido, la ruta aparecerá automáticamente en el mapa.',
            style: TextStyle(
              color: V2Colors.textoSecundario,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                _gpsOk ? Icons.gps_fixed : Icons.gps_off,
                color: _gpsOk ? V2Colors.verde : V2Colors.rojo,
                size: 17,
              ),
              const SizedBox(width: 6),
              Text(
                _gpsOk ? 'GPS conectado' : 'GPS sin señal',
                style: const TextStyle(
                    color: V2Colors.textoSecundario, fontSize: 12),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.sync,
                  color: V2Colors.textoSecundario, size: 17),
              const SizedBox(width: 6),
              Text(
                _ultimaSync != null
                    ? 'Sync ${V2Data.fmtHora(_ultimaSync!)}'
                    : 'Sin sincronizar',
                style: const TextStyle(
                    color: V2Colors.textoSecundario, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
