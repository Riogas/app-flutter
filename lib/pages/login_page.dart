import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/riogas_service.dart';
import '../services/firebase_constants_service.dart';
import '../services/session_service.dart';
import '../services/debug_config_manager.dart'; // 🆕 Sistema de logging remoto
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
import 'package:firebase_messaging/firebase_messaging.dart'; // <-- Add this import
import '../utils/config.dart'; // Import Config class
import '../utils/constantes.dart'; // Import Constants class
import 'package:local_auth/local_auth.dart'; // Import local_auth package
import 'package:flutter/services.dart'; // Import for MethodChannel
import 'package:permission_handler/permission_handler.dart'; // Import permission_handler package
import 'package:path_provider/path_provider.dart'; // Import for getTemporaryDirectory
import 'package:open_file/open_file.dart'; // Import for OpenFile
import 'package:dio/dio.dart'; // Import for Dio HTTP client
import 'package:video_player/video_player.dart';
import '../utils/stream_manager.dart';
import '../services/persistent_stream_manager.dart';

const String kLoginFlowTag = "[LOGIN_FLOW]";

class LoginBackground extends StatefulWidget {
  final Widget child;

  const LoginBackground({super.key, required this.child});

  @override
  State<LoginBackground> createState() => _LoginBackgroundState();
}

class _LoginBackgroundState extends State<LoginBackground> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.asset('assets/back_video.mp4')
      ..initialize().then((_) {
        setState(() {});
        _controller.setLooping(true);
        _controller.setVolume(0.0); // sin sonido
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _controller.value.isInitialized
            ? FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              )
            : Container(color: Colors.black),
        Container(
          color: Colors.black.withOpacity(0.3), // capa oscura encima opcional
        ),
        widget.child,
      ],
    );
  }
}

class ShinyButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String text;

  const ShinyButton({
    Key? key,
    required this.onPressed,
    required this.text,
  }) : super(key: key);

  @override
  State<ShinyButton> createState() => _ShinyButtonState();
}

