# MoveIT — RioGas Delivery (la app de los repartidores)

## Qué es

App Android hecha en **Flutter (Dart) + Kotlin nativo** que usan los repartidores de
RIOGAS en la calle. Hace cuatro cosas: baja los pedidos del día y los muestra en lista
y en mapa, deja cumplirlos (finalizar, anunciar llegada, cobrar), manda la posición GPS
de forma continua aunque la app esté en segundo plano, y —desde el rediseño 2026— valida
y consume **promociones de clientes** (Antel, Claro, OCA, MIDES…) con PIN por SMS o
escaneo de QR / código de barras.

Dentro de la misma app conviven **dos perfiles**:

- el **chofer** (escenarios `1000` y `2000`): la app completa, con GPS;
- el **comercio adherido** (escenario `9998`): una sola pantalla, la de Promociones,
  sin GPS, sin pedidos y sin mapa (`PromosShell`).

El backend es **GeneXus (SGM)** por HTTP POST contra una webapp, más **Firestore** y
**FCM** para todo lo de tiempo real (sesión activa, logout remoto, pedidos nuevos,
banderas de configuración del móvil). No hay base de datos propia: lo local es **Hive**.

⚠️ **No confundir con `linea-master` / `RiogasMovil`**, que es la app de **facturación**
móvil: ésa es Java nativo y vive en otro repositorio. Esta es la de **delivery**.

Repo: `Riogas/app-flutter`, rama de trabajo `dev`.

## Cómo se levanta

Esto **no es un servidor**: no hay puerto que abrir ni URL que levantar. Se compila y se
instala en un teléfono Android.

**En matrix (donde corre la consola de turnos):**

```bash
export PATH=$HOME/flutter/bin:$PATH   # o usar `bash -lc`, que ya lo trae
cd ~/proyectos/appflutter
flutter pub get                       # anda limpio
```

🚫 **En matrix NO se compila el APK.** No hay Android SDK ni JDK instalados, y tampoco
está el keystore de firma (`keystore/` no está versionado, así que en matrix no existe).
`flutter build apk`, `flutter run`, `flutter install` y `./gradlew` fallan sí o sí.
Lo único que se puede correr acá son **pruebas unitarias y de widget** (`flutter test`)
y **`flutter analyze`**. Cualquier tarea que exija ver la app andando, medir el arranque,
probar el GPS en background o verificar un cambio de Kotlin **no se puede cerrar en
matrix**: dejala documentada y avisá que quedó pendiente de verificación en dispositivo.

**En una PC con Android SDK + JDK 21** (así trabaja la persona):

```bash
flutter pub get
flutter run                    # con un teléfono enchufado por USB
flutter build apk --release    # firma con keystore/key.properties
```

**Ambientes.** No hay `.env` ni archivo de configuración: la app **arranca SIEMPRE en
producción** (`AppEnvironment.initialize()` en `lib/utils/constantes.dart` ignora a
propósito lo que haya guardado) y recién después del login, y solo para usuarios
especiales, se puede pasar a desarrollo. Las URLs salen de **constantes que viven en
Hive** (`constantBox`), bajadas del backend:

| Constante | Qué es |
|---|---|
| `600` + `601` | raíz + ruta de servicios de **producción** (fallback `https://www.riogas.uy/ica_geos_/`) |
| `611` | URL de **desarrollo** (fallback `https://sgm.riogas.com.uy/appservices/`) |
| `602` / `603` | rutas de los dos reportes PDF (visitas / promociones) |
| `180` | si la matrícula es obligatoria al elegir móvil (`'S'`) |

## Cómo se prueba

**El comando, desde la raíz del repo en matrix:**

```bash
flutter test $(find test -name '*_test.dart' ! -name 'persistent_stream_manager_test.dart' | sort)
```

**131 pruebas en verde. ~45 s con caché caliente, ~2 min en frío** (la primera corrida
compila el bundle de test). Si `flutter` no está en el PATH, antepoderle
`export PATH=$HOME/flutter/bin:$PATH &&`.

**Por qué esa exclusión, y por qué no hay que "arreglarla".** `flutter test` a secas da
**131 verdes y 13 rojas**, y las 13 son *todas* de
`test/services/persistent_stream_manager_test.dart`, siempre con el mismo error:

```
[core/no-app] No Firebase App '[DEFAULT]' has been created - call Firebase.initializeApp()
```

