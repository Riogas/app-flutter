import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart'; // Importa HiveFlutter
import 'utils/firebase_options.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'services/auth_service.dart';
import 'services/notifications_service.dart';
import 'services/riogas_service.dart';
import 'package:url_launcher/url_launcher.dart'; // Importa url_launcher
import 'utils/error_event.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 🔹 Inicializa Hive antes de cualquier acceso a Hive.openBox()
  await Hive.initFlutter();
  Hive.registerAdapter(ErrorEventAdapter());
  await Hive.openBox('sessionBox');
  await Hive.openBox<ErrorEvent>('errorBox');

  await NotificationsService.initialize();

  bool isLoggedIn = await AuthService.checkIsLoggedIn();

  // 🔹 Validar la versión de la aplicación
  await _validateAppVersion();

  runApp(MyApp(isLoggedIn: isLoggedIn));
}

Future<void> _validateAppVersion() async {
  String appVersion = await AuthService.getAppVersion();
  String deviceId = await AuthService.getDeviceId();

  var response = await RioGasService.validarVersion(appVersion, deviceId);

  if (response != null) {
    if (response['OK'] == 1) {
      _showMessage(response['message']);
    } else if (response['OK'] == 2) {
      _showUpdateDialog(response['message'], response['link']);
    }
  }
}

void _showMessage(String message) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    showDialog(
      context: navigatorKey.currentContext!,
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

void _showUpdateDialog(String message, String link) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    showDialog(
      context: navigatorKey.currentContext!,
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
                try {
                  final Uri url = Uri.parse(link);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    _showMessage('No se pudo abrir el enlace $link');
                  }
                } catch (e) {
                  print('Error al intentar abrir el enlace: $e');
                  _showMessage('Error al intentar abrir el enlace: $e');
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

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  MyApp({required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoveIT',
      theme: ThemeData(primarySwatch: Colors.blue),
      navigatorKey: navigatorKey,
      home: isLoggedIn ? HomePage() : LoginPage(),
    );
  }
}
