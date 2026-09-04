import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../services/riogas_service.dart';

/// 📄 Reportes de SGM que se abren desde el menú del avatar.
///
/// Los dos son el MISMO servicio con distinta constante de ruta y los mismos
/// parámetros: cambia el objeto GeneXus al que se le pega, y con eso el
/// contenido del PDF.
///
/// * **602** (`ica_geos_/com.icageos.urlhttprpt2sgm`) → visitas / pedidos
///   cumplidos.
/// * **603** (`ica_geos_/com.icageos.urlhttprptsgmpromosapp`) → solo las
///   promociones autorizadas desde la app.

/// Reporte de visitas (pedidos cumplidos). No lo ve el comercio adherido:
/// no hace visitas.
Future<void> abrirReporteVisitas(BuildContext context) => _abrirReporte(
      context,
      constanteRuta: '602',
      nombreArchivo: 'visitas.pdf',
      titulo: 'Reporte de visitas',
    );

/// Reporte de promociones autorizadas desde la app.
Future<void> abrirReportePromos(BuildContext context) => _abrirReporte(
      context,
      constanteRuta: '603',
      nombreArchivo: 'promos.pdf',
      titulo: 'Reporte de promociones',
    );

Future<void> _abrirReporte(
  BuildContext context, {
  required String constanteRuta,
  required String nombreArchivo,
  required String titulo,
}) async {
  final hoy = DateTime.now();
  final fecha = await showDatePicker(
    context: context,
    initialDate: hoy,
    firstDate: DateTime(hoy.year - 2),
    lastDate: hoy,
    helpText: titulo,
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
      escenarioId:
          int.tryParse(escenario.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
      movilId: int.tryParse(movil.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
      constanteRuta: constanteRuta,
      nombreArchivo: nombreArchivo,
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
