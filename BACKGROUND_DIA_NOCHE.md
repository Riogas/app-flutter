# 🌙☀️ Sistema Dinámico de Backgrounds Día/Noche

## 📋 Descripción General

Sistema automático que detecta la hora actual en Uruguay (incluyendo horario de verano) y carga el background correspondiente para la pantalla de login.

---

## 🎯 Funcionalidad

### Detección Automática de Hora

El sistema determina si es **día** o **noche** en Uruguay basándose en:

- ✅ Hora local de Uruguay (UTC-3 o UTC-2)
- ✅ Horario de verano automático
- ✅ Rango horario definido

---

## 🕐 Definición de Horarios

### Noche 🌙
**20:00 - 06:00** (8 PM a 6 AM)

### Día ☀️
**06:00 - 20:00** (6 AM a 8 PM)

---

## 🌍 Horario de Verano en Uruguay

### Cambio Automático

El sistema detecta automáticamente el horario de verano de Uruguay:

| Período | Offset UTC | Fechas |
|---------|------------|--------|
| **Horario Estándar** | UTC-3 | Segundo domingo de marzo - Primer domingo de octubre |
| **Horario de Verano** | UTC-2 | Primer domingo de octubre - Segundo domingo de marzo |

### Ejemplo de Cambios (2025-2026)

```
📅 Horario Estándar 2025:
   Desde: 9 de marzo 2025 (segundo domingo de marzo)
   Hasta: 5 de octubre 2025 (primer domingo de octubre)
   Offset: UTC-3

📅 Horario de Verano 2025-2026:
   Desde: 5 de octubre 2025
   Hasta: 8 de marzo 2026
   Offset: UTC-2
```

---

## 📁 Archivos de Background

### Nomenclatura de Archivos

El sistema busca archivos con el siguiente patrón:

```
background_delivery_<periodo>.<extension>
```

| Período | Archivo | Hora |
|---------|---------|------|
| **Día** | `background_delivery_dia.png/gif/mp4` | 06:00 - 20:00 |
| **Noche** | `background_delivery_noche.png/gif/mp4` | 20:00 - 06:00 |

### URLs Completas

```
Día:
- https://www.riogas.uy/ica_geos_/static/Resources/background_delivery_dia.mp4
- https://www.riogas.uy/ica_geos_/static/Resources/background_delivery_dia.gif
- https://www.riogas.uy/ica_geos_/static/Resources/background_delivery_dia.png

Noche:
- https://www.riogas.uy/ica_geos_/static/Resources/background_delivery_noche.mp4
- https://www.riogas.uy/ica_geos_/static/Resources/background_delivery_noche.gif
- https://www.riogas.uy/ica_geos_/static/Resources/background_delivery_noche.png
```

---

## 🔄 Orden de Carga (Cascada)

### Paso 1: Detectar Día/Noche
```dart
bool isNight = _isNightTimeInUruguay();
String timeOfDay = isNight ? 'noche' : 'dia';
```

### Paso 2: Intentar Cargar (en orden)

1. **Video específico**: `background_delivery_<periodo>.mp4`
2. **GIF específico**: `background_delivery_<periodo>.gif`
3. **Imagen específica**: `background_delivery_<periodo>.png`
4. **Imagen genérica**: `background_delivery.png` (fallback)
5. **Video local**: `assets/back_video.mp4` (último fallback)

---

## 🧮 Algoritmo de Detección

### Función Principal: `_isNightTimeInUruguay()`

```dart
bool _isNightTimeInUruguay() {
  final now = DateTime.now().toUtc();
  int uruguayOffset = -3; // Horario estándar
  
  // 1. Calcular inicio horario de verano (primer domingo de octubre)
  final summerStart = _getFirstSundayOfOctober(now.year);
  
  // 2. Calcular fin horario de verano (segundo domingo de marzo siguiente)
  final summerEnd = _getSecondSundayOfMarch(now.year + 1);
  
  // 3. Determinar offset actual
  if (now.isAfter(summerStart) && now.isBefore(summerEnd)) {
    uruguayOffset = -2; // Horario de verano
  }
  
  // 4. Convertir a hora de Uruguay
  final uruguayTime = now.add(Duration(hours: uruguayOffset));
  final hour = uruguayTime.hour;
  
  // 5. Determinar si es noche (20:00 - 06:00)
  return hour >= 20 || hour < 6;
}
```

### Cálculo de Primer Domingo de Octubre

```dart
final octoberFirst = DateTime.utc(year, 10, 1);
int daysUntilSunday = (7 - octoberFirst.weekday) % 7;
final summerStart = DateTime.utc(year, 10, 1 + daysUntilSunday);
```

### Cálculo de Segundo Domingo de Marzo

```dart
final marchFirst = DateTime.utc(year + 1, 3, 1);
int daysUntilSunday = (7 - marchFirst.weekday) % 7;
final summerEnd = DateTime.utc(year + 1, 3, 1 + daysUntilSunday + 7);
```

---

## 📊 Ejemplos de Detección

### Ejemplo 1: Día de Verano (Enero)

