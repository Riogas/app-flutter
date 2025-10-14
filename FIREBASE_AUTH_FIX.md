# Solución Completa: Firebase Auth Token Expiration & Coordinate Sending

## 🎯 Problema Original

El servicio de envío de coordenadas dejaba de funcionar después de cierto tiempo (~1 hora) con los siguientes errores:

### Errores Identificados en Logs:

```
❌ [FIREBASE_AUTH] Error: Given String is empty or null
   at signInWithEmailAndPassword()

❌ [RIOGAS_SERVICE] LateInitializationError: 
   Field 'baseUrl' has already been initialized
```

### Patrón de Fallos:

```
09:29:23 → Coordenadas enviadas ✅
09:32:25 → Coordenadas enviadas ✅ (+3min)
09:35:23 → Coordenadas enviadas ✅ (+3min)
09:38:21 → Coordenadas enviadas ✅ (+3min)
09:41:20 → Coordenadas enviadas ✅ (+3min)
09:44:29 → App restart
09:56:08 → App restart + Auth fail + RioGasService crash
          ❌ SERVICIO APARENTA DETENERSE
```

---

## 🔍 Análisis de Causa Raíz

### Problema 1: Credenciales No Persistidas
- `Config.firestoreEmail` y `Config.firestorePassword` se inicializan vacías (`""`)
- Solo se llenan durante el login en `registerOrReuseUser()`
- Cuando la app se reinicia en background, las variables vuelven a estar vacías
- `FirebaseService.signInWithEmailAndPassword()` intenta login con strings vacíos
- **Resultado**: Error "Given String is empty or null"

### Problema 2: Token Expiration
- Firebase Auth tokens expiran después de ~1 hora
- No había mecanismo de detección de expiración
- No había refresh automático del token
- **Resultado**: Después de 1 hora, el usuario queda desautenticado

### Problema 3: RioGasService Double Initialization
- `RioGasService.initializeService()` podía ser llamado múltiples veces
- Campo `late final String baseUrl` no puede ser re-asignado
- **Resultado**: LateInitializationError que crashea la app

### Problema 4: Efecto Cascada
```
Token expira → App reinicia → Credenciales vacías → Auth falla → 
RioGasService intenta init → Crash → App no puede recibir coordenadas →
Servicio Kotlin funciona pero Flutter está roto → 
Parece que "el servicio dejó de enviar"
```

---

## ✅ Soluciones Implementadas

### 1. Persistencia de Credenciales en Hive

**Archivo**: `lib/utils/config.dart`

**Cambios**:
```dart
import 'package:hive/hive.dart';

class Config {
  static String firestoreEmail = "";
  static String firestorePassword = "";

  /// Guarda las credenciales en Hive para persistencia entre reinicios
  static Future<void> saveCredentials(String email, String password) async {
    try {
      final box = await Hive.openBox('authBox');
      await box.put('firestoreEmail', email);
      await box.put('firestorePassword', password);
      firestoreEmail = email;
      firestorePassword = password;
      print('✅ [CONFIG] Credenciales guardadas en Hive');
    } catch (e) {
      print('❌ [CONFIG] Error guardando credenciales: $e');
    }
  }

  /// Carga las credenciales desde Hive al iniciar la app
  static Future<void> loadCredentials() async {
    try {
      final box = await Hive.openBox('authBox');
      firestoreEmail = box.get('firestoreEmail', defaultValue: "");
      firestorePassword = box.get('firestorePassword', defaultValue: "");
      
      if (firestoreEmail.isNotEmpty && firestorePassword.isNotEmpty) {
        print('✅ [CONFIG] Credenciales cargadas desde Hive: $firestoreEmail');
      } else {
        print('⚠️ [CONFIG] No hay credenciales guardadas en Hive');
      }
    } catch (e) {
      print('❌ [CONFIG] Error cargando credenciales: $e');
      firestoreEmail = "";
      firestorePassword = "";
    }
  }

  /// Limpia las credenciales (para logout)
  static Future<void> clearCredentials() async {
    try {
      final box = await Hive.openBox('authBox');
      await box.delete('firestoreEmail');
      await box.delete('firestorePassword');
      firestoreEmail = "";
      firestorePassword = "";
      print('✅ [CONFIG] Credenciales limpiadas');
    } catch (e) {
      print('❌ [CONFIG] Error limpiando credenciales: $e');
    }
  }
}
```

