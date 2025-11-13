import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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
import 'services/session_service.dart';
import 'services/persistent_stream_manager.dart';
import 'package:url_launcher/url_launcher.dart'; // Importa url_launcher
import 'utils/error_event.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:io'; // Importa dart:io para usar Platform
import 'package:connectivity_plus/connectivity_plus.dart'; // Importa connectivity_plus
import 'package:http/http.dart'
    as http; // Importa http para realizar solicitudes HTTP
import 'package:cloud_firestore/cloud_firestore.dart'; // Importa cloud_firestore para usar Firestore
import 'utils/constantes.dart'; // Importa constantes para usar getConstantValue
import 'package:dio/dio.dart'; // Importa dio para la descarga
import 'package:open_file/open_file.dart'; // Importa open_file para abrir el archivo descargado
import 'package:path_provider/path_provider.dart'; // Importa path_provider para obtener directorios
import 'package:permission_handler/permission_handler.dart'
    as permission_handler; // Importa permission_handler para manejar permisos
import 'package:flutter/services.dart'; // Importa SystemNavigator
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import '../services/location_service.dart'; // 🔹 Importamos LocationService
import '../services/native_log_sync_service.dart'; // 🔹 Importamos NativeLogSyncService
import 'package:screen_protector/screen_protector.dart';
import 'services/remote_logout_listener.dart'; // 🚨 Importar listener de logout remoto
import 'services/fcm_token_manager.dart'; // 🔑 Importar FCM Token Manager
import 'services/screen_recording_manager.dart'; // 🎥 Sistema de grabación de pantalla
import 'package:logrocket_flutter/logrocket_flutter.dart'; // 🎥 LogRocket SDK

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

bool? _screenSecureEnabled;

Future<void> _setupScreenProtectorByMovilStream() async {
  if (!Platform.isAndroid) return;

  final manager = PersistentStreamManager();
  try {
    await manager.initialize(); // Asegura que los streams estén activos
  } catch (_) {}

  Future<void> apply(DocumentSnapshot? doc) async {
    try {
      dynamic val;
      if (doc != null) {
        try {
          val = doc.get('printScreen');
        } catch (_) {
          final data = doc.data();
          if (data is Map<String, dynamic>) val = data['printScreen'];
        }
      }
      // 'S' => permitir (OFF), 'N' => bloquear (ON), null/otros => permitir (OFF)
      final bool shouldBlock = (val == 'N');
      if (_screenSecureEnabled == shouldBlock)
        return; // evita llamadas repetidas
      _screenSecureEnabled = shouldBlock;

      if (shouldBlock) {
        await ScreenProtector.preventScreenshotOn();
      } else {
        await ScreenProtector.preventScreenshotOff();
      }
    } catch (_) {}
  }

  await apply(manager.movilNotifier.value);
  manager.movilNotifier.addListener(() {
    // Ignorar el futuro; no bloquear
    apply(manager.movilNotifier.value);
  });
}

Future<void> _checkAndListenGpsPermissions() async {
  print('Antes de los permisos de ubicación');
  LocationPermission permission = await Geolocator.checkPermission();

  if (permission != LocationPermission.always) {
    print('🔄 Initial GPS Permission: $permission');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: navigatorKey.currentContext!,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Permiso de GPS requerido'),
            content: Text(
              'La aplicación requiere que habilites los permisos de ubicación TODO EL TIEMPO para funcionar correctamente. Por favor, habilítalos.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Only close the dialog
                },
                child: Text('Cancelar'),
              ),
              TextButton(
                child: Text('Ir a Ajustes'),
                onPressed: () async {
                  Navigator.of(context).pop();
                  final intent = AndroidIntent(
                    action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
                    data: 'package:com.example.moveit',
                    flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
                  );
                  await intent.launch();
                },
              ),
            ],
          );
        },
      );
    });
  }
}

void _listenToLocationPermission() {
  Geolocator.getServiceStatusStream().listen((ServiceStatus status) async {
    try {
      print('🔄 GPS Service Status: $status');
      LocationPermission permission = await Geolocator.checkPermission();
      print('🔄 Current GPS Permission: $permission');
    } catch (e) {
      print('❌ Error in Location Permission Listener: $e');
    }
  });
}

