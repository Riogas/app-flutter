import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../services/logout_service.dart';
import '../../services/persistent_stream_manager.dart';
import '../message_page.dart';
import '../settings_page.dart';
import 'v2_data.dart';
import 'v2_theme.dart';

/// 🏙️ Cabecera del rediseño: ilustración + degradado, logo, mensajes,
/// avatar con menú, píldora de estado del móvil y saludo.
class V2Header extends StatelessWidget {
  // Opcionales: en pantallas pushed (ej. Mensajes) no hay contador de
  // mensajes ni cambio de estado disponibles; se omiten.
  final ValueNotifier<int>? messageCountNotifier;
  final Future<void> Function(BuildContext context)? onEstadoTap;
  final bool problemaTecnico; // GPS/conexión con problemas → píldora naranja

  /// Modo sección: si [titulo] viene, se muestra en lugar del nombre del
  /// chofer (con [subtitulo] opcional debajo). Usado por Promociones.
  final String? titulo;
  final String? subtitulo;
  final double height;
  final double bottomSpace;

  /// Si viene, la izquierda muestra un botón de volver en lugar del logo.
  final VoidCallback? onBack;

  /// Si false, oculta el icono de mensajes y el avatar (para pantallas que
  /// ya están pushed, como Mensajes, donde serían redundantes).
  final bool showActions;

  const V2Header({
    super.key,
    this.messageCountNotifier,
    this.onEstadoTap,
    this.problemaTecnico = false,
    this.titulo,
    this.subtitulo,
    this.height = 182,
    this.bottomSpace = 82,
    this.onBack,
    this.showActions = true,
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
      height: height + statusBar,
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
                    onBack != null ? _buildBackButton(context) : _buildLogo(),
                    const Spacer(),
                    if (showActions) ...[
                      _buildMensajesIcon(context),
                      const SizedBox(width: 4),
                      _buildAvatarMenu(context),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                if (titulo != null) ...[
                  // Modo sección: título corto + píldora a la derecha
                  Row(
                    children: [
                      Expanded(child: _buildTitulo()),
                      const SizedBox(width: 10),
                      _buildEstadoPill(context),
                    ],
                  ),
                  if (subtitulo != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitulo!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ] else
                  // Modo home: nombre + píldora en la misma línea
                  Row(
                    children: [
                      Expanded(child: _buildNombre()),
                      const SizedBox(width: 10),
                      _buildEstadoPill(context),
                    ],
                  ),
                // Espacio inferior (para tarjetas que se superponen)
                SizedBox(height: bottomSpace),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Logo (asset local con transparencia real) ──
  Widget _buildLogo() {
    return Image.asset(
      'assets/logo_delivery.png',
      height: 40,
      fit: BoxFit.contain,
    );
  }

  // ── Botón de volver (pantallas pushed) ──
  Widget _buildBackButton(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onBack,
        child: const SizedBox(
          width: 42,
          height: 42,
          child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  // ── Icono de mensajes con badge de no leídos ──
  Widget _buildMensajesIcon(BuildContext context) {
    if (messageCountNotifier == null) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: messageCountNotifier!,
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
        _menuItem('config', Icons.settings_outlined, 'Configuración'),
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
      case 'config':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SettingsPage()),
        );
        break;
      case 'logout':
        await _confirmarLogout(context);
        break;
    }
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
              onTap:
                  onEstadoTap == null ? null : () => onEstadoTap!(context),
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
                    if (onEstadoTap != null) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.keyboard_arrow_down,
                          color: Colors.white.withOpacity(0.8), size: 18),
                    ],
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

  Widget _buildTitulo() {
    return Text(
      titulo!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );
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