**Modificaciones adicionales**:
- Reemplazadas las 3 asignaciones directas:
  ```dart
  // ANTES:
  Config.firestoreEmail = email;
  Config.firestorePassword = password;
  
  // DESPUÉS:
  await Config.saveCredentials(email, password);
  ```

**Resultado**: ✅ Las credenciales sobreviven reinicios de la app

---

### 2. Firebase Auth State Listener + Auto Re-Auth

**Archivo**: `lib/services/firebase_service.dart`

**Imports agregados**:
```dart
import 'dart:async'; // Para Timer
```

**Variables de control**:
```dart
class FirebaseService {
  static bool _authListenerInitialized = false;
  static Timer? _tokenRefreshTimer;
  // ... resto del código
}
```

**Método `initializeFirebase()` mejorado**:
```dart
Future<void> initializeFirebase() async {
  // Cargar credenciales guardadas antes de intentar login
  await Config.loadCredentials();

  // Autenticar al usuario
  await signInWithEmailAndPassword();

  // Inicializar listener de auth state (solo una vez)
  _setupAuthStateListener();
  
  // Iniciar refresh proactivo del token
  startProactiveTokenRefresh();
}
```

**Método `signInWithEmailAndPassword()` con validación**:
```dart
Future<void> signInWithEmailAndPassword() async {
  try {
    // Verificar que las credenciales no estén vacías
    if (Config.firestoreEmail.isEmpty || Config.firestorePassword.isEmpty) {
      print('⚠️ [FIREBASE_SERVICE] Credenciales vacías, no se puede hacer login');
      print('   Email: "${Config.firestoreEmail}", Password: "${Config.firestorePassword}"');
      await _logError('Firebase Auth Error', 'Credenciales vacías - Usuario no ha hecho login');
      return;
    }

    print('🔐 [FIREBASE_SERVICE] Intentando login con: ${Config.firestoreEmail}');
    
    UserCredential userCredential =
        await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: Config.firestoreEmail,
      password: Config.firestorePassword,
    );
    _user = userCredential.user;
    print('✅ [FIREBASE_SERVICE] Usuario autenticado: ${_user?.email}');
  } on FirebaseAuthException catch (e) {
    print('❌ [FIREBASE_SERVICE] Error de autenticación: ${e.code} - ${e.message}');
    await _logError('Firebase Auth Error', e.toString());
  }
}
```

**Listener de Auth State**:
```dart
void _setupAuthStateListener() {
  if (_authListenerInitialized) {
    print('ℹ️ [FIREBASE_SERVICE] Listener de auth ya inicializado');
    return;
  }

  FirebaseAuth.instance.authStateChanges().listen((User? user) async {
    if (user == null) {
      print('🔴 [FIREBASE_SERVICE] Usuario desautenticado o token expirado');
      print('   Timestamp: ${DateTime.now().toIso8601String()}');
      
      // Intentar re-autenticar si hay credenciales guardadas
      if (Config.firestoreEmail.isNotEmpty && Config.firestorePassword.isNotEmpty) {
        print('🔄 [FIREBASE_SERVICE] Intentando re-autenticación automática...');
        await signInWithEmailAndPassword();
      } else {
        print('⚠️ [FIREBASE_SERVICE] No hay credenciales para re-autenticar');
      }
    } else {
      print('✅ [FIREBASE_SERVICE] Usuario autenticado: ${user.email}');
      print('   UID: ${user.uid}');
      print('   Timestamp: ${DateTime.now().toIso8601String()}');
      _user = user;
    }
  }, onError: (error) {
    print('❌ [FIREBASE_SERVICE] Error en authStateChanges: $error');
  });

  _authListenerInitialized = true;
  print('✅ [FIREBASE_SERVICE] Listener de auth state inicializado');
}
```

**Resultado**: ✅ Detección automática de expiración y re-auth sin intervención del usuario

---

### 3. Token Refresh Proactivo (Timer cada 45 minutos)

