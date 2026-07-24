import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/location_service.dart';
import '../services/persistent_stream_manager.dart';
import '../services/riogas_service.dart';
import '../utils/constantes.dart';
import 'v2/v2_header.dart';
import 'v2/v2_theme.dart';

/// 📨 Mensajes de despacho — rediseño 2026 (coherente con Home/Promos/Mapa).
///
/// ⚠️ La lógica de "leído" + envío al endpoint (descargaLecturaMensajes) y el
/// borrado (BORRADO) se preservan EXACTAMENTE del diseño anterior. Solo cambia
/// la presentación. Como los mensajes reales no tienen categoría (todos son de
/// despacho), no hay chips ni filtros; el título/preview se derivan del texto.
class MessagePage extends StatefulWidget {
  @override
  _MessagePageState createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  final PersistentStreamManager _streamManager = PersistentStreamManager();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final LocationService locationService = LocationService();

  List<String> _readMessageIds = [];
  StreamSubscription<ServiceStatus>? _gpsStatusSubscription;
  bool _isLocationServiceEnabled = true;

  // ✅ Flag para prevenir múltiples llamadas simultáneas de lectura
  bool _isMarkingAsRead = false;

  @override
  void initState() {
    super.initState();
    _checkLocationService();
    _listenToMessages();
    _setupFCM();
    _listenToGPSChanges();
    _streamManager.initialize();
  }

