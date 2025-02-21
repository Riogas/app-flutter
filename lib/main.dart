import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart'; // Importa HiveFlutter
import 'utils/firebase_options.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'services/auth_service.dart';
import 'services/notifications_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 🔹 Inicializa Hive antes de cualquier acceso a Hive.openBox()
  await Hive.initFlutter();
  await Hive.openBox('sessionBox');

  await NotificationsService.initialize();

  bool isLoggedIn = await AuthService.checkIsLoggedIn();
  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  MyApp({required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoveIT',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: isLoggedIn ? HomePage() : LoginPage(),
    );
  }
}
