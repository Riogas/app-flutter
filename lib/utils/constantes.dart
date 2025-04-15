import 'package:hive/hive.dart';

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
