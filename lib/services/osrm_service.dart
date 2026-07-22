import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Tramo entre dos paradas consecutivas de la ruta
class OsrmTramo {
  final double distanciaM;
  final double duracionSeg;

  const OsrmTramo({required this.distanciaM, required this.duracionSeg});
}

/// Ruta calculada por OSRM (calles reales), con uno o más destinos
class OsrmRuta {
  final List<LatLng> puntos;
  final double distanciaM; // total
  final double duracionSeg; // total
  final List<OsrmTramo> tramos; // uno por leg (posición→P1, P1→P2, ...)

  const OsrmRuta({
    required this.puntos,
    required this.distanciaM,
    required this.duracionSeg,
    this.tramos = const [],
  });

  /// Tramo hasta la primera parada (para "Parada actual")
  OsrmTramo? get primerTramo => tramos.isNotEmpty ? tramos.first : null;
}

/// 🛣️ Cliente del OSRM propio de RioGas (https://osrm.riogas.com.uy,
/// Uruguay completo, self-hosted detrás de nginx).
///
/// - URL base configurable por constante Firestore `271` (Estado 'A' →
///   usa `Valor`); si no existe, usa el default.
/// - Cache en memoria por par de coordenadas (redondeo a 4 decimales ≈ 11 m)
///   con TTL de 2 minutos + dedupe de llamadas en vuelo.
/// - Ante cualquier error devuelve null → el llamador usa su fallback
///   (línea recta / estimación).
class OsrmService {
  OsrmService._();
  static final OsrmService _instance = OsrmService._();
  factory OsrmService() => _instance;

  static const String _defaultBase = 'https://osrm.riogas.com.uy';
  static const Duration _ttl = Duration(minutes: 2);
  static const Duration _timeout = Duration(seconds: 12);

  final Map<String, _Entrada> _cache = {};
  final Map<String, Future<OsrmRuta?>> _enVuelo = {};

  Future<String> _baseUrl() async {
    try {
      final box = await Hive.openBox('constantBox');
      final data = box.get('271');
      if (data != null && data['Estado'] == 'A') {
        final v = data['Valor']?.toString().trim() ?? '';
        if (v.isNotEmpty) return v;
      }
    } catch (_) {}
    return _defaultBase;
  }

  String _clave(List<LatLng> puntos) => puntos
      .map((p) =>
          '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}')
      .join('|');

  /// Ruta por calles de [desde] a [hasta]; null si OSRM no responde.
  Future<OsrmRuta?> ruta(LatLng desde, LatLng hasta) =>
      rutaPorPuntos([desde, hasta]);

  /// Ruta por calles pasando por TODOS los [waypoints] en orden
  /// (posición → parada 1 → parada 2 → ...); null si OSRM no responde.
  /// OSRM resuelve multi-waypoint en una sola llamada.
  Future<OsrmRuta?> rutaPorPuntos(List<LatLng> waypoints) {
    if (waypoints.length < 2) return Future.value(null);
    // Límite sano de paradas por URL (más que suficiente para una ruta diaria)
    final puntos =
        waypoints.length > 26 ? waypoints.sublist(0, 26) : waypoints;
    final clave = _clave(puntos);

    final cacheada = _cache[clave];
    if (cacheada != null &&
        DateTime.now().difference(cacheada.momento) < _ttl) {
      return Future.value(cacheada.ruta);
    }

    final enVuelo = _enVuelo[clave];
    if (enVuelo != null) return enVuelo;

    final futuro = _consultar(puntos).then((ruta) {
      // Solo cachear éxitos: un timeout no debe envenenar la ruta 2 minutos
      if (ruta != null) {
        _cache[clave] = _Entrada(ruta, DateTime.now());
      }
      _enVuelo.remove(clave);
      return ruta;
    });
    _enVuelo[clave] = futuro;
    return futuro;
  }

  Future<OsrmRuta?> _consultar(List<LatLng> puntosRuta) async {
    try {
      final base = await _baseUrl();
      final coordsUrl = puntosRuta
          .map((p) => '${p.longitude},${p.latitude}')
          .join(';');
      final uri = Uri.parse('$base/route/v1/driving/$coordsUrl'
          '?overview=full&geometries=geojson&alternatives=false&steps=false');

      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return null;

      final rutas = data['routes'] as List<dynamic>?;
      if (rutas == null || rutas.isEmpty) return null;

      final r = rutas.first as Map<String, dynamic>;
      final coords =
          (r['geometry']?['coordinates'] as List<dynamic>?) ?? const [];
      final puntos = coords
          .map((c) => LatLng(
              (c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      final tramos = ((r['legs'] as List<dynamic>?) ?? const [])
          .map((l) => OsrmTramo(
                distanciaM: (l['distance'] as num?)?.toDouble() ?? 0,
                duracionSeg: (l['duration'] as num?)?.toDouble() ?? 0,
              ))
          .toList();

      return OsrmRuta(
        puntos: puntos,
        distanciaM: (r['distance'] as num?)?.toDouble() ?? 0,
        duracionSeg: (r['duration'] as num?)?.toDouble() ?? 0,
        tramos: tramos,
      );
    } catch (e) {
      print('⚠️ [OSRM] Sin ruta (fallback a línea recta): $e');
      return null;
    }
  }
}

class _Entrada {
  final OsrmRuta? ruta;
  final DateTime momento;
  _Entrada(this.ruta, this.momento);
}
