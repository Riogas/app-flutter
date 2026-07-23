import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Un consumo de beneficio registrado en el dispositivo
class PromoConsumo {
  final String id;
  final String promo;
  final int idInterno;
  final String codigo;
  final String telefono;
  final String cliente;
  final String beneficio;
  final String autorizacion;
  final DateTime fechaHora;
  final bool anulada;
  final DateTime? fechaAnulacion;

  const PromoConsumo({
    required this.id,
    required this.promo,
    required this.idInterno,
    required this.codigo,
    required this.telefono,
    required this.cliente,
    required this.beneficio,
    required this.autorizacion,
    required this.fechaHora,
    this.anulada = false,
    this.fechaAnulacion,
  });

  Map<String, dynamic> toMap() => {
        'promo': promo,
        'idInterno': idInterno,
        'codigo': codigo,
        'telefono': telefono,
        'cliente': cliente,
        'beneficio': beneficio,
        'autorizacion': autorizacion,
        'fechaHora': fechaHora.toIso8601String(),
        'anulada': anulada,
        'fechaAnulacion': fechaAnulacion?.toIso8601String(),
      };

  static PromoConsumo fromMap(String id, Map<dynamic, dynamic> m) {
    return PromoConsumo(
      id: id,
      promo: (m['promo'] ?? '').toString(),
      idInterno: int.tryParse(m['idInterno']?.toString() ?? '') ?? 0,
      codigo: (m['codigo'] ?? '').toString(),
      telefono: (m['telefono'] ?? '').toString(),
      cliente: (m['cliente'] ?? '').toString(),
      beneficio: (m['beneficio'] ?? '').toString(),
      autorizacion: (m['autorizacion'] ?? '').toString(),
      fechaHora:
          DateTime.tryParse(m['fechaHora']?.toString() ?? '') ?? DateTime.now(),
      anulada: m['anulada'] == true,
      fechaAnulacion: m['fechaAnulacion'] != null
          ? DateTime.tryParse(m['fechaAnulacion'].toString())
          : null,
    );
  }
}

/// 🧾 Registro local (Hive) de los consumos de beneficios del dispositivo.
/// Permite ver las promos del día y ANULAR un consumo dentro de la ventana
/// de anulación. Cuando exista la API GeneXus, la anulación también viajará
/// al backend (ver BeneficiosService.anular).
class PromoConsumosStore {
  PromoConsumosStore._();
  static final PromoConsumosStore _instance = PromoConsumosStore._();
  factory PromoConsumosStore() => _instance;

  static const String _boxName = 'promosConsumosBox';

  /// ⏳ Ventana durante la cual un consumo se puede anular
  static const Duration ventanaAnulacion = Duration(minutes: 30);

  /// Retención local de registros (solo se muestran los del día)
  static const Duration _retencion = Duration(days: 7);

  final ValueNotifier<List<PromoConsumo>> consumos =
      ValueNotifier(const []);

  bool _inicializado = false;

  Future<Box> _box() async => Hive.isBoxOpen(_boxName)
      ? Hive.box(_boxName)
      : await Hive.openBox(_boxName);

  Future<void> init() async {
    if (_inicializado) return;
    _inicializado = true;
    try {
      final box = await _box();
      // Purga de registros viejos
      final limite = DateTime.now().subtract(_retencion);
      final aBorrar = <dynamic>[];
      for (final key in box.keys) {
        final m = box.get(key);
        if (m is Map) {
          final f = DateTime.tryParse(m['fechaHora']?.toString() ?? '');
          if (f != null && f.isBefore(limite)) aBorrar.add(key);
        }
      }
      await box.deleteAll(aBorrar);
      await _recargar();
      print('🧾 [CONSUMOS] Store inicializado (${consumos.value.length})');
    } catch (e) {
      print('❌ [CONSUMOS] Error inicializando store: $e');
    }
  }

  Future<void> _recargar() async {
    final box = await _box();
    final lista = <PromoConsumo>[];
    for (final key in box.keys) {
      final m = box.get(key);
      if (m is Map) lista.add(PromoConsumo.fromMap(key.toString(), m));
    }
    lista.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
    consumos.value = lista;
  }

  /// Registra un consumo confirmado
  Future<void> registrar({
    required String promo,
    required int idInterno,
    required String codigo,
    required String telefono,
    required String cliente,
    required String beneficio,
    required String autorizacion,
    DateTime? fechaHora,
  }) async {
    try {
      final box = await _box();
      final ahora = fechaHora ?? DateTime.now();
      final id = ahora.millisecondsSinceEpoch.toString();
      await box.put(
        id,
        PromoConsumo(
          id: id,
          promo: promo,
          idInterno: idInterno,
          codigo: codigo,
          telefono: telefono,
          cliente: cliente,
          beneficio: beneficio,
          autorizacion: autorizacion,
          fechaHora: ahora,
        ).toMap(),
      );
      await _recargar();
      print('🧾 [CONSUMOS] Registrado consumo $autorizacion ($promo)');
    } catch (e) {
      print('❌ [CONSUMOS] Error registrando consumo: $e');
    }
  }

  /// Marca un consumo como anulado (tras confirmar contra la API)
  Future<void> marcarAnulada(String id) async {
    try {
      final box = await _box();
      final m = box.get(id);
      if (m is Map) {
        final actualizado = Map<String, dynamic>.from(m);
        actualizado['anulada'] = true;
        actualizado['fechaAnulacion'] = DateTime.now().toIso8601String();
        await box.put(id, actualizado);
        await _recargar();
        print('🧾 [CONSUMOS] Consumo $id anulado');
      }
    } catch (e) {
      print('❌ [CONSUMOS] Error anulando consumo: $e');
    }
  }

  /// Consumos del día (más recientes primero)
  List<PromoConsumo> get delDia {
    final ahora = DateTime.now();
    return consumos.value
        .where((c) =>
            c.fechaHora.year == ahora.year &&
            c.fechaHora.month == ahora.month &&
            c.fechaHora.day == ahora.day)
        .toList();
  }

  /// ¿Sigue dentro de la ventana de anulación?
  bool puedeAnular(PromoConsumo c) =>
      !c.anulada &&
      DateTime.now().difference(c.fechaHora) < ventanaAnulacion;

  /// Minutos restantes para poder anular (0 si ya no se puede)
  int minutosParaAnular(PromoConsumo c) {
    final restante =
        ventanaAnulacion - DateTime.now().difference(c.fechaHora);
    return restante.isNegative ? 0 : restante.inMinutes + 1;
  }
}
