-- =====================================================================
-- 03_modelo_estrella.sql
-- Arma el modelo en estrella que va a usar Power BI:
--
--            dim_fecha
--                |
--   dim_linea -- fact_usos -- dim_empresa
--
-- fact_usos: un registro por día, línea, empresa y jurisdicción.
-- =====================================================================
SET client_encoding = 'UTF8';

-- ---------------------------------------------------------------------
-- dim_fecha: un registro por día, con feriados y tipo de día
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS dw.fact_usos;
DROP TABLE IF EXISTS dw.dim_fecha;
CREATE TABLE dw.dim_fecha AS
WITH dias AS (
    SELECT d::DATE AS fecha
    FROM GENERATE_SERIES(
        (SELECT MIN(fecha) FROM stg.usos),
        (SELECT MAX(fecha) FROM stg.usos),
        INTERVAL '1 day') AS d
)
SELECT
    d.fecha,
    EXTRACT(YEAR    FROM d.fecha)::INT  AS anio,
    EXTRACT(QUARTER FROM d.fecha)::INT  AS trimestre,
    EXTRACT(MONTH   FROM d.fecha)::INT  AS mes,
    -- Nombres armados a mano para no depender del idioma de Windows
    (ARRAY['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio',
           'Agosto','Septiembre','Octubre','Noviembre','Diciembre'])
        [EXTRACT(MONTH FROM d.fecha)::INT]                      AS nombre_mes,
    DATE_TRUNC('month', d.fecha)::DATE                          AS inicio_mes,
    EXTRACT(ISODOW FROM d.fecha)::INT                           AS dia_semana_num,  -- 1 = lunes
    (ARRAY['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'])
        [EXTRACT(ISODOW FROM d.fecha)::INT]                     AS dia_semana,
    (EXTRACT(ISODOW FROM d.fecha) >= 6)                         AS es_fin_de_semana,
    f.nombre                                                    AS nombre_feriado,
    f.tipo                                                      AS tipo_feriado,
    -- Tipo de día para comparar demanda. El orden del CASE importa:
    -- un feriado que cae sábado cuenta como feriado.
    CASE
        WHEN f.tipo IN ('feriado', 'extraordinario')  THEN 'Feriado'
        WHEN f.tipo IN ('puente', 'no_laborable')     THEN 'No laborable'
        WHEN EXTRACT(ISODOW FROM d.fecha) = 6         THEN 'Sábado'
        WHEN EXTRACT(ISODOW FROM d.fecha) = 7         THEN 'Domingo'
        ELSE 'Hábil'
    END                                                         AS tipo_dia
FROM dias d
LEFT JOIN raw.feriados f ON f.fecha = d.fecha;

ALTER TABLE dw.dim_fecha ADD PRIMARY KEY (fecha);

-- ---------------------------------------------------------------------
-- dim_empresa
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS dw.dim_empresa;
CREATE TABLE dw.dim_empresa AS
SELECT ROW_NUMBER() OVER (ORDER BY empresa)::INT AS empresa_key, empresa
FROM (SELECT DISTINCT empresa FROM stg.usos) e;
ALTER TABLE dw.dim_empresa ADD PRIMARY KEY (empresa_key);

