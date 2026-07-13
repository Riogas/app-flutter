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

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

bool? _screenSecureEnabled;

// 🆕 SISTEMA DE LOGGING DEFENSIVO PARA MAIN.DART
class MainLogger {
  static bool _debugMode = false;
  static bool _initialized = false;
  static String? _movilId;

  /// Inicializa el logger y verifica si debugMode está activo
  /// Solo se ejecuta si hay sesión activa (movil guardado en Hive)
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // 1️⃣ Verificar si hay sesión activa (movil en Hive)
      final sessionBox = await Hive.openBox('sessionBox');
      _movilId = sessionBox.get('movil') as String?;

      if (_movilId == null || _movilId!.isEmpty) {
        // Sin sesión activa, no podemos leer Firestore
        print('📋 [MainLogger] Sin sesión activa, logging desactivado');
        _initialized = true;
        return;
      }

      // 2️⃣ Leer debugMode de Firestore SOLO si hay sesión
      final doc = await FirebaseFirestore.instance
          .collection('Moviles-$_movilId')
          .doc('config')
          .get()
          .timeout(
        Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Timeout leyendo debugMode');
        },
      );

      if (doc.exists) {
        _debugMode = doc.data()?['debugMode'] == true;
        print(
            '📋 [MainLogger] Inicializado: debugMode=$_debugMode, movil=$_movilId');
      } else {
        print('📋 [MainLogger] Documento config no existe, debugMode=false');
      }

      _initialized = true;
    } catch (e, stackTrace) {
      // 🛡️ NUNCA CRASHEAR - Solo loguear error
      print(
          '⚠️ [MainLogger] Error inicializando (continuando sin logging): $e');
      print('📚 StackTrace: $stackTrace');
      _initialized = true; // Marcar como inicializado para no reintentar
    }
  }

  /// Loguea un mensaje SOLO si debugMode=true
  static void log(String message, {String? context}) {
    if (!_debugMode) return;

    final timestamp = DateTime.now().toIso8601String();
    final contextStr = context != null ? '[$context]' : '';
    print('🐛 [DEBUG-MAIN] $contextStr $timestamp: $message');
  }

  /// Loguea un error SIEMPRE (sin importar debugMode)
  static void logError(String message,
      {dynamic error, StackTrace? stackTrace, String? context}) {
    final timestamp = DateTime.now().toIso8601String();
    final contextStr = context != null ? '[$context]' : '';
    print('🔴 [ERROR-MAIN] $contextStr $timestamp: $message');
    if (error != null) {
      print('   Error: $error');
    }
    if (stackTrace != null) {
      print('   StackTrace: $stackTrace');
    }
  }

  /// Loguea eventos del ciclo de vida de la app
  static void logLifecycle(String event, {Map<String, dynamic>? data}) {
    if (!_debugMode) return;

    final timestamp = DateTime.now().toIso8601String();
    final dataStr = data != null ? ' | Data: $data' : '';
    print('🔄 [LIFECYCLE-MAIN] $timestamp: $event$dataStr');
  }

  /// Fuerza re-lectura de debugMode (útil después de login)
  static Future<void> refresh() async {
    _initialized = false;
    await initialize();
  }
}

