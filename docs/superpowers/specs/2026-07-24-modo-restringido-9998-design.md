# Modo restringido (escenario 9998) + auto-selección de móvil único

**Fecha:** 2026-07-24
**Branch base:** `refactor/gps-persistente`
**Estado:** diseño aprobado, pendiente de plan de implementación

---

## 1. Problema

Dos cambios independientes que comparten el mismo punto de entrada (el login):

1. **Auto-selección de móvil único — para todos los usuarios.** Hoy, si `ListaMoviles` trae un solo móvil, la app igual abre el diálogo de selección con un dropdown de un ítem. Peor: el ítem ni siquiera queda preseleccionado salvo que coincida con el móvil de un login anterior, así que el usuario tiene que abrir el combo y elegir la única opción que hay. Si la lista viene vacía, el login muere en silencio.

2. **Perfil "comercio adherido" (escenario 9998).** Un nuevo tipo de usuario —kiosco, agencia o fletera— que entra a la app únicamente a operar promociones. No hace reparto, así que no tiene sentido trackearlo por GPS ni mostrarle nada de la operativa de móviles.

---

## 2. Contexto: cómo funciona hoy

Verificado leyendo el código en `refactor/gps-persistente` (commit `b6fbb37`). Donde la documentación `.md` de la raíz del repo contradice al código, **manda el código**; el único documento alineado con la realidad actual es `REFACTOR_GPS_PERSISTENTE.md`.

### 2.1 Login y selección de móvil

`POST ValidarUsuario` devuelve, entre otros campos, `escenarioid` (string, a nivel raíz) y `ListaMoviles` — que **no** es un array sino un string con JSON adentro que hay que decodificar por segunda vez (`login_page.dart:2966`). Cada ítem trae solo `SDT_Mov_MovId`, `SDT_Mov_MovMat` y `DV_P_M_MOVDESCRIPCION`: **no hay ningún campo de escenario por móvil**.

El patrón `_extractAvailableMoviles(response)` + `_showMobileSelectionDialog(response)` está duplicado en **tres call sites** (`login_page.dart:1508`, `:1545`, `:1619`), correspondientes a las ramas `OK==0` sin registro previo, `OK==0` con registro de dispositivo, y `OK==9` con re-login. La única condición es `if (_availableMoviles.isNotEmpty)`, sin rama `else`.

El botón *Confirmar* del diálogo (`:2202-2346`) hace **ocho escrituras** antes de continuar: Hive `sessionBox` y `usuarioBox`, `SessionSyncService.syncToSharedPrefs()`, y los MethodChannel nativos `saveMovil`, `saveEscenario`, `saveBaseUrl`, `saveIsDevelopment`, más la fecha del día. Recién después llama a `_proceedAfterMobileSelection()` (credenciales, `firstLoginDone`, `loginDate`, auth Firebase, sesión en Firestore, `registrarUltLog`) y luego `_onSuccessfulLoginFlow()` (constantes, `sessionActive=true`, arranque del FGS de GPS, streams persistentes) para finalmente navegar a `HomePage`.

### 2.2 El escenario

```dart
// login_page.dart:2422-2425
await box.put('escenario', response['escenarioid'] == "1000" ? "1000" : "2000");
```

El valor real se **aplasta** a dos posibilidades. La misma coerción se repite para las prefs nativas en `:2260-2265`, y existe una tercera en `auth_service.dart:54` que es **código muerto** (nadie llama a `AuthService.login()`) y además compara contra el `int` 1000 en vez del `String`.

Ese valor es la clave multi-tenant de todo el sistema: sufijo de las colecciones `sessions-`, `Pedidos-`, `Mensajes-`, `Moviles-`, `SubEstadoMoviles-`, `CoordenadasMoviles-`, y parámetro `escenarioid` de casi todos los endpoints GeneXus. Los únicos valores conocidos son `1000` y `2000`, más `'0'` como centinela de "no definido" que bloquea la creación y el cierre de sesión.

**El literal `9998` no existe hoy en ninguna parte del repositorio** (ni Dart, ni Kotlin, ni manifest, ni documentación).

### 2.3 GPS y supervivencia del proceso

Existe **un solo** foreground service: `LocationTrackingService`, declarado con `foregroundServiceType="location"`. El refactor de esta rama eliminó AlarmManager, `LocationWorker`, `ForegroundLocationService` y el watchdog reiniciador. No hay wakelock propio ni servicio secundario: **el FGS es lo único que mantiene el proceso vivo**.

Hay cuatro caminos que lo arrancan:

