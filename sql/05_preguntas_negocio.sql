-- =====================================================================
-- 05_preguntas_negocio.sql  ←  ESTE ES TU ARCHIVO, Carolina
--
-- Cada pregunta tiene: qué se quiere saber, por qué le importa a alguien,
-- qué técnica SQL practica y una pista. Escribí tu consulta debajo,
-- correla en DBeaver y anotá el resultado en el comentario "Hallazgo".
--
-- Tablas disponibles (esquema dw):
--   fact_usos   (fecha, linea_key, empresa_key, jurisdiccion, cantidad, dato_preliminar)
--   dim_fecha   (fecha, anio, trimestre, mes, nombre_mes, inicio_mes, dia_semana_num,
--                dia_semana, es_fin_de_semana, nombre_feriado, tipo_feriado, tipo_dia)
--   dim_linea   (linea_key, linea_original, linea_canonica, modo, region, es_amba,
--                jurisdiccion_principal, provincia_principal, municipio_principal,
--                primer_dia, ultimo_dia)
--   dim_empresa (empresa_key, empresa)
--
-- Regla de oro: 2026 llega hasta el 30/10. Para comparar años usá
-- PROMEDIOS DIARIOS, no totales.
-- =====================================================================


-- ---------------------------------------------------------------------
-- P1. ¿Volvió el AMBA a viajar como antes de la pandemia?
-- Para quién: planificación de transporte (¿cuánta oferta hace falta?).
-- Técnica: JOIN + GROUP BY + agregación.
-- Pista: promedio de usos por DÍA HÁBIL en el AMBA, por año.
--   1) Primero sumá usos por fecha (subconsulta o CTE), filtrando es_amba y tipo_dia = 'Hábil'.
--   2) Después promediá esas sumas diarias por año.
--   Ojo: si hacés AVG(cantidad) directo sobre fact_usos, promediás filas
--   (línea-día), no días. Es el error más común: pensá por qué da distinto.
-- Nota: el dataset arranca en enero de 2020, así que el "antes de la
-- pandemia" son solo enero, febrero y la primera mitad de marzo de 2020.
-- ---------------------------------------------------------------------

WITH por_dia AS (
    SELECT f.anio,
           f.fecha,
           SUM(u.cantidad) AS usos
    FROM dw.fact_usos u
    JOIN dw.dim_fecha f ON f.fecha = u.fecha
    JOIN dw.dim_linea l ON l.linea_key = u.linea_key
    WHERE l.es_amba
      AND f.tipo_dia = 'Hábil'
    GROUP BY f.anio, f.fecha
)
SELECT anio, ROUND(AVG(usos)) AS promedio_diario
FROM por_dia
GROUP BY anio
ORDER BY anio;

-- Resultado (promedio de usos por día hábil, AMBA):
--   2020:  5.072.557 | 2021:  7.646.893 | 2022: 11.086.793 | 2023: 11.708.399
--   2024: 10.834.747 | 2025: 10.215.821 | 2026:  9.132.417 (hasta 30/10)
-- Hallazgo: la demanda tocó su máximo en 2023 (11,7 millones de usos por día
-- hábil) y desde entonces cae todos los años: en 2026 está un 22% por debajo de 2023.


-- ---------------------------------------------------------------------
-- P2. ¿Cómo se reparte la demanda entre colectivo, tren y subte, y cómo cambió?
-- Para quién: inversión en infraestructura.
-- Técnica: función de ventana  SUM(...) OVER (PARTITION BY ...)  para el % del total.
-- Pista: usos por año y modo; después
--   100.0 * usos / SUM(usos) OVER (PARTITION BY anio)
-- ---------------------------------------------------------------------

WITH por_modo AS (
    SELECT f.anio, l.modo, SUM(u.cantidad) AS usos
    FROM dw.fact_usos u
    JOIN dw.dim_fecha f ON f.fecha = u.fecha
    JOIN dw.dim_linea l ON l.linea_key = u.linea_key
    WHERE l.es_amba
    GROUP BY f.anio, l.modo
)
SELECT anio, modo, usos,
       ROUND(100.0 * usos / SUM(usos) OVER (PARTITION BY anio), 1) AS pct_del_anio
