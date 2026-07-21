import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'v2_data.dart';
import 'v2_theme.dart';

// ─────────────────────────────────────────────────────────────────────────
// 📊 Resumen operativo (tarjeta flotante bajo la cabecera)
// ─────────────────────────────────────────────────────────────────────────
class V2ResumenCard extends StatelessWidget {
  final int pendientes;
  final int entregadas;
  final double kmHoy;
  final DateTime? ultimaActualizacion;

  const V2ResumenCard({
    super.key,
    required this.pendientes,
    required this.entregadas,
    required this.kmHoy,
    required this.ultimaActualizacion,
  });

  @override
  Widget build(BuildContext context) {
    return V2Card(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      shadows: V2Shadows.cardElevada,
      child: Row(
        children: [
          _indicador(Icons.assignment_outlined, '$pendientes', 'Pendientes'),
          _divisor(),
          _indicador(Icons.check_circle_outline, '$entregadas', 'Entregadas'),
          _divisor(),
          _indicador(Icons.route_outlined,
              kmHoy >= 100 ? kmHoy.toStringAsFixed(0) : kmHoy.toStringAsFixed(1),
              'Km hoy'),
          _divisor(),
          _indicador(
              Icons.sync_outlined,
              ultimaActualizacion != null
                  ? V2Data.fmtHora(ultimaActualizacion!)
                  : '--:--',
              'Actualizado'),
        ],
      ),
    );
  }

