import 'package:flutter/material.dart';
import 'package:MoveIT/pages/login_page.dart';
import 'package:hive/hive.dart';
import '../services/session_service.dart';
import 'package:latlong2/latlong.dart';

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

  Future<void> _logout() async {
    var sessionBox = await Hive.openBox('sessionBox');
    var constantBox = await Hive.openBox('constantBox');

    // Llamar a SessionService para eliminar el documento activo y crear una copia
    SessionService sessionService = SessionService();
    await sessionService.saveSession(
      idUsuario: idUsuario!,
      nomUsuario: nombreUsuario!,
      primeraUbicacion:
          LatLng(0, 0), // Reemplaza con la ubicación real si es necesario
      versionApp: '1.0.0', // Reemplaza con la versión real de la app
      tipoDeCierreDeSesion: 'logoutUser',
    );

    // Eliminar los datos de sesión de Hive
    await sessionBox.deleteFromDisk();
    await constantBox.deleteFromDisk();

    // Navegar a la pantalla de inicio de sesión
    Future.microtask(() {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => LoginPage(),
        ),
      );
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
              onPressed: _logout,
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
