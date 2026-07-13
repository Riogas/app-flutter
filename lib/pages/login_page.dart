import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/riogas_service.dart';
import '../services/firebase_constants_service.dart';
import '../services/session_service.dart';
import '../services/session_sync_service.dart'; // 🔄 Sincronización de sesión
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
import 'package:http/http.dart' as http; // 🆕 Para verificar URLs remotas
import '../services/fcm_token_manager.dart'; // 🔑 Para gestión automática de tokens FCM
import 'package:audioplayers/audioplayers.dart'; // 🎵 Para reproducir audio
import 'package:shared_preferences/shared_preferences.dart'; // 💾 Para guardar preferencias
import 'package:cached_network_image/cached_network_image.dart'; // 🖼️ Para caché de imágenes

const String kLoginFlowTag = "[LOGIN_FLOW]";

class LoginBackground extends StatefulWidget {
  final Widget child;

  const LoginBackground({super.key, required this.child});

  @override
  State<LoginBackground> createState() => _LoginBackgroundState();
}

class _LoginBackgroundState extends State<LoginBackground> {
  VideoPlayerController? _videoController;
  String? _imageUrl;
  bool _isLoading = true;
  bool _useLocalAsset = false;
  String _backgroundType = 'video'; // 'video', 'image', 'gif'

  // 🌐 URL base para backgrounds personalizados
  static const String _remoteBaseUrl =
      'https://www.riogas.uy/ica_geos_/static/Resources/background_delivery';

  @override
  void initState() {
    super.initState();
    _loadBackground();
  }

  /// 🌙☀️ Determina si es de noche en Uruguay
  ///
  /// Considera:
  /// - Horario de verano (primer domingo de octubre - segundo domingo de marzo)
  /// - Noche: 20:00 - 06:00
  /// - Día: 06:00 - 20:00
  bool _isNightTimeInUruguay() {
    final now = DateTime.now().toUtc();

    // Uruguay está en UTC-3 (horario estándar)
    // Durante verano (octubre-marzo): UTC-2
    int uruguayOffset = -3;

    // Determinar si estamos en horario de verano
    final year = now.year;

    // Horario de verano: primer domingo de octubre
    final octoberFirst = DateTime.utc(year, 10, 1);
    int daysUntilSunday = (7 - octoberFirst.weekday) % 7;
    final summerStart = DateTime.utc(year, 10, 1 + daysUntilSunday);

    // Fin horario de verano: segundo domingo de marzo del año siguiente
    final marchFirst = DateTime.utc(year + 1, 3, 1);
    daysUntilSunday = (7 - marchFirst.weekday) % 7;
    final summerEnd = DateTime.utc(year + 1, 3, 1 + daysUntilSunday + 7);

    // Si estamos en horario de verano, offset es -2
    if (now.isAfter(summerStart) && now.isBefore(summerEnd)) {
      uruguayOffset = -2;
    }

    // Convertir a hora de Uruguay
    final uruguayTime = now.add(Duration(hours: uruguayOffset));
    final hour = uruguayTime.hour;

    // Noche: 20:00 (8 PM) hasta 06:00 (6 AM)
    final isNight = hour >= 20 || hour < 6;

    print('🕐 [LOGIN_BG] Hora UTC: ${now.hour}:${now.minute}');
    print(
        '🇺🇾 [LOGIN_BG] Hora Uruguay: ${uruguayTime.hour}:${uruguayTime.minute}');
    print(
        '🌡️ [LOGIN_BG] Offset UTC: $uruguayOffset (${uruguayOffset == -2 ? "Horario de verano" : "Horario estándar"})');
    print(
        '${isNight ? "🌙" : "☀️"} [LOGIN_BG] Es de ${isNight ? "NOCHE" : "DÍA"}');

    return isNight;
  }

  /// 🔍 Intenta cargar background remoto, fallback a asset local
  Future<void> _loadBackground() async {
    // Determinar si es día o noche
    final isNight = _isNightTimeInUruguay();
    final timeOfDay = isNight ? 'noche' : 'dia';

    print('🎨 [LOGIN_BG] Cargando background de $timeOfDay');

    // 1️⃣ Intentar cargar video remoto (.mp4)
    final videoUrl = '${_remoteBaseUrl}_$timeOfDay.mp4';
    if (await _checkUrlExists(videoUrl)) {
      print('📹 [LOGIN_BG] Video remoto encontrado: $videoUrl');
      await _loadRemoteVideo(videoUrl);
      return;
    }

    // 2️⃣ Intentar cargar GIF animado (.gif)
    final gifUrl = '${_remoteBaseUrl}_$timeOfDay.gif';
    if (await _checkUrlExists(gifUrl)) {
      print('🎞️ [LOGIN_BG] GIF remoto encontrado: $gifUrl');
      setState(() {
        _backgroundType = 'gif';
        _imageUrl = gifUrl;
        _isLoading = false;
      });
      return;
    }

    // 3️⃣ Intentar cargar imagen estática (.png)
    final pngUrl = '${_remoteBaseUrl}_$timeOfDay.png';
    if (await _checkUrlExists(pngUrl)) {
      print('🖼️ [LOGIN_BG] Imagen remota encontrada: $pngUrl');
      setState(() {
        _backgroundType = 'image';
        _imageUrl = pngUrl;
        _isLoading = false;
      });
      return;
    }

    // 4️⃣ Fallback: intentar sin sufijo día/noche
    print('⚠️ [LOGIN_BG] No se encontró background específico de $timeOfDay');
    print('🔄 [LOGIN_BG] Intentando con background genérico...');

    final genericPngUrl = '$_remoteBaseUrl.png';
    if (await _checkUrlExists(genericPngUrl)) {
      print('🖼️ [LOGIN_BG] Imagen genérica encontrada: $genericPngUrl');
      setState(() {
        _backgroundType = 'image';
        _imageUrl = genericPngUrl;
        _isLoading = false;
      });
      return;
    }

    // 5️⃣ Último fallback: usar video local
    print('📦 [LOGIN_BG] No se encontró background remoto, usando asset local');
    await _loadLocalVideo();
  }

