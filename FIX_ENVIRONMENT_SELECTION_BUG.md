# 🔧 FIX: Environment Selection Not Persisting to GPS Service

## 🐛 Problem

User selects **DESARROLLO** environment in both login dialogs, but the GPS service continues to use the **PRODUCCIÓN** URL when sending coordinates.

### Symptoms:
- User 49618553 or 27861374 selects "DESARROLLO" in environment dialog
- User sees confirmation: `🔧 [LOGIN] Ambiente: DESARROLLO`
- GPS service sends coordinates to: `https://www.riogas.uy/ica_geos_/appservices/` (PRODUCCIÓN)
- Expected URL: `https://sgm.riogas.com.uy/appservices/` (DESARROLLO)
- Result: 404 error because `RegistrarCoordenadasV2` endpoint doesn't exist in production

## 🔍 Root Cause

**SharedPreferences Storage Mismatch**

When Flutter saves the `baseUrl`, it was being saved to:
- **Location**: `config` SharedPreferences
- **Key**: `baseUrl` (no prefix)

But `LocationHelper.kt` was reading from:
- **Location**: `FlutterSharedPreferences`
- **Key**: `flutter.baseUrl` (with "flutter." prefix)

These are **two completely different storage locations** on Android!

### Code Locations:

**1. Flutter saves baseUrl (login_page.dart line 2056):**
```dart
await platform.invokeMethod('saveBaseUrl', {'baseUrl': fullBaseUrl});
```

**2. MainActivity.kt receives and saves (line 161-176) - BEFORE FIX:**
```kotlin
"saveBaseUrl" -> {
    val baseUrl = call.argument<String>("baseUrl")
    try {
        // ❌ ONLY saves to "config" SharedPreferences
        val configPrefs = getSharedPreferences("config", Context.MODE_PRIVATE)
        configPrefs.edit().putString("baseUrl", baseUrl).apply()
    } catch (e: Exception) { ... }
}
```

**3. LocationHelper.kt reads baseUrl (line 1488):**
```kotlin
// ❌ Reads from DIFFERENT location!
val baseUrl = prefs.getString("flutter.baseUrl", 
    "https://www.riogas.uy/ica_geos_/appservices/") ?: 
    "https://www.riogas.uy/ica_geos_/appservices/"
```

Since `flutter.baseUrl` was never set, it **always defaulted to PRODUCCIÓN URL**.

## ✅ Solution

Modified `MainActivity.kt` to save `baseUrl` to **BOTH** storage locations:

```kotlin
"saveBaseUrl" -> {
    val baseUrl = call.argument<String>("baseUrl")
    if (baseUrl == null) {
        result.error("INVALID_BASEURL", "baseUrl es requerido", null)
        return@setMethodCallHandler
    }
    
    try {
        // 🔹 Guardar en SharedPreferences "config" que usa FcmApiHelper
        val configPrefs = getSharedPreferences("config", Context.MODE_PRIVATE)
        configPrefs.edit().putString("baseUrl", baseUrl).apply()
        
        // 🆕 TAMBIÉN guardar en FlutterSharedPreferences para que LocationHelper pueda leerlo
        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        flutterPrefs.edit().putString("flutter.baseUrl", baseUrl).apply()
        
        Log.i("MainActivity", "✅ BaseUrl guardada en config.baseUrl: $baseUrl")
        Log.i("MainActivity", "✅ BaseUrl guardada en flutter.baseUrl: $baseUrl")
        result.success("✅ BaseUrl guardada exitosamente")
    } catch (e: Exception) {
        Log.e("MainActivity", "❌ Error guardando baseUrl: ${e.message}", e)
        result.error("SAVE_ERROR", "Error guardando baseUrl: ${e.message}", null)
    }
}
```

## 📊 Flow Diagram

### Before Fix:
```
User selects DESARROLLO
        ↓
Flutter: AppEnvironment.isDevelopment = true
        ↓
Flutter: calculates fullBaseUrl = "https://sgm.riogas.com.uy/appservices/"
        ↓
Flutter: calls platform.invokeMethod('saveBaseUrl', {'baseUrl': fullBaseUrl})
        ↓
MainActivity: saves to config.baseUrl ✅
MainActivity: DOES NOT save to flutter.baseUrl ❌
        ↓
LocationHelper: reads flutter.baseUrl
        ↓
LocationHelper: NOT FOUND, uses default: "https://www.riogas.uy/ica_geos_/appservices/" ❌
        ↓
GPS sends coordinates to PRODUCCIÓN URL ❌
```

