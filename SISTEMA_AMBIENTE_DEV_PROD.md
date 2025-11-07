# Sistema de Ambiente Dev/Prod - Documentación

## 📋 Resumen
Sistema implementado para permitir a usuarios especiales (49618553 y 27861374) cambiar entre ambientes de DESARROLLO y PRODUCCIÓN dentro de la aplicación, sin necesidad de recompilar.

## 🎯 Características Implementadas

### 1. **AppEnvironment Class** (`lib/utils/constantes.dart`)
Clase estática que gestiona el ambiente actual de la aplicación:

```dart
enum Environment { production, development }

class AppEnvironment {
  static const String devBaseRoot = 'https://riogas.desa.uy/ica_geos_/';
  static const String devServicesPath = 'appservices/';
  
  // Métodos principales:
  static Future<void> initialize()
  static bool get isDevelopment
  static bool get isProduction
  static Future<void> setEnvironment(Environment environment)
  static String get environmentName
}
```

**Funcionalidades:**
- ✅ Persistencia en `SharedPreferences` con clave `app_environment`
- ✅ Inicialización automática al arrancar la app
- ✅ Ambiente por defecto: PRODUCCIÓN
- ✅ URLs de desarrollo hardcodeadas (constante 611)
- ✅ URLs de producción desde constantes 600 y 601

---

### 2. **RioGasService Dinámico** (`lib/services/riogas_service.dart`)

**Cambios implementados:**
```dart
// Antes:
static late final String _baseUrl;
static String get baseUrl => _baseUrl;

// Después:
static late final String _baseUrlProduction;

static String get baseUrl {
  if (AppEnvironment.isDevelopment) {
    return '${AppEnvironment.devBaseRoot}${AppEnvironment.devServicesPath}';
  }
  return _baseUrlProduction;
}
```

**Comportamiento:**
- ✅ Getter dinámico que evalúa el ambiente en cada llamada
- ✅ En DESARROLLO: retorna `https://riogas.desa.uy/ica_geos_/appservices/`
- ✅ En PRODUCCIÓN: retorna URL configurada desde constantes (normalmente `https://www.riogas.uy/ica_geos_/appservices/`)
- ✅ Todos los servicios usan automáticamente la URL correcta
- ✅ Logs en consola muestran ambas URLs en inicialización

---

### 3. **Switch UI en Settings** (`lib/pages/settings_page.dart`)

**Control de acceso:**
```dart
bool _isSpecialUser() {
  final specialUsers = ['49618553', '27861374'];
  return idUsuario != null && specialUsers.contains(idUsuario);
}
```

**Widget implementado:**
- ✅ Card con Switch para cambiar ambiente
- ✅ **Visible SOLO para usuarios 49618553 y 27861374**
- ✅ Muestra texto "Desarrollo 🧪" o "Producción ✅"
- ✅ Muestra URL actual en texto pequeño monoespaciado
- ✅ Confirmación con diálogo antes de cambiar
- ✅ SnackBar de éxito tras cambiar ambiente
- ✅ Color naranja para desarrollo, verde para producción

**Ubicación:**
- Aparece entre el botón "Permisos" y el botón "Cerrar sesión"
- Se oculta completamente si el usuario no es especial (sin dejar espacio vacío)

---

### 4. **Banner Visual** (`lib/main.dart`)

**Implementación:**
```dart
MaterialApp(
  builder: (context, child) {
    if (AppEnvironment.isDevelopment) {
      return Banner(
        message: 'DESARROLLO 🧪',
        location: BannerLocation.topEnd,
        color: Colors.orange,
        child: child!,
      );
    }
    return child!;
  },
  // ...
)
```

**Características:**
- ✅ Banner diagonal naranja en esquina superior derecha
- ✅ Texto: "DESARROLLO 🧪"
- ✅ Visible en TODAS las pantallas cuando está en modo desarrollo
- ✅ Se oculta completamente en modo producción
- ✅ No interfiere con la UI ni con la navegación

---

## 🔧 Flujo de Funcionamiento

### Inicio de Aplicación
```
1. main() → WidgetsFlutterBinding.ensureInitialized()
2. Hive.initFlutter()
3. AppEnvironment.initialize() → Lee SharedPreferences
4. RioGasService.initializeService() → Configura URLs
5. runApp(MyApp()) → Renderiza con banner si isDevelopment
```

