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

- **`PreMduId` es el `NroTrn` de ValidarPromo**: el consumo confirma esa
  pre-registración, por eso no repite campaña, cliente ni teléfono.
- **`PreMduCodSMS`** es el PIN del SMS. **No hay endpoint que lo valide
  antes**: se junta en la pantalla (`registrarPin`) y lo verifica el server
  dentro del consumo, así que un PIN equivocado se descubre al consumir.
- **`Mdu_MduAutDir`** es la dirección del domicilio: al apretar Consumir se
  toma un fix GPS fresco y se resuelve calle y número por geoinversa contra
  el Nominatim propio (se recorta a 100 caracteres). El contrato del consumo
  **no tiene latitud/longitud** — las coordenadas viajan solo en la
  validación.

**Sigue simulada la anulación** (`anular()`): no existe endpoint, así que
"Promos del día" marca el consumo como anulado **solo en el teléfono**
mientras el servidor lo mantiene consumido.

## Flujo en la app

1. Combo de promociones (vigentes + escenario habilitado) → campos dinámicos.
2. **Validar** (deshabilitado hasta completar los requeridos) → resultado:
   beneficio directo / requiere PIN (abre bottom sheet de 6 casillas con
   auto-avance, pegado, reenvío con cuenta regresiva y expiración 5 min) /
   error amigable.
3. **Consumir** (solo tras validación OK) → modal de confirmación con
   promoción/cliente/beneficio → fix GPS fresco + geoinversa para la
   dirección → `ConsumirPromo` → tarjeta verde "Beneficio consumido" con
   autorización y fecha; el formulario queda bloqueado hasta
   "Nueva validación" (evita consumos duplicados).
   ⚠️ **El consumo es irreversible desde la app** mientras no exista el
   endpoint de anulación.
