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
| `LabelCodCliente` | string | Label del campo código (ej. "PIN Antel"); vacío/ausente = campo oculto |
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

## APIs (⚠️ SIMULADAS hoy)

`lib/services/beneficios_service.dart` define el contrato — `validar()`,
`confirmarPin()`, `reenviarPin()`, `consumir()` — con implementación
simulada hasta que existan los endpoints GeneXus (marcados con
`TODO(GeneXus)`). Reglas de la simulación para demos:

| Código ingresado | Resultado |
|---|---|
| `0000` | "El código ingresado no es válido." |
| `1111` | "El cliente no tiene beneficios disponibles..." |
| `2222` | "El beneficio ya fue utilizado anteriormente." |
| `9999` | "No fue posible conectarse al servicio..." |
| Empieza con `9` | Requiere PIN por SMS (el PIN correcto es **123456**) |
| Cualquier otro | Beneficio directo: "20% de descuento en la compra." |

El consumo siempre devuelve OK con un código de autorización `AUT-XXXXXX`.

## Flujo en la app

1. Combo de promociones (vigentes + escenario habilitado) → campos dinámicos.
2. **Validar** (deshabilitado hasta completar los requeridos) → resultado:
   beneficio directo / requiere PIN (abre bottom sheet de 6 casillas con
   auto-avance, pegado, reenvío con cuenta regresiva y expiración 5 min) /
   error amigable.
3. **Consumir** (solo tras validación OK) → modal de confirmación con
   promoción/cliente/beneficio → tarjeta verde "Beneficio consumido" con
   autorización y fecha; el formulario queda bloqueado hasta
   "Nueva validación" (evita consumos duplicados).