`PersistentStreamManager._instance` construye `FirebaseService` en el constructor, y ése
toca `FirebaseFirestore.instance`. Inicializar `firebase_core` en un test **no se puede
mockear**: el plugin migró a Pigeon y el mock por `MethodChannel` falla con
`channel-error`. Ya se intentó y se descartó; está anotado arriba de todo en
`test/pages/v2/v2_header_test.dart`. Ese rojo es del **entorno**, no del código: no lo
persigas, no borres el archivo y no lo "arregles" agregando un mock.

**`flutter analyze` NO sirve como puerta de calidad**: hoy devuelve **221 issues**
(warnings heredados, `unused_local_variable`, `deprecated_member_use`…) y sale en rojo
aunque el código esté perfecto. Corrélo para leerlo si tocás algo grande, nunca para
decidir si el trabajo está bien.

**Cómo se escriben pruebas acá:**

- El import es `package:MoveIT/...` — con esa capitalización exacta, es el `name` del
  `pubspec.yaml`.
- Se prueba **lógica pura**: los servicios chicos y sin estado global (`PromoDoc`,
  `MovilSelection`, `ModoRestringido`, `ModoIngresoCodigo`, `ProteccionPantalla`,
  `BeneficiosService.build*Body`). Es el patrón del repo: cuando hace falta cubrir algo,
  primero se extrae la decisión a una clase pura y después se prueba esa clase.
- Un widget se puede `pumpWidget` **solo si no construye Firestore por abajo**.
  `V2Header` con `mostrarEstado: true` sí lo construye → en test hay que pasarle
  `mostrarEstado: false`, o probar los defaults sin pumpear.
- Para inyectar el efecto de plataforma se usa un typedef reemplazable
  (`AplicadorProteccion` en `proteccion_pantalla.dart`) — no `mockito`.

## Convenciones

**Estructura.** Todo el Dart cuelga de `lib/`:

```
lib/main.dart              arranque, Firebase, FCM, permisos, auto-update  (~75 KB)
lib/pages/                 pantallas del diseño CLÁSICO (home, login, mapa, pedidos…)
lib/pages/v2/              rediseño 2026 (Home V2), tema, tarjetas, promociones
lib/services/              31 archivos: red, Firestore, sesión, GPS, promos, prefs
lib/utils/                 constantes, config, firebase_options, helpers
android/app/src/main/kotlin/  el lado nativo (ver abajo)
test/                      espeja lib/ (test/services/…, test/pages/v2/…)
```

- Archivos y carpetas en **snake_case**; clases en `PascalCase`; el sufijo `_page.dart`
  es una pantalla, `_service.dart` un servicio, `_store.dart` una persistencia local.
- **Los servicios son clases con miembros `static`** y constructor privado
  (`class Foo { Foo._(); static … }`). No hay inyección de dependencias ni contenedor.
- **No hay gestor de estado** (nada de Provider/Riverpod/Bloc): se usan `ValueNotifier`
  globales expuestos por el servicio (`UiPrefs.homeV2`, `ModoRestringido.activo`) y
  `ValueListenableBuilder` en la UI.
- **Todo en español**: identificadores nuevos, comentarios, doc-comments `///`, textos de
  UI y mensajes de commit. Hay código viejo en inglés; no lo traduzcas de paso.
- **Logging**: `print('🎨 [UI_PREFS] mensaje')` — un emoji, el módulo entre corchetes en
  mayúsculas, y el texto. Regla de oro del repo: **el logging nunca crashea la app**;
  cada bloque que loguea va dentro de un `try/catch` que se traga el error.
- **Commits**: una línea, en español, contando el efecto para quien usa la app
  («Los reportes siguen el ambiente, en vez de ir siempre a producción»). Los
  `feat(...)` / `fix(...)` que ves en el historial son viejos: no los imites.

**Reglas de dominio que ya están resueltas en un solo lugar — usalas, no las repitas:**

- **Escenarios**: nunca compares contra `'9998'`, `'1000'` o `'2000'` a mano.
  `lib/services/modo_restringido.dart` es *el único lugar del repo que conoce esos
  números* (`ModoRestringido.escenarioComercio`, `.normalizarEscenario()`,
  `.esRestringido()`). El escenario **es** la bandera: no se guarda un booleano aparte.
- **Documentos de promoción de Firestore**: leelos con `PromoDoc.valor/texto/idInterno/
  lista/habilitadaPara`, que toleran la grafía (`idInterno` vs `IdInterno`), los números
  como texto o `double`, y las listas cargadas como `"1000, 9998"`. GeneXus manda las dos
  grafías según el documento.
