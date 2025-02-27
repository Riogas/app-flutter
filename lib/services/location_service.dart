import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

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
    bool intervalLoaded = await _loadUpdateInterval();
    if (!intervalLoaded) {
      print(
          "❌ No se pudo cargar el intervalo de actualización. No se iniciarán las actualizaciones de ubicación.");
      return;
    }
    await _getLocationPermission();
    await ensureCorrectLocationPermission(); // 🔹 Verifica y solicita permiso en background
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
  Future<bool> _loadUpdateInterval() async {
    var box = await Hive.openBox('constantBox');
    var data = box.get('31');

    if (data != null) {
      print("📦 Contenido del documento con ID '31': $data");

      if (data['Estado'] == 'A') {
        _updateInterval =
            _parseUpdateInterval(data['Valor']); // Convertir a int
        print(
            "✅ Estado es 'A'. Intervalo de actualización configurado a $_updateInterval segundos.");
        return true;
      } else {
        print(
            "❌ Estado no es 'A'. No se iniciarán las actualizaciones de ubicación.");
        return false;
      }
    } else {
      print(
          "❌ No se encontró el documento con ID '31'. No se iniciarán las actualizaciones de ubicación.");
      return false;
    }
  }

  int _parseUpdateInterval(dynamic value, {int defaultValue = 30}) {
    if (value is String) {
      return int.tryParse(value) ?? defaultValue;
    }
    return defaultValue;
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

  /// ✅ **Verifica si el usuario otorgó el permiso "Permitir todo el tiempo"**
  Future<void> ensureCorrectLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.whileInUse) {
      print(
          "⚠️ El usuario solo concedió 'Mientras se usa la app'. Solicitando 'Permitir todo el tiempo'...");

      // 🔹 Redirige al usuario a la configuración para que habilite el permiso correcto
      final intent = AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:com.example.appmovil',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
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
      await _updateCoordinatesInFirestore(position);
    } catch (e) {
      print('❌ Error al obtener ubicación: $e');
    }
  }

  Future<void> _updateCoordinatesInFirestore(Position position) async {
    var box = await Hive.openBox('sessionBox');
    String? escenario = box.get('escenario');
    String? movil = box.get('movil');

    if (escenario == null || movil == null) {
      print('❌ No se pudo obtener el escenario o el móvil de Hive.');
      return;
    }

    DateTime now = DateTime.now();
    String fechaActual =
        now.toIso8601String().split('T')[0].replaceAll('-', '');
    String horaActual = now.toIso8601String().split('T')[1].split('.')[0];

    DocumentReference fechaDocRef = FirebaseFirestore.instance
        .collection('CoordenadasMoviles-$escenario')
        .doc(fechaActual);

    // Agregar el campo fechahoraCreacion al documento yyyyMMdd
    await fechaDocRef.set({
      'fechahoraCreacion': now,
    }, SetOptions(merge: true));

    DocumentReference movilDocRef =
        fechaDocRef.collection('Movil-$movil').doc(horaActual);

    Map<String, dynamic> coordinatesData = {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': now,
    };

    await movilDocRef.set(coordinatesData, SetOptions(merge: true));
    print('📍 Coordenadas guardadas en Firestore: $coordinatesData');
  }

  /// 🔹 Detiene la actualización de ubicación
  void stopLocationUpdates() {
    _timer?.cancel();
    FlutterBackground.disableBackgroundExecution();
    _isBackgroundEnabled = false;
    print("⏹️ Se detuvo la actualización de coordenadas.");
  }
}
