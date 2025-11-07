# 🌍 Selección de Servidor para Usuarios de Desarrollo

## 📋 Resumen

Sistema de selección de servidor (Producción/Desarrollo) que se muestra **solo para usuarios específicos** durante el login, antes de seleccionar el móvil.

---

## ✨ Características

### 🎯 Comportamiento

1. **Usuarios Normales**: Siempre usan **PRODUCCIÓN** (https://riogas.com.uy)
2. **Usuarios Especiales**: Pueden elegir entre Producción o Desarrollo antes de seleccionar móvil
3. **Sesión Temporal**: El servidor elegido solo dura **hasta cerrar sesión**
4. **Reset Automático**: Al cerrar sesión, vuelve automáticamente a **PRODUCCIÓN**

### 👥 Usuarios Especiales

Los siguientes usuarios verán el diálogo de selección de servidor:
- **49618553** (Jorge)
- **27869041** (Otro desarrollador)

Para agregar más usuarios, editar en `lib/pages/login_page.dart`:
```dart
static const List<String> _specialUsers = ['49618553', '27869041', 'NUEVO_USUARIO'];
```

---

## 🔄 Flujo de Login

### Para Usuarios Normales
```
┌─────────────────┐
│  Login Page     │
│  (user/pass)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Validar Usuario │
└────────┬────────┘
         │
         ▼
┌─────────────────────┐
│ Seleccionar Móvil   │  ← Directo a selección de móvil
│ (PRODUCCIÓN)        │
└─────────────────────┘
```

### Para Usuarios Especiales (49618553, 27869041)
```
┌─────────────────┐
│  Login Page     │
│  (user/pass)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Validar Usuario │
└────────┬────────┘
         │
         ▼
┌──────────────────────────┐
│ ¿Usuario especial?       │
│ (49618553 o 27869041)    │
└────────┬─────────────────┘
         │ SÍ
         ▼
┌─────────────────────────────┐
│ 🌍 Seleccionar Servidor     │  ← NUEVO DIÁLOGO
│                             │
│ ○ Producción (default)      │
│   https://riogas.com.uy     │
│                             │
│ ○ Desarrollo                │
│   https://riogas.desa.uy    │
│                             │
│     [Continuar]             │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────┐
│ Seleccionar Móvil   │
└─────────────────────┘
```

---

## 🛠️ Implementación Técnica

### 1️⃣ Nuevos Métodos en `AppEnvironment`

**Archivo**: `lib/utils/constantes.dart`

```dart
// Cambiar ambiente SOLO para esta sesión (NO persiste)
static void setEnvironmentForSession(Environment environment) {
  _currentEnvironment = environment;
  print('🌍 [AMBIENTE] Cambiado temporalmente a: ${environment == Environment.development ? "DESARROLLO" : "PRODUCCIÓN"}');
  print('ℹ️ [AMBIENTE] Este cambio NO persiste. Al cerrar sesión, volverá a PRODUCCIÓN.');
}

// Resetear a producción (llamar al cerrar sesión)
static Future<void> resetToProduction() async {
  _currentEnvironment = Environment.production;
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_keyEnvironment); // Eliminar preferencia guardada
  print('🌍 [AMBIENTE] Reseteado a PRODUCCIÓN (por defecto)');
}
```

### 2️⃣ Diálogo de Selección de Servidor

**Archivo**: `lib/pages/login_page.dart`

```dart
Future<void> _showServerSelectionDialog() async {
  Environment selectedEnv = Environment.production; // Default: Producción

  await showDialog(
    context: context,
    barrierDismissible: false,
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
                RadioListTile<Environment>(
                  title: Text('Producción'),
                  subtitle: Text('https://riogas.com.uy'),
                  value: Environment.production,
                  groupValue: selectedEnv,
                  onChanged: (value) => setState(() => selectedEnv = value!),
                ),
                RadioListTile<Environment>(
                  title: Text('Desarrollo'),
                  subtitle: Text('https://riogas.desa.uy'),
                  value: Environment.development,
                  groupValue: selectedEnv,
                  onChanged: (value) => setState(() => selectedEnv = value!),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  AppEnvironment.setEnvironmentForSession(selectedEnv);
                  Navigator.of(dialogContext).pop();
                },
                child: Text('Continuar'),
              ),
            ],
          );
        },
      );
    },
  );
}
```

### 3️⃣ Integración en Flujo de Login

```dart
if (_availableMoviles.isNotEmpty) {
  // 🌍 Si es usuario especial, mostrar selección de servidor PRIMERO
  if (_specialUsers.contains(_usernameController.text)) {
    print('🌍 [SERVER] Usuario especial detectado: ${_usernameController.text}');
    await _showServerSelectionDialog();
  }

  // Luego mostrar selección de móviles
  await _showMobileSelectionDialog(response);
}
```

### 4️⃣ Reset en Logout

**Archivo**: `lib/services/logout_service.dart`

```dart
// 🆕 Resetear ambiente a PRODUCCIÓN (por defecto)
try {
  await AppEnvironment.resetToProduction();
  print('$TAG 🌍 Ambiente reseteado a PRODUCCIÓN');
} catch (e) {
  print('$TAG ⚠️ Error reseteando ambiente: $e');
}
```

---

## 📊 Persistencia

| Tipo | Método Usado | ¿Persiste? | Cuándo Resetea |
|------|--------------|------------|----------------|
| **Producción** (default) | Ninguno | No | Siempre es default |
| **Desarrollo (temporal)** | `setEnvironmentForSession()` | ❌ NO | Al cerrar sesión |
| **Desarrollo (permanente)** | `setEnvironment()` | ✅ SÍ | Manual desde Settings |

---

## 🔍 Logs de Ejemplo

### Usuario Normal (no está en lista)
```
📋 Móviles disponibles para seleccionar: [...]
🛑 Mostrando selección de móviles antes de continuar...
```

### Usuario Especial (49618553)
```
📋 Móviles disponibles para seleccionar: [...]
🛑 Mostrando selección de móviles antes de continuar...
🌍 [SERVER] Usuario especial detectado: 49618553
🌍 [AMBIENTE] Cambiado temporalmente a: DESARROLLO
ℹ️ [AMBIENTE] Este cambio NO persiste. Al cerrar sesión, volverá a PRODUCCIÓN.
```

### Al Cerrar Sesión
```
LogoutService 🧹 Datos de Hive eliminados
LogoutService 🌍 Ambiente reseteado a PRODUCCIÓN
LogoutService 🚪 Cerrando aplicación...
```

---

## ✅ Ventajas

1. ✅ **Seguro**: Usuarios normales NUNCA ven el diálogo
2. ✅ **Default Correcto**: Siempre vuelve a Producción al cerrar sesión
3. ✅ **No Persiste**: Evita que un desarrollador deje accidentalmente en Desarrollo
4. ✅ **Flexible**: Durante la sesión, el desarrollador puede probar contra Desarrollo
5. ✅ **Simple**: Solo agregar username a la lista `_specialUsers`

---

## 🧪 Testing

### Caso 1: Usuario Normal
1. Login con usuario normal (ej: `12345678`)
2. ✅ NO debe aparecer diálogo de servidor
3. ✅ Va directo a selección de móvil
4. ✅ Usa PRODUCCIÓN

### Caso 2: Usuario Especial - Producción
1. Login con `49618553`
2. ✅ Aparece diálogo de servidor
3. Seleccionar "Producción" → Continuar
4. ✅ Selecciona móvil
5. ✅ Todas las llamadas van a `riogas.com.uy`

### Caso 3: Usuario Especial - Desarrollo
1. Login con `49618553`
2. ✅ Aparece diálogo de servidor
3. Seleccionar "Desarrollo" → Continuar
4. ✅ Selecciona móvil
5. ✅ Todas las llamadas van a `riogas.desa.uy`
6. Cerrar sesión
7. Re-login con `49618553`
8. ✅ Diálogo vuelve a aparecer con "Producción" seleccionado por defecto

---

## 🔧 Archivos Modificados

1. ✅ `lib/utils/constantes.dart`
   - `setEnvironmentForSession()` - Cambio temporal
   - `resetToProduction()` - Reset al logout

2. ✅ `lib/pages/login_page.dart`
   - `_specialUsers` - Lista de usuarios con acceso
   - `_showServerSelectionDialog()` - UI del diálogo
   - Integración en flujo de login (3 lugares)

3. ✅ `lib/services/logout_service.dart`
   - Llamada a `resetToProduction()` antes de cerrar app

---

## 📝 Notas Importantes

⚠️ **Diferencia con Settings**:
- **Login (temporal)**: Solo dura la sesión actual
- **Settings (permanente)**: Persiste hasta cambiar manualmente

🔒 **Seguridad**:
- Solo usuarios en `_specialUsers` ven el diálogo
- No hay forma de que un usuario normal cambie el servidor

🚀 **Producción**:
- Es el **default absoluto**
- Siempre vuelve a Producción al cerrar sesión
- No hay forma de "quedarse atascado" en Desarrollo

---

## 🎯 Casos de Uso

### Desarrollador Probando
```
1. Login → Elige Desarrollo
2. Prueba funcionalidad contra servidor de desarrollo
3. Cierra sesión
4. Próximo login → Vuelve automáticamente a Producción
```

### Usuario Normal
```
1. Login
2. NO ve diálogo de servidor
3. Siempre usa Producción
```

### Desarrollador en Producción
```
1. Login → Elige Producción (default)
2. Trabaja normalmente en producción
3. Cierra sesión
```
