import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';

class SessionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = Uuid();
  final Battery _battery = Battery();

  Future<void> saveSession({
    required String idUsuario,
    required String nomUsuario,
    required LatLng primeraUbicacion,
    required String versionApp,
  }) async {
    var box = await Hive.openBox('sessionBox');

    // ✅ Asegurar valores NO NULOS
    String escenarioId = box.get('escenario') ?? '0';
    String movil = box.get('movil') ?? 'Desconocido';
    String idSesion = _uuid.v4();
    String idTerminal = box.get('deviceId') ?? 'UnknownDevice';
    String infoDispositivo = await _getDeviceInfo();
    String nombreUsuario = (box.get('NombreUsuario') ?? 'Sin Nombre').trim();
    String versionAndroid = await _getAndroidVersion();
    int nivelBateria = await _getBatteryLevel();
    bool gpsActivado = await _isGpsEnabled();

    // ✅ Evitar error con valores Timestamp (Firebase no soporta Timestamp en Hive)
    DateTime now = DateTime.now();
    Timestamp fchHoraExpira = Timestamp.fromDate(now.add(Duration(hours: 8)));
    Timestamp fchHoraInicio = Timestamp.fromDate(now);
    Timestamp fchUltConexionDisp = Timestamp.fromDate(now);

    int distanciaRecorridaMts = 0;
    String estado = 'Activa';
    int tiempoLogueoMins = 0;

    // ✅ Asegurar formato de fecha y hora
    String fechaActual =
        now.toIso8601String().split('T')[0].replaceAll('-', '');
    String horaActual = now.toIso8601String().split('T')[1].split('.')[0];

    // 🔹 Referencias en Firestore
    DocumentReference fechaDocRef =
        _firestore.collection('Sesiones-$escenarioId').doc(fechaActual);
    DocumentReference sessionDocRef =
        fechaDocRef.collection('Movil-$movil').doc(horaActual);
    DocumentReference ultimaDocRef =
        fechaDocRef.collection('Movil-$movil').doc('activo');

    Map<String, dynamic> sessionData = {
      'distanciaRecorridaMts': distanciaRecorridaMts,
      'estado': estado,
      'fchHoraExpira': fchHoraExpira,
      'fchHoraInicio': fchHoraInicio,
      'fchUltConexionDisp': fchUltConexionDisp,
      'idSesion': idSesion,
      'idTerminal': idTerminal,
      'idUsuario': idUsuario,
      'infoDispositivo': infoDispositivo,
      'nomUsuario': nombreUsuario,
      'movil': movil,
      'primeraUbicacion':
          GeoPoint(primeraUbicacion.latitude, primeraUbicacion.longitude),
      'tiempoLogueoMins': tiempoLogueoMins,
      'ultUbicacion':
          GeoPoint(primeraUbicacion.latitude, primeraUbicacion.longitude),
      'versionApp': versionApp,
      'versionAndroid': versionAndroid,
      'nivelBateria': nivelBateria,
      'gpsActivado': gpsActivado,
    };

    print('Guardando sesión en Firestore con los siguientes datos:');
    print(sessionData);

    try {
      // ✅ Asegurar que el documento padre (fecha) tenga un campo para ser reconocido
      await fechaDocRef.set({'FchHoraCreacion': now}, SetOptions(merge: true));
      print('Documento padre asegurado en Firestore con FchHoraCreacion.');

      // ✅ Guardar la sesión actual
      await sessionDocRef.set(sessionData);
      print('Sesión guardada correctamente en Firestore.');

      // ✅ Verificar si existe un documento "activo"
      DocumentSnapshot activeDocSnapshot = await ultimaDocRef.get();
      if (activeDocSnapshot.exists) {
        // 🔹 Hacer una copia del documento "activo" con el nombre basado en la hora actual
        DocumentReference backupDocRef =
            fechaDocRef.collection('Movil-$movil').doc(horaActual);
        await backupDocRef
            .set(activeDocSnapshot.data() as Map<String, dynamic>);
        print('Documento "activo" copiado a $horaActual correctamente.');

        // 🔹 Eliminar el documento "activo" actual
        await ultimaDocRef.delete();
        print('Documento "activo" borrado correctamente.');
      }

      // ✅ Crear el nuevo documento "activo"
      await ultimaDocRef.set(sessionData);
      print('Documento "activo" creado correctamente.');
    } catch (e) {
      print('❌ Error al guardar la sesión en Firestore: $e');
    }
  }

  Future<String> _getDeviceInfo() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String deviceInfoString = 'Unknown Device';

    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceInfoString = '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceInfoString = '${iosInfo.name} ${iosInfo.model}';
      }
    } catch (e) {
      print('Error al obtener la información del dispositivo: $e');
    }

    return deviceInfoString;
  }

  Future<String> _getAndroidVersion() async {
    if (Platform.isAndroid) {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.release;
    }
    return 'N/A';
  }

  Future<int> _getBatteryLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (e) {
      print('⚠️ Error al obtener nivel de batería: $e');
      return -1; // 🔹 Devuelve -1 si no se puede obtener
    }
  }

  Future<bool> _isGpsEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }
}