- **Bodies de los servicios de promociones**: los arma `BeneficiosService.build*Body` y
  las claves tienen **casing exacto** de contrato (`Mdu_MDUID`, `INAux1`, `INAux2`,
  `PreMduPedId`, `OUTAux1`). Un `replace` descuidado ya rompió `PreMduPedId` una vez.
  El contrato está en `docs/PROMOCIONES_FIRESTORE.md`.
- **Anti-captura**: se pide y se libera por `ProteccionPantalla.adquirir()/liberar()`,
  que lleva un contador y hace el OR con la bandera `printScreen` del móvil. Nunca llames
  al plugin directo: en Android `FLAG_SECURE` es de la Activity, y apagarlo al salir de
  Promos dejaría descubierto al chofer que lo tenía prendido por configuración.
- **Firestore**: las colecciones llevan el escenario o el móvil en el nombre
  (`sessions-{escenario}`, `Pedidos-{escenario}`, `Moviles-{movil}`,
  `CoordenadasMoviles-{escenario}`). `Promociones` y `Constantes-1000` son top-level y
  las administra GeneXus.
- **Hive**: `sessionBox` se **borra en el logout**; `usuarioBox` **sobrevive** (ahí van
  el último usuario, la huella y las preferencias de UI). Si algo tiene que persistir
  entre sesiones, va en `usuarioBox`.
- **Constantes del backend**: `await getConstantValue('NNN')` (`lib/utils/constantes.dart`).
  `ValorEscenario<N>` pisa a `Valor`, `Estado != 'A'` devuelve `null`, y el valor `'-1'`
  también devuelve `null` a propósito.

**El lado Kotlin** vive en dos paquetes, y la división es histórica pero real:

- `com.example.moveit` → `MainActivity` (todos los `MethodChannel`), `BootReceiver`,
  helpers de ubicación;
- `com.riogas.appmovil` → lo agregado después: `tracking/` (servicio de GPS en primer
  plano, cola Room de fixes, workers), FCM, watchdog, loggers críticos.

Dart y Kotlin se hablan por `MethodChannel` con nombres fijos: `background_service`,
`device_info`, `apk_installer`, `network_location`, `com.riogas.appmovil/shared_prefs`,
`.../native_logs`, `.../service_status`. **Si tocás un canal, tocás los dos lados** — y
acordate de que el lado Kotlin no se puede compilar en matrix.

## Trampas conocidas

- **Firebase rompe 13 pruebas y no tiene arreglo**: usá el comando de "Cómo se prueba".
  Mockear `firebase_core` es imposible (Pigeon); ya se probó y se descartó.
- **`pubspec.lock` y `.flutter-plugins-dependencies` aparecen modificados solos** en
  matrix apenas corre `flutter pub get` o `flutter test`: el Flutter de matrix (3.35.4)
  resuelve versiones distintas de las que quedaron congeladas desde la PC. **No es
  trabajo de nadie y NO va a ningún commit**: dejalos afuera con `git add <archivo>`
  explícito, nunca `git add -A`.
- **`android/gradle.properties` tiene `org.gradle.java.home=C:\Program Files\Java\jdk-21`
  clavado a la PC de la persona.** Es un archivo versionado que solo sirve en Windows.
  No lo "arregles" para Linux: le romperías la compilación a quien publica.
- **El `applicationId` y el `namespace` son `com.example.moveit`.** Parece un descuido de
  plantilla y **no lo es**: cambiarlo convierte la app en otra distinta para Android y
  para Firebase, y la flota entera queda sin actualizaciones. No se toca.
- **`AppEnvironment.initialize()` fuerza producción en cada arranque** e ignora la
  preferencia guardada. Es a propósito. Si estás depurando algo de ambiente y "no toma la
  URL de dev", es esto: el cambio ocurre después del login y solo para usuarios
  especiales.
- **`lib/utils/config.dart` tiene un usuario y una contraseña de Firebase en texto
  plano.** Ya está en el repositorio y en el historial. No los rotes, no los muevas y no
  los "escondas" desde una tarea de la consola: eso deja a la flota entera sin poder
  escribir en Firestore. Es un tema para una persona.
- **`PersistentStreamManager` construye Firestore en el constructor del singleton**
  (`_instance`). Cualquier cosa que lo instancie temprano —o un widget que lo toque en un
  test— explota antes de `Firebase.initializeApp()`.
