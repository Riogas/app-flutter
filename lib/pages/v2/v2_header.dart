import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/logout_service.dart';
import '../../services/persistent_stream_manager.dart';
import '../../utils/constantes.dart';
import '../message_page.dart';
import '../settings_page.dart';
import 'v2_data.dart';
import 'v2_theme.dart';

/// 🏙️ Cabecera del rediseño: ilustración + degradado, logo, mensajes,
/// avatar con menú, píldora de estado del móvil y saludo.
class V2Header extends StatelessWidget {
  final ValueNotifier<int> messageCountNotifier;
  final Future<void> Function(BuildContext context) onEstadoTap;
  final bool problemaTecnico; // GPS/conexión con problemas → píldora naranja

  const V2Header({
    super.key,
    required this.messageCountNotifier,
    required this.onEstadoTap,
    this.problemaTecnico = false,
  });

  static const String _resourcesBase =
      'https://www.riogas.uy/ica_geos_/static/Resources';

  bool get _esDia {
    final h = DateTime.now().hour;
    return h >= 6 && h < 20;
  }

  @override
  Widget build(BuildContext context) {
    final statusBar = MediaQuery.of(context).padding.top;
    return SizedBox(
      height: 182 + statusBar,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 🖼️ Fondo: background_home.png remoto → fallback ilustración
          // día/noche del login → fallback color sólido
          CachedNetworkImage(
            imageUrl: '$_resourcesBase/background_home.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            placeholder: (_, __) => Container(color: V2Colors.azulOscuro),
            errorWidget: (_, __, ___) => CachedNetworkImage(
              imageUrl:
                  '$_resourcesBase/background_delivery_${_esDia ? 'dia' : 'noche'}.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              placeholder: (_, __) => Container(color: V2Colors.azulOscuro),
              errorWidget: (_, __, ___) =>
                  Container(color: V2Colors.azulOscuro),
            ),
          ),
          // 🌓 Degradado azul oscuro para legibilidad sin tapar la ilustración
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  V2Colors.azulOscuro.withOpacity(0.88),
                  V2Colors.azulOscuro.withOpacity(0.55),
                  V2Colors.azulOscuro.withOpacity(0.82),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          // Contenido
          Padding(
            padding: EdgeInsets.fromLTRB(20, statusBar + 6, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildLogo(),
                    const Spacer(),
                    _buildMensajesIcon(context),
                    const SizedBox(width: 4),
                    _buildAvatarMenu(context),
                  ],
                ),
                const SizedBox(height: 2),
                // Nombre a la izquierda + estado del móvil a la derecha
                Row(
                  children: [
                    Expanded(child: _buildNombre()),
                    const SizedBox(width: 10),
                    _buildEstadoPill(context),
                  ],
                ),
                // Espacio para la tarjeta de resumen que se superpone
                const SizedBox(height: 82),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Logo (recortado como en el login: el PNG trae aire transparente) ──
  Widget _buildLogo() {
    return ClipRect(
      child: Align(
        alignment: Alignment.center,
        heightFactor: 0.55,
        child: CachedNetworkImage(
          imageUrl: '$_resourcesBase/RGDelivery.png',
          height: 96,
          fit: BoxFit.contain,
          placeholder: (_, __) => const SizedBox(height: 96, width: 96),
          errorWidget: (_, __, ___) => const Text(
            'RIOGAS DELIVERY',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  // ── Icono de mensajes con badge de no leídos ──
  Widget _buildMensajesIcon(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: messageCountNotifier,
      builder: (context, count, _) {
        return IconButton(
          tooltip: 'Mensajes de despacho',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => MessagePage()),
            );
          },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.forum_outlined, color: Colors.white, size: 26),
              if (count > 0)
                Positioned(
                  right: -5,
                  top: -5,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: V2Colors.rojo,
                      shape: BoxShape.circle,
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Avatar con menú del chofer ──
  Widget _buildAvatarMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Menú del chofer',
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: CircleAvatar(
        radius: 18,
        backgroundColor: Colors.white.withOpacity(0.22),
        child: const Icon(Icons.person, color: Colors.white, size: 22),
      ),
      onSelected: (value) => _onMenuSelected(context, value),
      itemBuilder: (context) => [
        _menuItem('perfil', Icons.badge_outlined, 'Perfil del chofer'),
        _menuItem('config', Icons.settings_outlined, 'Configuración'),
        _menuItem('estado', Icons.local_shipping_outlined, 'Estado del móvil'),
        _menuItem('ayuda', Icons.help_outline, 'Ayuda'),
        const PopupMenuDivider(),
        _menuItem('logout', Icons.logout, 'Cerrar sesión',
            color: V2Colors.rojo),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
      {Color? color}) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? V2Colors.textoPrimario),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(color: color ?? V2Colors.textoPrimario)),
        ],
      ),
    );
  }

  Future<void> _onMenuSelected(BuildContext context, String value) async {
    switch (value) {
      case 'perfil':
      case 'config':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SettingsPage()),
        );
        break;
      case 'estado':
        await onEstadoTap(context);
        break;
      case 'ayuda':
        await _mostrarAyuda(context);
        break;
      case 'logout':
        await _confirmarLogout(context);
        break;
    }
  }

  Future<void> _mostrarAyuda(BuildContext context) async {
    final telefono = (await getConstantValue('170') ?? '').trim();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Ayuda'),
        content: Text(
          telefono.isNotEmpty
              ? 'Ante cualquier problema comunicate con despacho.'
              : 'Ante cualquier problema comunicate con despacho o con tu supervisor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          if (telefono.isNotEmpty)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: V2Colors.accion,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final uri = Uri.parse('tel:$telefono');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
              icon: const Icon(Icons.phone, size: 18),
              label: const Text('Llamar a despacho'),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmarLogout(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que querés cerrar la sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: V2Colors.rojo,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    final box = await Hive.openBox('sessionBox');
    await LogoutService.executeLogout(
      isRemoteLogout: false,
      nombreUsuario: box.get('NombreUsuario') ?? '',
      idUsuario: box.get('username') ?? '',
      deviceId: box.get('deviceId') ?? '',
    );
  }

  // ── Píldora de estado del móvil ──
  Widget _buildEstadoPill(BuildContext context) {
    final sm = PersistentStreamManager();
    return ValueListenableBuilder<DocumentSnapshot?>(
      valueListenable: sm.movilNotifier,
      builder: (context, movilSnap, _) {
        return ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: sm.subEstadoMovilesNotifier,
          builder: (context, subEstados, __) {
            String movil = '';
            String desc = 'Cargando...';
            Color color = V2Colors.textoSecundario;
            try {
              final sessionBox = Hive.box('sessionBox');
              movil = sessionBox.get('movil', defaultValue: '').toString();
            } catch (_) {}
            if (movilSnap != null && subEstados.isNotEmpty) {
              try {
                final data = movilSnap.data() as Map<String, dynamic>;
                final estadoNro = data['EstadoNro'];
                final sub = subEstados.firstWhere(
                  (s) => s['SubEstadoCod'].toString() == estadoNro.toString(),
                  orElse: () => {},
                );
                if (sub.isNotEmpty) {
                  desc = sub['SubEstadoDesc'] ?? 'Estado $estadoNro';
                  color = _colorFromCodColor(sub['CodColor']?.toString());
                } else {
                  desc = 'Estado $estadoNro';
                }
              } catch (_) {
                desc = 'Sin datos';
              }
            }
            // ⚠️ Problemas de GPS/conexión pintan la píldora naranja
            if (problemaTecnico) color = V2Colors.naranja;

            return GestureDetector(
              onTap: () => onEstadoTap(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: color.withOpacity(0.9), width: 1.4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Móvil $movil · $desc',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.keyboard_arrow_down,
                        color: Colors.white.withOpacity(0.8), size: 18),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _colorFromCodColor(String? codColor) {
    if (codColor == null) return V2Colors.textoSecundario;
    try {
      final parts = codColor.split(',').map((p) => int.parse(p.trim())).toList();
      if (parts.length == 3) {
        return Color.fromARGB(255, parts[0], parts[1], parts[2]);
      }
    } catch (_) {}
    return V2Colors.textoSecundario;
  }

  // ── Nombre del chofer (misma línea que la píldora de estado) ──
  Widget _buildNombre() {
    String nombre = '';
    try {
      nombre = Hive.box('sessionBox').get('NombreUsuario', defaultValue: '');
    } catch (_) {}
    return Text(
      V2Data.primerNombre(nombre),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );
  }
}
