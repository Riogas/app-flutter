import 'package:hive/hive.dart';

Future<String?> getConstantValue(String constantId) async {
  var box = await Hive.openBox('constantBox');
  var sessionBox = await Hive.openBox('sessionBox');
  var escenario = sessionBox.get('escenario');
  var data = box.get(constantId);

  String? valorEscenarioKey = 'ValorEscenario$escenario';
  String? valorFinal;

  if (data != null) {
    if (data['Estado'] == 'A') {
      // Check if Estado is 'A'
      if (data.containsKey(valorEscenarioKey) &&
          data[valorEscenarioKey] != null) {
        if (data[valorEscenarioKey] == '-1') {
          valorFinal = null; // Return null if ValorEscenario is -1
        } else {
          valorFinal = data[valorEscenarioKey]; // Prioritize ValorEscenario
        }
      } else {
        valorFinal = data['Valor']; // Default to Valor
      }
    } else {
      valorFinal = null; // Return null if Estado is not 'A'
    }
  }

  return valorFinal;
}