FROM por_modo
ORDER BY anio, usos DESC;

-- Resultado (% de los usos del AMBA):
--          Colectivo  Tren   Subte
--   2020:    86,0%    9,1%   4,8%
--   2023:    83,8%    9,4%   6,8%
--   2025:    85,5%    9,8%   4,7%
-- Hallazgo: el colectivo concentra ~85% de los viajes. Entre 2023 y 2025 el
-- subte perdió el 40% de sus usos (240 -> 143 millones), contra -12% del
-- colectivo y -10% del tren: su participación volvió al nivel de la pandemia.
-- Hipótesis a confirmar en P5: los aumentos de tarifa del subte de 2024.


-- ---------------------------------------------------------------------
-- P3. ¿Cuánto cae la demanda en un feriado, un sábado y un domingo
--     comparado con un día hábil?
-- Para quién: armado de frecuencias y cronogramas.
-- Técnica: CTE + agregación por categoría + comparación contra una base.
-- Pista: promedio de usos diarios por tipo_dia (AMBA, 2023–2025).
--   Para el % vs hábil podés usar una subconsulta escalar o
--   MAX(CASE WHEN tipo_dia = 'Hábil' THEN prom END) OVER ()
-- ---------------------------------------------------------------------

WITH por_dia AS (
    SELECT f.fecha, f.tipo_dia, SUM(u.cantidad) AS usos
    FROM dw.fact_usos u
    JOIN dw.dim_fecha f ON f.fecha = u.fecha
    JOIN dw.dim_linea l ON l.linea_key = u.linea_key
    WHERE l.es_amba
      AND f.anio BETWEEN 2023 AND 2025
    GROUP BY f.fecha, f.tipo_dia
),
por_tipo AS (
    SELECT tipo_dia, COUNT(*) AS dias, ROUND(AVG(usos)) AS promedio_diario
    FROM por_dia
    GROUP BY tipo_dia
)
SELECT tipo_dia, dias, promedio_diario,
       ROUND(100.0 * promedio_diario
             / MAX(CASE WHEN tipo_dia = 'Hábil' THEN promedio_diario END) OVER ()
             - 100, 1) AS dif_vs_habil_pct
FROM por_tipo
ORDER BY promedio_diario DESC;

-- Resultado (AMBA, 2023-2025):
--   Hábil         734 días   10.920.268 usos/día    0,0%
--   Sábado        152 días    6.848.191            -37,3%
--   No laborable   12 días    5.793.289            -46,9%
--   Feriado        48 días    3.795.094            -65,2%
--   Domingo       150 días    3.514.292            -67,8%
-- Hallazgo: un feriado se comporta como un domingo (-65% vs. día hábil).
-- Los días no laborables "puente" quedan a mitad de camino (-47%): mucha
-- gente igual trabaja. Recomendación: programar los puentes con frecuencia
-- de sábado, no de domingo.


-- ---------------------------------------------------------------------
-- P4. ¿Qué líneas de colectivo concentran la demanda? (análisis de Pareto)
-- Para quién: control de subsidios y prioridades de fiscalización.
-- Técnica: ventana con acumulado  SUM(...) OVER (ORDER BY ... ROWS UNBOUNDED PRECEDING).
-- Pista: usos por linea_canonica en 2025 (colectivos del AMBA), ordenados de mayor a menor;
--   calculá el % acumulado. ¿Cuántas líneas hacen el 50% de los viajes? ¿Y el 80%?
-- ---------------------------------------------------------------------

