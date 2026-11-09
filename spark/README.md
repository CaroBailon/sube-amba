# El pipeline en PySpark (Databricks)

El mismo pipeline de la carpeta `sql/`, reescrito en **PySpark** para correr en **Databricks**, con arquitectura de medallón (bronze → silver → gold) y tablas Delta.

La lógica es idéntica a la de PostgreSQL y lo demuestra el último notebook: recalcula los hallazgos del proyecto y los compara con los que dio el análisis en SQL.

## Equivalencias

| Notebook | Capa | Equivale a | Qué hace |
|---|---|---|---|
| `00_config.py` | — | — | Crea el esquema `workspace.sube` y el volumen `crudos` donde se suben los CSV. |
| `01_bronze_carga.py` | Bronze | `01_cargar_crudos.sql` | Lee los 7 CSV como texto, guarda el archivo de origen de cada fila y carga los feriados. |
| `02_silver_limpieza.py` | Silver | `02_limpiar.sql` | Tipa y normaliza; aparta las cantidades negativas en `silver_usos_descartados`. |
| `03_gold_modelo_estrella.py` | Gold | `03_modelo_estrella.sql` | Arma `gold_dim_fecha`, `gold_dim_linea` (con `linea_canonica`), `gold_dim_empresa` y `gold_fact_usos`. |
| `04_controles_calidad.py` | — | `04_controles_calidad.sql` | 8 controles; si alguno falla, el notebook se detiene. |
| `05_preguntas_negocio.py` | — | `05_preguntas_negocio.sql` | Las 7 preguntas con funciones de ventana (`lag`, acumulados, promedio móvil, `pivot`) y la validación cruzada. |

## Qué cambia respecto de PostgreSQL

- **Modo ANSI.** Databricks corta el proceso ante una conversión inválida. Por eso las fechas se convierten con patrones explícitos y las cantidades con `try_cast`: un dato mal formado queda en `null` y lo detecta un control, en lugar de romper la carga.
- **`MODE() WITHIN GROUP`** no existe igual en Spark. Se reemplazó por una función `moda()` con ventana que desempata igual que PostgreSQL (gana el menor valor).
- **`REGEXP_MATCH`** se reemplazó por `rlike` + `regexp_extract`, cuidando que una línea sin número siga dando `null` y no un texto vacío.
- **`FILTER (WHERE ...)`** se reemplazó por `pivot`.
- **Claves sustitutas** (`linea_key`, `empresa_key`): pueden numerarse distinto que en PostgreSQL porque el orden alfabético depende de la configuración regional. No afecta ningún resultado.

## Validación

**En Databricks Free Edition, con los datos reales de SUBE** (descargados el 09/11/2026, hasta el 07/11/2026):

- **Bronze:** 3.235.523 filas en 7 archivos.
- **Silver:** 3.235.507 filas limpias + 16 descartadas, las mismas 16 cantidades negativas que en PostgreSQL. No se pierde ninguna fila.
- **Controles de calidad:** los 8 en OK.
- **Validación cruzada:** los 9 indicadores coinciden exactamente con PostgreSQL.

| Indicador | Databricks | PostgreSQL |
|---|---:|---:|
| P1 · AMBA, promedio por día hábil 2023 | 11.708.399 | 11.708.399 |
| P1 · AMBA, promedio por día hábil 2026 (hasta 30/10) | 9.132.417 | 9.132.417 |
| P2 · Colectivo, % de los viajes de 2025 | 85,5% | 85,5% |
| P3 · Feriado vs. día hábil | −65,2% | −65,2% |
| P4 · Líneas para llegar al 80% de los viajes | 183 | 183 |
| P5 · Subte, promedio por día hábil oct-2023 | 915.021 | 915.021 |
| P5 · Subte, promedio por día hábil oct-2025 | 499.923 | 499.923 |
| P6 · Mayor caída (09/05/2024) | −95,2% | −95,2% |
| P7 · Líneas traspasadas a CABA, variación | −1,7% | −1,7% |

El archivo de 2026 se actualiza seguido: por eso 2026 se compara con el mismo corte que tenía el análisis en PostgreSQL (30/10/2026). Con todos los días disponibles, el promedio de 2026 es 9.130.504.

Antes de correrlo en Databricks, los notebooks se probaron con Spark local en modo ANSI, sobre archivos con el formato crudo de SUBE: las 512 líneas del AMBA dieron la misma `linea_canonica` y los 997.666 totales por día y línea, los mismos valores que en PostgreSQL.

## Cómo correrlo en Databricks Free Edition

1. Creá una cuenta gratuita en [Databricks Free Edition](https://www.databricks.com/learn/free-edition).
2. **Traé los notebooks.** En *Workspace* → *Create* → *Git folder*, pegá `https://github.com/CaroBailon/sube-amba`. También se pueden importar los `.py` de esta carpeta con *Import*.
3. **Ejecutá `00_config`.** Crea el esquema `sube` y el volumen `crudos`.
4. **Subí los datos.** En *Catalog* → `workspace` → `sube` → `crudos` → *Upload to this volume*, subí los 7 CSV de SUBE (`dat-ab-usos-2020.csv` … `dat-ab-usos-2026.csv`, del [portal de datos abiertos](https://datos.transporte.gob.ar/dataset/sube-cantidad-de-transacciones-usos-por-fecha)) y `data/feriados_ar.csv` de este repo.
5. **Ejecutá los notebooks del 01 al 05 en orden.** Cada uno usa el cómputo serverless que trae Free Edition; no hace falta configurar un clúster.

`01` muestra las filas cargadas por archivo, `02` aparta 16 filas descartadas, `04` termina con todos los controles en OK y `05` cierra con la validación cruzada.