| # | Camino | Detalle |
|---|---|---|
| 1 | `login_page.dart:3195` | `MethodChannel("background_service").invokeMethod("startLocationService")` al terminar el login |
| 2 | `MainActivity.kt:937` | `restartLocationServiceFromForeground()` dentro de `onCreate`, **antes de `super.onCreate()`** y por lo tanto antes de que exista el engine de Flutter. Arranca leyendo `config.last_movil` |
| 3 | `FcmPushReceiver.handleRestartTracking` | Comando remoto `restart_tracking` (+ aliases). Limpia `service_disabled`/`service_paused`/`watchdog_disabled` y arranca |
| 4 | `HealthCheckWorker` | Cada 15 min, si el FGS está caído **y** el equipo tiene exención de batería. Programado con `ExistingPeriodicWorkPolicy.KEEP`, sobrevive reinicios |

Además `MainActivity.startLocationService` **limpia los flags** de servicio deshabilitado y pausado (`:383-385`), con lo cual cualquier intento de "apagar el GPS con un flag" queda anulado si algún otro camino lo invoca.

Existen dos efectos colaterales de GPS independientes del tracking: el `LocationService` legado dispara el intent de exención de batería en cada `initState` de `HomePage` (`location_service.dart:38`), y `GPSStatusReceiver` muestra una notificación *ongoing* "Ubicación desactivada" ante `PROVIDERS_CHANGED`.

### 2.4 Control de sesión

**No existe ningún heartbeat.** El documento `sessions-{escenario}/{AAAAMMDD}/activeSessions/Usuario-{username}` se escribe una vez al login y no se actualiza nunca más; `registrarUltLog` se llama únicamente en el login; el FGS no valida sesión ni fecha. Confirmado con el equipo: **el backend no borra sesiones por falta de coordenadas**.

Conclusión: dejar de enviar GPS **no cierra la sesión**. El único acoplamiento real es de supervivencia — sin FGS el proceso queda como *cached process* y el LMK de Android lo puede matar; mientras esté muerto no corren ni el listener de sesión ni el logout remoto.

Los cuatro caminos vivos de cierre de sesión (logout manual, logout remoto por FCM, sesión inválida por desaparición del documento Firestore, y auto-logout por cambio de día) terminan todos en `LogoutService.executeLogout()`, que hace `exit(0)`.

### 2.5 Shell de navegación

`HomePage` no dibuja UI propia: en `build()` (`:1007`) un `ValueListenableBuilder<UiPrefs.homeV2>` elige entre `HomeV2Scaffold` (default) y `_buildLegacyScaffold`. **La preferencia vive en `usuarioBox` y sobrevive al logout**, así que hay dispositivos que pueden llegar en shell clásico.

`HomeV2Scaffold` es un `IndexedStack` con los **tres tabs siempre construidos** (Pedidos, Mapa, Promos) — sus `initState` y timers corren aunque no se vean. `PedidosTabV2` arranca un `Timer.periodic` de 30 s que usa `Geolocator`.

Toda la barra superior es un único widget compartido por **seis pantallas**: `V2Header`. Ahí viven el ícono de Mensajes, el menú del avatar (Configuración / Cerrar sesión) y la píldora `'Móvil N · Estado'`, que se inserta en dos lugares distintos (`:117` modo sección con título, `:138` modo home con nombre).

`PromocionesPage` es el tab índice 2, **no tiene Scaffold propio** y usa `ScaffoldMessenger.of(context)` en tres lugares más `showModalBottomSheet`. Pide ubicación puntual (`getLastKnownPosition` → `getCurrentPosition(8s)` → Nominatim) al elegir una promo, de forma tolerante a fallo. Recibe `messageCountNotifier` y `onEstadoTap` como parámetros **requeridos**.

---

## 3. Decisiones tomadas

| Tema | Decisión |
|---|---|
| Quién es el 9998 | Comercio / punto de venta adherido |
| Regla | Constante única y estable, no una familia |
| Origen del dato | `escenarioid` a nivel raíz de `ValidarUsuario` |
| Escenario persistido | `9998` real (no se reusa `2000`) |
| Promos | Pantalla completa: ver + registrar consumo + anular (ventana de 30 min) |
| Ubicación en Promos | Fix one-shot al abrir, sin servicio continuo |
| Plataforma | Solo Android |
| Push | FCM vivo para control **y** para avisos de promos nuevas |
| Supervivencia | Foreground service `dataSync` sin GPS |
| Medianoche | Se mantiene el corte por cambio de día, igual que cualquier chofer |
| Beneficios | Quedan simulados por ahora (no entra en este alcance) |
| Gate de permisos | Se recuerda el perfil del último login en `usuarioBox` |
| Arquitectura | Flag único + shell dedicado |

