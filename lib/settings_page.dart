import 'package:flutter/material.dart';
import 'package:MoveIT/main.dart';
import 'package:hive/hive.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? nombreUsuario;
  String? movil;
  String? idUsuario;
  String? deviceId;

  @override
  void initState() {
    super.initState();
    _loadSessionData();
  }

  Future<void> _loadSessionData() async {
    var box = await Hive.openBox('sessionBox');
    setState(() {
      nombreUsuario = box.get('NombreUsuario');
      movil = box.get('movil');
      idUsuario = box.get('username');
      deviceId = box.get('deviceId');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (nombreUsuario != null)
              Text('Nombre de Usuario: $nombreUsuario'),
            if (movil != null) Text('Móvil: $movil'),
            if (idUsuario != null) Text('ID de Usuario: $idUsuario'),
            if (deviceId != null) Text('ID de Dispositivo: $deviceId'),
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                // Eliminar los datos de sesión de Hive
                var box = await Hive.openBox('sessionBox');
                await box.deleteFromDisk();

                // Navegar a la pantalla de inicio de sesión
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) =>
                        LoginPage(), // Reemplaza LoginPage con tu pantalla de inicio de sesión
                  ),
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
          ],
        ),
      ),
    );
  }
}
