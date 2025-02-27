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
import 'package:cloud_firestore/cloud_firestore.dart';

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
  bool _wasActiveSessionForAnotherUser = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _deviceId = await AuthService.getDeviceId();
    print("Device ID iniciado: $_deviceId");
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

    print("Antes del login");

    if (response != null && response['OK'] == 0) {
      // 🔹 Extraer lista de móviles de la respuesta
      List<dynamic> listaMoviles = jsonDecode(response['ListaMoviles']);
      _availableMoviles = listaMoviles
          .map((movil) => movil['SDT_Mov_MovMat'].toString())
          .toList();

      if (_availableMoviles.isNotEmpty) {
        print("Mostrar selección de móviles antes de continuar");
        // 🔹 Mostrar selección de móviles antes de continuar
        await _showMobileSelectionDialog(response);
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

    print("Mostrar diálogo de selección de móviles");

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

                        print("Continuar luego de seleccionado un movil");

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
    print("Proceder después de seleccionar un móvil");
    _showLoadingDialog();

    print("Antes de guardar en hive");

    // 🔹 Guardar en Hive los datos del usuario, pero SOLO EL MÓVIL SELECCIONADO
    var box = await Hive.openBox('sessionBox');
    await box.put('username', _usernameController.text);
    await box.put('escenario', response['EscenarioId']);
    await box.put('NombreUsuario', response['NombreUsuario'].trim());
    await box.put('deviceId', _deviceId);

    // 🔹 Guardar que es un login manual para evitar el logout forzado inmediato
    await box.put('firstLoginDone', true);
    await box.flush(); // ✅ Asegura que el valor se escriba inmediatamente

    // 🔹 Imprimir el contenido de sessionBox después de asegurarnos que se guardó correctamente
    print("📦 Contenido de sessionBox después de guardar firstLoginDone:");
    box.toMap().forEach((key, value) => print('$key: $value'));

    // 🔹 Verificar si existe un documento "activo" con un idUsuario o idTerminal diferente
    bool shouldProceed = await _checkActiveSession(response, selectedMovil);

    if (shouldProceed) {
      // 🔹 Cargar y guardar constantes desde Firebase
      print("Cargando y guardando constantes desde Firebase...");
      await ConstantsService.loadAndSaveConstants();

      // 🔹 Obtener ubicación actual
      LatLng? currentLocation = await _getCurrentLocation();

      // 🔹 Guardar sesión en Firestore
      await _saveSession(currentLocation);

      // 🔹 Cerrar el diálogo de carga y navegar a HomePage
      Navigator.pop(context);
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (context) => HomePage()));
    } else {
      // 🔹 Cargar y guardar constantes desde Firebase
      print("Cargando y guardando constantes desde Firebase...");
      await ConstantsService.loadAndSaveConstants();

      // 🔹 Cerrar el diálogo de carga
      Navigator.pop(context);
    }
  }

  Future<bool> _checkActiveSession(
      Map<String, dynamic> response, String? selectedMovil) async {
    var box = await Hive.openBox('sessionBox');
    String? escenario = box.get('escenario');
    String? idUsuario = box.get('username');
    String? idTerminal = box.get('deviceId');
    String? nombreUsuario = box.get('NombreUsuario');

    // Verificar si hay datos en sessionBox
    if (escenario == null ||
        idUsuario == null ||
        idTerminal == null ||
        nombreUsuario == null) {
      return false;
    }

    DocumentReference ultimaDocRef = FirebaseFirestore.instance
        .collection('Sesiones-$escenario')
        .doc(DateTime.now().toIso8601String().split('T')[0].replaceAll('-', ''))
        .collection('Movil-$selectedMovil')
        .doc('activo');

    DocumentSnapshot activeDocSnapshot = await ultimaDocRef.get();

    if (activeDocSnapshot.exists) {
      var data = activeDocSnapshot.data() as Map<String, dynamic>;
      if (data['idUsuario'] != idUsuario || data['idTerminal'] != idTerminal) {
        _wasActiveSessionForAnotherUser = true;
        bool shouldProceed =
            await _showActiveSessionDialog(selectedMovil!, data['nomUsuario']);
        return shouldProceed;
      }
    }
    return true;
  }

  Future<bool> _showActiveSessionDialog(
      String selectedMovil, String activeUser) async {
    bool shouldProceed = false;
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Sesión Activa Encontrada'),
          content: Text(
              'Usted se está intentando conectar al móvil $selectedMovil, en el cual está logueado el usuario $activeUser. ¿Desea continuar?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                shouldProceed = true;
                Navigator.of(context).pop();
              },
              child: Text('Confirmar'),
            ),
          ],
        );
      },
    );
    return shouldProceed;
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
        tipoDeCierreDeSesion:
            _wasActiveSessionForAnotherUser ? 'logoutForzadoPorOtroLogin' : '',
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

  void _showRegisterDeviceDialog() {
    final TextEditingController _documentController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Registrar Dispositivo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Por favor, ingrese su documento de identidad.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _documentController,
                decoration: const InputDecoration(
                  labelText: 'Documento',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Cierra el diálogo
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final document = _documentController.text.trim();
                if (document.isNotEmpty) {
                  Navigator.of(context).pop(); // Cierra el diálogo
                  await _registerDevice(
                      document); // Llama a la función con el documento
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor, ingrese un documento válido.'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _registerDevice(String document) async {
    try {
      final response =
          await RioGasService.registrarDispositivo(_deviceId, document);

      if (response != null && response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dispositivo registrado con éxito.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        setState(() {
          _isDeviceRegistered = true;
        });

        var box = await Hive.openBox('sessionBox');
        await box.put('NombreUsuario', response['NombreUsuario']);
        print(
            'NombreUsuario guardado en sessionBox: ${response['NombreUsuario']}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(response?['message'] ?? 'Error al registrar dispositivo.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error al registrar dispositivo: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al registrar dispositivo.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
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
                            Image.asset('assets/logo-riogas.png'),
                            SizedBox(height: 20),
                            Image.asset(
                              'assets/logomoveit.png',
                              width: 150,
                              height: 150,
                            ),
                            SizedBox(height: 20),
                            Text(
                              'Device ID: $_deviceId',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.black,
                              ),
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
                            SizedBox(height: 20),
                            if (!_isDeviceRegistered)
                              ElevatedButton(
                                onPressed: () => _showRegisterDeviceDialog(),
                                child: Text('Registrar Dispositivo'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey,
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
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      _appVersion,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
