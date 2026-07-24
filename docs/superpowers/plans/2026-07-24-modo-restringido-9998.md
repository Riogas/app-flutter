# Modo restringido (escenario 9998) + auto-selección de móvil único — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que un usuario con `escenarioid=9998` (comercio adherido) entre directo a una pantalla de Promociones sin GPS continuo ni operativa de móviles, y que cualquier usuario con un solo móvil se saltee el diálogo de selección.

**Architecture:** Un flag único derivado del escenario, persistido en Hive + prefs nativas, más un shell de UI dedicado (`PromosShell`) al que `HomePage` deriva con un solo `if`. El camino del chofer no se toca: todo parámetro nuevo tiene default igual al comportamiento actual. Del lado Android se bloquean los cuatro caminos que arrancan el foreground service de GPS y se agrega un foreground service `dataSync` que no hace nada más que mantener el proceso vivo.

**Tech Stack:** Flutter 3.6+ / Dart, Hive, SharedPreferences, Kotlin (Android nativo), WorkManager, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-24-modo-restringido-9998-design.md`

## Global Constraints

- Dart SDK `>=3.6.0 <4.0.0`. **No agregar dependencias nuevas a `pubspec.yaml`** — el proyecto solo tiene `flutter_test`, `hive_generator` y `build_runner` como dev deps. No hay mockito ni mocktail: los tests son unitarios puros o widget tests con `flutter_test`.
- **El nombre del package es `MoveIT`** (`pubspec.yaml:1`), no `appmovil`. Los imports en los tests son `package:MoveIT/...`. Verificado en los stack traces de `flutter test`.
- **La suite de tests arranca en rojo y así se queda.** `test/services/persistent_stream_manager_test.dart` tiene 13 tests que fallan todos con `[core/no-app] No Firebase App '[DEFAULT]' has been created`: `PersistentStreamManager` construye `FirebaseService`, que toca `FirebaseFirestore.instance` en su constructor. Es una falla **preexistente**, ajena a esta feature, y arreglarla está fuera de alcance. Por eso **ningún paso de este plan dice "correr `flutter test` y esperar todo verde"**: cada paso corre los archivos de test concretos que le corresponden.
- **Camino cerrado, no reintentar:** mockear `firebase_core` con `setMockMethodCallHandler` sobre el canal `plugins.flutter.io/firebase_core` **no funciona**. `firebase_core` migró a Pigeon; el intento falla con `PlatformException(channel-error, Unable to establish connection on channel)` desde `FirebaseCoreHostApi.initializeCore`. Probado y descartado. Consecuencia práctica: **cualquier widget que construya `PersistentStreamManager` no se puede pumpear en un test.** En `V2Header` eso es exactamente `_buildEstadoPill`, así que solo se pueden pumpear las variantes con `mostrarEstado: false` (ver Task 4).
- **Solo Android.** No tocar `ios/`, `macos/`, `linux/`, `windows/`, `web/`.
- **Todo parámetro o flag nuevo debe tener default igual al comportamiento actual.** `V2Header` está compartido por seis pantallas; un default distinto rompe Mensajes, Configuración, Pedidos, Mapa y el shell clásico.
- El valor mágico `9998` se escribe **una sola vez en todo el repo**, en `ModoRestringido.escenarioComercio`. Ningún otro archivo compara contra el literal.
- `flutter analyze` no debe sumar errores nuevos.
- Los `.md` sueltos en la raíz del repo describen mayormente la arquitectura **anterior** al refactor de GPS y **no son fuente de verdad**. El único alineado es `REFACTOR_GPS_PERSISTENTE.md`.
- Un commit por tarea, con el prefijo indicado en cada `git commit`.
- El código Kotlin **no tiene infraestructura de tests** en este proyecto. Las tareas de Kotlin se verifican compilando (`flutter build apk --debug`) y con pasos manuales en dispositivo, explicitados en cada tarea.

---

## File Structure

**Archivos nuevos**

| Archivo | Responsabilidad |
|---|---|
| `lib/services/modo_restringido.dart` | Único lugar que conoce el valor `9998`. Normaliza el escenario, expone el predicado y el notifier, persiste en las tres capas |
| `lib/services/movil_selection.dart` | Decisión pura: dada la lista de móviles y si se pide matrícula, qué hay que hacer |
| `lib/pages/v2/promos_shell.dart` | Shell del modo restringido: `PopScope` + `Scaffold` + `PromocionesPage` |
| `android/.../riogas/appmovil/tracking/PromoKeepAliveService.kt` | Foreground service `dataSync` sin GPS, solo para mantener vivo el proceso |
| `test/services/modo_restringido_test.dart` | Tests de normalización y predicado |
| `test/services/movil_selection_test.dart` | Tests de las cuatro decisiones |
| `test/pages/v2/v2_header_test.dart` | Regresión del header para choferes + variantes restringidas |
| `test/pages/v2/promos_shell_test.dart` | Estructura del shell restringido |

**Archivos modificados**

| Archivo | Cambio |
|---|---|
| `lib/pages/login_page.dart` | Whitelist del escenario, extracción de `_seleccionarMovilYContinuar`, unificación de los 3 call sites, no arrancar GPS en modo restringido, persistir el perfil |
| `lib/services/auth_service.dart` | Borrar `login()` (código muerto con coerción inconsistente) |
| `lib/main.dart` | `ModoRestringido.init()` y saltear el diálogo de batería |
| `lib/pages/home_page.dart` | Rama a `PromosShell` y no inicializar el `LocationService` legado |
| `lib/pages/v2/v2_header.dart` | Flags `mostrarEstado` y `menuSoloLogout` + keys para test |
| `lib/pages/v2/promociones_page.dart` | Params nullable + flag `modoRestringido` |
| `android/.../example/moveit/MainActivity.kt` | Canal `saveRestrictedMode`, guardas en `restartLocationServiceFromForeground`, arranque del keep-alive |
| `android/.../riogas/appmovil/ServiceStatusFlags.kt` | Flag `restricted_mode` |
| `android/.../riogas/appmovil/FcmPushReceiver.kt` | Guarda en `handleRestartTracking` |
| `android/.../example/moveit/receivers/GPSStatusReceiver.kt` | No notificar en modo restringido |
| `android/app/src/main/AndroidManifest.xml` | Permiso `FOREGROUND_SERVICE_DATA_SYNC` + declaración del servicio nuevo |

---

## Task 0: Desbloquear la compilación de los tests — ✅ YA HECHO (commit `f7e91ae`)

**Files:**
- Modify: `lib/main.dart:38-39`

`lib/main.dart` importaba `'../services/location_service.dart'` y `'../services/native_log_sync_service.dart'`. Los archivos están en `lib/services/`, así que el `../` los saca del package (las líneas 41-42 del mismo archivo ya usaban la forma correcta). El analyzer lo toleraba —solo lo reportaba como *unused import*— pero el frontend de `flutter test` fallaba duro con `Error when reading 'services/location_service.dart'`, y con eso **ningún test del proyecto podía compilar**.

Se corrigió a `'services/...'`. Introducido en los commits `0e6b841` y `268ebb2`.

- [x] Corregido y commiteado como `f7e91ae`, antes de empezar el resto del plan

---

## Task 1: `ModoRestringido` — detección y normalización

**Files:**
- Create: `lib/services/modo_restringido.dart`
- Test: `test/services/modo_restringido_test.dart`

**Interfaces:**
- Consumes: nada (primera tarea)
- Produces:
  - `ModoRestringido.escenarioComercio` → `String` (`'9998'`)
  - `ModoRestringido.normalizarEscenario(dynamic raw)` → `String`
  - `ModoRestringido.esRestringido(String? escenario)` → `bool`
  - `ModoRestringido.activo` → `ValueNotifier<bool>`
  - `ModoRestringido.aplicar(String? escenario)` → `void` (setea `activo`)
  - `ModoRestringido.init()` → `Future<void>` (lee `sessionBox['escenario']`)

- [ ] **Step 1: Escribir el test que falla**

Crear `test/services/modo_restringido_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:MoveIT/services/modo_restringido.dart';

void main() {
  group('normalizarEscenario', () {
    test('deja pasar 1000 sin tocar', () {
      expect(ModoRestringido.normalizarEscenario('1000'), '1000');
    });

    test('deja pasar 9998 sin tocar', () {
      expect(ModoRestringido.normalizarEscenario('9998'), '9998');
    });

    test('aplasta cualquier otro valor a 2000', () {
      expect(ModoRestringido.normalizarEscenario('2000'), '2000');
      expect(ModoRestringido.normalizarEscenario('3000'), '2000');
      expect(ModoRestringido.normalizarEscenario('cualquiera'), '2000');
    });

    test('aplasta null y vacio a 2000', () {
      expect(ModoRestringido.normalizarEscenario(null), '2000');
      expect(ModoRestringido.normalizarEscenario(''), '2000');
    });

    test('acepta el escenario como numero, no solo como String', () {
      expect(ModoRestringido.normalizarEscenario(1000), '1000');
      expect(ModoRestringido.normalizarEscenario(9998), '9998');
      expect(ModoRestringido.normalizarEscenario(2000), '2000');
    });
  });

  group('esRestringido', () {
    test('true solo para 9998', () {
      expect(ModoRestringido.esRestringido('9998'), isTrue);
    });

    test('false para los escenarios normales', () {
      expect(ModoRestringido.esRestringido('1000'), isFalse);
      expect(ModoRestringido.esRestringido('2000'), isFalse);
    });

    test('false para null y vacio', () {
      expect(ModoRestringido.esRestringido(null), isFalse);
      expect(ModoRestringido.esRestringido(''), isFalse);
    });
  });

  group('aplicar', () {
    setUp(() => ModoRestringido.activo.value = false);

    test('enciende el notifier con 9998', () {
      ModoRestringido.aplicar('9998');
      expect(ModoRestringido.activo.value, isTrue);
    });

    test('apaga el notifier con un escenario normal', () {
      ModoRestringido.activo.value = true;
      ModoRestringido.aplicar('2000');
      expect(ModoRestringido.activo.value, isFalse);
    });
  });
}
```

> **Nota sobre el import:** el `name:` de `pubspec.yaml` es `MoveIT` (con esas mayúsculas), así que el import por package es `package:MoveIT/...`. El test viejo del repo usa path relativo, pero la forma por package funciona y es la que se usa acá. Verificado en los stack traces de `flutter test`.

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `flutter test test/services/modo_restringido_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:MoveIT/services/modo_restringido.dart'`

- [ ] **Step 3: Escribir la implementación mínima**

