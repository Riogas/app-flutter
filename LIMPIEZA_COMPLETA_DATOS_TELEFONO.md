# 🧹 Limpieza Completa de Datos en Teléfono

## 🐛 Problema Detectado

Al desinstalar y reinstalar la app, **los datos persistían**:
- ✅ Usuario guardado en login (de Hive)
- ✅ URL antigua `190.64.89.170:8888` en SharedPreferences
- ✅ Configuraciones de ambiente previas

Esto significa que los datos NO se borraban correctamente al desinstalar.

## 🔍 Root Cause

### 1. SharedPreferences Persistentes
Android puede configurar SharedPreferences para que persistan en backup:
- `config` SharedPreferences con `baseUrl` antigua
- `FlutterSharedPreferences` con configuraciones previas

### 2. Hive en Almacenamiento Externo
Hive puede estar guardando en `/sdcard/Android/data/` que:
- ❌ NO se borra al desinstalar la app
- ❌ Persiste entre instalaciones
- ❌ Puede causar datos obsoletos

### 3. Android Auto Backup
Android puede hacer backup automático de:
- SharedPreferences
- Bases de datos
- Archivos internos

## ✅ Solución: Limpieza Completa

### Opción 1: Limpiar Datos desde ADB (RECOMENDADO)

```powershell
# 1. Limpiar TODOS los datos internos de la app
adb shell pm clear com.example.moveit

# 2. Limpiar almacenamiento externo (por si Hive guarda ahí)
adb shell rm -rf /sdcard/Android/data/com.example.moveit/

# 3. Reinstalar la app
flutter install
```

### Opción 2: Desinstalar y Limpiar Manualmente

```powershell
# 1. Desinstalar
adb uninstall com.example.moveit

# 2. Limpiar almacenamiento externo
adb shell rm -rf /sdcard/Android/data/com.example.moveit/

# 3. Limpiar cache del sistema (opcional)
adb shell pm clear com.android.providers.settings

# 4. Reinstalar
flutter install
```

### Opción 3: Desde el Teléfono

1. **Configuración → Apps → MoveIt**
2. **Almacenamiento → Borrar datos**
3. **Desinstalar app**
4. **Reinstalar desde Flutter**

## 🔧 Ubicaciones de Datos en Android

### Almacenamiento Interno (se borra al desinstalar normalmente):
```
/data/data/com.example.moveit/
├── shared_prefs/
│   ├── FlutterSharedPreferences.xml    ← flutter.baseUrl, flutter.isDevelopment
│   ├── config.xml                       ← baseUrl (para FcmApiHelper)
│   ├── flutter_events.xml              ← Eventos de debug
│   └── ...
├── app_flutter/                         ← Hive boxes por defecto
│   ├── sessionBox.hive
│   ├── usuarioBox.hive
│   ├── constantBox.hive
│   └── errorBox.hive
├── databases/
└── cache/
```

### Almacenamiento Externo (NO se borra al desinstalar):
```
/sdcard/Android/data/com.example.moveit/
├── files/                               ← Puede tener Hive si se configuró así
└── cache/
```

## 📊 Datos que Persisten el Problema

### 1. config.baseUrl (SharedPreferences)
**Guardado en:** `config` SharedPreferences
**Valor antiguo:** `190.64.89.170:8888`
**Leído por:** `FcmApiHelper.kt`
**Solución aplicada:** Ahora también se guarda en `flutter.baseUrl`

### 2. flutter.baseUrl (FlutterSharedPreferences)
**Guardado en:** `FlutterSharedPreferences`
**Leído por:** `LocationHelper.kt`
**Solución aplicada:** `MainActivity.kt` ahora guarda en ambos lugares

### 3. Hive Boxes
**Boxes principales:**
- `sessionBox` → usuario, móvil, escenario
- `usuarioBox` → datos de usuario persistentes
- `constantBox` → constantes descargadas
- `errorBox` → logs de errores

**Limpieza en logout:**
```dart
// logout_service.dart líneas 276-300
await Hive.deleteBoxFromDisk('sessionBox');
await Hive.deleteBoxFromDisk('usuarioBox');
await Hive.deleteBoxFromDisk('constantBox');
// ... otros boxes
```

