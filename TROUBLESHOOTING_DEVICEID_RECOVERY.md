# 🔍 Troubleshooting: DeviceId Recovery

## Problema
El watchdog no puede recuperar el `deviceId` cuando intenta reiniciar el GPS service, lo que impide llamar al API `/GetMovilActivo`.

## ¿Por qué pasa esto?

### 1. DeviceId se guarda en Hive
En `login_page.dart` línea 1694:
```dart
await box.put('deviceId', _deviceId);
```

### 2. Hive usa SharedPreferences de forma especial
Cuando Hive guarda `deviceId` en el box `sessionBox`, **NO lo guarda** con la clave `flutter.deviceId`.

Hive serializa sus boxes de forma compleja y puede que use un formato interno diferente.

## Solución Implementada

### Búsqueda exhaustiva de DeviceId
El `ServiceWatchdog` ahora busca en **múltiples lugares**:

1. ✅ **FlutterSharedPreferences** con claves estándar:
   - `flutter.deviceId`
   - `flutter.DeviceId`
   - `deviceId`
   - `DeviceId`

2. ✅ **Todas las claves de FlutterSharedPreferences**:
   - Itera por TODAS las claves buscando cualquiera que contenga "deviceId"
   - Esto captura incluso formatos internos de Hive

3. ✅ **Native SharedPreferences**:
   - `config.last_deviceId`

## Comandos de Debugging

### Ver TODAS las claves en SharedPreferences
```powershell
adb shell "run-as com.riogas.appmovil cat /data/data/com.riogas.appmovil/shared_prefs/FlutterSharedPreferences.xml"
```

### Buscar específicamente deviceId
```powershell
adb shell "run-as com.riogas.appmovil cat /data/data/com.riogas.appmovil/shared_prefs/FlutterSharedPreferences.xml" | Select-String "deviceId"
```

### Ver config nativo
```powershell
adb shell "run-as com.riogas.appmovil cat /data/data/com.riogas.appmovil/shared_prefs/config.xml"
```

### Monitorear logs de recuperación
```powershell
adb logcat -s "ServiceWatchdog:*" "MovilRecoveryHelper:*" | Select-String "RECOVERY|deviceId|DeviceId"
```

## Logs esperados DESPUÉS del fix

### ✅ DeviceId encontrado:
```
I/ServiceWatchdog: ⚠️ [RECOVERY] DeviceId también está vacío, intentando recuperar...
D/ServiceWatchdog:    🔍 Buscando en Hive sessionBox...
D/ServiceWatchdog:    🔎 Encontrada clave: flutter.sessionBox.deviceId = ABC123XYZ
I/ServiceWatchdog: ✅ [RECOVERY] DeviceId recuperado: ABC123XYZ
```

### ✅ Luego llamada a API:
```
I/MovilRecoveryHelper: 🔍 [RECOVERY] Iniciando proceso de recuperación de MovilId...
I/MovilRecoveryHelper: 🔍 [RECOVERY] DeviceId: ABC123XYZ
D/MovilRecoveryHelper: 🔍 [RECOVERY] Intentando recuperar desde API /GetMovilActivo...
D/MovilRecoveryHelper:    🌐 URL: https://www.riogas.uy/ica_geos_/appservices/GetMovilActivo
D/MovilRecoveryHelper:    📤 Request body: {"DeviceId":"ABC123XYZ"}
D/MovilRecoveryHelper:    📥 Response code: 200
D/MovilRecoveryHelper:    📥 Response: {"MovilId":"693"}
I/MovilRecoveryHelper: ✅ [RECOVERY] MovilId recuperado desde API: 693
```

## ⚠️ Si sigue fallando

### Opción 1: Guardar deviceId explícitamente en Flutter prefs
Agregar en `login_page.dart` después de línea 1694:
```dart
// También guardar en SharedPreferences para acceso nativo
final prefs = await SharedPreferences.getInstance();
await prefs.setString('deviceId', _deviceId);
```

### Opción 2: Backend debe implementar endpoint
El endpoint `/GetMovilActivo` debe estar implementado en el backend:

```
POST /ica_geos_/appservices/GetMovilActivo
Content-Type: application/json

{
  "DeviceId": "ABC123XYZ"
}

Respuesta:
{
  "MovilId": "693"
}
```

Query SQL sugerido:
```sql
SELECT MovilId 
FROM Sesiones 
WHERE DeviceId = @DeviceId 
  AND Estado = 'Activo'
  AND FechaLogin >= DATEADD(day, -1, GETDATE())
ORDER BY FechaLogin DESC
```

## Testing

### 1. Instalar APK actualizado
```powershell
cd appmovil
flutter build apk --release
flutter install
```

### 2. Limpiar logs
```powershell
adb logcat -c
```

### 3. Simular problema (borrar movil de SharedPreferences)
```powershell
adb shell "run-as com.riogas.appmovil rm /data/data/com.riogas.appmovil/shared_prefs/config.xml"
```

### 4. Monitorear recuperación
```powershell
adb logcat -s "ServiceWatchdog:*" "MovilRecoveryHelper:*" | Select-String "RECOVERY|deviceId|GetMovilActivo"
```

### 5. Verificar en n8n
Buscar webhook con tags:
- `DEVICE_ID_RECOVERED`
- `MOVIL_RECOVERY_API_SUCCESS`
- `WATCHDOG_MOVIL_RECOVERED`

## Próximos pasos

1. ✅ **Build y deploy** del APK actualizado
2. ⏳ **Testing** con dispositivo real que tenga el problema
3. ⏳ **Backend** implementar endpoint `/GetMovilActivo`
4. ⏳ **Monitoreo** en n8n para ver si la recuperación funciona
5. ⏳ **Optimización** si es necesario guardar deviceId de forma más accesible

## Notas técnicas

### ¿Por qué Hive complica esto?
Hive serializa sus boxes de forma especial. Cuando haces:
```dart
var box = await Hive.openBox('sessionBox');
await box.put('deviceId', value);
```

Hive puede guardar esto como:
- Una estructura serializada del box completo
- Un formato interno que no es directamente accesible como `flutter.deviceId`
- Posiblemente con prefijos o sufijos del nombre del box

### Solución definitiva
La búsqueda exhaustiva por TODAS las claves de SharedPreferences garantiza que encontraremos el deviceId sin importar cómo Hive lo haya guardado.

## Contacto
Si después de estos cambios aún no funciona, verificar:
1. ¿El deviceId realmente se guardó en el login? (logs de Flutter)
2. ¿Las SharedPreferences tienen ALGO guardado? (adb shell cat)
3. ¿El endpoint del backend está implementado?