- **Archivos gigantes**: `login_page.dart` (138 KB), `home_page.dart` (99 KB),
  `order_detail_page.dart` (90 KB), `promociones_page.dart` (89 KB),
  `riogas_service.dart` (73 KB), `main.dart` (75 KB), `firebase_service.dart` (51 KB).
  **No los leas enteros**: ubicá con `grep -n` y leé la ventana que necesitás.
- **La raíz tiene ~100 archivos `.md`** (`FIX_*`, `ANALISIS_*`, `SISTEMA_*`…). Son
  bitácoras de arreglos viejos, no documentación vigente: sirven para entender por qué
  algo quedó así, **no** para saber cómo está hoy. La documentación viva es
  `docs/PROMOCIONES_FIRESTORE.md` y los doc-comments del código.
- **El remoto no tiene `main`**: solo `dev` (y `origin/HEAD → origin/dev`). El push va a
  `origin dev` y punto.
- **Hay dos números de versión y no coinciden**: `pubspec.yaml` dice `1.0.2+3` y
  `android/app/build.gradle` cae al fallback `versionCode 2070` / `versionName "1.1"`
  cuando Gradle corre sin las propiedades de Flutter. Lo que se publica de verdad lo
  define quien compila. **No toques ninguno de los dos** sin que lo pida la tarea.
- **Un valor desconocido en `ComoSeIngresaElCodigo` cae a `Manual` a propósito**: un error
  de carga en el documento tiene que degradar a un campo tecleable, nunca dejar la
  promoción inusable. No lo conviertas en un error.
- **El auto-update se baja e instala desde adentro de la app**: `ValidarVersion` /
  `DatosVersionActual` devuelven un `link`, la app lo baja con `dio.download` a un
  `app_update.apk` temporal y lo abre con `OpenFile.open` para que Android lo instale; al
  terminar **limpia `sessionBox`**. Es el único camino por el que se actualiza la flota:
  tocarlo mal deja teléfonos sin poder actualizarse y sin sesión.

## Qué no se toca

- **El keystore de firma** (`keystore/moveit.jks`, `keystore/key.properties`,
  `android/keystore/`). No está versionado, no está en matrix, y es **la** clave con la
  que se firma la flota: perderla o cambiarla obliga a reinstalar la app a mano en cada
  teléfono.
- **Publicar / desplegar la app: es tarea de una persona, no de una consola.** El circuito
  es compilar en la PC con el Android SDK, **firmar con el keystore** y subir el `.apk` a
  donde apunte el `link` que devuelve el backend (el bucket de **Firebase Storage** del
  proyecto `riogas-pedidos`), que es de donde la flota se auto-actualiza. Nada de eso se
  puede hacer ni simular desde matrix: no hay SDK, no hay JDK y no está el keystore. Una
  tarea que termina en "publicar" se cierra hasta el commit y se avisa que la publicación
  queda para una persona.
- **`android/app/google-services.json` y `lib/utils/firebase_options.dart`**: son la
  identidad de la app contra el proyecto Firebase `riogas-pedidos`. Se regeneran con
  FlutterFire, no se editan a mano.
- **Las credenciales de `lib/utils/config.dart`** (ver Trampas): no se rotan ni se mueven
  desde una tarea.
- **`UiPrefs.disenoNuevoHabilitado`**: es el interruptor único del rediseño 2026, hoy en
  `false` **por decisión expresa del usuario**. No lo prendas para "probar algo".
- **`applicationId` / `namespace` / `minSdk` / `targetSdk`** en `android/app/build.gradle`,
  y el `org.gradle.java.home` de `gradle.properties`.
- **Los números de versión** (`version:` del `pubspec.yaml`, `versionCode`/`versionName`
  del `build.gradle`).
- **`main` y `master`**: la consola trabaja en `dev` y vuelve a `dev`. A `main` la lleva
  una persona, a demanda.
- **Las reglas de seguridad de Firestore, la colección `Promociones` y las Constantes**:
  las administran GeneXus y operaciones desde el backend. Si un dato viene mal cargado,
  eso se avisa; no se compensa con un parche en la app —salvo que la tarea lo pida.
- **El contrato de los endpoints GeneXus** (nombres y casing de las claves de los bodies).
  Cambiarlo del lado de la app rompe la integración en silencio: primero se acuerda con
  quien mantiene SGM.
- **Los ~100 `.md` de la raíz**: son historia. No los borres, no los reescribas y no los
  actualices de paso.