## 🔒 Prevención: Deshabilitar Auto Backup

### AndroidManifest.xml
Para evitar que Android haga backup automático:

```xml
<application
    android:allowBackup="false"
    android:fullBackupContent="false"
    ...>
```

**Ubicación:** `android/app/src/main/AndroidManifest.xml`

Actualmente tu app tiene:
```xml
<application
    android:allowBackup="false"  ✅ Ya está deshabilitado
    ...>
```

## 🧪 Verificación de Limpieza

### Después de limpiar, verificar que NO existan:

```powershell
# 1. Verificar SharedPreferences borrados
adb shell "ls -la /data/data/com.example.moveit/shared_prefs/ 2>/dev/null || echo 'No existe'"

# 2. Verificar Hive boxes borrados
adb shell "ls -la /data/data/com.example.moveit/app_flutter/ 2>/dev/null || echo 'No existe'"

# 3. Verificar almacenamiento externo borrado
adb shell "ls -la /sdcard/Android/data/com.example.moveit/ 2>/dev/null || echo 'No existe'"
```

Si todo está limpio, deberías ver `"No existe"` en los 3 comandos.

## 🎯 Resultado Esperado

Después de la limpieza completa:

### ✅ Login Limpio
- ❌ NO debe aparecer ningún usuario por defecto
- ❌ NO debe recordar último usuario
- ✅ Campos vacíos para ingresar credenciales

### ✅ URLs Limpias
- ❌ NO debe existir `190.64.89.170:8888` en ningún lado
- ✅ Debe usar URL de producción por defecto
- ✅ Al elegir DESARROLLO, debe usar `https://sgm.riogas.com.uy/appservices/`

### ✅ Configuración Limpia
- ❌ NO debe recordar móvil anterior
- ❌ NO debe recordar escenario anterior
- ✅ Debe pedir selección de móvil después de login

## 📝 Comandos de Limpieza Ejecutados

Los siguientes comandos fueron ejecutados para limpiar tu teléfono:

```powershell
# 1. Limpiar TODOS los datos de la app
adb shell pm clear com.example.moveit
# ✅ Success

# 2. Limpiar almacenamiento externo
adb shell rm -rf /sdcard/Android/data/com.example.moveit/
# ✅ Ejecutado

# 3. Reinstalar app limpia
flutter install
# ✅ Installing app-release.apk to SM S926B...
```

## 🔄 Workflow Recomendado para Testing

### Para testing con datos limpios:
```powershell
# Opción A: Limpieza rápida (mantiene la app instalada)
adb shell pm clear com.example.moveit
flutter install

# Opción B: Limpieza completa (desinstala y reinstala)
adb uninstall com.example.moveit
adb shell rm -rf /sdcard/Android/data/com.example.moveit/
flutter install
```

### Para testing con datos existentes:
```powershell
# Solo reinstalar sin borrar datos
flutter install
```

## 🚨 Importante: Datos de Usuario Real

**⚠️ ADVERTENCIA:** `adb shell pm clear` borra TODO:
- ✅ Tokens de sesión
- ✅ Datos de login guardados
- ✅ Configuraciones de usuario
- ✅ Cache local
- ✅ Logs de debug

**NO ejecutar en producción** sin avisar al usuario que perderá su sesión.

## 🔗 Archivos Relacionados

- **logout_service.dart** → Limpieza de Hive en logout
- **MainActivity.kt** → Manejo de SharedPreferences
- **FcmApiHelper.kt** → Lee `config.baseUrl`
- **LocationHelper.kt** → Lee `flutter.baseUrl`
- **main.dart** → Inicialización de Hive

## 📚 Referencias

- [Hive Documentation](https://docs.hivedb.dev/)
- [Android Data Storage](https://developer.android.com/training/data-storage)
- [SharedPreferences](https://developer.android.com/training/data-storage/shared-preferences)
- [ADB Commands](https://developer.android.com/studio/command-line/adb)