### 3.1 Precisión sobre "que no se le cierre nunca"

Al mantener el corte de medianoche, el requisito se interpreta como **"la sesión no se cierra nunca dentro del mismo día"**. El comercio vuelve a loguearse al día siguiente, igual que cualquier chofer.

---

## 4. Diseño

### 4.1 Detección y persistencia

El escenario **es** el flag: no se agrega un booleano duplicado en Hive, para no tener dos verdades que puedan divergir.

La coerción pasa a ser una whitelist, aplicada en los dos lugares vivos (`login_page.dart:2422` para Hive, `:2260` para prefs nativas):

```dart
String _normalizarEscenario(dynamic raw) {
  final s = raw?.toString();
  return (s == '1000' || s == '9998') ? s! : '2000';
}
```

Whitelist y no eliminación de la coerción: así ningún usuario existente cambia de colección Firestore por accidente si el backend devolviera un valor inesperado.

Se elimina `AuthService.login()` (`auth_service.dart:39-60`), código muerto que contiene una tercera coerción inconsistente y referencia un campo `response['selectedMovil']` que el código vivo nunca usa.

Archivo nuevo `lib/services/modo_restringido.dart` — único lugar del código que conoce el número:

```dart
class ModoRestringido {
  static const String escenarioComercio = '9998';
  static bool esRestringido(String? escenario) => escenario == escenarioComercio;
  static final ValueNotifier<bool> activo = ValueNotifier<bool>(false);
  static Future<void> init() async { /* lee sessionBox['escenario'] */ }
}
```

Persistencia en tres capas:

| Capa | Clave | Para qué |
|---|---|---|
| Hive `sessionBox` | `escenario = '9998'` | Flutter; sobrevive al arranque en frío |
| Hive `usuarioBox` | `ultimoPerfilRestringido` | Gate de permisos; sobrevive al logout (misma caja que `uiHomeV2`) |
| Prefs nativas `config` | `restricted_mode` | Kotlin lo necesita **antes** de que exista Flutter |

`ModoRestringido.init()` se llama en `main.dart` antes de decidir `HomePage` vs `LoginPage`.

### 4.2 Auto-selección de móvil único

**Paso 1 — extraer.** El cuerpo del botón Confirmar (`login_page.dart:2202-2346`) se extrae a `_seleccionarMovilYContinuar(response, movilId, {matricula})`, con las ocho escrituras y las llamadas a `_proceedAfterMobileSelection` / `_onSuccessfulLoginFlow` intactas. El diálogo y la auto-selección lo llaman por igual.

**Paso 2 — unificar.** Los tres call sites duplicados (`:1508`, `:1545`, `:1619`) se reemplazan por un único `_manejarMovilesYContinuar(response)`:

| Cantidad de móviles | Comportamiento |
|---|---|
| 0 | Mensaje de error explícito al usuario (hoy el login muere en silencio) |
| 1 | Auto-selección, sin diálogo |
| N | Diálogo, igual que hoy |

**Excepción matrícula.** Si la constante `180 == 'S'` la matrícula es obligatoria y no se puede saltear. Con un solo móvil se muestra un diálogo **reducido**: móvil fijo, no editable, y solo el campo de matrícula.

**Deuda conocida, fuera de alcance:** `getConstantValue('180')` se evalúa en `:2096`, antes de que `ConstantsService.loadAndSaveConstants()` corra en `:3182`. O sea que la decisión de pedir matrícula usa el `constantBox` de la sesión anterior, y en un teléfono limpio nunca se pide. No se corrige acá.

### 4.3 Modo restringido — UI

Una sola bifurcación, **arriba del switch V2/clásico**, para que también cubra los dispositivos que quedaron en diseño clásico:

```dart
// home_page.dart, dentro de build():
//   - DESPUÉS del loader de _isVerifyingSession (:980-1003)
//   - ANTES del ValueListenableBuilder<UiPrefs.homeV2> (:1007)
if (ModoRestringido.activo.value) return const PromosShell();
```

El orden importa: si la rama se pone por encima del loader, el comercio se saltea la verificación de sesión que corre al entrar.

`PromosShell` (nuevo, `lib/pages/v2/promos_shell.dart`):