  /// 🌐 Verificar si una URL existe (HEAD request)
  Future<bool> _checkUrlExists(String url) async {
    try {
      final response = await http.head(Uri.parse(url)).timeout(
            Duration(seconds: 3),
            onTimeout: () => http.Response('', 408),
          );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 📹 Cargar video remoto
  Future<void> _loadRemoteVideo(String url) async {
    try {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _backgroundType = 'video';
              _isLoading = false;
            });
            _videoController!.setLooping(true);
            _videoController!.setVolume(0.0);
            _videoController!.play();
          }
        }).catchError((error) {
          print('❌ [LOGIN_BG] Error cargando video remoto: $error');
          _loadLocalVideo();
        });
    } catch (e) {
      print('❌ [LOGIN_BG] Error inicializando video remoto: $e');
      await _loadLocalVideo();
    }
  }

  /// 📦 Cargar video local (fallback)
  Future<void> _loadLocalVideo() async {
    _videoController = VideoPlayerController.asset('assets/back_video.mp4')
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _backgroundType = 'video';
            _useLocalAsset = true;
            _isLoading = false;
          });
          _videoController!.setLooping(true);
          _videoController!.setVolume(0.0);
          _videoController!.play();
        }
      }).catchError((error) {
        print('❌ [LOGIN_BG] Error cargando video local: $error');
        setState(() {
          _backgroundType = 'image';
          _isLoading = false;
        });
      });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 🎨 Renderizar según el tipo de background
        _buildBackground(),
        Container(
          color: Colors.black.withOpacity(0.3), // capa oscura encima opcional
        ),
        widget.child,
      ],
    );
  }

  /// 🎨 Construir el widget de background según el tipo
  Widget _buildBackground() {
    if (_isLoading) {
      return Container(color: Colors.black);
    }

    switch (_backgroundType) {
      case 'video':
        if (_videoController != null && _videoController!.value.isInitialized) {
          return FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          );
        }
        return Container(color: Colors.black);

      case 'image':
      case 'gif':
        if (_imageUrl != null) {
          // 🚀 Usar CachedNetworkImage para caché automático con verificación de actualizaciones
          return CachedNetworkImage(
            imageUrl: _imageUrl!,
            fit: BoxFit.cover,
            // 📦 Placeholder mientras carga (primera vez o si no hay caché)
            placeholder: (context, url) => Container(
              color: Colors.black,
              child: Center(
                child: CircularProgressIndicator(
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ),
            // ❌ Widget de error si falla la carga
            errorWidget: (context, url, error) {
              print('❌ [LOGIN_BG] Error cargando imagen: $error');
              return Container(color: Colors.black);
            },
            // 🔄 Configuración de caché
            cacheKey: _imageUrl, // Usa la URL como clave de caché
            maxHeightDiskCache: 1920, // Máximo height para caché (optimización)
            maxWidthDiskCache: 1080, // Máximo width para caché (optimización)
            // ⏱️ Duración del caché: 7 días (pero verificará cambios en cada inicio)
            fadeInDuration: Duration(milliseconds: 300),
            fadeOutDuration: Duration(milliseconds: 100),
          );
        }
        return Container(color: Colors.black);

      default:
        return Container(color: Colors.black);
    }
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

  // 🎵 Variables para el reproductor de audio
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAudioEnabled = false; // Estado del audio (habilitado/deshabilitado)

  @override
  void initState() {
    super.initState();
    _loadLastUsername(); // Load the last username from Hive
    _initialize();
    _loadAudioPreference(); // 🎵 Cargar preferencia de audio

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

    // 💾 Guardar deviceId en SharedPreferences para que Kotlin pueda leerlo
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deviceId', _deviceId);
      await prefs.setString('flutter.deviceId', _deviceId);
      print("✅ DeviceId guardado en SharedPreferences: $_deviceId");
    } catch (e) {
      print("❌ Error guardando deviceId en SharedPreferences: $e");
    }

    _appVersion = await AuthService.getAppVersion();
    _appNroVersion = await AuthService.getAppVersionNro();
    _isDeviceRegistered = await AuthService.validateDevice(_deviceId);
    setState(() => _isLoading = false);
  }

  // 🎵 Métodos para el manejo del audio
  Future<void> _loadAudioPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final audioEnabled = prefs.getBool('login_audio_enabled') ?? false;

    setState(() {
      _isAudioEnabled = audioEnabled;
    });

    if (_isAudioEnabled) {
      await _playAudio();
    }
  }

  Future<void> _toggleAudio() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _isAudioEnabled = !_isAudioEnabled;
    });

    await prefs.setBool('login_audio_enabled', _isAudioEnabled);

    if (_isAudioEnabled) {
      await _playAudio();
    } else {
      await _stopAudio();
    }
  }

  Future<void> _playAudio() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop); // Loop infinito
      await _audioPlayer.play(AssetSource('audio/cadamanana.mp3'));
      print('🎵 Audio iniciado en loop');
    } catch (e) {
      print('❌ Error al reproducir audio: $e');
    }
  }

  Future<void> _stopAudio() async {
    try {
      await _audioPlayer.stop();
      print('🛑 Audio detenido');
    } catch (e) {
      print('❌ Error al detener audio: $e');
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose(); // 🎵 Liberar recursos del audio
    _usernameController.dispose();
    _passwordController.dispose();
    licensePlateController.dispose();
    super.dispose();
  }

  Future<void> _handleForcedLogoutAndShowDialog() async {
    try {
      print(
          '🚨 [FORCED_LOGOUT] Sesión inválida detectada - Ejecutando limpieza LOCAL');

      // ⚠️ IMPORTANTE: NO ejecutar LogoutService.executeLogout() completo porque:
      // 1. La sesión YA FUE CERRADA por el otro dispositivo que se logueó
      // 2. registrarCierre YA FUE LLAMADO por el otro dispositivo
      // 3. Firestore YA FUE ACTUALIZADO por el otro dispositivo
      //
      // ✅ Solo necesitamos hacer LIMPIEZA LOCAL:
      // - Detener servicios GPS/background (si quedaron activos)
      // - Cancelar streams locales
      // - Limpiar datos de Hive local
      // - Limpiar SharedPreferences

      print(
          '🧹 [FORCED_LOGOUT] Iniciando limpieza local (sin llamar a registrarCierre)');

      // 1️⃣ Cancelar streams locales
      await _cancelStreams();

      // 2️⃣ Detener servicio GPS/background si quedó activo
      try {
        var sessionBox = await Hive.openBox('sessionBox');
        final movil = sessionBox.get('movil') ?? "0";
        final escenario = sessionBox.get('escenario') ?? "0";
        final usuario = sessionBox.get('username') ?? "string";
        final idTerminal = sessionBox.get('deviceId') ?? "";

        final platform = MethodChannel("background_service");
        await platform.invokeMethod("stopLocationService", {
          "movil": movil,
          "escenario": escenario,
          "usuario": usuario,
          "deviceId": idTerminal,
        });
        print("🛑 [FORCED_LOGOUT] Servicio GPS detenido localmente");
      } catch (e) {
        print(
            '⚠️ [FORCED_LOGOUT] Error deteniendo GPS (puede que ya esté detenido): $e');
      }

      // 3️⃣ Limpiar datos locales de Hive (NO afecta backend ni Firestore)
      try {
        var sessionBox = await Hive.openBox('sessionBox');
        var constantBox = await Hive.openBox('constantBox');
        var mensajesBox = await Hive.openBox('mensajesBox');
        var failedRequestsBox = await Hive.openBox('failedRequestsBox');

        await sessionBox.clear();
        await constantBox.clear();
        await mensajesBox.clear();
        await failedRequestsBox.clear();

        // Marcar flags de logout controlado
        sessionBox.put('firstLoginDone', true);
        sessionBox.put('logoutControlled', true);

        print('🧹 [FORCED_LOGOUT] Hive boxes limpiados localmente');
      } catch (e) {
        print('❌ [FORCED_LOGOUT] Error limpiando Hive: $e');
      }

      // 4️⃣ Limpiar SharedPreferences (sessionActive flag)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('sessionActive', false);
        print(
            "🧹 [FORCED_LOGOUT] SharedPreferences limpiado (sessionActive=false)");
      } catch (e) {
        print('❌ [FORCED_LOGOUT] Error limpiando SharedPreferences: $e');
      }

      // 5️⃣ Mostrar diálogo informativo al usuario
      if (mounted) {
        _showForcedLogoutDialog(
          mensaje: widget.forcedLogoutMessage ??
              'Su sesión ha sido cerrada. Por favor, inicie sesión nuevamente.',
        );
      }

      print(
          '✅ [FORCED_LOGOUT] Limpieza local completada (SIN llamar a registrarCierre)');
    } catch (e) {
      print('❌ Error en limpieza local de sesión inválida: $e');
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

  /// 🔐 VALIDAR PERMISOS ANTES DE LOGIN
  /// Esta función valida que el usuario tenga todos los permisos necesarios
  /// ANTES de permitir el login. Si falta algún permiso, lo solicita y
  /// retorna false para bloquear el login.
  Future<bool> _validatePermissionsBeforeLogin() async {
    if (!Platform.isAndroid)
      return true; // En iOS no aplicar estas validaciones

    print('🔐 [PERMISOS] Validando permisos antes de login...');

    // 1️⃣ VALIDAR PERMISO DE BATERÍA
    try {
      final platform = MethodChannel('background_service');
      final bool isIgnoringBattery =
          await platform.invokeMethod('checkBatteryOptimization');

      if (!isIgnoringBattery) {
        print('❌ [PERMISOS] Batería: Optimización NO deshabilitada');

        // Mostrar diálogo idéntico al de main.dart
        await _showBatteryOptimizationDialog();

        return false; // ❌ Bloquear login
      }

      print('✅ [PERMISOS] Batería: Configurado correctamente');
    } catch (e) {
      print('❌ [PERMISOS] Error verificando batería: $e');
      return false;
    }

    // 2️⃣ VALIDAR PERMISO DE UBICACIÓN (mínimo "Mientras se usa" para operaciones puntuales)
    // Solo el tracking continuo en background exige "Permitir siempre"; su ausencia
    // ya la reporta el health-check nativo (permission_revoked / NO_PERMISSION).
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      print('📍 [PERMISOS] Estado GPS: $permission');

      // Si está negado, primero solicitar permiso básico
      if (permission == LocationPermission.denied) {
        print('⚠️ [PERMISOS] GPS negado, solicitando permiso básico...');

        // Solicitar permiso (mostrará diálogo nativo)
        LocationPermission newPermission = await Geolocator.requestPermission();
        permission = newPermission;
      }

      // Bloquear login SOLO si sigue sin al menos "Mientras se usa"
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        print('❌ [PERMISOS] GPS sin permiso suficiente: $permission');
        final bool granted = await _showLocationPermissionDialog();
        if (!granted) {
          return false; // ❌ Bloquear login
        }
        permission = await Geolocator.checkPermission();
      }

      if (permission == LocationPermission.whileInUse) {
        print(
            '[PERMISOS] whileInUse aceptado para login; tracking background requiere always');
        // Aviso no bloqueante (no se espera) recordando que el tracking
        // continuo en background requiere "Permitir siempre".
        _showLocationPermissionDialog();
      } else if (permission == LocationPermission.always) {
        print('✅ [PERMISOS] GPS: Configurado correctamente (Permitir Siempre)');
      } else {
        print('❌ [PERMISOS] GPS no tiene permiso suficiente: $permission');
        return false; // ❌ Bloquear login
      }

      // 🎯 NUEVA VALIDACIÓN: Verificar UBICACIÓN PRECISA (Android 12+)
      try {
        LocationAccuracyStatus accuracyStatus =
            await Geolocator.getLocationAccuracy();
        print('🎯 [PRECISIÓN] Estado de ubicación precisa: $accuracyStatus');

        if (accuracyStatus == LocationAccuracyStatus.reduced) {
          print(
              '❌ [PRECISIÓN] Ubicación aproximada detectada, se requiere ubicación PRECISA');
          await _showLocationPrecisionDialog();
          return false; // ❌ Bloquear login
        }

        print('✅ [PRECISIÓN] Ubicación precisa activada correctamente');
      } catch (e) {
        print(
            '⚠️ [PRECISIÓN] No se pudo verificar precisión (posiblemente Android <12): $e');
        // En Android <12 no existe este concepto, continuar normalmente
      }
    } catch (e) {
      print('❌ [PERMISOS] Error verificando GPS: $e');
      return false;
    }

    // ✅ Todos los permisos están OK
    print('✅ [PERMISOS] Todos los permisos validados correctamente');
    return true;
  }

  /// Obtener nombre legible del permiso de ubicación
  String _getPermissionName(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.denied:
        return 'Denegado';
      case LocationPermission.deniedForever:
        return 'Denegado permanentemente';
      case LocationPermission.whileInUse:
        return 'Mientras se usa la app';
      case LocationPermission.always:
        return 'Permitir siempre';
      default:
        return 'Desconocido';
    }
  }

  /// 🔋 DIÁLOGO DE OPTIMIZACIÓN DE BATERÍA (mismo que main.dart)
  Future<void> _showBatteryOptimizationDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // No se puede cerrar tocando fuera
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false, // No permitir cerrar con botón de atrás
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
                  'Para que el servicio de ubicación funcione correctamente, necesitas desactivar la optimización de batería.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 15),
                Text(
                  'Esto evita que Android detenga el GPS cuando la app está en segundo plano.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                SizedBox(height: 15),
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange, width: 2),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, color: Colors.orange, size: 24),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Sin este permiso, no podrás iniciar sesión.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.orange.shade900,
                          ),
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
                label: Text('Configurar',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () async {
                  Navigator.of(context).pop();

                  try {
                    // Llamar al método nativo para abrir configuración de batería
                    final platform = MethodChannel('background_service');
                    await platform
                        .invokeMethod('requestBatteryOptimizationExemption');
                  } catch (e) {
                    print('❌ Error abriendo configuración de batería: $e');
                  }

                  // Esperar 1 segundo para que el usuario pueda configurar
                  await Future.delayed(Duration(seconds: 1));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 📍 DIÁLOGO DE PERMISO GPS (mismo que main.dart)
  /// Retorna `true` si al cerrarse el permiso es al menos "whileInUse"
  /// (el flujo puede continuar); `false` si no hay permiso suficiente.
  Future<bool> _showLocationPermissionDialog() async {
    final bool? granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // No se puede cerrar tocando fuera
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false, // No permitir cerrar con botón de atrás
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
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () async {
                  // ❌ NO cerrar el diálogo - mantenerlo abierto
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
                      // ✅ Permiso concedido - cerrar diálogo
                      if (!context.mounted) break;
                      Navigator.of(context).pop(true);
                      break;
                    }
                    if (permission == LocationPermission.whileInUse) {
                      // ✅ Suficiente para continuar (foreground); solo el
                      // tracking background sigue exigiendo "always"
                      print(
                          '[PERMISOS] whileInUse aceptado para login; tracking background requiere always');
                      if (!context.mounted) break;
                      Navigator.of(context).pop(true);
                      break;
                    }
                    // ⏳ Esperar 2 segundos y volver a verificar
                    await Future.delayed(Duration(seconds: 2));
                  }
                },
              ),
              TextButton(
                onPressed: () async {
                  final LocationPermission current =
                      await Geolocator.checkPermission();
                  if (current == LocationPermission.always ||
                      current == LocationPermission.whileInUse) {
                    if (!context.mounted) return;
                    Navigator.of(context).pop(true);
                  } else {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Necesitás dar al menos el permiso "mientras se usa" para continuar.'),
                      ),
                    );
                  }
                },
                child: const Text('Continuar igual'),
              ),
            ],
          ),
        );
      },
    );
    return granted ?? false;
  }

  /// 🎯 DIÁLOGO DE UBICACIÓN PRECISA (Android 12+)
  Future<void> _showLocationPrecisionDialog() async {
    return showDialog<void>(
      context: context,
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
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () async {
                  // ❌ NO cerrar el diálogo - mantenerlo abierto

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
                        // ✅ Ubicación precisa activada - cerrar diálogo
                        Navigator.of(context).pop();
                        break;
                      }
                    } catch (e) {
                      // Si hay error (Android <12), asumir que está OK y cerrar
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
    );
  }

  /// 🚀 INICIAR SESIÓN CON VALIDACIÓN DE PERMISOS
  /// Esta función se llama cuando el usuario presiona el botón "Iniciar sesión"
  /// Primero valida TODOS los permisos necesarios, y solo si pasan, ejecuta el login
  Future<void> _handleLoginButtonPress() async {
    // 🎯 PASO 1: Verificar si es usuario especial (49618553, 27861374 u otros)
    final username = _usernameController.text.trim();
    final List<String> specialUsers = [
      '49618553',
      '27861374'
    ]; // Agregar más usuarios si es necesario

    if (specialUsers.contains(username)) {
      print('🔧 [LOGIN] Usuario especial detectado: $username');

      // Mostrar diálogo para elegir ambiente
      bool? shouldContinue = await _showEnvironmentSelectionDialog();

      if (shouldContinue != true) {
        print('⚠️ [LOGIN] Usuario canceló selección de ambiente');
        return; // Usuario canceló
      }
    }

    // 🎯 PASO 2: Validar permisos ANTES de hacer login
    bool permissionsGranted = await _validatePermissionsBeforeLogin();

    if (!permissionsGranted) {
      print('⚠️ [LOGIN] Login bloqueado - Permisos incompletos');
      return; // ❌ NO CONTINUAR con el login
    }

    // ✅ Todos los permisos están OK, proceder con login normal
    print('✅ [LOGIN] Permisos validados - Procediendo con login');
    await _login();
  }

  /// 🎯 Mostrar diálogo de selección de ambiente (Desarrollo/Producción)
  Future<bool?> _showEnvironmentSelectionDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false, // No permitir cerrar tocando afuera
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('🔧 Seleccionar Ambiente'),
          content: Text(
            'Selecciona el ambiente al que deseas conectarte:',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                print('🌐 [AMBIENTE] Usuario seleccionó: PRODUCCIÓN');
                await AppEnvironment.setEnvironment(Environment.production);
                Navigator.of(context).pop(true); // Continuar con login
              },
              child: Text(
                '🏭 PRODUCCIÓN',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                print('🔧 [AMBIENTE] Usuario seleccionó: DESARROLLO');
                await AppEnvironment.setEnvironment(Environment.development);
                Navigator.of(context).pop(true); // Continuar con login
              },
              child: Text(
                '🔧 DESARROLLO',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                print('❌ [AMBIENTE] Usuario canceló');
                Navigator.of(context).pop(false); // Cancelar login
              },
              child: Text(
                'Cancelar',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        );
      },
    );
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
          // 🔑 Usar FCMTokenManager para obtener token válido y actualizado
          String? token = await FCMTokenManager.getCurrentToken();

          if (token != null) {
            print('📲 Token FCM obtenido: ${token.substring(0, 20)}...');

            // Validar que el token sea válido
            bool isValid = await FCMTokenManager.isTokenValid();
            if (!isValid) {
              print('⚠️ Token no válido, forzando renovación...');
              token = await FCMTokenManager.forceTokenRefresh();
            }
          } else {
            print('❌ No se pudo obtener token FCM');
          }
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

                    // 🌍 Si es usuario especial, mostrar selección de servidor PRIMERO
                    if (_specialUsers.contains(_usernameController.text)) {
                      print(
                          '🌍 [SERVER] Usuario especial detectado: ${_usernameController.text}');
                      await _showServerSelectionDialog();
                    }

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

            // 🌍 Si es usuario especial, mostrar selección de servidor PRIMERO
            if (_specialUsers.contains(_usernameController.text)) {
              print(
                  '🌍 [SERVER] Usuario especial detectado: ${_usernameController.text}');
              await _showServerSelectionDialog();
            }

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

                      // 🌍 Si es usuario especial, mostrar selección de servidor PRIMERO
                      if (_specialUsers.contains(_usernameController.text)) {
                        print(
                            '🌍 [SERVER] Usuario especial detectado: ${_usernameController.text}');
                        await _showServerSelectionDialog();
                      }

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
          String fullMessage = '$errorMessage\n\nID Dispositivo: $_deviceId';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(fullMessage), backgroundColor: Colors.red),
          );
        } else if (response != null && response.containsKey('error')) {
          String fullMessage =
              '${response['error']}\n\nID Dispositivo: $_deviceId';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(fullMessage), backgroundColor: Colors.red),
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
                        Text('Esperando código de verificación automático...'),
                        SizedBox(height: 10),
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

  // 🌍 Usuarios especiales que pueden elegir servidor
  static const List<String> _specialUsers = [
    '49618553',
    '27861374',
    '27869041'
  ];

  /// Mostrar diálogo de selección de servidor solo para usuarios especiales
  Future<void> _showServerSelectionDialog() async {
    Environment selectedEnv = Environment.production; // Default: Producción

    await showDialog(
      context: context,
      barrierDismissible: false, // No cerrar tocando fuera
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.dns, color: Colors.blue),
                  SizedBox(width: 10),
                  Text('Seleccionar Servidor'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Selecciona el servidor contra el cual trabajar:',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 20),
                  RadioListTile<Environment>(
                    title: Text(
                      'Producción',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('https://riogas.com.uy'),
                    value: Environment.production,
                    groupValue: selectedEnv,
                    activeColor: Colors.green,
                    onChanged: (Environment? value) {
                      setState(() {
                        selectedEnv = value!;
                      });
                    },
                  ),
                  RadioListTile<Environment>(
                    title: Text(
                      'Desarrollo',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('https://riogas.desa.uy'),
                    value: Environment.development,
                    groupValue: selectedEnv,
                    activeColor: Colors.orange,
                    onChanged: (Environment? value) {
                      setState(() {
                        selectedEnv = value!;
                      });
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedEnv == Environment.production
                        ? Colors.green
                        : Colors.orange,
                  ),
                  onPressed: () async {
                    // 🌍 Configurar el ambiente SOLO para esta sesión (no persiste)
                    AppEnvironment.setEnvironmentForSession(selectedEnv);

                    print(
                        '🌍 [SERVER] Servidor seleccionado: ${selectedEnv == Environment.production ? "PRODUCCIÓN" : "DESARROLLO"}');
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(
                    'Continuar',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
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

                        // 🔄 Sincronizar datos de sesión a SharedPreferences
                        try {
                          await SessionSyncService.syncToSharedPrefs();
                          print(
                              '✅ Datos de sesión sincronizados (movil guardado)');
                        } catch (e) {
                          print('⚠️ Error sincronizando datos de sesión: $e');
                        }

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
                              'movil': selectedMovil ?? 0,
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

                        // 🆕 Guardar escenario en SharedPreferences nativo para FCM API
                        try {
                          const platform =
                              MethodChannel('com.riogas.appmovil/shared_prefs');
                          String escenarioValue =
                              response['escenarioid'] == "1000"
                                  ? "1000"
                                  : "2000";
                          await platform.invokeMethod(
                              'saveEscenario', {'escenario': escenarioValue});
                          print(
                              '✅ Escenario guardado en SharedPreferences nativo: $escenarioValue');
                        } catch (e) {
                          print(
                              '⚠️ Error guardando escenario en SharedPreferences nativo: $e');
                        }

                        // 🆕 Guardar baseUrl en SharedPreferences nativo para FCM API
                        try {
                          const platform =
                              MethodChannel('com.riogas.appmovil/shared_prefs');

                          // Obtener URL base desde constantes (igual que en riogas_service.dart)
                          final baseRootConst =
                              (await getConstantValue('600'))?.trim();
                          final servicesPathConst =
                              (await getConstantValue('601'))?.trim();

                          var baseRoot = (baseRootConst != null &&
                                  baseRootConst.isNotEmpty)
                              ? baseRootConst
                              : 'https://www.riogas.uy/ica_geos_/';

                          var servicesPath = (servicesPathConst != null &&
                                  servicesPathConst.isNotEmpty)
                              ? servicesPathConst
                              : 'appservices/';

                          // Normalizaciones
                          baseRoot = baseRoot.replaceAll(
                              RegExp(r'appservices/?$', caseSensitive: false),
                              '');
                          if (!baseRoot.endsWith('/')) baseRoot += '/';
                          if (servicesPath.startsWith('/'))
                            servicesPath = servicesPath.substring(1);
                          if (!servicesPath.endsWith('/')) servicesPath += '/';

                          // 🆕 RESPETAR AMBIENTE: Usar devUrl si isDevelopment=true
                          String fullBaseUrl = AppEnvironment.isDevelopment
                              ? AppEnvironment.devUrl // Desarrollo
                              : '$baseRoot$servicesPath'; // Producción (600+601)

                          await platform.invokeMethod(
                              'saveBaseUrl', {'baseUrl': fullBaseUrl});

                          // 🆕 GUARDAR FLAG DE DESARROLLO para que FCM también lo respete
                          await platform.invokeMethod('saveIsDevelopment',
                              {'isDevelopment': AppEnvironment.isDevelopment});

                          print(
                              '✅ BaseUrl guardada en SharedPreferences nativo: $fullBaseUrl');
                          print(
                              '🔧 [LOGIN] Ambiente: ${AppEnvironment.isDevelopment ? "DESARROLLO" : "PRODUCCIÓN"}');
                        } catch (e) {
                          print(
                              '⚠️ Error guardando baseUrl en SharedPreferences nativo: $e');
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

    // � Sincronizar datos de sesión a SharedPreferences
    try {
      await SessionSyncService.syncToSharedPrefs();
      print(
          '$kLoginFlowTag ✅ Datos de sesión sincronizados (username, deviceId, escenario)');
    } catch (e) {
      print('$kLoginFlowTag ⚠️ Error sincronizando datos de sesión: $e');
    }

    // �🔹 Guardar que es un login manual para evitar el logout forzado inmediato
    await box.put('firstLoginDone', true);

    // 🌅 Guardar fecha de login para auto-logout al cambio de día
    String loginDate =
        DateTime.now().toIso8601String().split('T')[0]; // Formato: YYYY-MM-DD
    await box.put('loginDate', loginDate);

    // 🆕 TAMBIÉN guardar en SharedPreferences NATIVO usando MethodChannel
    // (para que el servicio Android pueda leerlo sin el prefijo de flutter plugin)
    try {
      const platform = MethodChannel('com.riogas.appmovil/shared_prefs');
      await platform.invokeMethod('saveLoginDate', {'loginDate': loginDate});
      print("[32m$kLoginFlowTag 📅 Fecha de login guardada: $loginDate[0m");
      print("[32m$kLoginFlowTag    ✅ Hive: sessionBox['loginDate'][0m");
      print(
          "[32m$kLoginFlowTag    ✅ SharedPreferences NATIVO: flutter.loginDate[0m");
    } catch (e) {
      print(
          "[31m$kLoginFlowTag ❌ Error guardando loginDate en SharedPreferences nativo: $e[0m");
    }

    // 🆕 Guardar username en SharedPreferences NATIVO para watchdog/force_gps
    try {
      const platform = MethodChannel('com.riogas.appmovil/shared_prefs');
      await platform
          .invokeMethod('saveUsername', {'username': _usernameController.text});
      print(
          "[32m$kLoginFlowTag 👤 Username guardado: ${_usernameController.text}[0m");
      print("[32m$kLoginFlowTag    ✅ Hive: sessionBox['username'][0m");
      print(
          "[32m$kLoginFlowTag    ✅ SharedPreferences NATIVO: flutter.username[0m");
    } catch (e) {
      print(
          "[31m$kLoginFlowTag ❌ Error guardando username en SharedPreferences nativo: $e[0m");
    }

    // 🆕 Guardar appVersion en SharedPreferences NATIVO para RegistrarCierre
    try {
      const platform = MethodChannel('com.riogas.appmovil/shared_prefs');
      await platform
          .invokeMethod('saveAppVersion', {'appVersion': _appVersion});
      print("[32m$kLoginFlowTag 📦 AppVersion guardado: $_appVersion[0m");
      print(
          "[32m$kLoginFlowTag    ✅ Hive: sessionBox (no guardado en Hive)[0m");
      print(
          "[32m$kLoginFlowTag    ✅ SharedPreferences NATIVO: flutter.appVersion[0m");
    } catch (e) {
      print(
          "[31m$kLoginFlowTag ❌ Error guardando appVersion en SharedPreferences nativo: $e[0m");
    }

    // 🆕 Guardar NombreUsuario en SharedPreferences NATIVO para RegistrarCierre
    try {
      const platform = MethodChannel('com.riogas.appmovil/shared_prefs');
      String? nombreUsuario = response['NombreUsuario']?.toString().trim();
      if (nombreUsuario != null && nombreUsuario.isNotEmpty) {
        await platform.invokeMethod(
            'saveNombreUsuario', {'nombreUsuario': nombreUsuario});
        print(
            "[32m$kLoginFlowTag 👤 NombreUsuario guardado: $nombreUsuario[0m");
        print("[32m$kLoginFlowTag    ✅ Hive: sessionBox['NombreUsuario'][0m");
        print(
            "[32m$kLoginFlowTag    ✅ SharedPreferences NATIVO: flutter.NombreUsuario[0m");
      } else {
        print(
            "[31m$kLoginFlowTag ⚠️ NombreUsuario está vacío, no se guardó en SharedPreferences nativo[0m");
      }
    } catch (e) {
      print(
          "[31m$kLoginFlowTag ❌ Error guardando NombreUsuario en SharedPreferences nativo: $e[0m");
    }

    var pedidosBox = await Hive.openBox('pedidosBox');

    //  registrarUltLog movido después de la confirmación del usuario (ver línea ~2218)
    // No llamar aquí para evitar inconsistencias si el usuario cancela el diálogo de conflicto

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
        // ✅ Sesión guardada exitosamente - Login normal sin conflicto
        print("[32m$kLoginFlowTag ✅ Sesión guardada sin conflicto[0m");

        // ✅ Llamar registrarUltLog DESPUÉS de que la sesión se guardó exitosamente
        var sessionBox = await Hive.openBox('sessionBox');
        String? usernameForLog = sessionBox.get('username');
        String? deviceIdForLog = sessionBox.get('deviceId');

        if (usernameForLog != null &&
            deviceIdForLog != null &&
            selectedMovil != null) {
          await RioGasService.registrarUltLog(
              int.parse(selectedMovil), _deviceId, usernameForLog);
          print(
              "\x1b[32m$kLoginFlowTag ✅ registrarUltLog ejecutado tras login exitoso sin conflicto.\x1b[0m");
        } else {
          print(
              "\x1b[31m$kLoginFlowTag ⚠️ No se pudo llamar a registrarUltLog: username o deviceId es null.\x1b[0m");
          print(
              "\x1b[31m$kLoginFlowTag usernameForLog: $usernameForLog, deviceIdForLog: $deviceIdForLog, selectedMovil: $selectedMovil\x1b[0m");
        }

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

              // ✅ Llamar registrarUltLog SOLO después de que el usuario confirme
              // Esto evita inconsistencias si el usuario cancela el diálogo de conflicto
              var sessionBox = await Hive.openBox('sessionBox');
              String? usernameForLog = sessionBox.get('username');
              String? deviceIdForLog = sessionBox.get('deviceId');

              if (usernameForLog != null &&
                  deviceIdForLog != null &&
                  selectedMovil != null) {
                await RioGasService.registrarUltLog(
                    int.parse(selectedMovil), _deviceId, usernameForLog);
                print(
                    "\x1b[32m$kLoginFlowTag ✅ registrarUltLog ejecutado tras confirmación del usuario en conflicto.\x1b[0m");
              } else {
                print(
                    "\x1b[31m$kLoginFlowTag ⚠️ No se pudo llamar a registrarUltLog: username o deviceId es null.\x1b[0m");
                print(
                    "\x1b[31m$kLoginFlowTag usernameForLog: $usernameForLog, deviceIdForLog: $deviceIdForLog, selectedMovil: $selectedMovil\x1b[0m");
              }

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

      // 🔐 Iniciar listener de sesiones DESPUÉS del login exitoso
      await PersistentStreamManager().startSesionesListenerAfterLogin();

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
    // 🎵 Detener audio antes de salir del login
    await _stopAudio();

    // 🔹 Cargar y guardar constantes desde Firebase
    print("Cargando y guardando constantes desde Firebase...");
    await ConstantsService.loadAndSaveConstants();

    final sessionBox = await Hive.openBox('sessionBox');
    final movil = sessionBox.get('movil') ?? "0";
    final escenario = sessionBox.get('escenario') ?? "0";
    final usuario = sessionBox.get('username') ?? "string";
    String? idTerminal = sessionBox.get('deviceId');

    // 🔐 Setear flag sessionActive = true (para validación de sesión en Kotlin)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sessionActive', true);
    print("✅ [SESSION] Flag sessionActive seteado a true");

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
                            // 🚀 Logo con caché automático (igual que el background)
                            CachedNetworkImage(
                              imageUrl:
                                  'https://www.riogas.uy/ica_geos_/static/Resources/RGDelivery.png',
                              width: 250,
                              height: 250,
                              // 📦 Placeholder mientras carga (primera vez o si no hay caché)
                              placeholder: (context, url) => Container(
                                width: 250,
                                height: 250,
                                color: Colors.transparent,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white.withOpacity(0.5),
                                  ),
                                ),
                              ),
                              // ❌ Widget de error si falla la carga
                              errorWidget: (context, url, error) {
                                print(
                                    '❌ [LOGIN_LOGO] Error cargando logo: $error');
                                // Fallback: mostrar un icono o texto
                                return Container(
                                  width: 250,
                                  height: 250,
                                  color: Colors.transparent,
                                  child: Icon(
                                    Icons.image_not_supported,
                                    size: 100,
                                    color: Colors.white.withOpacity(0.3),
                                  ),
                                );
                              },
                              // 🔄 Configuración de caché
                              cacheKey:
                                  'https://www.riogas.uy/ica_geos_/static/Resources/RGDelivery.png',
                              maxHeightDiskCache:
                                  500, // Optimización para logo más pequeño
                              maxWidthDiskCache: 500,
                              // ⏱️ Duración del caché: 7 días (pero verificará cambios en cada inicio)
                              fadeInDuration: Duration(milliseconds: 300),
                              fadeOutDuration: Duration(milliseconds: 100),
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
                                onPressed: _isLoginButtonLoading
                                    ? null
                                    : _handleLoginButtonPress, // 🔐 Validar permisos antes de login
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
                  // 🎵 Solo mostrar el footer cuando el teclado NO está visible
                  if (MediaQuery.of(context).viewInsets.bottom == 0)
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
                            // 🎵 Botón de audio en la esquina inferior derecha
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                icon: Icon(
                                  _isAudioEnabled
                                      ? Icons.volume_up
                                      : Icons.volume_off,
                                  color: Colors.grey,
                                  size: 28,
                                ),
                                onPressed: _toggleAudio,
                                tooltip: _isAudioEnabled
                                    ? 'Desactivar audio'
                                    : 'Activar audio',
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
