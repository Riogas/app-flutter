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
import 'dart:math'; // Add this import for random number generation
import 'package:sms_autofill/sms_autofill.dart'; // Import SmsAutoFill package
import 'package:firebase_auth/firebase_auth.dart'; // Import FirebaseAuth package
import '../utils/config.dart'; // Import Config class
import '../utils/constantes.dart'; // Import Constants class
import 'package:local_auth/local_auth.dart'; // Import local_auth package
import 'package:flutter/services.dart'; // Import for MethodChannel
import 'package:permission_handler/permission_handler.dart'; // Import permission_handler package
import 'package:path_provider/path_provider.dart'; // Import for getTemporaryDirectory
import 'package:open_file/open_file.dart'; // Import for OpenFile
import 'package:dio/dio.dart'; // Import for Dio HTTP client

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
  List<Map<String, String>> _availableMoviles = [];
  bool _wasActiveSessionForAnotherUser = false;
  String _phoneNumber = ''; // Global variable to store the phone number
  TextEditingController licensePlateController =
      TextEditingController(); // New controller for license plate

  @override
  void initState() {
    super.initState();
    _loadLastUsername(); // Load the last username from Hive
    _initialize();
  }

  Future<void> _loadLastUsername() async {
    print('📦 Abriendo caja Hive: usuarioBox...');
    var usuarioBox = await Hive.openBox('usuarioBox');

    print('🔍 Buscando clave "lastUsername"...');
    String? lastUsername = usuarioBox.get('lastUsername');

    if (lastUsername != null) {
      print('✅ Se encontró lastUsername: $lastUsername');
      _usernameController.text = lastUsername;
    } else {
      print('⚠️ No se encontró ningún lastUsername guardado.');
    }
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
      _appNroVersion,
    );

    print("Antes del login");

    if (response != null && response['OK'] == 99) {
      _validateAppVersion();
    } else {
      if (response != null && response['OK'] == 0) {
        print("✅ Login exitoso. Verificando dispositivo...");

        // Save the last logged-in username in Hive
        var usuarioBox = await Hive.openBox('usuarioBox');
        await usuarioBox.put('lastUsername', _usernameController.text);
        print(
            '✅ Se guardó el último nombre de usuario: ${_usernameController.text}');
/*
        // Verificar si el campo "huella" no está configurado
        final LocalAuthentication auth = LocalAuthentication();
        bool isBiometricAvailable = await auth.isDeviceSupported();
        if (usuarioBox.get('huella') == null && isBiometricAvailable) {
          print(
              "🔐 Huella no configurada. Mostrando diálogo para habilitar huella.");
          bool shouldEnableFingerprint = await _showEnableFingerprintDialog();
          if (shouldEnableFingerprint) {
            print("🔐 Usuario aceptó habilitar huella.");
            await _configureFingerprintAuthentication();

            // Verificar nuevamente si la huella fue configurada correctamente
            if (usuarioBox.get('huella') != true) {
              print('❌ Configuración de huella fallida. Deteniendo flujo.');
              return; // Detener el flujo si la configuración falla
            }
          }
        }
*/
        // Si el campo "huella" está configurado en true, solicitar autenticación con huella
        if (usuarioBox.get('huella') == true) {
          bool isAuthenticated = await _authenticateWithFingerprint();
          if (!isAuthenticated) {
            print("❌ Autenticación con huella fallida.");
            return; // Detener el flujo de inicio de sesión
          }
        }

        // 🔹 Validar dispositivo antes de mostrar selección de móviles
        bool isDeviceValid = await _validateDevice();
        print(
          "🔍 Validación de dispositivo: ${isDeviceValid ? '✅ Válido' : '❌ Inválido'}",
        );

        if (!isDeviceValid) {
          print(
              "🚨 Dispositivo no registrado. Mostrando diálogo de registro...");
          bool shouldRegister = await _showRegisterDeviceDialog();

          if (shouldRegister) {
            print("📲 Usuario aceptó registrar el dispositivo. Registrando...");
            bool registrationSuccess = await _registerDevice(
              _usernameController.text,
            );

            if (registrationSuccess) {
              var box = await Hive.openBox('sessionBox');
              String habilitado = box.get('Habilitado', defaultValue: 'N');

              if (habilitado == 'N') {
                print(
                  "✅ Dispositivo registrado con éxito. Esperando aprobación...",
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Su dispositivo fue registrado con éxito. Actualmente se encuentra en espera de aprobación por la agencia.',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
                return; // Volver al login
              } else {
                print("📥 Extrayendo lista de móviles...");
                _availableMoviles = _extractAvailableMoviles(response);

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
        _availableMoviles = _extractAvailableMoviles(response);

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
          "🔍 Validación de dispositivo: ${isDeviceValid ? '✅ Válido' : '❌ Inválido'}",
        );

        if (!isDeviceValid) {
          print(
              "🚨 Dispositivo no registrado. Mostrando diálogo de registro...");
          bool shouldRegister = await _showRegisterDeviceDialog();

          if (shouldRegister) {
            print("📲 Usuario aceptó registrar el dispositivo. Registrando...");
            bool registrationSuccess = await _registerDevice(
              _usernameController.text,
            );

            if (registrationSuccess) {
              var box = await Hive.openBox('sessionBox');
              String habilitado = box.get('Habilitado', defaultValue: 'N');

              if (habilitado == 'N') {
                print(
                  "✅ Dispositivo registrado con éxito. Esperando aprobación...",
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Su dispositivo fue registrado con éxito. Actualmente se encuentra en espera de aprobación por la agencia.',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
                return; // Volver al login
              } else {
                var response = await RioGasService.validarUsuario(
                  _usernameController.text,
                  _passwordController.text,
                  _deviceId,
                  _appNroVersion,
                );

                print("Antes del login");

                if (response != null && response['OK'] == 0) {
                  print("✅ Login exitoso. Verificando dispositivo...");

                  // 🔹 Validar dispositivo antes de mostrar selección de móviles
                  bool isDeviceValid = await _validateDevice();
                  print(
                    "🔍 Validación de dispositivo: ${isDeviceValid ? '✅ Válido' : '❌ Inválido'}",
                  );

                  // 🔹 Extraer lista de móviles de la respuesta
                  print("📥 Extrayendo lista de móviles...");
                  _availableMoviles = _extractAvailableMoviles(response);

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
              'En este momento no es posible comunicarse con los servidores de RioGas. Favor intente más tarde.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      } else if (response != null &&
          response['OK'] > 0 &&
          response['OK'] != 9) {
        String errorMessage = response['message'] ?? 'Error desconocido';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      } else if (response != null && response.containsKey('error')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(response['error']), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<bool> _validateDevice() async {
    _isDeviceRegistered = await AuthService.validateDevice(_deviceId);
    return _isDeviceRegistered;
  }

  Future<bool> _showRegisterDeviceDialog() async {
    bool shouldRegister = false;
    TextEditingController phoneController = TextEditingController();
    TextEditingController otpController1 = TextEditingController();
    TextEditingController otpController2 = TextEditingController();
    TextEditingController otpController3 = TextEditingController();
    TextEditingController otpController4 = TextEditingController();
    bool isWaitingForOtp = false;
    int countdown = 30;

    final appSignature = await SmsAutoFill().getAppSignature;
    print("📲 App Signature: $appSignature");

    // Escucha del SMS con el código
    SmsAutoFill().listenForCode();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Text('Registrar Dispositivo'),
              content: isWaitingForOtp
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Ingrese el código OTP enviado a su teléfono'),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildOtpField(otpController1),
                            _buildOtpField(otpController2),
                            _buildOtpField(otpController3),
                            _buildOtpField(otpController4),
                          ],
                        ),
                        SizedBox(height: 10),
                        Text(
                          countdown > 0
                              ? 'Espere $countdown segundos para reenviar el código'
                              : '¿No recibió el código?',
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Ingrese su número de teléfono para continuar'),
                        TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          onChanged: (value) {
                            _phoneNumber =
                                value; // Save the phone number to the global variable
                          },
                          decoration: InputDecoration(
                            labelText: 'Número de Teléfono',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
              actions: <Widget>[
                if (!isWaitingForOtp)
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text('Cancelar'),
                  ),
                if (isWaitingForOtp)
                  TextButton(
                    onPressed: countdown == 0
                        ? () async {
                            // Reenviar OTP
                            int generatedOtp = Random().nextInt(9000) + 1000;
                            var otpBox = await Hive.openBox('OTPBOX');
                            await otpBox.put('generatedOtp', generatedOtp);

                            String phoneNumber = phoneController.text;
                            String smsText =
                                "Tu%20codigo%20de%20ingreso%20a%20MoveIT%20es%20$generatedOtp%20%20$appSignature";

                            var response = await RioGasService.enviarOTP(
                              int.parse(phoneNumber),
                              generatedOtp,
                              smsText,
                            );

                            if (response != null && response['OK'] == 0) {
                              print('🔄 OTP reenviado.');
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error al reenviar OTP.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }

                            setState(() {
                              countdown = 30;
                            });

                            for (int i = 0; i < 30; i++) {
                              await Future.delayed(Duration(seconds: 1));
                              if (!context.mounted) return;
                              setState(() {
                                countdown--;
                              });
                            }
                          }
                        : null,
                    child: Text('Reenviar Código'),
                  ),
                ElevatedButton(
                  onPressed: () async {
                    if (!isWaitingForOtp) {
                      int generatedOtp = Random().nextInt(9000) + 1000;
                      var otpBox = await Hive.openBox('OTPBOX');
                      await otpBox.put('generatedOtp', generatedOtp);

                      String phoneNumber = phoneController.text;
                      String smsText =
                          "Tu%20codigo%20de%20ingreso%20a%20MoveIT%20es%20$generatedOtp%20%20$appSignature";

                      var response = await RioGasService.enviarOTP(
                        int.parse(phoneNumber),
                        generatedOtp,
                        smsText,
                      );

                      if (response != null && response['OK'] == 0) {
                        print('✅ OTP enviado exitosamente.');
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error al enviar OTP.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setState(() {
                        isWaitingForOtp = true;
                        countdown = 30;
                      });

                      // Escuchar código
                      SmsAutoFill().code.listen((receivedCode) async {
                        if (receivedCode.length == 4) {
                          otpController1.text = receivedCode[0];
                          otpController2.text = receivedCode[1];
                          otpController3.text = receivedCode[2];
                          otpController4.text = receivedCode[3];

                          var otpBox = await Hive.openBox('OTPBOX');
                          String storedOtp =
                              otpBox.get('generatedOtp').toString();

                          if (receivedCode == storedOtp) {
                            print(
                              '✅ OTP auto-completado y validado: $receivedCode',
                            );
                            shouldRegister = true;
                            if (context.mounted) Navigator.of(context).pop();
                          }
                        }
                      });

                      for (int i = 0; i < 30; i++) {
                        await Future.delayed(Duration(seconds: 1));
                        if (!context.mounted) return;
                        setState(() {
                          countdown--;
                        });
                      }
                    } else {
                      String otp = otpController1.text +
                          otpController2.text +
                          otpController3.text +
                          otpController4.text;
                      var otpBox = await Hive.openBox('OTPBOX');
                      String storedOtp = otpBox.get('generatedOtp').toString();

                      if (otp.length == 4 && otp == storedOtp) {
                        shouldRegister = true;
                        Navigator.of(context).pop();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Código OTP incorrecto.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: Text(isWaitingForOtp ? 'Confirmar OTP' : 'Enviar OTP'),
                ),
              ],
            );
          },
        );
      },
    );

    SmsAutoFill().unregisterListener(); // detener escucha cuando se cierra

    return shouldRegister;
  }

  Widget _buildOtpField(TextEditingController controller) {
    return SizedBox(
      width: 40,
      child: TextField(
        controller: controller,
        maxLength: 1,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        readOnly: true, // Prevent manual input
        decoration: InputDecoration(
          counterText: '',
          border: OutlineInputBorder(),
        ),
      ),
    );
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

      final response = await RioGasService.registrarDispositivo(
        _deviceId,
        document,
        _appNroVersion,
        _phoneNumber,
        marca,
        modelo,
        '', // Do not send license plate in the info field
      );

      if (response != null && response['OK'] == 0) {
        var box = await Hive.openBox('sessionBox');
        await box.put('NombreUsuario', response['NombreUsuario']);
        await box.put('Habilitado', response['habilitar']);
        print(
          '✅ NombreUsuario guardado en sessionBox: ${response['NombreUsuario']}',
        );
        return true;
      } else {
        // 🔹 Si el servicio devuelve un mensaje de error, lo mostramos en el SnackBar
        String errorMessage = response?['message'] ??
            'Error desconocido al registrar el dispositivo';
        print("❌ Error en respuesta del servicio: $errorMessage");

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
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
    TextEditingController licensePlateController = TextEditingController();
    bool showLicensePlateField = false;

    // Fetch the constant value with ID 170
    String? value = await getConstantValue('180');
    if (value == 'S') {
      showLicensePlateField = true;
    }

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
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width:
                                      MediaQuery.of(context).size.width * 0.8,
                                  child: FutureBuilder(
                                    future: Hive.openBox('usuarioBox')
                                        .then((box) => box.get('movil')),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return CircularProgressIndicator();
                                      }

                                      String? defaultMovil =
                                          snapshot.data as String?;
                                      if (!_availableMoviles.any((movil) =>
                                          movil['id'] == defaultMovil)) {
                                        defaultMovil = null;
                                      }

                                      // Inicializar selectedMovil con el valor predeterminado si no está inicializado
                                      if (selectedMovil == null &&
                                          defaultMovil != null) {
                                        selectedMovil = defaultMovil;
                                      }

                                      return DropdownButton<String>(
                                        hint: Text('Seleccione móvil'),
                                        value: selectedMovil,
                                        onChanged: (String? newValue) {
                                          setState(() {
                                            selectedMovil = newValue;
                                          });
                                        },
                                        items: _availableMoviles
                                            .map<DropdownMenuItem<String>>(
                                                (movil) {
                                          return DropdownMenuItem<String>(
                                            value: movil['id'],
                                            child: Text(
                                                movil['displayValue'] ?? 'N/A'),
                                          );
                                        }).toList(),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (showLicensePlateField) ...[
                          SizedBox(height: 10),
                          TextField(
                            controller: licensePlateController,
                            keyboardType: TextInputType.text,
                            decoration: InputDecoration(
                              labelText: 'Matrícula del Vehículo',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ],
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
                      if (selectedMovil != null &&
                          (!showLicensePlateField ||
                              licensePlateController.text.isNotEmpty)) {
                        setState(() {
                          isLoading = true;
                        });

                        // 🔹 Guardar móvil seleccionado y matrícula en Hive
                        var userbox = await Hive.openBox('usuarioBox');
                        var box = await Hive.openBox('sessionBox');
                        await box.put('movil', selectedMovil);
                        await userbox.put('movil', selectedMovil);

                        String hoy = DateTime.now()
                            .toUtc()
                            .toIso8601String()
                            .split('T')[0]
                            .replaceAll('-', '');

                        await box.put('fecha', hoy);
                        if (showLicensePlateField) {
                          await box.put(
                              'matricula', licensePlateController.text);
                          await userbox.put(
                              'matricula', licensePlateController.text);
                        }

                        Navigator.of(dialogContext).pop();

                        print("Continuar luego de seleccionado un movil");

                        // 🔹 Continuar con el flujo después de la selección del móvil
                        await _proceedAfterMobileSelection(
                          response,
                          selectedMovil,
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Seleccione un móvil y complete la matrícula.'),
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
    Map<String, dynamic> response,
    String? selectedMovil,
  ) async {
    print("Proceder después de seleccionar un móvil");
    _showLoadingDialog();

    print("Antes de guardar en hive");

    // 🔹 Guardar en Hive los datos del usuario, pero SOLO EL MÓVIL SELECCIONADO
    var box = await Hive.openBox('sessionBox');
    await box.put('username', _usernameController.text);
    await box.put('password', _passwordController.text);
    await box.put(
      'escenario',
      response['escenarioid'] == "1000" ? "1000" : "2000",
    );
    await box.put('NombreUsuario', response['NombreUsuario'].trim());
    await box.put('deviceId', _deviceId);

    // 🔹 Guardar que es un login manual para evitar el logout forzado inmediato
    await box.put('firstLoginDone', true);

    var pedidosBox = await Hive.openBox('pedidosBox');

    // Call registrarUltLog after confirming the mobile selection
    var sessionBox = await Hive.openBox('sessionBox');
    String? username = sessionBox.get('username');
    String? deviceId = sessionBox.get('deviceId');

    if (username != null && deviceId != null) {
      await RioGasService.registrarUltLog(
          int.parse(selectedMovil!), _deviceId, username);
      print('✅ Servicio registrarUltLog llamado exitosamente.');
    } else {
      print(
          '⚠️ No se pudo llamar a registrarUltLog: username o deviceId es null.');
      print(
          'username: $username, deviceId: $_deviceId, selectedMovil: $selectedMovil');
    }

    // 🔹 Limpiar pedidosBox de claves cuyo valor sea 'Procesando'
    final keysToDelete = <dynamic>[];

    // Buscar las claves cuyos valores sean 'Procesando'
    for (var key in pedidosBox.keys) {
      final value = pedidosBox.get(key);
      if (value == 'Procesando') {
        keysToDelete.add(key);
      }
    }

    // Eliminar esas claves
    for (var key in keysToDelete) {
      await pedidosBox.delete(key);
    }

    // Obtener datos de la versión actual y guardar ReleaseNotes en Hive
    var versionData = await RioGasService.DatosVersionActual(
      _appVersion,
      _deviceId,
    );
    if (versionData != null && versionData.containsKey('ReleaseNotes')) {
      await box.put('ReleaseNotes', versionData['ReleaseNotes']);
      print(
        "?? ReleaseNotes guardado en sessionBox: ${versionData['ReleaseNotes']}",
      );
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

      final sessionBox = await Hive.openBox('sessionBox');
      final movil = sessionBox.get('movil') ?? "0";
      final escenario = sessionBox.get('escenario') ?? "0";
      final usuario = sessionBox.get('username') ?? "string";
      String? idTerminal = sessionBox.get('deviceId');

      final platform = MethodChannel("background_service");
      await platform.invokeMethod("startLocationService", {
        "interval": 3,
        "movil": movil,
        "escenario": escenario,
        "usuario": usuario,
        "deviceId": "$idTerminal",
      });
      print(
          "🔄 Servicio de ubicación en segundo plano iniciado con movil=$movil, escenario=$escenario, usuario=$usuario.");

      await platform.invokeMethod("FcmNotification", {
        "interval": 3,
        "movil": movil,
        "escenario": escenario,
        "usuario": usuario,
        "deviceId": "$idTerminal",
      });
      print(
          "🔄 Servicio de ubicación en segundo plano iniciado con movil=$movil, escenario=$escenario, usuario=$usuario.");

      // 🔹 Cerrar el diálogo de carga y navegar a HomePage
      if (mounted) {
        Navigator.pop(context);
      }
      await _checkNotificationPermissionAndNavigate();
    } else {
      // 🔹 Cargar y guardar constantes desde Firebase
      print("Cargando y guardando constantes desde Firebase...");
      await ConstantsService.loadAndSaveConstants();

      // 🔹 Cerrar el diálogo de carga
      Navigator.pop(context);
    }
  }

  Future<void> _validateAppVersion() async {
    String appVersion = await AuthService.getAppVersion();
    String deviceId = await AuthService.getDeviceId();

    var response = await RioGasService.validarVersion(appVersion, deviceId);

    if (response != null) {
      if (response['OK'] == 1) {
        _showMessage(response['message']);
      } else if (response['OK'] == 2) {
        bool isRequired =
            response['Requerida'] ?? false; // Obtiene el valor de 'Requerida'
        _showUpdateDialog(response['message'], response['link'], isRequired);
      }
    }
  }

  void _showMessage(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    });
  }

  void _showUpdateDialog(String message, String link, bool isRequired) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Actualización Requerida'),
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
                  print(
                      '🔄 Confirmación recibida. Iniciando proceso de actualización.');

                  // Solicitar permiso REQUEST_INSTALL_PACKAGES
                  if (await Permission.requestInstallPackages.isDenied) {
                    print(
                        '⚠️ Permiso REQUEST_INSTALL_PACKAGES denegado. Solicitando permiso.');
                    final status =
                        await Permission.requestInstallPackages.request();
                    if (!status.isGranted) {
                      print('❌ Permiso REQUEST_INSTALL_PACKAGES no concedido.');
                      _showMessage(
                          'No se puede continuar sin el permiso para instalar paquetes.');
                      return;
                    }
                  }

                  try {
                    // Mostrar indicador de progreso
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: Text('Descargando actualización...'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 20),
                              Text(
                                  'Por favor, espera mientras se descarga la actualización.')
                            ],
                          ),
                        );
                      },
                    );

                    // Descarga el archivo desde la URL
                    final tempDir = await getTemporaryDirectory();
                    final filePath = '${tempDir.path}/app_update.apk';

                    Dio dio = Dio();
                    await dio.download(link, filePath,
                        onReceiveProgress: (received, total) {
                      if (total != -1) {
                        print(
                            '📥 Progreso de descarga: ${(received / total * 100).toStringAsFixed(0)}%');
                      }
                    });

                    Navigator.of(context)
                        .pop(); // Cierra el diálogo de progreso

                    print(
                        '✅ Descarga completada. Archivo guardado en: $filePath');

                    // Abre el archivo descargado para instalarlo
                    final result = await OpenFile.open(filePath);

                    var box = await Hive.openBox('sessionBox');
                    box.clear(); // Limpia la caja de sesión al cerrar la app

                    if (result.type == ResultType.done) {
                      print('✅ Archivo abierto exitosamente.');
                    } else {
                      print(
                          '⚠️ No se pudo abrir el archivo descargado. Resultado: ${result.message}');
                      _showMessage('No se pudo abrir el archivo descargado.');
                    }
                  } catch (e) {
                    Navigator.of(context)
                        .pop(); // Cierra el diálogo de progreso en caso de error
                    print(
                        '❌ Error al intentar descargar o abrir el archivo: $e');
                    _showMessage(
                        'Error al intentar descargar o abrir el archivo: $e');
                  }
                },
                child: Text('Confirmar'),
              ),
            ],
          );
        },
      );
    });
  }

  Future<bool> _checkActiveSession(
    Map<String, dynamic> response,
    String? selectedMovil,
  ) async {
    print('📦 Abriendo caja Hive: sessionBox...');
    var box = await Hive.openBox('sessionBox');

    String? escenario = box.get('escenario')?.toString();
    String? idUsuario = box.get('username');
    String? idTerminal = box.get('deviceId');
    String? nombreUsuario = box.get('NombreUsuario');

    print('🔍 Datos recuperados de Hive:');
    print('   ➤ Escenario: $escenario');
    print('   ➤ Usuario: $idUsuario');
    print('   ➤ Terminal: $idTerminal');
    print('   ➤ NombreUsuario: $nombreUsuario');

    // Verificar si hay datos en sessionBox
    if (escenario == null ||
        idUsuario == null ||
        idTerminal == null ||
        nombreUsuario == null) {
      print(
        '⚠️ Falta información en sessionBox. No se puede validar sesión activa.',
      );
      return false;
    }

    // Authenticate with Firestore using credentials from Config
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: Config.firestoreEmail,
        password: Config.firestorePassword,
      );
      print('✅ Autenticación con Firestore exitosa.');
    } catch (e) {
      print('❌ Error al autenticar con Firestore: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al autenticar con Firestore.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    String hoy = DateTime.now()
        .toUtc()
        .toIso8601String()
        .split('T')[0]
        .replaceAll('-', '');
    String pathMovil =
        'Sesiones-$escenario / $hoy / Movil-$selectedMovil / activo';
    String pathUsuario =
        'Sesiones-$escenario / $hoy / Usuario-$idUsuario / activo';

    print('📄 Consultando documento Firestore: $pathMovil');

    DocumentReference ultimaDocRefMovil = FirebaseFirestore.instance
        .collection('Sesiones-$escenario')
        .doc(hoy)
        .collection('Movil-$selectedMovil')
        .doc('activo');

    DocumentReference ultimaDocRefUsuario = FirebaseFirestore.instance
        .collection('Sesiones-$escenario')
        .doc(hoy)
        .collection('Usuario-$idUsuario')
        .doc('activo');

    DocumentSnapshot activeDocSnapshotMovil;
    DocumentSnapshot activeDocSnapshotUsuario;

    try {
      activeDocSnapshotMovil = await ultimaDocRefMovil.get();
      print('✅ Documento Firestore de Movil obtenido correctamente.');
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
        print('❌ Error inesperado al acceder a Firestore: $e');
        rethrow;
      }
    }

    try {
      activeDocSnapshotUsuario = await ultimaDocRefUsuario.get();
      print('✅ Documento Firestore de Usuario obtenido correctamente.');
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
        print('❌ Error inesperado al acceder a Firestore: $e');
        rethrow;
      }
    }

    if (activeDocSnapshotMovil.exists) {
      var data = activeDocSnapshotMovil.data() as Map<String, dynamic>;
      if (data['idUsuario'] != idUsuario || data['idTerminal'] != idTerminal) {
        _wasActiveSessionForAnotherUser = true;
        bool shouldProceed = await _showActiveSessionDialog(
          selectedMovil!,
          data['nomUsuario'],
          'Usted se está intentando conectar al móvil $selectedMovil, en el cual está logueado el usuario ${data['nomUsuario']}. ¿Desea continuar?',
        );
        return shouldProceed;
      }
    }

    if (activeDocSnapshotUsuario.exists) {
      var data = activeDocSnapshotUsuario.data() as Map<String, dynamic>;
      _wasActiveSessionForAnotherUser = true;
      bool shouldProceed = await _showActiveSessionDialog(
        selectedMovil!,
        data['nomUsuario'],
        'Su usuario ya está logueado en el movil ${data['movil']}. ¿Desea continuar?',
      );
      return shouldProceed;
    }

    return true;
  }

  Future<bool> _showActiveSessionDialog(
    String selectedMovil,
    String activeUser,
    String contentText,
  ) async {
    bool shouldProceed = false;
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Sesión Activa Encontrada'),
          content: Text(contentText),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); //SERVICIO DE LIMPIEZA DE SESION
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
              Text('Cargando información...'),
            ],
          ),
        );
      },
    );
  }

  List<Map<String, String>> _extractAvailableMoviles(
      Map<String, dynamic> response) {
    print('📥 Iniciando extracción de móviles disponibles...');

    // Verificar si 'ListaMoviles' está presente en la respuesta
    List<dynamic> listaMoviles = response['ListaMoviles'] != null
        ? jsonDecode(response['ListaMoviles'])
        : [];
    print('🔍 Lista de móviles obtenida: $listaMoviles');
    print('🔍 Cantidad de móviles: ${response['escenarioid']}');

    // Mapear la lista de móviles a una lista de mapas con 'id' y 'displayValue'
    List<Map<String, String>> mappedMoviles = listaMoviles.map((movil) {
      String displayValue = response['escenarioid'] == "1000"
          ? movil['SDT_Mov_MovMat'].toString()
          : movil['DV_P_M_MOVDESCRIPCION'].toString();
      print(
          '🛠️ Procesando móvil: ID=${movil['SDT_Mov_MovId']}, DisplayValue=$displayValue');
      return {
        'id': movil['SDT_Mov_MovId'].toString(),
        'displayValue': displayValue
      };
    }).toList();

    print('✅ Mapeo de móviles completado: $mappedMoviles');
    return mappedMoviles;
  }

  Future<bool> _showEnableFingerprintDialog() async {
    bool shouldEnable = false;
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Habilitar Autenticación con Huella'),
          content: Text(
              '¿Desea habilitar la autenticación con huella dactilar para futuros inicios de sesión?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('No'),
            ),
            ElevatedButton(
              onPressed: () {
                shouldEnable = true;
                Navigator.of(context).pop();
              },
              child: Text('Sí'),
            ),
          ],
        );
      },
    );
    return shouldEnable;
  }

  Future<void> _configureFingerprintAuthentication() async {
    final LocalAuthentication auth = LocalAuthentication();
    var usuarioBox = await Hive.openBox('usuarioBox');

    print('📦 Abriendo caja Hive: usuarioBox...');

    try {
      // Verificar si el dispositivo soporta autenticación biométrica
      print(
          '🔍 Verificando si el dispositivo soporta autenticación biométrica...');
      bool canCheckBiometrics = await auth.canCheckBiometrics;
      print('✅ Soporte de biometría: $canCheckBiometrics');

      if (!canCheckBiometrics) {
        print('❌ El dispositivo no soporta autenticación biométrica.');
        return;
      }

      // Verificar si hay biometría disponible
      print('🔍 Verificando si hay biometría disponible en el dispositivo...');
      bool isBiometricAvailable = await auth.isDeviceSupported();
      print('✅ Biometría disponible: $isBiometricAvailable');

      if (!isBiometricAvailable) {
        print(
            '❌ La autenticación biométrica no está disponible en este dispositivo.');
        return;
      }

      // Intentar autenticar para configurar la huella digital
      print('🔐 Intentando autenticar para configurar la huella digital...');
      bool authenticated = await auth.authenticate(
        localizedReason:
            'Por favor autentíquese para configurar la huella digital',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      print('🔍 Resultado de la autenticación: $authenticated');

      if (authenticated) {
        print('✅ Autenticación exitosa. Guardando configuración en Hive...');
        await usuarioBox.put('huella', true);
        print('✅ Autenticación con huella habilitada en Hive.');
      } else {
        print('❌ Configuración de huella cancelada por el usuario.');
      }
    } catch (e) {
      print('❌ Error durante la configuración de huella: $e');
    }
  }

  Future<bool> _authenticateWithFingerprint() async {
    final LocalAuthentication auth = LocalAuthentication();

    try {
      // Verificar si el dispositivo soporta autenticación biométrica
      bool canCheckBiometrics = await auth.canCheckBiometrics;
      if (!canCheckBiometrics) {
        print('❌ El dispositivo no soporta autenticación biométrica.');
        return false;
      }

      // Verificar si hay biometría disponible
      bool isBiometricAvailable = await auth.isDeviceSupported();
      if (!isBiometricAvailable) {
        print(
            '❌ La autenticación biométrica no está disponible en este dispositivo.');
        return false;
      }

      // Intentar autenticar con huella dactilar
      bool authenticated = await auth.authenticate(
        localizedReason: 'Por favor autentíquese para continuar',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (authenticated) {
        print('✅ Autenticación con huella completada.');
        return true;
      } else {
        print('❌ Autenticación con huella fallida.');
        return false;
      }
    } catch (e) {
      print('❌ Error durante la autenticación con huella: $e');
      return false;
    }
  }

  Future<void> _checkNotificationPermissionAndNavigate() async {
    // Verificar si las notificaciones están habilitadas
    if (await Permission.notification.isGranted) {
      // Si están habilitadas, navegar a HomePage
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomePage()),
      );
    } else {
      // Mostrar diálogo para solicitar permisos
      bool shouldOpenSettings = await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Permisos de Notificación'),
            content: Text(
                'Para continuar, habilite las notificaciones en la configuración de la aplicación.'),
            actions: <Widget>[
              TextButton(
                child: Text('Cancelar'),
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
              ),
              ElevatedButton(
                child: Text('Configurar'),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        },
      );

      if (shouldOpenSettings == true) {
        // Abrir configuración de la aplicación
        await openAppSettings();
      }
    }
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
                            Image.network(
                              'https://www.riogas.uy/ica_geos_/static/Resources/LogoTransparente.png',
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
                                prefixIcon: Icon(
                                  Icons.person,
                                  color: Colors.black,
                                ),
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
                                prefixIcon: Icon(
                                  Icons.lock,
                                  color: Colors.black,
                                ),
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
                                  horizontal: 50,
                                  vertical: 15,
                                ),
                                textStyle: TextStyle(fontSize: 18),
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              _appVersion,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
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
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
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
