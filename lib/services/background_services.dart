import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:hive/hive.dart';
import 'package:geolocator/geolocator.dart';
import 'package:proj4dart/proj4dart.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'dart:isolate';
import 'dart:async';

Future<Map<String, dynamic>> getCurrentCoordinates() async {
  try {
    // Verificar permisos de ubicación
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('Permiso de ubicación denegado por el usuario.');
        // Intentar obtener ubicación aproximada por red
        return await _getCoordinatesByNetwork();
      }
    }
    if (permission == LocationPermission.deniedForever) {
      print('Permiso de ubicación denegado permanentemente.');
      // Intentar obtener ubicación aproximada por red
      return await _getCoordinatesByNetwork();
    }

    // Verificar si el GPS está habilitado
    bool isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationServiceEnabled) {
      print(
          'El GPS está deshabilitado. Intentando obtener ubicación por red...');
      // Intentar obtener ubicación aproximada por red
      return await _getCoordinatesByNetwork();
    }

    // Si hay permisos y GPS, obtener ubicación precisa
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    double latitude = position.latitude;
    double longitude = position.longitude;

    // Proyección UTM (Zona 21S para Uruguay, ajustar según tu zona)
    var srcProj = Projection.get('EPSG:4326'); // WGS84
    var dstProj = Projection.parse(
        '+proj=utm +zone=21 +south +datum=WGS84 +units=m +no_defs');
    if (srcProj != null && dstProj != null) {
      var point = Point(x: longitude, y: latitude);
      var utmPoint = srcProj.transform(dstProj, point);
      double utmX = utmPoint.x;
      double utmY = utmPoint.y;
      print(
          'Coordenadas actuales: lat=$latitude, lon=$longitude, utmX=$utmX, utmY=$utmY');
      return {
        'latitude': latitude,
        'longitude': longitude,
        'utmX': utmX,
        'utmY': utmY,
      };
    } else {
      print('Error en la proyección UTM.');
      return {
        'latitude': latitude,
        'longitude': longitude,
        'utmX': null,
        'utmY': null,
      };
    }
  } catch (e) {
    print('Error al obtener coordenadas: $e');
    return await _getCoordinatesByNetwork();
  }
}

Future<Map<String, dynamic>> _getCoordinatesByNetwork() async {
  try {
    // Usar getLastKnownPosition para obtener la última ubicación conocida (puede ser por red)
    Position? position = await Geolocator.getLastKnownPosition();
    if (position != null) {
      double latitude = position.latitude;
      double longitude = position.longitude;
      var srcProj = Projection.get('EPSG:4326');
      var dstProj = Projection.parse(
          '+proj=utm +zone=21 +south +datum=WGS84 +units=m +no_defs');
      var point = Point(x: longitude, y: latitude);
      if (srcProj != null && dstProj != null) {
        var utmPoint = srcProj.transform(dstProj, point);
        double utmX = utmPoint.x;
        double utmY = utmPoint.y;
        print(
            '[RED] Última ubicación conocida: lat=$latitude, lon=$longitude, utmX=$utmX, utmY=$utmY');
        return {
          'latitude': latitude,
          'longitude': longitude,
          'utmX': utmX,
          'utmY': utmY,
        };
      } else {
        print('Error en la proyección UTM.');
        return {
          'latitude': latitude,
          'longitude': longitude,
          'utmX': null,
          'utmY': null,
        };
      }
    } else {
      // Si no hay última posición conocida, intentar obtener por canal nativo (Kotlin)
      const platform = MethodChannel('network_location');
      try {
        final result = await platform.invokeMethod<Map>('getNetworkLocation');
        if (result != null &&
            result['latitude'] != null &&
            result['longitude'] != null) {
          double latitude = double.parse(result['latitude'].toString());
          double longitude = double.parse(result['longitude'].toString());
          var srcProj = Projection.get('EPSG:4326');
          var dstProj = Projection.parse(
              '+proj=utm +zone=21 +south +datum=WGS84 +units=m +no_defs');
          var point = Point(x: longitude, y: latitude);
          if (srcProj != null && dstProj != null) {
            var utmPoint = srcProj.transform(dstProj, point);
            double utmX = utmPoint.x;
            double utmY = utmPoint.y;
            print(
                '[KOTLIN] Ubicación por red: lat=$latitude, lon=$longitude, utmX=$utmX, utmY=$utmY');
            return {
              'latitude': latitude,
              'longitude': longitude,
              'utmX': utmX,
              'utmY': utmY,
            };
          } else {
            print('Error en la proyección UTM (Kotlin).');
            return {
              'latitude': latitude,
              'longitude': longitude,
              'utmX': null,
              'utmY': null,
            };
          }
        } else {
          print('No se pudo obtener la ubicación por red (Kotlin).');
        }
      } catch (e) {
        print('Error al invocar el canal nativo para ubicación por red: $e');
      }
      return {
        'latitude': null,
        'longitude': null,
        'utmX': null,
        'utmY': null,
      };
    }
  } catch (e) {
    print('Error al obtener coordenadas por red: $e');
    return {
      'latitude': null,
      'longitude': null,
      'utmX': null,
      'utmY': null,
    };
  }
}

/// 👇 ESTA ES LA CLAVE para evitar el error
@pragma('vm:entry-point')
Future<void> backgroundTaskCallback() async {
  // Inicializar plugins en el Isolate
  WidgetsFlutterBinding.ensureInitialized();
  final DateTime now = DateTime.now();
  print('\x1B[32m[AlarmManager] Tarea periódica ejecutada a las $now\x1B[0m');
  print(
      '[AlarmManager] Timer ejecutado a las \x1B[36m${now.toIso8601String()}\x1B[0m');
  await getCurrentCoordinates(); // Obtener coordenadas en cada ejecución
  // Aquí puedes poner la lógica que quieras ejecutar periódicamente
}

Future<void> initializeBackgroundServices() async {
  print('📦 Abriendo caja Hive: sessionBox...');
  var box = await Hive.openBox('sessionBox');

  String? escenario = box.get('escenario')?.toString();
  String? idUsuario = box.get('username');
  String? idTerminal = box.get('deviceId');
  String? nombreUsuario = box.get('NombreUsuario');
  dynamic timerValue = box.get('timerCoordenadas');
  int minutes = 1; // Valor por defecto
  int taskId = 1710; // Usar un ID distinto de 0

  if (timerValue != null) {
    try {
      minutes = int.tryParse(timerValue.toString()) ?? 1;
      if (minutes < 1) minutes = 3;
    } catch (e) {
      print('Error al convertir timerCoordenadas: $e');
    }
  }

  await getCurrentCoordinates(); // Obtener coordenadas al inicio

  await AndroidAlarmManager.initialize();

  await AndroidAlarmManager.periodic(
    Duration(minutes: minutes),
    taskId, // ID único para esta tarea
    backgroundTaskCallback,
    wakeup: true,
    exact: false,
    rescheduleOnReboot: true,
  );
}
