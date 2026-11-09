# Databricks notebook source
# MAGIC %md
# MAGIC # 03 · Gold: modelo en estrella
# MAGIC Equivale a `sql/03_modelo_estrella.sql`.
# MAGIC
# MAGIC ```
# MAGIC            gold_dim_fecha
# MAGIC                  |
# MAGIC gold_dim_linea -- gold_fact_usos -- gold_dim_empresa
# MAGIC ```
# MAGIC `gold_fact_usos`: un registro por día, línea, empresa y jurisdicción.

# COMMAND ----------

# MAGIC %run ./00_config

# COMMAND ----------

from pyspark.sql import functions as F
from pyspark.sql.window import Window

silver = spark.table("silver_usos")
feriados = spark.table("bronze_feriados")

def guardar(df, nombre):
    df.write.mode("overwrite").option("overwriteSchema", True).saveAsTable(nombre)

# COMMAND ----------

# MAGIC %md
# MAGIC ## gold_dim_fecha
# MAGIC Un registro por día del período, con feriados y tipo de día. Los nombres de mes y día se arman a mano
# MAGIC para no depender del idioma del clúster.

# COMMAND ----------

MESES = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio",
         "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]
DIAS = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]

rango = silver.agg(F.min("fecha").alias("desde"), F.max("fecha").alias("hasta"))
dias = rango.select(F.explode(F.sequence("desde", "hasta")).alias("fecha"))

# dayofweek() de Spark devuelve 1 = domingo; se pasa a ISO (1 = lunes, 7 = domingo)
dia_iso = ((F.dayofweek("fecha") + 5) % 7) + 1

dim_fecha = (
    dias.join(feriados.withColumnRenamed("nombre", "nombre_feriado")
                      .withColumnRenamed("tipo", "tipo_feriado"), "fecha", "left")
    .select(
        "fecha",
        F.year("fecha").alias("anio"),
        F.quarter("fecha").alias("trimestre"),
        F.month("fecha").alias("mes"),
        F.element_at(F.array(*[F.lit(m) for m in MESES]), F.month("fecha")).alias("nombre_mes"),
        F.trunc("fecha", "month").alias("inicio_mes"),
        dia_iso.alias("dia_semana_num"),
        F.element_at(F.array(*[F.lit(d) for d in DIAS]), dia_iso).alias("dia_semana"),
        (dia_iso >= 6).alias("es_fin_de_semana"),
        "nombre_feriado",
        "tipo_feriado",
        # El orden importa: un feriado que cae sábado cuenta como feriado
        F.when(F.col("tipo_feriado").isin("feriado", "extraordinario"), "Feriado")
         .when(F.col("tipo_feriado").isin("puente", "no_laborable"), "No laborable")
         .when(dia_iso == 6, "Sábado")
         .when(dia_iso == 7, "Domingo")
         .otherwise("Hábil").alias("tipo_dia"),
    )
)
guardar(dim_fecha, "gold_dim_fecha")

# COMMAND ----------

# MAGIC %md
# MAGIC ## gold_dim_empresa

# COMMAND ----------

dim_empresa = (silver.select("empresa").distinct()
    .withColumn("empresa_key", F.row_number().over(Window.orderBy("empresa")))
    .select("empresa_key", "empresa"))
guardar(dim_empresa, "gold_dim_empresa")

# COMMAND ----------

# MAGIC %md
# MAGIC ## gold_dim_linea
# MAGIC Una fila por nombre de línea tal como viene en el archivo (+ modo y región). La columna clave es
# MAGIC `linea_canonica`: unifica nombres distintos de la **misma** línea para poder seguirla en el tiempo.
# MAGIC Por ejemplo, en enero de 2025 la línea 39 pasó de jurisdicción nacional a la Ciudad y cambió de nombre de
# MAGIC `BSAS_LINEA_039` a `CABA_LINEA_39`. Solo se unifica en el AMBA; en el interior queda el nombre original.

# COMMAND ----------

GRUPO = ["linea_original", "modo", "region"]

def moda(df, col):
    """Valor más frecuente (sin nulos) por grupo. Ante un empate gana el menor,
    igual que MODE() WITHIN GROUP en PostgreSQL."""
    w = Window.partitionBy(*GRUPO).orderBy(F.desc("n"), F.asc(col))
    return (df.filter(F.col(col).isNotNull())
              .groupBy(*GRUPO, col).agg(F.count("*").alias("n"))
              .withColumn("rk", F.row_number().over(w))
              .filter("rk = 1")
              .select(*GRUPO, F.col(col).alias(f"{col}_principal")))