WITH por_linea AS (
    SELECT l.linea_canonica, SUM(u.cantidad) AS usos
    FROM dw.fact_usos u
    JOIN dw.dim_fecha f ON f.fecha = u.fecha
    JOIN dw.dim_linea l ON l.linea_key = u.linea_key
    WHERE l.es_amba
      AND l.modo = 'COLECTIVO'
      AND f.anio = 2025
    GROUP BY l.linea_canonica
),
acumulado AS (
    SELECT linea_canonica, usos,
           ROW_NUMBER() OVER (ORDER BY usos DESC) AS ranking,
           COUNT(*)     OVER ()                  AS total_lineas,
           ROUND(100.0 * SUM(usos) OVER (ORDER BY usos DESC ROWS UNBOUNDED PRECEDING)
                 / SUM(usos) OVER (), 1)         AS pct_acumulado
    FROM por_linea
)
SELECT *
FROM acumulado
WHERE ranking <= 10                                                         -- el top 10
   OR ranking = (SELECT MIN(ranking) FROM acumulado WHERE pct_acumulado >= 50)  -- dónde se llega al 50%
   OR ranking = (SELECT MIN(ranking) FROM acumulado WHERE pct_acumulado >= 80)  -- dónde se llega al 80%
ORDER BY ranking;

-- Resultado (colectivos del AMBA, 2025: 391 líneas):
--   Top 5: 501G (Moreno) 47,6 M | 60: 36,4 M | 203: 33,3 M | 365: 32,7 M | 324: 27,9 M
--   El top 10 suma el 11,6% de los viajes.
--   50% de los viajes -> 83 líneas (21% de las líneas)
--   80% de los viajes -> 183 líneas (47% de las líneas)
-- Hallazgo: la demanda está MENOS concentrada que la regla 80/20: hace falta
-- casi la mitad de las líneas para llegar al 80% de los viajes. No hay un
-- puñado de líneas "críticas"; la red depende de muchas líneas medianas.
-- Ojo: la "501G (Moreno)" probablemente agrupa varios ramales informados juntos.


-- ---------------------------------------------------------------------
-- P5. ¿Cómo evolucionó el subte mes a mes, y cuánto cambió contra el mismo
--     mes del año anterior?
-- Para quién: el área tarifaria (el subte tuvo fuertes aumentos en 2024).
-- Técnica: LAG() para la variación interanual.
-- Pista: promedio diario por mes (inicio_mes) para modo = 'SUBTE';
--   LAG(prom, 12) OVER (ORDER BY inicio_mes) te da el mismo mes del año anterior.
-- ---------------------------------------------------------------------

WITH por_dia AS (
    SELECT f.fecha, f.inicio_mes, SUM(u.cantidad) AS usos
    FROM dw.fact_usos u
    JOIN dw.dim_fecha f ON f.fecha = u.fecha
    JOIN dw.dim_linea l ON l.linea_key = u.linea_key
    WHERE l.es_amba
      AND l.modo = 'SUBTE'
      AND f.tipo_dia = 'Hábil'
    GROUP BY f.fecha, f.inicio_mes
),
por_mes AS (
    SELECT inicio_mes, ROUND(AVG(usos)) AS prom_diario
    FROM por_dia
    GROUP BY inicio_mes
)
SELECT inicio_mes,
       prom_diario,
       LAG(prom_diario, 12) OVER (ORDER BY inicio_mes) AS mismo_mes_anio_anterior,
       ROUND(100.0 * prom_diario / LAG(prom_diario, 12) OVER (ORDER BY inicio_mes) - 100, 1) AS var_interanual_pct
FROM por_mes
ORDER BY inicio_mes;
-- Ojo: el LAG se calcula ANTES de cualquier WHERE sobre el resultado. Si
-- filtraras inicio_mes >= '2023-01-01' en por_mes, los primeros 12 meses
-- quedarían sin comparación. Por eso el filtro, si lo querés, va afuera.

