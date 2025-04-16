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
import 'package:sms_autofill/sms_autofill.dart';
import 'dart:math';

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

      // Establecer bandera para logout controlado
      sessionBox.put('logoutControlled', true);

      // Llamar al servicio RegistrarCierre antes de cerrar sesión
      await RioGasService.registrarCierre(
          int.tryParse(movil ?? '0') ?? 0,
          deviceId ?? '',
          idUsuario ?? '',
          DateTime.now().toIso8601String(),
          'Controlado');

      // Buscar y manejar el documento activo para el móvil y el usuario
      String escenarioId = sessionBox.get('escenario', defaultValue: '0');
      String movilId = sessionBox.get('movil', defaultValue: '0');
      String fechaActualStr = DateTime.now()
          .toUtc()
          .subtract(Duration(hours: 3))
          .toIso8601String()
          .split('T')[0]
          .replaceAll('-', '');

      DocumentReference fechaDocRef = FirebaseFirestore.instance
          .collection('Sesiones-$escenarioId')
          .doc(fechaActualStr);
      DocumentReference movilActivoDocRef =
          fechaDocRef.collection('Movil-$movilId').doc('activo');
      DocumentReference usuarioActivoDocRef =
          fechaDocRef.collection('Usuario-$idUsuario').doc('activo');

      try {
        // Manejar el documento activo del móvil
        DocumentSnapshot activeDocSnapshot = await movilActivoDocRef.get();
        if (activeDocSnapshot.exists) {
          var activeData = activeDocSnapshot.data() as Map<String, dynamic>;

          // Agregar el campo "logout" con el valor "Controlado"
          activeData['logout'] = 'Controlado';

          // Crear una copia del documento "activo" con el nombre basado en la hora actual
          String horaActual =
              DateTime.now().toIso8601String().split('T')[1].split('.')[0];
          DocumentReference backupDocRef =
              fechaDocRef.collection('Movil-$movilId').doc(horaActual);
          await backupDocRef.set(activeData);

          // Eliminar el documento "activo"
          await movilActivoDocRef.delete();
        }

        // Manejar el documento activo del usuario
        DocumentSnapshot usuarioDocSnapshot = await usuarioActivoDocRef.get();
        if (usuarioDocSnapshot.exists) {
          var usuarioData = usuarioDocSnapshot.data() as Map<String, dynamic>;

          // Agregar el campo "logout" con el valor "Controlado"
          usuarioData['logout'] = 'Controlado';

          // Crear una copia del documento "activo" con el nombre basado en la hora actual
          String horaActual =
              DateTime.now().toIso8601String().split('T')[1].split('.')[0];
          DocumentReference usuarioBackupDocRef =
              fechaDocRef.collection('Usuario-$idUsuario').doc(horaActual);
          await usuarioBackupDocRef.set(usuarioData);

          // Eliminar el documento "activo"
          await usuarioActivoDocRef.delete();
        }
      } catch (e) {
        print('Error al manejar los documentos activos: $e');
      }

      // Llamar a SessionService para eliminar el documento activo y crear una copia
      SessionService sessionService = SessionService();
      await sessionService.saveSession(
        idUsuario: idUsuario!,
        nomUsuario: nombreUsuario!,
        primeraUbicacion: LatLng(
          0,
          0,
        ), // Reemplaza con la ubicación real si es necesario
        versionApp: '1.0.0', // Reemplaza con la versión real de la app
        tipoDeCierreDeSesion: 'logoutUser',
      );

      // Eliminar los datos de sesión de Hive
      await sessionBox.deleteFromDisk();
      await constantBox.deleteFromDisk();
      await mensajesBox.deleteFromDisk();

      // Navegar a la pantalla de inicio de sesión
      Future.microtask(() {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (context) => LoginPage()));
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
            '¿Está seguro que desea cerrar sesión y salir de la aplicación?',
          ),
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
    TextEditingController currentPasswordController = TextEditingController();
    TextEditingController newPasswordController = TextEditingController();
    TextEditingController confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Cambiar Contraseña'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordController,
                decoration: InputDecoration(labelText: 'Contraseña Actual'),
                obscureText: true,
              ),
              TextField(
                controller: newPasswordController,
                decoration: InputDecoration(labelText: 'Nueva Contraseña'),
                obscureText: true,
              ),
              TextField(
                controller: confirmPasswordController,
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
                if (currentPasswordController.text.isEmpty ||
                    newPasswordController.text.isEmpty ||
                    confirmPasswordController.text.isEmpty) {
                  Navigator.of(context).pop();
                  _showMessage('Error: Todos los campos son obligatorios.');
                  return;
                }

                if (newPasswordController.text !=
                    confirmPasswordController.text) {
                  Navigator.of(context).pop();
                  _showMessage('Error: Las contraseñas no coinciden.');
                  return;
                }

                var box = await Hive.openBox('sessionBox');
                String? nombreUsuario = box.get('username');
                if (nombreUsuario != null) {
                  await RioGasService.cambioPassword(
                    nombreUsuario,
                    currentPasswordController.text,
                    newPasswordController.text,
                  );
                  Navigator.of(context).pop();
                } else {
                  Navigator.of(context).pop();
                  _showMessage('Error: NombreUsuario no encontrado.');
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
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Center(child: CircularProgressIndicator());
        },
      );

      try {
        // Split the selectedDate into components
        int year = selectedDate.year;
        int month = selectedDate.month;
        int day = selectedDate.day;
        int hour = selectedDate.hour;
        int minutes = selectedDate.minute;
        int seconds = selectedDate.second;

        var box = await Hive.openBox('sessionBox');
        String idUsuario = box.get('username');
        String deviceId = box.get('deviceId');
        String escenarioId = box.get('escenario', defaultValue: '0');
        String movil = box.get('movil');

        // Log the data being sent to the console
        print('Datos enviados a downloadAndOpenPDF:');
        print('Año: $year, Mes: $month, Día: $day');
        print('Hora: $hour, Minutos: $minutes, Segundos: $seconds');
        print('Usuario: $idUsuario, Equipo: $deviceId');
        print(
            'Agencia ID: 0, Escenario ID: ${int.tryParse(escenarioId) ?? 0}, Móvil ID: ${int.tryParse(movil) ?? 0}');

        // Call the function to download and open the PDF
        await RioGasService.downloadAndOpenPDF(
          year: year,
          month: month,
          day: day,
          hour: hour,
          minutes: minutes,
          seconds: seconds,
          usuMobileLogin: idUsuario ?? '',
          termMobileEquipo: deviceId ?? '',
          agenciaId: 0,
          escenarioId: int.tryParse(escenarioId) ?? 0,
          movilId: int.tryParse(movil) ?? 0,
        );

        // print('Fecha seleccionada para el reporte: $selectedDate');
      } catch (e) {
        _showMessage('Error al generar el reporte: $e');
      } finally {
        // Dismiss loading indicator
        Navigator.of(context).pop();
      }
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
        _showUpdateDialog(response['message'], response['link']);
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
            child: Text(
              releaseNotes ?? 'No hay notas de la versión disponibles.',
            ),
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

    // print('Contenido completo de errorBox (clave -> valor):');
    // print(errorBox.toMap());

    // Sort errors by timestamp in descending order
    errors.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    String? supportEmail = await getConstantValue(
      '90',
    ); // Fetch email from constant

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
                String sanitizedPayload = error.payload?.replaceAll(
                      '"token": "IcA.FwL.1710.!"',
                      '"token": "I************!"',
                    ) ??
                    "N/A";
                return ListTile(
                  title: Text('${error.type}: ${error.message}'),
                  subtitle: Text(
                    'Fecha: ${error.timestamp}\n'
                    'Info Adicional: ${error.additionalInfo ?? "N/A"}\n'
                    'Endpoint: ${error.endpoint ?? "N/A"}\n'
                    'Payload: $sanitizedPayload',
                  ),
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
    List<ErrorEvent> errors,
    String supportEmail,
  ) async {
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
      // print('Temporary directory: $directory');
      // print('File path: $filePath');

      // Escribir contenido en el archivo
      final file = File(filePath);
      await file.writeAsString(content);
      // print('File written successfully.');

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
      // print('Email sent successfully.');
    } catch (e) {
      // print('Error during _sendErrorsToSupport: $e');
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

  Future<void> _changePhoneNumber() async {
    TextEditingController phoneController = TextEditingController();
    TextEditingController otpController1 = TextEditingController();
    TextEditingController otpController2 = TextEditingController();
    TextEditingController otpController3 = TextEditingController();
    TextEditingController otpController4 = TextEditingController();
    bool isWaitingForOtp = false;
    int countdown = 30;

    final appSignature = await SmsAutoFill().getAppSignature;
    SmsAutoFill().listenForCode();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Text('Cambiar Número de Teléfono'),
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
                        Text('Ingrese su nuevo número de teléfono'),
                        TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
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
                              // print('🔄 OTP reenviado.');
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
                        // print('✅ OTP enviado exitosamente.');
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
                            // print(
                            //   '✅ OTP auto-completado y validado: $receivedCode',
                            // );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Número actualizado correctamente',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              Navigator.of(context).pop();
                            }
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
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Número actualizado correctamente'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          Navigator.of(context).pop();
                        }
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Código OTP incorrecto.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
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

    SmsAutoFill().unregisterListener();
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

  Widget _buildChangePhoneNumberButton() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: _changePhoneNumber,
        icon: Icon(Icons.phone, color: Colors.blue),
        label: Text('Cambiar número de teléfono'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.blue,
          side: BorderSide(color: Colors.blue),
        ),
      ),
    );
  }

  Widget _buildSuggestionsButton() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: () async {
          String supportEmail = await getConstantValue('90') ??
              ''; // Fetch email from constant or use default
          final Uri emailUri = Uri(
            scheme: 'mailto',
            path: supportEmail,
            query: 'subject=Sugerencias de Mejora',
          );
          if (await canLaunchUrl(emailUri)) {
            await launchUrl(emailUri);
          } else {
            _showMessage('No se pudo abrir la aplicación de correo.');
          }
        },
        icon: Icon(Icons.lightbulb, color: Colors.green),
        label: Text('Sugerencias'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.green,
          side: BorderSide(color: Colors.green),
        ),
      ),
    );
  }

  Widget _buildViewErrorsButton() {
    return FutureBuilder<String?>(
      future: getConstantValue('130'), // Fetch constant value
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox.shrink(); // Show nothing while loading
        }
        if (snapshot.hasData && snapshot.data == 'S') {
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
        return SizedBox
            .shrink(); // Show nothing if "Ver Errores" is not visible
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
              _buildChangePhoneNumberButton(),
              SizedBox(height: 10),
              _buildSuggestionsButton(), // Ensure only one suggestions button
              SizedBox(height: 10),
              _buildViewErrorsButton(),
              SizedBox(height: 10),
              _buildLogoutButton(),
              SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                if (idUsuario != null)
                  Text(
                    'ID de Usuario: $idUsuario',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (movil != null)
              _buildInfoRow(Icons.local_shipping, 'Móvil', movil!),
            if (deviceId != null)
              _buildInfoRow(
                Icons.devices,
                'DeviceID',
                deviceId!,
                isLongText: true,
              ),
            if (releaseNotes != null)
              GestureDetector(
                onTap: _showReleaseNotesDialog,
                child: _buildInfoRow(
                  Icons.info_outline,
                  'Notas de la Versión',
                  'Mas Info',
                  isLongText: true,
                ),
              ),
            _buildInfoRowWithButton(
              Icons.check_circle,
              'Pedidos Finalizados',
              '$subCompletedOrdersCount/$completedOrdersCount',
              Icons.description,
              _generateReport,
            ),
            _buildInfoRowWithButton(
              Icons.verified,
              'Versión de la App',
              appVersion,
              Icons.update,
              _checkForUpdate,
            ),
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
                        return _buildInfoRow(
                          Icons.directions_walk,
                          'Dist. recorrida',
                          'Cargando...',
                        );
                      } else if (distanceSnapshot.hasError) {
                        return _buildInfoRow(
                          Icons.directions_walk,
                          'Dist. recorrida',
                          'Error al cargar',
                        );
                      } else {
                        return _buildInfoRow(
                          Icons.directions_walk,
                          'Dist. recorrida',
                          '${distanceSnapshot.data?.toStringAsFixed(2) ?? 0.0} mts.',
                        );
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

  Widget _buildInfoRowWithButton(
    IconData icon,
    String title,
    String value,
    IconData buttonIcon,
    VoidCallback onPressed,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.blueAccent),
          SizedBox(width: 10),
          Text(
            '$title: ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
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

  Widget _buildInfoRow(
    IconData icon,
    String title,
    String value, {
    bool isLongText = false,
  }) {
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
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
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
