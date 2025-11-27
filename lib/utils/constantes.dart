import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/riogas_service.dart'; // 🆕 Para resetear HTTP client

// 🌍 Enumeración para los ambientes de la aplicación
enum Environment { production, development }

// 🌍 Clase para gestionar el ambiente de la aplicación (Producción/Desarrollo)
class AppEnvironment {
  static const String _keyEnvironment = 'app_environment';
  static Environment _currentEnvironment = Environment.production;

  // 🔧 URL de desarrollo cargada desde constante 611
  static String? _devUrlFromConstant;

  // URLs de desarrollo por defecto (fallback si no existe constante 611)
  static const String _devUrlFallback =
      'https://sgm.riogas.com.uy/appservices/';

  // Getter para URL de desarrollo (usa constante 611 o fallback)
  static String get devUrl => _devUrlFromConstant ?? _devUrlFallback;

  // Inicializar desde SharedPreferences y cargar constante 611
  static Future<void> initialize() async {
    // 🔒 SIEMPRE iniciar en PRODUCCIÓN (ignorar preferencia guardada)
    _currentEnvironment = Environment.production;
    print('🌍 [AMBIENTE] Aplicación SIEMPRE inicia en modo PRODUCCIÓN');
    print(
        'ℹ️ [AMBIENTE] El ambiente se cambiará después del login si el usuario es especial');

    // 🔧 Cargar constante 611 para URL de desarrollo
    await _loadDevUrlFromConstant();
  }

  // 🔧 Cargar la constante 611 desde Hive
  static Future<void> _loadDevUrlFromConstant() async {
    try {
      final constantBox = await Hive.openBox('constantBox');
      final data = constantBox.get('611');

      if (data != null && data['Estado'] == 'A') {
        final url = data['Valor']?.toString().trim();
        if (url != null && url.isNotEmpty) {
          _devUrlFromConstant = url;
          print(
              '🔧 [CONSTANTE 611] URL Desarrollo cargada: "$_devUrlFromConstant"');
        } else {
          print('⚠️ [CONSTANTE 611] Valor vacío, usando fallback');
        }
      } else {
        print('⚠️ [CONSTANTE 611] No existe o Estado != A, usando fallback');
      }
    } catch (e) {
      print('❌ [CONSTANTE 611] Error cargando: $e, usando fallback');
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

    // 🔄 Resetear el cliente HTTP para aplicar nueva configuración SSL
    RioGasService.resetHttpClient();
  }

  // 🆕 Cambiar el ambiente SOLO durante la sesión actual (no persiste en SharedPreferences)
  static void setEnvironmentForSession(Environment environment) {
    _currentEnvironment = environment;
    print(
        '🌍 [AMBIENTE] Cambiado temporalmente a: ${environment == Environment.development ? "DESARROLLO" : "PRODUCCIÓN"}');
    print(
        'ℹ️ [AMBIENTE] Este cambio NO persiste. Al cerrar sesión, volverá a PRODUCCIÓN.');

    // 🔄 Resetear el cliente HTTP para aplicar nueva configuración SSL
    RioGasService.resetHttpClient();
  }

  // 🆕 Resetear a producción (llamar al cerrar sesión)
  static Future<void> resetToProduction() async {
    _currentEnvironment = Environment.production;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEnvironment); // Eliminar preferencia guardada
    print('🌍 [AMBIENTE] Reseteado a PRODUCCIÓN (por defecto)');

    // 🔄 Resetear el cliente HTTP para aplicar nueva configuración SSL
    RioGasService.resetHttpClient();
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
