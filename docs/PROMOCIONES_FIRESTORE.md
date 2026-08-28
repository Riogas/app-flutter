# Promociones (beneficios de clientes) — esquema Firestore y flujo

La pantalla **Promociones** del rediseño (Home V2) permite al chofer
**validar y consumir beneficios del cliente** (Antel, Claro, OCA Metros,
etc.). La configuración de cada promoción viene de la colección Firestore
**top-level `Promociones`** (administrada por GeneXus).

## Documento de la colección `Promociones`

| Campo | Tipo | Uso en la app |
|---|---|---|
| `NombreCombo` | string | Valor mostrado en el combo de promociones |
| `Descripcion` | string | Subtítulo en el selector |
| `Estado` | string | Solo se leen documentos con `'A'` (filtro server-side) |
| `IdInterno` | int | Identificador que se envía a las APIs |
| `FechaDesde` / `FechaHasta` | timestamp | Vigencia; fuera del rango la promo no aparece |
| `EscenariosHabilitados` | array<string> | `["*"]` = todos; sino solo esos escenarios |
| `AgenciasHabilitadas` | array<string> | `["*"]` = todas (⚠️ aún no se evalúa: la app no conoce la agencia) |
| `LabelCodCliente` | string | Label del campo código (ej. "PIN Antel"); vacío/ausente = campo oculto (salvo que `ComoSeIngresaElCodigo` pida cámara) |
| `ComoSeIngresaElCodigo` | string | Cómo carga el código el usuario: `Manual` (campo de texto, default), `QR` o `CodigoBarras` (botón que abre la cámara). Ver abajo |
| `LabelCodTelCliente` | string | Label del campo teléfono; vacío = oculto |
| `LabelNomCliente` | string | Label del campo nombre; vacío = oculto |
| `LabelAuxIn1` | string | Label del campo auxiliar/observaciones; vacío = oculto |
| `ReqNomCliente` / `ReqAuxIn1` | string | `"Requerido"` u `"Opcional"` (default: opcional) |
| `ReqCodCliente` / `ReqCodTelCliente` | string | Ídem (default: **requerido** si el campo es visible) |
| `TelValores` | string | Texto de ayuda bajo el teléfono (ej. "Fijos y Celulares") |
| `LabelBotonValidar` | string | Texto del botón de validación (default "Validar") |
| `LabelBotonConsumir` | string | Texto del botón de consumo (default "Consumir beneficio") |
| `NotaAnteriorAlBotonValidar` | string | Nota informativa antes del botón (banner naranja) |

**Reglas de renderizado:** un campo se muestra solo si su `Label*` tiene
texto. Código y teléfono son requeridos por defecto; nombre y auxiliar son
opcionales por defecto. Los `Req*` explícitos ganan.

## 📷 `ComoSeIngresaElCodigo` — carga manual vs. cámara

| Valor | Qué ve el usuario |
|---|---|
| `Manual` (o vacío/ausente/desconocido) | Campo de texto, como siempre |
| `QR` | Botón **"Escanear código QR"** → cámara con marco cuadrado |
| `CodigoBarras` | Botón **"Escanear código de barras"** → cámara con marco apaisado (Code128/39/93, Codabar, EAN-8/13, ITF, UPC-A/E) |

El parseo (`lib/services/modo_ingreso_codigo.dart`) es tolerante: ignora
mayúsculas, acentos, espacios y guiones (`"Código de Barras"`,
`CODIGO_BARRAS` y `barcode` son todos `CodigoBarras`). **Un valor
desconocido cae en `Manual`**, para que un error de carga degrade a un campo
tecleable en vez de dejar la promoción inusable.

Cambia solo *cómo se obtiene* el código: lo escaneado viaja en el mismo
`CodigoCliente` de `promociones/ValidarPromo`, y la app **no interpreta el
contenido** (puede ser un número, una URL o un JSON: quien decide si sirve es
el servicio). Si el modo es de escaneo y falta `LabelCodCliente`, el campo se
muestra igual con un label por defecto.

Requisitos de dispositivo: permiso de cámara (se pide al abrir el escáner,
con acceso a los ajustes si quedó denegado para siempre) y una cámara
trasera. El reconocimiento es **on-device** (MLKit embebido): funciona sin
datos y no manda la imagen a ningún lado.

## 🔒 Anti-captura

La pantalla de Promociones y el escáner bloquean screenshot y grabación de
pantalla mientras están abiertos (`FLAG_SECURE` vía
`lib/services/proteccion_pantalla.dart`), porque muestran códigos de
beneficio y datos del cliente. Es independiente del flag `printScreen` del
móvil: ambas fuentes conviven con un contador, así que salir de Promos no
desprotege al chofer que ya lo tenía activado por configuración.

## APIs GeneXus

Los tres endpoints cuelgan de la **raíz de la webapp GX**, no de
`appservices/` (la app la deriva con `RioGasService.gxRootFromBaseUrl`):
dev `https://sgm.riogas.com.uy/promociones/...`. El `token` lo inyecta
`RioGasService._post`; ninguno reintenta desde la cola offline.

⚠️ **GeneXus responde 400 ante cualquier propiedad desconocida**, así que
los bodies van exactos (pasó con `escenarioid`, que el build deployado no
declara). `ok` se lee tolerante a mayúsculas: la firma lo declara en
minúscula pero el servicio devuelve `OK`. Convención: **0 = todo bien**,
cualquier otro valor es rechazo y `message` trae el motivo.

