import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

const String kSessionTag = "[SESSION_SERVICE]";

class SessionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = Uuid();
  final Battery _battery = Battery();

  Future<Map<String, dynamic>> saveSession({
    required String idUsuario,
    required String nomUsuario,
    required LatLng primeraUbicacion,
    required String versionApp,
    required String tipoDeCierreDeSesion,
    DateTime? fchHoraCierre,
  }) async {
    print("$kSessionTag saveSession: INICIO");
    var box = await Hive.openBox('sessionBox');

    String escenarioId = box.get('escenario') ?? '0';
    if (escenarioId == '0') {
      return {
        'success': false,
        'message': 'No se pudo crear la sesión: escenario no definido.',
      };
    }
    String movilSeleccionado = box.get('movil') ?? 'Desconocido';
    String idSesion = _uuid.v4();
    String idTerminal = box.get('deviceId') ?? 'UnknownDevice';
    String infoDispositivo = await _getDeviceInfo();
    String nombreUsuario = (box.get('NombreUsuario') ?? 'Sin Nombre').trim();
    String versionAndroid = await _getAndroidVersion();
    int nivelBateria = await _getBatteryLevel();
    bool gpsActivado = await _isGpsEnabled();
    int distanciaRecorridaMts = 0;
    String estado = 'Activa';
    int tiempoLogueoMins = 0;

    DateTime now = DateTime.now();
    Timestamp fchHoraExpira = Timestamp.fromDate(now.add(Duration(hours: 8)));
    Timestamp fchHoraInicio = Timestamp.fromDate(now);
    Timestamp fchUltConexionDisp = Timestamp.fromDate(now);

    String fechaActual =
        now.toIso8601String().split('T')[0].replaceAll('-', '');

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
      'movil': movilSeleccionado,
      'primeraUbicacion': GeoPoint(
        primeraUbicacion.latitude,
        primeraUbicacion.longitude,
      ),
      'tiempoLogueoMins': tiempoLogueoMins,
      'ultUbicacion': GeoPoint(
        primeraUbicacion.latitude,
        primeraUbicacion.longitude,
      ),
      'versionApp': versionApp,
      'versionAndroid': versionAndroid,
      'nivelBateria': nivelBateria,
      'gpsActivado': gpsActivado,
      'fchHoraCierre': fchHoraCierre,
      'tipoDeCierreDeSesion': tipoDeCierreDeSesion,
    };

    print("$kSessionTag saveSession: Datos de sesión preparados");
    try {
      // Asegurar que el documento de la fecha existe
      await _firestore.collection('sessions-$escenarioId').doc(fechaActual).set(
          {'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      // 1. Verificar si el usuario ya está logueado en otro móvil
      print(
          "$kSessionTag saveSession: Verificando usuario logueado en otro móvil");
      final doc = await _firestore
          .collection('sessions-$escenarioId')
          .doc(fechaActual)
          .collection('activeSessions')
          .doc('Usuario-$idUsuario')
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        final movilAnterior = data['idMovil'] ?? data['movil'] ?? 'Desconocido';
        print(
            "$kSessionTag saveSession: Usuario ya logueado en $movilAnterior");
        return {
          'success': false,
          'message':
              'Su usuario ya está logueado en el movil ${data['movil']}. ¿Desea continuar?',
          'movilAnterior': movilAnterior,
        };
      }
      // 2. Verificar si el móvil ya está en uso por otro usuario
      print(
          "$kSessionTag saveSession: Verificando móvil en uso por otro usuario");
      final snapshot = await _firestore
          .collection('sessions-$escenarioId')
          .doc(fechaActual)
          .collection('activeSessions')
          .where('movil', isEqualTo: movilSeleccionado)
          .get();
      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final otroUsuario = data['idUsuario'] ?? 'Desconocido';
        print("$kSessionTag saveSession: Móvil en uso por $otroUsuario");
        return {
          'success': false,
          'message':
              'Usted se está intentando conectar al móvil $movilSeleccionado, en el cual está logueado el usuario ${data['nomUsuario']}. ¿Desea continuar?',
          'otroUsuario': otroUsuario,
        };
      }
      // 3. Crear la sesión si no hay conflictos
      print("$kSessionTag saveSession: Creando sesión en Firestore");
      await _firestore
          .collection('sessions-$escenarioId')
          .doc(fechaActual)
          .collection('activeSessions')
          .doc('Usuario-$idUsuario')
          .set(sessionData);
      print("$kSessionTag saveSession: Sesión guardada exitosamente");
      return {
        'success': true,
        'message': 'Sesión guardada exitosamente.',
        'idSesion': idSesion,
      };
    } catch (e) {
      print("$kSessionTag saveSession: ERROR $e");
      return {
        'success': false,
        'message': 'Error al guardar la sesión: $e',
      };
    }
  }

  // Refactorización para obtener los datos de sesión comunes
  Future<Map<String, dynamic>> _getSessionCommonData({
    required String idUsuario,
    required String nomUsuario,
    required LatLng primeraUbicacion,
    required String versionApp,
    required String tipoDeCierreDeSesion,
    required DateTime fchHoraCierre,
  }) async {
    print("$kSessionTag _getSessionCommonData: INICIO");
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario') ?? '0';
    String movilSeleccionado = box.get('movil') ?? 'Desconocido';
    String idSesion = _uuid.v4();
    String idTerminal = box.get('deviceId') ?? 'UnknownDevice';
    String infoDispositivo = await _getDeviceInfo();
    String nombreUsuario = (box.get('NombreUsuario') ?? 'Sin Nombre').trim();
    String versionAndroid = await _getAndroidVersion();
    int nivelBateria = await _getBatteryLevel();
    bool gpsActivado = await _isGpsEnabled();
    int distanciaRecorridaMts = 0;
    String estado = 'Activa';
    int tiempoLogueoMins = 0;
    DateTime now = DateTime.now();
    Timestamp fchHoraExpira = Timestamp.fromDate(now.add(Duration(hours: 8)));
    Timestamp fchHoraInicio = Timestamp.fromDate(now);
    Timestamp fchUltConexionDisp = Timestamp.fromDate(now);
    String fechaActual =
        now.toIso8601String().split('T')[0].replaceAll('-', '');
    print("$kSessionTag _getSessionCommonData: Datos comunes preparados");
    return {
      'escenarioId': escenarioId,
      'movilSeleccionado': movilSeleccionado,
      'idSesion': idSesion,
      'idTerminal': idTerminal,
      'infoDispositivo': infoDispositivo,
      'nombreUsuario': nombreUsuario,
      'versionAndroid': versionAndroid,
      'nivelBateria': nivelBateria,
      'gpsActivado': gpsActivado,
      'distanciaRecorridaMts': distanciaRecorridaMts,
      'estado': estado,
      'tiempoLogueoMins': tiempoLogueoMins,
      'now': now,
      'fchHoraExpira': fchHoraExpira,
      'fchHoraInicio': fchHoraInicio,
      'fchUltConexionDisp': fchUltConexionDisp,
      'fechaActual': fechaActual,
      'primeraUbicacion': primeraUbicacion,
      'versionApp': versionApp,
      'tipoDeCierreDeSesion': tipoDeCierreDeSesion,
      'fchHoraCierre': fchHoraCierre,
      'idUsuario': idUsuario,
      'nomUsuario': nomUsuario,
    };
  }

  Future<Map<String, dynamic>> setHistory({
    required String idUsuario,
    required String nomUsuario,
    required LatLng primeraUbicacion,
    required String versionApp,
    required String tipoDeCierreDeSesion,
    required DateTime fchHoraCierre,
  }) async {
    print("$kSessionTag 📥 setHistory: INICIO");

    try {
      print("$kSessionTag 🔍 Obteniendo datos comunes de sesión...");
      final common = await _getSessionCommonData(
        idUsuario: idUsuario,
        nomUsuario: nomUsuario,
        primeraUbicacion: primeraUbicacion,
        versionApp: versionApp,
        tipoDeCierreDeSesion: tipoDeCierreDeSesion,
        fchHoraCierre: fchHoraCierre,
      );

      print("$kSessionTag ✅ Datos comunes obtenidos: $common");

      if (common['escenarioId'] == '0') {
        print("$kSessionTag ⚠️ Escenario no definido. Abortando.");
        return {
          'success': false,
          'message': 'No se pudo crear la sesión: escenario no definido.',
        };
      }

      final escenarioId = common['escenarioId'];
      final movilSeleccionado = common['movilSeleccionado'];
      final fechaActual = common['fechaActual'];
      final now = common['now'] as DateTime;
      final horaActual = now.toIso8601String().split('T')[1].split('.')[0];
      final idSesion = common['idSesion'];

      final sessionData = {
        'distanciaRecorridaMts': common['distanciaRecorridaMts'],
        'estado': common['estado'],
        'fchHoraExpira': common['fchHoraExpira'],
        'fchHoraInicio': common['fchHoraInicio'],
        'fchUltConexionDisp': common['fchUltConexionDisp'],
        'idSesion': idSesion,
        'idTerminal': common['idTerminal'],
        'idUsuario': idUsuario,
        'infoDispositivo': common['infoDispositivo'],
        'nomUsuario': common['nombreUsuario'],
        'movil': movilSeleccionado,
        'primeraUbicacion': GeoPoint(
          primeraUbicacion.latitude,
          primeraUbicacion.longitude,
        ),
        'tiempoLogueoMins': common['tiempoLogueoMins'],
        'ultUbicacion': GeoPoint(
          primeraUbicacion.latitude,
          primeraUbicacion.longitude,
        ),
        'versionApp': versionApp,
        'versionAndroid': common['versionAndroid'],
        'nivelBateria': common['nivelBateria'],
        'gpsActivado': common['gpsActivado'],
      };

      print("$kSessionTag 🗂 Asegurando documento de fecha...");
      await _firestore.collection('sessions-$escenarioId').doc(fechaActual).set(
          {'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

      print("$kSessionTag 🔎 Buscando sesión activa del usuario...");
      final doc = await _firestore
          .collection('sessions-$escenarioId')
          .doc(fechaActual)
          .collection('activeSessions')
          .doc('Usuario-$idUsuario')
          .get();

      if (doc.exists) {
        print(
            "$kSessionTag 🔄 Sesión activa encontrada, moviendo a history...");
        final data = doc.data()!;

        // 🔹 Agregar campos faltantes antes de guardar en "history"
        data['tipoDeCierreDeSesion'] = tipoDeCierreDeSesion;
        data['fchHoraCierre'] = fchHoraCierre.toIso8601String();

        final historyId = '${horaActual.replaceAll(':', '')}-$idUsuario';

        await _firestore
            .collection('sessions-$escenarioId')
            .doc(fechaActual)
            .collection('history')
            .doc(historyId)
            .set(data);

        await _firestore
            .collection('sessions-$escenarioId')
            .doc(fechaActual)
            .collection('activeSessions')
            .doc('Usuario-$idUsuario')
            .delete();

        print(
            "$kSessionTag ✅ Sesión movida a history. Creando nueva sesión...");
        final saveResult = await saveSession(
          idUsuario: idUsuario,
          nomUsuario: nomUsuario,
          primeraUbicacion: primeraUbicacion,
          versionApp: versionApp,
          tipoDeCierreDeSesion: tipoDeCierreDeSesion,
          fchHoraCierre: fchHoraCierre,
        );
        print("$kSessionTag 📌 Resultado saveSession: $saveResult");
        return saveResult;
      }

      print(
          "$kSessionTag 🔍 Buscando si el móvil está en uso por otro usuario...");
      final snapshot = await _firestore
          .collection('sessions-$escenarioId')
          .doc(fechaActual)
          .collection('activeSessions')
          .where('movil', isEqualTo: movilSeleccionado)
          .get();

      if (snapshot.docs.isNotEmpty) {
        print(
            "$kSessionTag 🔄 Móvil está en uso. Moviendo sesión a history...");
        final data = snapshot.docs.first.data();
        final otroUsuario = data['idUsuario'] ?? 'Desconocido';
        final docId = snapshot.docs.first.id;
        final historyId = '${horaActual.replaceAll(':', '')}-$otroUsuario';

        await _firestore
            .collection('sessions-$escenarioId')
            .doc(fechaActual)
            .collection('history')
            .doc(historyId)
            .set(data);

        await _firestore
            .collection('sessions-$escenarioId')
            .doc(fechaActual)
            .collection('activeSessions')
            .doc(docId)
            .delete();

        print("$kSessionTag ✅ Móvil liberado. Creando nueva sesión...");
        final saveResult = await saveSession(
          idUsuario: idUsuario,
          nomUsuario: nomUsuario,
          primeraUbicacion: primeraUbicacion,
          versionApp: versionApp,
          tipoDeCierreDeSesion: tipoDeCierreDeSesion,
        );
        print("$kSessionTag 📌 Resultado saveSession: $saveResult");
        return saveResult;
      }

      print("$kSessionTag ⚠️ No existe sesión previa para mover a history.");
      return {
        'success': false,
        'message': 'No existe sesión previa para mover a history.',
      };
    } catch (e) {
      print("$kSessionTag ❌ ERROR en setHistory: $e");
      return {
        'success': false,
        'message': 'Error en setHistory: $e',
      };
    }
  }

  Future<Map<String, dynamic>> cerrarSesion({
    required String idUsuario,
    required String tipoDeCierreDeSesion,
  }) async {
    print("$kSessionTag cerrarSesion: INICIO");
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario') ?? '0';
    if (escenarioId == '0') {
      return {
        'success': false,
        'message': 'No se pudo cerrar la sesión: escenario no definido.',
      };
    }
    DateTime now = DateTime.now();
    String fechaActual =
        now.toIso8601String().split('T')[0].replaceAll('-', '');
    String horaActual = now.toIso8601String().split('T')[1].split('.')[0];
    try {
      // Asegurar que el documento de la fecha existe
      await _firestore.collection('sessions-$escenarioId').doc(fechaActual).set(
          {'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      print("$kSessionTag cerrarSesion: Documento de fecha asegurado");
      print("$kSessionTag cerrarSesion: Buscando sesión activa");
      final doc = await _firestore
          .collection('sessions-$escenarioId')
          .doc(fechaActual)
          .collection('activeSessions')
          .doc('Usuario-$idUsuario')
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        final movilAnterior = data['idMovil'] ?? data['movil'] ?? 'Desconocido';
        final historyId = '${horaActual.replaceAll(':', '')}-$idUsuario';
        print("$kSessionTag cerrarSesion: Moviendo sesión activa a history");
        await _firestore
            .collection('sessions-$escenarioId')
            .doc(fechaActual)
            .collection('history')
            .doc(historyId)
            .set({
          ...data,
          'tipoDeCierreDeSesion': tipoDeCierreDeSesion,
          'fchHoraCierre': Timestamp.fromDate(now),
        });
        await _firestore
            .collection('sessions-$escenarioId')
            .doc(fechaActual)
            .collection('activeSessions')
            .doc('Usuario-$idUsuario')
            .delete();
        print("$kSessionTag cerrarSesion: Sesión movida a history");
        return {
          'success': true,
          'message': 'Login exitoso: sesión anterior movida a history.',
          'movilAnterior': movilAnterior,
        };
      } else {
        print(
            "$kSessionTag cerrarSesion: No existe sesión activa para este usuario");
        return {
          'success': false,
          'message': 'No existe sesión activa para este usuario.',
        };
      }
    } catch (e) {
      print("$kSessionTag cerrarSesion: ERROR $e");
      return {
        'success': false,
        'message': 'Error al cerrar la sesión: $e',
      };
    }
  }

  Future<String> _getDeviceInfo() async {
    print("$kSessionTag _getDeviceInfo: INICIO");
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
      print("$kSessionTag _getDeviceInfo: $deviceInfoString");
    } catch (e) {
      print('$kSessionTag _getDeviceInfo: ERROR $e');
    }
    return deviceInfoString;
  }

  Future<String> _getAndroidVersion() async {
    print("$kSessionTag _getAndroidVersion: INICIO");
    if (Platform.isAndroid) {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      print("$kSessionTag _getAndroidVersion: ${androidInfo.version.release}");
      return androidInfo.version.release;
    }
    print("$kSessionTag _getAndroidVersion: N/A");
    return 'N/A';
  }

  Future<int> _getBatteryLevel() async {
    print("$kSessionTag _getBatteryLevel: INICIO");
    try {
      int level = await _battery.batteryLevel;
      print("$kSessionTag _getBatteryLevel: $level");
      return level;
    } catch (e) {
      print('$kSessionTag _getBatteryLevel: ERROR $e');
      return -1; // 🔹 Devuelve -1 si no se puede obtener
    }
  }

  Future<bool> _isGpsEnabled() async {
    print("$kSessionTag _isGpsEnabled: INICIO");
    bool enabled = await Geolocator.isLocationServiceEnabled();
    print("$kSessionTag _isGpsEnabled: $enabled");
    return enabled;
  }
}
