import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_background/flutter_background.dart';

class LocationService {
  Timer? _timer;
  bool _locationPermissionDenied = false;
  int _updateInterval = 30; // Intervalo por defecto en segundos

  Future<void> initializeLocationUpdates() async {
    await _loadUpdateInterval();
    await _getLocationPermission();
    await _enableBackgroundExecution();
    _startLocationUpdates();
  }

  Future<void> _loadUpdateInterval() async {
    var box = await Hive.openBox('sessionBox');
    var frecuenciaEnvio = box.get(
      'Frecuencia envio coordenadas a Riogas (segs)',
      defaultValue: {'Valor': 30, 'Estado': 'I'},
    );

    if (frecuenciaEnvio['Estado'] == 'A') {
      _updateInterval = frecuenciaEnvio['Valor'];
    }

    print(
        "🔄 Intervalo de actualización de coordenadas: $_updateInterval segundos");
  }

  Future<void> _getLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _locationPermissionDenied = true;
      print('❌ Permisos de ubicación denegados.');
    }
  }

  Future<void> _enableBackgroundExecution() async {
    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: "Background Location Service",
      notificationText: "Your location is being tracked in the background",
      notificationImportance: AndroidNotificationImportance.max,
    );

    bool hasPermissions = await FlutterBackground.hasPermissions;
    print('🔄 hasPermissions antes de inicializar: $hasPermissions');
    if (!hasPermissions) {
      hasPermissions =
          await FlutterBackground.initialize(androidConfig: androidConfig);
      print('🔄 hasPermissions después de inicializar: $hasPermissions');
    }

    if (hasPermissions) {
      try {
        await FlutterBackground.enableBackgroundExecution();
        print('✅ Ejecución en segundo plano habilitada.');
      } catch (e) {
        print('❌ Error al habilitar la ejecución en segundo plano: $e');
      }
    } else {
      print('❌ No se pudo habilitar la ejecución en segundo plano.');
    }
  }

  void _startLocationUpdates() {
    if (_locationPermissionDenied) return;

    _getAndShowLocation(); // 🔹 Obtener ubicación inmediatamente
    print(
        '📍 Iniciando actualización de coordenadas cada $_updateInterval segundos.');

    _timer = Timer.periodic(
      Duration(seconds: _updateInterval),
      (timer) async {
        print('⏳ Obteniendo nuevas coordenadas...');
        await _getAndShowLocation();
      },
    );
  }

  Future<void> _getAndShowLocation() async {
    if (_locationPermissionDenied) return;

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      print(
          '📍 Nueva ubicación obtenida: Lat ${position.latitude}, Lng ${position.longitude}');
      _updateCoordinatesInFirestore(position);
    } catch (e) {
      print('❌ Error al obtener ubicación: $e');
    }
  }

  Future<void> _updateCoordinatesInFirestore(Position position) async {
    try {
      var box = await Hive.openBox('sessionBox');
      String? movil = box.get('movil');
      String? escenario = box.get('escenario');
      String? idSesion = box.get('idSesion');

      if (movil != null && escenario != null && idSesion != null) {
        await FirebaseFirestore.instance
            .collection('Sesiones-$escenario')
            .doc(idSesion)
            .update({
          'ultUbicacion': GeoPoint(position.latitude, position.longitude),
          'fchUltConexionDisp': Timestamp.now(),
        });

        print("✅ Coordenadas actualizadas en Firestore.");
      }
    } catch (e) {
      print("❌ Error al actualizar coordenadas en Firestore: $e");
    }
  }

  void stopLocationUpdates() {
    _timer?.cancel();
    FlutterBackground.disableBackgroundExecution();
    print("⏹️ Se detuvo la actualización de coordenadas.");
  }
}