-- ---------------------------------------------------------------------
-- dim_linea
-- Una fila por nombre de línea tal como viene en el archivo (+ modo y región).
-- La columna clave es linea_canonica: unifica nombres distintos de la
-- MISMA línea, para poder seguirla en el tiempo. Ejemplo: en enero de 2025
-- la línea 39 pasó de jurisdicción nacional a la Ciudad y cambió de nombre
-- de "BSAS_LINEA_039" a "CABA_LINEA_39". Sin esto, parecería que una línea
-- murió y nació otra.
-- Solo se unifica en el AMBA; en el interior se deja el nombre original.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS dw.dim_linea;
CREATE TABLE dw.dim_linea AS
WITH base AS (
    SELECT
        linea_original,
        modo,
        region,
        BOOL_OR(es_amba)                                        AS es_amba,
        MODE() WITHIN GROUP (ORDER BY jurisdiccion)             AS jurisdiccion_principal,
        MODE() WITHIN GROUP (ORDER BY municipio)                AS municipio_principal,
        MODE() WITHIN GROUP (ORDER BY provincia)                AS provincia_principal,
        MIN(fecha)                                              AS primer_dia,
        MAX(fecha)                                              AS ultimo_dia,
        -- número + letra opcional: "BSAS_LINEA_044" -> {044,""}, "BS_AS_LINEA 715M" -> {715,M}
        REGEXP_MATCH(REPLACE(linea_original, '_', ' '), '(\d+) ?([A-Z]?)(?![A-Z0-9])') AS num
    FROM stg.usos
    GROUP BY linea_original, modo, region
)
SELECT
    ROW_NUMBER() OVER (ORDER BY region, modo, linea_original)::INT AS linea_key,
    linea_original,
    modo,
    region,
    es_amba,
    jurisdiccion_principal,
    provincia_principal,
    municipio_principal,
    primer_dia,
    ultimo_dia,
    CASE
        -- Subte: "LINEA_A", "LINEA SUBTE C" y "LIN_AMARILLA_C" son la misma línea
        WHEN es_amba AND modo = 'SUBTE' AND linea_original LIKE '%PREMETRO%' THEN 'Premetro'
        WHEN es_amba AND modo = 'SUBTE'
            THEN 'Subte ' || SUBSTRING(linea_original FROM '([A-H])$')

        -- Trenes: agrupamos ramales en su línea
        WHEN es_amba AND modo = 'TREN' THEN
            CASE
                WHEN linea_original ~ 'BELG_SUR|G\.CATAN'    THEN 'Tren Belgrano Sur'
                WHEN linea_original ~ 'BELGRANO_NORTE'       THEN 'Tren Belgrano Norte'
                WHEN linea_original ~ 'MITRE|SUAREZ'         THEN 'Tren Mitre'
                WHEN linea_original ~ 'SAR'                  THEN 'Tren Sarmiento'
                WHEN linea_original ~ 'ROCA'                 THEN 'Tren Roca'
                WHEN linea_original ~ 'SANM'                 THEN 'Tren San Martín'
                WHEN linea_original ~ 'URQUIZA'              THEN 'Tren Urquiza'
                WHEN linea_original ~ 'COSTA'                THEN 'Tren de la Costa'
                ELSE linea_original
            END

        -- Colectivos del AMBA: por número. Las líneas municipales repiten
        -- números entre municipios (hay una "1" en Mercedes), así que
        -- les agregamos el municipio.
        WHEN es_amba AND modo = 'COLECTIVO' AND num IS NOT NULL THEN
            'Línea ' || LTRIM(num[1], '0') || num[2] ||
            CASE
                WHEN jurisdiccion_principal = 'MUNICIPAL' AND linea_original NOT LIKE 'CABA%'
                    THEN ' (' || INITCAP(COALESCE(municipio_principal, 'municipal')) || ')'
                ELSE ''
            END

        ELSE linea_original
    END AS linea_canonica
FROM base;

ALTER TABLE dw.dim_linea ADD PRIMARY KEY (linea_key);

-- ---------------------------------------------------------------------
-- fact_usos
-- Se agrupa con SUM por si, al normalizar nombres de empresa, dos filas
-- del mismo día y línea quedaron con la misma clave.
-- ---------------------------------------------------------------------
CREATE TABLE dw.fact_usos AS
SELECT
    u.fecha,
    l.linea_key,
    e.empresa_key,
    u.jurisdiccion,
    SUM(u.cantidad)::BIGINT     AS cantidad,
    BOOL_OR(u.dato_preliminar)  AS dato_preliminar
FROM stg.usos u
JOIN dw.dim_linea   l ON l.linea_original = u.linea_original
                     AND l.modo = u.modo
                     AND l.region = u.region
JOIN dw.dim_empresa e ON e.empresa = u.empresa
GROUP BY u.fecha, l.linea_key, e.empresa_key, u.jurisdiccion;

ALTER TABLE dw.fact_usos
    ADD CONSTRAINT fk_fecha   FOREIGN KEY (fecha)       REFERENCES dw.dim_fecha (fecha),
    ADD CONSTRAINT fk_linea   FOREIGN KEY (linea_key)   REFERENCES dw.dim_linea (linea_key),
    ADD CONSTRAINT fk_empresa FOREIGN KEY (empresa_key) REFERENCES dw.dim_empresa (empresa_key);

CREATE INDEX ix_fact_fecha ON dw.fact_usos (fecha);
CREATE INDEX ix_fact_linea ON dw.fact_usos (linea_key);

ANALYZE dw.fact_usos;

SELECT 'dim_fecha' AS tabla, COUNT(*) AS filas FROM dw.dim_fecha
UNION ALL SELECT 'dim_linea',   COUNT(*) FROM dw.dim_linea
UNION ALL SELECT 'dim_empresa', COUNT(*) FROM dw.dim_empresa
UNION ALL SELECT 'fact_usos',   COUNT(*) FROM dw.fact_usos;