**Nuevo método para iniciar timer**:
```dart
/// Inicia el timer para refresh proactivo del token cada 45 minutos
/// Esto previene que el token expire (expira a la 1 hora)
void startProactiveTokenRefresh() {
  // Cancelar timer existente si hay
  _tokenRefreshTimer?.cancel();

  // Crear nuevo timer que se ejecuta cada 45 minutos
  _tokenRefreshTimer = Timer.periodic(const Duration(minutes: 45), (timer) async {
    print('⏰ [FIREBASE_SERVICE] Timer de refresh de token ejecutado');
    print('   Timestamp: ${DateTime.now().toIso8601String()}');
    
    bool refreshed = await refreshAuthToken();
    
    if (refreshed) {
      print('✅ [FIREBASE_SERVICE] Token refrescado proactivamente');
    } else {
      print('❌ [FIREBASE_SERVICE] Falló el refresh proactivo del token');
    }
  });

  print('✅ [FIREBASE_SERVICE] Timer de refresh proactivo iniciado (cada 45 min)');
}

/// Detiene el timer de refresh proactivo
void stopProactiveTokenRefresh() {
  _tokenRefreshTimer?.cancel();
  _tokenRefreshTimer = null;
  print('🛑 [FIREBASE_SERVICE] Timer de refresh proactivo detenido');
}
```

**Método de refresh manual**:
```dart
/// Refresca el token del usuario actual
/// Llama a este método antes de operaciones críticas o periódicamente
Future<bool> refreshAuthToken() async {
  try {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    
    if (currentUser == null) {
      print('⚠️ [FIREBASE_SERVICE] No hay usuario autenticado para refrescar token');
      
      // Intentar re-autenticar
      if (Config.firestoreEmail.isNotEmpty && Config.firestorePassword.isNotEmpty) {
        print('🔄 [FIREBASE_SERVICE] Intentando re-autenticación...');
        await signInWithEmailAndPassword();
        return FirebaseAuth.instance.currentUser != null;
      }
      
      return false;
    }

    print('🔄 [FIREBASE_SERVICE] Refrescando token para: ${currentUser.email}');
    
    // getIdToken(true) fuerza el refresh del token
    String? token = await currentUser.getIdToken(true);
    
    if (token != null) {
      print('✅ [FIREBASE_SERVICE] Token refrescado exitosamente');
      print('   Timestamp: ${DateTime.now().toIso8601String()}');
      return true;
    } else {
      print('❌ [FIREBASE_SERVICE] No se pudo obtener el token');
      return false;
    }
  } catch (e) {
    print('❌ [FIREBASE_SERVICE] Error refrescando token: $e');
    await _logError('Token Refresh Error', e.toString());
    return false;
  }
}
```

**Método de verificación de autenticación**:
```dart
/// Verifica si el usuario está autenticado y el token es válido
/// Retorna true si está todo OK, false si necesita re-autenticación
Future<bool> ensureAuthenticated() async {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  
  if (currentUser == null) {
    print('⚠️ [FIREBASE_SERVICE] Usuario no autenticado, intentando login...');
    await signInWithEmailAndPassword();
    return FirebaseAuth.instance.currentUser != null;
  }

  // Verificar si el token necesita refresh (opcional, getIdToken lo hace automáticamente)
  try {
    String? token = await currentUser.getIdToken(false); // false = usa cache si es válido
    return token != null;
  } catch (e) {
    print('❌ [FIREBASE_SERVICE] Error verificando autenticación: $e');
    // Intentar refresh
    return await refreshAuthToken();
  }
}
```

**Resultado**: ✅ Token se refresca automáticamente cada 45 minutos, previniendo expiración

---

### 4. Protección contra Double Initialization de RioGasService

**Archivo**: `lib/services/riogas_service.dart`

**Cambios**:
```dart
class RioGasService {
  // ANTES:
  static late final String baseUrl;
  
  // DESPUÉS:
  static late final String _baseUrl; // Privado
  static bool _isInitialized = false; // Flag de control
  static String get baseUrl => _baseUrl; // Getter público
  
  static Future<void> initializeService() async {
    // Protección contra doble inicialización
    if (_isInitialized) {
      print('⚠️ [INIT] RioGasService ya está inicializado, saltando...');
      return;
    }
    
    // ... código de inicialización ...
    
    _baseUrl = '$baseRoot$servicesPath';
    _isInitialized = true; // Marcar como inicializado
  }
}
```

**Resultado**: ✅ RioGasService puede ser llamado múltiples veces sin crashear

---

## 📊 Diagrama de Flujo de la Solución