| Endpoint | In | Out |
|---|---|---|
| `ValidarPromo` | usuario, DeviceId, Departamento, Localidad, **Latitud**, **longitud**, idCampana, CodigoCliente, nombreCliente, telCliente, CampoIn1/2, INAux1/2, movil | OK, message, ReqValidacionSMS, LabelSMS, NroTrn, OUTAux1/2 |
| `ConsumirPromo` | usuario, DeviceId, movil, **PreMduId**, **PreMduCodSMS**, **Mdu_MduAutDir**, CampoIn1/2 | OK, message, OUTAux1/2 |
| `ReenviarSMS` | usuario, DeviceId, NroTrn | OK, message |
| `AnularPromo` | usuario, DeviceId, movil, **Mdu_MDUID**, INAux1/2 | OK, message, OUTAux1/2 |

- **`PreMduId` es el `NroTrn` de ValidarPromo**: el consumo confirma esa
  pre-registración, por eso no repite campaña, cliente ni teléfono.
- **`PreMduCodSMS`** es el PIN del SMS. No hay endpoint que lo confirme
  aparte, pero **tampoco hace falta: `ValidarPromo` devuelve el PIN en
  `OUTAux1`** y es exactamente el que recibe el cliente. Verificado contra un
  celular real: respuesta `OUTAux1:"9169"` ⇄ SMS *"Para validar la promo debe
  proporcionar al personal de Riogas el siguiente PIN: 9169."*. Por eso
  `registrarPin()` lo compara en el momento y el error sale ahí.
  - **El PIN es de 4 dígitos.** La pantalla igual toma el largo de `OUTAux1`,
    así que si mañana lo cambian acompaña sola (`kLargoPinPorDefecto` = 4 es
    solo el respaldo para cuando `OUTAux1` viene vacío).
  - **El SMS va al `telCliente` que manda la app**, no al teléfono guardado en
    el cupón (comprobado mandando el del propio equipo).
  - **`ReenviarSMS` reenvía el MISMO código**, no genera uno nuevo (se ve en
    el SMS: cambia el número emisor, el PIN no). Por eso la comparación local
    sigue siendo válida después de reenviar.
  - Ante un PIN equivocado el consumo responde **`OK:98 "No se pudo localizar
    la validación, vuelva a realizarla nuevamente."`** — un mensaje que hace
    pensar que se perdió la validación. No es así: la pre-registración sigue
    viva y **no hay límite de reintentos** (3 PIN errados y el correcto
    después consumió igual).
- **`Mdu_MduAutDir`** es la dirección del domicilio: al apretar Consumir se
  toma un fix GPS fresco y se resuelve calle y número por geoinversa contra
  el Nominatim propio (se recorta a 100 caracteres). El contrato del consumo
  **no tiene latitud/longitud** — las coordenadas viajan solo en la
  validación.

**La anulación es real** (`AnularPromo` con el `Mdu_MDUID` que devolvió el
consumo). Un consumo sin ese id no se puede anular desde la app.

🔴 **Bug abierto del lado GeneXus: los consumos con SMS no se pueden
anular.** En las campañas con `ReqValidacionSMS:'S'`, `ConsumirPromo` no
devuelve el `Mdu_MDUID` real sino un contador que arranca en 1 (`"1"`, `"2"`,
… en consumos sucesivos), y `AnularPromo` con ese id responde **HTTP 500**.
Aislado contra una campaña sin SMS en la misma corrida: devolvió
`Mdu_MDUID:"1372570"` y anuló con `OK:0 "Anulacion completada"`.

⚠️ **Gotcha de ambiente**: la elección "Desarrollo" del login la hace
`AppEnvironment.setEnvironmentForSession()` y **no persiste** —
`AppEnvironment.initialize()` arranca siempre en producción. Al reiniciar la
app la sesión sobrevive pero los requests se van a `www.riogas.uy/ica_geos_/`,
donde estos endpoints **no existen**: dan 404 y la pantalla dice "No fue
posible conectarse al servicio", sin ninguna pista del ambiente. Se corrige
volviendo a loguear (o desde el switch de Configuración).

## Flujo en la app

1. Combo de promociones (vigentes + escenario habilitado) → campos dinámicos.
2. **Validar** (deshabilitado hasta completar los requeridos) → resultado:
   beneficio directo / requiere PIN (bottom sheet con una casilla por dígito
   del PIN — 4 hoy, tomadas del largo de `OUTAux1` — con auto-avance, pegado,
   y reenvío con cuenta regresiva) / error amigable.
   - El PIN se **compara contra `OUTAux1` al confirmarlo**: si no coincide, la
     pantalla no se cierra, limpia las casillas y avisa *"El PIN no coincide
     con el que se envió por SMS"*. Al **segundo intento fallido se habilita
     el reenvío** sin esperar la cuenta regresiva.
   - Si `OUTAux1` viniera vacío no se puede comparar: se acepta el largo
     esperado y decide el server en el consumo (y ahí el mensaje confuso del
     `OK:98` se acompaña con una aclaración sobre el PIN).
3. **Consumir** (solo tras validación OK) → modal de confirmación con el
   **teléfono del cliente y, si se cargó, el nombre** (nada más: la promoción
   y el beneficio ya están a la vista detrás) → fix GPS fresco + geoinversa para la
   dirección → `ConsumirPromo` → tarjeta verde "Beneficio consumido" con
   autorización y fecha; el formulario queda bloqueado hasta
   "Nueva validación" (evita consumos duplicados).
   En **Promos del día** cada consumo muestra el chip **"Confirmado"** (verde)
   y el botón **"Anular promo"**. La ventana de anulación NO se muestra: el
   contador invitaba a tratar la anulación como parte del flujo normal.
   ⚠️ El consumo se puede anular desde "Promos del día" dentro de la ventana
   configurada — **salvo los de campañas con SMS**, por el bug del
   `Mdu_MDUID` descrito arriba.