# número + letra opcional: "BSAS_LINEA_044" -> (044, ""), "BS_AS_LINEA 715M" -> (715, M)
PATRON_NUM = r"(\d+) ?([A-Z]?)(?![A-Z0-9])"
linea_esp = F.regexp_replace("linea_original", "_", " ")

base = (
    silver.groupBy(*GRUPO).agg(
        F.max("es_amba").alias("es_amba"),          # equivale a BOOL_OR
        F.min("fecha").alias("primer_dia"),
        F.max("fecha").alias("ultimo_dia"),
    )
    .join(moda(silver, "jurisdiccion"), GRUPO, "left")
    .join(moda(silver, "provincia"), GRUPO, "left")
    .join(moda(silver, "municipio"), GRUPO, "left")
    .withColumn("tiene_num", linea_esp.rlike(PATRON_NUM))
    .withColumn("num", F.regexp_replace(F.regexp_extract(linea_esp, PATRON_NUM, 1), "^0+", ""))
    .withColumn("letra", F.regexp_extract(linea_esp, PATRON_NUM, 2))
)

lo = F.col("linea_original")
amba, modo = F.col("es_amba"), F.col("modo")

tren = (
    F.when(lo.rlike(r"BELG_SUR|G\.CATAN"), "Tren Belgrano Sur")
     .when(lo.rlike("BELGRANO_NORTE"), "Tren Belgrano Norte")
     .when(lo.rlike("MITRE|SUAREZ"), "Tren Mitre")
     .when(lo.rlike("SAR"), "Tren Sarmiento")
     .when(lo.rlike("ROCA"), "Tren Roca")
     .when(lo.rlike("SANM"), "Tren San Martín")
     .when(lo.rlike("URQUIZA"), "Tren Urquiza")
     .when(lo.rlike("COSTA"), "Tren de la Costa")
     .otherwise(lo)
)

# Las líneas municipales repiten números entre municipios (hay una "1" en Mercedes): se agrega el municipio
sufijo_municipal = (
    F.when((F.col("jurisdiccion_principal") == "MUNICIPAL") & ~lo.startswith("CABA"),
           F.concat(F.lit(" ("), F.initcap(F.coalesce("municipio_principal", F.lit("municipal"))), F.lit(")")))
     .otherwise("")
)

linea_canonica = (
    F.when(amba & (modo == "SUBTE") & lo.contains("PREMETRO"), "Premetro")
     .when(amba & (modo == "SUBTE"),
           F.when(lo.rlike("[A-H]$"), F.concat(F.lit("Subte "), F.regexp_extract(lo, "([A-H])$", 1))))
     .when(amba & (modo == "TREN"), tren)
     .when(amba & (modo == "COLECTIVO") & F.col("tiene_num"),
           F.concat(F.lit("Línea "), F.col("num"), F.col("letra"), sufijo_municipal))
     .otherwise(lo)
)

dim_linea = (
    base.withColumn("linea_canonica", linea_canonica)
    .withColumn("linea_key", F.row_number().over(Window.orderBy("region", "modo", "linea_original")))
    .select("linea_key", "linea_original", "modo", "region", "es_amba",
            "jurisdiccion_principal", "provincia_principal", "municipio_principal",
            "primer_dia", "ultimo_dia", "linea_canonica")
)
guardar(dim_linea, "gold_dim_linea")

# COMMAND ----------

# MAGIC %md
# MAGIC ## gold_fact_usos
# MAGIC Se agrupa con `sum` por si, al normalizar nombres de empresa, dos filas del mismo día y línea quedaron con la misma clave.

# COMMAND ----------

dim_linea = spark.table("gold_dim_linea")
dim_empresa = spark.table("gold_dim_empresa")

fact = (
    silver
    .join(dim_linea.select("linea_key", *GRUPO), GRUPO)
    .join(dim_empresa, "empresa")
    .groupBy("fecha", "linea_key", "empresa_key", "jurisdiccion")
    .agg(F.sum("cantidad").cast("bigint").alias("cantidad"),
         F.max("dato_preliminar").alias("dato_preliminar"))
)
guardar(fact, "gold_fact_usos")

# COMMAND ----------

display(spark.createDataFrame(
    [(t, spark.table(t).count()) for t in ["gold_dim_fecha", "gold_dim_linea", "gold_dim_empresa", "gold_fact_usos"]],
    "tabla string, filas long"))