Crear `lib/services/modo_restringido.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// 🏪 Modo restringido: perfil "comercio adherido" (escenario 9998).
///
/// Este es el ÚNICO lugar del repositorio que conoce el número 9998.
/// Nadie más debe compararlo contra un literal.
///
/// El escenario ES el flag: no se guarda un booleano duplicado en Hive,
/// para no tener dos verdades que puedan divergir.
class ModoRestringido {
  ModoRestringido._();

  /// Escenario del comercio adherido: solo ve Promociones, sin GPS continuo.
  static const String escenarioComercio = '9998';

  /// Escenario histórico que muestra matrícula en el combo de móviles.
  static const String escenarioMatricula = '1000';

  /// Escenario por defecto para todo lo demás.
  static const String escenarioPorDefecto = '2000';

  /// Notifier para que la UI reaccione sin releer Hive.
  static final ValueNotifier<bool> activo = ValueNotifier<bool>(false);

  /// Whitelist del escenario que devuelve el backend.
  ///
  /// Históricamente la app aplastaba TODO lo distinto de "1000" a "2000".
  /// Se mantiene ese comportamiento salvo para 9998, que ahora pasa entero.
  /// Es una whitelist a propósito: así ningún usuario existente cambia de
  /// colección Firestore por accidente si el backend devuelve algo inesperado.
  static String normalizarEscenario(dynamic raw) {
    final s = raw?.toString();
    if (s == escenarioMatricula) return escenarioMatricula;
    if (s == escenarioComercio) return escenarioComercio;
    return escenarioPorDefecto;
  }

  static bool esRestringido(String? escenario) =>
      escenario == escenarioComercio;

  /// Setea [activo] a partir de un escenario ya normalizado.
  static void aplicar(String? escenario) {
    activo.value = esRestringido(escenario);
    print('🏪 [MODO_RESTRINGIDO] escenario=$escenario → activo=${activo.value}');
  }

  /// Lee el escenario persistido y setea [activo]. Se llama en el arranque
  /// en frío, donde no hay respuesta de login de la cual derivarlo.
  static Future<void> init() async {
    try {
      final box = Hive.isBoxOpen('sessionBox')
          ? Hive.box('sessionBox')
          : await Hive.openBox('sessionBox');
      aplicar(box.get('escenario')?.toString());
    } catch (e) {
      print('⚠️ [MODO_RESTRINGIDO] No se pudo leer el escenario: $e');
      activo.value = false;
    }
  }
}
```

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `flutter test test/services/modo_restringido_test.dart`
Expected: PASS — 10 tests

- [ ] **Step 5: Commit**

```bash
git add lib/services/modo_restringido.dart test/services/modo_restringido_test.dart
git commit -m "feat(modo-restringido): deteccion y normalizacion del escenario 9998"
```

---

## Task 2: `MovilSelection` — decisión pura de qué hacer con la lista de móviles

**Files:**
- Create: `lib/services/movil_selection.dart`
- Test: `test/services/movil_selection_test.dart`

**Interfaces:**
- Consumes: nada
- Produces:
  - `enum AccionMovil { sinMoviles, autoSeleccionar, pedirMatricula, mostrarDialogo }`
  - `MovilSelection.decidir({required List<Map<String, String>> moviles, required bool pideMatricula})` → `AccionMovil`

**Por qué existe esta clase:** `login_page.dart` tiene 3514 líneas y está acoplado a Hive, Firebase y MethodChannels; no es testeable en unidad. Sacar la *decisión* a una función pura permite cubrir las cuatro ramas con tests reales, y deja en el widget solo los efectos.

- [ ] **Step 1: Escribir el test que falla**

Crear `test/services/movil_selection_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:MoveIT/services/movil_selection.dart';

void main() {
  const unMovil = [
    {'id': '101', 'displayValue': 'Movil 101'}
  ];
  const dosMoviles = [
    {'id': '101', 'displayValue': 'Movil 101'},
    {'id': '102', 'displayValue': 'Movil 102'},
  ];

  group('MovilSelection.decidir', () {
    test('lista vacia → sinMoviles', () {
      expect(
        MovilSelection.decidir(moviles: const [], pideMatricula: false),
        AccionMovil.sinMoviles,
      );
    });

    test('lista vacia con matricula obligatoria tambien → sinMoviles', () {
      expect(
        MovilSelection.decidir(moviles: const [], pideMatricula: true),
        AccionMovil.sinMoviles,
      );
    });

    test('un movil sin matricula → autoSeleccionar', () {
      expect(
        MovilSelection.decidir(moviles: unMovil, pideMatricula: false),
        AccionMovil.autoSeleccionar,
      );
    });

    test('un movil con matricula obligatoria → pedirMatricula', () {
      expect(
        MovilSelection.decidir(moviles: unMovil, pideMatricula: true),
        AccionMovil.pedirMatricula,
      );
    });

    test('varios moviles → mostrarDialogo', () {
      expect(
        MovilSelection.decidir(moviles: dosMoviles, pideMatricula: false),
        AccionMovil.mostrarDialogo,
      );
    });

    test('varios moviles con matricula → mostrarDialogo (el dialogo ya la pide)', () {
      expect(
        MovilSelection.decidir(moviles: dosMoviles, pideMatricula: true),
        AccionMovil.mostrarDialogo,
      );
    });
  });

  group('MovilSelection.idUnico', () {
    test('devuelve el id cuando hay exactamente uno', () {
      expect(MovilSelection.idUnico(unMovil), '101');
    });

    test('devuelve null cuando hay cero o mas de uno', () {
      expect(MovilSelection.idUnico(const []), isNull);
      expect(MovilSelection.idUnico(dosMoviles), isNull);
    });
  });
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `flutter test test/services/movil_selection_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:MoveIT/services/movil_selection.dart'`

- [ ] **Step 3: Escribir la implementación mínima**

Crear `lib/services/movil_selection.dart`:

```dart
/// Qué hacer con la lista de móviles que devuelve ValidarUsuario.
enum AccionMovil {
  /// El backend no devolvió ningún móvil: hay que avisarle al usuario.
  /// Antes de esta feature el login moría en silencio.
  sinMoviles,

  /// Un solo móvil y no hace falta matrícula: se entra directo.
  autoSeleccionar,

  /// Un solo móvil pero la matrícula es obligatoria (constante 180 == 'S'):
  /// se muestra un diálogo reducido, con el móvil fijo.
  pedirMatricula,

  /// Varios móviles: diálogo de selección completo, como siempre.
  mostrarDialogo,
}

/// Decisión pura sobre la lista de móviles. Sin Hive, sin red, sin contexto.
class MovilSelection {
  MovilSelection._();

  static AccionMovil decidir({
    required List<Map<String, String>> moviles,
    required bool pideMatricula,
  }) {
    if (moviles.isEmpty) return AccionMovil.sinMoviles;
    if (moviles.length > 1) return AccionMovil.mostrarDialogo;
    return pideMatricula ? AccionMovil.pedirMatricula : AccionMovil.autoSeleccionar;
  }

  /// El id del móvil cuando hay exactamente uno; null en cualquier otro caso.
  static String? idUnico(List<Map<String, String>> moviles) =>
      moviles.length == 1 ? moviles.first['id'] : null;
}
```

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `flutter test test/services/movil_selection_test.dart`
Expected: PASS — 8 tests

- [ ] **Step 5: Commit**

```bash
git add lib/services/movil_selection.dart test/services/movil_selection_test.dart
git commit -m "feat(login): decision pura de seleccion de movil (0/1/N + matricula)"
```

---

## Task 3: Whitelist del escenario en el login + borrar código muerto + init en arranque

**Files:**
- Modify: `lib/pages/login_page.dart:2260-2265` (prefs nativas) y `lib/pages/login_page.dart:2422-2425` (Hive)
- Modify: `lib/services/auth_service.dart:39-60` (borrar `login()`)
- Modify: `lib/main.dart` (llamar `ModoRestringido.init()`)

**Interfaces:**
- Consumes: `ModoRestringido.normalizarEscenario`, `ModoRestringido.aplicar`, `ModoRestringido.init` (Task 1)
- Produces: `sessionBox['escenario']` y `config.last_escenario` pueden ahora valer `'9998'`; `ModoRestringido.activo` está seteado antes de que se construya `HomePage`

- [ ] **Step 1: Reemplazar la coerción de las prefs nativas**

En `lib/pages/login_page.dart`, dentro del `onPressed` del botón Confirmar, reemplazar:

```dart
                          String escenarioValue =
                              response['escenarioid'] == "1000"
                                  ? "1000"
                                  : "2000";
```

por:

```dart
                          String escenarioValue = ModoRestringido
                              .normalizarEscenario(response['escenarioid']);
```

- [ ] **Step 2: Reemplazar la coerción de Hive**

En `lib/pages/login_page.dart`, dentro de `_proceedAfterMobileSelection`, reemplazar:

```dart
    await box.put(
      'escenario',
      response['escenarioid'] == "1000" ? "1000" : "2000",
    );
```

por:

```dart
    final escenarioNormalizado =
        ModoRestringido.normalizarEscenario(response['escenarioid']);
    await box.put('escenario', escenarioNormalizado);
    ModoRestringido.aplicar(escenarioNormalizado);
```

Agregar el import al principio de `login_page.dart` (junto a los otros de `services/`):

```dart
import '../services/modo_restringido.dart';
```

- [ ] **Step 3: Borrar el código muerto de `AuthService`**

En `lib/services/auth_service.dart`, borrar el método completo `static Future<bool> login(...)` (líneas 39-60). Contiene una tercera coerción del escenario que compara contra el `int` 1000 en vez del `String`, y lee `response['selectedMovil']`, un campo que el código vivo nunca usa. Nadie lo llama.

Si al borrarlo queda sin usar el import de `riogas_service.dart`, **dejarlo**: `validateDevice` y `registerDevice` siguen usando `RioGasService`.

- [ ] **Step 4: Verificar que no queda ninguna coerción vieja**

Run: `git grep -n '"1000" ? "1000" : "2000"' -- lib/`
Expected: sin resultados

Run: `git grep -n "== 1000 ? 1000 : 2000" -- lib/`
Expected: sin resultados

Run: `git grep -n "AuthService.login" -- lib/ test/`
Expected: sin resultados

- [ ] **Step 5: Llamar `ModoRestringido.init()` en el arranque en frío**

En `lib/main.dart`, justo **después** del bloque que setea `isLoggedIn` (el `try/catch` alrededor de `AuthService.checkIsLoggedIn()`), agregar:

```dart
    // 🏪 Derivar el modo restringido del escenario persistido. Al reabrir la
    // app no se vuelve a llamar a ValidarUsuario, así que este es el único
    // lugar donde se puede saber que el usuario es un comercio 9998.
    try {
      await ModoRestringido.init();
    } catch (e) {
      print('⚠️ Error inicializando ModoRestringido: $e');
    }
```

Agregar el import correspondiente en `main.dart`:

```dart
import 'services/modo_restringido.dart';
```

- [ ] **Step 6: Verificar que compila y que los tests siguen verdes**

