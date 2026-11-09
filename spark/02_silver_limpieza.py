# Databricks notebook source
# MAGIC %md
# MAGIC # 02 · Silver: tipado y limpieza
# MAGIC Equivale a `sql/02_limpiar.sql`. Cada decisión está explicada en `docs/decisiones_de_limpieza.md`.
# MAGIC
# MAGIC Las conversiones usan `try_cast` y expresiones regulares en lugar de `cast` directo: en Databricks el modo ANSI
# MAGIC está activado y un valor mal formado cortaría el proceso. Así, un dato inválido queda en `null` y lo detecta
# MAGIC `04_controles_calidad`.

# COMMAND ----------

# MAGIC %run ./00_config

# COMMAND ----------

from pyspark.sql import functions as F

crudo = spark.table("bronze_usos_sube")

def sin_tildes(col):
    return F.translate(col, "ÁÉÍÓÚ", "AEIOU")

def vacio_a_null(col):
    return F.when(col == "", None).otherwise(col)

fecha_txt = F.col("dia_transporte")
fecha = (
    F.when(fecha_txt.rlike(r"^\d{4}-\d{2}-\d{2}"), F.to_date(F.substring(fecha_txt, 1, 10), "yyyy-MM-dd"))
     .when(fecha_txt.rlike(r"^\d{2}/\d{2}/\d{4}"), F.to_date(F.substring(fecha_txt, 1, 10), "dd/MM/yyyy"))
)

usos = crudo.select(
    fecha.alias("fecha"),

    # Empresa: sin espacios al inicio/final ni espacios dobles
    F.upper(F.regexp_replace(F.trim("nombre_empresa"), r"\s+", " ")).alias("empresa"),

    F.trim("linea").alias("linea_original"),
    F.col("tipo_transporte").alias("modo"),
    (F.col("amba") == "SI").alias("es_amba"),

    # Jurisdicción: el subte viene vacío (lo gestiona la Ciudad) y la Ciudad
    # aparece como 'C.A.B.A'. Se unifica en 'CABA'.
    F.when(F.col("tipo_transporte") == "SUBTE", "CABA")
     .when(F.col("jurisdiccion") == "C.A.B.A", "CABA")
     .otherwise(vacio_a_null(F.col("jurisdiccion"))).alias("jurisdiccion"),

    # Provincia: 3 formas de escribir la Ciudad, tildes inconsistentes
    # y 'JN' = líneas nacionales del AMBA
    F.when((F.col("tipo_transporte") == "SUBTE")
           | F.col("provincia").isin("C.A.B.A", "CIUDAD AUTÓNOMA DE BUENOS AIRES"), "CABA")
     .when(F.col("provincia") == "JN", "NACIONAL (AMBA)")
     .when(F.col("provincia") == "", None)
     .otherwise(sin_tildes(F.col("provincia"))).alias("provincia"),

    # Municipio: 'SN' (sin nombre) y 'SD' (sin dato) son faltantes, no municipios
    F.when(F.col("municipio").isin("SN", "SD", ""), None)
     .otherwise(sin_tildes(F.col("municipio"))).alias("municipio"),

    F.expr("try_cast(cantidad AS INT)").alias("cantidad"),
    (F.col("dato_preliminar") == "SI").alias("dato_preliminar"),
)

# COMMAND ----------

# MAGIC %md
# MAGIC Cantidades negativas: 16 filas, todas de trenes (parecen anulaciones o correcciones de la operadora).
# MAGIC No representan viajes: se apartan en una tabla propia para que quede registro, en lugar de borrarlas.

# COMMAND ----------

es_negativa = F.coalesce(F.col("cantidad") < 0, F.lit(False))

(usos.filter(es_negativa)
    .withColumn("motivo", F.lit("cantidad negativa"))
    .write.mode("overwrite").option("overwriteSchema", True).saveAsTable("silver_usos_descartados"))

# Región de análisis: el AMBA como un todo; fuera del AMBA, la provincia
(usos.filter(~es_negativa)
    .withColumn("region", F.when(F.col("es_amba"), "AMBA").otherwise(F.coalesce("provincia", F.lit("SIN DATO"))))
    .write.mode("overwrite").option("overwriteSchema", True).saveAsTable("silver_usos"))

# COMMAND ----------

silver = spark.table("silver_usos")
display(silver.agg(
    F.count("*").alias("filas_limpias"),
    F.min("fecha").alias("desde"),
    F.max("fecha").alias("hasta"),
).crossJoin(spark.table("silver_usos_descartados").agg(F.count("*").alias("filas_descartadas"))))
