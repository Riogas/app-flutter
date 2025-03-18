import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:hive/hive.dart';
import '../utils/error_event.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart'; // Add this line to import LocationService

class RioGasService {
  static const String baseUrl = 'https://www.riogas.uy/ica_geos_/appservices/';
  static const Map<String, String> headers = {
    'accept': 'application/json',
    'Content-Type': 'application/json',
    'Cookie': 'GX_CLIENT_ID=3fc38cab-575b-44c7-af56-339c14d664f0',
  };
  static const String token = 'IcA.FwL.1710.!';

  static DateTime? _lastErrorTime; // Track the last error time
  static const int errorThresholdMinutes =
      5; // Threshold in minutes - CONSTANTE

  static Future<Map<String, dynamic>?> _post(
      String endpoint, Map<String, dynamic> body) async {
    try {
      // Procesar el valor de la versión para que solo incluya el número
      if (body.containsKey('version')) {
        body['version'] = body['version'].replaceAll(RegExp(r'[^0-9.]'), '');
      }

      print('Ejecutando servicio: $endpoint');
      print('Solicitud (request):');
      print('URL: $baseUrl$endpoint');
      print('Headers: $headers');
      print('Body: ${jsonEncode({...body, 'token': token})}');

      final response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
        body: jsonEncode({...body, 'token': token}),
      );

      print('[$endpoint] Código de respuesta: ${response.statusCode}');
      print('[$endpoint] Respuesta: ${response.body}');

      if (response.statusCode == 200) {
        _lastErrorTime = null; // Reset error tracking on success
        return jsonDecode(response.body);
      } else {
        await _logError('HTTP Error',
            'Código de respuesta: ${response.statusCode}', response.body);
      }
      return null;
    } catch (e) {
      print('❌ Error en [$endpoint]: $e');
      await _logError('Exception', e.toString());
      return null;
    }
  }

  static Future<void> _logError(String type, String message,
      [String? additionalInfo]) async {
    var errorBox = await Hive.openBox<ErrorEvent>('errorBox');
    var errorEvent = ErrorEvent(
      type: type,
      message: message,
      timestamp: DateTime.now(),
      additionalInfo: additionalInfo,
    );
    await errorBox.add(errorEvent);

    // Track persistent errors
    await _handlePersistentErrors();
  }

  static Future<void> _handlePersistentErrors() async {
    DateTime now = DateTime.now();
    if (_lastErrorTime == null) {
      _lastErrorTime = now; // Set the first error time
    } else {
      Duration difference = now.difference(_lastErrorTime!);
      if (difference.inMinutes >= errorThresholdMinutes) {
        var conexionBox = await Hive.openBox('conexionBox');
        await conexionBox.put('conexionRioGas', false);
        await conexionBox.put('conexionRioGasTimestamp', now.toIso8601String());
        print('❌ Persisting error: conexionRioGas set to false.');
      }
    }
  }

  static Future<Map<String, dynamic>?> validarUsuario(
      String usuario, String password, String deviceId) {
    return _post('ValidarUsuario',
        {'usuario': usuario, 'password': password, 'DeviceId': deviceId});
  }

  static Future<Map<String, dynamic>?> validarDispositivo(String deviceId) {
    return _post('ValidarDispositivo', {'DeviceId': deviceId});
  }

  static Future<Map<String, dynamic>?> registrarDispositivo(
      String deviceId,
      String documento,
      String version,
      String marca,
      String modelo,
      String info) {
    return _post('RegistrarDispositivo', {
      'DeviceId': deviceId, 'Documento': documento, 'version': version,
      'Marca': marca, // Update this line
      'Modelo': modelo, // Update this line
      'Info': info // Update this line
    });
  }

  // Nuevo método para validar la versión
  static Future<Map<String, dynamic>?> validarVersion(
      String version, String deviceId) {
    return _post('ValidarVersion', {'version': version, 'DeviceId': deviceId});
  }

  // Nuevo método para obtener datos de la versión
  static Future<Map<String, dynamic>?> DatosVersionActual(
      String version, String deviceId) {
    return _post(
        'DatosVersionActual', {'version': version, 'DeviceId': deviceId});
  }

  static Future<Map<String, dynamic>?> cambioPassword(
      String usuMobileLogin, String usuMobilePassword) {
    return _post('CambioPassword', {
      'UsuMobileLogin': usuMobileLogin,
      'UsuMobilePassword': usuMobilePassword,
    });
  }

  static Future<Map<String, dynamic>?> descargaLecturaMensajes(
      int escenarioId,
      int movilId,
      int messageId,
      String usuario,
      String nroSesion,
      String termMobileEquipo,
      String lectDesc,
      String fechaHoraCmbEst,
      String inAux1,
      String inAux2,
      String latitud,
      String longitud) {
    return _post('DescargaLecturaMensajes', {
      'EscenarioId': escenarioId,
      'MovilId': movilId,
      'MessageId': messageId,
      'usuario': usuario,
      'NroSesion': nroSesion,
      'TermMobileEquipo': termMobileEquipo,
      'LectDesc': lectDesc,
      'FechaHoraCmbEst': fechaHoraCmbEst,
      'INAux1': inAux1,
      'INAux2': inAux2,
      'Latitud': latitud,
      'longitud': longitud,
    });
  }

  static Future<Map<String, dynamic>?> descargaLecturaPedidos(
      int escenarioId,
      int pedidoId,
      String pedidoTpo,
      String usuario,
      String nroSesion,
      String termMobileEquipo,
      String lectDesc,
      String fechaHoraCmbEst,
      String inAux1,
      String inAux2,
      String latitud,
      String longitud) {
    return _post('DescargaLecturaPedidos', {
      'EscenarioId': escenarioId,
      'PedidoId': pedidoId,
      'PedidoTpo': pedidoTpo,
      'usuario': usuario,
      'NroSesion': nroSesion,
      'TermMobileEquipo': termMobileEquipo,
      'LectDesc': lectDesc,
      'FechaHoraCmbEst': fechaHoraCmbEst,
      'INAux1': inAux1,
      'INAux2': inAux2,
      'Latitud': latitud,
      'longitud': longitud,
    });
  }

  static Future<Map<String, dynamic>?> finalizarPedido(
      int escenarioId,
      int pedidoId,
      String pedidoTpo,
      String usuario,
      String nroSesion,
      String termMobileEquipo,
      int estado,
      int subEstado,
      String formaPago,
      String motCancel,
      String fechaHoraCmbEst,
      String inAux1,
      String inAux2,
      String latitud,
      String longitud) {
    return _post('FinalizarPedido', {
      'EscenarioId': escenarioId,
      'PedidoId': pedidoId,
      'PedidoTpo': pedidoTpo,
      'usuario': usuario,
      'NroSesion': nroSesion,
      'TermMobileEquipo': termMobileEquipo,
      'Estado': estado,
      'SubEstado': subEstado,
      'FormaPago': formaPago,
      'MotCancel': motCancel,
      'FechaHoraCmbEst': fechaHoraCmbEst,
      'INAux1': inAux1,
      'INAux2': inAux2,
      'Latitud': latitud,
      'longitud': longitud,
    });
  }

  static Future<Map<String, dynamic>?> actualizarMoviles(
      int escenarioId,
      int movilId,
      String usuario,
      String nroSesion,
      String termMobileEquipo,
      String estadoStr,
      String latitud,
      String longitud,
      String fechaHoraCmbEst,
      String inAux1,
      String inAux2) {
    return _post('ActualizarMoviles', {
      'EscenarioId': escenarioId,
      'MovilId': movilId,
      'usuario': usuario,
      'NroSesion': nroSesion,
      'TermMobileEquipo': termMobileEquipo,
      'EstadoStr': estadoStr,
      'Latitud': latitud,
      'longitud': longitud,
      'FechaHoraCmbEst': fechaHoraCmbEst,
      'INAux1': inAux1,
      'INAux2': inAux2,
    });
  }

  static Future<Map<String, dynamic>?> actualizarMovilesEstado(
      int movilId, int estado) async {
    var box = await Hive.openBox('sessionBox');
    String? escenarioId = box.get('escenario');
    String? usuario = box.get('username');
    String? deviceId = box.get('deviceId');

    if (escenarioId == null || usuario == null || deviceId == null) {
      print('❌ No se pudo obtener el escenario, usuario o deviceId de Hive.');
      return null;
    }

    Position? position = await LocationService().getCurrentLocation();
    if (position == null) {
      print('❌ No se pudo obtener la ubicación actual.');
      return null;
    }

    DateTime now = DateTime.now();
    String fechaHoraCmbEst = now.toIso8601String();

    return _post('ActualizarMoviles', {
      'EscenarioId': int.parse(escenarioId),
      'MovilId': movilId,
      'usuario': usuario,
      'NroSesion': '',
      'TermMobileEquipo': deviceId,
      'EstadoStr': 'ACTIVO',
      'Latitud': position.latitude.toString(),
      'longitud': position.longitude.toString(),
      'FechaHoraCmbEst': fechaHoraCmbEst,
      'INAux1': '',
      'INAux2': '',
    });
  }
}
