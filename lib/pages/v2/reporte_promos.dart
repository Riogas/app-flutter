import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../services/riogas_service.dart';

/// 📄 Reporte de promociones autorizadas desde la app.
///
/// Es el mismo servicio de SGM que el "Reporte de visitas" de Configuración
/// (mismos parámetros, mismo PDF), pero apuntando a la **constante 603**
/// (`ica_geos_/com.icageos.urlhttprptsgmpromosapp`) en vez de la 602: ese
/// servicio devuelve SOLO las promociones.
Future<void> abrirReportePromos(BuildContext context) async {
  final hoy = DateTime.now();
  final fecha = await showDatePicker(
    context: context,
    initialDate: hoy,
    firstDate: DateTime(hoy.year - 2),
    lastDate: hoy,
    helpText: 'Reporte de promociones',
    cancelText: 'Cancelar',
    confirmText: 'Ver reporte',
  );
  if (fecha == null || !context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  String? error;
  try {
    final box = await Hive.openBox('sessionBox');
    final escenario = box.get('escenario', defaultValue: '0').toString();
    final movil = box.get('movil', defaultValue: '0').toString();

    error = await RioGasService.downloadAndOpenPDF(
      year: fecha.year,
      month: fecha.month,
      day: fecha.day,
      hour: 0,
      minutes: 0,
      seconds: 0,
      usuMobileLogin: box.get('username', defaultValue: '').toString(),
      termMobileEquipo: box.get('deviceId', defaultValue: '').toString(),
      agenciaId: 0,
      // El móvil llega como texto y a veces con el prefijo del documento de
      // Firestore ("Moviles-336"): se queda con los dígitos.
      escenarioId: int.tryParse(escenario.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
      movilId: int.tryParse(movil.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
      constanteRuta: '603',
      nombreArchivo: 'promos.pdf',
    );
  } catch (e) {
    error = 'No se pudo generar el reporte: $e';
  }

  if (!context.mounted) return;
  Navigator.of(context).pop(); // cierra el indicador
  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}
