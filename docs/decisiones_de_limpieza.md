# Decisiones de limpieza

Este documento explica qué encontré al explorar los datos, qué hice con cada problema y por qué. Cada decisión cambia los números del análisis, así que quedan registradas para poder revisarlas o revertirlas.

## Fuente

- **Dataset:** SUBE – Cantidad de transacciones (usos) por fecha. Ministerio de Transporte de la Nación.
- **URL:** https://datos.transporte.gob.ar/dataset/sube-cantidad-de-transacciones-usos-por-fecha
- **Período:** 01/01/2020 al 30/10/2026 (2.495 días).
- **Volumen:** 3.221.807 filas en 7 archivos CSV, uno por año.
- **Grano:** una fila = cantidad de usos de una línea, de una empresa, en un día.
- **Cobertura:** todo el país, no solo el AMBA (columna `AMBA` = SI/NO).

## Diccionario de datos original

| Columna | Qué es | Observaciones |
| --- | --- | --- |
| DIA_TRANSPORTE | Fecha | Sin errores; no falta ningún día |
| NOMBRE_EMPRESA | Empresa operadora | 409 empresas; espacios de más en más de 40.000 filas |
| LINEA | Nombre de la línea | 2.480 nombres; **sin formato estándar** (ver abajo) |
| AMBA | Si la línea es del AMBA | SI / NO |
| TIPO_TRANSPORTE | Modo | COLECTIVO, TREN, SUBTE, LANCHAS |
| JURISDICCION | Quién regula la línea | NACIONAL, PROVINCIAL, MUNICIPAL, C.A.B.A; vacía en el subte |
| PROVINCIA | Provincia | 'JN' = líneas nacionales del AMBA; la Ciudad escrita de 3 formas |
| MUNICIPIO | Municipio | 'SN' y 'SD' = sin dato (el 60% de las filas) |
| CANTIDAD | Cantidad de usos | 16 negativos, 41 ceros |
| DATO_PRELIMINAR | Si el dato puede corregirse | 'SI' desde febrero de 2026 |

## Problemas encontrados y decisiones

| # | Problema | Filas afectadas | Decisión | Por qué |
| --- | --- | --- | --- | --- |
| 1 | Cantidades negativas | 16 (todas de trenes) | Se apartan a `stg.usos_descartados` | Parecen anulaciones o correcciones; un viaje no puede ser negativo. Suman -796 usos sobre 24.000 millones: impacto nulo, pero queda registro |
| 2 | Cantidades en cero | 41 | Se mantienen | Un día sin viajes en un ramal chico (lanchas, ramales del Mitre) es plausible |
| 3 | Espacios dobles o al borde en nombres de empresa | más de 40.000 | `TRIM` + reemplazar espacios múltiples por uno | Sin esto, la misma empresa aparece como dos distintas |
| 4 | La Ciudad escrita de 3 formas en PROVINCIA | ~18.200 | Se unifica como `CABA` | Para poder agrupar |
| 5 | Subte sin jurisdicción ni provincia | 17.566 | Se completa con `CABA` | El subte es de la Ciudad; el dato faltante es sistemático, no aleatorio |
| 6 | Tildes inconsistentes ("NEUQUÉN" pero "CORDOBA") | — | Se sacan las tildes de provincia y municipio | Para que no haya duplicados por escritura |
| 7 | 'SN' y 'SD' en MUNICIPIO | ~1,9 millones | Se convierten en `NULL` | Son faltantes, no municipios. Contarlos como municipio inflaría un "municipio fantasma" |
| 8 | **Líneas que cambian de nombre** | ver abajo | Columna `linea_canonica` en `dim_linea` | Sin esto, no se puede seguir una línea en el tiempo |

## El problema más importante: los nombres de línea

El campo `LINEA` no tiene un formato estándar. La misma línea aparece escrita de formas distintas, y además **cambia de nombre** cuando cambia de jurisdicción:

- **Traspaso de 31 líneas a la Ciudad (enero–febrero 2025).** Por ejemplo, la línea 39 figura como `BSAS_LINEA_039` (jurisdicción NACIONAL) hasta el 01/02/2025, y desde el 31/01/2025 como `CABA_LINEA_39` (jurisdicción CABA). Si no se unifican, parece que 31 líneas desaparecieron y aparecieron otras 31.
- **Formatos distintos para la misma línea:** `LINEA 44`, `CABA_LINEA_ 44`, `BSAS_LINEA_044`, `BSAS_LINEA303`, `LINEA_119_AMBA`.
- **Subte:** la línea C aparece como `LINEA SUBTE C` y desde septiembre de 2025 también como `LIN_AMARILLA_C`.
- **Trenes:** cada ramal es una "línea" distinta (`FFCC_MITRE_ZARATE`, `FCC MITRE_TIGRE`, `FFCC_SUAREZ`…).

**Regla aplicada (solo en el AMBA):**

- **Colectivos:** se extrae el número y la letra (`BSAS_LINEA_044` → `Línea 44`). Las líneas municipales repiten números entre municipios (hay una línea "1" en Mercedes), así que se les agrega el municipio: `Línea 503 (Florencio Varela)`.
- **Subte:** por letra (`Subte A` … `Subte H`, `Premetro`).
- **Trenes:** por línea (`Tren Mitre`, `Tren Roca`, etc.), agrupando ramales.

Resultado: 484 nombres de colectivos del AMBA quedan en 438 líneas; 19 ramales de tren, en 8 líneas; 9 nombres de subte, en 7 líneas.

**Fuera del AMBA no se unifica**, porque el mismo número corresponde a líneas distintas en cada ciudad. Además, en mayo de 2026 Mendoza empezó a informar cada ramal por separado (`749 F`, `749 G`…), por lo que **no conviene analizar líneas individuales del interior a lo largo del tiempo**: solo totales por provincia.

## Limitaciones a tener en cuenta en el análisis

1. **Datos preliminares.** Desde febrero de 2026 hay filas marcadas como preliminares. Los meses recientes pueden corregirse.
2. **2026 está incompleto** (hasta el 30/10). Para comparar años, usar el mismo período (por ejemplo, enero–octubre) o promedios diarios, nunca totales anuales.
3. **Municipio casi siempre falta.** Las líneas provinciales y nacionales que circulan por La Plata (por ejemplo, la 214 o la 273) no tienen municipio. Un análisis "La Plata" con este dataset solo puede usar las líneas municipales de La Plata.
4. **Usos ≠ personas.** Una persona que combina colectivo y tren genera 2 usos.
5. **Algunas empresas informan varios ramales juntos.** Por ejemplo, `Línea 501G (Moreno)` promedia ~120.000 usos diarios, mucho más que una línea típica.
6. **24 y 31 de diciembre** no son feriados oficiales, pero la demanda cae ~50%. Se clasifican como "Hábil"; se puede agregar como categoría propia si hace falta.

## Feriados

`data/feriados_ar.csv` se armó a partir de las comunicaciones "C" del BCRA sobre feriados de cada año (2020–2026). Tipos:

- `feriado`: feriado nacional (inamovible o trasladable).
- `puente`: día no laborable con fines turísticos.
- `no_laborable`: Jueves Santo.
- `extraordinario`: Censo 2022 (18/05/2022), feriado por el atentado a la Vicepresidenta (02/09/2022, DNU 573/2022) y festejos del Mundial (20/12/2022).

## Controles de calidad (`sql/04_controles_calidad.sql`)

| Control | Resultado |
| --- | --- |
| Total crudo − descartado = total del modelo (24.010.376.519 usos) | OK |
| Filas crudas = limpias + descartadas | OK |
| Calendario sin días faltantes | OK |
| Todos los días tienen datos | OK |
| Subte: 7 líneas canónicas | OK |
| Trenes AMBA: 8 líneas canónicas | OK |
