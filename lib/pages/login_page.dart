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
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _deviceId = 'Cargando...';
  String _appVersion = 'Versión desconocida';
  String _appNroVersion = '0.0.0';
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
    _appNroVersion = await AuthService.getAppVersionNro();
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
      print("✅ Login exitoso. Verificando dispositivo...");

      // 🔹 Validar dispositivo antes de mostrar selección de móviles
      bool isDeviceValid = await _validateDevice();
      print(
          "🔍 Validación de dispositivo: ${isDeviceValid ? '✅ Válido' : '❌ Inválido'}");

      if (!isDeviceValid) {
        print("🚨 Dispositivo no registrado. Mostrando diálogo de registro...");
        bool shouldRegister = await _showRegisterDeviceDialog();

        if (shouldRegister) {
          print("📲 Usuario aceptó registrar el dispositivo. Registrando...");
          bool registrationSuccess =
              await _registerDevice(_usernameController.text);

          if (registrationSuccess) {
            var box = await Hive.openBox('sessionBox');
            String habilitado = box.get('Habilitado', defaultValue: 'N');

            if (habilitado == 'N') {
              print(
                  "✅ Dispositivo registrado con éxito. Esperando aprobación...");
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Su dispositivo fue registrado con éxito. Actualmente se encuentra en espera de aprobación por la agencia.'),
                  backgroundColor: Colors.green,
                ),
              );
              return; // Volver al login
            } else {
              // 🔹 Extraer lista de móviles de la respuesta
              print("📥 Extrayendo lista de móviles...");
              List<dynamic> listaMoviles = response['ListaMoviles'] != null
                  ? jsonDecode(response['ListaMoviles'])
                  : [];
              _availableMoviles = listaMoviles
                  .map((movil) => movil['SDT_Mov_MovMat'].toString())
                  .toList();

              if (_availableMoviles.isNotEmpty) {
                print(
                    "📋 Móviles disponibles para seleccionar: $_availableMoviles");
                print(
                    "🛑 Mostrando selección de móviles antes de continuar...");

                // 🔹 Mostrar selección de móviles antes de continuar
                await _showMobileSelectionDialog(response);
              }
            }
          } else {
            print("❌ Error al registrar el dispositivo.");
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al registrar dispositivo.'),
                backgroundColor: Colors.red,
              ),
            );
            return; // Volver al login
          }
        } else {
          print("🔙 Usuario canceló el registro. Volviendo al login...");
          return; // Volver al login
        }
      }

      // 🔹 Extraer lista de móviles de la respuesta
      print("📥 Extrayendo lista de móviles...");
      List<dynamic> listaMoviles = response['ListaMoviles'] != null
          ? jsonDecode(response['ListaMoviles'])
          : [];
      _availableMoviles = listaMoviles
          .map((movil) => movil['SDT_Mov_MovMat'].toString())
          .toList();

      if (_availableMoviles.isNotEmpty) {
        print("📋 Móviles disponibles para seleccionar: $_availableMoviles");
        print("🛑 Mostrando selección de móviles antes de continuar...");

        // 🔹 Mostrar selección de móviles antes de continuar
        await _showMobileSelectionDialog(response);
      }
    } else if (response != null && response['OK'] == 9) {
      // 🔹 Validar dispositivo antes de mostrar selección de móviles
      bool isDeviceValid = await _validateDevice();
      print(
          "🔍 Validación de dispositivo: ${isDeviceValid ? '✅ Válido' : '❌ Inválido'}");

      if (!isDeviceValid) {
        print("🚨 Dispositivo no registrado. Mostrando diálogo de registro...");
        bool shouldRegister = await _showRegisterDeviceDialog();

        if (shouldRegister) {
          print("📲 Usuario aceptó registrar el dispositivo. Registrando...");
          bool registrationSuccess =
              await _registerDevice(_usernameController.text);

          if (registrationSuccess) {
            var box = await Hive.openBox('sessionBox');
            String habilitado = box.get('Habilitado', defaultValue: 'N');

            if (habilitado == 'N') {
              print(
                  "✅ Dispositivo registrado con éxito. Esperando aprobación...");
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Su dispositivo fue registrado con éxito. Actualmente se encuentra en espera de aprobación por la agencia.'),
                  backgroundColor: Colors.green,
                ),
              );
              return; // Volver al login
            } else {
              var response = await RioGasService.validarUsuario(
                _usernameController.text,
                _passwordController.text,
                _deviceId,
              );

              print("Antes del login");

              if (response != null && response['OK'] == 0) {
                print("✅ Login exitoso. Verificando dispositivo...");

                // 🔹 Validar dispositivo antes de mostrar selección de móviles
                bool isDeviceValid = await _validateDevice();
                print(
                    "🔍 Validación de dispositivo: ${isDeviceValid ? '✅ Válido' : '❌ Inválido'}");

                // 🔹 Extraer lista de móviles de la respuesta
                print("📥 Extrayendo lista de móviles...");
                List<dynamic> listaMoviles = response['ListaMoviles'] != null
                    ? jsonDecode(response['ListaMoviles'])
                    : [];
                _availableMoviles = listaMoviles
                    .map((movil) => movil['SDT_Mov_MovMat'].toString())
                    .toList();

                if (_availableMoviles.isNotEmpty) {
                  print(
                      "📋 Móviles disponibles para seleccionar: $_availableMoviles");
                  print(
                      "🛑 Mostrando selección de móviles antes de continuar...");

                  // 🔹 Mostrar selección de móviles antes de continuar
                  await _showMobileSelectionDialog(response);
                }
              }
            }
          } else {
            print("❌ Error al registrar el dispositivo.");
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al registrar dispositivo.'),
                backgroundColor: Colors.red,
              ),
            );
            return; // Volver al login
          }
        } else {
          print("🔙 Usuario canceló el registro. Volviendo al login...");
          return; // Volver al login
        }
      }
    } else if (response == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'En este momento no es posible comunicarse con los servidores de RioGas. Favor intente más tarde.'),
          backgroundColor: Colors.red,
        ),
      );
    } else if (response != null && response['OK'] > 0 && response['OK'] != 9) {
      String errorMessage = response['message'] ?? 'Error desconocido';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    } else if (response != null && response.containsKey('error')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['error']),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _validateDevice() async {
    _isDeviceRegistered = await AuthService.validateDevice(_deviceId);
    return _isDeviceRegistered;
  }

  Future<bool> _showRegisterDeviceDialog() async {
    bool shouldRegister = false;
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Dispositivo No Registrado'),
          content: Text(
              'Su dispositivo no se encuentra registrado en el sistema. ¿Desea registrarlo?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                shouldRegister = true;
                Navigator.of(context).pop();
              },
              child: Text('Registrar'),
            ),
          ],
        );
      },
    );
    return shouldRegister;
  }

  Future<Map<String, String>> obtenerMarcaYModelo() async {
    final deviceInfo = DeviceInfoPlugin();
    String marca = 'Desconocida';
    String modelo = 'Desconocido';

    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      marca = androidInfo.brand ?? 'Desconocida';
      modelo = androidInfo.model ?? 'Desconocido';
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      marca = 'Apple'; // siempre es Apple en iOS
      modelo = iosInfo.utsname.machine ?? 'Desconocido';
    }

    print('Marca: $marca');
    print('Modelo: $modelo');

    return {'marca': marca, 'modelo': modelo};
  }

  Future<bool> _registerDevice(String document) async {
    try {
      // Call obtenerMarcaYModelo to get the device brand and model
      Map<String, String> deviceInfo = await obtenerMarcaYModelo();
      String marca = deviceInfo['marca']!;
      String modelo = deviceInfo['modelo']!;
      String info = '';

      final response = await RioGasService.registrarDispositivo(
          _deviceId, document, _appNroVersion, marca, modelo, info);

      if (response != null && response['OK'] == 0) {
        var box = await Hive.openBox('sessionBox');
        await box.put('NombreUsuario', response['NombreUsuario']);
        await box.put('Habilitado', response['habilitar']);
        print(
            '✅ NombreUsuario guardado en sessionBox: ${response['NombreUsuario']}');
        return true;
      } else {
        // 🔹 Si el servicio devuelve un mensaje de error, lo mostramos en el SnackBar
        String errorMessage = response?['message'] ??
            'Error desconocido al registrar el dispositivo';
        print("❌ Error en respuesta del servicio: $errorMessage");

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }
    } catch (e) {
      print('❌ Excepción atrapada en _registerDevice: $e');

      // 🔹 Mostrar el mensaje de error en un SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error de conexión: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
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

    // Obtener datos de la versión actual y guardar ReleaseNotes en Hive
    var versionData =
        await RioGasService.DatosVersionActual(_appVersion, _deviceId);
    if (versionData != null && versionData.containsKey('ReleaseNotes')) {
      await box.put('ReleaseNotes', versionData['ReleaseNotes']);
      print(
          "?? ReleaseNotes guardado en sessionBox: ${versionData['ReleaseNotes']}");
    }

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

    DocumentSnapshot activeDocSnapshot;
    try {
      activeDocSnapshot = await ultimaDocRef.get();
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        print('❌ Error de permisos al acceder a Firestore: ${e.message}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de permisos al acceder a Firestore.'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      } else {
        rethrow;
      }
    }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text(
          '',
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
                            Image.asset(
                              'assets/logomoveit.png',
                              width: 150,
                              height: 150,
                            ),
                            SizedBox(height: 20),
                            SizedBox(height: 20),
                            TextField(
                              controller: _usernameController,
                              style: TextStyle(color: Colors.black),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.transparent,
                                labelText: 'Usuario',
                                labelStyle: TextStyle(color: Colors.black),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.black),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.black),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.black),
                                ),
                                prefixIcon:
                                    Icon(Icons.person, color: Colors.black),
                              ),
                            ),
                            SizedBox(height: 10),
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              style: TextStyle(color: Colors.black),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.transparent,
                                labelText: 'Contraseña',
                                labelStyle: TextStyle(color: Colors.black),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.black),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.black),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.black),
                                ),
                                prefixIcon:
                                    Icon(Icons.lock, color: Colors.black),
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
                            SizedBox(height: 10),
                            Text(
                              _appVersion,
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                            SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'ID: $_deviceId',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Image.asset(
                            'assets/logo-riogas.png',
                            width: 100,
                            height: 30,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