-- Resultado (promedio de usos del subte por día hábil, meses seleccionados):
--   oct-2023: 915.021 | oct-2024: 671.163 (-26,7%) | oct-2025: 499.923 (-25,5%) | oct-2026: 460.667 (-7,9%)
--   abr-2024 fue el último mes con crecimiento interanual (+5,2%).
--   De jun-2024 a dic-2025, todos los meses caen entre 14% y 40% contra el año
--   anterior; el peor fue abr-2025 (-40,0%).
-- Hallazgo: el subte perdió la mitad de sus pasajeros de día hábil en dos años
-- (915 mil en oct-2023 -> 500 mil en oct-2025). La caída empieza a mediados
-- de 2024 y en 2026 se modera (de -16% en febrero a -8% en octubre): la demanda
-- parece estar tocando un piso.
--
-- Aumentos de tarifa del subte en 2024 (para marcar en el gráfico):
--   17-may-2024: $125 -> $574 (+359%, primer tramo; estaba previsto para el 1/5)
--   01-jun-2024: $574 -> $650 (segundo tramo)
--   ago-2024:    tercer tramo, con tarifa diferenciada para SUBE no registrada
-- Los datos acompañan las fechas: abr-2024 todavía crecía (+5,2%), may-2024
-- (medio mes con tarifa nueva) cae -6,7% y jun-2024 (mes completo) -15,0%.
-- La pérdida sigue profundizándose hasta abr-2025 (-40%): el efecto no fue
-- un salto puntual sino una caída sostenida durante un año.


-- ---------------------------------------------------------------------
-- P6. ¿Qué días hábiles tuvieron caídas anómalas y por qué?
-- Para quién: medir el impacto de paros y eventos.
-- Técnica: ventana con promedio móvil  AVG(...) OVER (ORDER BY fecha ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING).
-- Pista: compará cada día hábil con el promedio de los 7 días hábiles anteriores.
--   Listá los 10 peores y buscá en las noticias qué pasó (paros generales,
--   paros de la UTA, cortes de servicio). Ya hay una versión simple al final
--   de 04_controles_calidad.sql: mejorala.
-- ---------------------------------------------------------------------