- `Scaffold` propio — **obligatorio**, porque `PromocionesPage` usa `ScaffoldMessenger.of(context)` y `showModalBottomSheet`; montada suelta revienta en runtime
- `V2Header` con el nombre del comercio, sin píldora, sin Mensajes, menú de un solo item
- `PromocionesPage` como único contenido
- Sin `BottomNavigationBar`
- `PopScope(canPop: false)` para que Atrás no cierre la app

Cambios en `V2Header` — dos parámetros nuevos, **ambos con default igual al comportamiento actual**, para que las otras cinco pantallas no se enteren:

| Parámetro | Default | Efecto |
|---|---|---|
| `mostrarEstado` | `true` | Oculta la píldora en los dos lugares donde se inserta (`:117` y `:138`) |
| `menuSoloLogout` | `false` | Deja el menú del avatar con un único item |

Para ocultar Mensajes **no se agrega flag**: ya existe el atajo `messageCountNotifier: null` (`v2_header.dart:182-183`).

`PromocionesPage`: `messageCountNotifier` y `onEstadoTap` pasan de `required` a nullable.

El cartel *"⚙️ Modo demostración: validación con servicios simulados"* **se mantiene**: mientras `BeneficiosService` esté simulado, ocultarlo sería engañar al comercio.

### 4.4 Modo restringido — GPS

Los cuatro caminos de arranque, cerrados uno por uno:

| # | Camino | Acción |
|---|---|---|
| 1 | `login_page.dart:3195` | No se llama `startLocationService`. **Sí** se siguen seteando `flutter.sessionActive=true` y la identidad nativa |
| 2 | `MainActivity.kt:937` | Return temprano si `config.restricted_mode` es true |
| 3 | `FcmPushReceiver.handleRestartTracking` | Mismo chequeo; reporta `restart_result=RESTRICTED_MODE` para dejar traza en el backend |
| 4 | `HealthCheckWorker` | `cancel()` explícito al detectar el modo |

El punto 1 obliga a **separar "setear identidad y flags" de "arrancar el tracking"**, que hoy viajan juntos en la misma llamada al MethodChannel.

El punto 4 no es opcional: el worker está programado con `KEEP` y sobrevive reinicios, así que en un teléfono que antes usó un chofer seguiría intentando revivir el FGS cada 15 minutos.

Sobre el punto 1, cuidado documentado: si **no** se setea `flutter.sessionActive=true`, `LocationHelper.isSessionActive()` devuelve `false` y se rompe todo el control remoto por FCM, incluido el logout remoto que sí queremos conservar.

Efectos colaterales a apagar en modo restringido:

- `HomePage.initState` → `_initializeLocationService()`, que dispara el intent de exención de batería
- El diálogo de batería de `main.dart:1131`
- La notificación *ongoing* "Ubicación desactivada" de `GPSStatusReceiver`, que se dispara por `PROVIDERS_CHANGED` con independencia del tracking

`PromocionesPage` conserva su fix de ubicación one-shot: es puntual, tolerante a fallo y no requiere el FGS.

### 4.5 Keep-alive

Servicio nuevo `PromoKeepAliveService`:

- `foregroundServiceType="dataSync"`, permiso `FOREGROUND_SERVICE_DATA_SYNC` en el manifest
- Canal de notificación propio, distinto del de `location_channel`
- No hace absolutamente nada: existe para que el proceso no sea *cached* y el LMK no lo mate
- `onTimeout()` → `stopSelf()` limpio, para Android 15
- Arranca al final del login restringido y en `MainActivity.onCreate` cuando `restricted_mode=true`, simétrico al camino del GPS

**Limitación aceptada:** en Android 15 los FGS de tipo `dataSync` tienen un tope de 6 horas por día. Pasado ese tope el servicio se detiene y el proceso vuelve a ser matable. El plan B es el comportamiento por defecto: la sesión sobrevive en Hive, y FCM o el propio usuario reabren la app sin re-login.

### 4.6 Permisos

`_validatePermissionsBeforeLogin()` (batería + GPS *always* + precisión) se saltea cuando `usuarioBox['ultimoPerfilRestringido'] == true` **y** el usuario tipeado coincide con `usuarioBox['lastUsername']`.

El primer login de un comercio pide todos los permisos, porque el escenario recién se conoce después de `ValidarUsuario` y el gate corre antes. Del segundo login en adelante, no.

### 4.7 Lo que explícitamente NO se toca

`SessionService` (creación, cierre y detección de conflicto usuario/móvil), el listener de sesiones y el logout forzado de `PersistentStreamManager`, `LogoutService.executeLogout()` incluido su `exit(0)`, el comando FCM `logout_user`, el corte de medianoche completo (`DateChangeReceiver`, `loginDate`, gate de `fecha`), y `registrarUltLog` / `RegistrarCierre`.