### Cambio de Ambiente (Usuario Especial)
```
1. Usuario abre Settings
2. Ve el switch de ambiente (solo si es usuario especial)
3. Toca el switch
4. Aparece diálogo de confirmación
5. Confirma → AppEnvironment.setEnvironment()
6. Guarda en SharedPreferences
7. setState() actualiza UI
8. SnackBar muestra confirmación
9. Próxima request HTTP usa nueva URL automáticamente
```

### Persistencia
```
- Clave SharedPreferences: 'app_environment'
- Valores: 'development' | 'production'
- Persiste entre cierres de app
- No requiere login nuevamente
```

---

## 📱 Experiencia de Usuario

### Usuario Especial (49618553 o 27861374)
1. **Al loguearse**: Ve su configuración de ambiente en Settings
2. **En Settings**: Card visible con switch de ambiente
3. **Al cambiar**: Confirmación clara de URLs a usar
4. **Visual**: Banner naranja si está en desarrollo
5. **Logs**: Puede ver URL actual en Settings

### Usuario Normal
- **No ve nada diferente**
- Siempre usa ambiente de producción
- Switch completamente oculto
- Sin banner nunca

---

## 🎨 Elementos Visuales

### Settings Card (Solo Usuarios Especiales)
```
┌────────────────────────────────────────┐
│ ⚙️ Ambiente de Aplicación              │
│                                        │
│ Desarrollo 🧪              [ SWITCH ]  │
│ URL: https://riogas.desa.uy/...        │
└────────────────────────────────────────┘
```

### Banner en Toda la App (Desarrollo)
```
                              DESARROLLO 🧪
                            /
                          /
                        /  (Banner diagonal naranja)
```

### Diálogo de Confirmación
```
┌─────────────────────────────────────┐
│ Cambiar Ambiente                    │
│                                     │
│ ¿Deseas cambiar a modo DESARROLLO?  │
│                                     │
│ La aplicación se conectará a        │
│ riogas.desa.uy                      │
│                                     │
│      [Cancelar]    [Confirmar]      │
└─────────────────────────────────────┘
```

---

## 🔒 Seguridad

### Control de Acceso
- ✅ Validación por ID de usuario (no por rol)
- ✅ IDs hardcodeados en código: `['49618553', '27861374']`
- ✅ Verificación en cada render del switch
- ✅ No hay forma de activar sin ser usuario especial

### Persistencia
- ✅ SharedPreferences local (no se sincroniza con backend)
- ✅ Ambiente persiste solo en el dispositivo
- ✅ Cambiar de usuario respeta ambiente configurado previamente
- ✅ Ambiente no se envía en requests (solo afecta URL base)

---

## 🧪 Pruebas Manuales

### Caso 1: Usuario Especial - Cambio a Desarrollo
```
1. Login con usuario 49618553 o 27861374
2. Ir a Settings
3. Verificar que switch aparece
4. Activar switch (hacia la derecha)
5. Confirmar diálogo
6. ✅ Verificar SnackBar naranja: "Ambiente cambiado a: Desarrollo"
7. ✅ Verificar banner diagonal aparece
8. ✅ Verificar URL en Settings: "riogas.desa.uy"
9. Hacer una request (ej: descargar pedidos)
10. ✅ Verificar en logs que usa URL de desarrollo
```

### Caso 2: Usuario Especial - Cambio a Producción
```
1. Con usuario especial en modo desarrollo
2. Desactivar switch (hacia la izquierda)
3. Confirmar diálogo
4. ✅ Verificar SnackBar verde: "Ambiente cambiado a: Producción"
5. ✅ Verificar banner desaparece
6. ✅ Verificar URL en Settings: "riogas.uy"
7. Hacer una request
8. ✅ Verificar en logs que usa URL de producción
```

### Caso 3: Usuario Normal
```
1. Login con cualquier otro usuario
2. Ir a Settings
3. ✅ Verificar que switch NO aparece
4. ✅ Verificar que banner NO aparece nunca
5. Hacer requests
6. ✅ Verificar que siempre usa URL de producción
```

