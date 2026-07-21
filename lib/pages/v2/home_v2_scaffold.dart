import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../services/persistent_stream_manager.dart';
import '../map_page.dart';
import 'pedidos_tab_v2.dart';
import 'promociones_page.dart';
import 'v2_theme.dart';

/// 🏗️ Scaffold del rediseño 2026: Pedidos / Mapa / Promos.
/// Presentación pura — la lógica (streams, FCM, estado del móvil) sigue
/// viviendo en HomePage, que nos pasa notifiers y callbacks.
class HomeV2Scaffold extends StatefulWidget {
  final ValueNotifier<int> messageCountNotifier;
  final Future<void> Function(BuildContext context) onEstadoTap;

  const HomeV2Scaffold({
    super.key,
    required this.messageCountNotifier,
    required this.onEstadoTap,
  });

  @override
  State<HomeV2Scaffold> createState() => _HomeV2ScaffoldState();
}

class _HomeV2ScaffoldState extends State<HomeV2Scaffold> {
  int _tab = 0;
  final _streamManager = PersistentStreamManager();
  Box? _vistasBox;

  @override
  void initState() {
    super.initState();
    Hive.openBox('promocionesVistasBox').then((box) {
      if (mounted) setState(() => _vistasBox = box);
    });
  }

  int _promosNuevas(List<DocumentSnapshot> promos) {
    if (_vistasBox == null) return promos.length;
    return promos.where((d) => _vistasBox!.get(d.id) != true).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Colors.fondo,
      body: IndexedStack(
        index: _tab,
        children: [
          PedidosTabV2(
            messageCountNotifier: widget.messageCountNotifier,
            onEstadoTap: widget.onEstadoTap,
            onVerPromos: () => setState(() => _tab = 2),
          ),
          MapPage(),
          PromocionesPage(
            messageCountNotifier: widget.messageCountNotifier,
            onEstadoTap: widget.onEstadoTap,
          ),
        ],
      ),
      bottomNavigationBar: ValueListenableBuilder<List<DocumentSnapshot>>(
        valueListenable: _streamManager.pedidosNotifier,
        builder: (context, pedidos, _) {
          return ValueListenableBuilder<List<DocumentSnapshot>>(
            valueListenable: _streamManager.promocionesNotifier,
            builder: (context, promos, __) {
              final promosNuevas = _promosNuevas(promos);
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: V2Colors.azulOscuro.withOpacity(0.10),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: BottomNavigationBar(
                  items: [
                    _item(Icons.local_shipping_outlined, Icons.local_shipping,
                        'Pedidos', pedidos.length),
                    _item(Icons.map_outlined, Icons.map, 'Mapa', 0),
                    _item(Icons.card_giftcard_outlined, Icons.card_giftcard,
                        'Promos', promosNuevas),
                  ],
                  currentIndex: _tab,
                  onTap: (i) {
                    setState(() => _tab = i);
                    // Entrar a Promos apaga el badge (la página marca vistas)
                    if (i == 2) {
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (mounted) setState(() {});
                      });
                    }
                  },
                  backgroundColor: Colors.white,
                  elevation: 0,
                  type: BottomNavigationBarType.fixed,
                  selectedItemColor: V2Colors.accion,
                  unselectedItemColor: V2Colors.textoSecundario,
                  selectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                  ),
                  showUnselectedLabels: true,
                ),
              );
            },
          );
        },
      ),
    );
  }

  BottomNavigationBarItem _item(
      IconData icon, IconData activeIcon, String label, int badge) {
    Widget conBadge(Widget child) {
      if (badge <= 0) return child;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            right: -8,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(3.5),
              decoration: const BoxDecoration(
                color: V2Colors.rojo,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              child: Text(
                '$badge',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return BottomNavigationBarItem(
      icon: conBadge(Icon(icon, size: 24)),
      activeIcon: conBadge(Icon(activeIcon, size: 24)),
      label: label,
    );
  }
}
