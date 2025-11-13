# 🌍 Sistema de URLs por Ambiente (Producción vs Desarrollo)

## 📋 Descripción General

El sistema de URLs de la aplicación utiliza **diferentes constantes según el ambiente** en el que se ejecuta:

- **🏭 PRODUCCIÓN**: Usa constantes **600** + **601** (URL compuesta)
- **🔧 DESARROLLO**: Usa constante **611** (URL completa)

---

## 🎯 Constantes por Ambiente

### 🏭 Modo PRODUCCIÓN

Se construye la URL combinando dos constantes:

#### Constante 600 - Base Root
```json
{
  "Descripcion": "Url Base Desarrollo",
  "Estado": "A",
  "Valor": "https://www.riogas.uy/"
}
```

#### Constante 601 - Services Path
```json
{
  "Descripcion": "Url Servlet Servicios Riogas",
  "Estado": "A", 
  "Valor": "ica_geos_/appservices/"
}
```

**URL Final en Producción:**
```
https://www.riogas.uy/ + ica_geos_/appservices/
= https://www.riogas.uy/ica_geos_/appservices/
```

---

### 🔧 Modo DESARROLLO

Usa una **única constante completa**:

#### Constante 611 - URL Completa Desarrollo
```json
{
  "Descripcion": "Url Base Desarrollo",
  "Estado": "A",
  "Valor": "http://201.217.139.98:8888/ICA_Geos_/appservices/"
}
```

**URL Final en Desarrollo:**
```
http://201.217.139.98:8888/ICA_Geos_/appservices/
```

---

## 🔄 Flujo de Carga

### Al Iniciar la App

```
1. main.dart
   └─> AppEnvironment.initialize()
       ├─> Lee SharedPreferences
       │   └─> Determina: Producción o Desarrollo
       └─> Carga constante 611 (para desarrollo)

2. RioGasService.initialize()
   ├─> Carga constantes 600 + 601 (para producción)
   └─> Construye _baseUrlProduction

3. RioGasService.baseUrl (getter)
   ├─> Si isDevelopment → devuelve AppEnvironment.devUrl (constante 611)
   └─> Si isProduction → devuelve _baseUrlProduction (600+601)
```

---

## 📂 Archivos Involucrados

### 1. `lib/utils/constantes.dart`

```dart
class AppEnvironment {
  static String? _devUrlFromConstant; // 👈 Cargada desde constante 611
  static const String _devUrlFallback = 'http://192.168.1.72:8082/ICA_Geos_/appservices/';
  
  static String get devUrl => _devUrlFromConstant ?? _devUrlFallback;
  
  static Future<void> initialize() async {
    // ... determina ambiente ...
    await _loadDevUrlFromConstant(); // 👈 Carga constante 611
  }
  
  static Future<void> _loadDevUrlFromConstant() async {
    final constantBox = await Hive.openBox('constantBox');
    final data = constantBox.get('611');
    
    if (data != null && data['Estado'] == 'A') {
      _devUrlFromConstant = data['Valor']?.toString().trim();
    }
  }
}
```

### 2. `lib/services/riogas_service.dart`

```dart
class RioGasService {
  static late final String _baseUrlProduction; // 👈 600 + 601
  
  static String get baseUrl {
    if (AppEnvironment.isDevelopment) {
      return AppEnvironment.devUrl; // 👈 Constante 611
    }
    return _baseUrlProduction; // 👈 Constante 600 + 601
  }
  
  static Future<void> initialize() async {
    // Carga constantes 600 y 601
    final baseRoot = await getConstantValue('600');
    final servicesPath = await getConstantValue('601');
    
    _baseUrlProduction = '$baseRoot$servicesPath';
  }
}
```

---

## 🔍 Logs Esperados

### Al Iniciar en Modo DESARROLLO

```
🌍 [AMBIENTE] Aplicación iniciada en modo DESARROLLO
🔧 [CONSTANTE 611] URL Desarrollo cargada: "http://201.217.139.98:8888/ICA_Geos_/appservices/"
🔧 [INIT] Inicializando configuración de URLs...
🔧 [INIT] Constante 600 (base): "https://www.riogas.uy/"
🔧 [INIT] Constante 601 (services): "ica_geos_/appservices/"
🔧 [INIT] ===== URL FINAL CONFIGURADA =====
🔧 [INIT] baseUrl PRODUCCIÓN (600+601) = "https://www.riogas.uy/ica_geos_/appservices/"
🔧 [INIT] baseUrl DESARROLLO (611) = "http://201.217.139.98:8888/ICA_Geos_/appservices/"
🌍 [INIT] Ambiente actual: DESARROLLO
```

**URL que se usará:** `http://201.217.139.98:8888/ICA_Geos_/appservices/` ✅

---

### Al Iniciar en Modo PRODUCCIÓN

```
🌍 [AMBIENTE] Aplicación iniciada en modo PRODUCCIÓN
🔧 [CONSTANTE 611] URL Desarrollo cargada: "http://201.217.139.98:8888/ICA_Geos_/appservices/"
🔧 [INIT] Inicializando configuración de URLs...
🔧 [INIT] Constante 600 (base): "https://www.riogas.uy/"
🔧 [INIT] Constante 601 (services): "ica_geos_/appservices/"
🔧 [INIT] ===== URL FINAL CONFIGURADA =====
🔧 [INIT] baseUrl PRODUCCIÓN (600+601) = "https://www.riogas.uy/ica_geos_/appservices/"
🔧 [INIT] baseUrl DESARROLLO (611) = "http://201.217.139.98:8888/ICA_Geos_/appservices/"
🌍 [INIT] Ambiente actual: PRODUCCIÓN
```

**URL que se usará:** `https://www.riogas.uy/ica_geos_/appservices/` ✅

