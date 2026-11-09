# Databricks notebook source
# MAGIC %md
# MAGIC # 04 · Controles de calidad
# MAGIC Equivale a `sql/04_controles_calidad.sql`, con controles extra propios de Spark (conversiones fallidas).
# MAGIC Verifica que no se perdió ni se duplicó nada en el camino. Si algún control da ERROR, el notebook se detiene.

# COMMAND ----------

# MAGIC %run ./00_config

# COMMAND ----------

from pyspark.sql import functions as F

bronze = spark.table("bronze_usos_sube")
silver = spark.table("silver_usos")
descartados = spark.table("silver_usos_descartados")
dim_fecha = spark.table("gold_dim_fecha")
dim_linea = spark.table("gold_dim_linea")
fact = spark.table("gold_fact_usos")

def total(df, col="cantidad"):
    return df.agg(F.sum(col)).first()[0] or 0

total_crudo = bronze.agg(F.sum(F.expr("try_cast(cantidad AS BIGINT)"))).first()[0]
total_descartado = total(descartados)
total_fact = total(fact)

filas_bronze, filas_silver, filas_desc = bronze.count(), silver.count(), descartados.count()
dias_calendario = dim_fecha.count()
desde, hasta = dim_fecha.agg(F.min("fecha"), F.max("fecha")).first()
dias_sin_datos = dim_fecha.join(fact.select("fecha").distinct(), "fecha", "left_anti").count()

def canonicas(modo):
    return (dim_linea.filter(F.col("es_amba") & (F.col("modo") == modo))
            .select("linea_canonica").distinct().count())

controles = [
    ("Total de usos: crudo - descartado = fact",
     total_crudo - total_descartado == total_fact, f"{total_crudo:,} - {total_descartado:,} = {total_fact:,}"),
    ("Filas: crudo = limpio + descartado",
     filas_bronze == filas_silver + filas_desc, f"{filas_bronze:,} = {filas_silver:,} + {filas_desc:,}"),
    ("Fechas válidas en todas las filas",
     silver.filter(F.col("fecha").isNull()).count() == 0, "conversión de dia_transporte"),
    ("Cantidades numéricas en todas las filas",
     silver.filter(F.col("cantidad").isNull()).count() == 0, "conversión de cantidad"),
    ("Sin días faltantes en el calendario",
     dias_calendario == (hasta - desde).days + 1, f"{dias_calendario:,} días ({desde} a {hasta})"),
    ("Todos los días tienen datos", dias_sin_datos == 0, f"{dias_sin_datos} días sin datos"),
    ("Subte: 7 líneas canónicas (A-E, H, Premetro)", canonicas("SUBTE") == 7, f"{canonicas('SUBTE')} líneas"),
    ("Trenes AMBA: 8 líneas canónicas", canonicas("TREN") == 8, f"{canonicas('TREN')} líneas"),
]

resultado = spark.createDataFrame(
    [(c, "OK" if ok else "ERROR", detalle) for c, ok, detalle in controles],
    "control string, resultado string, detalle string")
display(resultado)

errores = [c for c, ok, _ in controles if not ok]
assert not errores, f"Controles con ERROR: {errores}"

# COMMAND ----------

# MAGIC %md
# MAGIC Para mirar (no es un control): días hábiles con muchos menos viajes que el promedio de su mes.
# MAGIC Ahí suelen aparecer paros, cortes y datos raros.

# COMMAND ----------

from pyspark.sql.window import Window

diario = (fact.join(dim_fecha, "fecha").join(dim_linea.filter("es_amba"), "linea_key")
          .groupBy("fecha", "inicio_mes", "tipo_dia").agg(F.sum("cantidad").alias("usos")))

display(diario
    .withColumn("dif_vs_promedio_mes_pct",
                F.round(100 * F.col("usos") / F.avg("usos").over(Window.partitionBy("inicio_mes")) - 100, 1))
    .filter(F.col("tipo_dia") == "Hábil")
    .orderBy("dif_vs_promedio_mes_pct")
    .select("fecha", "usos", "dif_vs_promedio_mes_pct")
    .limit(15))
