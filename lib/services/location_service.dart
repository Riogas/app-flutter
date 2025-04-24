import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/riogas_service.dart';
import 'package:flutter/material.dart';
import '../utils/constantes.dart'; // Import constantes.dart
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  Timer? _timer;
  bool _locationPermissionDenied = false;
  bool _isBackgroundEnabled = false;
  bool _isUpdateEnabled =
      false; // 🔹 Tracks if updates to Firestore are allowed
  int _updateInterval = 30; // Intervalo por defecto en segundos
  final StreamController<LatLng> _locationStreamController =
      StreamController<LatLng>.broadcast();
  StreamSubscription<Position>? _positionStreamSubscription;
  LatLng? _lastPosition;
  double _totalDistance = 0.0;

  /// 🔹 Permite escuchar actualizaciones de ubicación en tiempo real
  Stream<LatLng> get locationStream => _locationStreamController.stream;

  /// 🔹 Inicializa el servicio de ubicación y sincronización
  Future<void> initializeLocationUpdates(BuildContext context) async {
    await _requestIgnoreBatteryOptimizations();
    await _getLocationPermission(context);
    await ensureCorrectLocationPermission(
      context,
    ); // 🔹 Verifica y solicita permiso en background
    await _enableBackgroundExecution();
    _startLocationUpdates();
    await _startLocationAndSyncTimers(); // 🔹 Configura los timers para Firestore y RioGas
  }

  /// 🔹 Solicita ignorar la optimización de batería
  Future<void> _requestIgnoreBatteryOptimizations() async {
    if (Platform.isAndroid) {
      final intent = AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:com.example.MoveIT',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    }
  }

  /// 🔹 Carga el intervalo de actualización desde Hive
  Future<bool> _loadUpdateInterval() async {
    var box = await Hive.openBox('constantBox');
    var sessionBox = await Hive.openBox('sessionBox');
    var escenario = sessionBox.get('escenario');

    var data = box.get('31');

    String? valorEscenarioKey = 'ValorEscenario$escenario';
    String? valorFinal;

    if (data != null) {
      // print("📦 Contenido del documento con ID '31': $data");

      if (data['Estado'] == 'A') {
        _isUpdateEnabled = true; // 🔹 Enable updates
        if (data.containsKey(valorEscenarioKey) &&
            data[valorEscenarioKey] != null) {
          valorFinal = data[valorEscenarioKey]; // Prioritize ValorEscenario
        } else {
          valorFinal = data['Valor']; // Default to Valor
        }
        _updateInterval = _parseUpdateInterval(valorFinal); // Convertir a int
        // print(
        //   "✅ Estado es 'A'. Intervalo de actualización configurado a $_updateInterval segundos.",
        // );
        return true;
      } else {
        _isUpdateEnabled = false; // 🔹 Disable updates
        // print(
        //   "❌ Estado no es 'A'. No se iniciarán las actualizaciones de ubicación.",
        // );
        return false;
      }
    } else {
      _isUpdateEnabled = false; // 🔹 Disable updates
      // print(
      //   "❌ No se encontró el documento con ID '31'. No se iniciarán las actualizaciones de ubicación.",
      // );
      return false;
    }
  }

  int _parseUpdateInterval(dynamic value) {
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  /// 🔹 Manejo de permisos para primer y segundo plano
  Future<void> _getLocationPermission(BuildContext context) async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.whileInUse) {
      _locationPermissionDenied = true;
      var sessionBox = await Hive.openBox('sessionBox');
      await sessionBox.put(
          '_locationPermissionDenied', _locationPermissionDenied);
      print('❌ Permisos de ubicación denegados.');

      // Start a timer to periodically check for location permissions
      Timer.periodic(Duration(seconds: 10), (timer) async {
        LocationPermission updatedPermission =
            await Geolocator.checkPermission();
        if (updatedPermission == LocationPermission.always) {
          _locationPermissionDenied = false;
          await sessionBox.put(
              '_locationPermissionDenied', _locationPermissionDenied);
          print(
              '✅ Permisos de ubicación concedidos. Continuando con el flujo normal.');
          timer.cancel(); // Stop the timer once permissions are granted
          await initializeLocationUpdates(context); // Restart location updates
        } else {
          print('🔄 Verificando permisos de ubicación...');
        }
      });
    } else if (permission == LocationPermission.always) {
      _locationPermissionDenied = false;
      var sessionBox = await Hive.openBox('sessionBox');
      await sessionBox.put(
          '_locationPermissionDenied', _locationPermissionDenied);
      print('✅ Permisos de ubicación concedidos.');
    }

    // 🚀 Android 10+ requiere permiso especial para background
    if (permission != LocationPermission.always) {
      // 🔹 Solicitar nuevamente el permiso si no es "Permitir todo el tiempo"
      LocationPermission backgroundPermission =
          await Geolocator.requestPermission();

      if (backgroundPermission != LocationPermission.always) {
        // print('⚠️ Permiso de ubicación en background denegado.');
        // 🔹 Mostrar diálogo y redirigir a configuración
        bool shouldRedirect = await _showPermissionDialog(context);
        if (shouldRedirect) {
          await openAppSettings();
        }
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
    // print('🔄 hasPermissions antes de inicializar: $hasPermissions');

    if (hasPermissions) {
      try {
        hasPermissions = await FlutterBackground.initialize(
          androidConfig: androidConfig,
        );
        // print('🔄 hasPermissions después de inicializar: $hasPermissions');
      } catch (e) {
        // print('❌ Error al inicializar FlutterBackground: $e');
      }
    }

    if (hasPermissions) {
      try {
        await FlutterBackground.enableBackgroundExecution();
        _isBackgroundEnabled = true;
        // print('✅ Ejecución en segundo plano habilitada.');
      } catch (e) {
        // print('❌ Error al habilitar la ejecución en segundo plano: $e');
      }
    } else {
      // print('❌ No se pudo habilitar la ejecución en segundo plano.');
    }
  }

  /// ✅ **Verifica si el usuario otorgó el permiso "Permitir todo el tiempo"**
  Future<void> ensureCorrectLocationPermission(BuildContext context) async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.whileInUse) {
      // print(
      //   "⚠️ El usuario solo concedió 'Mientras se usa la app'. Solicitando 'Permitir todo el tiempo'...",
      // );

      // 🔹 Muestra un popup antes de redirigir a la configuración
      bool shouldRedirect = await _showPermissionDialog(context);
      if (shouldRedirect) {
        await openAppSettings();
      }
    }
  }

  Future<bool> _showPermissionDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Permiso de ubicación requerido'),
              content: Text.rich(
                TextSpan(
                  text: 'La app ',
                  children: <TextSpan>[
                    TextSpan(
                      text: 'REQUIERE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    TextSpan(
                      text:
                          ' que se habiliten los permisos de acceder a la ubicación TODO EL TIEMPO para poder funcionar, por favor habilítelos.',
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('Cancelar'),
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                ),
                TextButton(
                  child: Text('Continuar'),
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                ),
              ],
            );
          },
        ) ??
        false;
  }

  /// 🔹 Inicia la actualización de ubicación en primer y segundo plano
  void _startLocationUpdates() {
    if (_locationPermissionDenied) return;

    _getAndShowLocation(); // 🔹 Obtener ubicación inmediatamente
    // print(
    //   '📍 Iniciando actualización de coordenadas cada $_updateInterval segundos.',
    // );

    // 🔹 Configura el stream para calcular distancia recorrida en tiempo real
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
    );

    _positionStreamSubscription?.cancel(); // Cancela cualquier stream previo
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {
      LatLng newLocation = LatLng(position.latitude, position.longitude);

      if (_lastPosition != null) {
        double distance = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          newLocation.latitude,
          newLocation.longitude,
        );

        double speed = position.speed; // Get the current speed
        _totalDistance += distance;
        // print(
        //   '📏 Distancia recorrida: $distance mts | Total: $_totalDistance mts',
        // );
        await _updateLocationAndDistanceInHive(
            newLocation, _totalDistance, speed);
      }

      _lastPosition = newLocation;
      _locationStreamController.add(newLocation); // 🔹 Notifica a los listeners
    });

    // 🔹 Mantiene el timer para guardar coordenadas en Firestore
    _timer?.cancel(); // Evita múltiples timers
    _timer = Timer.periodic(Duration(seconds: _updateInterval), (timer) async {
      // print('⏳ Obteniendo nuevas coordenadas para Firestore...');
      await _getAndShowLocation();
    });
  }

  /// 🔹 Obtiene la ubicación actual y la envía al Stream y Firestore
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
        '📍 Nueva ubicación obtenida: Lat ${position.latitude}, Lng ${position.longitude}, Fecha y Hora: ${DateTime.now().toIso8601String()}',
      );

      await _updateCoordinatesInFirestore(position); // 🔹 Actualiza Firestore
      await _updateLocationAndDistanceInHive(
        newLocation,
        _totalDistance,
        position.speed, // Pass the speed
      ); // 🔹 Actualiza Hive
    } catch (e) {
      // print('❌ Error al obtener ubicación: $e');
    }
  }

  /// 🔹 Actualiza la última ubicación y la distancia total en Hive
  Future<void> _updateLocationAndDistanceInHive(
    LatLng newLocation,
    double totalDistance,
    double speed, // Added parameter for speed
  ) async {
    var box = await Hive.openBox('locationBox');

    await box.put('lastLocation', {
      'latitude': newLocation.latitude,
      'longitude': newLocation.longitude,
    });
    await box.put('totalDistance', totalDistance);
    await box.put('lastSpeed', speed); // Store the last speed in Hive

    // print(
    //   '📦 Última ubicación guardada en Hive: Lat ${newLocation.latitude}, Lng ${newLocation.longitude}',
    // );
    // print(
    //   '📦 Distancia total recorrida actualizada: ${totalDistance.toStringAsFixed(2)} mts',
    // );
    // print(
    //   '📦 Última velocidad registrada: ${speed.toStringAsFixed(2)} m/s',
    // );
  }

  Future<Position?> getCurrentLocation() async {
    if (_locationPermissionDenied) return null;

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: true,
      );
      print(
          '📍 Ubicación obtenida: Lat ${position.latitude}, Lng ${position.longitude}');
      return position;
    } catch (e) {
      print('❌ Error al obtener ubicación: $e');
      return null;
    }
  }

  Future<void> _updateCoordinatesInFirestore(Position position) async {
    if (!_isUpdateEnabled) {
      // print('⚠️ Actualización de coordenadas en Firestore deshabilitada.');
      return; // 🔹 Skip updates if not enabled
    }

    var box = await Hive.openBox('sessionBox');
    String? escenario = box.get('escenario');
    String? movil = box.get('movil');

    if (escenario == null || movil == null) {
      // print('❌ No se pudo obtener el escenario o el móvil de Hive.');
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
    await fechaDocRef.set({'fechahoraCreacion': now}, SetOptions(merge: true));

    DocumentReference movilDocRef =
        fechaDocRef.collection('Movil-$movil').doc(horaActual);

    Map<String, dynamic> coordinatesData = {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': now,
    };

    await movilDocRef.set(coordinatesData, SetOptions(merge: true));
    // print('📍 Coordenadas guardadas en Firestore: $coordinatesData');
  }

  /// 🔹 Inicia los timers para sincronización con Firestore y RioGas
  Future<void> _startLocationAndSyncTimers() async {
    // Obtener valores de las constantes
    String? firestoreIntervalValue = await getConstantValue('31');
    String? rioGasIntervalValue = await getConstantValue('30');
    int rioGasInterval = 0;
    int firestoreInterval = 0;

    // print('intervalo firestore  $firestoreIntervalValue');
    // print('intervalo riogas $rioGasIntervalValue');

    // Parsear los intervalos en segundos
    if (firestoreIntervalValue != null) {
      firestoreInterval = _parseUpdateInterval(firestoreIntervalValue);

      // print(
      //   '⏳ Configurando timer para Firestore cada $firestoreInterval segundos.',
      // );
    }

    if (rioGasIntervalValue != null) {
      rioGasInterval = _parseUpdateInterval(rioGasIntervalValue);

      // print('⏳ Configurando timer para RioGas cada $rioGasInterval segundos.');
    }

    if (firestoreInterval == null || firestoreInterval == 0) {
      // print('❌ No se pudo obtener el intervalo de Firestore.');
    } else {
      // Timer para Firestore
      Timer.periodic(Duration(seconds: firestoreInterval), (
        firestoreTimer,
      ) async {
        Position? position = await getCurrentLocation();
        if (position == null) {
          // print('❌ No se pudo obtener la ubicación actual para Firestore.');
          return;
        }

        // print(
        //   '📍 Actualizando Firestore con coordenadas: Lat ${position.latitude}, Lng ${position.longitude}',
        // );
        await _updateCoordinatesInFirestore(position);
      });
    }

    if (rioGasInterval == null || rioGasInterval == 0) {
      // print('❌ No se pudo obtener el intervalo de RioGas.');
    } else {
      // Timer para RioGas
      Timer.periodic(Duration(seconds: rioGasInterval), (rioGasTimer) async {
        Position? position = await getCurrentLocation();
        if (position == null) {
          // print('❌ No se pudo obtener la ubicación actual para RioGas.');
          return;
        }

        var sessionBox = await Hive.openBox('sessionBox');
        String? movil = sessionBox.get('movil');
        String? deviceId = sessionBox.get('deviceId');

        if (movil == null || deviceId == null) {
          // print(
          //   '❌ No se pudo obtener el móvil o el DeviceId de Hive para RioGas.',
          // );
          return;
        }

        String fechaHora = DateTime.now().toUtc().toIso8601String();

        double velocidad = double.parse(
            position.speed.toStringAsFixed(2)); // Ensure speed is rounded
        double distanciaRecorrida =
            _totalDistance; // Use total distance tracked

        // print(
        //   '📍 Enviando coordenadas a RioGas: Lat ${position.latitude}, Lng ${position.longitude}',
        // );
        await RioGasService.registrarCoordenadas(
            int.parse(movil),
            position.latitude.toString(),
            position.longitude.toString(),
            deviceId,
            fechaHora,
            distanciaRecorrida, // Pass total distance
            velocidad // Pass speed (rounded to 2 decimal places)
            );
      });
    }
  }

  /// 🔹 Detiene la actualización de ubicación
  void stopLocationUpdates() {
    _timer?.cancel();
    _positionStreamSubscription?.cancel(); // Cancela el stream de posición
    FlutterBackground.disableBackgroundExecution();
    _isBackgroundEnabled = false;
    // print("⏹️ Se detuvo la actualización de coordenadas.");
  }
}
