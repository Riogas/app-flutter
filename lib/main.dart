import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart'; // Importa HiveFlutter
import 'package:firebase_messaging/firebase_messaging.dart'; // Importa firebase_messaging
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Importa flutter_local_notifications
import 'package:device_info_plus/device_info_plus.dart'; // Importa device_info_plus
import 'package:battery_plus/battery_plus.dart'; // Importa battery_plus
import 'utils/firebase_options.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'services/auth_service.dart';
import 'services/notifications_service.dart';
import 'services/riogas_service.dart';
import 'package:url_launcher/url_launcher.dart'; // Importa url_launcher
import 'utils/error_event.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:io'; // Importa dart:io para usar Platform
import 'package:connectivity_plus/connectivity_plus.dart'; // Importa connectivity_plus
import 'package:http/http.dart'
    as http; // Importa http para realizar solicitudes HTTP
import 'package:cloud_firestore/cloud_firestore.dart'; // Importa cloud_firestore para usar Firestore

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 🔹 Verificar conectividad a Internet
  await _checkInternetConnectivity();

  // 🔹 Inicializa Hive antes de cualquier acceso a Hive.openBox()
  await Hive.initFlutter();
  Hive.registerAdapter(ErrorEventAdapter());
  await Hive.openBox('sessionBox');
  await Hive.openBox<ErrorEvent>('errorBox');

  await NotificationsService.initialize();

  bool isLoggedIn = await AuthService.checkIsLoggedIn();

  // 🔹 Validar la versión de la aplicación
  await _validateAppVersion();

  // 🔹 Inicializar Firebase Messaging
  await _initializeFirebaseMessaging();

  // 🔹 Verificar configuraciones de batería y actividad en segundo plano
  await _checkBatteryAndBackgroundSettings();

  // 🔹 Verificar sesión activa
  bool hasActiveSession = await _checkActiveSession(
    {}, // Replace with actual response data if available
    null, // Replace with actual selectedMovil if available
  );

  if (!hasActiveSession) {
    isLoggedIn = false; // Redirect to login if no active session
  }

  WidgetsFlutterBinding.ensureInitialized(); // Asegura la inicialización
  runApp(MyApp(isLoggedIn: isLoggedIn));
}

Future<void> _initializeFirebaseMessaging() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Solicitar permisos para iOS
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    print('Usuario concedió permisos de notificación');
  } else {
    print('Usuario no concedió permisos de notificación');
  }

  // Configurar el canal de notificaciones
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel', // id
    'High Importance Notifications', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // Inicializar las notificaciones locales
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  final InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Configurar el manejo de mensajes en foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            icon: android.smallIcon,
          ),
        ),
      );
    }
  });

  // Configurar el manejo de mensajes en background
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling a background message: ${message.messageId}');
  RemoteNotification? notification = message.notification;
  if (notification != null) {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'messages_channel_id',
      'Messages Notifications',
      channelDescription: 'Notifications for new messages',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      platformChannelSpecifics,
    );
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
      _showUpdateDialog(response['message'], response['link']);
    }
  }
}

Future<void> _checkBatteryAndBackgroundSettings() async {
  /*DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  Battery battery = Battery();

  // Verificar si la aplicación está en la lista de optimización de batería
  bool isIgnoringBatteryOptimizations = await battery.isInBatterySaveMode;
  if (!isIgnoringBatteryOptimizations) {
    _showMessage(
        'La aplicación está optimizada para batería. Esto puede afectar su rendimiento.');
  }

  // Verificar si la aplicación está en la lista de aplicaciones en segundo plano
  if (Platform.isAndroid) {
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    if (await battery.isInBatterySaveMode) {
      _showMessage(
          'La aplicación está restringida para ejecutarse en segundo plano.');
    }
  }*/
}

Future<void> _checkInternetConnectivity() async {
  print('🔍 Verificando conectividad a Internet...');
  var connectivityResult = await Connectivity().checkConnectivity();
  print('🔍 Resultado de conectividad: $connectivityResult');

  if (connectivityResult == ConnectivityResult.none ||
      (connectivityResult is List &&
          connectivityResult.contains(ConnectivityResult.none))) {
    print('❌ No hay conexión a Internet.');
    _showNoInternetDialog(); // entra a modo "bloqueo"
  } else {
    print('✅ Conexión a Internet disponible. Verificando acceso a datos...');
    bool hasDataAccess = await _checkDataAccess();
    if (!hasDataAccess) {
      print('❌ No hay acceso a datos. Posible falta de paquete de datos.');
      _showNoDataAccessDialog();
    } else {
      print('✅ Acceso a datos confirmado.');
      // Podés continuar con la app aquí si querés.
    }
  }
}

