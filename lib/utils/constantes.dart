import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🌍 Enumeración para los ambientes de la aplicación
enum Environment { production, development }

// 🌍 Clase para gestionar el ambiente de la aplicación (Producción/Desarrollo)
class AppEnvironment {
  static const String _keyEnvironment = 'app_environment';
  static Environment _currentEnvironment = Environment.production;

  // URLs de desarrollo (usando constante 611 para ambiente dev)
  static const String devBaseRoot = 'https://riogas.desa.uy/ica_geos_/';
  static const String devServicesPath = 'appservices/';

  // Inicializar desde SharedPreferences
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final envString = prefs.getString(_keyEnvironment);

    if (envString == 'development') {
      _currentEnvironment = Environment.development;
      print('🌍 [AMBIENTE] Aplicación iniciada en modo DESARROLLO');
    } else {
      _currentEnvironment = Environment.production;
      print('🌍 [AMBIENTE] Aplicación iniciada en modo PRODUCCIÓN');
    }
  }

  // Obtener el ambiente actual
  static Environment get current => _currentEnvironment;

  // Verificar si está en desarrollo
  static bool get isDevelopment =>
      _currentEnvironment == Environment.development;

  // Verificar si está en producción
  static bool get isProduction => _currentEnvironment == Environment.production;

  // Cambiar el ambiente (solo para usuarios especiales)
  static Future<void> setEnvironment(Environment environment) async {
    _currentEnvironment = environment;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyEnvironment,
      environment == Environment.development ? 'development' : 'production',
    );
    print(
        '🌍 [AMBIENTE] Cambiado a: ${environment == Environment.development ? "DESARROLLO" : "PRODUCCIÓN"}');
  }

  // 🆕 Cambiar el ambiente SOLO durante la sesión actual (no persiste en SharedPreferences)
  static void setEnvironmentForSession(Environment environment) {
    _currentEnvironment = environment;
    print(
        '🌍 [AMBIENTE] Cambiado temporalmente a: ${environment == Environment.development ? "DESARROLLO" : "PRODUCCIÓN"}');
    print(
        'ℹ️ [AMBIENTE] Este cambio NO persiste. Al cerrar sesión, volverá a PRODUCCIÓN.');
  }

  // 🆕 Resetear a producción (llamar al cerrar sesión)
  static Future<void> resetToProduction() async {
    _currentEnvironment = Environment.production;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEnvironment); // Eliminar preferencia guardada
    print('🌍 [AMBIENTE] Reseteado a PRODUCCIÓN (por defecto)');
  }

  // Obtener el nombre legible del ambiente
  static String get environmentName =>
      _currentEnvironment == Environment.development
          ? 'Desarrollo'
          : 'Producción';
}

Future<String?> getConstantValue(String constantId) async {
  var box = await Hive.openBox('constantBox');
  var sessionBox = await Hive.openBox('sessionBox');
  var escenario = sessionBox.get('escenario');
  var data = box.get(constantId);

  String? valorEscenarioKey = 'ValorEscenario$escenario';
  String? valorFinal;

  if (data != null) {
    print('Data encontrado: $data');
    if (data['Estado'] == 'A') {
      print('Estado es A');
      if (data.containsKey(valorEscenarioKey) &&
          data[valorEscenarioKey] != null) {
        print('ValorEscenarioKey encontrado: ${data[valorEscenarioKey]}');
        if (data[valorEscenarioKey] == '-1') {
          print('ValorEscenario es -1, devolviendo null');
          valorFinal = null; // Return null if ValorEscenario is -1
        } else {
          print('Usando ValorEscenario: ${data[valorEscenarioKey]}');
          valorFinal = data[valorEscenarioKey]; // Prioritize ValorEscenario
        }
      } else {
        print('Usando Valor por defecto: ${data['Valor']}');
        valorFinal = data['Valor']; // Default to Valor
      }
    } else {
      print('Estado no es A, devolviendo null');
      valorFinal = null; // Return null if Estado is not 'A'
    }
  } else {
    print('Data es null');
  }

  return valorFinal;
}