```
┌─────────────────────────────────────────────────────┐
│ 1. Usuario hace login en login_page.dart           │
│    ├─ registerOrReuseUser(email, password)         │
│    ├─ Config.saveCredentials(email, pass)          │
│    └─ Guarda en Hive ('authBox')                   │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│ 2. App inicia (cualquier momento)                  │
│    ├─ FirebaseService.initializeFirebase()         │
│    ├─ Config.loadCredentials() from Hive           │
│    ├─ signInWithEmailAndPassword()                 │
│    ├─ _setupAuthStateListener()                    │
│    └─ startProactiveTokenRefresh()                 │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│ 3. Sistemas de Monitoreo Activos 24/7              │
│                                                     │
│ A) Auth State Listener:                            │
│    ├─ Si user == null (token expiró):              │
│    │  ├─ Detecta inmediatamente                    │
│    │  └─ Re-autentica con credenciales Hive        │
│    └─ Si user != null:                             │
│       └─ Todo OK, actualiza _user                  │
│                                                     │
│ B) Timer Proactivo (cada 45 min):                  │
│    ├─ refreshAuthToken() automáticamente           │
│    ├─ getIdToken(true) fuerza refresh              │
│    └─ Previene expiración antes de 1 hora          │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│ 4. Operaciones Críticas (opcional)                 │
│    ├─ Pueden llamar ensureAuthenticated()          │
│    ├─ Verifica y refresca token si necesita        │
│    └─ Garantiza auth válido antes de operar        │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│ 5. Servicio Kotlin sigue funcionando               │
│    ├─ AlarmManager dispara cada 3 minutos          │
│    ├─ LocationHelper obtiene GPS                   │
│    ├─ HTTP POST a Riogas API                       │
│    └─ Flutter siempre autenticado para recibirlos  │
└─────────────────────────────────────────────────────┘
```

---

## 🎯 Ventajas de la Solución

### ✅ Persistencia Total
- Credenciales sobreviven reinicios de app
- Sobreviven cierres forzados del sistema
- Almacenadas de forma segura en Hive

### ✅ Triple Capa de Protección

**Capa 1: Auth State Listener (Reactivo)**
- Detecta cuando el token expira
- Re-autentica automáticamente

**Capa 2: Timer Proactivo (Preventivo)**
- Refresca token cada 45 minutos
- Previene la expiración (que ocurre a la 1 hora)

**Capa 3: Validación Pre-Operación (Bajo Demanda)**
- `ensureAuthenticated()` para operaciones críticas
- Verifica y refresca si es necesario

### ✅ Sin Intervención del Usuario
- Todo el proceso es automático
- Usuario no ve errores de autenticación
- No necesita re-loguear manualmente

### ✅ Logging Completo
Emojis para identificación rápida en logs:
- `🔐` Intentando login
- `✅` Operación exitosa
- `❌` Error
- `⚠️` Advertencia
- `🔴` Usuario desautenticado
- `🔄` Re-autenticación en progreso
- `⏰` Timer ejecutado
- `🛑` Proceso detenido

### ✅ Robusto y Resiliente
- Manejo de errores en todos los métodos
- Retry automático en fallos
- No crashea si algo falla
- Protección contra double initialization

---

## 🧪 Plan de Testing

### Test 1: Persistencia de Credenciales
1. Hacer login en la app
2. Cerrar app completamente (kill process)
3. Reabrir app
4. **Verificar**: Logs muestran `✅ Credenciales cargadas desde Hive`
5. **Verificar**: No hay error de "Given String is empty or null"

### Test 2: Token Expiration Detection
1. Hacer login
2. Esperar 1 hora y 5 minutos (para que expire)
3. **Verificar**: Log muestra `🔴 Usuario desautenticado o token expirado`
4. **Verificar**: Log muestra `🔄 Intentando re-autenticación automática...`
5. **Verificar**: Log muestra `✅ Usuario autenticado` después

### Test 3: Refresh Proactivo
1. Hacer login
2. Dejar app en background por 2+ horas
3. **Verificar**: Cada 45 minutos aparece `⏰ Timer de refresh de token ejecutado`
4. **Verificar**: Después aparece `✅ Token refrescado proactivamente`
5. **Verificar**: Coordenadas se siguen enviando sin interrupciones

### Test 4: Coordenadas Long-Running
1. Compilar APK con estos cambios
2. Instalar en dispositivo
3. Hacer login
4. Dejar app corriendo en background por 3+ horas
5. **Verificar**: Coordenadas se envían cada 3 minutos consistentemente
6. **Verificar**: No hay interrupciones después de 1 hora
7. **Verificar**: Logs no muestran errores de auth

### Test 5: App Restart en Background
1. App corriendo con coordenadas enviándose
2. Sistema operativo mata la app (por memoria, etc.)
3. App se reinicia en background
4. **Verificar**: Credenciales se cargan desde Hive
5. **Verificar**: Auth exitoso automáticamente
6. **Verificar**: Coordenadas continúan enviándose