Future<void> _setupScreenProtectorByMovilStream() async {
  if (!Platform.isAndroid) return;

  final manager = PersistentStreamManager();

  // ⚠️ NO inicializar manager aquí - solo escuchar cambios
  // La inicialización ocurre después del login en startSesionesListenerAfterLogin()

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

  // Solo escuchar cambios, NO forzar valor inicial (puede ser null antes del login)
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
  // 🛡️ PROTECCIÓN GLOBAL: Captura TODOS los errores no manejados
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 🛡️ Captura errores de Flutter Framework
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      print('🔴 [FLUTTER ERROR] ${details.exceptionAsString()}');
      print('📚 StackTrace: ${details.stack}');

      // 🆕 Loguear error con MainLogger (defensivo)
      try {
        MainLogger.logError('Error de Flutter Framework',
            error: details.exception,
            stackTrace: details.stack,
            context: 'FLUTTER_ERROR');
      } catch (e) {
        // Nunca crashear por logging
        print('⚠️ MainLogger no disponible: $e');
      }

      // No crashear, solo loguear
      try {
        FirebaseCrashlytics.instance.recordFlutterError(details);
      } catch (e) {
        print('⚠️ No se pudo reportar a Crashlytics: $e');
      }
    };

    // 🛡️ Firebase con try-catch
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
      print('✅ Firebase inicializado correctamente');
    } catch (e, stackTrace) {
      print('⚠️ Error inicializando Firebase: $e');
      print('📚 StackTrace: $stackTrace');
      // Continuar sin Firebase si falla
    }

    // 🔴 DESACTIVAR ENVÍO DE DATOS A FIREBASE
    try {
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
    } catch (e) {
      print('⚠️ Error configurando Firebase Analytics/Crashlytics: $e');
    }

    // 🔹 Inicializa Hive antes de cualquier acceso a Hive.openBox()
    try {
      await Hive.initFlutter();
      Hive.registerAdapter(ErrorEventAdapter());
      await Hive.openBox('sessionBox');
      await Hive.openBox<ErrorEvent>('errorBox');
      print('✅ Hive inicializado correctamente');
    } catch (e, stackTrace) {
      print('⚠️ Error inicializando Hive: $e');
      print('📚 StackTrace: $stackTrace');
      // Si Hive falla, intentar recuperación
      try {
        await Hive.deleteBoxFromDisk('sessionBox');
        await Hive.deleteBoxFromDisk('errorBox');
        await Hive.initFlutter();
        Hive.registerAdapter(ErrorEventAdapter());
        await Hive.openBox('sessionBox');
        await Hive.openBox<ErrorEvent>('errorBox');
        print('✅ Hive recuperado exitosamente');
      } catch (e2) {
        print('❌ No se pudo recuperar Hive: $e2');
      }
    }

    // 🌍 Inicializar ambiente de aplicación (Dev/Prod)
    try {
      await AppEnvironment.initialize();
    } catch (e) {
      print('⚠️ Error inicializando AppEnvironment: $e');
    }

    // 🛡️ Inicializar servicios con protección
    try {
      await NotificationsService.initialize();
      MainLogger.log('✅ NotificationsService inicializado', context: 'INIT');
    } catch (e) {
      print('⚠️ Error inicializando NotificationsService: $e');
      MainLogger.logError('NotificationsService falló',
          error: e, context: 'INIT');
    }

    try {
      await RioGasService.initializeService(); // 👈 imprescindible
      MainLogger.log('✅ RioGasService inicializado', context: 'INIT');
    } catch (e) {
      print('⚠️ Error inicializando RioGasService: $e');
      MainLogger.logError('RioGasService falló', error: e, context: 'INIT');
    }

    // 🔹 Inicializar servicio de sincronización de logs nativos
    try {
      await NativeLogSyncService.initialize();
      MainLogger.log('✅ NativeLogSyncService inicializado', context: 'INIT');
    } catch (e) {
      print('⚠️ Error inicializando NativeLogSyncService: $e');
      MainLogger.logError('NativeLogSyncService falló',
          error: e, context: 'INIT');
    }

    // 🔍 Mostrar logs sincronizados para debugging (temporal)
    // await NativeLogSyncService.displaySyncedLogs(); // ❌ COMENTADO: Ralentiza el inicio de la app

    // 🚨 Inicializar listener de logout remoto via FCM
    try {
      await RemoteLogoutListener.initialize();
      MainLogger.log('✅ RemoteLogoutListener inicializado', context: 'INIT');
    } catch (e) {
      print('⚠️ Error inicializando RemoteLogoutListener: $e');
      MainLogger.logError('RemoteLogoutListener falló',
          error: e, context: 'INIT');
    }

    bool isLoggedIn = false;
    try {
      isLoggedIn = await AuthService.checkIsLoggedIn();
    } catch (e) {
      print('⚠️ Error verificando login: $e - Redirigiendo a login');
      isLoggedIn = false;
    }

    // 🔹 Inicializar sincronización centralizada de Hive (mensajes y pedidos)
    try {
      PersistentStreamManager().initializeHiveSync();
    } catch (e) {
      print('⚠️ Error inicializando PersistentStreamManager: $e');
    }

    // Control de captura de pantalla según stream de móviles
    try {
      await _setupScreenProtectorByMovilStream();
    } catch (e) {
      print('⚠️ Error configurando ScreenProtector: $e');
    }

    if (isLoggedIn) {
      // 🔹 Verificar y escuchar permisos de GPS
      //await _checkAndListenGpsPermissions();
    }

    // 🔹 Verificar conectividad a Internet
    try {
      await _checkInternetConnectivity();
    } catch (e) {
      print('⚠️ Error verificando conectividad: $e');
    }

    // 🔹 Validar la versión de la aplicación
    /*if (!isLoggedIn) {
    
  }*/
    try {
      await _validateAppVersion();
    } catch (e) {
      print('⚠️ Error validando versión: $e');
    }

    // 🔹 Inicializar Firebase Messaging
    try {
      await _initializeFirebaseMessaging();
    } catch (e) {
      print('⚠️ Error inicializando Firebase Messaging: $e');
    }

    // 🔑 Inicializar FCM Token Manager (auto-renovación de tokens)
    try {
      await _initializeFCMTokenManager();
    } catch (e) {
      print('⚠️ Error inicializando FCM Token Manager: $e');
    }

    // 🔹 Verificar configuraciones de batería y actividad en segundo plano
    //await _checkBatteryAndBackgroundSettings();

    // 🔹 Verificar sesión activa
    bool hasActiveSession = false;
    try {
      hasActiveSession = await _checkActiveSession(
        {}, // Replace with actual response data if available
        null, // Replace with actual selectedMovil if available
      );
    } catch (e) {
      print('⚠️ Error verificando sesión activa: $e');
      hasActiveSession = false;
    }

    if (!hasActiveSession) {
      isLoggedIn = false; // Redirect to login if no active session
    }

    // 🛡️ Obtener info del dispositivo con protección
    int sdkVersion = 26; // Default seguro
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      sdkVersion = androidInfo.version.sdkInt;
    } catch (e) {
      print('⚠️ Error obteniendo info del dispositivo: $e');
    }

    // 🚀 Lanzar app con protección
    if (Platform.isAndroid && sdkVersion < 26) {
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
    try {
      _listenToLocationPermission();
    } catch (e) {
      print('⚠️ Error iniciando listener de permisos: $e');
    }
  }, (error, stack) {
    // 🛡️ MANEJADOR DE ERRORES GLOBAL: Captura errores asincrónicos no manejados
    print('🔴 [GLOBAL ERROR] Error no manejado capturado: $error');
    print('📚 StackTrace: $stack');

    // 🆕 Loguear error con MainLogger (defensivo - nunca crashea)
    try {
      MainLogger.logError('Error asíncrono no manejado',
          error: error, stackTrace: stack, context: 'GLOBAL_ZONE');
    } catch (e) {
      // Si MainLogger falla, solo print (nunca crashear por logging)
      print('⚠️ MainLogger no disponible: $e');
    }

    // Intentar reportar a Firebase Crashlytics si está disponible
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
    } catch (e) {
      print('⚠️ No se pudo reportar a Crashlytics: $e');
    }

    // NO crashear la app, solo loguear
    // La app continuará funcionando
  });
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

  // ❌ ELIMINADO: Validación contra colección "Sesiones-$escenario" (ya no se usa)
  // La validación de sesión ahora se hace únicamente en backend via API
  return true;

  /* CÓDIGO ANTERIOR ELIMINADO:
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
  */
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
  bool _batteryCheckCompleted = false; // 🔋 Flag para evitar spam de batería

  // 🎯 Flags para verificación de UBICACIÓN PRECISA
  bool _isCheckingLocationPrecision = false;
  bool _precisionDialogShown = false;
  DateTime? _lastPrecisionDialogDismissed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startNotificationMonitoring();

    // 🆕 Inicializar logger defensivamente
    MainLogger.initialize().catchError((e) {
      // Nunca crashear por error en logging
      print('⚠️ Error inicializando MainLogger: $e');
    });

    MainLogger.logLifecycle('App iniciada', data: {
      'isLoggedIn': widget.isLoggedIn,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  void dispose() {
    MainLogger.logLifecycle('App dispose iniciado');
    _notificationCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 🆕 Loguear cambios de estado del ciclo de vida
    try {
      MainLogger.logLifecycle('Estado cambió', data: {
        'state': state.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Nunca crashear por logging
      print('⚠️ Error logueando lifecycle: $e');
    }

    // Verificar permisos cuando la app vuelve al foreground
    if (state == AppLifecycleState.resumed) {
      MainLogger.log('App resumed - Verificando permisos',
          context: 'LIFECYCLE');

      Future.delayed(Duration(milliseconds: 500), () {
        _checkNotificationPermissions();
      });
      // ⚠️ NO verificar batería en cada resume para evitar spam
      // Solo se verifica 1 vez al inicio
    } else if (state == AppLifecycleState.paused) {
      MainLogger.log('App paused - Entrando en background',
          context: 'LIFECYCLE');
    } else if (state == AppLifecycleState.inactive) {
      MainLogger.log('App inactive', context: 'LIFECYCLE');
    } else if (state == AppLifecycleState.detached) {
      MainLogger.log('App detached - Cerrando app', context: 'LIFECYCLE');
    }
  }

  void _startNotificationMonitoring() {
    // Verificación inicial de notificaciones
    Future.delayed(Duration(seconds: 1), () {
      _checkNotificationPermissions();
    });

    // Verificación inicial de optimización de batería (SOLO 1 VEZ)
    Future.delayed(Duration(seconds: 2), () {
      _checkBatteryOptimization();
    });

    // 📍 Verificación inicial de permisos GPS "Permitir Siempre" (SOLO 1 VEZ)
    Future.delayed(Duration(seconds: 3), () {
      _checkLocationPermissions();
    });

    // Verificación periódica cada 5 segundos
    // ✅ NOTIFICACIONES: Se verifica continuamente
    // ✅ UBICACIÓN PRECISA: Se verifica continuamente (Android 12+)
    // ⚠️ BATERÍA: NO se verifica periódicamente para evitar spam
    _notificationCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      _checkNotificationPermissions();
      _checkLocationPrecision(); // 🎯 NUEVA: Verificar ubicación precisa continuamente
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

    // 🛡️ Si ya se verificó y el usuario cerró el diálogo, NO volver a molestar
    if (_batteryCheckCompleted) {
      print('🔋 Verificación de batería ya completada, no se vuelve a mostrar');
      return;
    }

    try {
      final platform = MethodChannel('background_service');
      final bool isIgnoring =
          await platform.invokeMethod('checkBatteryOptimization');

      print('🔋 Battery optimization status: isIgnoring=$isIgnoring');

      // ✅ Si ya está ignorando optimización, marcar como completado
      if (isIgnoring) {
        _batteryCheckCompleted = true;
        print('✅ Batería configurada correctamente, no se volverá a verificar');
        return;
      }

      // ⚠️ Si NO está ignorando, mostrar diálogo SOLO UNA VEZ
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
          // Marcar como completado DESPUÉS de mostrar el diálogo
          _batteryCheckCompleted = true;
          print(
              '🔋 Diálogo de batería mostrado, no se volverá a mostrar en esta sesión');
        }
      }
    } catch (e) {
      print('❌ Error verificando optimización de batería: $e');
      // Marcar como completado aunque haya error para no seguir intentando
      _batteryCheckCompleted = true;
    }
  }

  // 📍 FIX: Verificar permisos GPS "Permitir Siempre" después del login
  Future<void> _checkLocationPermissions() async {
    if (!Platform.isAndroid) return;

    try {
      // Verificar el estado actual del permiso de ubicación
      LocationPermission permission = await Geolocator.checkPermission();

      print('📍 Location permission status: $permission');

      // ✅ Si ya tiene "Permitir Siempre", no hacer nada
      if (permission == LocationPermission.always) {
        print('✅ GPS configurado correctamente (Permitir Siempre)');
        return;
      }

      // 🔴 Si está "denied", primero solicitar permiso básico
      if (permission == LocationPermission.denied) {
        print('⚠️ Permiso de ubicación negado, solicitando permiso básico...');

        // Solicitar permiso (esto mostrará el diálogo nativo de Android)
        LocationPermission newPermission = await Geolocator.requestPermission();

        print('📍 Nuevo permiso después de solicitud: $newPermission');

        // Si el usuario lo denegó permanentemente, mostrar diálogo para ir a settings
        if (newPermission == LocationPermission.deniedForever) {
          if (!_dialogShown && navigatorKey.currentContext != null) {
            _dialogShown = true;
            await _showLocationPermissionDialog();
          }
          return;
        }

        // Si ahora tiene "whileInUse", continuar para pedir "always"
        permission = newPermission;
      }

      // ⚠️ Si tiene "Mientras se usa", solicitar "Permitir Siempre"
      if (permission == LocationPermission.whileInUse) {
        // Esperar 1 segundo para que el diálogo de batería se cierre completamente
        await Future.delayed(Duration(seconds: 1));

        // Resetear la flag para poder mostrar este diálogo
        _dialogShown = false;

        // Si el diálogo fue cerrado hace menos de 3 segundos, esperar
        if (_lastDialogDismissed != null) {
          final timeSinceDismissed =
              DateTime.now().difference(_lastDialogDismissed!);
          if (timeSinceDismissed.inSeconds < 3) {
            await Future.delayed(Duration(seconds: 3));
          }
        }

        // Mostrar diálogo solo si no está ya visible
        if (!_dialogShown && navigatorKey.currentContext != null) {
          _dialogShown = true;
          print(
              '📍 Mostrando diálogo para cambiar a "Permitir todo el tiempo"');
          await _showLocationPermissionDialog();
        }
      }

      // 🔴 Si está "deniedForever", mostrar diálogo para ir a settings
      if (permission == LocationPermission.deniedForever) {
        if (!_dialogShown && navigatorKey.currentContext != null) {
          _dialogShown = true;
          await _showLocationPermissionDialog();
        }
      }

      // 🎯 NUEVA VALIDACIÓN: Verificar UBICACIÓN PRECISA (Android 12+)
      if (permission == LocationPermission.always) {
        try {
          LocationAccuracyStatus accuracyStatus =
              await Geolocator.getLocationAccuracy();
          print('🎯 [PRECISIÓN] Estado de ubicación precisa: $accuracyStatus');

          if (accuracyStatus == LocationAccuracyStatus.reduced) {
            print(
                '❌ [PRECISIÓN] Ubicación aproximada detectada, se requiere ubicación PRECISA');

            // Resetear flag para poder mostrar el diálogo de precisión
            _dialogShown = false;

            if (!_dialogShown && navigatorKey.currentContext != null) {
              _dialogShown = true;
              await _showLocationPrecisionDialog();
            }
          } else {
            print('✅ [PRECISIÓN] Ubicación precisa activada correctamente');
          }
        } catch (e) {
          print(
              '⚠️ [PRECISIÓN] No se pudo verificar precisión (posiblemente Android <12): $e');
          // En Android <12 no existe este concepto, continuar normalmente
        }
      }
    } catch (e) {
      print('❌ Error verificando permisos de ubicación: $e');
    }
  }

  // 🎯 NUEVA: Verificar UBICACIÓN PRECISA continuamente (Android 12+)
  Future<void> _checkLocationPrecision() async {
    if (!Platform.isAndroid) return;

    // 🛡️ Evitar múltiples verificaciones simultáneas
    if (_isCheckingLocationPrecision) return;
    _isCheckingLocationPrecision = true;

    try {
      // 1️⃣ Primero verificar que tenga permiso "Permitir Siempre"
      LocationPermission permission = await Geolocator.checkPermission();

      // Si NO tiene "always", no verificar precisión (se maneja en otro lugar)
      if (permission != LocationPermission.always) {
        _isCheckingLocationPrecision = false;
        return;
      }

      // 2️⃣ Verificar precisión de ubicación (solo Android 12+)
      try {
        LocationAccuracyStatus accuracyStatus =
            await Geolocator.getLocationAccuracy();

        print('🎯 [PRECISIÓN-CONTINUA] Estado: $accuracyStatus');

        // Si está en modo REDUCIDO (aproximado), mostrar diálogo
        if (accuracyStatus == LocationAccuracyStatus.reduced) {
          print('❌ [PRECISIÓN-CONTINUA] Ubicación aproximada detectada');

          // Si el diálogo fue cerrado hace menos de 3 segundos, esperar
          if (_lastPrecisionDialogDismissed != null) {
            final timeSinceDismissed =
                DateTime.now().difference(_lastPrecisionDialogDismissed!);
            if (timeSinceDismissed.inSeconds < 3) {
              _isCheckingLocationPrecision = false;
              return;
            }
          }

          // Mostrar diálogo solo si no está ya visible
          if (!_precisionDialogShown && navigatorKey.currentContext != null) {
            _precisionDialogShown = true;
            await _showLocationPrecisionDialog();
          }
        } else {
          // ✅ Precisión OK - resetear flags
          _precisionDialogShown = false;
          print('✅ [PRECISIÓN-CONTINUA] Ubicación precisa activada');
        }
      } catch (e) {
        // Android <12 no soporta LocationAccuracyStatus
        print('⚠️ [PRECISIÓN-CONTINUA] No soportado en este dispositivo: $e');
      }
    } catch (e) {
      print('❌ [PRECISIÓN-CONTINUA] Error: $e');
    } finally {
      _isCheckingLocationPrecision = false;
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

  // 📍 FIX: Diálogo para solicitar permiso GPS "Permitir Siempre"
  Future<void> _showLocationPermissionDialog() async {
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
            // ❌ NO permitir cerrar con botón de atrás
            return false; // CAMBIADO de true a false
          },
          child: AlertDialog(
            title: Row(
              children: [
                Icon(Icons.location_off, color: Colors.red, size: 30),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '📍 Permiso de Ubicación Requerido',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: 'La app ',
                    style: TextStyle(fontSize: 16),
                    children: <TextSpan>[
                      TextSpan(
                        text: 'REQUIERE',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                          fontSize: 16,
                        ),
                      ),
                      TextSpan(
                        text:
                            ' que se habilite el permiso de acceso a la ubicación ',
                        style: TextStyle(fontSize: 16),
                      ),
                      TextSpan(
                        text: 'TODO EL TIEMPO',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                          fontSize: 16,
                        ),
                      ),
                      TextSpan(
                        text: ' para poder funcionar correctamente.',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 15),
                Text(
                  '🚫 Sin este permiso, la aplicación no podrá rastrear tu ubicación en segundo plano.',
                  style: TextStyle(fontSize: 14, color: Colors.red),
                ),
                SizedBox(height: 15),
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📋 Pasos para habilitar:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        '1. Tap en "Abrir Configuración"',
                        style: TextStyle(fontSize: 13),
                      ),
                      Text(
                        '2. Ve a "Permisos" → "Ubicación"',
                        style: TextStyle(fontSize: 13),
                      ),
                      Text(
                        '3. Selecciona "Permitir todo el tiempo"',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
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
                  // ❌ NO cerrar el diálogo - mantenerlo abierto
                  // _lastDialogDismissed = DateTime.now(); // ELIMINADO
                  // _dialogShown = false; // ELIMINADO
                  // Navigator.of(context).pop(); // ELIMINADO

                  // Abrir configuración de la app para permisos
                  await Geolocator.openAppSettings();

                  // Esperar a que el usuario regrese de configuración
                  await Future.delayed(Duration(seconds: 2));

                  // 🔄 Re-verificar permisos en loop hasta que se concedan
                  while (true) {
                    LocationPermission permission =
                        await Geolocator.checkPermission();
                    if (permission == LocationPermission.always) {
                      // ✅ Permiso concedido - cerrar diálogo y resetear flags
                      _lastDialogDismissed = DateTime.now();
                      _dialogShown = false;
                      Navigator.of(context).pop();
                      break;
                    }
                    // ⏳ Esperar 2 segundos y volver a verificar
                    await Future.delayed(Duration(seconds: 2));
                  }
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

  Future<void> _showLocationPrecisionDialog() async {
    if (navigatorKey.currentContext == null) {
      _precisionDialogShown = false; // 🎯 Usar flag específica
      return;
    }

    return showDialog<void>(
      context: navigatorKey.currentContext!,
      barrierDismissible: false, // ❌ No se puede cerrar tocando fuera
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async =>
              false, // ❌ No permitir cerrar con botón de atrás
          child: AlertDialog(
            title: Row(
              children: [
                Icon(Icons.my_location, color: Colors.orange, size: 30),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '🎯 Ubicación Precisa Requerida',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: 'La app ',
                    style: TextStyle(fontSize: 16),
                    children: <TextSpan>[
                      TextSpan(
                        text: 'REQUIERE',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                          fontSize: 16,
                        ),
                      ),
                      TextSpan(
                        text: ' acceso a ',
                        style: TextStyle(fontSize: 16),
                      ),
                      TextSpan(
                        text: 'UBICACIÓN PRECISA',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                          fontSize: 16,
                        ),
                      ),
                      TextSpan(
                        text: ' para funcionar correctamente.',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 15),
                Text(
                  '⚠️ Actualmente solo tienes "Ubicación aproximada" activada.',
                  style: TextStyle(fontSize: 14, color: Colors.orange),
                ),
                SizedBox(height: 15),
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📋 Pasos para habilitar:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        '1. Tap en "Abrir Configuración"',
                        style: TextStyle(fontSize: 13),
                      ),
                      Text(
                        '2. Ve a "Permisos" → "Ubicación"',
                        style: TextStyle(fontSize: 13),
                      ),
                      Text(
                        '3. Activa "Usar ubicación precisa"',
                        style: TextStyle(fontSize: 13),
                      ),
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.orange, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Ubicación aproximada reduce la precisión del rastreo.',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                  backgroundColor: Colors.orange,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () async {
                  // Abrir configuración de la app para permisos
                  await Geolocator.openAppSettings();

                  // Esperar a que el usuario regrese de configuración
                  await Future.delayed(Duration(seconds: 2));

                  // 🔄 Re-verificar precisión en loop hasta que se active
                  while (true) {
                    try {
                      LocationAccuracyStatus accuracyStatus =
                          await Geolocator.getLocationAccuracy();
                      if (accuracyStatus == LocationAccuracyStatus.precise) {
                        // ✅ Ubicación precisa activada - cerrar diálogo y resetear flags
                        _lastPrecisionDialogDismissed =
                            DateTime.now(); // 🎯 Flag específica
                        _precisionDialogShown = false; // 🎯 Flag específica
                        Navigator.of(context).pop();
                        break;
                      }
                    } catch (e) {
                      // Si hay error (Android <12), asumir que está OK y cerrar
                      _lastPrecisionDialogDismissed =
                          DateTime.now(); // 🎯 Flag específica
                      _precisionDialogShown = false; // 🎯 Flag específica
                      Navigator.of(context).pop();
                      break;
                    }
                    // ⏳ Esperar 2 segundos y volver a verificar
                    await Future.delayed(Duration(seconds: 2));
                  }
                },
              ),
            ],
          ),
        );
      },
    ).then((_) {
      _precisionDialogShown = false; // 🎯 Flag específica
      _lastPrecisionDialogDismissed = DateTime.now(); // 🎯 Flag específica
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
    return MaterialApp(
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
    );
  }
}
