import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'riogas_service.dart';

class AuthService {
  static const MethodChannel _channel = MethodChannel('device_info');

  static Future<bool> checkIsLoggedIn() async {
    var box = await Hive.openBox('sessionBox');
    return box.get('username') != null && box.get('movil') != null;
  }

  static Future<String> getDeviceId() async {
    try {
      final String deviceId = await _channel.invokeMethod('getAndroidId');
      return deviceId;
    } catch (e) {
      return 'Error obteniendo ID';
    }
  }

  static Future<String> getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    print(
      'Package Info: version=${packageInfo.version}, buildNumber=${packageInfo.buildNumber}',
    );
    return 'Versión ${packageInfo.version}.${packageInfo.buildNumber}';
  }

  static Future<String> getAppVersionNro() async {
    final packageInfo = await PackageInfo.fromPlatform();
    print(
      'Package Info: version=${packageInfo.version}, buildNumber=${packageInfo.buildNumber}',
    );
    return '${packageInfo.version}.${packageInfo.buildNumber}';
  }

  static Future<bool> login(String username, String password) async {
    String deviceId = await getDeviceId();
    var response = await RioGasService.validarUsuario(
      username,
      password,
      deviceId,
      await getAppVersionNro(),
    );

    print("en auth_service.dart");

    if (response != null && response['OK'] == 0) {
      var box = await Hive.openBox('sessionBox');
      await box.put('username', username);
      await box.put('movil', response['selectedMovil']);
      await box.put('escenario', response['escenarioid'] == 1000 ? 1000 : 2000);
      await box.put('NombreUsuario', response['NombreUsuario'].trim());

      return true;
    }
    return false;
  }

  static Future<bool> validateDevice(String deviceId) async {
    var response = await RioGasService.validarDispositivo(deviceId);
    return response != null ? response['Existe'] ?? false : false;
  }

  static Future<bool> registerDevice(
    String deviceId,
    String document,
    String version,
    String number,
    String marca,
    String modelo,
    String info,
  ) async {
    var response = await RioGasService.registrarDispositivo(
      deviceId,
      document,
      version,
      number,
      marca,
      modelo,
      info,
    );
    return response != null ? response['success'] ?? false : false;
  }
}
