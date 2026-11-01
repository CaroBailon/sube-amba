-- =====================================================================
-- 04_controles_calidad.sql
-- Verifica que no se perdió ni se duplicó nada en el camino.
-- Todas las filas de "resultado" deberían decir OK.
-- =====================================================================
SET client_encoding = 'UTF8';

WITH
crudo AS (
    SELECT SUM(cantidad::BIGINT) AS total, COUNT(*) AS filas FROM raw.usos_sube
),
descartado AS (
    SELECT COALESCE(SUM(cantidad), 0) AS total, COUNT(*) AS filas FROM stg.usos_descartados
),
hechos AS (
    SELECT SUM(cantidad) AS total FROM dw.fact_usos
)
SELECT 'Total de usos: crudo - descartado = fact' AS control,
       CASE WHEN c.total - d.total = h.total THEN 'OK' ELSE 'ERROR' END AS resultado,
       c.total AS crudo, d.total AS descartado, h.total AS fact
FROM crudo c, descartado d, hechos h

UNION ALL
SELECT 'Filas: crudo = limpio + descartado',
       CASE WHEN (SELECT COUNT(*) FROM raw.usos_sube)
               = (SELECT COUNT(*) FROM stg.usos) + (SELECT COUNT(*) FROM stg.usos_descartados)
            THEN 'OK' ELSE 'ERROR' END,
       (SELECT COUNT(*) FROM raw.usos_sube), (SELECT COUNT(*) FROM stg.usos_descartados),
       (SELECT COUNT(*) FROM stg.usos)

UNION ALL
SELECT 'Sin días faltantes en el calendario',
       CASE WHEN (SELECT COUNT(*) FROM dw.dim_fecha)
               = (SELECT MAX(fecha) - MIN(fecha) + 1 FROM dw.dim_fecha)
            THEN 'OK' ELSE 'ERROR' END,
       NULL, NULL, (SELECT COUNT(*) FROM dw.dim_fecha)

UNION ALL
SELECT 'Todos los días tienen datos',
       CASE WHEN NOT EXISTS (
            SELECT 1 FROM dw.dim_fecha f
            WHERE NOT EXISTS (SELECT 1 FROM dw.fact_usos u WHERE u.fecha = f.fecha))
            THEN 'OK' ELSE 'ERROR' END,
       NULL, NULL, NULL

UNION ALL
SELECT 'Subte: solo 7 líneas canónicas (A-E, H, Premetro)',
       CASE WHEN (SELECT COUNT(DISTINCT linea_canonica) FROM dw.dim_linea
                  WHERE es_amba AND modo = 'SUBTE') = 7
            THEN 'OK' ELSE 'ERROR' END,
       NULL, NULL,
       (SELECT COUNT(DISTINCT linea_canonica) FROM dw.dim_linea WHERE es_amba AND modo = 'SUBTE')

UNION ALL
SELECT 'Trenes AMBA: 8 líneas canónicas',
       CASE WHEN (SELECT COUNT(DISTINCT linea_canonica) FROM dw.dim_linea
                  WHERE es_amba AND modo = 'TREN') = 8
            THEN 'OK' ELSE 'ERROR' END,
       NULL, NULL,
       (SELECT COUNT(DISTINCT linea_canonica) FROM dw.dim_linea WHERE es_amba AND modo = 'TREN');

-- Para mirar (no es un control): días hábiles con muchos menos viajes que
-- el promedio de su mes. Ahí suelen aparecer paros, cortes y datos raros.
WITH diario AS (
    SELECT f.fecha, f.inicio_mes, f.tipo_dia, SUM(u.cantidad) AS usos
    FROM dw.fact_usos u
    JOIN dw.dim_fecha f ON f.fecha = u.fecha
    JOIN dw.dim_linea l ON l.linea_key = u.linea_key
    WHERE l.es_amba
    GROUP BY f.fecha, f.inicio_mes, f.tipo_dia
)
SELECT fecha, usos,
       ROUND(100.0 * usos / AVG(usos) OVER (PARTITION BY inicio_mes) - 100, 1) AS dif_vs_promedio_mes_pct
FROM diario
WHERE tipo_dia = 'Hábil'
ORDER BY dif_vs_promedio_mes_pct
LIMIT 15;
