# ¿Cómo se mueve el AMBA? 19.000 millones de viajes con SUBE (2020–2026)

**El AMBA viaja un 22% menos que en 2023, y el subte perdió la mitad de sus pasajeros de día hábil en dos años, después del aumento de tarifa de mayo de 2024.**

Análisis de los registros diarios de SUBE del Ministerio de Transporte, de punta a punta: carga y limpieza en PostgreSQL, modelo en estrella, preguntas de negocio en SQL y dashboard en Power BI.

![Resumen](dashboard/01_resumen.png)

## Hallazgos

| # | Hallazgo | Dato |
| --- | --- | --- |
| 1 | **La demanda tocó su máximo en 2023 y cae desde entonces.** | 11,7 millones de viajes por día hábil en 2023 → 9,1 millones en 2026 (-22%). |
| 2 | **El subte perdió la mitad de sus pasajeros.** La caída arranca con el aumento del 17/05/2024 ($125 → $574, +359%) y se profundiza durante un año. | 915.000 viajes por día hábil en oct-2023 → 500.000 en oct-2025. Peor mes: abr-2025 (-40% interanual). |
| 3 | **El colectivo sostiene la red.** | 85% de los viajes. El subte bajó del 6,8% (2023) al 4,7% (2025). |
| 4 | **Un feriado se comporta como un domingo, pero un "puente" no.** | Feriado -65% y domingo -68% vs. día hábil; día no laborable con fines turísticos, -47%. **Recomendación:** programar los puentes con frecuencia de sábado, no de domingo. |
| 5 | **Lo que define el impacto de un paro es si paran los colectivos.** | Paro general con colectivos (9/5/2024): -95% de viajes. Sin colectivos (10/4/2025): -47%. Una tormenta fuerte resta entre 35% y 38%. |

**Hallazgo de calidad de datos:** el 10/12/2021 aparece como una caída del 40%, pero no lo es. Ese día el transporte fue gratuito desde el mediodía por el acto del Día de la Democracia, y esos viajes no quedaron registrados. El subte, que no fue gratuito, subió un 9%. **SUBE mide viajes pagos, no viajes totales.**

## Dashboard

| Página | Qué muestra |
| --- | --- |
| **Resumen** | Indicadores por año, evolución mensual desde 2020 y reparto entre colectivo, tren y subte |
| **El subte** | Evolución mensual con el aumento de tarifa marcado y variación interanual desde 2024 |
| **Días atípicos** | Demanda por tipo de día y los 12 días hábiles con mayor caída, con su causa |

![El subte](dashboard/02_subte.png)
![Días atípicos](dashboard/03_dias_atipicos.png)

## Datos

- **Fuente:** [SUBE – Cantidad de transacciones (usos) por fecha](https://datos.transporte.gob.ar/dataset/sube-cantidad-de-transacciones-usos-por-fecha), Ministerio de Transporte.
- 3,2 millones de registros diarios por línea y empresa, del 01/01/2020 al 30/10/2026, de todo el país. El análisis se centra en el AMBA.
- Feriados nacionales armados a partir de las comunicaciones del BCRA.
- Causas de los días atípicos verificadas en medios de prensa.

## Cómo está hecho

```
CSV (7 archivos) ──► raw (texto crudo) ──► stg (limpio) ──► dw (modelo en estrella) ──► Power BI
                   01_cargar_crudos     02_limpiar        03_modelo_estrella        06_exportar_powerbi
                                                          04_controles_calidad
                                                          05_preguntas_negocio
```

- **PostgreSQL:** carga, limpieza, modelado y 7 preguntas de negocio (CTEs, funciones de ventana como `LAG`, `SUM OVER`, promedios móviles, y comparación contra un grupo de control).
- **Modelo en estrella:** `fact_usos` + `dim_fecha` (con feriados y tipo de día) + `dim_linea` + `dim_empresa`.
- **Power BI:** modelo con relaciones, medidas DAX (promedio por día hábil, variación interanual con `SAMEPERIODLASTYEAR`, % del total) y 3 páginas.

### El desafío de limpieza principal

La misma línea aparece con nombres distintos según el año. Cuando 31 líneas de colectivo pasaron de jurisdicción nacional a la Ciudad (enero de 2025), la línea 39 pasó de llamarse `BSAS_LINEA_039` a `CABA_LINEA_39`. Construí una clave canónica que unifica 512 nombres en 453 líneas del AMBA y permite seguirlas en el tiempo. Todas las decisiones están en [docs/decisiones_de_limpieza.md](docs/decisiones_de_limpieza.md).

### Controles de calidad

El total de usos se verifica en cada etapa (crudo − descartado = modelo final), sin días faltantes en el calendario. Ver `sql/04_controles_calidad.sql`. El análisis de días atípicos (P6) además detectó un feriado nacional que faltaba en la tabla de feriados (02/09/2022), que se corrigió.

## Preguntas de negocio (`sql/05_preguntas_negocio.sql`)

1. ¿Volvió el AMBA a viajar como antes de la pandemia?
2. ¿Cómo se reparte la demanda entre colectivo, tren y subte?
3. ¿Cuánto cae la demanda en feriados y fines de semana?
4. ¿Qué líneas concentran la demanda? *El 80% de los viajes lo hacen 183 de 391 líneas: la demanda está menos concentrada que la regla 80/20.*
5. ¿Cómo evolucionó el subte y cuánto cambió contra el año anterior?
6. ¿Qué días hábiles tuvieron caídas anómalas y por qué?
7. ¿Cambió la demanda de las 31 líneas traspasadas a la Ciudad? *No: -1,7% contra -2,5% del resto en el mismo período.*

## Cómo reproducirlo

Ver [docs/instalacion_windows.md](docs/instalacion_windows.md). En resumen: instalar PostgreSQL, copiar los CSV en `data/raw/` y ejecutar `ejecutar_todo.bat`. Los archivos que usa Power BI están en `dashboard/datos/` (se regeneran con `sql/06_exportar_powerbi.sql`).

## Estructura

```
sube-amba/
├── data/
│   ├── raw/                     ← los CSV de SUBE (no se suben a GitHub por tamaño)
│   ├── feriados_ar.csv
│   └── dias_atipicos.csv        ← causas de los 12 días atípicos
├── sql/
│   ├── 01_cargar_crudos.sql
│   ├── 02_limpiar.sql
│   ├── 03_modelo_estrella.sql
│   ├── 04_controles_calidad.sql
│   ├── 05_preguntas_negocio.sql
│   └── 06_exportar_powerbi.sql
├── dashboard/
│   ├── sube_amba.pbix
│   ├── 01_resumen.png, 02_subte.png, 03_dias_atipicos.png
│   └── datos/                   ← CSV que usa Power BI (solo AMBA)
├── docs/
│   ├── decisiones_de_limpieza.md
│   └── instalacion_windows.md
└── ejecutar_todo.bat
```

---
Carolina Bailon Trujillo · [LinkedIn](https://www.linkedin.com/in/carolina-bailon-trujillo-18334a36b/) · bailontrujillocarolina@gmail.com