  Widget _indicador(IconData icon, String valor, String label) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: V2Colors.celesteClaro,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: V2Colors.accion, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: const TextStyle(
              color: V2Colors.textoPrimario,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: const TextStyle(
              color: V2Colors.textoSecundario,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divisor() => Container(
        width: 1,
        height: 44,
        color: V2Colors.celesteClaro,
      );
}

// ─────────────────────────────────────────────────────────────────────────
// 🚚 Tarjeta PEDIDO ACTUAL
// ─────────────────────────────────────────────────────────────────────────
class V2PedidoActualCard extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final int pedidoId;
  final LatLng? posicionActual;
  final String tileUrl;
  final VoidCallback onIniciarViaje;
  final VoidCallback onVerDetalle;
  final VoidCallback onDevolver;

  const V2PedidoActualCard({
    super.key,
    required this.pedido,
    required this.pedidoId,
    required this.posicionActual,
    required this.tileUrl,
    required this.onIniciarViaje,
    required this.onVerDetalle,
    required this.onDevolver,
  });

  LatLng? get _destino {
    final u = pedido['ubicacion'];
    if (u is GeoPoint) return LatLng(u.latitude, u.longitude);
    return null;
  }

  double? get _distanciaMts {
    final d = _destino;
    final p = posicionActual;
    if (d == null || p == null) return null;
    return const Distance().as(LengthUnit.Meter, p, d);
  }

  @override
  Widget build(BuildContext context) {
    final esPedido = pedido['Tipo'] == 'Pedidos';
    final direccion = (pedido['ClienteDireccion'] ?? 'Sin dirección').toString();
    final servicio = esPedido
        ? (pedido['ServicioNombre'] ?? '').toString()
        : (pedido['Defecto'] ?? '').toString();
    final obs = (pedido['PedidoObs'] ?? '').toString().trim();
    final restantes = V2Data.minutosRestantes(pedido);
    final dist = _distanciaMts;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: V2Shadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado azul
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [V2Colors.azulOscuro, V2Colors.accion],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_shipping_outlined,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  esPedido ? 'PEDIDO ACTUAL' : 'SERVICE ACTUAL',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                if (restantes != null) V2PrioridadChip(minutos: restantes),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Datos del pedido
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            direccion,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: V2Colors.textoPrimario,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (servicio.isNotEmpty)
                            _dato(
                                esPedido
                                    ? Icons.propane_tank_outlined
                                    : Icons.build_outlined,
                                servicio),
                          _dato(Icons.tag, 'Pedido $pedidoId'),
                          if (restantes != null)
                            _dato(
                              Icons.schedule,
                              restantes >= 0
                                  ? 'Quedan ${V2Data.fmtMinutos(restantes)}'
                                  : 'Atrasado ${V2Data.fmtMinutos(restantes)}',
                              color: restantes < 15
                                  ? V2Colors.rojo
                                  : V2Colors.textoSecundario,
                            ),
                          if (dist != null)
                            _dato(
                              Icons.near_me_outlined,
                              '${V2Data.fmtKm(dist)} · ${V2Data.fmtEta(dist)}',
                            ),
                          if (obs.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: V2Colors.celesteClaro.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  obs,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: V2Colors.textoSecundario,
                                    fontSize: 12.5,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Mini-mapa
                    if (_destino != null)
                      _MiniMapa(
                        destino: _destino!,
                        actual: posicionActual,
                        tileUrl: tileUrl,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // Botón principal
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [V2Colors.accion, V2Colors.celeste],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: V2Colors.accion.withOpacity(0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: onIniciarViaje,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      icon: const Icon(Icons.navigation_outlined, size: 22),
                      label: const Text('Iniciar viaje'),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Botones secundarios
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: onVerDetalle,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: V2Colors.accion,
                            side: const BorderSide(
                                color: V2Colors.accion, width: 1.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          icon: const Icon(Icons.receipt_long_outlined,
                              size: 19),
                          label: const Text('Ver detalle'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: onDevolver,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: V2Colors.rojo,
                            side: BorderSide(
                                color: V2Colors.rojo.withOpacity(0.6)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          icon: const Icon(Icons.keyboard_return, size: 19),
                          label: const Text('Devolver'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dato(IconData icon, String texto, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color ?? V2Colors.textoSecundario),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                color: color ?? V2Colors.textoSecundario,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 🗺️ Mini-mapa de la tarjeta (no interactivo)
// ─────────────────────────────────────────────────────────────────────────
class _MiniMapa extends StatelessWidget {
  final LatLng destino;
  final LatLng? actual;
  final String tileUrl;

  const _MiniMapa({
    required this.destino,
    required this.actual,
    required this.tileUrl,
  });

  double get _zoom {
    if (actual == null) return 15;
    final d = const Distance().as(LengthUnit.Meter, actual!, destino);
    if (d < 800) return 15;
    if (d < 2000) return 14;
    if (d < 5000) return 13;
    if (d < 12000) return 12;
    return 11;
  }

  LatLng get _centro {
    if (actual == null) return destino;
    return LatLng(
      (actual!.latitude + destino.latitude) / 2,
      (actual!.longitude + destino.longitude) / 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 118,
        height: 148,
        child: IgnorePointer(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: _centro,
              initialZoom: _zoom,
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(
                urlTemplate: '$tileUrl/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.moveit',
              ),
              if (actual != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [actual!, destino],
                      color: V2Colors.accion,
                      strokeWidth: 3.5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (actual != null)
                    Marker(
                      point: actual!,
                      width: 26,
                      height: 26,
                      child: const Icon(Icons.local_shipping,
                          color: V2Colors.accion, size: 22),
                    ),
                  Marker(
                    point: destino,
                    width: 32,
                    height: 32,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_on,
                        color: V2Colors.rojo, size: 30),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// ⏱️ Chip de prioridad/urgencia (constantes 40-43 reales)
// ─────────────────────────────────────────────────────────────────────────
class V2PrioridadChip extends StatelessWidget {
  final int minutos;

  const V2PrioridadChip({super.key, required this.minutos});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: V2Data.prioridadDe(minutos),
      builder: (context, snap) {
        final etiqueta = (snap.data?['Etiqueta'] ?? '').toString();
        if (etiqueta.isEmpty) return const SizedBox.shrink();
        final color = snap.data!['Color'] as Color;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            etiqueta,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 📦 Tarjeta SIGUIENTE PEDIDO
// ─────────────────────────────────────────────────────────────────────────
class V2SiguientePedidoCard extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final int pedidoId;
  final Map<String, dynamic>? pedidoAnterior;
  final VoidCallback onTap;

  const V2SiguientePedidoCard({
    super.key,
    required this.pedido,
    required this.pedidoId,
    required this.pedidoAnterior,
    required this.onTap,
  });

  double? get _distanciaDesdeAnterior {
    final u = pedido['ubicacion'];
    final ua = pedidoAnterior?['ubicacion'];
    if (u is! GeoPoint || ua is! GeoPoint) return null;
    return const Distance().as(
      LengthUnit.Meter,
      LatLng(ua.latitude, ua.longitude),
      LatLng(u.latitude, u.longitude),
    );
  }

  @override
  Widget build(BuildContext context) {
    final direccion = (pedido['ClienteDireccion'] ?? 'Sin dirección').toString();
    final restantes = V2Data.minutosRestantes(pedido);
    final dist = _distanciaDesdeAnterior;

    return V2Card(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: V2Colors.celesteClaro,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.skip_next_outlined,
                    color: V2Colors.accion, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'SIGUIENTE PEDIDO',
                          style: TextStyle(
                            color: V2Colors.textoSecundario,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const Spacer(),
                        if (restantes != null)
                          V2PrioridadChip(minutos: restantes),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      direccion,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: V2Colors.textoPrimario,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (dist != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'A ${V2Data.fmtKm(dist)} del pedido actual · ${V2Data.fmtEta(dist)}',
                          style: const TextStyle(
                            color: V2Colors.textoSecundario,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: V2Colors.textoSecundario),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// ➕ Fila "+N pedidos más en tu ruta"
// ─────────────────────────────────────────────────────────────────────────
class V2MasPedidosRow extends StatelessWidget {
  final int cantidad;
  final VoidCallback onTap;

  const V2MasPedidosRow({super.key, required this.cantidad, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return V2Card(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.format_list_bulleted,
                  color: V2Colors.accion, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  cantidad == 1
                      ? '1 pedido más en tu ruta'
                      : '$cantidad pedidos más en tu ruta',
                  style: const TextStyle(
                    color: V2Colors.textoPrimario,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  color: V2Colors.textoSecundario, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 🔧 Estado técnico
// ─────────────────────────────────────────────────────────────────────────
class V2EstadoTecnicoCard extends StatelessWidget {
  final bool gpsOk;
  final bool conexionOk;
  final int? minutosSinSync; // null = nunca sincronizó
  final int? bateria; // null = desconocida

  const V2EstadoTecnicoCard({
    super.key,
    required this.gpsOk,
    required this.conexionOk,
    required this.minutosSinSync,
    required this.bateria,
  });

  @override
  Widget build(BuildContext context) {
    final syncColor = minutosSinSync == null
        ? V2Colors.naranja
        : minutosSinSync! <= 5
            ? V2Colors.verde
            : minutosSinSync! <= 15
                ? V2Colors.naranja
                : V2Colors.rojo;
    final batColor = bateria == null
        ? V2Colors.naranja
        : bateria! <= 10
            ? V2Colors.rojo
            : bateria! <= 20
                ? V2Colors.naranja
                : V2Colors.verde;

    return V2Card(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        children: [
          _item(
            gpsOk ? Icons.gps_fixed : Icons.gps_off,
            'GPS',
            gpsOk ? 'Conectado' : 'Sin señal',
            gpsOk ? V2Colors.verde : V2Colors.rojo,
          ),
          _item(
            conexionOk ? Icons.wifi : Icons.wifi_off,
            'Conexión',
            conexionOk ? 'Óptima' : 'Sin red',
            conexionOk ? V2Colors.verde : V2Colors.rojo,
          ),
          _item(
            Icons.sync,
            'Sincro',
            minutosSinSync == null
                ? 'Pendiente'
                : minutosSinSync! <= 1
                    ? 'Al día'
                    : 'Hace ${minutosSinSync}m',
            syncColor,
          ),
          _item(
            bateria != null && bateria! <= 20
                ? Icons.battery_alert
                : Icons.battery_full,
            'Batería',
            bateria != null ? '$bateria%' : '--',
            batColor,
          ),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String label, String valor, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            valor,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: V2Colors.textoSecundario,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// ✅ Estado sin pedidos: "Estás al día"
// ─────────────────────────────────────────────────────────────────────────
class V2AlDiaCard extends StatelessWidget {
  final VoidCallback onVerPromos;

  const V2AlDiaCard({super.key, required this.onVerPromos});

  @override
  Widget build(BuildContext context) {
    return V2Card(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              color: V2Colors.celesteClaro,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_shipping_outlined,
                color: V2Colors.accion, size: 44),
          ),
          const SizedBox(height: 18),
          const Text(
            'Estás al día',
            style: TextStyle(
              color: V2Colors.textoPrimario,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No tenés pedidos pendientes.\nTe avisaremos cuando se asigne uno nuevo.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: V2Colors.textoSecundario,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: onVerPromos,
            style: TextButton.styleFrom(foregroundColor: V2Colors.accion),
            icon: const Icon(Icons.card_giftcard, size: 20),
            label: const Text(
              'Ver promociones',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
