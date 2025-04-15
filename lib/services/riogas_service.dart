import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io'; // Import for SocketException
import 'package:hive/hive.dart';
import '../utils/error_event.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart'; // Add this line to import LocationService
import 'dart:async'; // Import for Timer
import '../utils/constantes.dart';
import 'package:url_launcher/url_launcher.dart'; // Add this import for opening URLs
import 'package:path_provider/path_provider.dart'; // Add this import for file handling
import 'package:open_file/open_file.dart'; // Ensure this import is present

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
  static late int retryIntervalSeconds;

  static Future<void> initializeRetryInterval() async {
    String? value = await getConstantValue('110');
    retryIntervalSeconds = int.tryParse(value ?? '0') ?? 0;
  }

  static Timer? _retryTimer;

  static Future<void> startRetryTimer() async {
    // print('🔄 Iniciando el temporizador de reintentos.');
    var failedRequestsBox = await Hive.openBox('failedRequestsBox');
    // print("📦 requestbox values: ${failedRequestsBox.values}");
    if (failedRequestsBox.isNotEmpty) {
      // print('📦 Pending requests found: ${failedRequestsBox.length}');
      //_retryTimer?.cancel(); // Cancel any existing timer
      // print('⏱️ Existing retry timer canceled.');
      // print('⏱️ Setting retry interval to: $retryIntervalSeconds seconds.');
      _retryTimer = Timer.periodic(Duration(seconds: retryIntervalSeconds), (
        timer,
      ) async {
        // print('🔄 Timer triggered. Executing retry timer callback.');
        try {
          await processPendingRequests();
          //_retryTimer = null; // Reset the timer to null after processing
          // print('⏱️ Retry timer reset to null after processing.');
        } catch (e) {
          // print('❌ Error in retry timer callback: $e');
        }
      });
      // print(
      //   '🔄 Retry timer started with interval: $retryIntervalSeconds seconds.',
      // );
    } else {
      // print('⚠️ No pending requests in failedRequestsBox.');
      // print('⚠️ Retry timer will not be started.');
    }
  }

  // Ensure the timer starts at least once during initialization
  static Future<void> initializeService() async {
    await initializeRetryInterval();
    await deleteOldRequests(); // Call the method to delete old requests
    var failedRequestsBox = await Hive.openBox('failedRequestsBox');

    // Listen for changes in the failedRequestsBox
    failedRequestsBox.watch().listen((event) async {
      if (failedRequestsBox.isNotEmpty) {
        // print(
        //   '📦 Detected new data in failedRequestsBox. Starting retry timer.',
        // );
        await startRetryTimer();
      } else {
        // print('📦 failedRequestsBox is empty. No retry timer will be started.');
      }
    });
  }

  static Future<void> _saveFailedRequest(
    String? endpoint,
    Map<String, dynamic>? payload,
  ) async {
    if (endpoint == null || payload == null) {
      // print(
      //   '⚠️ No se puede guardar la solicitud fallida: endpoint o payload es null.',
      // );
      return;
    }
    var failedRequestsBox = await Hive.openBox('failedRequestsBox');

    // Check if the same endpoint + payload already exists
    bool exists = failedRequestsBox.values.any((request) {
      return request['endpoint'] == endpoint &&
          Map<String, dynamic>.from(request['payload'] as Map).toString() ==
              payload.toString();
    });

    if (exists) {
      // print('⚠️ Duplicate request detected. Not saving again: $endpoint');
      return;
    }

    await failedRequestsBox.add({'endpoint': endpoint, 'payload': payload});
    // print('❌ Request saved for retry: $endpoint');
  }

  static Future<void> processPendingRequests() async {
    print('🔄 Starting processPendingRequests...');
    var failedRequestsBox = await Hive.openBox('failedRequestsBox');
    var conexionBox = await Hive.openBox('conexionBox');
    bool isConnected = conexionBox.get('conexionRioGas', defaultValue: false);

    if (!isConnected) {
      print('⚠️ Not connected. Skipping processing.');
      return;
    }

    print('📦 Retrieving pending requests...');
    List<MapEntry<dynamic, Map<String, dynamic>>> pendingRequests =
        failedRequestsBox
            .toMap()
            .entries
            .map((entry) {
              try {
                final map = Map<String, dynamic>.from(entry.value as Map);
                return MapEntry(entry.key, map);
              } catch (error) {
                print('❌ Error parsing request: $error');
                return null;
              }
            })
            .whereType<MapEntry<dynamic, Map<String, dynamic>>>()
            .toList();

    print('📋 Found ${pendingRequests.length} pending requests.');

    for (var entry in pendingRequests) {
      final key = entry.key;
      final request = entry.value;

      try {
        String endpoint = request['endpoint'];

        // Skip processing for the 'RegistrarErrores' endpoint
        if (endpoint == 'RegistrarErrores') {
          print('⚠️ Skipping request to endpoint: $endpoint');
          continue;
        }

        Map<String, dynamic> payload = Map<String, dynamic>.from(
          request['payload'] as Map,
        );

        print(
            '🌐 Sending request to endpoint: $endpoint with payload: $payload');
        var response = await _post(endpoint, payload);

        print('📦 Response: $response Endpoint: $endpoint');

        if (response != null) {
          print('✅ Request to $endpoint processed successfully.');
          if (endpoint == 'FinalizarPedido' &&
              payload.containsKey('PedidoId')) {
            var pedidosBox = await Hive.openBox('pedidosBox');
            int pedidoId = payload['PedidoId'];
            if (pedidosBox.containsKey(pedidoId)) {
              await pedidosBox.put(pedidoId, 'Procesando');
              print('📦 Updated pedidoId $pedidoId to "Procesando".');
            }
          }
          await failedRequestsBox.delete(key);
          print('🗑️ Deleted successfully processed request with key: $key.');
        } else {
          try {
            print('⚠️ Request to $endpoint failed.');
            // ...existing code for handling failed requests...
          } catch (e) {
            print('❌ Error while handling failed request: $e');
          }
        }
      } catch (e) {
        print('❌ Error processing request with key $key: $e');
        if (request['endpoint'] == 'FinalizarPedido' &&
            request['payload'].containsKey('PedidoId')) {
          var pedidosBox = await Hive.openBox('pedidosBox');
          int pedidoId = request['payload']['PedidoId'];
          if (pedidosBox.containsKey(pedidoId)) {
            await pedidosBox.put(pedidoId, 'Enviando');
            print('📦 Updated pedidoId $pedidoId to "Enviando" due to error.');
          }
        }
      }
    }

    print('🔄 Finished processing pending requests.');
  }

  static Future<Map<String, dynamic>?> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      // Process the version value to include only the number
      if (body.containsKey('version')) {
        body['version'] = body['version'].replaceAll(RegExp(r'[^0-9.]'), '');
      }

      if (endpoint == 'RegistrarCoordenadas') {
        /*print('📦 Processing RegistrarCoordenadas...');
        print('📦 RegistrarCoordenadas Body: $body');*/
      }

      if (endpoint == 'RegistrarCoordenadasBatch') {
        // Ensure Latitud, longitud, and FechaHora are inside "data"
        var failedRequestsBox = await Hive.openBox('failedRequestsBox');

        // Filter pending requests for 'RegistrarCoordenadas'
        List<Map<String, dynamic>> pendingRequests = failedRequestsBox.values
            .where((request) => request['endpoint'] == 'RegistrarCoordenadas')
            .map((request) => Map<String, dynamic>.from(request['payload']))
            .toList();

        // Sort by FechaHora to ensure chronological order
        pendingRequests
            .sort((a, b) => a['FechaHora'].compareTo(b['FechaHora']));

        // Keep only the last 30 requests
        if (pendingRequests.length > 30) {
          pendingRequests =
              pendingRequests.sublist(pendingRequests.length - 30);
        }

        // Add the current request to the batch
        pendingRequests.add({
          'Latitud': body['Latitud'],
          'longitud': body['longitud'],
          'FechaHora': body['FechaHora'],
        });

        // Ensure the batch size is still 30
        if (pendingRequests.length > 30) {
          pendingRequests.removeAt(0); // Remove the oldest entry
        }

        // Update the body with the batch data
        body = {
          ...body,
          'data': jsonEncode(pendingRequests),
        };
        body.remove('Latitud');
        body.remove('longitud');
        body.remove('FechaHora');

        // Remove all 'RegistrarCoordenadas' entries from the failedRequestsBox
        final keysToRemove = failedRequestsBox.keys.where((key) {
          var request = failedRequestsBox.get(key);
          return request != null &&
              request['endpoint'] == 'RegistrarCoordenadas';
        }).toList();

        for (var key in keysToRemove) {
          await failedRequestsBox.delete(key);
        }
      }

      print('🌐 Sending request to endpoint: $endpoint with payload: $body');
      final response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
        body: jsonEncode({...body, 'token': token}),
      );

      if (response.statusCode == 200) {
        _lastErrorTime = null; // Reset error tracking on success
        await _updateConnectionStatus(true); // Update connection status
        return jsonDecode(response.body);
      } else {
        if (endpoint != 'RegistrarCoordenadasBatch') {
          await _saveFailedRequest(endpoint, body); // Save failed request
        }
        await _logError(
          'HTTP Error',
          'Código de respuesta: ${response.statusCode}',
          response.body,
          endpoint,
          jsonEncode({...body, 'token': token}),
        );
      }
      return null;
    } catch (e) {
      if (endpoint == 'RegistrarCoordenadas') {
        var failedRequestsBox = await Hive.openBox('failedRequestsBox');
        var existingRequest = failedRequestsBox.values.firstWhere(
          (request) =>
              request['endpoint'] == 'RegistrarCoordenadasBatch' &&
              request['payload']['movil'] == body['movil'] &&
              request['payload']['DeviceId'] == body['DeviceId'],
          orElse: () => null,
        );

        if (existingRequest != null) {
          List<dynamic> data = existingRequest['payload']['data'];
          // Add new entry if it doesn't already exist
          if (!data.any((entry) =>
              entry['Latitud'] == body['Latitud'] &&
              entry['longitud'] == body['longitud'] &&
              entry['FechaHora'] == body['FechaHora'])) {
            if (data.length >= 30) {
              data.removeAt(
                  0); // Remove the oldest entry to maintain a limit of 30
            }
            data.add({
              'Latitud': body['Latitud'],
              'longitud': body['longitud'],
              'FechaHora': body['FechaHora'],
            });
            await failedRequestsBox.put(
                existingRequest['key'], existingRequest);
            print('📝 Updated existing failed request with new data: $data');
          }
        } else {
          // Save a new failed request
          var newRequest = {
            'endpoint': 'RegistrarCoordenadasBatch',
            'payload': {
              'token': body['token'],
              'movil': body['movil'],
              'DeviceId': body['DeviceId'],
              'data': [
                {
                  'Latitud': body['Latitud'],
                  'longitud': body['longitud'],
                  'FechaHora': body['FechaHora'],
                }
              ],
            },
          };
          await failedRequestsBox.add(newRequest);
          print('📝 Saved new failed request: $newRequest');
        }
      } else if (endpoint != 'RegistrarCoordenadasBatch') {
        await _saveFailedRequest(endpoint, body); // Save failed request
      }
      await _logError(
        'Exception',
        e.toString(),
        e is SocketException ? 'Network issue' : null,
        endpoint,
        jsonEncode({...body, 'token': token}),
      );
      return null;
    }
  }

  static Future<void> _updateConnectionStatus(bool isConnected) async {
    var conexionBox = await Hive.openBox('conexionBox');
    DateTime now = DateTime.now();

    if (isConnected) {
      await conexionBox.put('conexionRioGas', true);
      await conexionBox.put('conexionRioGasTimestamp', now.toIso8601String());
      // print('✅ Connection successful: conexionRioGas set to true.');
    } else {
      await conexionBox.put('conexionRioGas', false);
      // print('❌ Connection failed: conexionRioGas set to false.');
    }
  }

  static Future<void> _logError(
    String type,
    String message, [
    String? additionalInfo,
    String? endpoint,
    String? payload,
  ]) async {
    var errorBox = await Hive.openBox<ErrorEvent>('errorBox');
    var errorEvent = ErrorEvent(
      type: type,
      message: message,
      timestamp: DateTime.now(),
      additionalInfo: additionalInfo,
      endpoint: endpoint ?? 'Unknown endpoint',
      payload: payload ?? 'No payload',
    );
    await errorBox.add(errorEvent);
    // print(
    //   '📋 Error logged: ${errorEvent.toString()}',
    // ); // Log full details of errorEvent

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
        await _updateConnectionStatus(
          false,
        ); // Update connection status on persistent error
      }
    }
  }

  static Future<Map<String, dynamic>?> validarUsuario(
    String usuario,
    String password,
    String deviceId,
  ) {
    return _post('ValidarUsuario', {
      'usuario': usuario,
      'password': password,
      'DeviceId': deviceId,
    });
  }

  static Future<Map<String, dynamic>?> validarDispositivo(String deviceId) {
    return _post('ValidarDispositivo', {'DeviceId': deviceId});
  }

  static Future<Map<String, dynamic>?> registrarDispositivo(
    String deviceId,
    String documento,
    String version,
    String number,
    String marca,
    String modelo,
    String info,
  ) {
    return _post('RegistrarDispositivo', {
      'DeviceId': deviceId,
      'Documento': documento,
      'version': version,
      'numero': number,
      'Marca': marca,
      'Modelo': modelo,
      'Info': info,
    });
  }

  // Nuevo método para validar la versión
  static Future<Map<String, dynamic>?> validarVersion(
    String version,
    String deviceId,
  ) {
    return _post('ValidarVersion', {'version': version, 'DeviceId': deviceId});
  }

  // Nuevo método para obtener datos de la versión
  static Future<Map<String, dynamic>?> DatosVersionActual(
    String version,
    String deviceId,
  ) {
    return _post('DatosVersionActual', {
      'version': version,
      'DeviceId': deviceId,
    });
  }

  static Future<Map<String, dynamic>?> cambioPassword(
    String usuMobileLogin,
    String currentPassword,
    String newPassword,
  ) {
    return _post('CambioPassword', {
      'UsuMobileLogin': usuMobileLogin,
      'CurrentPassword': currentPassword,
      'UsuMobilePassword': newPassword,
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
      String longitud,
      double velocidad, // Added parameter
      double distanciaRecorrida // Added parameter
      ) {
    velocidad = double.parse(velocidad.toStringAsFixed(2));
    distanciaRecorrida = double.parse(distanciaRecorrida.toStringAsFixed(2));
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
      'Velocidad': velocidad, // Added to body
      'DistanciaRecorrida': distanciaRecorrida // Added to body
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
      String longitud,
      double velocidad, // Added parameter
      double distanciaRecorrida // Added parameter
      ) {
    velocidad = double.parse(velocidad.toStringAsFixed(2));
    distanciaRecorrida = double.parse(distanciaRecorrida.toStringAsFixed(2));
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
      'Velocidad': velocidad, // Added to body
      'DistanciaRecorrida': distanciaRecorrida // Added to body
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
      String longitud,
      double velocidad, // Added parameter
      double distanciaRecorrida // Added parameter
      ) {
    velocidad = double.parse(velocidad.toStringAsFixed(2));
    distanciaRecorrida = double.parse(distanciaRecorrida.toStringAsFixed(2));
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
      'Velocidad': velocidad, // Added to body
      'DistanciaRecorrida': distanciaRecorrida // Added to body
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
      String inAux2,
      double velocidad, // Added parameter
      double distanciaRecorrida // Added parameter
      ) {
    velocidad = double.parse(velocidad.toStringAsFixed(2));
    distanciaRecorrida = double.parse(distanciaRecorrida.toStringAsFixed(2));
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
      'Velocidad': velocidad, // Added to body
      'DistanciaRecorrida': distanciaRecorrida // Added to body
    });
  }

  static Future<Map<String, dynamic>?> actualizarMovilesEstado(
    int movilId,
    int estado,
  ) async {
    var box = await Hive.openBox('sessionBox');
    String? escenarioId = box.get('escenario');
    String? usuario = box.get('username');
    String? deviceId = box.get('deviceId');

    if (escenarioId == null || usuario == null || deviceId == null) {
      // print('❌ No se pudo obtener el escenario, usuario o deviceId de Hive.');
      return null;
    }

    Position? position = await LocationService().getCurrentLocation();
    if (position == null) {
      // print('❌ No se pudo obtener la ubicación actual.');
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

  static Future<Map<String, dynamic>?> enviarOTP(
    int nroTelefono,
    int codigoOTP,
    String hash,
  ) {
    return _post('EnviarOTP', {
      'token': token,
      'nroTelefono': nroTelefono,
      'codigoOTP': codigoOTP,
      'hash': hash,
    });
  }

  static Future<Map<String, dynamic>?> registrarCoordenadas(
      int movil,
      String latitud,
      String longitud,
      String deviceId,
      String fechaHora,
      double distanciaRecorrida, // Add distance parameter
      double velocidad // Add speed parameter
      ) async {
    velocidad = double.parse(velocidad.toStringAsFixed(2));
    distanciaRecorrida = double.parse(distanciaRecorrida.toStringAsFixed(2));
    try {
      var box = await Hive.openBox('sessionBox');
      String? escenarioId = box.get('escenario');
      String? username = box.get('username');
      int? escenarioIdInt =
          escenarioId != null ? int.tryParse(escenarioId) : null;
      if (escenarioIdInt == null) {
        throw Exception('Invalid escenarioId: $escenarioId');
      }
      // Use the specified structure for the REST service request
      return await _post('RegistrarCoordenadas', {
        'token': token,
        'movil': movil,
        'Latitud': latitud,
        'longitud': longitud,
        'DeviceId': deviceId,
        'FechaHora': fechaHora,
        'DistanciaRecorrida': distanciaRecorrida, // Pass distance to service
        'Velocidad': velocidad, // Pass speed to service
        'EscenarioId': escenarioIdInt,
        'usuario': username
      });
    } catch (e) {
      // Save the failed request in the specified Hive structure
      var failedRequestsBox = await Hive.openBox('failedRequestsBox');
      var existingRequest = failedRequestsBox.values.firstWhere(
        (request) =>
            request['endpoint'] == 'RegistrarCoordenadasBatch' &&
            request['payload']['movil'] == movil &&
            request['payload']['DeviceId'] == deviceId,
        orElse: () => null,
      );

      if (existingRequest != null) {
        // Add new data to the existing collection if it's not already present
        List<dynamic> data = existingRequest['payload']['data'];
        if (!data.any((entry) =>
            entry['Latitud'] == latitud && entry['longitud'] == longitud)) {
          if (data.length >= 30) {
            data.removeAt(
                0); // Remove the oldest entry to maintain a limit of 30
          }
          data.add({
            'Latitud': latitud,
            'longitud': longitud,
            'FechaHora': fechaHora,
            'DistanciaRecorrida': distanciaRecorrida, // Add distance to batch
            'Velocidad': velocidad // Add speed to batch
          });
          await failedRequestsBox.put(existingRequest['key'], existingRequest);
          print('📝 Updated existing failed request: $existingRequest');
        }
      } else {
        // Save a new failed request
        var newRequest = {
          'endpoint': 'RegistrarCoordenadasBatch',
          'payload': {
            'token': token,
            'movil': movil,
            'DeviceId': deviceId,
            'data': [
              {
                'Latitud': latitud,
                'longitud': longitud,
                'FechaHora': fechaHora,
                'DistanciaRecorrida': distanciaRecorrida, // Add distance
                'Velocidad': velocidad // Add speed
              }
            ],
          },
        };
        await failedRequestsBox.add(newRequest);
        print('📝 Saved new failed request: $newRequest');
      }
      return null;
    }
  }

  static Future<void> downloadAndOpenPDF({
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minutes,
    required int seconds,
    required String usuMobileLogin,
    required String termMobileEquipo,
    required int agenciaId,
    required int escenarioId,
    required int movilId,
  }) async {
    // print('📋 Parameters:');
    // print('Year: $year, Month: $month, Day: $day');
    // print('Hour: $hour, Minutes: $minutes, Seconds: $seconds');
    // print(
    //   'UsuMobileLogin: $usuMobileLogin, TermMobileEquipo: $termMobileEquipo',
    // );
    // print('AgenciaId: $agenciaId, EscenarioId: $escenarioId');
    // print('MovilId: $movilId');
    final url =
        'https://www.riogas.uy/ica_geos_/com.icageos.urlhttprpt2?Year=$year&Month=$month&Day=$day&Hour=$hour&Minutes=$minutes&Seconds=$seconds&UsuMobileLogin=$usuMobileLogin&TermMobileEquipo=$termMobileEquipo&AgenciaId=$agenciaId&EscenarioId=$escenarioId&Movid=$movilId';

    try {
      // print('🌐 Downloading PDF from: $url');
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/report.pdf';
        final file = File(filePath);

        await file.writeAsBytes(response.bodyBytes);
        // print('✅ PDF downloaded to: $filePath');

        final result = await OpenFile.open(filePath);
        // print('📂 Opened PDF with result: $result');
      } else {
        // print('❌ Failed to download PDF. Status code: ${response.statusCode}');
      }
    } catch (e) {
      // print('❌ Error downloading or opening PDF: $e');
    }
  }

  static Future<void> deleteOldRequests() async {
    // print('🗑️ Checking for old requests to delete.');
    var failedRequestsBox = await Hive.openBox('failedRequestsBox');

    // Check if the box contains more than 500 records
    if (failedRequestsBox.length > 500) {
      // print('⚠️ More than 500 records found. Clearing the box.');
      await failedRequestsBox.clear(); // Clear all records
      // print('✅ All records cleared from failedRequestsBox.');
      return;
    }

    DateTime today = DateTime.now();

    List<dynamic> keysToDelete = failedRequestsBox.keys.where((key) {
      var request = failedRequestsBox.get(key);
      if (request != null && request is Map) {
        DateTime? timestamp = DateTime.tryParse(request['timestamp'] ?? '');
        if (timestamp != null) {
          return timestamp.isBefore(
            DateTime(today.year, today.month, today.day),
          );
        }
      }
      return false;
    }).toList();

    for (var key in keysToDelete) {
      await failedRequestsBox.delete(key);
      // print('🗑️ Deleted old request with key: $key');
    }

    // print('✅ Finished deleting old requests.');
  }

  static Future<void> registrarErrores() async {
    var errorBox = await Hive.openBox('errorBox');

    String? constantValue = await getConstantValue('200');
    if (constantValue != null) {
      return;
    }
    // Check if there are errors without the "enviadoARioGas" mark
    List<dynamic> errorsToSend = errorBox.keys.where((key) {
      var error = errorBox.get(key);
      return error != null && error is Map && error['enviadoARioGas'] != true;
    }).toList();

    if (errorsToSend.isEmpty) {
      print('⚠️ No errors to send. Waiting for new errors.');
      return;
    }

    for (var key in errorsToSend) {
      var error = errorBox.get(key);
      if (error != null && error is Map) {
        try {
          // Clean additionalInfo by removing quotes
          if (error['additionalInfo'] != null) {
            error['additionalInfo'] =
                error['additionalInfo'].replaceAll('"', '').replaceAll("'", '');
          }

          // Prepare the payload
          Map<String, dynamic> payload = {
            'token': token,
            'movil': error['movil'] ?? 0,
            'DeviceId': error['DeviceId'] ?? '',
            'usuario': error['usuario'] ?? '',
            'data': jsonEncode(error),
          };

          // Send the error to RioGas
          var response = await _post('RegistrarErrores', payload);

          if (response != null) {
            print('✅ Error sent successfully to RioGas: $key');
            // Mark the error as sent
            error['enviadoARioGas'] = true;
            await errorBox.put(key, error);
          } else {
            print('❌ Failed to send error to RioGas: $key');
          }
        } catch (e) {
          print('❌ Error while sending error to RioGas: $e');
        }
      }
    }

    // Listen for new errors being added to the box
    errorBox.watch().listen((event) async {
      String? constantValue = await getConstantValue('200');
      if (constantValue != null) {
        var newErrorsToSend = errorBox.keys.where((key) {
          var error = errorBox.get(key);
          return error != null &&
              error is Map &&
              error['enviadoARioGas'] != true;
        }).toList();

        if (newErrorsToSend.isNotEmpty) {
          print('📦 New errors detected. Sending to RioGas.');
          await registrarErrores();
        }
      }
    });
  }

  static Future<void> registrarUltLog(
      int movil, String deviceId, String usuario) async {
    try {
      // Prepare the payload
      Map<String, dynamic> payload = {
        'token': token,
        'movil': movil,
        'DeviceId': deviceId,
        'usuario': usuario,
      };

      // Send the request to RioGas
      var response = await _post('RegistrarUltLog', payload);

      if (response != null) {
        print('✅ Último log registrado exitosamente en RioGas.');
      } else {
        print('❌ Falló el registro del último log en RioGas.');
      }
    } catch (e) {
      print('❌ Error al registrar el último log en RioGas: $e');
    }
  }

  static Future<void> monitorAndSendErrors() async {
    var errorBox = await Hive.openBox<ErrorEvent>('errorBox');
    var conexionBox = await Hive.openBox('conexionBox');

    // Monitorear constantemente los errores
    Timer.periodic(Duration(seconds: 10), (timer) async {
      bool isConnected = conexionBox.get('conexionRioGas', defaultValue: false);

      if (!isConnected) {
        print('⚠️ No hay conectividad con RioGas. Esperando conexión...');
        return;
      }

      // Filtrar errores que no han sido enviados
      List<dynamic> errorsToSend = errorBox.keys.where((key) {
        var error = errorBox.get(key);
        return error != null &&
            error is ErrorEvent &&
            error.additionalInfo != 'enviadoARioGas';
      }).toList();

      if (errorsToSend.isEmpty) {
        print('⚠️ No hay errores pendientes para enviar.');
        return;
      }

      for (var key in errorsToSend) {
        var error = errorBox.get(key);
        if (error != null && error is ErrorEvent) {
          try {
            var sessionBox = await Hive.openBox('sessionBox');
            // Preparar el payload
            Map<String, dynamic> payload = {
              'token': token,
              'type': error.type,
              'message': error.message,
              'timestamp': error.timestamp.toIso8601String(),
              'additionalInfo': error.additionalInfo,
              'endpoint': error.endpoint,
              'payload': error.payload,
              'username': sessionBox.get('username'),
              'DeviceId': sessionBox.get('deviceId'),
              'movil': sessionBox.get('movil'),
            };

            // Enviar el error a RioGas
            var response = await _post('RegistrarErrores', payload);

            if (response != null && response['ok'] == 0) {
              print('✅ Error enviado exitosamente a RioGas: $key');
              // Marcar el error como enviado
              var updatedError = ErrorEvent(
                type: error.type,
                message: error.message,
                timestamp: error.timestamp,
                additionalInfo: 'enviadoARioGas',
                endpoint: error.endpoint,
                payload: error.payload,
              );
              await errorBox.put(key, updatedError);
            } else {
              print('❌ Falló el envío del error a RioGas: $key');
              timer.cancel(); // Cancelar el timer en caso de error
              Future.delayed(Duration(minutes: 30), () {
                monitorAndSendErrors(); // Reintentar después de 30 minutos
              });
              return;
            }
          } catch (e) {
            print('❌ Error al enviar el error a RioGas: $e');
            timer.cancel(); // Cancelar el timer en caso de error
            Future.delayed(Duration(minutes: 30), () {
              monitorAndSendErrors(); // Reintentar después de 30 minutos
            });
            return;
          }
        }
      }
    });
  }

  static Future<Map<String, dynamic>?> registrarCierre(
      int movil,
      String deviceId,
      String usuario,
      String fechaHora,
      String tipoCierre) async {
    return _post('RegistrarCierre', {
      'token': token,
      'movil': movil,
      'DeviceId': deviceId,
      'usuario': usuario,
      'TipoCierre': tipoCierre,
      'FechaHora': fechaHora,
    });
  }
}
