import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'dart:io';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  Timer? _timer;
  bool _locationPermissionDenied = false;
  bool _isBackgroundEnabled = false;
  int _updateInterval = 30; // Intervalo por defecto en segundos
  final StreamController<LatLng> _locationStreamController =
      StreamController<LatLng>.broadcast();

  /// 🔹 Permite escuchar actualizaciones de ubicación en tiempo real
  Stream<LatLng> get locationStream => _locationStreamController.stream;

  /// 🔹 Inicializa el servicio de ubicación en primer y segundo plano
  Future<void> initializeLocationUpdates() async {
    await _requestIgnoreBatteryOptimizations();
    await _loadUpdateInterval();
    await _getLocationPermission();
    await _enableBackgroundExecution();
    _startLocationUpdates();
  }

  /// 🔹 Solicita ignorar la optimización de batería
  Future<void> _requestIgnoreBatteryOptimizations() async {
    if (Platform.isAndroid) {
      final intent = AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:com.example.appmovil',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    }
  }

  /// 🔹 Carga el intervalo de actualización desde Hive
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

  /// 🔹 Manejo de permisos para primer y segundo plano
  Future<void> _getLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _locationPermissionDenied = true;
      print('❌ Permisos de ubicación denegados.');
      return;
    }

    // 🚀 Android 10+ requiere permiso especial para background
    if (permission == LocationPermission.whileInUse) {
      LocationPermission backgroundPermission =
          await Geolocator.requestPermission();

      if (backgroundPermission != LocationPermission.always) {
        print('⚠️ Permiso de ubicación en background denegado.');
      }
    }
  }

  /// 🔹 Habilita la ejecución en segundo plano
  Future<void> _enableBackgroundExecution() async {
    if (_isBackgroundEnabled) return;

    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: "Background Location Service",
      notificationText: "Tu ubicación está siendo rastreada",
      notificationImportance: AndroidNotificationImportance.max,
    );

    bool hasPermissions = await FlutterBackground.hasPermissions;
    print('🔄 hasPermissions antes de inicializar: $hasPermissions');

    if (hasPermissions) {
      try {
        hasPermissions =
            await FlutterBackground.initialize(androidConfig: androidConfig);
        print('🔄 hasPermissions después de inicializar: $hasPermissions');
      } catch (e) {
        print('❌ Error al inicializar FlutterBackground: $e');
      }
    }

    if (hasPermissions) {
      try {
        await FlutterBackground.enableBackgroundExecution();
        _isBackgroundEnabled = true;
        print('✅ Ejecución en segundo plano habilitada.');
      } catch (e) {
        print('❌ Error al habilitar la ejecución en segundo plano: $e');
      }
    } else {
      print('❌ No se pudo habilitar la ejecución en segundo plano.');
    }
  }

  /// 🔹 Inicia la actualización de ubicación en primer y segundo plano
  void _startLocationUpdates() {
    if (_locationPermissionDenied) return;

    _getAndShowLocation(); // 🔹 Obtener ubicación inmediatamente
    print(
        '📍 Iniciando actualización de coordenadas cada $_updateInterval segundos.');

    _timer?.cancel(); // Evita múltiples timers
    _timer = Timer.periodic(
      Duration(seconds: _updateInterval),
      (timer) async {
        print('⏳ Obteniendo nuevas coordenadas...');
        await _getAndShowLocation();
      },
    );
  }

  /// 🔹 Obtiene la ubicación actual y la envía al Stream
  Future<void> _getAndShowLocation() async {
    if (_locationPermissionDenied) return;

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager:
            true, // 🔹 Usa el Location Manager de Android
      );

      LatLng newLocation = LatLng(position.latitude, position.longitude);
      _locationStreamController.add(newLocation); // 🔹 Notifica a los listeners

      print(
          '📍 Nueva ubicación obtenida: Lat ${position.latitude}, Lng ${position.longitude}');
    } catch (e) {
      print('❌ Error al obtener ubicación: $e');
    }
  }

  /// 🔹 Detiene la actualización de ubicación
  void stopLocationUpdates() {
    _timer?.cancel();
    FlutterBackground.disableBackgroundExecution();
    _isBackgroundEnabled = false;
    print("⏹️ Se detuvo la actualización de coordenadas.");
  }
}