WITH por_dia AS (
    SELECT f.fecha, f.dia_semana, SUM(u.cantidad) AS usos
    FROM dw.fact_usos u
    JOIN dw.dim_fecha f ON f.fecha = u.fecha
    JOIN dw.dim_linea l ON l.linea_key = u.linea_key
    WHERE l.es_amba
      AND f.tipo_dia = 'Hábil'
      AND NOT (f.mes = 12 AND EXTRACT(DAY FROM f.fecha) IN (24, 31))  -- Nochebuena y fin de año
    GROUP BY f.fecha, f.dia_semana
),
con_base AS (
    SELECT fecha, dia_semana, usos,
           AVG(usos) OVER (ORDER BY fecha ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS prom_7_previos
    FROM por_dia
)
SELECT fecha, dia_semana, usos,
       ROUND(prom_7_previos) AS prom_7_previos,
       ROUND(100.0 * usos / prom_7_previos - 100, 1) AS caida_pct
FROM con_base
WHERE fecha >= '2020-07-01'   -- excluye el inicio de la cuarentena (marzo-junio 2020)
ORDER BY caida_pct
LIMIT 12;

-- Resultado y causa de cada caída (AMBA, días hábiles):
--   2024-05-09  -95,2%  Paro general de la CGT (con adhesión del transporte)
--   2026-02-19  -91,6%  Paro general de la CGT contra la reforma laboral; adhirieron UTA y trenes
--   2023-07-07  -79,2%  Paro nacional de colectivos de la UTA (se levantó a las 17:30)
--   2025-05-06  -72,7%  Paro de colectivos de la UTA (DOTA siguió circulando)
--   2024-04-11  -66,7%  ~140 líneas paradas por falta de pago del aumento salarial
--   2025-04-10  -46,7%  Paro general de la CGT: sin trenes ni subte, colectivos funcionando
--   2021-12-10  -40,0%  NO es una caída real: colectivos y trenes fueron GRATIS desde las
--                       12 h por el acto del Día de la Democracia, y esos viajes no se
--                       registraron en SUBE. El subte (de la Ciudad, no gratuito) subió +9%.
--   2024-01-24  -37,9%  Paro general de la CGT (desde el mediodía)
--   2025-08-19  -37,8%  Temporal de lluvia (pico del temporal pronosticado para ese día)
--   2024-03-12  -35,2%  Temporal récord: 125 mm, inundaciones y una víctima fatal
--   2025-05-16  -35,0%  Temporal con alerta naranja e inundaciones en el conurbano
--   2024-10-30  -31,4%  Paro nacional de transporte (trenes y subte)
-- Cómo se diagnosticó: abriendo cada caída por modo. Un paro afecta a UN modo
-- (el que para); una tormenta baja TODOS los modos parecido (-20% a -40%);
-- y si un modo SUBE mientras otros caen, sospechar de un problema en el dato.
--
-- Hallazgo: la variable que más explica la caída es si paran los COLECTIVOS.
-- Un paro general con colectivos (9/5/2024) borra el 95% de los viajes; uno
-- sin colectivos (10/4/2025) solo el 47%, porque el colectivo es el 85% de la red.
-- Nota: esta consulta encontró un feriado que faltaba en la tabla (2/9/2022,
-- DNU 573/2022), que se agregó a data/feriados_ar.csv.
-- Hallazgo de calidad de datos: los días de transporte gratuito (10/12/2021)
-- aparecen como caídas falsas. SUBE mide viajes PAGOS, no viajes totales.
-- Las tormentas fuertes restan entre 35% y 38% de los viajes del día.


-- ---------------------------------------------------------------------
-- P7 (bonus). Las 31 líneas traspasadas a la Ciudad en 2025:
--     ¿cambió su demanda después del traspaso?
-- Para quién: evaluación de una política pública.
-- Técnica: filtrar con subconsulta (líneas con algún nombre que empiece con 'CABA_')
--   y comparar períodos equivalentes (feb–oct 2024 vs feb–oct 2025).
-- Pista: compará contra el resto de los colectivos del AMBA en el mismo período,
--   porque si TODO bajó, la baja no se explica por el traspaso.
-- ---------------------------------------------------------------------

WITH lineas_traspasadas AS (
    SELECT DISTINCT linea_canonica
    FROM dw.dim_linea
    WHERE es_amba AND modo = 'COLECTIVO' AND linea_original LIKE 'CABA%'
),
por_dia AS (
    SELECT f.anio, f.fecha,
           CASE WHEN t.linea_canonica IS NOT NULL THEN 'Traspasadas a CABA'
                ELSE 'Resto AMBA' END AS grupo,
           SUM(u.cantidad) AS usos
    FROM dw.fact_usos u
    JOIN dw.dim_fecha f ON f.fecha = u.fecha
    JOIN dw.dim_linea l ON l.linea_key = u.linea_key
    LEFT JOIN lineas_traspasadas t ON t.linea_canonica = l.linea_canonica
    WHERE l.es_amba
      AND l.modo = 'COLECTIVO'
      AND f.tipo_dia = 'Hábil'
      AND f.mes BETWEEN 2 AND 10
      AND f.anio IN (2024, 2025)
    GROUP BY f.anio, f.fecha, grupo
),
resumen AS (
    SELECT grupo, anio, ROUND(AVG(usos)) AS prom_diario
    FROM por_dia
    GROUP BY grupo, anio
)
SELECT grupo,
       MAX(prom_diario) FILTER (WHERE anio = 2024) AS feb_oct_2024,
       MAX(prom_diario) FILTER (WHERE anio = 2025) AS feb_oct_2025,
       ROUND(100.0 * MAX(prom_diario) FILTER (WHERE anio = 2025)
                   / MAX(prom_diario) FILTER (WHERE anio = 2024) - 100, 1) AS var_pct
FROM resumen
GROUP BY grupo;

-- Resultado (promedio de usos por día hábil, febrero a octubre):
--   Traspasadas a CABA (31 líneas):   853.841 -> 839.624   -1,7%
--   Resto de colectivos del AMBA:   8.311.767 -> 8.107.842   -2,5%
-- Hallazgo: las 31 líneas traspasadas se comportaron igual que el resto
-- (incluso cayeron un poco menos). En el primer año, el traspaso no tuvo un
-- efecto visible en la demanda. Técnica usada: comparar contra un grupo de
-- control (diferencia en diferencias simple).
