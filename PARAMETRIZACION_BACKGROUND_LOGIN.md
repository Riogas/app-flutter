# 🎨 Parametrización de Background del Login

## 📋 Resumen

El background del login ahora es **parametrizable** mediante archivos remotos en el servidor. Si no hay background personalizado, usa el video local por defecto.

---

## ✨ Características

### 🎯 Comportamiento

1. **Intenta cargar background remoto** desde `https://www.riogas.uy/ica_geos_/static/Resources/`
2. **Prueba múltiples formatos** en orden de preferencia:
   - 📹 Video MP4 (`background_delivery.mp4`)
   - 🎞️ GIF animado (`background_delivery.gif`)
   - 🖼️ Imagen estática PNG (`background_delivery.png`)
3. **Fallback automático**: Si no encuentra ninguno remoto, usa `assets/back_video.mp4` (local)

### 🌐 URL Base

```
https://www.riogas.uy/ica_geos_/static/Resources/background_delivery
```

Los archivos deben estar accesibles en:
- `background_delivery.mp4` (video)
- `background_delivery.gif` (animación)
- `background_delivery.png` (imagen estática)

---

## 🔄 Flujo de Carga

```
┌─────────────────────────┐
│  Inicio de Login        │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│ ¿Existe background_delivery.mp4?    │
│ (HEAD request con timeout 3s)       │
└────────┬────────────────────────────┘
         │
    ┌────┴────┐
    │   SÍ    │ ✅ Cargar video remoto
    └─────────┘
         │
         ▼
┌─────────────────────────────────────┐
│ ¿Existe background_delivery.gif?    │
└────────┬────────────────────────────┘
         │
    ┌────┴────┐
    │   SÍ    │ ✅ Cargar GIF remoto
    └─────────┘
         │
         ▼
┌─────────────────────────────────────┐
│ ¿Existe background_delivery.png?    │
└────────┬────────────────────────────┘
         │
    ┌────┴────┐
    │   SÍ    │ ✅ Cargar imagen remota
    └─────────┘
         │
         ▼
┌─────────────────────────────────────┐
│ ❌ Ninguno encontrado                │
│ ✅ Usar assets/back_video.mp4        │
│    (video local)                     │
└─────────────────────────────────────┘
```

---

## 🛠️ Implementación Técnica

### 1️⃣ Verificación de Existencia (HEAD Request)

```dart
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
```

### 2️⃣ Carga Secuencial por Prioridad

```dart
// 1. Video MP4 (preferido)
if (await _checkUrlExists('$_remoteBaseUrl.mp4')) {
  await _loadRemoteVideo('$_remoteBaseUrl.mp4');
  return;
}

// 2. GIF animado
if (await _checkUrlExists('$_remoteBaseUrl.gif')) {
  setState(() {
    _backgroundType = 'gif';
    _imageUrl = '$_remoteBaseUrl.gif';
  });
  return;
}

// 3. PNG estático
if (await _checkUrlExists('$_remoteBaseUrl.png')) {
  setState(() {
    _backgroundType = 'image';
    _imageUrl = '$_remoteBaseUrl.png';
  });
  return;
}

// 4. Fallback local
await _loadLocalVideo();
```

### 3️⃣ Renderizado Adaptativo

```dart
Widget _buildBackground() {
  switch (_backgroundType) {
    case 'video':
      return VideoPlayer(_videoController!);
    
    case 'image':
    case 'gif':
      return Image.network(
        _imageUrl!,
        fit: BoxFit.cover,
      );
    
    default:
      return Container(color: Colors.black);
  }
}
```

---

## 📊 Formatos Soportados

| Formato | Extensión | Tipo | Características |
|---------|-----------|------|-----------------|
| **Video** | `.mp4` | VideoPlayer | Loop automático, sin sonido |
| **GIF** | `.gif` | Image.network | Animación nativa del formato |
| **Imagen** | `.png` | Image.network | Estática, sin animación |
| **Local** | `.mp4` | VideoPlayer | Fallback desde `assets/` |

---

## 🔍 Logs de Ejemplo

### Caso 1: Video Remoto Encontrado
```
📹 [LOGIN_BG] Video remoto encontrado: https://www.riogas.uy/ica_geos_/static/Resources/background_delivery.mp4
```

### Caso 2: GIF Remoto Encontrado
```
🎞️ [LOGIN_BG] GIF remoto encontrado: https://www.riogas.uy/ica_geos_/static/Resources/background_delivery.gif
```

### Caso 3: Imagen Remota Encontrada
```
🖼️ [LOGIN_BG] Imagen remota encontrada: https://www.riogas.uy/ica_geos_/static/Resources/background_delivery.png
```

### Caso 4: Fallback a Local
```
📦 [LOGIN_BG] No se encontró background remoto, usando asset local
```

### Caso 5: Error Cargando Remoto
```
❌ [LOGIN_BG] Error cargando video remoto: SocketException
📦 [LOGIN_BG] No se encontró background remoto, usando asset local
```

---

## 📝 Cómo Configurar un Background Personalizado

### Opción 1: Video MP4 (Recomendado)
1. Crear un video en formato MP4
2. Subirlo al servidor como: `background_delivery.mp4`
3. URL final: `https://www.riogas.uy/ica_geos_/static/Resources/background_delivery.mp4`
4. La app lo detectará automáticamente

### Opción 2: GIF Animado
1. Crear/obtener un GIF animado
2. Subirlo como: `background_delivery.gif`
3. URL final: `https://www.riogas.uy/ica_geos_/static/Resources/background_delivery.gif`