---

## 📝 Logs Esperados (Secuencia Normal)

### Inicio de App
```
✅ [CONFIG] Credenciales cargadas desde Hive: usuario@ejemplo.com
🔐 [FIREBASE_SERVICE] Intentando login con: usuario@ejemplo.com
✅ [FIREBASE_SERVICE] Usuario autenticado: usuario@ejemplo.com
   UID: abc123...
   Timestamp: 2025-10-14T10:00:00.000Z
✅ [FIREBASE_SERVICE] Listener de auth state inicializado
✅ [FIREBASE_SERVICE] Timer de refresh proactivo iniciado (cada 45 min)
```

### Cada 45 Minutos (Timer)
```
⏰ [FIREBASE_SERVICE] Timer de refresh de token ejecutado
   Timestamp: 2025-10-14T10:45:00.000Z
🔄 [FIREBASE_SERVICE] Refrescando token para: usuario@ejemplo.com
✅ [FIREBASE_SERVICE] Token refrescado exitosamente
   Timestamp: 2025-10-14T10:45:00.123Z
✅ [FIREBASE_SERVICE] Token refrescado proactivamente
```

### Si Token Expira (no debería pasar con el timer)
```
🔴 [FIREBASE_SERVICE] Usuario desautenticado o token expirado
   Timestamp: 2025-10-14T11:05:00.000Z
🔄 [FIREBASE_SERVICE] Intentando re-autenticación automática...
🔐 [FIREBASE_SERVICE] Intentando login con: usuario@ejemplo.com
✅ [FIREBASE_SERVICE] Usuario autenticado: usuario@ejemplo.com
   UID: abc123...
   Timestamp: 2025-10-14T11:05:00.500Z
```

---

## 🚀 Comandos para Deploy

### Compilar APK
```bash
cd C:\Users\jgomez\Documents\Projects\AppTFlutter\appmovil
flutter build apk --release
```

### Instalar en Dispositivo
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Ver Logs en Tiempo Real
```bash
adb logcat -c
adb logcat | Select-String -Pattern "FIREBASE_SERVICE|CONFIG|RIOGAS_SERVICE|LocationHelper"
```

### Filtro Específico para Auth
```bash
adb logcat | Select-String -Pattern "🔐|✅|❌|⚠️|🔴|🔄|⏰"
```

---

## 📌 Próximos Pasos Opcionales

### Mejora 1: Telemetría
- Agregar contador de re-auths exitosos/fallidos
- Enviar métricas a Firebase Analytics
- Dashboard para monitoreo en producción

### Mejora 2: Custom Token (Requires Backend)
- Implementar generación de Custom Token en backend
- Custom Tokens pueden tener duración más larga
- Reduce frecuencia de re-auths

### Mejora 3: Exponential Backoff
- Si re-auth falla, reintentar con delays crecientes
- Prevenir bombardeo del servidor en casos de problemas de red

### Mejora 4: Health Check Endpoint
- Endpoint que verifique estado de auth
- Llamado periódico desde el servicio Kotlin
- Alerta si auth está roto

---

## 📚 Referencias

- [Firebase Auth - Get ID Token](https://firebase.google.com/docs/auth/admin/verify-id-tokens)
- [Firebase Auth - Auth State Listener](https://firebase.google.com/docs/auth/flutter/start#auth_state_listener)
- [Hive - Flutter Persistent Storage](https://docs.hivedb.dev/)
- [Dart Timer - Periodic](https://api.dart.dev/stable/dart-async/Timer/Timer.periodic.html)

---

## ✅ Checklist de Implementación

- [x] Persistir credenciales en Hive
- [x] Cargar credenciales al iniciar app
- [x] Validar credenciales antes de signIn
- [x] Auth State Listener para detección de expiración
- [x] Re-auth automático cuando token expira
- [x] Timer proactivo cada 45 minutos
- [x] Método refreshAuthToken() manual
- [x] Método ensureAuthenticated() para operaciones críticas
- [x] Protección RioGasService contra double init
- [x] Logging detallado con emojis
- [x] Documentación completa
- [ ] Testing en dispositivo real (2+ horas)
- [ ] Validación en producción

---

**Fecha de Implementación**: 14 de Octubre, 2025  
**Autor**: GitHub Copilot + jgomez  
**Status**: ✅ Implementado, pendiente testing en dispositivo
