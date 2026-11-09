# Databricks notebook source
# MAGIC %md
# MAGIC # 01 · Bronze: carga de los CSV tal cual vienen
# MAGIC Equivale a `sql/01_cargar_crudos.sql`.
# MAGIC
# MAGIC Todas las columnas se leen como texto: si una fila viene mal formada, la carga no falla y el problema se detecta en la limpieza.
# MAGIC Se guarda además el nombre del archivo de origen de cada fila (linaje).

# COMMAND ----------

# MAGIC %run ./00_config

# COMMAND ----------

from pyspark.sql import functions as F
from pyspark.sql.types import StructType, StructField, StringType, DateType

# Mismo orden de columnas que el CSV. Con un esquema explícito, Spark lee por posición
# y no depende de cómo venga escrito el encabezado en cada año.
esquema_usos = StructType([
    StructField(c, StringType()) for c in [
        "dia_transporte", "nombre_empresa", "linea", "amba", "tipo_transporte",
        "jurisdiccion", "provincia", "municipio", "cantidad", "dato_preliminar",
    ]
])

bronze_usos = (
    spark.read
    .option("header", True)
    .option("encoding", "UTF-8")
    .schema(esquema_usos)
    .csv(f"{VOLUMEN}/dat-ab-usos-*.csv")
    .withColumn("archivo_origen", F.col("_metadata.file_name"))
)

bronze_usos.write.mode("overwrite").option("overwriteSchema", True).saveAsTable("bronze_usos_sube")

# COMMAND ----------

# Feriados nacionales (armados a partir de las comunicaciones del BCRA)
esquema_feriados = StructType([
    StructField("fecha", DateType()),
    StructField("nombre", StringType()),
    StructField("tipo", StringType()),
])

(spark.read.option("header", True).schema(esquema_feriados)
    .csv(f"{VOLUMEN}/feriados_ar.csv")
    .write.mode("overwrite").option("overwriteSchema", True).saveAsTable("bronze_feriados"))

# COMMAND ----------

# Control rápido: filas por archivo (3.235.523 con los datos al 07/11/2026) y 140 feriados.
# rollup agrega una fila con el total de todos los archivos.
display(spark.table("bronze_usos_sube").rollup("archivo_origen").count()
        .withColumn("archivo_origen", F.coalesce("archivo_origen", F.lit("TOTAL")))
        .orderBy("archivo_origen"))
print("Feriados:", spark.table("bronze_feriados").count())
