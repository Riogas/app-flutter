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
  String? releaseNotes;

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
      releaseNotes = box.get('ReleaseNotes');
    });
  }

  Future<void> _logout() async {
    var sessionBox = await Hive.openBox('sessionBox');
    var constantBox = await Hive.openBox('constantBox');

    sessionBox.put('firstLoginDone', true);

    // Eliminar los datos de sesión de Hive
    await sessionBox.deleteFromDisk();
    await constantBox.deleteFromDisk();

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

    // Navegar a la pantalla de inicio de sesión
    Future.microtask(() {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => LoginPage(),
        ),
      );
    });
  }

  void _showReleaseNotesDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Notas de la Versión'),
          content: SingleChildScrollView(
            child:
                Text(releaseNotes ?? 'No hay notas de la versión disponibles.'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Configuración'),
        backgroundColor: Colors.blueAccent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileSection(),
            SizedBox(height: 20),
            _buildInfoSection(),
            SizedBox(height: 20),
            _buildLogoutButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.blueAccent,
              child: Icon(Icons.person, size: 40, color: Colors.white),
            ),
            SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (nombreUsuario != null)
                  Text(
                    nombreUsuario!,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (idUsuario != null)
                  Text(
                    'ID de Usuario: $idUsuario',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (movil != null)
              _buildInfoRow(Icons.local_shipping, 'Móvil', movil!),
            if (deviceId != null)
              _buildInfoRow(Icons.devices, 'DeviceID', deviceId!,
                  isLongText: true),
            if (releaseNotes != null)
              GestureDetector(
                onTap: _showReleaseNotesDialog,
                child: _buildInfoRow(
                    Icons.info_outline, 'Notas de la Versión', 'Mas Info',
                    isLongText: true),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String value,
      {bool isLongText = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment:
            isLongText ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.blueAccent),
          SizedBox(width: 10),
          Text(
            '$title: ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              overflow:
                  isLongText ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: _logout,
        icon: Icon(Icons.power_settings_new, color: Colors.blue),
        label: Text('Cerrar sesión'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.blue,
          side: BorderSide(color: Colors.blue),
        ),
      ),
    );
  }
}
