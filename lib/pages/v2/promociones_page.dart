import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../services/persistent_stream_manager.dart';
import 'v2_data.dart';
import 'v2_theme.dart';

/// 🎁 Promociones: campañas, desafíos y premios para el chofer.
/// Fuente: colección Firestore `Promociones-{escenario}` vía
/// PersistentStreamManager (ver docs/PROMOCIONES_FIRESTORE.md).
class PromocionesPage extends StatefulWidget {
  const PromocionesPage({super.key});

  @override
  State<PromocionesPage> createState() => _PromocionesPageState();
}

class _PromocionesPageState extends State<PromocionesPage> {
  final _streamManager = PersistentStreamManager();
  int _entregadasHoy = 0;

  @override
  void initState() {
    super.initState();
    _cargarProgreso();
    _marcarVistas();
  }

  Future<void> _cargarProgreso() async {
    final entregadas = await V2Data.entregadasHoy();
    if (mounted) setState(() => _entregadasHoy = entregadas);
  }

  /// Marca todas las promos vigentes como vistas (apaga el badge del tab)
  Future<void> _marcarVistas() async {
    try {
      final box = await Hive.openBox('promocionesVistasBox');
      for (final doc in _streamManager.promocionesNotifier.value) {
        await box.put(doc.id, true);
      }
    } catch (e) {
      print('⚠️ [PROMOS] Error marcando vistas: $e');
    }
  }

  String _fmtFecha(dynamic fchInt) {
    final n = int.tryParse(fchInt?.toString() ?? '');
    if (n == null || n < 19000101) return '';
    final d = n % 100;
    final m = (n ~/ 100) % 100;
    return '${d.toString().padLeft2()}/${m.toString().padLeft2()}';
  }

  @override
  Widget build(BuildContext context) {
    final statusBar = MediaQuery.of(context).padding.top;
    return Container(
      color: V2Colors.fondo,
      child: Column(
        children: [
          // Cabecera compacta
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20, statusBar + 14, 20, 18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [V2Colors.azulOscuro, V2Colors.accion],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Row(
                  children: [
                    Icon(Icons.card_giftcard, color: Colors.white, size: 26),
                    SizedBox(width: 10),
                    Text(
                      'Promociones',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  'Desafíos, premios y beneficios para vos',
                  style: TextStyle(color: Colors.white70, fontSize: 13.5),
                ),
              ],
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<List<DocumentSnapshot>>(
              valueListenable: _streamManager.promocionesNotifier,
              builder: (context, promos, _) {
                // Cada vez que llegan promos nuevas, marcarlas vistas
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _marcarVistas());

                if (promos.isEmpty) {
                  return _emptyState();
                }
                return RefreshIndicator(
                  color: V2Colors.accion,
                  onRefresh: _cargarProgreso,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: promos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final promo =
                          promos[i].data() as Map<String, dynamic>;
                      return _promoCard(promo);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: V2Colors.celesteClaro,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.card_giftcard,
                  color: V2Colors.accion, size: 48),
            ),
            const SizedBox(height: 20),
            const Text(
              'No hay promociones vigentes',
              style: TextStyle(
                color: V2Colors.textoPrimario,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cuando haya campañas, desafíos o premios nuevos\nlos vas a ver acá.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: V2Colors.textoSecundario,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _promoCard(Map<String, dynamic> promo) {
    final titulo = (promo['Titulo'] ?? '').toString();
    final descripcion = (promo['Descripcion'] ?? '').toString();
    final premio = (promo['Premio'] ?? '').toString();
    final tipoMeta = (promo['TipoMeta'] ?? 'info').toString();
    final meta = int.tryParse(promo['MetaCantidad']?.toString() ?? '') ?? 0;
    final hasta = _fmtFecha(promo['FchHasta']);

    final esDesafio = tipoMeta == 'entregas_dia' && meta > 0;
    final progreso = esDesafio ? (_entregadasHoy / meta).clamp(0.0, 1.0) : 0.0;
    final completado = esDesafio && _entregadasHoy >= meta;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: V2Shadows.card,
        border: Border.all(
          color: completado
              ? V2Colors.verde.withOpacity(0.5)
              : V2Colors.celesteClaro,
          width: 1.4,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [V2Colors.accion, V2Colors.celeste],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  completado
                      ? Icons.emoji_events
                      : esDesafio
                          ? Icons.flag_outlined
                          : Icons.campaign_outlined,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: V2Colors.textoPrimario,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (hasta.isNotEmpty)
                      Text(
                        'Vigente hasta el $hasta',
                        style: const TextStyle(
                          color: V2Colors.textoSecundario,
                          fontSize: 11.5,
                        ),
                      ),
                  ],
                ),
              ),
              if (completado)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: V2Colors.verde.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '¡Logrado!',
                    style: TextStyle(
                      color: V2Colors.verde,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          if (descripcion.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              descripcion,
              style: const TextStyle(
                color: V2Colors.textoSecundario,
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
          ],
          if (esDesafio) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progreso,
                      minHeight: 10,
                      backgroundColor: V2Colors.celesteClaro,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        completado ? V2Colors.verde : V2Colors.accion,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$_entregadasHoy de $meta',
                  style: const TextStyle(
                    color: V2Colors.textoPrimario,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
          if (premio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: V2Colors.celesteClaro.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard,
                      color: V2Colors.accion, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Premio: $premio',
                      style: const TextStyle(
                        color: V2Colors.textoPrimario,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

extension on String {
  String padLeft2() => padLeft(2, '0');
}