void main() async {
  // 🎥 Inicializar LogRocket PRIMERO (wrap toda la app)
  LogRocket.wrapAndInitialize(
    LogRocketWrapConfiguration(),
    LogRocketInitConfiguration(appID: 'w2ree2/delivery-ammr6'),
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);

      // 🔴 DESACTIVAR ENVÍO DE DATOS A FIREBASE
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);

      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;

      // 🔹 Inicializa Hive antes de cualquier acceso a Hive.openBox()

      await Hive.initFlutter();
      Hive.registerAdapter(ErrorEventAdapter());
      await Hive.openBox('sessionBox');
      await Hive.openBox<ErrorEvent>('errorBox');

      // 🌍 Inicializar ambiente de aplicación (Dev/Prod)
      await AppEnvironment.initialize();

      await NotificationsService.initialize();
      await RioGasService.initializeService(); // 👈 imprescindible

      // 🔹 Inicializar servicio de sincronización de logs nativos
      await NativeLogSyncService.initialize();

      // 🔍 Mostrar logs sincronizados para debugging (temporal)
      await NativeLogSyncService.displaySyncedLogs();

      // 🚨 Inicializar listener de logout remoto via FCM
      await RemoteLogoutListener.initialize();

      // 🎥 LogRocket se inicializa automáticamente desde AndroidManifest.xml
      // App ID: w2ree2/delivery-ammr6
      print('🎥 LogRocket configurado con App ID desde AndroidManifest');

      bool isLoggedIn = await AuthService.checkIsLoggedIn();

      // 🔹 Inicializar sincronización centralizada de Hive (mensajes y pedidos)
      PersistentStreamManager().initializeHiveSync();

      // Control de captura de pantalla según stream de móviles
      await _setupScreenProtectorByMovilStream();

      if (isLoggedIn) {
        // 🔹 Verificar y escuchar permisos de GPS
        //await _checkAndListenGpsPermissions();
      }

      // 🔹 Verificar conectividad a Internet
      await _checkInternetConnectivity();

      // 🔹 Validar la versión de la aplicación
      /*if (!isLoggedIn) {
    
  }*/
      await _validateAppVersion();

      // 🔹 Inicializar Firebase Messaging
      await _initializeFirebaseMessaging();

      // � Inicializar FCM Token Manager (auto-renovación de tokens)
      await _initializeFCMTokenManager();

      // �🔹 Verificar configuraciones de batería y actividad en segundo plano
      //await _checkBatteryAndBackgroundSettings();

      // 🔹 Verificar sesión activa
      bool hasActiveSession = await _checkActiveSession(
        {}, // Replace with actual response data if available
        null, // Replace with actual selectedMovil if available
      );

      if (!hasActiveSession) {
        isLoggedIn = false; // Redirect to login if no active session
      }

      FlutterError.onError = (FlutterErrorDetails details) {
        // Podés registrar esto en logs o mostrar una pantalla de error
        // print("Error crítico atrapado: \\${details.exceptionAsString()}");
        FlutterError.presentError(details); // Muestra el error en consola
      };

      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final version = androidInfo.version.sdkInt;

      if (Platform.isAndroid && version < 26) {
        runApp(
          MaterialApp(
            home: Scaffold(body: Center(child: Text('Lite Fallback App'))),
          ),
        ); // algo más liviano, sin animaciones
      } else {
        runApp(MyApp(isLoggedIn: isLoggedIn));
      }

      //WidgetsFlutterBinding.ensureInitialized(); // Asegura la inicialización

      // 🔹 Start listening to location permissions
      _listenToLocationPermission();
    }, // 🎥 Cierre de la función lambda de LogRocket.wrapAndInitialize
  ); // 🎥 Cierre de LogRocket.wrapAndInitialize
}

Future<void> _initializeFirebaseMessaging() async {
  final FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Solicitar permisos para iOS
  final NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    // print('Usuario concedió permisos de notificación');
  } else {
    // print('Usuario no concedió permisos de notificación');
  }

  // Configurar el canal de notificaciones
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel', // id
    'High Importance Notifications', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.high,
    sound: RawResourceAndroidNotificationSound(
      'iphone_notification',
    ), // Configura el sonido personalizado
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // Inicializar las notificaciones locales
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Configurar el manejo de mensajes en foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    print('📩 [FCM FG] Mensaje recibido en foreground');
    print('📩 [FCM FG] Message ID: ${message.messageId}');
    print('📩 [FCM FG] Data: ${message.data}');

    // 🎥 Manejar comando de grabación de pantalla
    final action = message.data['action'];
    if (action == 'toggle_screen_recording') {
      final enable = message.data['enable'] == 'true';
      try {
        await ScreenRecordingManager.toggleRecording(enable);
        print(
            '📹 [FCM] Grabación ${enable ? "activada" : "desactivada"} remotamente');
      } catch (e) {
        print('❌ [FCM] Error toggle grabación: $e');
      }
      return; // No mostrar notificación para comandos de sistema
    }

    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      await flutterLocalNotificationsPlugin.show(
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

    // ✅ Llamada al servicio RecepcionFCM
    if (message.messageId != null) {
      await RioGasService.recepcionFCM(
        message.messageId!, // Identificador de la notificación
        "Recibido FG", // Estado
      );
      print('📬 Notificación reportada a RecepcionFCM');
    }
  });

  // Configurar el manejo de mensajes en background
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
}

