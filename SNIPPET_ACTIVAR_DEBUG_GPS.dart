// 🐞 SNIPPET PARA ACTIVAR DEBUG MODE DEL GPS SERVICE MANAGER
// Copiar y pegar este código en lib/main.dart

// 1️⃣ Agregar import al inicio del archivo (después de los otros imports)
import 'services/gps_service_manager.dart';

// 2️⃣ Dentro de la función main(), agregar DESPUÉS de WidgetsFlutterBinding.ensureInitialized()
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🐞 ACTIVAR DEBUG MODE DEL GPS SERVICE MANAGER
  // ⚠️ IMPORTANTE: Comentar esta línea en PRODUCCIÓN
  GpsServiceManager.setDebugMode(true); // ← AGREGAR ESTA LÍNEA

  print('🐞 [MAIN] GPS Service Manager Debug Mode: ACTIVADO');
  print('🔍 [MAIN] Logs disponibles con tag: [GPS_SERVICE_MANAGER]');

  // ... resto del código (Firebase.initializeApp, etc.)
}

// 📝 Para ver los logs en PowerShell:
// adb logcat | Select-String "GPS_SERVICE_MANAGER"

// 📝 Para desactivar en producción:
// GpsServiceManager.setDebugMode(false); // o comentar la línea
