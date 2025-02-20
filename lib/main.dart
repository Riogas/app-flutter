import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:hive/hive.dart';
import 'hive_init.dart';
import 'home_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google_maps;
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'session_service.dart'; // Importar el servicio de sesión
import 'package:geolocator/geolocator.dart';
import 'firebase_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Inicializar Hive
  final appDocumentDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDir.path);
  await Hive.openBox('sessionBox');

  // Verificar si hay datos en sessionBox
  var box = await Hive.openBox('sessionBox');
  bool isLoggedIn = box.get('username') != null && box.get('movil') != null;

  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;

  MyApp({required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoveIT',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: isLoggedIn ? HomePage() : LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _deviceIdController =
      TextEditingController(text: 'Cargando...');
  String deviceId = 'Cargando...';
  bool? _deviceExists; // Controla si el dispositivo ya está registrado
  int? _escenario; // Guarda el EscenarioId en sesión
  String _appVersion = 'Versión desconocida';
  final SessionService _sessionService = SessionService();
  final FirebaseService _firebaseService = FirebaseService();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _getDeviceId();
  }

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
    _getDeviceId(); // Llama automáticamente al obtener el Device ID
    _getAppVersion(); // Llama automáticamente al obtener la versión de la app
    _checkActiveSession();
  }

  Future<void> _checkLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Permisos de ubicación denegados. Por favor, actívelos para continuar.'),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Permisos de ubicación denegados permanentemente. Por favor, actívelos en la configuración.'),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }
  }

  Future<void> _getDeviceId() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String id;
    try {
      if (Theme.of(context).platform == TargetPlatform.android) {
        print('Obteniendo información del dispositivo Android...');
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        id = androidInfo.id; // Identificador único de Android
        print('ID de dispositivo Android: $id');
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        print('Obteniendo información del dispositivo iOS...');
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        id = iosInfo.identifierForVendor ??
            'Unknown Device'; // Identificador único de iOS
        print('ID de dispositivo iOS: $id');
      } else {
        id = 'Unknown Device';
        print('Plataforma desconocida');
      }
    } catch (e) {
      id = 'Error obteniendo Device ID';
      print('Error al obtener el ID del dispositivo: $e');
    }
    setState(() {
      deviceId = id;
      _deviceIdController.text = id;
    });

    // Guardar el ID del dispositivo en sessionBox
    var box = await Hive.openBox('sessionBox');
    await box.put('deviceId', id);
    print('ID de dispositivo guardado en sessionBox: $id');

    // Llama al servicio para validar el dispositivo
    await _validateDevice(id);
  }

  Future<void> _getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = 'Versión ${packageInfo.version}';
    });
  }

  Future<void> _validateDevice(String deviceId) async {
    print('Validando dispositivo con ID: $deviceId');
    try {
      final response = await http.post(
        Uri.parse(
            'https://www.riogas.uy/ica_geos_/appservices/ValidarDispositivo'),
        headers: {
          'accept': 'application/json',
          'Content-Type': 'application/json',
          'Cookie': 'GX_CLIENT_ID=3fc38cab-575b-44c7-af56-339c14d664f0',
        },
        body: jsonEncode({
          'token': 'IcA.FwL.1710.!',
          'DeviceId': deviceId,
        }),
      );

      print('Código de respuesta: ${response.statusCode}');
      print('Cuerpo de respuesta: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('Respuesta del servidor: $responseData');
        setState(() {
          _deviceExists = responseData['Existe'] ?? false; // True o False
          _escenario =
              responseData['EscenarioId']; // Guardar EscenarioId en sesión
        });
      } else {
        print('Error al validar el dispositivo: ${response.statusCode}');
        setState(() {
          _deviceExists = false; // Por defecto, si falla la validación
        });
      }
    } catch (e) {
      print('Error al validar el dispositivo: $e');
      setState(() {
        _deviceExists = false; // Por defecto, si ocurre un error
      });
    }
  }

  Future<void> _registerDevice(String document) async {
    try {
      final response = await http.post(
        Uri.parse(
            'https://www.riogas.uy/ica_geos_/appservices/RegistrarDispositivo'),
        headers: {
          'accept': 'application/json',
          'Content-Type': 'application/json',
          'Cookie': 'GX_CLIENT_ID=3fc38cab-575b-44c7-af56-339c14d664f0',
        },
        body: jsonEncode({
          'token': 'IcA.FwL.1710.!',
          'DeviceId': deviceId,
          'Documento':
              document, // Agrega el documento al cuerpo de la solicitud
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Dispositivo registrado con éxito.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          setState(() {
            _deviceExists = true; // Actualiza el estado para ocultar el botón
          });

          // Guardar el valor de "NombreUsuario" en sessionBox
          var box = await Hive.openBox('sessionBox');
          await box.put('NombreUsuario', responseData['NombreUsuario']);
          print(
              'NombreUsuario guardado en sessionBox: ${responseData['NombreUsuario']}');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  responseData['message'] ?? 'Error al registrar dispositivo.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        throw Exception(
            'Error al registrar dispositivo: ${response.statusCode}');
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

  Future<void> _login() async {
    final String username = _usernameController.text;
    final String password = _passwordController.text;

    try {
      print('Enviando solicitud de inicio de sesión...');
      print('Usuario: $username');
      print('Contraseña: $password');
      print('Device ID: $deviceId');

      final body = jsonEncode({
        'token': 'IcA.FwL.1710.!',
        'usuario': username,
        'password': password,
        'DeviceId': deviceId, // Agregar el Device ID al cuerpo del JSON
      });

      print('Cuerpo del JSON: $body');

      final response = await http.post(
        Uri.parse('https://www.riogas.uy/ica_geos_/appservices/ValidarUsuario'),
        headers: {
          'accept': 'application/json',
          'Content-Type': 'application/json',
          'Cookie': 'GX_CLIENT_ID=3fc38cab-575b-44c7-af56-339c14d664f0',
        },
        body: body,
      );

      print('Código de respuesta: ${response.statusCode}');
      print('Cuerpo de respuesta: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('Respuesta del servidor: $responseData');
        if (responseData['OK'] == 0) {
          print('Login exitoso. Cargando y guardando constantes...');
          await _loadAndSaveConstants(); // Cargar y guardar constantes

          // Decodificar la cadena JSON de 'ListaMoviles'
          print('Extrayendo matrículas de ListaMoviles...');
          List<dynamic> listaMovilesJson =
              jsonDecode(responseData['ListaMoviles']);
          List<String> listaMoviles = listaMovilesJson
              .map((movil) => movil['SDT_Mov_MovMat'].toString())
              .toList();
          print('Lista de móviles extraída: $listaMoviles');
          _showMobileSelectionDialog(listaMoviles, username);

          // Guardar EscenarioId y NombreUsuario en Hive
          print('Guardando EscenarioId y NombreUsuario en Hive...');
          var box = await Hive.openBox('sessionBox');
          await box.put('escenario', responseData['EscenarioId']);
          await box.put('NombreUsuario', responseData['NombreUsuario'].trim());
          print(
              'EscenarioId guardado en sesión: ${responseData['EscenarioId']}');
          print(
              'NombreUsuario guardado en sesión: ${responseData['NombreUsuario'].trim()}');

          //print('Guardando sesión...');
          //await _saveSession(username, responseData['selectedMovil']);
          print('Sesión guardada exitosamente.');
        } else {
          print('Error en login: ${responseData['message']}');
          _showErrorDialog(
              responseData['message'] ?? 'Usuario o contraseña incorrectos.');
        }
      } else {
        print('Código de respuesta: ${response.statusCode}');
        print('Cuerpo de respuesta: ${response.body}');
        _showErrorDialog(
            'Ocurrió un problema. Por favor, intente más tarde. Detalles: ${response.body}');
      }
    } catch (e) {
      print('Error en _login: $e');
      _showErrorDialog(
          'Ocurrió un problema. Por favor, intente más tarde. Detalles: $e');
    }
  }

  Future<void> _loadAndSaveConstants() async {
    try {
      QuerySnapshot querySnapshot =
          await FirebaseFirestore.instance.collection('Constantes-1000').get();
      var box = Hive.box('sessionBox');
      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data.forEach((key, value) {
          if (value is Timestamp) {
            data[key] = value.toDate();
          }
        });
        await box.put(doc.id, data);
      }
      print("✅ Constantes guardadas en Hive.");
    } catch (e) {
      print("❌ Error al cargar y guardar constantes: $e");
    }
  }

  void _showMobileSelectionDialog(List<String> listaMoviles, String username) {
    String? selectedMovil;
    bool isLoading = false; // Estado para controlar el indicador de carga

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Seleccionar Móvil'),
              content: isLoading
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 10),
                        const Text('Accediendo... Espere un momento'),
                      ],
                    )
                  : DropdownButton<String>(
                      hint: const Text('Seleccione un móvil'),
                      value: selectedMovil,
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedMovil = newValue;
                        });
                      },
                      items: listaMoviles
                          .map<DropdownMenuItem<String>>((String movil) {
                        return DropdownMenuItem<String>(
                          value: movil,
                          child: Text(movil),
                        );
                      }).toList(),
                    ),
              actions: <Widget>[
                if (!isLoading) // Ocultar botones cuando está cargando
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop(); // Cierra el diálogo
                    },
                    child: const Text('Cancelar'),
                  ),
                if (!isLoading)
                  ElevatedButton(
                    onPressed: () async {
                      if (selectedMovil != null) {
                        setState(() {
                          isLoading = true; // Muestra el indicador de carga
                        });

                        await _saveUserData(
                            username, selectedMovil!, _escenario.toString());

                        Future.delayed(Duration.zero, () {
                          if (mounted) {
                            Navigator.of(dialogContext)
                                .pop(); // Oculta el diálogo de selección
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => HomePage()),
                            );
                          }
                        });
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Por favor, seleccione un móvil.'),
                            backgroundColor: Colors.red,
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
      },
    );
  }

  Future<void> _saveUserData(
      String username, String movil, String escenario) async {
    try {
      var box = await Hive.openBox('sessionBox');
      await box.put('username', username);
      await box.put('movil', movil);
      await box.put('escenario', escenario);
      print('Sesión guardada con los siguientes valores:');
      print('Username: $username');
      print('Movil: $movil');
      print('Escenario: $escenario');
    } catch (e) {
      print('Error al guardar los datos del usuario: $e');
    }
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
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

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveSession(String? idUsuario, String? nomUsuario) async {
    print('_SaveSession');
    try {
      // Verifica que los valores no sean null antes de asignarlos
      final String safeIdUsuario = idUsuario ?? "Desconocido";
      final String safeNomUsuario = nomUsuario ?? "Desconocido";
      final String safeVersionApp = _appVersion ?? "Versión desconocida";

      // Valor por defecto para la ubicación
      LatLng currentLocation = LatLng(0.0, 0.0);

      try {
        // Obtener ubicación con timeout
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(Duration(seconds: 2), onTimeout: () {
          throw TimeoutException('Timeout al obtener la ubicación');
        });
        currentLocation = LatLng(position.latitude, position.longitude);
      } catch (e) {
        print('Error al obtener ubicación: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Error al obtener ubicación. Verifique los permisos.'),
            backgroundColor: Colors.red,
          ),
        );
      }

      print('Guardando sesión con los siguientes datos:');
      print('ID Usuario: $safeIdUsuario');
      print('Nombre Usuario: $safeNomUsuario');
      print('Primera Ubicación: $currentLocation');
      print('Versión de la App: $safeVersionApp');

      await _sessionService.saveSession(
        idUsuario: safeIdUsuario,
        nomUsuario: safeNomUsuario,
        primeraUbicacion: currentLocation,
        versionApp: safeVersionApp,
      );
    } catch (e) {
      print('Error al guardar la sesión: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al guardar la sesión.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _checkActiveSession() async {
    await for (var _ in _firebaseService.getSesionesStream()) {
      var box = await Hive.openBox('sessionBox');
      if (box.get('username') != null && box.get('movil') != null) {
        print('Sesión activa encontrada en sessionBox.');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomePage()),
        );
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue, // Fondo azul
        title: Text(
          'RIOGAS', // Título del AppBar
          style: TextStyle(
            color: Colors.white, // Texto en blanco
            fontWeight: FontWeight.bold, // Negrita para destacarlo
            fontSize: 20, // Tamaño de fuente ajustable
          ),
        ),
        centerTitle: true, // Centrar el título
      ),
      body: Container(
        height: MediaQuery.of(context)
            .size
            .height, // Ocupa toda la altura de la pantalla
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue, Colors.white],
          ),
        ),
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
                  width: 150, // Cambia el ancho según lo que prefieras
                  height: 150, // Cambia la altura según lo que prefieras
                ),
                SizedBox(height: 20),
                TextField(
                  controller: _deviceIdController,
                  decoration: InputDecoration(
                    labelText: 'Device ID',
                  ),
                  enabled: false,
                ),
                SizedBox(height: 20),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Usuario',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _login,
                  child: const Text('Iniciar sesión'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 50, vertical: 15),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(height: 20),
                if (_deviceExists ==
                    false) // Mostrar si el dispositivo no existe
                  ElevatedButton(
                    onPressed: () => _showRegisterDeviceDialog(),
                    child: const Text('Registrar Dispositivo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 50, vertical: 15),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  _appVersion,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
