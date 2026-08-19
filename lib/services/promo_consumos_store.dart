import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Un consumo de beneficio registrado en el dispositivo
class PromoConsumo {
  final String id;
  final String promo;
  final int idInterno;

  /// ⚠️ El código del cupón NO se guarda entero: solo esta máscara, que es
  /// lo único que se muestra. Después de validar el código no tiene ningún
  /// uso (no viaja al consumo ni a la anulación), así que no hay motivo para
  /// tenerlo en el teléfono.
  final String codigoMascara;
  final String telefono;
  final String cliente;
  final String beneficio;
  final String autorizacion;
  final DateTime fechaHora;
  final bool anulada;
  final DateTime? fechaAnulacion;

  /// Id del consumo en SGM (`Mdu_MDUID` de ConsumirPromo). Lo pide
  /// AnularPromo; 0 en consumos previos a que el server lo devolviera.
  final int mduId;

  /// Pre-registración que originó el consumo (`NroTrn` de ValidarPromo, que
  /// viaja como `PreMduId` al consumir). No hace falta para anular, pero es
  /// el único hilo para rastrear qué validación generó este consumo.
  final int preMduId;

  const PromoConsumo({
    required this.id,
    required this.promo,
    required this.idInterno,
    required this.codigoMascara,
    required this.telefono,
    required this.cliente,
    required this.beneficio,
    required this.autorizacion,
    required this.fechaHora,
    this.anulada = false,
    this.fechaAnulacion,
    this.mduId = 0,
    this.preMduId = 0,
  });

  Map<String, dynamic> toMap() => {
        'promo': promo,
        'idInterno': idInterno,
        'codigoMascara': codigoMascara,
        'telefono': telefono,
        'cliente': cliente,
        'beneficio': beneficio,
        'autorizacion': autorizacion,
        'fechaHora': fechaHora.toIso8601String(),
        'anulada': anulada,
        'fechaAnulacion': fechaAnulacion?.toIso8601String(),
        'mduId': mduId,
        'preMduId': preMduId,
      };

  static PromoConsumo fromMap(String id, Map<dynamic, dynamic> m) {
    return PromoConsumo(
      id: id,
      promo: (m['promo'] ?? '').toString(),
      idInterno: int.tryParse(m['idInterno']?.toString() ?? '') ?? 0,
      // Registros viejos guardaban el código entero en 'codigo': se enmascara
      // al leerlos (y init() los reescribe enmascarados).
      codigoMascara: (m['codigoMascara'] ?? '').toString().isNotEmpty
          ? m['codigoMascara'].toString()
          : PromoConsumosStore.enmascarar((m['codigo'] ?? '').toString()),
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
      mduId: int.tryParse(m['mduId']?.toString() ?? '') ?? 0,
      preMduId: int.tryParse(m['preMduId']?.toString() ?? '') ?? 0,
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

  /// Retención local de registros
  static const Duration _retencion = Duration(days: 7);

  /// Enmascara el código del cupón para poder mostrarlo sin exponerlo.
  ///
  /// La cantidad de caracteres visibles es PROPORCIONAL al largo: hay
  /// campañas con códigos de 3 o 4 caracteres (`A018`, `1004`), y ahí
  /// "mostrar los últimos 4" sería mostrarlo entero. Nunca se revela más de
  /// la mitad, con un tope de 4.
  static String enmascarar(String codigo) {
    final c = codigo.trim();
    if (c.isEmpty) return '';
    final visibles = c.length <= 3 ? 1 : (c.length ~/ 2).clamp(1, 4);
    final puntos = (c.length - visibles).clamp(1, 4);
    return '${'•' * puntos}${c.substring(c.length - visibles)}';
  }

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
      // Los registros viejos guardaban el código entero: se reescriben
      // enmascarados para que deje de estar en el teléfono.
      for (final key in box.keys) {
        final m = box.get(key);
        if (m is Map && (m['codigo']?.toString().isNotEmpty ?? false)) {
          final limpio = Map<String, dynamic>.from(m);
          limpio['codigoMascara'] = (m['codigoMascara']?.toString().isNotEmpty ?? false)
              ? m['codigoMascara'].toString()
              : enmascarar(m['codigo'].toString());
          limpio.remove('codigo');
          await box.put(key, limpio);
        }
      }
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
    int mduId = 0,
    int preMduId = 0,
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
          // Solo la máscara: el código entero no se guarda nunca.
          codigoMascara: enmascarar(codigo),
          telefono: telefono,
          cliente: cliente,
          beneficio: beneficio,
          autorizacion: autorizacion,
          fechaHora: ahora,
          mduId: mduId,
          preMduId: preMduId,
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

  /// Consumos visibles en "Promos del día" (más recientes primero).
  ///
  /// Son los de hoy MÁS cualquiera que todavía esté dentro de su ventana de
  /// anulación. Ese agregado tapa el corte de medianoche: un consumo hecho
  /// 23:50 desaparecía a las 00:00 con la ventana todavía abierta, y quedaba
  /// sin forma de anularse desde la app.
  List<PromoConsumo> get visibles {
    final ahora = DateTime.now();
    return consumos.value
        .where((c) =>
            (c.fechaHora.year == ahora.year &&
                c.fechaHora.month == ahora.month &&
                c.fechaHora.day == ahora.day) ||
            puedeAnular(c))
        .toList();
  }

  @Deprecated('Usar `visibles`: delDia perdía los consumos de fin del día '
      'que seguían siendo anulables después de medianoche.')
  List<PromoConsumo> get delDia => visibles;

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
