import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/riogas_service.dart';
import '../services/firebase_constants_service.dart';
import '../services/session_service.dart';
import 'home_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _deviceId = 'Cargando...';
  String _appVersion = 'Versión desconocida';
  bool _isLoading = true;
  bool _isDeviceRegistered = true;
  List<String> _availableMoviles = [];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _deviceId = await AuthService.getDeviceId();
    _appVersion = await AuthService.getAppVersion();
    _isDeviceRegistered = await AuthService.validateDevice(_deviceId);
    setState(() => _isLoading = false);
  }

  Future<void> _login() async {
    var response = await RioGasService.validarUsuario(
      _usernameController.text,
      _passwordController.text,
      _deviceId,
    );

    if (response != null && response['OK'] == 0) {
      // 🔹 Extraer lista de móviles de la respuesta
      List<dynamic> listaMoviles = jsonDecode(response['ListaMoviles']);
      _availableMoviles = listaMoviles
          .map((movil) => movil['SDT_Mov_MovMat'].toString())
          .toList();

      if (_availableMoviles.isNotEmpty) {
        // 🔹 Mostrar selección de móviles antes de continuar
        await _showMobileSelectionDialog(response);
      } else {
        // Si no hay móviles disponibles, continuar directamente
        await _proceedAfterMobileSelection(response, null);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al iniciar sesión'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showMobileSelectionDialog(Map<String, dynamic> response) async {
    String? selectedMovil;
    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Text('Seleccionar Móvil'),
              content: isLoading
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 10),
                        Text('Guardando selección...'),
                      ],
                    )
                  : DropdownButton<String>(
                      hint: Text('Seleccione un móvil'),
                      value: selectedMovil,
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedMovil = newValue;
                        });
                      },
                      items: _availableMoviles
                          .map<DropdownMenuItem<String>>((String movil) {
                        return DropdownMenuItem<String>(
                          value: movil,
                          child: Text(movil),
                        );
                      }).toList(),
                    ),
              actions: <Widget>[
                if (!isLoading)
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                    child: Text('Cancelar'),
                  ),
                if (!isLoading)
                  ElevatedButton(
                    onPressed: () async {
                      if (selectedMovil != null) {
                        setState(() {
                          isLoading = true;
                        });

                        // 🔹 Guardar móvil seleccionado en Hive
                        var box = await Hive.openBox('sessionBox');
                        await box.put('movil', selectedMovil);

                        Navigator.of(dialogContext).pop();

                        // 🔹 Continuar con el flujo después de la selección del móvil
                        await _proceedAfterMobileSelection(
                            response, selectedMovil);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Seleccione un móvil.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    child: Text('Confirmar'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _proceedAfterMobileSelection(
      Map<String, dynamic> response, String? selectedMovil) async {
    _showLoadingDialog();

    // 🔹 Guardar en Hive los datos del usuario, pero SOLO EL MÓVIL SELECCIONADO
    var box = await Hive.openBox('sessionBox');
    await box.put('username', _usernameController.text);
    await box.put('escenario', response['EscenarioId']);
    await box.put('NombreUsuario', response['NombreUsuario'].trim());

    // 🔹 Cargar y guardar constantes desde Firebase
    await ConstantsService.loadAndSaveConstants();

    // 🔹 Obtener ubicación actual
    LatLng? currentLocation = await _getCurrentLocation();

    // 🔹 Guardar sesión en Firestore
    await _saveSession(currentLocation);

    // 🔹 Cerrar el diálogo de carga y navegar a HomePage
    Navigator.pop(context);
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (context) => HomePage()));
  }

  Future<void> _saveSession(LatLng? location) async {
    var box = await Hive.openBox('sessionBox');
    String? username = box.get('username');
    String? nombreUsuario = box.get('NombreUsuario');

    if (username != null && nombreUsuario != null) {
      await SessionService().saveSession(
        idUsuario: username,
        nomUsuario: nombreUsuario,
        primeraUbicacion: location ?? LatLng(0.0, 0.0),
        versionApp: _appVersion,
      );
    }
  }

  Future<LatLng?> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      print('Error al obtener la ubicación: $e');
      return null;
    }
  }

  Future<void> _showLoadingDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 10),
              Text('Cargando información...')
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text(
          'MOVEIT',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Container(
              height: MediaQuery.of(context).size.height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.blue, Colors.white],
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset('assets/logo.png'),
                            SizedBox(height: 20),
                            Image.asset(
                              'assets/garrafa.png',
                              width: 150,
                              height: 150,
                            ),
                            SizedBox(height: 20),
                            TextField(
                              controller: _usernameController,
                              decoration: InputDecoration(
                                labelText: 'Usuario',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person),
                              ),
                            ),
                            SizedBox(height: 10),
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.lock),
                              ),
                            ),
                            SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: _login,
                              child: Text('Iniciar sesión'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                    horizontal: 50, vertical: 15),
                                textStyle: TextStyle(fontSize: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