### After Fix:
```
User selects DESARROLLO
        ↓
Flutter: AppEnvironment.isDevelopment = true
        ↓
Flutter: calculates fullBaseUrl = "https://sgm.riogas.com.uy/appservices/"
        ↓
Flutter: calls platform.invokeMethod('saveBaseUrl', {'baseUrl': fullBaseUrl})
        ↓
MainActivity: saves to config.baseUrl ✅
MainActivity: saves to flutter.baseUrl ✅ (NEW!)
        ↓
LocationHelper: reads flutter.baseUrl
        ↓
LocationHelper: FOUND! Uses: "https://sgm.riogas.com.uy/appservices/" ✅
        ↓
GPS sends coordinates to DESARROLLO URL ✅
```

## 🔄 Related Components

### Environment Selection Flow:

1. **First Dialog** (line 1022): `_showEnvironmentSelectionDialog()`
   - Shown BEFORE login for special users (49618553, 27861374)
   - Calls `AppEnvironment.setEnvironmentForSession()`

2. **Second Dialog** (line 1267): `_showServerSelectionDialog()`
   - Shown AFTER login, BEFORE mobile selection
   - Also calls `AppEnvironment.setEnvironmentForSession()`

3. **Save to Android** (line 2056-2060):
   - After mobile selection
   - Calculates `fullBaseUrl` based on `AppEnvironment.isDevelopment`
   - Calls `saveBaseUrl` and `saveIsDevelopment` MethodChannel handlers

4. **GPS Service Reads** (LocationHelper.kt line 1488):
   - When sending coordinates
   - Reads `flutter.baseUrl` from FlutterSharedPreferences
   - NOW works correctly! ✅

## 🧪 Testing

### Test Case 1: DESARROLLO Selection
1. Login with user `49618553` or `27861374`
2. Select **DESARROLLO** in BOTH environment dialogs
3. Select a mobile
4. Check logs for:
   ```
   ✅ BaseUrl guardada en config.baseUrl: https://sgm.riogas.com.uy/appservices/
   ✅ BaseUrl guardada en flutter.baseUrl: https://sgm.riogas.com.uy/appservices/
   🌍 [URL_AMBIENTE] BaseUrl obtenida: https://sgm.riogas.com.uy/appservices/
   ```
5. Verify GPS coordinates are sent to DESARROLLO URL

### Test Case 2: PRODUCCIÓN Selection
1. Login with user `49618553` or `27861374`
2. Select **PRODUCCIÓN** in environment dialogs
3. Check logs for production URL:
   ```
   🌍 [URL_AMBIENTE] BaseUrl obtenida: https://www.riogas.uy/ica_geos_/appservices/
   ```

### Test Case 3: Regular User
1. Login with regular user (not 49618553/27861374/27869041)
2. No environment dialog shown
3. Should default to PRODUCCIÓN URL

## 📝 Files Modified

- `android/app/src/main/kotlin/com/example/moveit/MainActivity.kt`
  - Modified `saveBaseUrl` MethodChannel handler (lines 161-179)
  - Added save to `FlutterSharedPreferences` with key `flutter.baseUrl`

## 🎯 Expected Result

After this fix:
- ✅ User selects DESARROLLO → GPS uses DESARROLLO URL
- ✅ User selects PRODUCCIÓN → GPS uses PRODUCCIÓN URL  
- ✅ Environment selection persists correctly to native services
- ✅ No more 404 errors on RegistrarCoordenadasV2 endpoint in dev environment

## 🔗 Related Systems

This fix also affects:
- **FcmPushReceiver.kt**: Reads `flutter.isDevelopment` to calculate URL (already working)
- **FcmApiHelper.kt**: Reads `config.baseUrl` (still works)
- **LocationHelper.kt**: Reads `flutter.baseUrl` (NOW FIXED! ✅)

All three components now have access to the correct URL based on user's environment selection.
