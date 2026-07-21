import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'location_service.dart';
import 'riogas_service.dart';

/// 📦 Registro de DESCARGA/LECTURA de pedidos contra el backend.
///
/// Lógica extraída de `PendingOrdersPage` (diseño clásico) para poder
/// reutilizarla desde el diseño nuevo (Home V2) sin duplicarla.
/// El comportamiento es idéntico al original:
/// - Dedupe por Hive `descargaLecturaPedidosBox` (null → DESCARGA → LECTURA)
/// - Gating por constantes 400 (LECTURA) y 402 (DESCARGA)
/// - Fire-and-forget: nunca bloquea la UI
class PedidoLecturaService {
  PedidoLecturaService._();
  static final PedidoLecturaService _instance = PedidoLecturaService._();
  factory PedidoLecturaService() => _instance;

  final LocationService _locationService = LocationService();
  bool _lecturaEnCurso = false;

  Future<Box?> _openBoxSafe(String boxName) async {
    try {
      return await Hive.openBox(boxName);
    } catch (e) {
      print('❌ Error opening Hive box "$boxName": $e');
      return null;
    }
  }

  Future<void> marcarLecturaSiCorresponde({
    required Map<String, dynamic> pedido,
    required int pedidoId,
    BuildContext? context,
  }) async {
    const tag = '📦[LECTURA_ON_TAP_BG]';

    if (_lecturaEnCurso) {
      print('$tag ⏳ Hay otra LECTURA en curso, se omite');
      return; // retorna inmediato, nada bloquea la UI
    }
    _lecturaEnCurso = true;

    // Fire-and-forget: ejecuta en el próximo ciclo del event loop
    // y retornamos sin esperar.
    Future<void>(() async {
      try {
        final Box? box = await _openBoxSafe('descargaLecturaPedidosBox');
        if (box == null) {
          print('$tag ❌ No se pudo abrir "descargaLecturaPedidosBox"');
          return;
        }

        final estadoActual = box.get(pedidoId); // null | DESCARGA | LECTURA
        print('$tag 🔍 Pedido $pedidoId - Estado actual: $estadoActual');

        if (estadoActual == 'DESCARGA') {
          print('$tag 📖 Enviando LECTURA para $pedidoId (BG)...');
          final success = await callDescargaLectura(
            pedido,
            pedidoId,
            lectDesc: 'LECTURA',
            context: context,
          );

          // ✅ Marcar como LECTURA en Hive SIEMPRE, independientemente del resultado HTTP
          await box.put(pedidoId, 'LECTURA');

          if (success) {
            print('$tag ✅ LECTURA enviada y registrada para $pedidoId');
          } else {
            print(
                '$tag ⚠️ LECTURA registrada localmente pero no se envió al servidor (constante 400 deshabilitada o error)');
          }
        } else if (estadoActual == null) {
          // Robustez: si no hubo DESCARGA previa, la hacemos rápido en BG y luego LECTURA
          print(
              '$tag ℹ️ Sin DESCARGA previa. Ejecutando DESCARGA+LECTURA para $pedidoId (BG)...');

          final descargaSuccess = await callDescargaLectura(
            pedido,
            pedidoId,
            lectDesc: 'DESCARGA',
            context: context,
          );

          await box.put(pedidoId, 'DESCARGA');

          if (descargaSuccess) {
            print('$tag ✅ DESCARGA enviada al servidor');
          } else {
            print(
                '$tag ℹ️ DESCARGA registrada localmente pero no se envió al servidor (constante 402 deshabilitada o error)');
          }

          final lecturaSuccess = await callDescargaLectura(
            pedido,
            pedidoId,
            lectDesc: 'LECTURA',
            context: context,
          );

          await box.put(pedidoId, 'LECTURA');

          if (lecturaSuccess) {
            print('$tag ✅ LECTURA enviada al servidor');
          } else {
            print(
                '$tag ℹ️ LECTURA registrada localmente pero no se envió al servidor (constante 400 deshabilitada o error)');
          }

          print('$tag ✅ DESCARGA+LECTURA registradas en Hive para $pedidoId');
        } else {
          print(
              '$tag ⏭️ Pedido $pedidoId ya estaba en LECTURA. No se vuelve a llamar.');
        }
      } catch (e, st) {
        print('$tag ❌ Error en marcarLecturaSiCorresponde($pedidoId): $e');
        print(st);
      } finally {
        _lecturaEnCurso = false;
      }
    });

    // Retorna sin esperar
    print('$tag 🚀 Tarea de lectura lanzada en segundo plano para $pedidoId');
  }