  @override
  void dispose() {
    _gpsStatusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkLocationService() async {
    bool isEnabled = await Geolocator.isLocationServiceEnabled();
    if (mounted) setState(() => _isLocationServiceEnabled = isEnabled);
  }

  void _listenToMessages() async {
    try {
      var mensajesBox = await Hive.openBox('mensajesBox');
      _readMessageIds = mensajesBox.keys
          .cast<String>()
          .where((key) => mensajesBox.get(key) != 'Borrado')
          .toList();
    } catch (e) {
      print('❌ [MessagePage] Error in _listenToMessages: $e');
    }
  }

  void _setupFCM() {
    _firebaseMessaging.subscribeToTopic('messages');
  }

  void _listenToGPSChanges() {
    _gpsStatusSubscription =
        Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      if (mounted) {
        setState(
            () => _isLocationServiceEnabled = status == ServiceStatus.enabled);
      }
    });
  }

  // ── Lógica de LECTURA (endpoint) — PRESERVADA del diseño anterior ─────────

  Future<void> _markMessageAsRead(DocumentSnapshot message) async {
    if (_isMarkingAsRead) {
      print("⚠️ [LECTURA] Ya hay una lectura en curso, ignorando...");
      return;
    }

    setState(() => _isMarkingAsRead = true);

    try {
      final String capturedTimestamp = DateTime.now().toUtc().toIso8601String();

      var box = await Hive.openBox('sessionBox');
      String? escenario = box.get('escenario');
      String? movil = box.get('movil');
      String? username = box.get('username');
      String? deviceId = box.get('deviceId');

      if (escenario == null ||
          movil == null ||
          username == null ||
          deviceId == null) {
        print('❌ No se pudo obtener los datos necesarios de Hive.');
        return;
      }

      String latitude = '0.0';
      String longitude = '0.0';
      String utmX = '0.0';
      String utmY = '0.0';

      final locationData = await locationService.getCurrentLocation();
      if (locationData != null) {
        latitude = locationData['latitude'].toString();
        longitude = locationData['longitude'].toString();
        utmX = locationData['utmX'].toString();
        utmY = locationData['utmY'].toString();
      }

      var data = message.data() as Map<String, dynamic>;

      final numericIdMatch = RegExp(r'\d+').firstMatch(message.id);
      if (numericIdMatch == null) {
        print('❌ No se pudo extraer un ID numérico del mensaje: ${message.id}');
        return;
      }
      int messageId = int.parse(numericIdMatch.group(0)!);

      if (data.containsKey('FchHoraLeido')) {
        return;
      }

      var mensajesBox = await Hive.openBox('mensajesBox');
      await mensajesBox.put(message.id, 'Leido');

      var locationBox = await Hive.openBox('locationBox');
      double velocidad = double.parse(
          locationBox.get('lastSpeed', defaultValue: 0.0).toStringAsFixed(2));
      double distanciaRecorrida =
          locationBox.get('totalDistance', defaultValue: 0.0);

      await RioGasService.descargaLecturaMensajes(
          int.parse(escenario),
          int.parse(movil),
          messageId,
          username,
          '',
          deviceId,
          'LECTURA',
          capturedTimestamp,
          '',
          '',
          latitude,
          longitude,
          utmX,
          utmY,
          velocidad,
          distanciaRecorrida);

      if (mounted) {
        setState(() => _readMessageIds.add(message.id));
      }
    } finally {
      if (mounted) {
        setState(() => _isMarkingAsRead = false);
      }
    }
  }

  Future<void> _descargaLecturaMensajeService(
    DocumentSnapshot message, [
    String lectDesc = 'LECTURA',
  ]) async {
    var box = await Hive.openBox('sessionBox');
    String? escenario = box.get('escenario');
    String? movil = box.get('movil');
    String? username = box.get('username');
    String? deviceId = box.get('deviceId');

    if (escenario == null ||
        movil == null ||
        username == null ||
        deviceId == null) {
      print('❌ No se pudo obtener los datos necesarios de Hive.');
      return;
    }

    String latitude = '0.0';
    String longitude = '0.0';
    String utmX = '0.0';
    String utmY = '0.0';

    final locationData = await locationService.getCurrentLocation();
    if (locationData != null) {
      latitude = locationData['latitude'].toString();
      longitude = locationData['longitude'].toString();
      utmX = locationData['utmX'].toString();
      utmY = locationData['utmY'].toString();
    }

    final numericIdMatch = RegExp(r'\d+').firstMatch(message.id);
    if (numericIdMatch == null) {
      print('❌ No se pudo extraer un ID numérico del mensaje: ${message.id}');
      return;
    }
    int messageId = int.parse(numericIdMatch.group(0)!);

    var locationBox = await Hive.openBox('locationBox');
    double velocidad = double.parse(
        locationBox.get('lastSpeed', defaultValue: 0.0).toStringAsFixed(2));
    double distanciaRecorrida =
        locationBox.get('totalDistance', defaultValue: 0.0);

    await RioGasService.descargaLecturaMensajes(
        int.parse(escenario),
        int.parse(movil),
        messageId,
        username,
        '',
        deviceId,
        lectDesc,
        DateTime.now().toUtc().toIso8601String(),
        '',
        '',
        latitude,
        longitude,
        utmX,
        utmY,
        velocidad,
        distanciaRecorrida);
  }

  Future<void> _eliminarMensaje(DocumentSnapshot message) async {
    var box = await Hive.openBox('mensajesBox');
    await box.put(message.id, 'Borrado');
    if (mounted) setState(() {});
    await _descargaLecturaMensajeService(message, 'BORRADO');
  }

  // ── Detalle (bottom sheet) + lógica de leído/borrado preservada ───────────

  Future<void> _openDetail(DocumentSnapshot message) async {
    final data = message.data() as Map<String, dynamic>;
    final fullText = (data['Mensaje'] ?? 'Sin contenido').toString();
    final fecha = data['FchHoraCreado'] is Timestamp
        ? DateFormat('dd/MM/yyyy HH:mm')
            .format((data['FchHoraCreado'] as Timestamp).toDate())
        : '';

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: V2Colors.celesteClaro,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.headset_mic,
                        color: V2Colors.accion, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Despacho',
                        style: TextStyle(
                          color: V2Colors.accion,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      if (fecha.isNotEmpty)
                        Text(
                          fecha,
                          style: const TextStyle(
                            color: V2Colors.textoSecundario,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    fullText,
                    style: const TextStyle(
                      color: V2Colors.textoPrimario,
                      fontSize: 15.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(ctx, 'eliminar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: V2Colors.rojo,
                          side: BorderSide(
                              color: V2Colors.rojo.withOpacity(0.6)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 19),
                        label: const Text('Eliminar'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, 'cerrar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: V2Colors.accion,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Cerrar'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (result == 'eliminar') {
      await _eliminarMensaje(message);
    } else {
      // Cualquier otro cierre → marcar como leído (lógica preservada)
      await _markMessageAsRead(message);
    }
  }

  // ── Llamar a despacho (constante 170) — funcionalidad preservada ──────────
  Future<void> _llamarDespacho() async {
    final phoneNumber = await getConstantValue('170') ?? '';
    if (phoneNumber.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Número de teléfono no disponible.')),
        );
      }
      return;
    }
    final Uri callUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(callUri)) {
      await launchUrl(callUri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo realizar la llamada.')),
      );
    }
  }

  // ── Derivar título + vista previa de un texto sin estructura ──────────────
  ({String titulo, String preview}) _tituloPreview(String texto) {
    final norm = texto.replaceAll('\r', '').trim();
    if (norm.isEmpty) return (titulo: 'Sin contenido', preview: '');

    // 1) Cortar en el primer salto de línea si es "corto" (parece un título)
    final nl = norm.indexOf('\n');
    if (nl > 0 && nl <= 60) {
      return (
        titulo: norm.substring(0, nl).trim(),
        preview: norm.substring(nl + 1).trim(),
      );
    }

    // 2) Cortar en el fin de la primera oración
    final sentence = RegExp(r'^.{0,58}?[\.\!\?…](\s|$)').firstMatch(norm);
    if (sentence != null && sentence.end < norm.length) {
      return (
        titulo: norm.substring(0, sentence.end).trim(),
        preview: norm.substring(sentence.end).trim(),
      );
    }

    // 3) Cortar por longitud
    if (norm.length > 56) {
      return (
        titulo: '${norm.substring(0, 56).trim()}…',
        preview: norm.substring(56).trim(),
      );
    }

    return (titulo: norm, preview: '');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Colors.fondo,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _llamarDespacho,
        backgroundColor: V2Colors.accion,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.headset_mic, size: 20),
        label: const Text('Despacho'),
      ),
      body: Column(
        children: [
          V2Header(
            titulo: 'Mensajes',
            subtitulo: 'Comunicación con despacho y sistema',
            onBack: () => Navigator.of(context).maybePop(),
            showActions: false,
            height: 168,
            bottomSpace: 34,
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              transform: Matrix4.translationValues(0, -22, 0),
              decoration: const BoxDecoration(
                color: V2Colors.fondo,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return ValueListenableBuilder<List<DocumentSnapshot>>(
      valueListenable: _streamManager.mensajesNotifier,
      builder: (context, mensajes, _) {
        return FutureBuilder<Box>(
          future: Hive.openBox('mensajesBox'),
          builder: (context, boxSnapshot) {
            if (!boxSnapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: V2Colors.accion),
              );
            }
            final mensajesBox = boxSnapshot.data!;

            // Ordenar por fecha desc + filtrar borrados
            final visibles = mensajes
                .where((m) => mensajesBox.get(m.id) != 'Borrado')
                .toList()
              ..sort((a, b) {
                final ad = (a.data() as Map)['FchHoraCreado'];
                final bd = (b.data() as Map)['FchHoraCreado'];
                if (ad is Timestamp && bd is Timestamp) {
                  return bd.compareTo(ad);
                }
                return 0;
              });

            if (visibles.isEmpty) return _emptyState();

            final noLeidos = visibles.where((m) {
              final data = m.data() as Map<String, dynamic>;
              return mensajesBox.get(m.id) != 'Leido' &&
                  !data.containsKey('FchHoraLeido');
            }).length;

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
              itemCount: visibles.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return _resumenNoLeidos(noLeidos);
                final doc = visibles[index - 1];
                return _mensajeCard(doc, mensajesBox);
              },
            );
          },
        );
      },
    );
  }

  Widget _resumenNoLeidos(int noLeidos) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.forum_outlined,
              color: V2Colors.textoSecundario, size: 18),
          const SizedBox(width: 8),
          Text(
            noLeidos == 0
                ? 'Sin mensajes nuevos'
                : noLeidos == 1
                    ? '1 mensaje sin leer'
                    : '$noLeidos mensajes sin leer',
            style: const TextStyle(
              color: V2Colors.textoSecundario,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mensajeCard(DocumentSnapshot doc, Box mensajesBox) {
    final data = doc.data() as Map<String, dynamic>;
    final isRead = mensajesBox.get(doc.id) == 'Leido' ||
        data.containsKey('FchHoraLeido');
    final texto = (data['Mensaje'] ?? 'Sin contenido').toString();
    final tp = _tituloPreview(texto);
    final fecha = data['FchHoraCreado'] is Timestamp
        ? DateFormat('dd/MM · HH:mm')
            .format((data['FchHoraCreado'] as Timestamp).toDate())
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey(doc.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(
            color: V2Colors.rojo,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        confirmDismiss: (_) async {
          await _eliminarMensaje(doc);
          return true;
        },
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _openDetail(doc),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: V2Shadows.card,
                border: Border(
                  left: BorderSide(
                    color: isRead ? Colors.transparent : V2Colors.accion,
                    width: 4,
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icono circular de categoría (Despacho)
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: V2Colors.celesteClaro,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.headset_mic,
                        color: V2Colors.accion, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Despacho',
                              style: TextStyle(
                                color: V2Colors.accion,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              fecha,
                              style: const TextStyle(
                                color: V2Colors.textoSecundario,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tp.titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: V2Colors.textoPrimario,
                            fontSize: 15,
                            fontWeight:
                                isRead ? FontWeight.w600 : FontWeight.w800,
                          ),
                        ),
                        if (tp.preview.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            tp.preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: V2Colors.textoSecundario,
                              fontSize: 13,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Punto de no leído + chevron
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!isRead)
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: const BoxDecoration(
                            color: V2Colors.accion,
                            shape: BoxShape.circle,
                          ),
                        ),
                      const Icon(Icons.chevron_right,
                          color: V2Colors.textoSecundario, size: 20),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: V2Colors.celesteClaro,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mark_email_read_outlined,
                  color: V2Colors.accion, size: 48),
            ),
            const SizedBox(height: 20),
            const Text(
              'No tenés mensajes',
              style: TextStyle(
                color: V2Colors.textoPrimario,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cuando recibas novedades de despacho, sistema o\npromociones aparecerán acá.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: V2Colors.textoSecundario,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                _listenToMessages();
                setState(() {});
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: V2Colors.accion,
                side: const BorderSide(color: V2Colors.accion, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              icon: const Icon(Icons.refresh, size: 19),
              label: const Text('Actualizar'),
            ),
          ],
        ),
      ),
    );
  }
}