Run: `flutter analyze lib/pages/login_page.dart lib/services/auth_service.dart lib/main.dart lib/services/modo_restringido.dart`
Expected: sin errores nuevos (puede haber warnings preexistentes)

Run: `flutter test test/services/modo_restringido_test.dart test/services/movil_selection_test.dart`
Expected: PASS — 18 tests

> No correr `flutter test` a secas: `test/services/persistent_stream_manager_test.dart` está rojo desde antes de esta feature por falta de Firebase (ver Global Constraints).

- [ ] **Step 7: Commit**

```bash
git add lib/pages/login_page.dart lib/services/auth_service.dart lib/main.dart
git commit -m "feat(login): whitelist del escenario (1000/9998/2000) y baja de AuthService.login muerto"
```

---

## Task 4: `V2Header` — flags `mostrarEstado` y `menuSoloLogout`

**Files:**
- Modify: `lib/pages/v2/v2_header.dart`
- Test: `test/pages/v2/v2_header_test.dart`

**Interfaces:**
- Consumes: nada de tareas anteriores
- Produces: `V2Header({..., bool mostrarEstado = true, bool menuSoloLogout = false})`, más las keys `v2-estado-pill`, `v2-avatar-menu`, `v2-mensajes-icon`

**Cuidado:** `V2Header` está instanciado en seis lugares (`pedidos_tab_v2.dart:364`, `mapa_tab_v2.dart:315`, `promociones_page.dart:425`, `home_page.dart:1028`, `message_page.dart:468`, `settings_page.dart:1126`). Los defaults tienen que reproducir exactamente lo de hoy.

- [ ] **Step 1: Escribir el test que falla**

Crear `test/pages/v2/v2_header_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:MoveIT/pages/v2/v2_header.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  // ⚠️ LÍMITE DEL ENTORNO DE TEST — leer antes de agregar casos.
  //
  // Solo se pueden pumpear variantes con `mostrarEstado: false`. Con la
  // píldora visible, V2Header construye PersistentStreamManager →
  // FirebaseService → FirebaseFirestore.instance, y en un test eso explota
  // con `[core/no-app] No Firebase App '[DEFAULT]' has been created`.
  // Mockear firebase_core NO es viable: migró a Pigeon y el mock por
  // MethodChannel falla con `channel-error` (probado y descartado).
  //
  // El camino del chofer queda cubierto por el test de defaults de abajo,
  // que NO pumpea nada, más la verificación manual en dispositivo (Task 13).

  group('V2Header — defaults (regresion del camino del chofer)', () {
    test('los flags nuevos preservan el comportamiento actual', () {
      const header = V2Header();

      expect(header.mostrarEstado, isTrue,
          reason: 'la pildora de movil/estado debe seguir apareciendo');
      expect(header.menuSoloLogout, isFalse,
          reason: 'el menu del avatar debe seguir teniendo Configuracion');
      expect(header.showActions, isTrue);
      expect(header.messageCountNotifier, isNull);
      expect(header.onEstadoTap, isNull);
      expect(header.titulo, isNull);
      expect(header.height, 182);
      expect(header.bottomSpace, 82);
    });
  });

  group('V2Header — modo restringido', () {
    testWidgets('mostrarEstado:false oculta la pildora en modo home',
        (tester) async {
      await tester.pumpWidget(_wrap(const V2Header(mostrarEstado: false)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('v2-estado-pill')), findsNothing);
    });

    testWidgets('mostrarEstado:false oculta la pildora tambien en modo seccion',
        (tester) async {
      await tester.pumpWidget(
          _wrap(const V2Header(titulo: 'Promos', mostrarEstado: false)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('v2-estado-pill')), findsNothing);
      expect(find.text('Promos'), findsOneWidget);
    });

    testWidgets('sin notifier no se dibuja el icono de mensajes',
        (tester) async {
      await tester.pumpWidget(_wrap(const V2Header(mostrarEstado: false)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('v2-mensajes-icon')), findsNothing);
      // El avatar SÍ tiene que estar: es el único acceso a Cerrar sesión.
      expect(find.byKey(const Key('v2-avatar-menu')), findsOneWidget);
    });

    testWidgets('con notifier sí se dibuja el icono de mensajes',
        (tester) async {
      await tester.pumpWidget(_wrap(V2Header(
        mostrarEstado: false,
        messageCountNotifier: ValueNotifier<int>(0),
      )));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('v2-mensajes-icon')), findsOneWidget);
    });

    testWidgets('showActions:false oculta mensajes y avatar', (tester) async {
      await tester.pumpWidget(_wrap(V2Header(
        mostrarEstado: false,
        showActions: false,
        messageCountNotifier: ValueNotifier<int>(3),
      )));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('v2-mensajes-icon')), findsNothing);
      expect(find.byKey(const Key('v2-avatar-menu')), findsNothing);
    });

    testWidgets('menu por defecto tiene Configuracion y Cerrar sesion',
        (tester) async {
      await tester.pumpWidget(_wrap(const V2Header(mostrarEstado: false)));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('v2-avatar-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Configuración'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
    });

    testWidgets('menuSoloLogout:true deja solo Cerrar sesion', (tester) async {
      await tester.pumpWidget(_wrap(
          const V2Header(mostrarEstado: false, menuSoloLogout: true)));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('v2-avatar-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Configuración'), findsNothing);
      expect(find.text('Cerrar sesión'), findsOneWidget);
    });
  });
}
```

> **No usar `pumpAndSettle()` en estos tests.** `V2Header` usa `CachedNetworkImage`, que en el entorno de test deja timers de reintento vivos y haría que `pumpAndSettle` se cuelgue hasta el timeout. Los `pump(Duration(...))` explícitos alcanzan: la animación del `PopupMenuButton` dura 300 ms.

> **Contingencia no verificada:** los pumps de este archivo no se pudieron probar antes de escribir el plan, porque la implementación de `mostrarEstado` todavía no existía y sin ella todo pump toca Firebase. Si en el Step 7 algún test falla por `CachedNetworkImage` (fondo remoto del header) o por `Image.asset('assets/logo_delivery.png')`, la causa es la carga de imágenes, no la lógica: envolver el `pumpWidget` en `tester.runAsync(() async { ... })` **no** es la solución. La solución es reemplazar los `expect` sobre keys por `expect(tester.takeException(), isNull)` más la aserción de key correspondiente, y dejar registrado el desvío en el commit.

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `flutter test test/pages/v2/v2_header_test.dart`
Expected: FAIL — `No named parameter with the name 'mostrarEstado'` (error de compilación; ningún test llega a correr)

- [ ] **Step 3: Agregar los parámetros nuevos**

En `lib/pages/v2/v2_header.dart`, agregar dos campos después de `final bool showActions;`:

```dart
  /// Si false, oculta la píldora "Móvil N · Estado" (y con ella el acceso a
  /// cambiar el estado del móvil). Usado por el modo restringido, donde el
  /// comercio no tiene operativa de móvil.
  final bool mostrarEstado;

  /// Si true, el menú del avatar queda con un único item: Cerrar sesión.
  final bool menuSoloLogout;
```

y sumarlos al constructor, **con los defaults que reproducen el comportamiento actual**:

```dart
  const V2Header({
    super.key,
    this.messageCountNotifier,
    this.onEstadoTap,
    this.problemaTecnico = false,
    this.titulo,
    this.subtitulo,
    this.height = 182,
    this.bottomSpace = 82,
    this.onBack,
    this.showActions = true,
    this.mostrarEstado = true,
    this.menuSoloLogout = false,
  });
```

- [ ] **Step 4: Condicionar la píldora en los DOS lugares donde se inserta**

En el `build()`, reemplazar el bloque de modo sección:

```dart
                if (titulo != null) ...[
                  // Modo sección: título corto + píldora a la derecha
                  Row(
                    children: [
                      Expanded(child: _buildTitulo()),
                      const SizedBox(width: 10),
                      _buildEstadoPill(context),
                    ],
                  ),
```

por:

```dart
                if (titulo != null) ...[
                  // Modo sección: título corto + píldora a la derecha
                  Row(
                    children: [
                      Expanded(child: _buildTitulo()),
                      if (mostrarEstado) ...[
                        const SizedBox(width: 10),
                        _buildEstadoPill(context),
                      ],
                    ],
                  ),
```

y el bloque de modo home:

```dart
                ] else
                  // Modo home: nombre + píldora en la misma línea
                  Row(
                    children: [
                      Expanded(child: _buildNombre()),
                      const SizedBox(width: 10),
                      _buildEstadoPill(context),
                    ],
                  ),
```

por:

```dart
                ] else
                  // Modo home: nombre + píldora en la misma línea
                  Row(
                    children: [
                      Expanded(child: _buildNombre()),
                      if (mostrarEstado) ...[
                        const SizedBox(width: 10),
                        _buildEstadoPill(context),
                      ],
                    ],
                  ),
```

- [ ] **Step 5: Condicionar el menú del avatar**

En `_buildAvatarMenu`, reemplazar el `itemBuilder`:

```dart
      itemBuilder: (context) => [
        _menuItem('config', Icons.settings_outlined, 'Configuración'),
        const PopupMenuDivider(),
        _menuItem('logout', Icons.logout, 'Cerrar sesión',
            color: V2Colors.rojo),
      ],
```

por:

```dart
      itemBuilder: (context) => [
        if (!menuSoloLogout) ...[
          _menuItem('config', Icons.settings_outlined, 'Configuración'),
          const PopupMenuDivider(),
        ],
        _menuItem('logout', Icons.logout, 'Cerrar sesión',
            color: V2Colors.rojo),
      ],
```

- [ ] **Step 6: Agregar las tres keys**

En `_buildAvatarMenu`, agregar la key al `PopupMenuButton`:

```dart
    return PopupMenuButton<String>(
      key: const Key('v2-avatar-menu'),
      tooltip: 'Menú del chofer',
```

En `_buildMensajesIcon`, agregar la key al `IconButton`:

```dart
        return IconButton(
          key: const Key('v2-mensajes-icon'),
          tooltip: 'Mensajes de despacho',
```

En `_buildEstadoPill`, agregar la key al `GestureDetector`:

```dart
            return GestureDetector(
              key: const Key('v2-estado-pill'),
              onTap:
                  onEstadoTap == null ? null : () => onEstadoTap!(context),
```

- [ ] **Step 7: Correr el test y verificar que pasa**

Run: `flutter test test/pages/v2/v2_header_test.dart`
Expected: PASS — 8 tests (1 unitario de defaults + 7 de widget)

- [ ] **Step 8: Verificar que los seis call sites siguen compilando**

Run: `flutter analyze lib/pages/v2/ lib/pages/home_page.dart lib/pages/message_page.dart lib/pages/settings_page.dart`
Expected: sin errores nuevos

- [ ] **Step 9: Commit**

```bash
git add lib/pages/v2/v2_header.dart test/pages/v2/v2_header_test.dart
git commit -m "feat(v2-header): flags mostrarEstado y menuSoloLogout con defaults intactos"
```