  Future<bool> callDescargaLectura(
    Map<String, dynamic> pedido,
    int pedidoId, {
    required String lectDesc,
    BuildContext? context, // <- Opcional para mostrar mensajes
  }) async {
    try {
      print("🟠 [callDescargaLectura] Iniciando para pedidoId: $pedidoId");

      final String pedidoTpo =
          pedido['Tipo'] == 'Pedidos' ? 'PEDIDOS' : 'SERVICES';

      // ✅ Capturar timestamp AL INICIO para evitar duplicados
      final String fechaHoraCmbEst = DateTime.now().toUtc().toIso8601String();
      print("🕒 [TIMESTAMP] Capturado timestamp único: $fechaHoraCmbEst");

      final box = await Hive.openBox('sessionBox');

      final String? deviceId = box.get('deviceId');
      final String? movilid = box.get('movil');
      final int escenarioId =
          int.tryParse(box.get('escenario')?.toString() ?? '') ?? 0;
      final String? username = box.get('username');

      if ([deviceId, movilid, username].contains(null)) {
        print("❌ Faltan datos en sessionBox (deviceId, movilid o username)");
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error de sesión: faltan datos del usuario.')),
          );
        }
        return false; // ❌ Falló
      }

      String inAux2 = '';
      String latitud = '0.0', longitud = '0.0', utmx = '0.0', utmy = '0.0';

      print("🛰️ Obteniendo ubicación GPS...");
      try {
        final locationData = await _locationService
            .getCurrentLocation()
            .timeout(const Duration(seconds: 5));

        if (locationData != null) {
          latitud = locationData['latitude'].toString();
          longitud = locationData['longitude'].toString();
          utmx = locationData['utmX'].toString();
          utmy = locationData['utmY'].toString();
          print("✅ Ubicación obtenida: $latitud, $longitud");
        } else {
          print("⚠️ No se obtuvo ubicación GPS.");
        }
      } on TimeoutException {
        print("⏰ Timeout al obtener la ubicación GPS.");
      } catch (e) {
        print("❌ Error al obtener ubicación GPS: $e");
      }

      double velocidad = 0.0;
      double distanciaRecorrida = 0.0;

      try {
        final locationBox = await Hive.openBox('locationBox');
        final rawSpeed = locationBox.get('lastSpeed', defaultValue: 0.0);
        final rawDistance = locationBox.get('totalDistance', defaultValue: 0.0);
        velocidad = double.parse(rawSpeed.toStringAsFixed(2));
        distanciaRecorrida = double.parse(rawDistance.toStringAsFixed(6));
      } catch (e) {
        print("❌ Error leyendo datos de velocidad/distancia en Hive: $e");
      }

      // 🆕 GENERAR STRING DE ESTADO DEL MÓVIL PARA INAUX2
      try {
        String appState = "active";
        String notificaciones = "ON";
        String permisos =
            (latitud != '0.0' && longitud != '0.0') ? "FULL" : "DENIED";
        String gpsState =
            (latitud != '0.0' && longitud != '0.0') ? "ON" : "OFF";
        inAux2 =
            "Estado: $appState | Notificaciones: $notificaciones | Permisos: $permisos | GPS: $gpsState | Retry: 0 | Reset: No";
      } catch (e) {
        inAux2 = "Error generando estado";
      }

      print("📤 Enviando datos a RioGasService...");

      // Control separado por tipo de operación:
      // - Constante 400: Controla LECTURAS / Constante 402: DESCARGAS
      final constantId = lectDesc == 'LECTURA' ? '400' : '402';

      final constantBox = await Hive.openBox('constantBox');
      var data = constantBox.get(constantId);
      String llamarws = 'N';
      if (data != null && data['Estado'] == 'A') {
        llamarws = data['Valor'] ?? 'N';
      }

      if (llamarws == 'S') {
        try {
          final sessionBox = await Hive.openBox('sessionBox');
          final lastServiceCheck =
              sessionBox.get('lastServiceCheck', defaultValue: 'NOCHECK');

          print(
              "🔍 Usando NroSesion desde lastServiceCheck: $lastServiceCheck");

          await RioGasService.descargaLecturaPedidos(
            escenarioId,
            pedidoId,
            pedidoTpo,
            username!,
            lastServiceCheck,
            deviceId!,
            lectDesc,
            fechaHoraCmbEst,
            movilid!,
            inAux2,
            latitud,
            longitud,
            utmx,
            utmy,
            velocidad,
            distanciaRecorrida,
          ).timeout(const Duration(seconds: 8));

          print("✅ Petición completada con éxito para pedido $pedidoId");
          return true;
        } on TimeoutException {
          print("⏰ Timeout esperando respuesta de RioGasService");
          if (context != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('La conexión con el servidor ha expirado.')),
            );
          }
          return false;
        } catch (e) {
          print("❌ Error inesperado al llamar a RioGasService: $e");
          if (context != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al enviar datos al servidor.')),
            );
          }
          return false;
        }
      } else {
        print("ℹ️ No se llamará a RioGasService, 'llamarws' es 'N'");
        return false;
      }
    } catch (e, st) {
      print("❌ Excepción general: $e");
      print(st);
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ocurrió un error inesperado.')),
        );
      }
      return false;
    }
  }
}
