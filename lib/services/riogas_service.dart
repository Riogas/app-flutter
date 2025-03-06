import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:hive/hive.dart';
import '../utils/error_event.dart';

class RioGasService {
  static const String baseUrl = 'https://www.riogas.uy/ica_geos_/appservices/';
  static const Map<String, String> headers = {
    'accept': 'application/json',
    'Content-Type': 'application/json',
    'Cookie': 'GX_CLIENT_ID=3fc38cab-575b-44c7-af56-339c14d664f0',
  };
  static const String token = 'IcA.FwL.1710.!';

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
      String deviceId, String documento, String version) {
    return _post('RegistrarDispositivo',
        {'DeviceId': deviceId, 'Documento': documento, 'version': version});
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
}