---

## Task 5: `PromocionesPage` — params opcionales y modo restringido

**Files:**
- Modify: `lib/pages/v2/promociones_page.dart:27-35` (constructor) y `:425-432` (call site de `V2Header`) y `:456` (espacio inferior)

**Interfaces:**
- Consumes: `V2Header.mostrarEstado`, `V2Header.menuSoloLogout` (Task 4)
- Produces: `PromocionesPage({Key? key, ValueNotifier<int>? messageCountNotifier, Future<void> Function(BuildContext)? onEstadoTap, bool modoRestringido = false})`

- [ ] **Step 1: Hacer los parámetros nullable y agregar el flag**

Reemplazar:

```dart
class PromocionesPage extends StatefulWidget {
  final ValueNotifier<int> messageCountNotifier;
  final Future<void> Function(BuildContext context) onEstadoTap;

  const PromocionesPage({
    super.key,
    required this.messageCountNotifier,
    required this.onEstadoTap,
  });
```

por:

```dart
class PromocionesPage extends StatefulWidget {
  /// Null cuando la página se monta fuera del shell de chofer (modo
  /// restringido): sin contador de mensajes no se dibuja el icono.
  final ValueNotifier<int>? messageCountNotifier;

  /// Null en modo restringido: el comercio no cambia el estado del móvil.
  final Future<void> Function(BuildContext context)? onEstadoTap;

  /// 🏪 Perfil comercio (escenario 9998): header con el nombre del comercio,
  /// sin píldora de móvil, sin mensajes y con el menú del avatar reducido.
  final bool modoRestringido;

  const PromocionesPage({
    super.key,
    this.messageCountNotifier,
    this.onEstadoTap,
    this.modoRestringido = false,
  });
```

- [ ] **Step 2: Adaptar el `V2Header` que dibuja la página**

En `build()`, reemplazar:

```dart
                V2Header(
                  messageCountNotifier: widget.messageCountNotifier,
                  onEstadoTap: widget.onEstadoTap,
                  titulo: 'Promos',
                  subtitulo: 'Validá beneficios del cliente antes de consumirlos',
                  height: 168,
                  bottomSpace: 40,
                ),
```

por:

```dart
                V2Header(
                  messageCountNotifier: widget.messageCountNotifier,
                  onEstadoTap: widget.onEstadoTap,
                  // 🏪 Comercio: header con su nombre (modo home) en vez del
                  // título de sección, sin píldora y con menú reducido.
                  titulo: widget.modoRestringido ? null : 'Promos',
                  subtitulo: widget.modoRestringido
                      ? null
                      : 'Validá beneficios del cliente antes de consumirlos',
                  mostrarEstado: !widget.modoRestringido,
                  menuSoloLogout: widget.modoRestringido,
                  height: 168,
                  bottomSpace: 40,
                ),
```

- [ ] **Step 3: Ajustar el espacio inferior reservado para la barra de navegación**

En modo restringido no hay `BottomNavigationBar`, así que los 70 px de guarda sobran. Reemplazar:

```dart
                        const SizedBox(height: 70),
```

por:

```dart
                        // Guarda para la barra inferior; en modo restringido
                        // no hay barra, así que alcanza con un margen chico.
                        SizedBox(height: widget.modoRestringido ? 16 : 70),
```

- [ ] **Step 4: Verificar que el call site existente sigue compilando**

`home_v2_scaffold.dart:62-65` sigue pasando ambos parámetros por nombre; al ser ahora opcionales, compila igual y su comportamiento no cambia.

Run: `flutter analyze lib/pages/v2/promociones_page.dart lib/pages/v2/home_v2_scaffold.dart`
Expected: sin errores nuevos

Run: `flutter test test/pages/v2/v2_header_test.dart`
Expected: PASS — 8 tests (el header no cambió, esto confirma que no hubo regresión)

- [ ] **Step 5: Commit**

```bash
git add lib/pages/v2/promociones_page.dart
git commit -m "feat(promos): parametros opcionales y variante de header para modo restringido"
```

---

## Task 6: `PromosShell` + rama en `HomePage`

**Files:**
- Create: `lib/pages/v2/promos_shell.dart`
- Modify: `lib/pages/home_page.dart:1005-1007`
- Test: `test/pages/v2/promos_shell_test.dart`

**Interfaces:**
- Consumes: `PromocionesPage.modoRestringido` (Task 5), `ModoRestringido.activo` (Task 1)
- Produces: `PromosShell({Key? key, Widget? child})`

- [ ] **Step 1: Escribir el test que falla**

Crear `test/pages/v2/promos_shell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:MoveIT/pages/v2/promos_shell.dart';

void main() {
  group('PromosShell', () {
    testWidgets('provee un Scaffold propio', (tester) async {
      // PromocionesPage necesita un Scaffold ancestro porque usa
      // ScaffoldMessenger.of(context) y showModalBottomSheet.
      await tester.pumpWidget(const MaterialApp(
        home: PromosShell(child: Text('contenido')),
      ));

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('contenido'), findsOneWidget);
    });

    testWidgets('no tiene barra de navegacion inferior', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: PromosShell(child: Text('contenido')),
      ));

      expect(find.byType(BottomNavigationBar), findsNothing);
    });

    testWidgets('bloquea el boton Atras para que no cierre la app',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: PromosShell(child: Text('contenido')),
      ));

      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });
  });
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `flutter test test/pages/v2/promos_shell_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:MoveIT/pages/v2/promos_shell.dart'`

> El test pasa un `child` explícito a propósito: así el shell no construye `PromocionesPage`, que tocaría Firestore y Hive. Ver el límite documentado en Global Constraints.

- [ ] **Step 3: Escribir la implementación mínima**

Crear `lib/pages/v2/promos_shell.dart`:

```dart
import 'package:flutter/material.dart';

import 'promociones_page.dart';
import 'v2_theme.dart';

/// 🏪 Shell del modo restringido (comercio adherido, escenario 9998).
///
/// Es la raíz completa de la app para ese perfil: una sola pantalla, sin
/// barra inferior, sin tabs de Pedidos ni Mapa. Que esos tabs NO se
/// construyan es parte del requisito: viven en un IndexedStack que los
/// instancia siempre, y PedidosTabV2 arranca un Timer.periodic de 30 s que
/// consulta Geolocator — justo lo que este modo no debe hacer.
///
/// El [Scaffold] no es opcional: PromocionesPage usa ScaffoldMessenger.of()
/// y showModalBottomSheet, que fallan en runtime sin un Scaffold ancestro.
class PromosShell extends StatelessWidget {
  /// Contenido de la pantalla. Por defecto, la página de Promociones en
  /// modo restringido.
  final Widget? child;

  const PromosShell({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // El comercio no tiene a dónde volver: Atrás cerraría la app.
      canPop: false,
      child: Scaffold(
        backgroundColor: V2Colors.fondo,
        body: child ?? const PromocionesPage(modoRestringido: true),
      ),
    );
  }
}
```

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `flutter test test/pages/v2/promos_shell_test.dart`
Expected: PASS — 3 tests

- [ ] **Step 5: Ramificar en `HomePage.build()`**

En `lib/pages/home_page.dart`, en `build()`, insertar la rama **después** del bloque `if (_isVerifyingSession) { ... }` y **antes** del `return ValueListenableBuilder<bool>(valueListenable: UiPrefs.homeV2, ...)`.

Reemplazar:

```dart
    // âœ… SesiÃ³n verificada - Mostrar UI normal
    // 🎨 Toggle de diseño: nuevo (Home V2) o clásico, conmutable en runtime
    return ValueListenableBuilder<bool>(
```

por:

```dart
    // âœ… SesiÃ³n verificada - Mostrar UI normal
    // 🏪 Modo restringido (comercio 9998): shell dedicado de Promociones.
    // Va ANTES del toggle de diseño a propósito: la preferencia V2/clásico
    // vive en usuarioBox y sobrevive al logout, así que un dispositivo puede
    // llegar en shell clásico y le mostraría Pedidos y Mapa al comercio.
    // Va DESPUÉS del loader de _isVerifyingSession, también a propósito: si
    // se pusiera arriba, el comercio saltearía la verificación de sesión.
    if (ModoRestringido.activo.value) {
      return const PromosShell();
    }

    // 🎨 Toggle de diseño: nuevo (Home V2) o clásico, conmutable en runtime
    return ValueListenableBuilder<bool>(
```

Agregar los dos imports en `home_page.dart`:

```dart
import '../services/modo_restringido.dart';
import 'v2/promos_shell.dart';
```

> Ajustá el path relativo del import de `promos_shell.dart` según dónde estén los otros imports de `v2/` en ese archivo (`home_page.dart` está en `lib/pages/`, así que `v2/promos_shell.dart` es correcto).

- [ ] **Step 6: Verificar compilación y tests**

Run: `flutter analyze lib/pages/home_page.dart lib/pages/v2/promos_shell.dart`
Expected: sin errores nuevos

Run: `flutter test test/pages/v2/promos_shell_test.dart test/pages/v2/v2_header_test.dart`
Expected: PASS — 11 tests

- [ ] **Step 7: Commit**

```bash
git add lib/pages/v2/promos_shell.dart lib/pages/home_page.dart test/pages/v2/promos_shell_test.dart
git commit -m "feat(modo-restringido): PromosShell dedicado y rama en HomePage"
```

---

## Task 7: Auto-selección del móvil único

**Files:**
- Modify: `lib/pages/login_page.dart` — extraer `_seleccionarMovilYContinuar`, agregar `_manejarMovilesYContinuar`, reemplazar los 3 call sites (`:1508+1524`, `:1545+1560`, `:1619+1635`)

**Interfaces:**
- Consumes: `MovilSelection.decidir`, `MovilSelection.idUnico`, `AccionMovil` (Task 2)
- Produces: `_manejarMovilesYContinuar(Map<String, dynamic> response)` → `Future<void>`, `_seleccionarMovilYContinuar(Map<String, dynamic> response, String movilId, {String? matricula})` → `Future<void>`

**Riesgo central de esta tarea:** el botón Confirmar hace **ocho escrituras** antes de continuar (Hive `sessionBox` y `usuarioBox`, `SessionSyncService`, `saveMovil`, `saveEscenario`, `saveBaseUrl`, `saveIsDevelopment`, `fecha`). Un atajo que solo haga `box.put('movil', ...)` rompe CriticalLogger, la baseUrl nativa y el arranque de servicios. Por eso primero se **extrae** el cuerpo tal cual, y recién después se lo reutiliza.

- [ ] **Step 1: Extraer el cuerpo del botón Confirmar a un método**

Agregar en `_LoginPageState` (por ejemplo justo antes de `_showMobileSelectionDialog`):

