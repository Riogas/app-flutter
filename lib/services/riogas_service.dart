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

    // Start the retry timer if there is already data in the box
    if (failedRequestsBox.isNotEmpty) {
      // print('📦 failedRequestsBox has existing data. Starting retry timer.');
      await startRetryTimer();
    }
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
    // print('🔍 Opening failedRequestsBox to process pending requests.');
    var failedRequestsBox = await Hive.openBox('failedRequestsBox');

    List<MapEntry<dynamic, Map<String, dynamic>>> pendingRequests =
        failedRequestsBox
            .toMap()
            .entries
            .map((entry) {
              try {
                final map = Map<String, dynamic>.from(entry.value as Map);
                return MapEntry(entry.key, map);
              } catch (error) {
                // print(
                //   '❌ Error converting request with key ${entry.key}: $error',
                // );
                return null;
              }
            })
            .whereType<MapEntry<dynamic, Map<String, dynamic>>>()
            .toList();

    // print('📋 Total pending requests: ${pendingRequests.length}');
    // print('📋 Pending requests: $pendingRequests'); // Debugging print

    for (var entry in pendingRequests) {
      final key = entry.key;
      final request = entry.value;

      try {
        String endpoint = request['endpoint'];
        Map<String, dynamic> payload = Map<String, dynamic>.from(
          request['payload'] as Map,
        );

        // print('🔄 Retrying request for endpoint: $endpoint');
        // print('📦 Payload: $payload');

        var response = await _post(endpoint, payload);
        if (response != null) {
          // print('✅ Request to $endpoint succeeded.');

          if (endpoint == 'FinalizarPedido' &&
              payload.containsKey('PedidoId')) {
            var pedidosBox = await Hive.openBox('pedidosBox');
            int pedidoId = payload['PedidoId'];
            // print('📦 Checking pedidosBox for PedidoId: $pedidoId');
            if (pedidosBox.containsKey(pedidoId)) {
              await pedidosBox.put(pedidoId, 'Procesando');
              // print(
              //   '📦 Pedido $pedidoId updated to "Procesando" in pedidosBox.',
              // );
            } else {
              // print('⚠️ PedidoId $pedidoId not found in pedidosBox.');
            }
          } else {
            // print(
            //   '📨 Executed request for endpoint "$endpoint" without extra logic.',
            // );
          }

          await failedRequestsBox.delete(
            key,
          ); // ✅ Remove successfully processed request
          // print('🗑️ Removed successfully processed request with key $key.');
        } else {
          // print('⚠️ Request to $endpoint failed. Response is null.');
        }
      } catch (e) {
        // print('❌ Exception while retrying request with key $key: $e');
      }
    }

    // print('✅ Finished processing all pending requests.');
  }

  static Future<Map<String, dynamic>?> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      // Procesar el valor de la versión para que solo incluya el número
      if (body.containsKey('version')) {
        body['version'] = body['version'].replaceAll(RegExp(r'[^0-9.]'), '');
      }

      // print('Ejecutando servicio: $endpoint');
      // print('Solicitud (request):');
      // print('URL: $baseUrl$endpoint');
      // print('Headers: $headers');
      // print('Body $endpoint: ${jsonEncode({...body, 'token': token})}');

      final response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
        body: jsonEncode({...body, 'token': token}),
      );

      // print('[$endpoint] Código de respuesta: ${response.statusCode}');
      // print('[$endpoint] Respuesta: ${response.body}');

      if (response.statusCode == 200) {
        _lastErrorTime = null; // Reset error tracking on success
        await _updateConnectionStatus(true); // Update connection status
        return jsonDecode(response.body);
      } else {
        await _saveFailedRequest(endpoint, body); // Save failed request
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
      // print('❌ Error en [$endpoint]: $e');
      if (e is SocketException) {
        // print('⚠️ Error de red detectado: ${e.message}');
      }
      await _saveFailedRequest(endpoint, body); // Save failed request
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
    String usuMobilePassword,
  ) {
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
    String longitud,
  ) {
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
    String longitud,
  ) {
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
    String longitud,
  ) {
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
    String inAux2,
  ) {
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
  ) {
    return _post('RegistrarCoordenadas', {
      'token': token,
      'movil': movil,
      'Latitud': latitud,
      'longitud': longitud,
      'DeviceId': deviceId,
      'FechaHora': fechaHora,
    });
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
}
