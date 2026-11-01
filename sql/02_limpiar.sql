-- =====================================================================
-- 02_limpiar.sql
-- Pasa de raw.usos_sube (texto crudo) a stg.usos (tipado y normalizado).
-- Cada decisión está explicada en docs/decisiones_de_limpieza.md
-- =====================================================================
SET client_encoding = 'UTF8';

DROP TABLE IF EXISTS stg.usos;
CREATE TABLE stg.usos AS
SELECT
    dia_transporte::DATE                                         AS fecha,

    -- Empresa: sin espacios al inicio/final ni espacios dobles
    -- ("COMPAÑIA  DE TRANSPORTE" -> "COMPAÑIA DE TRANSPORTE")
    UPPER(REGEXP_REPLACE(TRIM(nombre_empresa), '\s+', ' ', 'g'))  AS empresa,

    TRIM(linea)                                                  AS linea_original,
    tipo_transporte                                              AS modo,
    (amba = 'SI')                                                AS es_amba,

    -- Jurisdicción: el subte viene vacío (lo gestiona la Ciudad) y
    -- la Ciudad aparece como 'C.A.B.A'. Unificamos en 'CABA'.
    CASE
        WHEN tipo_transporte = 'SUBTE'   THEN 'CABA'
        WHEN jurisdiccion = 'C.A.B.A'    THEN 'CABA'
        WHEN jurisdiccion = ''           THEN NULL
        ELSE jurisdiccion
    END                                                          AS jurisdiccion,

    -- Provincia: unificamos las 3 formas de escribir la Ciudad, sacamos
    -- tildes (venía "NEUQUÉN" pero "CORDOBA") y 'JN' = líneas nacionales del AMBA
    CASE
        WHEN tipo_transporte = 'SUBTE'
          OR provincia IN ('C.A.B.A', 'CIUDAD AUTÓNOMA DE BUENOS AIRES') THEN 'CABA'
        WHEN provincia = 'JN'  THEN 'NACIONAL (AMBA)'
        WHEN provincia = ''    THEN NULL
        ELSE TRANSLATE(provincia, 'ÁÉÍÓÚ', 'AEIOU')
    END                                                          AS provincia,

    -- Municipio: 'SN' (sin nombre) y 'SD' (sin dato) son faltantes, no municipios
    CASE
        WHEN municipio IN ('SN', 'SD', '') THEN NULL
        ELSE TRANSLATE(municipio, 'ÁÉÍÓÚ', 'AEIOU')
    END                                                          AS municipio,

    cantidad::INTEGER                                            AS cantidad,
    (dato_preliminar = 'SI')                                     AS dato_preliminar
FROM raw.usos_sube;

-- ---------------------------------------------------------------------
-- Cantidades negativas: son 16 filas, todas de trenes (parecen anulaciones
-- o correcciones de la operadora). No representan viajes: las apartamos
-- a una tabla aparte para que quede registro, en lugar de borrarlas sin más.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg.usos_descartados;
CREATE TABLE stg.usos_descartados AS
SELECT *, 'cantidad negativa'::TEXT AS motivo
FROM stg.usos
WHERE cantidad < 0;

DELETE FROM stg.usos WHERE cantidad < 0;

-- Región de análisis: AMBA como un todo; fuera del AMBA, la provincia
ALTER TABLE stg.usos ADD COLUMN region TEXT;
UPDATE stg.usos
SET region = CASE WHEN es_amba THEN 'AMBA' ELSE COALESCE(provincia, 'SIN DATO') END;

-- Resumen de lo que quedó
SELECT
    (SELECT COUNT(*) FROM stg.usos)             AS filas_limpias,
    (SELECT COUNT(*) FROM stg.usos_descartados) AS filas_descartadas,
    (SELECT MIN(fecha) FROM stg.usos)           AS desde,
    (SELECT MAX(fecha) FROM stg.usos)           AS hasta;
