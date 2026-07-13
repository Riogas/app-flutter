# 🔧 Fix: Servicio GPS Respetando URL Dinámica (Producción/Desarrollo)

## 📋 Problema Identificado

El **servicio GPS en foreground** (código nativo Android - Kotlin) siempre enviaba coordenadas a la URL de **PRODUCCIÓN hardcodeada**:

```kotlin
val url = "https://www.riogas.uy/ica_geos_/appservices/RegistrarCoordenadasV2"
```

❌ **Problema:** No respetaba la configuración de ambiente (Producción vs Desarrollo) establecida en Flutter.

---

## ✅ Solución Implementada

### 1. Modificación en `LocationHelper.kt`

**Archivo:** `android/app/src/main/kotlin/com/example/moveit/LocationHelper.kt`  
**Líneas:** 1124-1138

**Antes (hardcodeada):**
```kotlin
private fun invokeRegistrarCoordenadasV2ApiWithRetry(...) {
    val maxRetries = 3
    val retryDelayMs = 5000L
    val url = "https://www.riogas.uy/ica_geos_/appservices/RegistrarCoordenadasV2"  // ❌ Siempre producción
    
    // ... resto del código
}
```

**Después (dinámica):**
```kotlin
private fun invokeRegistrarCoordenadasV2ApiWithRetry(...) {
    val maxRetries = 3
    val retryDelayMs = 5000L
    
    // 🌍 Obtener URL desde SharedPreferences (guardada por Flutter según ambiente)
    val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    val baseUrl = prefs.getString("flutter.baseUrl", "https://www.riogas.uy/ica_geos_/appservices/") 
        ?: "https://www.riogas.uy/ica_geos_/appservices/"
    val url = "${baseUrl}RegistrarCoordenadasV2"
    
    Log.d(TAG, "🌍 [URL_AMBIENTE] BaseUrl obtenida: $baseUrl")
    Log.d(TAG, "🌍 [URL_AMBIENTE] URL completa: $url")
    
    // ... resto del código
}
```

---

## 🔄 Flujo de Configuración de URL

### Al hacer Login en Flutter

1. **Usuario hace login** en `login_page.dart`
2. **Se construye baseUrl** según constantes:
   - **Producción:** Constante 600 + 601 → `https://www.riogas.uy/ica_geos_/appservices/`
   - **Desarrollo:** Constante 611 → `https://sgm.riogas.com.uy/appservices/`

3. **Se guarda en SharedPreferences nativo** (línea 1501):
   ```dart
   const platform = MethodChannel('com.riogas.appmovil/shared_prefs');
   await platform.invokeMethod('saveBaseUrl', {'baseUrl': fullBaseUrl});
   ```

4. **LocationHelper.kt lee esta URL** al enviar coordenadas:
   ```kotlin
   val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
   val baseUrl = prefs.getString("flutter.baseUrl", ...)
   ```

---

## 📊 Comportamiento por Ambiente

| Ambiente | BaseUrl Guardada | URL Final GPS |
|----------|------------------|---------------|
| **🏭 Producción** | `https://www.riogas.uy/ica_geos_/appservices/` | `https://www.riogas.uy/ica_geos_/appservices/RegistrarCoordenadasV2` |
| **🔧 Desarrollo** | `https://sgm.riogas.com.uy/appservices/` | `https://sgm.riogas.com.uy/appservices/RegistrarCoordenadasV2` |

---

## 🐛 Cómo Verificar el Fix

### 1. Compilar e instalar la app
```powershell
flutter install
```

### 2. Hacer login con modo desarrollo activado

En **Settings → Modo Desarrollo → ON**

### 3. Monitorear logs del servicio GPS

```powershell
adb logcat | Select-String "URL_AMBIENTE|LocationHelper.*URL|SETTINGS.*baseUrl"
```

**Logs esperados al cambiar a desarrollo en Settings:**
```
🔄 [SETTINGS] Actualizando baseUrl del servicio GPS...
🔄 [SETTINGS] Nuevo ambiente: DESARROLLO
🔄 [SETTINGS] Nueva URL: https://sgm.riogas.com.uy/appservices/
✅ [SETTINGS] BaseUrl del servicio GPS actualizada exitosamente
🌍 [URL_AMBIENTE] BaseUrl obtenida: https://sgm.riogas.com.uy/appservices/
🌍 [URL_AMBIENTE] URL completa: https://sgm.riogas.com.uy/appservices/RegistrarCoordenadasV2
🌐 Request (intento 1/3): URL=https://sgm.riogas.com.uy/appservices/RegistrarCoordenadasV2
```

### 4. Cambiar a producción y verificar

En **Settings → Modo Desarrollo → OFF** (sin cerrar sesión)

