import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'riogas_service.dart';

class AuthService {
  static Future<bool> checkIsLoggedIn() async {
    var box = await Hive.openBox('sessionBox');
    return box.get('username') != null && box.get('movil') != null;
  }

  static Future<String> getDeviceId() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      if (deviceInfo.androidInfo != null) {
        return (await deviceInfo.androidInfo).id;
      } else if (deviceInfo.iosInfo != null) {
        return (await deviceInfo.iosInfo).identifierForVendor ?? 'Unknown';
      }
    } catch (e) {
      return 'Error obteniendo ID';
    }
    return 'Unknown';
  }

  static Future<String> getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return 'Versión ${packageInfo.version}';
  }

  static Future<bool> login(String username, String password) async {
    String deviceId = await getDeviceId();
    var response =
        await RioGasService.validarUsuario(username, password, deviceId);

    print("en auth_service.dart");

    if (response != null && response['OK'] == 0) {
      var box = await Hive.openBox('sessionBox');
      await box.put('username', username);
      await box.put('movil', response['selectedMovil']);
      await box.put('escenario', response['EscenarioId']);
      await box.put('NombreUsuario', response['NombreUsuario'].trim());

      // 🔹 Guardar que es un login manual para evitar el logout forzado inmediato
      await box.put('firstLoginDone', true);

      return true;
    }
    return false;
  }

  static Future<bool> validateDevice(String deviceId) async {
    var response = await RioGasService.validarDispositivo(deviceId);
    return response != null ? response['Existe'] ?? false : false;
  }

  static Future<bool> registerDevice(String deviceId, String document) async {
    var response = await RioGasService.registrarDispositivo(deviceId, document);
    return response != null ? response['success'] ?? false : false;
  }
}