Todo sigue funcionando igual, apuntando ahora a `sessions-9998`.

---

## 5. Prerrequisitos fuera de la app

Sin estos cuatro puntos la feature se ve rota aunque el código esté bien:

1. **Reglas de Firestore para `sessions-9998`.** La colección se crea sola al escribir, pero si las reglas están escritas por nombre de colección, `saveSession` falla y el comercio no puede loguearse.
2. **Promos etiquetadas.** El filtro compara `EscenariosHabilitados` contra el escenario de la sesión (`persistent_stream_manager.dart:392-397`). Si ninguna promo tiene `"9998"` ni `"*"`, la única pantalla del comercio sale vacía.
3. **GeneXus debe aceptar `escenarioid=9998`** en `RegistrarSesion` (login) y `RegistrarCierre` (logout). Numéricamente parsea bien; la duda es si se valida contra una tabla de escenarios.
4. **`Moviles-9998/Moviles-{movil}` no va a existir.** Ver riesgos.

---

## 6. Criterios de aceptación

### Auto-selección (todos los usuarios)

- [ ] Con **un** móvil en `ListaMoviles`, el login entra directo sin mostrar el diálogo, y quedan escritos exactamente los mismos ocho destinos que escribe hoy el botón Confirmar
- [ ] Con **varios** móviles, el diálogo se comporta igual que antes
- [ ] Con **cero** móviles, el usuario ve un mensaje de error en lugar de quedarse trabado sin explicación
- [ ] Con un móvil y `constante 180 == 'S'`, se muestra el diálogo reducido de matrícula
- [ ] El comportamiento es idéntico en los tres caminos de login (`OK==0` con y sin registro de dispositivo, y `OK==9`)

### Modo restringido

- [ ] Con `escenarioid=9998`, Hive y las prefs nativas guardan `'9998'`, no `'2000'`
- [ ] Con cualquier otro escenario, se sigue guardando `'1000'` o `'2000'` exactamente como hoy
- [ ] El comercio entra a `PromosShell`: sin barra inferior, sin píldora de móvil ni estado, sin ícono de Mensajes, con el nombre del comercio en el header
- [ ] El menú del avatar tiene un solo item: *Cerrar sesión*
- [ ] `PedidosTabV2` y `MapaTabV2` **no se construyen** (verificable por la ausencia de su `Timer.periodic`)
- [ ] La notificación de rastreo de ubicación **no aparece** en ningún momento
- [ ] Cerrar y reabrir la app no arranca el FGS de GPS (camino `MainActivity.onCreate`)
- [ ] Un `restart_tracking` remoto es ignorado y reporta `RESTRICTED_MODE`
- [ ] El `HealthCheckWorker` queda cancelado
- [ ] El keep-alive `dataSync` está corriendo y su notificación no menciona ubicación
- [ ] El logout remoto por FCM sigue funcionando
- [ ] La sesión no se cierra sola durante el día
- [ ] A partir del segundo login, no se piden permisos de GPS ni de batería
- [ ] Un chofer normal en el mismo dispositivo no ve ningún cambio de comportamiento

---

## 7. Riesgos asumidos

- **`printScreen` no se activa para el comercio.** El anti-screenshot sale del documento `Moviles-{escenario}/Moviles-{movil}`, que para `9998` no va a existir. Se pierde esa protección en ese perfil.
- **Tope de 6 h del FGS `dataSync` en Android 15.** Después de ese tope el proceso vuelve a ser matable. Aceptado: la sesión sobrevive en Hive.
- **Dead-end del permiso de notificaciones.** Si no está concedido, el login no navega a `HomePage` y se queda en la pantalla de login con la sesión ya escrita en Firestore (`login_page.dart:3129-3172`). Es un bug preexistente que esta feature no introduce ni corrige.
- **`BeneficiosService` simulado.** El comercio recibe una pantalla que no opera contra el backend real. Decisión explícita de producto para esta etapa.
- **`V2Header` es compartido por seis pantallas.** Los parámetros nuevos deben tener default igual al comportamiento actual, o se rompen Mensajes, Configuración y el shell clásico.

---

## 8. Fuera de alcance

- Implementar los endpoints GeneXus reales de beneficios
- iOS
- Corregir la condición de carrera de `getConstantValue('180')`
- Corregir el dead-end del permiso de notificaciones
- Unificar los dos criterios descoordinados de cambio de día (Hive `loginDate` en local vs Hive `fecha` en UTC)
- Cualquier familia de escenarios especiales más allá de `9998`
