# Promociones — esquema Firestore

La pantalla **Promociones** del rediseño (Home V2) lee la colección
**`Promociones-{escenario}`** (ej.: `Promociones-1000`, `Promociones-2000`)
en el mismo Firestore que ya usa la app. Hoy no hay backend que la escriba:
los documentos se cargan a mano desde la consola de Firebase (o desde
GeneXus cuando exista el proceso).

## Documento

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| `Titulo` | string | ✅ | Título de la promo ("Completá 10 entregas hoy") |
| `Descripcion` | string | — | Texto descriptivo |
| `TipoMeta` | string | ✅ | `entregas_dia` (desafío con barra de progreso contra las entregas de hoy) o `info` (campaña informativa sin progreso) |
| `MetaCantidad` | number | solo si `entregas_dia` | Meta de entregas del día (ej. 10) |
| `Premio` | string | — | Texto del premio ("Bono adicional") |
| `FchDesde` | number | ✅ | Vigencia desde, int AAAAMMDD (ej. 20260721) |
| `FchHasta` | number | ✅ | Vigencia hasta, int AAAAMMDD inclusive |
| `VisibleEnApp` | string | ✅ | `'S'` para mostrarla (la query filtra por este campo) |
| `Movil` | number | — | Si está y ≠ 0, la promo solo la ve ese móvil. Ausente o 0 = todos |

## Comportamiento en la app

- El filtro de vigencia (`FchDesde`/`FchHasta`, fecha operativa base UTC-3) y
  el de `Movil` se aplican en el cliente (`PersistentStreamManager`).
- El **progreso** de los desafíos `entregas_dia` se calcula contra las
  entregas reales del día del móvil (`Pedidos-{escenario}` con
  `EstadoNro == 2` y `FchPara == hoy`).
- El **badge** del tab Promos marca las promos vigentes que el chofer todavía
  no abrió (caja Hive local `promocionesVistasBox`).

## Ejemplo

```json
{
  "Titulo": "Completá 10 entregas hoy",
  "Descripcion": "Llegá a 10 entregas en el día y ganá un bono adicional.",
  "TipoMeta": "entregas_dia",
  "MetaCantidad": 10,
  "Premio": "Bono adicional",
  "FchDesde": 20260721,
  "FchHasta": 20260731,
  "VisibleEnApp": "S"
}
```