```dart
  /// Persiste el móvil elegido y dispara el resto del login.
  ///
  /// Es EXACTAMENTE lo que hacía el botón Confirmar del diálogo: ocho
  /// escrituras (Hive sessionBox + usuarioBox, SharedPreferences de Flutter,
  /// y las prefs nativas movil/escenario/baseUrl/isDevelopment) más la fecha,
  /// antes de `_proceedAfterMobileSelection`. No simplificar: CriticalLogger,
  /// la baseUrl del canal FCM y el arranque de servicios dependen de todas.
  Future<void> _seleccionarMovilYContinuar(
    Map<String, dynamic> response,
    String movilId, {
    String? matricula,
  }) async {
    var userbox = await Hive.openBox('usuarioBox');
    var box = await Hive.openBox('sessionBox');
    await box.put('movil', movilId);
    await userbox.put('movil', movilId);

    // 🔄 Sincronizar datos de sesión a SharedPreferences
    try {
      await SessionSyncService.syncToSharedPrefs();
      print('✅ Datos de sesión sincronizados (movil guardado)');
    } catch (e) {
      print('⚠️ Error sincronizando datos de sesión: $e');
    }

    // 🆕 Guardar móvil en SharedPreferences nativo (Android) para CriticalLogger
    try {
      const platform = MethodChannel('com.riogas.appmovil/shared_prefs');
      await platform.invokeMethod('saveMovil', {'movil': movilId});
      print('✅ Móvil guardado en SharedPreferences nativo: $movilId');
    } catch (e) {
      print('⚠️ Error guardando móvil en SharedPreferences nativo: $e');
      try {
        const platform = MethodChannel('com.riogas.appmovil/shared_prefs');
        await platform.invokeMethod('criticalLogFromFlutter', {
          'type': 'SharedPreferencesError',
          'movil': movilId,
          'error': e.toString(),
          'context':
              'Error guardando móvil en SharedPreferences desde Flutter (login_page)',
        });
        print('✅ Error enviado a CriticalLogger en Android');
      } catch (err) {
        print('⚠️ Error enviando log crítico a Android: $err');
      }
    }

    // 🆕 Guardar escenario en SharedPreferences nativo para FCM API
    try {
      const platform = MethodChannel('com.riogas.appmovil/shared_prefs');
      String escenarioValue =
          ModoRestringido.normalizarEscenario(response['escenarioid']);
      await platform
          .invokeMethod('saveEscenario', {'escenario': escenarioValue});
      print('✅ Escenario guardado en SharedPreferences nativo: $escenarioValue');
    } catch (e) {
      print('⚠️ Error guardando escenario en SharedPreferences nativo: $e');
    }

    // 🆕 Guardar baseUrl en SharedPreferences nativo para FCM API
    try {
      const platform = MethodChannel('com.riogas.appmovil/shared_prefs');

      final baseRootConst = (await getConstantValue('600'))?.trim();
      final servicesPathConst = (await getConstantValue('601'))?.trim();

      var baseRoot = (baseRootConst != null && baseRootConst.isNotEmpty)
          ? baseRootConst
          : 'https://www.riogas.uy/ica_geos_/';

      var servicesPath =
          (servicesPathConst != null && servicesPathConst.isNotEmpty)
              ? servicesPathConst
              : 'appservices/';

      baseRoot = baseRoot.replaceAll(
          RegExp(r'appservices/?$', caseSensitive: false), '');
      if (!baseRoot.endsWith('/')) baseRoot += '/';
      if (servicesPath.startsWith('/')) servicesPath = servicesPath.substring(1);
      if (!servicesPath.endsWith('/')) servicesPath += '/';

      String fullBaseUrl = AppEnvironment.isDevelopment
          ? AppEnvironment.devUrl
          : '$baseRoot$servicesPath';

      await platform.invokeMethod('saveBaseUrl', {'baseUrl': fullBaseUrl});
      await platform.invokeMethod(
          'saveIsDevelopment', {'isDevelopment': AppEnvironment.isDevelopment});

      print('✅ BaseUrl guardada en SharedPreferences nativo: $fullBaseUrl');
      print(
          '🔧 [LOGIN] Ambiente: ${AppEnvironment.isDevelopment ? "DESARROLLO" : "PRODUCCIÓN"}');
    } catch (e) {
      print('⚠️ Error guardando baseUrl en SharedPreferences nativo: $e');
    }

    String hoy = DateTime.now()
        .toUtc()
        .toIso8601String()
        .split('T')[0]
        .replaceAll('-', '');

    await box.put('fecha', hoy);
    if (matricula != null) {
      await box.put('matricula', matricula);
      await userbox.put('matricula', matricula);
    }

    print("Continuar luego de seleccionado un movil");

    await _proceedAfterMobileSelection(response, movilId);
  }
```

- [ ] **Step 2: Hacer que el diálogo use el método extraído**

En `_showMobileSelectionDialog`, reemplazar el cuerpo del `onPressed` del `ElevatedButton` desde `// 🔹 Guardar móvil seleccionado y matrícula en Hive` hasta la llamada a `_proceedAfterMobileSelection` por:

```dart
                        Navigator.of(dialogContext).pop();

                        await _seleccionarMovilYContinuar(
                          response,
                          selectedMovil!,
                          matricula: showLicensePlateField
                              ? licensePlateController.text
                              : null,
                        );
```

Es decir, el `onPressed` completo queda:

```dart
                    onPressed: () async {
                      if (selectedMovil != null &&
                          (!showLicensePlateField ||
                              licensePlateController.text.isNotEmpty)) {
                        setState(() {
                          isLoading = true;
                        });

                        Navigator.of(dialogContext).pop();

                        await _seleccionarMovilYContinuar(
                          response,
                          selectedMovil!,
                          matricula: showLicensePlateField
                              ? licensePlateController.text
                              : null,
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Seleccione un móvil y complete la matrícula.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
```

- [ ] **Step 3: Escribir el orquestador con las cuatro ramas**

Agregar en `_LoginPageState`, junto al método anterior:

```dart
  /// Decide qué hacer con la lista de móviles y continúa el login.
  ///
  /// Reemplaza los tres bloques duplicados que antes hacían
  /// `_extractAvailableMoviles` + `if (isNotEmpty) _showMobileSelectionDialog`.
  Future<void> _manejarMovilesYContinuar(Map<String, dynamic> response) async {
    _availableMoviles = _extractAvailableMoviles(response);

    // 🌍 Si es usuario especial, elegir servidor ANTES de cualquier otra cosa
    if (_specialUsers.contains(_usernameController.text)) {
      print(
          '🌍 [SERVER] Usuario especial detectado: ${_usernameController.text}');
      await _showServerSelectionDialog();
    }

    final pideMatricula = (await getConstantValue('180')) == 'S';
    final accion = MovilSelection.decidir(
      moviles: _availableMoviles,
      pideMatricula: pideMatricula,
    );
    print('🚚 [LOGIN] ${_availableMoviles.length} móvil(es) → $accion');

    switch (accion) {
      case AccionMovil.sinMoviles:
        // Antes de esta feature el login moría acá en silencio.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Su usuario no tiene ningún móvil asignado. Comuníquese con la agencia.'),
            backgroundColor: Colors.red,
          ),
        );
        return;

      case AccionMovil.autoSeleccionar:
        final movilId = MovilSelection.idUnico(_availableMoviles)!;
        print('🚚 [LOGIN] Móvil único ($movilId): se entra directo');
        await _seleccionarMovilYContinuar(response, movilId);
        return;

      case AccionMovil.pedirMatricula:
        // Un solo móvil pero la matrícula es obligatoria: diálogo REDUCIDO,
        // sin dropdown, con el móvil ya fijado.
        await _showMobileSelectionDialog(response, movilFijo: true);
        return;

      case AccionMovil.mostrarDialogo:
        await _showMobileSelectionDialog(response);
        return;
    }
  }
```

- [ ] **Step 4: Agregar el modo "móvil fijo" al diálogo**

En `_showMobileSelectionDialog`, cambiar la firma:

```dart
  Future<void> _showMobileSelectionDialog(
    Map<String, dynamic> response, {
    bool movilFijo = false,
  }) async {
```

y reemplazar el título del `AlertDialog`:

```dart
              title: Text('Seleccionar Móvil'),
```

por:

```dart
              title: Text(movilFijo ? 'Ingresar matrícula' : 'Seleccionar Móvil'),
```

Después, ocultar el dropdown cuando el móvil ya está fijado. Envolver el `Row` que contiene el `FutureBuilder` del dropdown (el primer hijo del `Column` de contenido) con la guarda:

```dart
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!movilFijo)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              // ... contenido existente del Row, sin cambios ...
                            ],
                          ),
                        if (showLicensePlateField) ...[
```

> Importante: el `Row` del dropdown se conserva **tal cual** por dentro; solo se le antepone `if (!movilFijo)`. No reindentar de más ni tocar el `FutureBuilder`.

- [ ] **Step 5: Preseleccionar el móvil cuando hay uno solo**

La preselección tiene que ocurrir **fuera** del `FutureBuilder`, arriba de todo en el método. Con `movilFijo: true` el dropdown no se dibuja, así que el código que vive adentro del `FutureBuilder` nunca correría y `selectedMovil` quedaría en `null` — y el botón Confirmar mostraría el snackbar de error en vez de continuar.

En `_showMobileSelectionDialog`, reemplazar el arranque del método:

```dart
    String? selectedMovil;
    bool isLoading = false;
    TextEditingController licensePlateController = TextEditingController();
    bool showLicensePlateField = false;
```

por:

```dart
    String? selectedMovil;
    bool isLoading = false;
    TextEditingController licensePlateController = TextEditingController();
    bool showLicensePlateField = false;

    // 🚚 Con un solo móvil no hay nada que elegir: queda preseleccionado.
    // Va acá y no dentro del FutureBuilder del dropdown porque en el modo
    // `movilFijo` ese dropdown ni se construye.
    if (_availableMoviles.length == 1) {
      selectedMovil = _availableMoviles.first['id'];
    }
```

No tocar el bloque de `defaultMovil` que ya existe dentro del `FutureBuilder`: sigue sirviendo para el caso de varios móviles.

- [ ] **Step 6: Reemplazar los tres call sites duplicados**

Buscar las **tres** apariciones de este patrón en `_login()` y reemplazar cada una por una sola línea.

Reemplazar cada bloque con esta forma:

```dart
                  print("📥 Extrayendo lista de móviles...");
                  _availableMoviles = _extractAvailableMoviles(response);

                  if (_availableMoviles.isNotEmpty) {
                    print(
                        "📋 Móviles disponibles para seleccionar: $_availableMoviles");
                    print(
                        "🛑 Mostrando selección de móviles antes de continuar...");

                    // 🌍 Si es usuario especial, mostrar selección de servidor PRIMERO
                    if (_specialUsers.contains(_usernameController.text)) {
                      print(
                          '🌍 [SERVER] Usuario especial detectado: ${_usernameController.text}');
                      await _showServerSelectionDialog();
                    }

                    // 🔹 Mostrar selección de móviles antes de continuar
                    await _showMobileSelectionDialog(response);
                  }
```

