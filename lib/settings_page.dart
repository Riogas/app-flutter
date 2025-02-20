import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'main.dart'; // Asegúrate de importar la pantalla de inicio de sesión

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String username = "";
  String mobileNumber = "";

  @override
  void initState() {
    super.initState();
    _loadSessionData();
  }

  Future<void> _loadSessionData() async {
    var box = await Hive.openBox('sessionBox');
    setState(() {
      username = box.get('username', defaultValue: 'Usuario no encontrado');
      mobileNumber = box.get('movil', defaultValue: 'Número no encontrado');
    });

    // Debug: Mostrar todo el contenido de sessionBox
    print("Contenido de sessionBox:");
    box.toMap().forEach((key, value) {
      print('$key: $value');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Opciones'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usuario: $username',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Número de móvil: $mobileNumber',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 20),
            Center(
              child: ElevatedButton.icon(
                onPressed: () async {
                  // Eliminar los datos de sesión de Hive
                  var box = await Hive.openBox('sessionBox');
                  await box.clear();

                  // Navegar a la pantalla de inicio de sesión
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                        builder: (context) =>
                            MyApp()), // Reemplaza MyApp con tu pantalla de inicio de sesión
                  );
                },
                icon: Icon(Icons.power_settings_new, color: Colors.blue),
                label: Text('Cerrar sesión'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue,
                  side: BorderSide(color: Colors.blue),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