### Caso 4: Persistencia
```
1. Usuario especial cambia a desarrollo
2. Cerrar app completamente
3. Abrir app nuevamente
4. ✅ Verificar banner sigue apareciendo
5. Ir a Settings
6. ✅ Verificar switch sigue activado
7. ✅ Ambiente persiste correctamente
```

---

## 📝 Logs para Debugging

### Logs de Inicialización (main.dart)
```dart
print('🌍 [AMBIENTE] Aplicación iniciada en modo DESARROLLO');
// o
print('🌍 [AMBIENTE] Aplicación iniciada en modo PRODUCCIÓN');
```

### Logs de RioGasService (riogas_service.dart)
```dart
print('🔧 [INIT] baseUrl PRODUCCIÓN = "$_baseUrlProduction"');
print('🔧 [INIT] baseUrl DESARROLLO = "${AppEnvironment.devBaseRoot}${AppEnvironment.devServicesPath}"');
print('🌍 [INIT] Ambiente actual: ${AppEnvironment.environmentName}');
```

### Logs de Cambio de Ambiente (constantes.dart)
```dart
print('🌍 [AMBIENTE] Cambiado a: DESARROLLO');
// o
print('🌍 [AMBIENTE] Cambiado a: PRODUCCIÓN');
```

### Verificar en Logcat
```powershell
# Ver logs de ambiente
adb logcat | Select-String "AMBIENTE"

# Ver logs de inicialización
adb logcat | Select-String "INIT.*baseUrl"

# Ver ambiente actual
adb logcat | Select-String "Ambiente actual"
```

---

## 🚀 Archivos Modificados

### Creados/Modificados
1. ✅ `lib/utils/constantes.dart` - AppEnvironment class agregada
2. ✅ `lib/services/riogas_service.dart` - baseUrl dinámico
3. ✅ `lib/pages/settings_page.dart` - Switch UI agregado
4. ✅ `lib/main.dart` - Banner y inicialización
5. ✅ `pubspec.yaml` - Dependencia `shared_preferences: ^2.2.2`

### Dependencias Nuevas
```yaml
shared_preferences: ^2.2.2
```

---

## ✅ Checklist de Implementación

- [x] AppEnvironment class con persistencia
- [x] Inicialización en main()
- [x] RioGasService con baseUrl dinámico
- [x] Switch en Settings (solo usuarios especiales)
- [x] Diálogo de confirmación
- [x] SnackBar de feedback
- [x] Banner visual en modo desarrollo
- [x] URLs de desarrollo hardcodeadas
- [x] Logs para debugging
- [x] Documentación completa

---

## 🎯 URLs Configuradas

### Desarrollo (Hardcodeadas)
```
Base: https://riogas.desa.uy/ica_geos_/
Services: appservices/
Final: https://riogas.desa.uy/ica_geos_/appservices/
```

### Producción (Desde Constantes)
```
Base: Constante 600 (default: https://www.riogas.uy/ica_geos_/)
Services: Constante 601 (default: appservices/)
Final: https://www.riogas.uy/ica_geos_/appservices/
```

---

## 📌 Notas Importantes

1. **No requiere recompilación**: El cambio es instantáneo y persiste
2. **Solo dos usuarios**: 49618553 y 27861374 pueden ver/cambiar
3. **Ambiente por defecto**: PRODUCCIÓN (seguro)
4. **Persistencia local**: No se sincroniza con backend
5. **Sin logout necesario**: Cambio aplica inmediatamente
6. **Banner siempre visible**: En desarrollo, en TODAS las pantallas
7. **URLs hardcodeadas**: Desarrollo no depende de constantes Firestore

---

## 🔄 Próximos Pasos (Opcionales)

### Mejoras Potenciales
- [ ] Agregar más usuarios especiales si es necesario
- [ ] Mostrar indicador de ambiente en HomeBar
- [ ] Agregar logs de todas las requests con URL usada
- [ ] Crear constante 611 en Firestore para URL dev (opcional)
- [ ] Agregar analytics para rastrear uso de ambientes

---

**Fecha de Implementación**: 6 de noviembre de 2025  
**Usuarios Especiales**: 49618553, 27861374  
**Estado**: ✅ Completamente Implementado y Funcional