por:

```dart
                  await _manejarMovilesYContinuar(response);
```

respetando la indentación de cada sitio. Los tres sitios son:
1. Rama `OK==0` **con** registro de dispositivo previo (alrededor de la línea 1507)
2. Rama `OK==0` **sin** registro previo (alrededor de la línea 1544)
3. Rama `OK==9` con re-login (alrededor de la línea 1618)

- [ ] **Step 7: Verificar que no quedó ningún call site suelto**

Run: `grep -n "await _showMobileSelectionDialog\|_availableMoviles = _extractAvailableMoviles" lib/pages/login_page.dart`

Expected: exactamente **tres** líneas, las tres dentro de `_manejarMovilesYContinuar` — una extracción de móviles y dos llamadas al diálogo (la reducida con `movilFijo: true` y la completa).

> No usar `git grep -c` sobre los nombres pelados: el docstring de `_manejarMovilesYContinuar` los menciona a los dos en una misma línea, así que el conteo da uno de más en cada caso y parece que quedó un call site suelto.

- [ ] **Step 8: Agregar el import y verificar compilación**

Agregar en `login_page.dart`:

```dart
import '../services/movil_selection.dart';
```

Run: `flutter analyze lib/pages/login_page.dart`
Expected: sin errores nuevos

Run: `flutter test test/services/movil_selection_test.dart test/services/modo_restringido_test.dart`
Expected: PASS — 18 tests

- [ ] **Step 9: Commit**

```bash
git add lib/pages/login_page.dart
git commit -m "feat(login): auto-seleccion con un solo movil y aviso cuando no hay ninguno"
```

---

## Task 8: No arrancar el GPS en modo restringido (lado Dart)

**Files:**
- Modify: `lib/pages/login_page.dart` — `_onSuccessfulLoginFlow` (alrededor de `:3176-3224`)

**Interfaces:**
- Consumes: `ModoRestringido.activo` (Task 1)
- Produces: se invoca `saveRestrictedMode` y `startPromoKeepAlive` / `cancelHealthCheck` en el canal `background_service` (implementados en Tasks 9 y 10)

**Cuidado documentado:** hay que seguir seteando `flutter.sessionActive = true` aunque no haya GPS. Sin ese flag, `LocationHelper.isSessionActive()` devuelve `false` y se rompe **todo** el control remoto por FCM, incluido el logout remoto que sí queremos conservar.

- [ ] **Step 1: Ramificar el arranque de servicios**

En `_onSuccessfulLoginFlow`, reemplazar:

```dart
    final platform = MethodChannel("background_service");
    await platform.invokeMethod("startLocationService", {
      "interval": 3,
      "movil": movil,
      "escenario": escenario,
      "usuario": usuario,
      "deviceId": "$idTerminal",
    });
    print(
        "🔄 Servicio de ubicación en segundo plano iniciado con movil=$movil, escenario=$escenario, usuario=$usuario.");
```

por:

```dart
    final platform = MethodChannel("background_service");

    // 🏪 Modo restringido: el comercio no se trackea. Se persiste el flag en
    // las prefs nativas ANTES de cualquier otra cosa, porque MainActivity.onCreate
    // arranca el FGS de GPS leyendo config.last_movil y corre ANTES de que
    // exista el engine de Flutter: apagarlo solo desde acá no alcanza.
    final restringido = ModoRestringido.activo.value;
    try {
      await platform
          .invokeMethod("saveRestrictedMode", {"restricted": restringido});
      print("🏪 [MODO_RESTRINGIDO] restricted_mode nativo = $restringido");
    } catch (e) {
      print("⚠️ Error guardando restricted_mode nativo: $e");
    }

    if (restringido) {
      // El HealthCheckWorker se programa con KEEP y sobrevive reinicios: si
      // este teléfono lo usó antes un chofer, seguiría reviviendo el FGS de
      // GPS cada 15 minutos. Hay que cancelarlo explícitamente.
      try {
        await platform.invokeMethod("cancelHealthCheck");
        print("🏪 [MODO_RESTRINGIDO] HealthCheckWorker cancelado");
      } catch (e) {
        print("⚠️ Error cancelando HealthCheckWorker: $e");
      }

      // Keep-alive sin GPS para que el LMK no mate el proceso.
      try {
        await platform.invokeMethod("startPromoKeepAlive");
        print("🏪 [MODO_RESTRINGIDO] PromoKeepAliveService iniciado");
      } catch (e) {
        print("⚠️ Error iniciando PromoKeepAliveService: $e");
      }
    } else {
      await platform.invokeMethod("startLocationService", {
        "interval": 3,
        "movil": movil,
        "escenario": escenario,
        "usuario": usuario,
        "deviceId": "$idTerminal",
      });
      print(
          "🔄 Servicio de ubicación en segundo plano iniciado con movil=$movil, escenario=$escenario, usuario=$usuario.");
    }
```

> **No mover ni condicionar** la línea `await prefs.setBool('sessionActive', true);` que está justo arriba, ni la llamada a `FcmNotification` que está justo abajo. La primera mantiene viva la validación nativa de sesión; la segunda registra el canal FCM, que el comercio sigue usando para avisos de promos y para el logout remoto.

- [ ] **Step 2: Persistir el perfil para el gate de permisos**

En el mismo método, después del bloque anterior, agregar:

```dart
    // 🏪 Recordar el perfil para el próximo login: el gate de permisos corre
    // ANTES de ValidarUsuario, así que en el primer login todavía no se sabe
    // que este usuario es un comercio. usuarioBox sobrevive al logout.
    try {
      final userbox = await Hive.openBox('usuarioBox');
      await userbox.put('ultimoPerfilRestringido', restringido);
    } catch (e) {
      print('⚠️ Error guardando ultimoPerfilRestringido: $e');
    }
```

- [ ] **Step 3: Verificar compilación**

Run: `flutter analyze lib/pages/login_page.dart`
Expected: sin errores nuevos

> Los métodos `saveRestrictedMode`, `cancelHealthCheck` y `startPromoKeepAlive` todavía no existen del lado Kotlin (Tasks 9 y 10). Eso **no** rompe la compilación: `invokeMethod` resuelve en runtime y cada llamada está en su propio `try/catch`. Hasta que se implementen, cada una va a loguear un `MissingPluginException` atrapado. Es esperado.

- [ ] **Step 4: Commit**

```bash
git add lib/pages/login_page.dart
git commit -m "feat(modo-restringido): no arrancar GPS en el login y persistir el perfil"
```

---

## Task 9: Kotlin — bloquear los caminos nativos que arrancan el GPS

**Files:**
- Modify: `android/app/src/main/kotlin/com/riogas/appmovil/ServiceStatusFlags.kt`
- Modify: `android/app/src/main/kotlin/com/example/moveit/MainActivity.kt` (canal `background_service`, `restartLocationServiceFromForeground`)
- Modify: `android/app/src/main/kotlin/com/riogas/appmovil/FcmPushReceiver.kt` (`handleRestartTracking`)

**Interfaces:**
- Consumes: los métodos del canal invocados en Task 8 (`saveRestrictedMode`, `cancelHealthCheck`)
- Produces:
  - `ServiceStatusFlags.isRestrictedMode(context)` → `Boolean`
  - `ServiceStatusFlags.setRestrictedMode(context, restricted, reason)` → `Unit`
  - Métodos `saveRestrictedMode`, `cancelHealthCheck` en el canal `background_service`

**Sin tests automatizados:** el proyecto no tiene infraestructura de tests de Kotlin. La verificación es compilación + pasos manuales.

- [ ] **Step 1: Agregar el flag a `ServiceStatusFlags`**

En `ServiceStatusFlags.kt`, agregar la constante junto a las otras:

```kotlin
    private const val KEY_RESTRICTED_MODE = "restricted_mode"
```

y los dos métodos, después de `setServiceDisabled`:

```kotlin
    /**
     * 🏪 Perfil comercio (escenario 9998): la app NO debe trackear ubicación.
     *
     * Es distinto de service_disabled: aquel es un apagado temporal y global
     * del dispositivo, que startLocationService y restart_tracking limpian.
     * Este describe QUIÉN está logueado, y ningún camino de arranque de GPS
     * puede limpiarlo — solo el login o el logout lo cambian.
     */
    @Synchronized
    fun isRestrictedMode(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_RESTRICTED_MODE, false)

    @Synchronized
    fun setRestrictedMode(context: Context, restricted: Boolean, reason: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_RESTRICTED_MODE, restricted)
            .putString("restricted_mode_reason", reason)
            .putLong("restricted_mode_ts", System.currentTimeMillis())
            .commit() // commit síncrono: MainActivity.onCreate lo lee antes de Flutter
        Log.i(TAG, "restricted_mode=$restricted reason=$reason")
    }
```

> El `commit()` síncrono no es opcional: `restartLocationServiceFromForeground()` lo lee en `onCreate`, potencialmente en el siguiente arranque, y un `apply()` asíncrono podría no haber llegado a disco.

- [ ] **Step 2: Agregar los métodos nuevos al canal `background_service`**

En `MainActivity.kt`, dentro del `when (call.method)` del canal `background_service`, agregar dos ramas nuevas (por ejemplo después de `"stopLocationService" -> { ... }`):

```kotlin
                    "saveRestrictedMode" -> {
                        val restricted = call.argument<Boolean>("restricted") ?: false
                        com.riogas.appmovil.ServiceStatusFlags.setRestrictedMode(
                            this, restricted, "login Flutter")
                        if (restricted) {
                            // Nada de tracking para este perfil: matar el FGS por
                            // si venía corriendo de una sesión anterior de chofer.
                            com.riogas.appmovil.tracking.LocationTrackingService.stop(this)
                        }
                        result.success("✅ restricted_mode=$restricted")
                    }
                    "cancelHealthCheck" -> {
                        com.riogas.appmovil.tracking.HealthCheckWorker.cancel(this)
                        Log.i("MainActivity", "🏪 HealthCheckWorker cancelado (modo restringido)")
                        result.success("✅ HealthCheckWorker cancelado")
                    }
```

- [ ] **Step 3: Limpiar el flag cuando arranca un chofer normal**

En el mismo `when`, dentro de la rama `"startLocationService"`, agregar junto a los otros `ServiceStatusFlags.set*`:

```kotlin
                        com.riogas.appmovil.ServiceStatusFlags.setRestrictedMode(this, false, "startLocationService desde Flutter UI")
```

Esto evita que un teléfono usado por un comercio quede en modo restringido para el chofer siguiente.

- [ ] **Step 4: Bloquear el arranque nativo en `onCreate`**

