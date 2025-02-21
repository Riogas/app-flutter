import 'package:http/http.dart' as http;
import 'dart:convert';

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
      final response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
        body: jsonEncode({...body, 'token': token}),
      );

      print('[$endpoint] Código de respuesta: ${response.statusCode}');
      print('[$endpoint] Respuesta: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('❌ Error en [$endpoint]: $e');
      return null;
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
      String deviceId, String documento) {
    return _post(
        'RegistrarDispositivo', {'DeviceId': deviceId, 'Documento': documento});
  }
}
