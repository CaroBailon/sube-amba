-- =====================================================================
-- 01_cargar_crudos.sql
-- Crea los esquemas y carga los CSV de SUBE tal cual vienen (todo como texto).
-- Se ejecuta desde la carpeta raíz del proyecto:
--   psql -U postgres -d sube -f sql/01_cargar_crudos.sql
--
-- Por qué todo como texto: si una fila viene mal formada, preferimos que
-- la carga NO falle y detectar el problema después con SQL (paso 02).
-- =====================================================================
SET client_encoding = 'UTF8';

CREATE SCHEMA IF NOT EXISTS raw;   -- datos crudos, sin tocar
CREATE SCHEMA IF NOT EXISTS stg;   -- datos limpios (staging)
CREATE SCHEMA IF NOT EXISTS dw;    -- modelo en estrella para Power BI

DROP TABLE IF EXISTS raw.usos_sube;
CREATE TABLE raw.usos_sube (
    dia_transporte   TEXT,
    nombre_empresa   TEXT,
    linea            TEXT,
    amba             TEXT,
    tipo_transporte  TEXT,
    jurisdiccion     TEXT,
    provincia        TEXT,
    municipio        TEXT,
    cantidad         TEXT,
    dato_preliminar  TEXT
);

-- \copy lee el archivo desde TU computadora (no desde el servidor).
\copy raw.usos_sube FROM 'data/raw/dat-ab-usos-2020.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.usos_sube FROM 'data/raw/dat-ab-usos-2021.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.usos_sube FROM 'data/raw/dat-ab-usos-2022.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.usos_sube FROM 'data/raw/dat-ab-usos-2023.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.usos_sube FROM 'data/raw/dat-ab-usos-2024.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.usos_sube FROM 'data/raw/dat-ab-usos-2025.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.usos_sube FROM 'data/raw/dat-ab-usos-2026.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- Feriados nacionales (armados a partir de las comunicaciones del BCRA)
DROP TABLE IF EXISTS raw.feriados;
CREATE TABLE raw.feriados (fecha DATE PRIMARY KEY, nombre TEXT, tipo TEXT);
\copy raw.feriados FROM 'data/feriados_ar.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- Control rápido: deberían ser 3.221.807 filas de usos y 140 feriados
SELECT 'usos_sube' AS tabla, COUNT(*) AS filas FROM raw.usos_sube
UNION ALL
SELECT 'feriados', COUNT(*) FROM raw.feriados;
