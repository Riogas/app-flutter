import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class SessionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = Uuid();

  Future<void> saveSession({
    required String idUsuario,
    required String nomUsuario,
    required LatLng primeraUbicacion,
    required String versionApp,
  }) async {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario');
    String movil = box.get('movil');
    String idSesion = _uuid.v4();
    String idTerminal = box.get('deviceId');
    String infoDispositivo =
        await _getDeviceInfo(); // Obtener información del dispositivo
    String nombreUsuario = box.get('NombreUsuario');
    int distanciaRecorridaMts = 0;
    String estado = 'Activa';
    DateTime now = DateTime.now();
    DateTime fchHoraExpira = now.add(Duration(hours: 8));
    DateTime fchHoraInicio = now;
    DateTime fchUltConexionDisp = now;
    int tiempoLogueoMins = 0;

    String fechaActual =
        now.toIso8601String().split('T')[0].replaceAll('-', '');
    String horaActual = now.toIso8601String().split('T')[1].split('.')[0];

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
    };

    print('Guardando sesión en Firestore con los siguientes datos:');
    print(sessionData);

    try {
      // Asegurar que el documento padre (fecha) tenga un campo para ser reconocido como documento válido
      await fechaDocRef.set({'FchHoraCreacion': now}, SetOptions(merge: true));
      print('Documento padre asegurado en Firestore con FchHoraCreacion.');

      // Guardar la sesión actual
      await sessionDocRef.set(sessionData);
      print('Sesión guardada correctamente en sessionDocRef.');

      // Borrar y crear la colección 'ultima'
      await ultimaDocRef.delete();
      print('Documento "ultima" borrado correctamente.');
      await ultimaDocRef.set(sessionData);
      print('Documento "ultima" creado correctamente.');
    } catch (e) {
      print('Error al guardar la sesión en Firestore: $e');
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
}