---

## ⚙️ Cómo Cambiar de Ambiente

### Desde la App

1. Ir a **Settings** (⚙️)
2. Scroll hasta encontrar **"Modo Desarrollo"**
3. Toggle ON/OFF
   - **ON** = Desarrollo (usa constante 611)
   - **OFF** = Producción (usa constantes 600+601)
4. **Reiniciar la app** para aplicar cambios

### Programáticamente

```dart
// Cambiar a desarrollo
await AppEnvironment.setEnvironment(Environment.development);

// Cambiar a producción
await AppEnvironment.setEnvironment(Environment.production);

// Verificar ambiente actual
if (AppEnvironment.isDevelopment) {
  print('Estás en desarrollo');
}
```

---

## 🐛 Troubleshooting

### Problema: La app usa URL incorrecta

**Síntomas:**
- Esperabas `http://192.168.1.72:8082/...` pero usa `https://www.riogas.uy/...`
- O viceversa

**Solución:**

1. **Verificar ambiente actual:**
   ```powershell
   adb logcat | Select-String "AMBIENTE.*iniciada"
   ```
   
   Buscar línea:
   - `🌍 [AMBIENTE] Aplicación iniciada en modo DESARROLLO` → Usa 611
   - `🌍 [AMBIENTE] Aplicación iniciada en modo PRODUCCIÓN` → Usa 600+601

2. **Verificar constante 611 cargada:**
   ```powershell
   adb logcat | Select-String "CONSTANTE 611"
   ```
   
   Debe mostrar:
   ```
   🔧 [CONSTANTE 611] URL Desarrollo cargada: "http://201.217.139.98:8888/ICA_Geos_/appservices/"
   ```

3. **Verificar URL final usada:**
   ```powershell
   adb logcat | Select-String "URL FINAL CONFIGURADA" -Context 0,3
   ```

---

### Problema: Constante 611 no se carga

**Síntomas:**
```
⚠️ [CONSTANTE 611] No existe o Estado != A, usando fallback
```

**Causas posibles:**

1. **Constante 611 no existe en Firestore**
   - Crear en Firebase Console
   - Estado = 'A'
   - Valor = "http://192.168.1.72:8082/ICA_Geos_/appservices/"

2. **Estado no es 'A'**
   - Cambiar Estado a 'A' en Firestore

3. **Valor vacío o null**
   - Agregar valor válido

**Fallback automático:**
Si la constante 611 falla, usa:
```
http://201.217.139.98:8888/ICA_Geos_/appservices/
```

---

## 📊 Tabla Comparativa

| Aspecto | Producción 🏭 | Desarrollo 🔧 |
|---------|---------------|---------------|
| **Constantes usadas** | 600 + 601 | 611 |
| **URL típica** | `https://www.riogas.uy/...` | `http://201.217.139.98:8888/...` |
| **Construcción** | Compuesta (base + path) | Completa (todo en una) |
| **Modificación** | Editar 2 constantes | Editar 1 constante |
| **Fallback** | Hardcoded en código | Hardcoded en código |
| **Validación Estado** | ✅ Sí | ✅ Sí |

---

## ✅ Checklist de Verificación

Cuando actualices URLs, verifica:

- [ ] Constante 600 tiene URL base correcta (producción)
- [ ] Constante 601 tiene path de servicios correcto (producción)
- [ ] Constante 611 tiene URL completa correcta (desarrollo)
- [ ] Todas las constantes tienen Estado = 'A'
- [ ] URL de producción termina en `/appservices/`
- [ ] URL de desarrollo termina en `/appservices/`
- [ ] Logs muestran URLs correctas al iniciar
- [ ] Ambiente configurado correctamente en Settings

---

## 🎯 Ejemplos de Llamadas

### En Producción

```dart
// baseUrl = "https://www.riogas.uy/ica_geos_/appservices/"

await RioGasService.finalizarPedido(...);
// 👉 POST https://www.riogas.uy/ica_geos_/appservices/FinalizarPedidoV3

await RioGasService.descargaPedidos(...);
// 👉 POST https://www.riogas.uy/ica_geos_/appservices/DescargaPedidosV3
```

### En Desarrollo

```dart
// baseUrl = "http://201.217.139.98:8888/ICA_Geos_/appservices/"

await RioGasService.finalizarPedido(...);
// 👉 POST http://201.217.139.98:8888/ICA_Geos_/appservices/FinalizarPedidoV3

await RioGasService.descargaPedidos(...);
// 👉 POST http://201.217.139.98:8888/ICA_Geos_/appservices/DescargaPedidosV3
```

---

## 🔒 Seguridad

### URLs en Logs

Las URLs se loguean al iniciar. En producción, considera:

1. **No loguear URLs sensibles** en builds de release
2. **Usar ProGuard/R8** para ofuscar logs
3. **Remover prints** de URLs en modo producción

### Ejemplo de log condicional:

```dart
if (kDebugMode) {
  print('🔧 [INIT] baseUrl PRODUCCIÓN = "$_baseUrlProduction"');
}
```

---

## 📝 Notas Importantes

1. ✅ **Reiniciar app** después de cambiar constantes en Firestore
2. ✅ **Reiniciar app** después de cambiar de ambiente en Settings
3. ⚠️ Las constantes se cargan **solo al iniciar** la app
4. ⚠️ El fallback **solo se usa si falla la carga** de constantes
5. 🔧 En desarrollo, puedes usar IP local (192.168.x.x)
6. 🏭 En producción, usa dominio público (www.riogas.uy)

---

**Fecha de creación:** 7 de noviembre de 2025  
**Archivos modificados:** `constantes.dart`, `riogas_service.dart`  
**Constantes involucradas:** 600, 601, 611