```
Fecha/Hora UTC: 2025-01-15 12:00 UTC
Horario de verano: SÍ (octubre 2024 - marzo 2025)
Offset: UTC-2
Hora en Uruguay: 10:00
Resultado: ☀️ DÍA
Background: background_delivery_dia.png
```

### Ejemplo 2: Noche de Verano (Diciembre)

```
Fecha/Hora UTC: 2025-12-20 01:00 UTC
Horario de verano: SÍ (octubre 2025 - marzo 2026)
Offset: UTC-2
Hora en Uruguay: 23:00 (11 PM)
Resultado: 🌙 NOCHE
Background: background_delivery_noche.png
```

### Ejemplo 3: Día Horario Estándar (Junio)

```
Fecha/Hora UTC: 2025-06-10 14:00 UTC
Horario de verano: NO
Offset: UTC-3
Hora en Uruguay: 11:00
Resultado: ☀️ DÍA
Background: background_delivery_dia.png
```

### Ejemplo 4: Noche Horario Estándar (Julio)

```
Fecha/Hora UTC: 2025-07-05 08:00 UTC
Horario de verano: NO
Offset: UTC-3
Hora en Uruguay: 05:00 (5 AM)
Resultado: 🌙 NOCHE
Background: background_delivery_noche.png
```

---

## 🎨 Tabla de Horarios (24 horas)

| Hora Uruguay | Período | Background | Emoji |
|--------------|---------|------------|-------|
| 00:00 - 00:59 | Noche | `_noche.png` | 🌙 |
| 01:00 - 01:59 | Noche | `_noche.png` | 🌙 |
| 02:00 - 02:59 | Noche | `_noche.png` | 🌙 |
| 03:00 - 03:59 | Noche | `_noche.png` | 🌙 |
| 04:00 - 04:59 | Noche | `_noche.png` | 🌙 |
| 05:00 - 05:59 | Noche | `_noche.png` | 🌙 |
| **06:00 - 06:59** | **Día** | `_dia.png` | ☀️ |
| 07:00 - 07:59 | Día | `_dia.png` | ☀️ |
| 08:00 - 08:59 | Día | `_dia.png` | ☀️ |
| 09:00 - 09:59 | Día | `_dia.png` | ☀️ |
| 10:00 - 10:59 | Día | `_dia.png` | ☀️ |
| 11:00 - 11:59 | Día | `_dia.png` | ☀️ |
| 12:00 - 12:59 | Día | `_dia.png` | ☀️ |
| 13:00 - 13:59 | Día | `_dia.png` | ☀️ |
| 14:00 - 14:59 | Día | `_dia.png` | ☀️ |
| 15:00 - 15:59 | Día | `_dia.png` | ☀️ |
| 16:00 - 16:59 | Día | `_dia.png` | ☀️ |
| 17:00 - 17:59 | Día | `_dia.png` | ☀️ |
| 18:00 - 18:59 | Día | `_dia.png` | ☀️ |
| 19:00 - 19:59 | Día | `_dia.png` | ☀️ |
| **20:00 - 20:59** | **Noche** | `_noche.png` | 🌙 |
| 21:00 - 21:59 | Noche | `_noche.png` | 🌙 |
| 22:00 - 22:59 | Noche | `_noche.png` | 🌙 |
| 23:00 - 23:59 | Noche | `_noche.png` | 🌙 |

---

## 🔍 Logs de Debug

### Logs al Iniciar Login

```bash
🕐 [LOGIN_BG] Hora UTC: 14:30
🇺🇾 [LOGIN_BG] Hora Uruguay: 11:30
🌡️ [LOGIN_BG] Offset UTC: -3 (Horario estándar)
☀️ [LOGIN_BG] Es de DÍA
🎨 [LOGIN_BG] Cargando background de dia
🖼️ [LOGIN_BG] Imagen remota encontrada: https://...background_delivery_dia.png
```

### Logs Durante Noche

```bash
🕐 [LOGIN_BG] Hora UTC: 02:15
🇺🇾 [LOGIN_BG] Hora Uruguay: 23:15
🌡️ [LOGIN_BG] Offset UTC: -2 (Horario de verano)
🌙 [LOGIN_BG] Es de NOCHE
🎨 [LOGIN_BG] Cargando background de noche
🖼️ [LOGIN_BG] Imagen remota encontrada: https://...background_delivery_noche.png
```

---

## 📝 Filtros de Logcat

```powershell
# Ver detección de día/noche
adb logcat | Select-String "LOGIN_BG.*Uruguay|LOGIN_BG.*DÍA|LOGIN_BG.*NOCHE"

# Ver carga de backgrounds
adb logcat | Select-String "LOGIN_BG.*background_delivery"

# Ver todos los logs de login background
adb logcat | Select-String "LOGIN_BG"
```

---

## 🛠️ Configuración de Archivos

### Subir Archivos al Servidor

Para que el sistema funcione, debes subir los archivos al servidor:

```
Servidor: www.riogas.uy
Ruta: /ica_geos_/static/Resources/

Archivos necesarios:
✅ background_delivery_dia.png (obligatorio)
✅ background_delivery_noche.png (obligatorio)
⭕ background_delivery_dia.gif (opcional)
⭕ background_delivery_noche.gif (opcional)
⭕ background_delivery_dia.mp4 (opcional)
⭕ background_delivery_noche.mp4 (opcional)
⭕ background_delivery.png (fallback genérico)
```

### Recomendaciones de Diseño

#### Background de Día ☀️
- Colores brillantes y cálidos
- Alta luminosidad
- Tonos claros (blancos, amarillos, azules claros)
- Sugerencia: cielo azul, paisaje diurno

#### Background de Noche 🌙
- Colores oscuros y fríos
- Baja luminosidad
- Tonos oscuros (azules oscuros, morados, negros)
- Sugerencia: cielo nocturno, estrellas, luna

---

## ⚙️ Personalización

### Cambiar Horarios de Día/Noche

Si deseas modificar los horarios, edita esta línea en `login_page.dart`:

```dart
// Actualmente: Noche = 20:00 - 06:00
final isNight = hour >= 20 || hour < 6;

// Ejemplo: Noche = 19:00 - 07:00
final isNight = hour >= 19 || hour < 7;

// Ejemplo: Noche = 21:00 - 05:00
final isNight = hour >= 21 || hour < 5;
```

### Cambiar URLs de Background

Si los archivos están en otra ubicación:

```dart
// Cambiar URL base
static const String _remoteBaseUrl =
    'https://tu-servidor.com/ruta/background_delivery';
```

---

## 🧪 Testing

### Pruebas Manuales

```dart
// Para probar en diferentes horas, puedes modificar temporalmente:
final now = DateTime.now().toUtc();

// Simular las 3 AM Uruguay (noche)
final now = DateTime.utc(2025, 11, 7, 6, 0); // 6 AM UTC = 3 AM Uruguay

// Simular las 10 AM Uruguay (día)
final now = DateTime.utc(2025, 11, 7, 13, 0); // 1 PM UTC = 10 AM Uruguay

// Simular las 9 PM Uruguay (noche)
final now = DateTime.utc(2025, 11, 8, 0, 0); // 12 AM UTC = 9 PM Uruguay
```

### Casos de Prueba

| Caso | Hora UTC | Horario Verano | Hora UY | Esperado |
|------|----------|----------------|---------|----------|
| Madrugada verano | 07:00 | Sí (-2) | 05:00 | 🌙 Noche |
| Mañana verano | 13:00 | Sí (-2) | 11:00 | ☀️ Día |
| Tarde estándar | 20:00 | No (-3) | 17:00 | ☀️ Día |
| Noche estándar | 01:00 | No (-3) | 22:00 | 🌙 Noche |
| Límite día inicio | 09:00 | No (-3) | 06:00 | ☀️ Día |
| Límite noche inicio | 23:00 | No (-3) | 20:00 | 🌙 Noche |

---

## 📊 Ventajas del Sistema

✅ **Automático**: No requiere configuración manual
✅ **Preciso**: Considera horario de verano de Uruguay
✅ **Dinámico**: Cambia en tiempo real según la hora
✅ **Fallback**: Si no hay archivo específico, usa genérico
✅ **Experiencia de usuario**: Background acorde al momento del día
✅ **Mantenible**: URLs remotas fáciles de actualizar

---

## 🚨 Errores Comunes

### Error: Muestra el background genérico

**Causa:** No existen los archivos `_dia.png` o `_noche.png` en el servidor

**Solución:** Subir los archivos correctos al servidor

### Error: Siempre muestra el mismo background

**Causa:** La función de detección puede tener problemas

**Solución:** Revisar logs para ver qué hora detecta:
```bash
adb logcat | Select-String "Hora Uruguay"
```

### Error: Background cambia a la hora incorrecta

**Causa:** Offset UTC mal calculado

**Solución:** Verificar que el cálculo de horario de verano sea correcto

---

## 📅 Próximas Mejoras (Opcional)

1. **Atardecer/Amanecer**: Agregar períodos intermedios (5-7 AM, 18-20 PM)
2. **Cache local**: Guardar última imagen descargada para offline
3. **Animaciones**: Transición suave entre día/noche
4. **Estaciones**: Backgrounds diferentes por estación del año
5. **Geolocalización**: Detectar ubicación real del usuario

---

## ✅ Checklist de Implementación

- [x] Función de detección día/noche
- [x] Cálculo de horario de verano Uruguay
- [x] Carga dinámica de backgrounds según hora
- [x] Logs detallados para debugging
- [x] Fallback a background genérico
- [x] Documentación completa
- [ ] Subir archivos `background_delivery_dia.png` al servidor
- [ ] Subir archivos `background_delivery_noche.png` al servidor
- [ ] Probar en diferentes horarios
- [ ] Validar cambio de horario de verano (octubre/marzo)

---

**Fecha de implementación:** 7 de noviembre de 2025  
**Estado:** ✅ Implementado - Pendiente subir archivos al servidor  
**Archivos modificados:** `lib/pages/login_page.dart`
