-- =====================================================================
-- 06_exportar_powerbi.sql
-- Exporta las tablas del AMBA a CSV para Power BI (dashboard/datos/).
-- Se usa CSV en lugar de conectar Power BI a PostgreSQL porque es más
-- liviano (1 millón de filas en vez de 3,2) y no depende del conector.
--   psql -U postgres -d sube -f sql/06_exportar_powerbi.sql
-- =====================================================================
SET client_encoding = 'UTF8';

\copy (SELECT fecha, anio, trimestre, mes, nombre_mes, inicio_mes, dia_semana_num, dia_semana, CASE WHEN es_fin_de_semana THEN 'Sí' ELSE 'No' END AS es_fin_de_semana, nombre_feriado, tipo_feriado, tipo_dia FROM dw.dim_fecha ORDER BY fecha) TO 'dashboard/datos/dim_fecha.csv' WITH (FORMAT csv, HEADER, ENCODING 'UTF8')

\copy (SELECT linea_key, linea_canonica, linea_original, modo, jurisdiccion_principal, municipio_principal FROM dw.dim_linea WHERE es_amba ORDER BY linea_key) TO 'dashboard/datos/dim_linea.csv' WITH (FORMAT csv, HEADER, ENCODING 'UTF8')

\copy (SELECT u.fecha, u.linea_key, SUM(u.cantidad) AS cantidad FROM dw.fact_usos u JOIN dw.dim_linea l ON l.linea_key = u.linea_key WHERE l.es_amba GROUP BY u.fecha, u.linea_key ORDER BY u.fecha, u.linea_key) TO 'dashboard/datos/fact_usos_amba.csv' WITH (FORMAT csv, HEADER, ENCODING 'UTF8')