### Opción 3: Imagen Estática PNG
1. Crear/obtener una imagen PNG
2. Subirla como: `background_delivery.png`
3. URL final: `https://www.riogas.uy/ica_geos_/static/Resources/background_delivery.png`

### ⚠️ Importante
- El archivo debe ser **accesible públicamente** (sin autenticación)
- Debe responder **HTTP 200** a un HEAD request
- Tamaño recomendado: **< 5 MB** para carga rápida
- Resolución recomendada: **1080x1920** (vertical) o **1920x1080** (horizontal)

---

## 🎯 Casos de Uso

### Caso 1: Campaña de Marketing
```
background_delivery.mp4 → Video promocional de Navidad
```

### Caso 2: Branding Regional
```
background_delivery.png → Logo/imagen específica de la región
```

### Caso 3: Sin Personalización
```
(No subir ningún archivo)
→ App usa assets/back_video.mp4 por defecto
```

---

## ⚡ Optimizaciones

### Timeout Corto (3 segundos)
```dart
.timeout(Duration(seconds: 3))
```
- Si el servidor tarda >3s, se salta al siguiente formato
- Evita que el login tarde mucho en cargar

### HEAD Request (No descarga el archivo)
```dart
await http.head(Uri.parse(url))
```
- Solo verifica si existe, no lo descarga
- Muy rápido, consume ~1 KB de datos

### Carga Progresiva
```dart
loadingBuilder: (context, child, loadingProgress) {
  if (loadingProgress == null) return child;
  return Container(color: Colors.black); // Mientras carga
}
```

---

## 🧪 Testing

### Test 1: Sin Internet
1. Desconectar internet
2. Abrir app
3. ✅ Debería mostrar video local `assets/back_video.mp4`

### Test 2: Con Video Remoto
1. Subir `background_delivery.mp4` al servidor
2. Abrir app con internet
3. ✅ Debería mostrar video remoto
4. Logs: `📹 [LOGIN_BG] Video remoto encontrado`

### Test 3: Solo GIF Disponible
1. Eliminar `.mp4` del servidor
2. Subir `background_delivery.gif`
3. Abrir app
4. ✅ Debería mostrar GIF animado
5. Logs: `🎞️ [LOGIN_BG] GIF remoto encontrado`

### Test 4: Solo PNG Disponible
1. Eliminar `.mp4` y `.gif` del servidor
2. Subir `background_delivery.png`
3. Abrir app
4. ✅ Debería mostrar imagen estática
5. Logs: `🖼️ [LOGIN_BG] Imagen remota encontrada`

### Test 5: Servidor Caído
1. Simular servidor caído (timeout)
2. Abrir app
3. ✅ Después de 3s por formato (9s total), usa video local
4. Logs: `📦 [LOGIN_BG] No se encontró background remoto, usando asset local`

---

## 🔧 Archivos Modificados

1. ✅ `lib/pages/login_page.dart`
   - Clase `_LoginBackgroundState` completamente reescrita
   - Soporte para múltiples formatos (MP4, GIF, PNG)
   - Verificación remota con HEAD requests
   - Fallback automático a asset local
   - Añadido import: `package:http/http.dart`

---

## 📦 Dependencias

Ya incluidas en `pubspec.yaml`:
- ✅ `video_player` - Para reproducir videos MP4
- ✅ `http` - Para verificar existencia de URLs remotas

---

## 🎨 Personalización Avanzada

### Cambiar URL Base
```dart
static const String _remoteBaseUrl =
    'https://tu-servidor.com/custom/path/background';
```

### Agregar Más Formatos
```dart
// Ejemplo: agregar soporte para WebP
final webpUrl = '$_remoteBaseUrl.webp';
if (await _checkUrlExists(webpUrl)) {
  setState(() {
    _backgroundType = 'image';
    _imageUrl = webpUrl;
  });
  return;
}
```

### Ajustar Timeout
```dart
// Aumentar timeout a 5 segundos
.timeout(Duration(seconds: 5))
```

---

## ✅ Ventajas

1. ✅ **Flexible**: Soporta video, GIF e imagen estática
2. ✅ **Robusto**: Fallback automático a asset local
3. ✅ **Rápido**: HEAD request + timeout corto (3s)
4. ✅ **Sin Cambios de Código**: Solo subir archivo al servidor
5. ✅ **Priorización Inteligente**: Intenta video primero (mejor UX)
6. ✅ **Error Handling**: Maneja timeouts y errores de red

---

## 🚨 Troubleshooting

### Problema: No carga el video remoto
**Solución**:
1. Verificar que la URL es accesible: `curl -I https://www.riogas.uy/ica_geos_/static/Resources/background_delivery.mp4`
2. Debe responder `HTTP/1.1 200 OK`
3. Verificar logs en la app: `adb logcat | Select-String "LOGIN_BG"`

### Problema: Se queda en negro mucho tiempo
**Solución**:
- El timeout está en 3s por formato (9s total máximo)
- Si tarda más, verificar conexión a internet
- Revisar si el servidor está respondiendo lento

### Problema: Video local no funciona
**Solución**:
1. Verificar que existe `assets/back_video.mp4`
2. Verificar `pubspec.yaml` tiene:
```yaml
flutter:
  assets:
    - assets/back_video.mp4
```

---

## 📌 Conclusión

El sistema ahora permite cambiar el background del login **sin tocar código**, solo subiendo archivos al servidor. Esto permite:
- 🎄 Campañas estacionales (Navidad, etc.)
- 🏢 Branding personalizado por región
- 🎨 A/B testing de diseños
- 🚀 Actualizaciones visuales inmediatas