**Logs esperados:**
```
🔄 [SETTINGS] Actualizando baseUrl del servicio GPS...
🔄 [SETTINGS] Nuevo ambiente: PRODUCCIÓN
🔄 [SETTINGS] Nueva URL: https://www.riogas.uy/ica_geos_/appservices/
✅ [SETTINGS] BaseUrl del servicio GPS actualizada exitosamente
🌍 [URL_AMBIENTE] BaseUrl obtenida: https://www.riogas.uy/ica_geos_/appservices/
🌍 [URL_AMBIENTE] URL completa: https://www.riogas.uy/ica_geos_/appservices/RegistrarCoordenadasV2
🌐 Request (intento 1/3): URL=https://www.riogas.uy/ica_geos_/appservices/RegistrarCoordenadasV2
```

---

## 🔍 Comandos de Debug

### Ver a qué URL está pegando el GPS en tiempo real:
```powershell
adb logcat | Select-String "sgm.riogas.com.uy|www.riogas.uy|URL_AMBIENTE"
```

### Ver cambios de ambiente en Settings:
```powershell
adb logcat | Select-String "SETTINGS.*baseUrl|SETTINGS.*ambiente"
```

### Ver todo el flujo (cambio de ambiente + request + response):
```powershell
adb logcat | Select-String "SETTINGS|LocationHelper.*URL|LocationHelper.*Body|LocationHelper.*exitosa"
```

### Ver inicialización de URLs al login:
```powershell
adb logcat | Select-String "baseUrl.*guardada|CONSTANTE 611|AMBIENTE.*iniciada"
```

---

## ⚠️ Consideraciones Importantes

### 1. **Fallback Automático**

Si por alguna razón no se puede leer `baseUrl` de SharedPreferences, usa el fallback de producción:

```kotlin
val baseUrl = prefs.getString("flutter.baseUrl", "https://www.riogas.uy/ica_geos_/appservices/")
```

### 2. **Cuándo se actualiza la URL**

La URL se actualiza:
- ✅ Al hacer **login**
- ✅ Al **cambiar de servidor** en Settings (inmediatamente, sin re-login)
- ✅ Al **cambiar entre Desarrollo/Producción** en Settings (inmediatamente, sin re-login)
- ✅ **En tiempo real** cuando se cambia el ambiente

### 3. **Persistencia**

El valor de `baseUrl` persiste en SharedPreferences hasta:
- Desinstalar la app
- Limpiar datos de la app
- Hacer un nuevo login

---

## 📝 Archivos Modificados

| Archivo | Líneas | Cambio |
|---------|--------|--------|
| `LocationHelper.kt` | 1124-1138 | URL dinámica desde SharedPreferences |
| `login_page.dart` | 1501-1503 | Guarda baseUrl al hacer login |
| `settings_page.dart` | 1448-1477 | 🆕 Actualiza baseUrl al cambiar ambiente |
| `constantes.dart` | 16-17 | URL de desarrollo actualizada a `sgm.riogas.com.uy` |

---

## ✅ Checklist de Verificación

Después de instalar la app actualizada:

- [ ] Hacer login en modo **PRODUCCIÓN** (por defecto)
- [ ] Ver logs: `adb logcat | Select-String "URL_AMBIENTE"`
- [ ] Verificar URL contiene: `https://www.riogas.uy`
- [ ] Esperar 3 minutos (intervalo GPS)
- [ ] Verificar request se envía a URL de producción
- [ ] **Cambiar a modo DESARROLLO en Settings** (sin cerrar sesión)
- [ ] Ver logs nuevamente en tiempo real
- [ ] Verificar URL contiene: `https://sgm.riogas.com.uy`
- [ ] Esperar 3 minutos
- [ ] Verificar request se envía a URL de desarrollo
- [ ] **Cambiar a modo PRODUCCIÓN** (sin cerrar sesión)
- [ ] Ver logs nuevamente
- [ ] Verificar URL vuelve a: `https://www.riogas.uy`

---

## 🎯 Resultado Esperado

✅ **Antes del fix (versión anterior):**
- GPS siempre enviaba a `https://www.riogas.uy` (producción)
- No respetaba configuración de ambiente
- Requería logout/login para actualizar URL

✅ **Después del fix (versión actual):**
- GPS respeta configuración de ambiente
- En desarrollo → `https://sgm.riogas.com.uy`
- En producción → `https://www.riogas.uy`
- **Se actualiza inmediatamente** al cambiar ambiente en Settings
- **No requiere logout/login** para aplicar cambios

---

**Fecha de implementación:** 11 de noviembre de 2025  
**Última actualización:** 25 de noviembre de 2025 (URL de desarrollo actualizada)  
**Archivo principal:** `LocationHelper.kt` + `settings_page.dart`  
**Líneas modificadas:** `LocationHelper.kt` (1124-1138) | `settings_page.dart` (1448-1477)  
**Impacto:** Servicio GPS respeta ambiente y se actualiza en tiempo real