En `restartLocationServiceFromForeground()`, agregar la guarda **como primer chequeo**, antes de leer `last_movil`:

```kotlin
        private fun restartLocationServiceFromForeground() {
            // 🏪 Perfil comercio: nunca arrancar el FGS de ubicación. Este método
            // corre en onCreate ANTES de super.onCreate(), o sea antes de que
            // exista el engine de Flutter: es el único punto donde se puede
            // frenar este camino.
            if (com.riogas.appmovil.ServiceStatusFlags.isRestrictedMode(this)) {
                Log.i("MainActivity", "🏪 restricted_mode=true → no se arranca el FGS de ubicación")
                return
            }

            val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)
            val movil = prefs.getString("last_movil", "")
```

- [ ] **Step 5: Bloquear el arranque remoto por FCM**

En `FcmPushReceiver.kt`, en `handleRestartTracking`, agregar la guarda inmediatamente después del chequeo de sesión:

```kotlin
            if (!isSessionValid()) {
                Log.w(TAG, "🚫 [FCM] [SESSION] No hay sesión activa, ignorando comando restart_tracking")
                DeviceEventReporter.report(this, "restart_result", "NO_SESSION")
                return
            }

            // 🏪 Perfil comercio: el servidor no debe poder resucitar el GPS.
            // Se reporta igual para que quede traza en el backend.
            if (ServiceStatusFlags.isRestrictedMode(this)) {
                Log.w(TAG, "🏪 [FCM] restricted_mode=true, ignorando restart_tracking")
                DeviceEventReporter.report(this, "restart_result", "RESTRICTED_MODE")
                return
            }
```

- [ ] **Step 6: Blindar también el health-check**

En `HealthCheckWorker.kt`, agregar la guarda junto a la de `service_disabled`:

```kotlin
    override suspend fun doWork(): Result {
        val ctx = applicationContext
        if (ServiceStatusFlags.isServiceDisabled(ctx)) return Result.success()
        // 🏪 Perfil comercio: aunque haya quedado programado de una sesión
        // anterior (se encola con KEEP y sobrevive reinicios), no revivir el FGS.
        if (ServiceStatusFlags.isRestrictedMode(ctx)) return Result.success()
```

Es redundante con el `cancelHealthCheck` de Task 8 y está puesto a propósito: `cancel()` puede fallar o el worker puede reprogramarse desde otro camino.

- [ ] **Step 7: Verificar que compila**

Run: `flutter build apk --debug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 8: Commit**

```bash
git add android/app/src/main/kotlin/com/riogas/appmovil/ServiceStatusFlags.kt android/app/src/main/kotlin/com/example/moveit/MainActivity.kt android/app/src/main/kotlin/com/riogas/appmovil/FcmPushReceiver.kt android/app/src/main/kotlin/com/riogas/appmovil/tracking/HealthCheckWorker.kt
git commit -m "feat(android): flag restricted_mode y bloqueo de los 4 caminos de arranque del FGS"
```

---

## Task 10: `PromoKeepAliveService` — foreground service `dataSync` sin GPS

**Files:**
- Create: `android/app/src/main/kotlin/com/riogas/appmovil/tracking/PromoKeepAliveService.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/kotlin/com/example/moveit/MainActivity.kt` (canal + `onCreate`)

**Interfaces:**
- Consumes: `ServiceStatusFlags.isRestrictedMode` (Task 9)
- Produces:
  - `PromoKeepAliveService.start(context)` / `.stop(context)` / `.isRunning`
  - Método `startPromoKeepAlive` en el canal `background_service` (invocado en Task 8)

**Limitación conocida y aceptada:** en Android 15 los FGS de tipo `dataSync` tienen un tope de 6 horas por día. Pasado ese tope llega `onTimeout()` y el servicio debe detenerse solo; el proceso vuelve a ser matable. El plan B es el comportamiento por defecto: la sesión sobrevive en Hive y el usuario o un push FCM reabren la app sin re-login.

- [ ] **Step 1: Crear el servicio**

Crear `android/app/src/main/kotlin/com/riogas/appmovil/tracking/PromoKeepAliveService.kt`:

```kotlin
package com.riogas.appmovil.tracking

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.riogas.appmovil.DeviceEventReporter
import com.riogas.appmovil.ServiceStatusFlags

/**
 * 🏪 Keep-alive del perfil comercio (escenario 9998).
 *
 * NO hace absolutamente nada: no lee ubicación, no consulta la red, no
 * programa loops. Existe solo para que el proceso no quede como "cached
 * process" y el low-memory killer no lo mate mientras el comercio tiene la
 * app abierta.
 *
 * Es un FGS de tipo `dataSync` a propósito, NO `location`: no pide ni usa
 * permisos de ubicación, y su notificación no menciona rastreo.
 *
 * Android 15 limita los FGS `dataSync` a ~6 h por día. Al llegar al tope
 * llega onTimeout() y hay que detenerse limpiamente o el sistema mata la app
 * con ForegroundServiceDidNotStopInTimeException. A partir de ahí el proceso
 * vuelve a ser matable: la sesión sigue viva en Hive y el usuario reabre.
 */
class PromoKeepAliveService : Service() {

    companion object {
        private const val TAG = "PromoKeepAlive"
        private const val NOTIF_ID = 1720
        private const val CHANNEL_ID = "promo_keepalive_channel"

        @Volatile
        var isRunning = false
            private set

        /** Idempotente: si ya corre, Android reutiliza la instancia. */
        fun start(context: Context) {
            context.startForegroundService(
                Intent(context, PromoKeepAliveService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, PromoKeepAliveService::class.java))
        }
    }

