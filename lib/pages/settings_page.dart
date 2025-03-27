import 'package:flutter/material.dart';
import 'package:MoveIT/pages/login_page.dart';
import 'package:hive/hive.dart';
import '../services/session_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/riogas_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../utils/error_event.dart';
import '../utils/constantes.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter_email_sender/flutter_email_sender.dart';

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
  String appVersion = '1.0.0'; // Reemplaza con la versión real de la app
  int completedOrdersCount = 0;
  int subCompletedOrdersCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSessionData();
    _loadCompletedOrdersCount();
    _loadAppVersion();
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

  Future<void> _loadCompletedOrdersCount() async {
    var box = await Hive.openBox('sessionBox');
    String escenarioId = box.get('escenario', defaultValue: '0');
    int movil = int.tryParse(box.get('movil', defaultValue: '0')) ?? 0;

    String collectionName = 'Pedidos-$escenarioId';
    String fechaActualStr = DateTime.now()
        .toUtc()
        .subtract(Duration(hours: 3))
        .toIso8601String()
        .split('T')[0]
        .replaceAll('-', '');
    int fechaActual = int.tryParse(fechaActualStr) ?? 0;

    var snapshot = await FirebaseFirestore.instance
        .collection(collectionName)
        .where('Movil', isEqualTo: movil)
        .where('FchPara', isEqualTo: fechaActual)
        .where('VisibleEnApp', isEqualTo: 'S')
        .get();

    int totalOrders = snapshot.docs.length;
    int completedOrders =
        snapshot.docs.where((doc) => doc['EstadoNro'] == 2).length;
    int subCompletedOrders =
        snapshot.docs.where((doc) => doc['SubEstadoNro'] == 3).length;

    if (mounted) {
      setState(() {
        completedOrdersCount = completedOrders;
        subCompletedOrdersCount = subCompletedOrders;
      });
    }
  }

  Future<void> _logout() async {
    bool? confirmLogout = await _showLogoutConfirmationDialog();
    if (confirmLogout == true) {
      var sessionBox = await Hive.openBox('sessionBox');
      var constantBox = await Hive.openBox('constantBox');
      var mensajesBox = await Hive.openBox('mensajesBox'); // Open mensajesBox
      sessionBox.put('firstLoginDone', true);

      // Eliminar los datos de sesión de Hive
      await sessionBox.deleteFromDisk();
      await constantBox.deleteFromDisk();
      await mensajesBox.deleteFromDisk();

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
  }

  Future<bool?> _showLogoutConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Confirmación de Cierre de Sesión'),
          content: Text(
              '¿Está seguro que desea cerrar sesión y salir de la aplicación?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text('Aceptar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _changePassword() async {
    TextEditingController oldPasswordController = TextEditingController();
    TextEditingController newPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Cambiar Contraseña'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPasswordController,
                decoration: InputDecoration(labelText: 'Nueva Contraseña'),
                obscureText: true,
              ),
              TextField(
                controller: newPasswordController,
                decoration: InputDecoration(labelText: 'Confirmar Contraseña'),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                if (oldPasswordController.text == newPasswordController.text) {
                  var box = await Hive.openBox('sessionBox');
                  String? nombreUsuario = box.get('username');
                  if (nombreUsuario != null) {
                    await RioGasService.cambioPassword(
                      nombreUsuario,
                      newPasswordController.text,
                    );
                    Navigator.of(context).pop();
                  } else {
                    // Handle error: NombreUsuario not found in Hive
                    Navigator.of(context).pop();
                    _showMessage('Error: NombreUsuario no encontrado.');
                  }
                } else {
                  // Handle error: Passwords do not match
                  Navigator.of(context).pop();
                  _showMessage('Error: Las contraseñas no coinciden.');
                }
              },
              child: Text('Aceptar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _generateReport() async {
    DateTime? selectedDate = await _selectDate(context);
    if (selectedDate != null) {
      // Aquí puedes agregar el código para ejecutar el servicio de terceros
      print('Fecha seleccionada para el reporte: $selectedDate');
    }
  }

  Future<DateTime?> _selectDate(BuildContext context) async {
    DateTime initialDate = DateTime.now();
    DateTime firstDate = DateTime(2000);
    DateTime lastDate = DateTime(2101);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    return picked;
  }

  Future<void> _checkForUpdate() async {
    var response = await RioGasService.validarVersion(appVersion, deviceId!);

    if (response != null) {
      if (response['Ultversion'] == '') {
        _showMessage(response['message']);
      } else {
        _showUpdateDialog(
          response['message'],
          response['link'],
        );
      }
    }
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Información'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Aceptar'),
            ),
          ],
        );
      },
    );
  }

  void _showUpdateDialog(String message, String link) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Actualización'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final Uri url = Uri.parse(link);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } else {
                  _showMessage('No se pudo abrir el enlace $link');
                }
              },
              child: Text('Confirmar'),
            ),
          ],
        );
      },
    );
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

  Future<void> _loadAppVersion() async {
    String version = await AuthService.getAppVersionNro();
    setState(() {
      appVersion = version;
    });
  }

  Future<void> _viewErrors() async {
    var errorBox = await Hive.openBox<ErrorEvent>('errorBox');
    List<ErrorEvent> errors = errorBox.values.toList().cast<ErrorEvent>();

    String? supportEmail =
        await getConstantValue('90'); // Fetch email from constant

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Errores Registrados'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: errors.length,
              itemBuilder: (context, index) {
                final error = errors[index];
                return ListTile(
                  title: Text('${error.type}: ${error.message}'),
                  subtitle: Text(
                      'Fecha: ${error.timestamp}\nInfo Adicional: ${error.additionalInfo ?? "N/A"}'),
                );
              },
            ),
          ),
          actions: [
            if (supportEmail != null) // Show button only if email is not null
              TextButton(
                onPressed: () async {
                  await _sendErrorsToSupport(errors, supportEmail);
                },
                child: Text('Enviar Datos a Soporte'),
              ),
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

  Future<void> _sendErrorsToSupport(
      List<ErrorEvent> errors, String supportEmail) async {
    try {
      // Crear contenido del archivo
      String content = errors.map((error) {
        return "Tipo: ${error.type}\n"
            "Mensaje: ${error.message}\n"
            "Fecha: ${error.timestamp}\n"
            "Info Adicional: ${error.additionalInfo ?? "N/A"}\n\n";
      }).join();

      // Obtener directorio temporal
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/errores_reportados.txt';
      debugPrint('Temporary directory: $directory');
      debugPrint('File path: $filePath');

      // Escribir contenido en el archivo
      final file = File(filePath);
      await file.writeAsString(content);
      debugPrint('File written successfully.');

      // Preparar correo con archivo adjunto
      final Email email = Email(
        body: 'Adjunto archivo con los errores.',
        subject: 'Reporte de Errores',
        recipients: [supportEmail],
        attachmentPaths: [filePath],
        isHTML: false,
      );

      // Enviar correo
      await FlutterEmailSender.send(email);
      debugPrint('Email sent successfully.');
    } catch (e) {
      debugPrint('Error during _sendErrorsToSupport: $e');
      _showMessage("Error al generar el archivo de errores: $e");
    }
  }

  Future<double> _loadTotalDistance() async {
    var box = await Hive.openBox('locationBox');
    return box.get('totalDistance', defaultValue: 0.0);
  }

  Future<bool> _shouldShowDistance() async {
    var box = await Hive.openBox('constantBox');
    var data = box.get('80');

    if (data != null) {
      return data['Estado'] == 'A' && data['Valor'] == 'S';
    }
    return false;
  }

  Widget _buildViewErrorsButton() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: _viewErrors,
        icon: Icon(Icons.error, color: Colors.red),
        label: Text('Ver Errores'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.red,
          side: BorderSide(color: Colors.red),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Configuración'),
        backgroundColor: Colors.blueAccent,
      ),
      body: SingleChildScrollView(
        // Wrap the body in a scrollable view
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileSection(),
              SizedBox(height: 20),
              _buildInfoSection(),
              SizedBox(height: 20),
              _buildChangePasswordButton(),
              SizedBox(height: 10),
              _buildLogoutButton(),
              SizedBox(height: 10),
              _buildViewErrorsButton(),
            ],
          ),
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
            _buildInfoRowWithButton(
                Icons.check_circle,
                'Pedidos Finalizados',
                '$subCompletedOrdersCount/$completedOrdersCount',
                Icons.description,
                _generateReport),
            _buildInfoRowWithButton(Icons.verified, 'Versión de la App',
                appVersion, Icons.update, _checkForUpdate),
            FutureBuilder<bool>(
              future: _shouldShowDistance(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return SizedBox.shrink();
                } else if (snapshot.hasData && snapshot.data == true) {
                  return FutureBuilder<double>(
                    future: _loadTotalDistance(),
                    builder: (context, distanceSnapshot) {
                      if (distanceSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return _buildInfoRow(Icons.directions_walk,
                            'Dist. recorrida', 'Cargando...');
                      } else if (distanceSnapshot.hasError) {
                        return _buildInfoRow(Icons.directions_walk,
                            'Dist. recorrida', 'Error al cargar');
                      } else {
                        return _buildInfoRow(
                            Icons.directions_walk,
                            'Dist. recorrida',
                            '${distanceSnapshot.data?.toStringAsFixed(2) ?? 0.0} mts.');
                      }
                    },
                  );
                } else {
                  return SizedBox.shrink();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRowWithButton(IconData icon, String title, String value,
      IconData buttonIcon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(buttonIcon, color: Colors.blueAccent),
            onPressed: onPressed,
          ),
        ],
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

  Widget _buildChangePasswordButton() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: _changePassword,
        icon: Icon(Icons.lock, color: Colors.blue),
        label: Text('Cambiar contraseña'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.blue,
          side: BorderSide(color: Colors.blue),
        ),
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