/// 🔑 Inicializar FCM Token Manager
///
/// Sistema automático que:
/// - Detecta cuando Firebase rota/invalida el token
/// - Sincroniza automáticamente con el backend
/// - Mantiene cache local del token actual
Future<void> _initializeFCMTokenManager() async {
  try {
    print('🔑 [MAIN] Inicializando FCM Token Manager...');
    await FCMTokenManager.initialize();
    print('✅ [MAIN] FCM Token Manager inicializado');
  } catch (e, stackTrace) {
    print('❌ [MAIN] Error inicializando FCM Token Manager: $e');
    print('📚 StackTrace: $stackTrace');
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  print('📩 [FCM BG] Mensaje recibido en background o con app cerrada');
  print('📩 [FCM BG] Message ID: ${message.messageId}');
  print('📩 [FCM BG] Data: ${message.data}');

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
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    await flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      platformChannelSpecifics,
    );
  }

  // ✅ Reportar recepción en BG
  if (message.messageId != null) {
    await RioGasService.recepcionFCM(
      message.messageId!,
      "Recibido BG",
    );
    print('📬 [FCM BG] Notificación reportada a RecepcionFCM');
  }
}

Future<void> _validateAppVersion() async {
  String appVersion = await AuthService.getAppVersion();
  String deviceId = await AuthService.getDeviceId();

  // 🔹 Verificar si ya se asignó un móvil en sessionBox
  var box = await Hive.openBox('sessionBox');
  var movil = box.get('movil');

  bool tieneMovilValido = movil != null &&
      movil.toString().isNotEmpty &&
      int.tryParse(movil.toString()) != null &&
      int.parse(movil.toString()) > 0;

  if (tieneMovilValido) {
    print(
        "🔴 hay un móvil válido registrado, no se controla porque esta usando la app.");
    return; // 🚫 Detenemos la validación si no hay móvil
  }

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

Future<void> _checkBatteryAndBackgroundSettings() async {
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  Battery battery = Battery();

  // Verificar si la aplicación está en la lista de optimización de batería
  bool isIgnoringBatteryOptimizations = await battery.isInBatterySaveMode;
  if (!isIgnoringBatteryOptimizations) {
    String? batteryOptimizationMessage = await getConstantValue(
      '140',
    ); // Fetch message from constant
    if (batteryOptimizationMessage != null) {
      _showMessage(
        batteryOptimizationMessage,
      );
    }
  }

  // Verificar si la aplicación está en la lista de aplicaciones en segundo plano
  if (Platform.isAndroid) {
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    /*if (await battery.isInBatterySaveMode) {
      String? backgroundMessage = await getConstantValue(
        '141',
      ); // Fetch message from constant
      _showMessage(
        backgroundMessage ??
            'La aplicación está restringida para ejecutarse en segundo plano.',
      );
    }*/
  }
}

Future<void> _checkInternetConnectivity() async {
  // print('🔍 Verificando conectividad a Internet...');
  var connectivityResult = await Connectivity().checkConnectivity();
  // print('🔍 Resultado de conectividad: $connectivityResult');

  if (connectivityResult == ConnectivityResult.none ||
      (connectivityResult is List &&
          connectivityResult.contains(ConnectivityResult.none))) {
    // print('❌ No hay conexión a Internet.');
    final mostrarDesconexion = await getConstantValue('230');
    if (mostrarDesconexion != null && mostrarDesconexion == 'S') {
      _showNoInternetDialog(); // entra a modo "bloqueo"
    }
  } else {
    // print('✅ Conexión a Internet disponible. Verificando acceso a datos...');
    bool hasDataAccess = await _checkDataAccess();
    if (!hasDataAccess) {
      // print('❌ No hay acceso a datos. Posible falta de paquete de datos.');
      _showNoDataAccessDialog();
    } else {
      // print('✅ Acceso a datos confirmado.');
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
    // print('Error verificando acceso a datos: $e');
    return false;
  }
}

void _showNoInternetDialog() {
  // print('⚠️ Mostrando diálogo de "Sin Conexión a Internet".');
  WidgetsBinding.instance.addPostFrameCallback((_) {
    showDialog(
      context: navigatorKey.currentContext!,
      barrierDismissible: false, // No puede cerrarse tocando fuera del dialog
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Sin Conexión a Internet'),
          content: Text(
            'No tienes conexión a Internet. Por favor, verifica tu conexión.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                // print('🔄 Reintentando conectividad a Internet...');
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
  // print('⚠️ Mostrando diálogo de "Sin Acceso a Datos".');
  WidgetsBinding.instance.addPostFrameCallback((_) {
    showDialog(
      context: navigatorKey.currentContext!,
      barrierDismissible: false, // No puede cerrarse tocando fuera del dialog
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Sin Acceso a Datos'),
          content: Text(
            'No tienes acceso a datos. Por favor, verifica tu paquete de datos o conéctate a una red Wi-Fi.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                // print('🔄 Reintentando acceso a datos...');
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
  // print('🔁 Reintento de conexión iniciado...');
  var connectivityResult = await Connectivity().checkConnectivity();
  if (connectivityResult == ConnectivityResult.none ||
      (connectivityResult is List &&
          connectivityResult.contains(ConnectivityResult.none))) {
    // print('🚫 Aún sin conexión. Mostrando diálogo nuevamente.');

    final mostrarDesconexion = await getConstantValue('230');
    if (mostrarDesconexion != null && mostrarDesconexion == 'S') {
      _showNoInternetDialog(); // vuelve a mostrar el diálogo si sigue sin internet
    }
  } else {
    // print('✅ Conexión restaurada.');
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

void _showUpdateDialog(String message, String link, bool isRequired) {
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
                print(
                    '🔄 Confirmación recibida. Iniciando proceso de actualización.');

                // Solicitar permiso REQUEST_INSTALL_PACKAGES
                if (await permission_handler
                    .Permission.requestInstallPackages.isDenied) {
                  print(
                      '⚠️ Permiso REQUEST_INSTALL_PACKAGES denegado. Solicitando permiso.');
                  final status = await permission_handler
                      .Permission.requestInstallPackages
                      .request();
                  if (!status.isGranted) {
                    print('❌ Permiso REQUEST_INSTALL_PACKAGES no concedido.');
                    _showMessage(
                        'No se puede continuar sin el permiso para instalar paquetes.');
                    return;
                  }
                }

                double progress = 0.0;
                late StateSetter dialogSetState;

                // Mostrar barra de progreso
                showDialog(
                  context: navigatorKey.currentContext!,
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
                                  'Descarga: ${(progress * 100).toStringAsFixed(0)}%'),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );

                try {
                  // Descarga el archivo desde la URL
                  final tempDir = await getTemporaryDirectory();
                  final filePath = '${tempDir.path}/app_update.apk';

                  Dio dio = Dio();
                  await dio.download(link, filePath,
                      onReceiveProgress: (received, total) {
                    if (total != -1) {
                      final newProgress = received / total;
                      dialogSetState(() {
                        progress = newProgress;
                      });
                      print(
                          '📥 Progreso de descarga: ${(newProgress * 100).toStringAsFixed(0)}%');
                    }
                  });

                  Navigator.of(navigatorKey.currentContext!)
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
                  Navigator.of(navigatorKey.currentContext!)
                      .pop(); // Cierra el diálogo de progreso en caso de error
                  print('❌ Error al intentar descargar o abrir el archivo: $e');
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
  // print('📦 Abriendo caja Hive: sessionBox...');
  var box = await Hive.openBox('sessionBox');

  String? escenario = box.get('escenario')?.toString();
  String? idUsuario = box.get('username');
  String? idTerminal = box.get('deviceId');
  String? nombreUsuario = box.get('NombreUsuario');
  String? fecha = box.get('fecha');

  String hoy = DateTime.now()
      .toUtc()
      .toIso8601String()
      .split('T')[0]
      .replaceAll('-', '');

  // Verificar si hay datos en sessionBox
  if (escenario == null ||
      idUsuario == null ||
      idTerminal == null ||
      nombreUsuario == null ||
      fecha != hoy) {
    // print(
    //   '⚠️ Falta información en sessionBox. No se puede validar sesión activa.',
    // );
    return false;
  }

  String path = 'Sesiones-$escenario / $hoy / Movil-$selectedMovil / activo';

  // print('📄 Consultando documento Firestore: $path');

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
        // print('✅ Documento Firestore obtenido correctamente.');
        break; // Exit loop on success
      } catch (e) {
        if (e is FirebaseException && e.code == 'unavailable') {
          attempt++;
          if (attempt > maxRetries) {
            // print('❌ Máximo número de reintentos alcanzado. Error: $e');
            return false;
          }
          final delay = initialDelay * attempt;
          // print('🔄 Reintentando en $delay segundos...');
          await Future.delayed(delay);
        } else if (e is FirebaseException && e.code == 'permission-denied') {
          // print('❌ Error de permisos al acceder a Firestore: ${e.message}');
          return false;
        } else {
          // print('❌ Error inesperado al acceder a Firestore: $e');
          rethrow;
        }
      }
    }
  } catch (e) {
    // print('❌ Error crítico al acceder a Firestore: $e');
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

class MyApp extends StatefulWidget {
  final bool isLoggedIn;
  MyApp({required this.isLoggedIn});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Timer? _notificationCheckTimer;
  bool _isCheckingPermissions = false;
  bool _dialogShown = false;
  DateTime? _lastDialogDismissed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startNotificationMonitoring();
  }

  @override
  void dispose() {
    _notificationCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Verificar permisos cuando la app vuelve al foreground
    if (state == AppLifecycleState.resumed) {
      Future.delayed(Duration(milliseconds: 500), () {
        _checkNotificationPermissions();
      });
    }
  }

  void _startNotificationMonitoring() {
    // Verificación inicial de notificaciones
    Future.delayed(Duration(seconds: 1), () {
      _checkNotificationPermissions();
    });

    // Verificación inicial de optimización de batería
    Future.delayed(Duration(seconds: 2), () {
      _checkBatteryOptimization();
    });

    // Verificación periódica cada 5 segundos
    _notificationCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      _checkNotificationPermissions();
    });
  }

  Future<void> _checkNotificationPermissions() async {
    if (_isCheckingPermissions) return;
    _isCheckingPermissions = true;

    try {
      // Verificar si las notificaciones están habilitadas
      final status = await permission_handler.Permission.notification.status;

      if (!status.isGranted) {
        // Si el diálogo fue cerrado hace menos de 3 segundos, esperar
        if (_lastDialogDismissed != null) {
          final timeSinceDismissed =
              DateTime.now().difference(_lastDialogDismissed!);
          if (timeSinceDismissed.inSeconds < 3) {
            _isCheckingPermissions = false;
            return;
          }
        }

        // Mostrar diálogo solo si no está ya visible
        if (!_dialogShown && navigatorKey.currentContext != null) {
          _dialogShown = true;
          await _showNotificationPermissionDialog();
        }
      } else {
        _dialogShown = false;
      }
    } catch (e) {
      print('❌ Error verificando permisos de notificación: $e');
    } finally {
      _isCheckingPermissions = false;
    }
  }

  Future<void> _checkBatteryOptimization() async {
    if (!Platform.isAndroid) return;

    try {
      final platform = MethodChannel('background_service');
      final bool isIgnoring =
          await platform.invokeMethod('checkBatteryOptimization');

      print('🔋 Battery optimization status: $isIgnoring');

      if (!isIgnoring) {
        // Si el diálogo fue cerrado hace menos de 3 segundos, esperar
        if (_lastDialogDismissed != null) {
          final timeSinceDismissed =
              DateTime.now().difference(_lastDialogDismissed!);
          if (timeSinceDismissed.inSeconds < 3) {
            return;
          }
        }

        // Mostrar diálogo solo si no está ya visible
        if (!_dialogShown && navigatorKey.currentContext != null) {
          _dialogShown = true;
          await _showBatteryOptimizationDialog();
        }
      }
    } catch (e) {
      print('❌ Error verificando optimización de batería: $e');
    }
  }

  Future<void> _showNotificationPermissionDialog() async {
    if (navigatorKey.currentContext == null) {
      _dialogShown = false;
      return;
    }

    return showDialog<void>(
      context: navigatorKey.currentContext!,
      barrierDismissible: false, // No se puede cerrar tocando fuera
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async {
            // No permitir cerrar con botón de atrás
            _lastDialogDismissed = DateTime.now();
            _dialogShown = false;
            return true;
          },
          child: AlertDialog(
            title: Row(
              children: [
                Icon(Icons.notifications_off, color: Colors.red, size: 30),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '⚠️ Notificaciones Deshabilitadas',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Las notificaciones son OBLIGATORIAS para el funcionamiento de la aplicación.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 15),
                Text(
                  '📍 Sin notificaciones activas, el servicio de ubicación NO funcionará correctamente.',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 10),
                Text(
                  '🚫 La aplicación no puede continuar sin este permiso.',
                  style: TextStyle(fontSize: 14, color: Colors.red),
                ),
                SizedBox(height: 15),
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange, width: 2),
                  ),
                  child: Text(
                    'Por favor, activa las notificaciones en la configuración de Android.',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton.icon(
                icon: Icon(Icons.settings, color: Colors.white),
                label: Text('Abrir Configuración',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () async {
                  _lastDialogDismissed = DateTime.now();
                  _dialogShown = false;
                  Navigator.of(context).pop();

                  // Abrir configuración de la app
                  await permission_handler.openAppSettings();

                  // Esperar 3 segundos antes de volver a verificar
                  await Future.delayed(Duration(seconds: 3));
                },
              ),
            ],
          ),
        );
      },
    ).then((_) {
      _dialogShown = false;
      _lastDialogDismissed = DateTime.now();
    });
  }

  Future<void> _showBatteryOptimizationDialog() async {
    if (navigatorKey.currentContext == null) {
      _dialogShown = false;
      return;
    }

    return showDialog<void>(
      context: navigatorKey.currentContext!,
      barrierDismissible: false, // No se puede cerrar tocando fuera
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async {
            // No permitir cerrar con botón de atrás
            _lastDialogDismissed = DateTime.now();
            _dialogShown = false;
            return true;
          },
          child: AlertDialog(
            title: Row(
              children: [
                Icon(Icons.battery_alert, color: Colors.orange, size: 30),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '🔋 Optimización de Batería',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'La app necesita estar excluida de la optimización de batería para funcionar correctamente.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 15),
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange, width: 2),
                  ),
                  child: Text(
                    'Por favor, permite que la app funcione sin restricciones de batería.',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton.icon(
                icon: Icon(Icons.settings, color: Colors.white),
                label: Text('Configurar Ahora',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () async {
                  _lastDialogDismissed = DateTime.now();
                  _dialogShown = false;
                  Navigator.of(context).pop();

                  try {
                    // Llamar al método nativo para abrir configuración
                    final platform = MethodChannel('background_service');
                    await platform
                        .invokeMethod('requestBatteryOptimizationExemption');
                  } catch (e) {
                    print('❌ Error abriendo configuración de batería: $e');
                  }

                  // Esperar 3 segundos antes de volver a verificar
                  await Future.delayed(Duration(seconds: 3));
                },
              ),
            ],
          ),
        );
      },
    ).then((_) {
      _dialogShown = false;
      _lastDialogDismissed = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LogRocketWidget(
      child: MaterialApp(
        title: 'MoveIT',
        theme: ThemeData(primarySwatch: Colors.blue),
        navigatorKey: navigatorKey,
        // 🌍 Banner visual si está en modo desarrollo
        builder: (context, child) {
          if (AppEnvironment.isDevelopment) {
            return Banner(
              message: 'DESARROLLO 🧪',
              location: BannerLocation.topEnd,
              color: Colors.orange,
              textStyle: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              child: child!,
            );
          }
          return child!;
        },
        home: widget.isLoggedIn ? HomePage() : LoginPage(),
        onGenerateRoute: (RouteSettings settings) {
          if (settings.name == '/login') {
            final args = settings.arguments as Map<String, dynamic>?;

            return MaterialPageRoute(
              builder: (context) => LoginPage(
                forcedLogout: args?['forcedLogout'] ?? false,
                forcedLogoutMessage: args?['mensaje'] ?? '',
              ),
            );
          }

          if (settings.name == '/home') {
            return MaterialPageRoute(builder: (context) => HomePage());
          }

          return null;
        },
      ),
    );
  }
}