    override fun onCreate() {
        super.onCreate()
        try {
            startInForeground()
            isRunning = true
            Log.i(TAG, "✅ Keep-alive del comercio en foreground")
        } catch (e: Exception) {
            // Mismo criterio que LocationTrackingService: no propagar, mata el proceso.
            Log.e(TAG, "❌ No se pudo pasar a foreground", e)
            DeviceEventReporter.report(this, "health_fgs_dead", "KEEPALIVE_START_DENIED",
                mapOf("error" to e.javaClass.simpleName))
            isRunning = false
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!isRunning) return START_NOT_STICKY

        // Si el perfil dejó de ser restringido (p.ej. se logueó un chofer),
        // este servicio no tiene razón de existir.
        if (!ServiceStatusFlags.isRestrictedMode(this)) {
            Log.w(TAG, "restricted_mode=false → keep-alive se detiene")
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    private fun startInForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Promociones", NotificationManager.IMPORTANCE_LOW)
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MoveIT")
            .setContentText("Promociones activas")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    /** Android 15+: tope diario de dataSync alcanzado. Detenerse limpio. */
    override fun onTimeout(startId: Int) {
        Log.w(TAG, "⏱️ Tope de dataSync alcanzado → keep-alive se detiene")
        DeviceEventReporter.report(this, "health_fgs_dead", "KEEPALIVE_TIMEOUT")
        isRunning = false
        stopSelf()
    }

    override fun onDestroy() {
        isRunning = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
```

> `override fun onTimeout(startId: Int)` compila: `android/app/build.gradle:19` tiene `compileSdk = 35` y `Service.onTimeout(int)` se agregó justo en API 35. Verificado antes de escribir el plan; no hace falta chequearlo de nuevo.

- [ ] **Step 2: Declarar permiso y servicio en el manifest**

En `AndroidManifest.xml`, agregar el permiso junto a los otros de foreground service (después de la línea de `FOREGROUND_SERVICE_LOCATION`):

```xml
    <!-- 🏪 Keep-alive del perfil comercio (sin ubicación) -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
```

y declarar el servicio junto al de tracking:

```xml
        <service
            android:name="com.riogas.appmovil.tracking.PromoKeepAliveService"
            android:foregroundServiceType="dataSync"
            android:exported="false" />
```

- [ ] **Step 3: Exponer el arranque por MethodChannel**

En `MainActivity.kt`, en el `when` del canal `background_service`, agregar:

```kotlin
                    "startPromoKeepAlive" -> {
                        com.riogas.appmovil.tracking.PromoKeepAliveService.start(this)
                        result.success("✅ PromoKeepAliveService iniciado")
                    }
                    "stopPromoKeepAlive" -> {
                        com.riogas.appmovil.tracking.PromoKeepAliveService.stop(this)
                        result.success("✅ PromoKeepAliveService detenido")
                    }
```

- [ ] **Step 4: Arrancarlo también en cada apertura de la app**

En `MainActivity.onCreate`, reemplazar:

```kotlin
            // 🔄 REINICIAR SERVICIO DESDE FOREGROUND (Android 12+ compatible)
            restartLocationServiceFromForeground()
```

por:

```kotlin
            // 🔄 REINICIAR SERVICIO DESDE FOREGROUND (Android 12+ compatible)
            // 🏪 Simétrico al camino del GPS: el comercio arranca su keep-alive
            // sin ubicación, el chofer arranca el FGS de tracking.
            if (com.riogas.appmovil.ServiceStatusFlags.isRestrictedMode(this)) {
                com.riogas.appmovil.tracking.PromoKeepAliveService.start(this)
                Log.i("MainActivity", "🏪 Keep-alive del comercio iniciado desde onCreate")
            } else {
                restartLocationServiceFromForeground()
            }
```

- [ ] **Step 5: Verificar que compila**

Run: `flutter build apk --debug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/kotlin/com/riogas/appmovil/tracking/PromoKeepAliveService.kt android/app/src/main/AndroidManifest.xml android/app/src/main/kotlin/com/example/moveit/MainActivity.kt
git commit -m "feat(android): PromoKeepAliveService (FGS dataSync sin GPS) para el perfil comercio"
```

---

## Task 11: Apagar el nagging de GPS y batería en modo restringido

**Files:**
- Modify: `lib/pages/home_page.dart` (`initState` → `_initializeLocationService`)
- Modify: `lib/main.dart` (chequeo de batería)
- Modify: `android/app/src/main/kotlin/com/example/moveit/receivers/GPSStatusReceiver.kt`

**Interfaces:**
- Consumes: `ModoRestringido.activo` (Task 1), `ServiceStatusFlags.isRestrictedMode` (Task 9)
- Produces: nada nuevo

**Por qué hace falta:** son tres efectos colaterales de GPS que corren con total independencia del tracking. Sin esto, un comercio que no usa ubicación igual vería el intent de exención de batería, un diálogo no cancelable, y una notificación fija pidiéndole que prenda el GPS.

- [ ] **Step 1: No inicializar el `LocationService` legado**

En `lib/pages/home_page.dart`, en `initState`, reemplazar la llamada:

```dart
    _initializeLocationService();
```

por:

```dart
    // 🏪 El comercio no trackea: el LocationService legado dispara el intent
    // de exención de batería en cada init, sin motivo para este perfil.
    if (!ModoRestringido.activo.value) {
      _initializeLocationService();
    }
```

El import de `modo_restringido.dart` ya se agregó en Task 6.

- [ ] **Step 2: Saltear el diálogo de batería**

En `lib/main.dart`, en el método `_checkBatteryOptimization()`, agregar como primera línea del cuerpo:

```dart
    // 🏪 El comercio no necesita exención de batería: no hay tracking continuo.
    if (ModoRestringido.activo.value) {
      print('🏪 [BATERÍA] Modo restringido: se omite el chequeo');
      return;
    }
```

El import ya se agregó en Task 3.

- [ ] **Step 3: No mostrar la notificación de "Ubicación desactivada"**

En `GPSStatusReceiver.kt`, en `onReceive`, envolver la llamada a `showGpsOffNotification(context)` (alrededor de la línea 127) con la guarda:

```kotlin
                    DeviceEventReporter.report(context, "gps_off", "PROVIDERS_CHANGED")
                    // 🏪 El comercio no usa ubicación: no tiene sentido pedirle
                    // que la prenda con una notificación fija.
                    if (!com.riogas.appmovil.ServiceStatusFlags.isRestrictedMode(context)) {
                        showGpsOffNotification(context)
                    }
```

> `showGpsOffNotification` tiene exactamente **un** call site (`GPSStatusReceiver.kt:127`), más su definición en `:28`. Verificado antes de escribir el plan. El `cancel` de la notificación (rama `gps_on`) **no** se toca: cancelar es siempre seguro.

- [ ] **Step 4: Verificar que compila**

Run: `flutter analyze lib/pages/home_page.dart lib/main.dart`
Expected: sin errores nuevos

Run: `flutter build apk --debug`
Expected: BUILD SUCCESSFUL

Run: `flutter test test/services/modo_restringido_test.dart test/services/movil_selection_test.dart test/pages/v2/v2_header_test.dart test/pages/v2/promos_shell_test.dart`
Expected: PASS — 29 tests

> Enumerar los archivos, **no** correr `flutter test test/services/`: ese directorio contiene `persistent_stream_manager_test.dart`, que está rojo desde antes (ver Global Constraints).

- [ ] **Step 5: Commit**

```bash
git add lib/pages/home_page.dart lib/main.dart android/app/src/main/kotlin/com/example/moveit/receivers/GPSStatusReceiver.kt
git commit -m "feat(modo-restringido): sin nagging de bateria ni de GPS para el comercio"
```

---

## Task 12: Gate de permisos según el perfil recordado

**Files:**
- Modify: `lib/pages/login_page.dart` — `_handleLoginButtonPress` (alrededor de `:1283-1289`)

**Interfaces:**
- Consumes: `usuarioBox['ultimoPerfilRestringido']` (escrito en Task 8)
- Produces: nada nuevo

**Limitación explícita:** el primer login de un comercio pide todos los permisos, porque el escenario recién se conoce después de `ValidarUsuario` y este gate corre antes. Del segundo login en adelante, no.

- [ ] **Step 1: Escribir el helper que decide si saltear el gate**

Agregar en `_LoginPageState`, junto a `_handleLoginButtonPress`:

```dart
  /// ¿Se puede saltear el gate de permisos (batería + GPS always + precisión)?
  ///
  /// Solo si el último login en este dispositivo fue de un comercio Y el
  /// usuario tipeado es el mismo. El gate corre ANTES de ValidarUsuario, así
  /// que en el primer login es imposible saber el perfil: se piden todos.
  Future<bool> _puedeSaltearPermisos(String username) async {
    try {
      final userbox = await Hive.openBox('usuarioBox');
      final fueRestringido =
          userbox.get('ultimoPerfilRestringido', defaultValue: false) == true;
      final mismoUsuario =
          userbox.get('lastUsername', defaultValue: '').toString() == username;
      return fueRestringido && mismoUsuario;
    } catch (e) {
      print('⚠️ [LOGIN] No se pudo leer el perfil anterior: $e');
      return false;
    }
  }
```

> **Ambas premisas están verificadas, no hace falta re-chequearlas:**
> - La clave `lastUsername` existe y es exactamente esa: se escribe en `login_page.dart:1439` y `logout_service.dart:199` la restaura después del logout.
> - `usuarioBox` **sobrevive al logout**: `LogoutService` borra `sessionBox`, `constantBox`, `mensajesBox`, `failedRequestsBox` y siete boxes más (`logout_service.dart:157-193`), pero `usuarioBox` no está en ninguna de esas listas, y además preserva y restaura `lastUsername`/`huella` explícitamente. Por eso `ultimoPerfilRestringido` sigue ahí en el siguiente login.
> - El orden también funciona: `lastUsername` se escribe dentro de `_login()`, o sea **después** del gate de permisos. En el segundo login, el gate lee el valor que dejó el primero. Que es justo lo que queremos.

- [ ] **Step 2: Usar el helper en el gate**

En `_handleLoginButtonPress`, reemplazar:

```dart
    // 🎯 PASO 2: Validar permisos ANTES de hacer login
    bool permissionsGranted = await _validatePermissionsBeforeLogin();

    if (!permissionsGranted) {
      print('⚠️ [LOGIN] Login bloqueado - Permisos incompletos');
      return; // ❌ NO CONTINUAR con el login
    }
```

por:

```dart
    // 🎯 PASO 2: Validar permisos ANTES de hacer login
    // 🏪 Salvo que el último login de este mismo usuario haya sido de un
    // comercio: no tiene sentido exigirle GPS y batería a alguien que no
    // trackea. En el primer login todavía no sabemos el perfil.
    if (await _puedeSaltearPermisos(username)) {
      print('🏪 [LOGIN] Perfil comercio recordado: se omite el gate de permisos');
    } else {
      bool permissionsGranted = await _validatePermissionsBeforeLogin();

      if (!permissionsGranted) {
        print('⚠️ [LOGIN] Login bloqueado - Permisos incompletos');
        return; // ❌ NO CONTINUAR con el login
      }
    }
```

- [ ] **Step 3: Verificar compilación y tests**

Run: `flutter analyze lib/pages/login_page.dart`
Expected: sin errores nuevos

Run: `flutter test test/services/modo_restringido_test.dart test/services/movil_selection_test.dart test/pages/v2/v2_header_test.dart test/pages/v2/promos_shell_test.dart`
Expected: PASS — 29 tests

> Enumerar los archivos, **no** correr `flutter test test/services/`: ese directorio contiene `persistent_stream_manager_test.dart`, que está rojo desde antes (ver Global Constraints).

- [ ] **Step 4: Commit**

```bash
git add lib/pages/login_page.dart
git commit -m "feat(login): saltear el gate de permisos cuando el perfil anterior fue comercio"
```

---

## Task 13: Verificación manual en dispositivo

**Files:** ninguno (solo verificación)

**Interfaces:**
- Consumes: todas las tareas anteriores

No hay forma de automatizar esto: requiere un backend que devuelva `escenarioid=9998` y un teléfono Android real.

- [ ] **Step 1: Preparar los prerrequisitos de backend**

Confirmar con los equipos correspondientes, antes de probar:

1. Las reglas de Firestore permiten escribir en `sessions-9998`
2. Hay al menos una promo con `EscenariosHabilitados` conteniendo `"9998"` o `"*"`
3. GeneXus acepta `escenarioid=9998` en `RegistrarSesion` y `RegistrarCierre`
4. Existe un usuario de prueba cuyo `ValidarUsuario` devuelve `escenarioid=9998` y **un solo** móvil

Si (1) o (2) faltan, la pantalla del comercio va a salir vacía o el login va a fallar, y **no va a ser un bug del código**.

- [ ] **Step 2: Regresión del chofer (lo más importante)**

Instalar y loguear con un usuario **normal** de varios móviles:

- [ ] Aparece el diálogo de selección con todos los móviles
- [ ] Después del login se ve la notificación "Rastreo de ubicación activo"
- [ ] La barra superior muestra la píldora `Móvil N · <estado>`
- [ ] El ícono de Mensajes está y abre la pantalla
- [ ] El menú del avatar tiene Configuración **y** Cerrar sesión
- [ ] Las coordenadas siguen llegando al backend

- [ ] **Step 3: Auto-selección con un móvil**

Con un usuario normal de **un solo** móvil:

- [ ] El login entra directo, sin diálogo
- [ ] `Hive sessionBox['movil']` quedó con el id correcto
- [ ] El tracking arrancó igual que siempre

- [ ] **Step 4: Modo restringido**

Con el usuario de escenario 9998:

- [ ] Entra directo a Promociones, sin diálogo de móvil
- [ ] **No** aparece la notificación de rastreo de ubicación
- [ ] **Sí** aparece la notificación "MoveIT · Promociones activas"
- [ ] El header muestra el nombre del comercio, sin píldora de móvil ni estado
- [ ] No hay ícono de Mensajes ni barra inferior
- [ ] El menú del avatar tiene **solo** Cerrar sesión
- [ ] El botón Atrás de Android no cierra la app
- [ ] Se ven promociones (si no, revisar el prerrequisito 2)
- [ ] Validar y consumir una promo funciona (contra los mocks)
- [ ] Cerrar la app y reabrirla: entra directo a Promociones y **sigue sin** notificación de rastreo
- [ ] Enviar un `restart_tracking` por FCM: el GPS **no** arranca y el backend recibe `restart_result=RESTRICTED_MODE`
- [ ] Enviar un `logout_user` por FCM: la sesión se cierra
- [ ] Dejar la app en background 30+ minutos: sigue viva
- [ ] Segundo login del mismo usuario: no pide permisos de GPS ni de batería

- [ ] **Step 5: Cambio de perfil en el mismo dispositivo**

- [ ] Loguear el comercio, cerrar sesión, loguear un chofer normal
- [ ] El chofer ve la notificación de rastreo y las coordenadas llegan
- [ ] La notificación "Promociones activas" desapareció

- [ ] **Step 6: Documentar los resultados**

Anotar cualquier desvío en `docs/superpowers/plans/2026-07-24-modo-restringido-9998.md` bajo una sección "Resultados de la verificación en dispositivo", y commitear.

---

## Notas de implementación

**Deuda conocida que este plan NO corrige** (documentada en el spec, sección 8):

- `getConstantValue('180')` se evalúa antes de que el login recargue las constantes, así que la decisión de pedir matrícula usa el `constantBox` de la sesión anterior. En un teléfono limpio nunca se pide matrícula.
- Si el permiso de notificaciones no está concedido, el login no navega y queda en un dead-end silencioso.
- `printScreen` (anti-screenshot) no se va a activar para el comercio, porque sale del documento `Moviles-9998/Moviles-{movil}`, que no va a existir.
- `BeneficiosService` está 100% simulado; la pantalla del comercio no opera contra el backend real.
- Los dos criterios de cambio de día están descoordinados: `loginDate` en hora local contra `fecha` en UTC.