class _ShinyButtonState extends State<ShinyButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(); // ← Repite infinito

    _progress = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = const Color(0xFFB34700); // Naranja oscuro elegante

    return AnimatedBuilder(
      animation: _progress,
      builder: (context, child) {
        return Stack(
          children: [
            ElevatedButton(
              onPressed: widget.onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: baseColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                textStyle:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(40),
                ),
                elevation: 8,
              ),
              child: Text(widget.text),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: CustomPaint(
                    painter: _DiagonalSheenPainter(progress: _progress.value),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DiagonalSheenPainter extends CustomPainter {
  final double progress;

  _DiagonalSheenPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    final gradient = LinearGradient(
      begin: Alignment(-1.0 + progress, 1.0 - progress),
      end: Alignment(1.0 + progress, -1.0 - progress),
      colors: [
        Colors.transparent,
        Colors.white.withOpacity(0.3),
        Colors.transparent,
      ],
      stops: const [0.4, 0.5, 0.6],
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..blendMode = BlendMode.lighten;

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _DiagonalSheenPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class LoginPage extends StatefulWidget {
  final bool forcedLogout;
  final String? forcedLogoutMessage;
  final String? movil;

  const LoginPage({
    Key? key,
    this.forcedLogout = false,
    this.forcedLogoutMessage,
    this.movil,
  }) : super(key: key);

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
  bool _isLoginButtonLoading = false; // Add this line

  @override
  void initState() {
    super.initState();
    _loadLastUsername(); // Load the last username from Hive
    _initialize();

    if (widget.forcedLogout) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _handleForcedLogoutAndShowDialog();
      });
    }
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

  Future<void> _handleForcedLogoutAndShowDialog() async {
    try {
      //final movil = int.tryParse(widget.movil ?? '0') ?? 0;

      Box? box;
      if (Hive.isBoxOpen('sessionBox')) {
        box = Hive.box('sessionBox');
      } else {
        box = await Hive.openBox('sessionBox');
      }
      final deviceId = box.get('deviceId');
      final idUsuario = box.get('username');
      final escenario = box.get('escenario') ?? "0";
      final usuario = box.get('username') ?? "string";
      final idTerminal = box.get('deviceId');
      final movil = box.get('movil') ?? 0;

      final platform = MethodChannel("background_service");
      await platform.invokeMethod("stopLocationService", {
        "movil": movil.toString(),
        "escenario": escenario,
        "usuario": usuario,
        "deviceId": idTerminal.toString(),
      });

      print("🛑 Servicio de ubicación detenido y notificación eliminada.");

      await RioGasService.registrarCierre(
        movil,
        deviceId ?? '',
        idUsuario ?? '',
        DateTime.now().toIso8601String(),
        'DeslogueoForzado',
      );

      // Limpiar cajas abiertas de forma segura
      if (box.isOpen) await box.clear();

      if (Hive.isBoxOpen('mensajesBox')) {
        await Hive.box('mensajesBox').clear();
      } else {
        await Hive.openBox('mensajesBox').then((b) => b.clear());
      }

      await _cancelStreams();

      // Eliminar disco solo si sigue abierto
      if (box.isOpen) await box.deleteFromDisk();

      if (mounted) {
        _showForcedLogoutDialog(
          mensaje: widget.forcedLogoutMessage ??
              'Su sesión ha sido cerrada. Por favor, inicie sesión nuevamente.',
        );
      }
    } catch (e) {
      print('❌ Error durante limpieza por deslogueo forzado: $e');
    }
  }

  void _showForcedLogoutDialog({required String mensaje}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Deslogueo forzado'),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Cierra el diálogo
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => LoginPage()),
                (_) => false,
              );
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelStreams() async {
    await cancelAllStreams(); // Esto cancela los streams externos que ya tenías
    PersistentStreamManager().dispose(); // 🔥 Cancela los persistentes
    print('🔴 Todos los streams cancelados.');
  }

  Future<void> _login() async {
    if (_isLoginButtonLoading) return;
    setState(() {
      _isLoginButtonLoading = true;
    });
    try {
      print("🔘 Se presionó el botón de login");

      // 🔔 SOLICITAR PERMISO DE NOTIFICACIONES
      NotificationSettings settings =
          await FirebaseMessaging.instance.requestPermission();

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        print("❌ Permiso de notificaciones denegado.");
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.notDetermined) {
        print("⚠️ Permiso de notificaciones no determinado.");
      } else {
        print("✅ Permiso de notificaciones otorgado.");

        try {
          String? token = await FirebaseMessaging.instance.getToken();
          print('📲 Token FCM: $token');
        } catch (e) {
          print('❌ Error al obtener token FCM: $e');
        }
      }

      var response = await RioGasService.validarUsuario(
        _usernameController.text,
        _passwordController.text,
        _deviceId,
        _appNroVersion,
      );

      var failedRequestsBox = await Hive.openBox('failedRequestsBox');

      await failedRequestsBox.deleteFromDisk();

      print("Antes del login");

      if (response != null && response['OK'] == 99) {
        //Poner loading de descarga y desconectar hives

        var sessionBox = await Hive.openBox('sessionBox');
        var constantBox = await Hive.openBox('constantBox');
        var mensajesBox = await Hive.openBox('mensajesBox'); // Open mensajesBox
        var descargaLecturaPedidosBox =
            await Hive.openBox('descargaLecturaPedidosBox');

        // Borramos completamente el box del disco
        await descargaLecturaPedidosBox.deleteFromDisk();

        // Eliminar los datos de sesión de Hive
        await sessionBox.deleteFromDisk();
        await constantBox.deleteFromDisk();
        await mensajesBox.deleteFromDisk();

        _validateAppVersion();
      } else {
        if (response != null && response['OK'] == 0) {
          print("✅ Login exitoso. Verificando dispositivo...");

          var descargaLecturaPedidosBox =
              await Hive.openBox('descargaLecturaPedidosBox');

          // Borramos completamente el box del disco
          await descargaLecturaPedidosBox.deleteFromDisk();

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
              print(
                  "📲 Usuario aceptó registrar el dispositivo. Registrando...");
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
            print(
                "📋 Móviles disponibles para seleccionar: $_availableMoviles");
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
              print(
                  "📲 Usuario aceptó registrar el dispositivo. Registrando...");
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
    } finally {
      setState(() {
        _isLoginButtonLoading = false;
      });
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

                        // 🆕 Guardar móvil en SharedPreferences nativo (Android) para CriticalLogger
                        try {
                          const platform =
                              MethodChannel('com.riogas.appmovil/shared_prefs');
                          await platform.invokeMethod(
                              'saveMovil', {'movil': selectedMovil});
                          print(
                              '✅ Móvil guardado en SharedPreferences nativo: $selectedMovil');
                        } catch (e) {
                          print(
                              '⚠️ Error guardando móvil en SharedPreferences nativo: $e');
                          // Enviar error a Android para que CriticalLogger lo registre
                          try {
                            const platform = MethodChannel(
                                'com.riogas.appmovil/shared_prefs');
                            await platform
                                .invokeMethod('criticalLogFromFlutter', {
                              'type': 'SharedPreferencesError',
                              'movil': selectedMovil ?? 'unknown',
                              'error': e.toString(),
                              'context':
                                  'Error guardando móvil en SharedPreferences desde Flutter (login_page)',
                            });
                            print(
                                '✅ Error enviado a CriticalLogger en Android');
                          } catch (err) {
                            print(
                                '⚠️ Error enviando log crítico a Android: $err');
                          }
                        }

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

  Future<void> autoLogin() async {
    Map<String, String> credentials = await generateCredentials();

    String email = credentials['email']!;
    String password = credentials['password']!;

    await registerOrReuseUser(email, password);

    print("🟢 Login exitoso como $email");
  }

  Future<Map<String, String>> generateCredentials() async {
    String deviceId = await AuthService.getDeviceId();

    print("Device ID para credenciales: $deviceId");

    // Normalizá el ID (sin símbolos raros)
    String sanitized = deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');

    String email = 'android-$sanitized@riogas.com.uy';
    String password = 'P@ss${sanitized}#${sanitized.length}';

    return {
      'email': email,
      'password': password,
    };
  }

  Future<String> getDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id;
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'unknown_ios';
    } else {
      return 'unknown_device';
    }
  }

  Future<void> _proceedAfterMobileSelection(
    Map<String, dynamic> response,
    String? selectedMovil,
  ) async {
    print("[32m$kLoginFlowTag Proceder después de seleccionar un móvil[0m");
    _showLoadingDialog();

    print("[32m$kLoginFlowTag Antes de guardar en hive[0m");

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
      print(
          "[32m$kLoginFlowTag ✅ Servicio registrarUltLog llamado exitosamente.[0m");
    } else {
      print(
          "[31m$kLoginFlowTag ⚠️ No se pudo llamar a registrarUltLog: username o deviceId es null.[0m");
      print(
          "[31m$kLoginFlowTag username: $username, deviceId: $_deviceId, selectedMovil: $selectedMovil[0m");
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
          "[32m$kLoginFlowTag ?? ReleaseNotes guardado en sessionBox: ${versionData['ReleaseNotes']}[0m");
    }

    // 🔹 Imprimir el contenido de sessionBox después de asegurarnos que se guardó correctamente
    print(
        "[32m$kLoginFlowTag 📦 Contenido de sessionBox después de guardar firstLoginDone:[0m");
    box
        .toMap()
        .forEach((key, value) => print("[32m$kLoginFlowTag $key: $value[0m"));

    // 🔹 Intentar login automático con credenciales globales
    bool success = await _autoLogin(context);

    if (success) {
      print("[32m$kLoginFlowTag 🟢 Login automático exitoso.[0m");

      // 🔹 Obtener ubicación actual
      LatLng? currentLocation = await _getCurrentLocation();

      // 🔹 Guardar sesión en Firestore
      final sessionResult = await _saveSession(currentLocation);

      print(
          "[32m$kLoginFlowTag Guardando sesión en Firestore: $sessionResult[0m");

      if (sessionResult != null && sessionResult['success']) {
        await _onSuccessfulLoginFlow(context);
      } else {
        print(
            "[31m$kLoginFlowTag ❌ Error al guardar la sesión en Firestore.[0m");

        bool shouldProceed = await _showActiveSessionDialog(
            sessionResult != null ? sessionResult['message'] : null);

        print("[33m$kLoginFlowTag shouldProceed: $shouldProceed[0m");
        if (shouldProceed) {
          print(
              "[33m$kLoginFlowTag Usuario decidió continuar, moviendo activo al histórico[0m");
          // 🔹 Mover el activo al historico
          var sessionBox = await Hive.openBox('sessionBox');
          String? username = sessionBox.get('username');
          String? nombreUsuario = sessionBox.get('NombreUsuario');
          String? versionApp = _appVersion;
          LatLng? currentLocation = await _getCurrentLocation();
          print(
              "[33m$kLoginFlowTag username: $username, nombreUsuario: $nombreUsuario, versionApp: $versionApp, currentLocation: $currentLocation[0m");
          if (username != null && nombreUsuario != null) {
            print("[33m$kLoginFlowTag Llamando a setHistory[0m");
            final result = await SessionService().setHistory(
              idUsuario: username,
              nomUsuario: nombreUsuario,
              primeraUbicacion: currentLocation ?? LatLng(0.0, 0.0),
              versionApp: versionApp,
              tipoDeCierreDeSesion: 'logoutForzado',
              fchHoraCierre: DateTime.now(),
            );

            print("[33m$kLoginFlowTag Resultado de setHistory: $result[0m");
            if (result != null && result['success'] == true) {
              print(
                  "\u001b[32m$kLoginFlowTag ✅ Activo movido al histórico correctamente.\u001b[0m");
              await _onSuccessfulLoginFlow(context);
              return;
            } else {
              // Manejar el caso en que no se pudo mover el activo al histórico
              print(
                  "\u001b[31m$kLoginFlowTag ❌ No se pudo mover el activo al histórico.\u001b[0m");
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      "$kLoginFlowTag Ocurrió un error inesperado, favor intente nuevamente más tarde."),
                ),
              );
            }
          } else {
            print(
                "[31m$kLoginFlowTag ❌ Datos insuficientes para mover al histórico[0m");
          }
        } else {
          print("[33m$kLoginFlowTag Usuario decidió NO continuar[0m");
        }

        // 🔹 Cargar y guardar constantes desde Firebase
        print(
            "[33m$kLoginFlowTag Cargando y guardando constantes desde Firebase...[0m");
        await ConstantsService.loadAndSaveConstants();

        // 🔹 Cerrar el diálogo de carga
        print("[33m$kLoginFlowTag Cerrando diálogo de carga[0m");
        Navigator.pop(context);
      }
    } else {
      print("[31m$kLoginFlowTag 🔴 Error en el login automático.[0m");
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

  double _downloadProgress = 0.0;

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
                  if (await Permission.requestInstallPackages.isDenied) {
                    final status =
                        await Permission.requestInstallPackages.request();
                    if (!status.isGranted) {
                      _showMessage(
                          'No se puede continuar sin el permiso para instalar paquetes.');
                      return;
                    }
                  }

                  double progress = 0.0;
                  late StateSetter dialogSetState;

                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (BuildContext context) {
                      return StatefulBuilder(
                        builder: (context, setState) {
                          dialogSetState = setState;
                          return AlertDialog(
                            title: Text('Descargando actualización...'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                LinearProgressIndicator(value: progress),
                                SizedBox(height: 16),
                                Text(
                                  'Descarga: ${(progress * 100).toStringAsFixed(0)}%',
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );

                  try {
                    final tempDir = await getTemporaryDirectory();
                    final filePath = '${tempDir.path}/app_update.apk';

                    Dio dio = Dio();
                    await dio.download(
                      link,
                      filePath,
                      onReceiveProgress: (received, total) {
                        if (total != -1) {
                          final newProgress = received / total;
                          dialogSetState(() {
                            progress = newProgress;
                          });
                        }
                      },
                    );

                    Navigator.of(context)
                        .pop(); // Cierra el diálogo de progreso

                    // 🆕 Usar instalador nativo en lugar de OpenFile para evitar "error de paquetes"
                    try {
                      const platform = MethodChannel('apk_installer');
                      final result = await platform.invokeMethod('installApk', {
                        'filePath': filePath,
                      });

                      print('✅ APK enviado al instalador nativo: $result');

                      // Limpiar sesión antes de cerrar la app (la actualización reiniciará la app)
                      var box = await Hive.openBox('sessionBox');
                      box.clear();

                      // Informar al usuario que la instalación comenzó
                      _showMessage(
                          'Instalación iniciada. La app se reiniciará al completar.');
                    } on PlatformException catch (e) {
                      print('❌ Error en instalador nativo: ${e.message}');

                      // Fallback: Intentar con OpenFile (método anterior)
                      final result = await OpenFile.open(filePath);

                      var box = await Hive.openBox('sessionBox');
                      box.clear();

                      if (result.type != ResultType.done) {
                        _showMessage(
                            'No se pudo abrir el archivo descargado. Error: ${e.message}');
                      }
                    }
                  } catch (e) {
                    Navigator.of(context)
                        .pop(); // Cierra el diálogo de progreso
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

  Future<bool> _autoLogin(BuildContext context) async {
    // ✅ CREACIÓN O VALIDACIÓN DE DISPOSITIVO EN FIRESTORE
    try {
      await autoLogin();
      print("✅ Dispositivo validado");
    } catch (e) {
      print("❌ Error durante la validación del dispositivo: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al validar el dispositivo.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    // 🔐 Autenticación con Firestore
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: Config.firestoreEmail,
        password: Config.firestorePassword,
      );
      print('✅ Autenticación con Firestore exitosa.');
      return true;
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
  }

  Future<bool> _showActiveSessionDialog(String contentText) async {
    bool shouldProceed = false;

    String title = 'Sesión Activa Encontrada';

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(contentText),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Cancela
              },
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                shouldProceed = true;
                Navigator.of(context).pop(); // Confirma
              },
              child: Text('Confirmar'),
            ),
          ],
        );
      },
    );

    return shouldProceed;
  }

  Future<Map<String, dynamic>?> _saveSession(LatLng? location) async {
    var box = await Hive.openBox('sessionBox');
    String? username = box.get('username');
    String? nombreUsuario = box.get('NombreUsuario');

    if (username != null && nombreUsuario != null) {
      final result = await SessionService().saveSession(
        idUsuario: username,
        nomUsuario: nombreUsuario,
        primeraUbicacion: location ?? LatLng(0.0, 0.0),
        versionApp: _appVersion,
        tipoDeCierreDeSesion:
            _wasActiveSessionForAnotherUser ? 'logoutForzadoPorOtroLogin' : '',
      );
      return result;
    }
    return null;
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
    // 🆕 Inicializar sistema de logging remoto
    try {
      final sessionBox = await Hive.openBox('sessionBox');
      final movil = sessionBox.get('movil') ?? "0";

      await DebugConfigManager.startListening(movil);
      print(
          '✅ [DEBUG_CONFIG] Sistema de logging remoto iniciado para móvil $movil');
    } catch (e) {
      print('⚠️ [DEBUG_CONFIG] Error iniciando logging remoto: $e');
      // No bloqueamos el login si falla esto
    }

    // Verificar si las notificaciones están habilitadas
    if (await Permission.notification.isGranted) {
      // Si están habilitadas, navegar a HomePage
      PersistentStreamManager().reset(); // Reinicia todo el estado
      await PersistentStreamManager().initialize(); // Relanza listeners

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

  /// Ejecuta la carga de constantes, inicialización de servicios y navegación tras login exitoso
  Future<void> _onSuccessfulLoginFlow(BuildContext context) async {
    // 🔹 Cargar y guardar constantes desde Firebase
    print("Cargando y guardando constantes desde Firebase...");
    await ConstantsService.loadAndSaveConstants();

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
      PersistentStreamManager().reset(); // Reinicia todo el estado
      await PersistentStreamManager().initialize(); // Relanza listeners

      Navigator.pop(context);
    }
    await _checkNotificationPermissionAndNavigate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : LoginBackground(
              child: Column(
                children: [
                  SizedBox(height: 5), // Margen superior igual a AppBar
                  Expanded(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(1.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.network(
                              'https://www.riogas.uy/ica_geos_/static/Resources/RGDelivery.png',
                              width: 250,
                              height: 250,
                            ),
                            SizedBox(height: 1),
                            TextField(
                              controller: _usernameController,
                              style: TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.transparent,
                                labelText: 'Usuario',
                                labelStyle: TextStyle(color: Colors.white),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.white),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.white),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.white),
                                ),
                                prefixIcon:
                                    Icon(Icons.person, color: Colors.white),
                              ),
                            ),
                            SizedBox(height: 10),
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              style: TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.transparent,
                                labelText: 'Contraseña',
                                labelStyle: TextStyle(color: Colors.white),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.white),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.white),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.white),
                                ),
                                prefixIcon:
                                    Icon(Icons.lock, color: Colors.white),
                              ),
                            ),
                            SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed:
                                    _isLoginButtonLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  textStyle: TextStyle(fontSize: 18),
                                ),
                                child: _isLoginButtonLoading
                                    ? SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text('Iniciar sesión'),
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
                    child: SafeArea(
                      child: Stack(
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'ID: $_deviceId',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