Future<bool> _checkDataAccess() async {
  try {
    final response = await http
        .get(Uri.parse('https://www.google.com'))
        .timeout(Duration(seconds: 5));
    if (response.statusCode == 200) {
      return true;
    } else {
      return false;
    }
  } catch (e) {
    print('Error verificando acceso a datos: $e');
    return false;
  }
}

void _showNoInternetDialog() {
  print('⚠️ Mostrando diálogo de "Sin Conexión a Internet".');
  WidgetsBinding.instance.addPostFrameCallback((_) {
    showDialog(
      context: navigatorKey.currentContext!,
      barrierDismissible: false, // No puede cerrarse tocando fuera del dialog
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Sin Conexión a Internet'),
          content: Text(
              'No tienes conexión a Internet. Por favor, verifica tu conexión.'),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                print('🔄 Reintentando conectividad a Internet...');
                Navigator.of(context).pop(); // Cierra el diálogo actual
              },
              child: Text('Confirmar'),
            ),
          ],
        );
      },
    );
  });
}

void _showNoDataAccessDialog() {
  print('⚠️ Mostrando diálogo de "Sin Acceso a Datos".');
  WidgetsBinding.instance.addPostFrameCallback((_) {
    showDialog(
      context: navigatorKey.currentContext!,
      barrierDismissible: false, // No puede cerrarse tocando fuera del dialog
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Sin Acceso a Datos'),
          content: Text(
              'No tienes acceso a datos. Por favor, verifica tu paquete de datos o conéctate a una red Wi-Fi.'),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                print('🔄 Reintentando acceso a datos...');
                Navigator.of(context).pop(); // Cierra el diálogo actual
              },
              child: Text('Confirmar'),
            ),
          ],
        );
      },
    );
  });
}

Future<void> _retryInternetConnectivity() async {
  print('🔁 Reintento de conexión iniciado...');
  var connectivityResult = await Connectivity().checkConnectivity();
  if (connectivityResult == ConnectivityResult.none ||
      (connectivityResult is List &&
          connectivityResult.contains(ConnectivityResult.none))) {
    print('🚫 Aún sin conexión. Mostrando diálogo nuevamente.');
    _showNoInternetDialog(); // vuelve a mostrar el diálogo si sigue sin internet
  } else {
    print('✅ Conexión restaurada.');
    // Aquí podés continuar con el flujo normal de tu app
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

Future<bool> _checkActiveSession(
    Map<String, dynamic> response, String? selectedMovil) async {
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
        '⚠️ Falta información en sessionBox. No se puede validar sesión activa.');
    return false;
  }

  String hoy = DateTime.now()
      .toUtc()
      .toIso8601String()
      .split('T')[0]
      .replaceAll('-', '');
  String path = 'Sesiones-$escenario / $hoy / Movil-$selectedMovil / activo';

  print('📄 Consultando documento Firestore: $path');

  DocumentReference ultimaDocRef = FirebaseFirestore.instance
      .collection('Sesiones-$escenario')
      .doc(hoy)
      .collection('Movil-$selectedMovil')
      .doc('activo');

  DocumentSnapshot activeDocSnapshot;

  try {
    const int maxRetries = 3;
    const Duration initialDelay = Duration(seconds: 2);
    int attempt = 0;

    while (true) {
      try {
        activeDocSnapshot = await ultimaDocRef.get();
        print('✅ Documento Firestore obtenido correctamente.');
        break; // Exit loop on success
      } catch (e) {
        if (e is FirebaseException && e.code == 'unavailable') {
          attempt++;
          if (attempt > maxRetries) {
            print('❌ Máximo número de reintentos alcanzado. Error: $e');
            return false;
          }
          final delay = initialDelay * attempt;
          print('🔄 Reintentando en $delay segundos...');
          await Future.delayed(delay);
        } else if (e is FirebaseException && e.code == 'permission-denied') {
          print('❌ Error de permisos al acceder a Firestore: ${e.message}');
          return false;
        } else {
          print('❌ Error inesperado al acceder a Firestore: $e');
          rethrow;
        }
      }
    }
  } catch (e) {
    print('❌ Error crítico al acceder a Firestore: $e');
    rethrow;
  }

  if (activeDocSnapshot.exists) {
    var data = activeDocSnapshot.data() as Map<String, dynamic>;
    if (data['idUsuario'] != idUsuario || data['idTerminal'] != idTerminal) {
      return false;
    }
  }
  return true;
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
