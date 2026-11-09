# Databricks notebook source
# MAGIC %md
# MAGIC # 05 · Preguntas de negocio en PySpark
# MAGIC Las 7 preguntas de `sql/05_preguntas_negocio.sql`, resueltas con la API de DataFrames y funciones de ventana.
# MAGIC Al final, una **validación cruzada**: los resultados clave se comparan con los que dio el mismo análisis en PostgreSQL.
# MAGIC
# MAGIC Criterio general: 2026 llega hasta el 30/10, así que los años se comparan con promedios diarios, no con totales.

# COMMAND ----------

# MAGIC %run ./00_config

# COMMAND ----------

from pyspark.sql import functions as F
from pyspark.sql.window import Window

fact = spark.table("gold_fact_usos")
dim_fecha = spark.table("gold_dim_fecha")
dim_linea = spark.table("gold_dim_linea")

# Base común: viajes del AMBA con los atributos de fecha y línea
amba = (fact.join(dim_fecha, "fecha")
            .join(dim_linea.filter("es_amba"), "linea_key"))

def por_dia(df, *extra):
    """Suma los viajes de cada fecha. Promediar estas sumas da un promedio por día;
    promediar fact_usos directo daría un promedio por fila (línea-día)."""
    return df.groupBy("fecha", *extra).agg(F.sum("cantidad").alias("usos"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## P1. ¿Volvió el AMBA a viajar como antes de la pandemia?
# MAGIC Promedio de viajes por día hábil, por año.

# COMMAND ----------

p1 = (por_dia(amba.filter(F.col("tipo_dia") == "Hábil"), "anio")
      .groupBy("anio").agg(F.round(F.avg("usos")).cast("long").alias("promedio_diario"))
      .orderBy("anio"))
display(p1)

# COMMAND ----------

# MAGIC %md
# MAGIC ## P2. ¿Cómo se reparte la demanda entre colectivo, tren y subte?
# MAGIC Porcentaje de cada modo sobre el total del año: ventana `sum().over(partitionBy("anio"))`.

# COMMAND ----------

p2 = (amba.groupBy("anio", "modo").agg(F.sum("cantidad").alias("usos"))
      .withColumn("pct_del_anio",
                  F.round(100 * F.col("usos") / F.sum("usos").over(Window.partitionBy("anio")), 1))
      .orderBy("anio", F.desc("usos")))
display(p2)

# COMMAND ----------

# MAGIC %md
# MAGIC ## P3. ¿Cuánto cae la demanda en un feriado, un sábado y un domingo?
# MAGIC Promedio diario por tipo de día (2023–2025), comparado contra el día hábil.

# COMMAND ----------

p3 = (por_dia(amba.filter(F.col("anio").between(2023, 2025)), "tipo_dia")
      .groupBy("tipo_dia").agg(F.count("*").alias("dias"),
                               F.round(F.avg("usos")).cast("long").alias("promedio_diario")))
habil = F.max(F.when(F.col("tipo_dia") == "Hábil", F.col("promedio_diario"))).over(Window.partitionBy())
p3 = (p3.withColumn("dif_vs_habil_pct", F.round(100 * F.col("promedio_diario") / habil - 100, 1))
        .orderBy(F.desc("promedio_diario")))
display(p3)

# COMMAND ----------

# MAGIC %md
# MAGIC ## P4. ¿Qué líneas de colectivo concentran la demanda? (Pareto, 2025)
# MAGIC Ranking con % acumulado: ventana ordenada con `rowsBetween(unboundedPreceding, currentRow)`.

# COMMAND ----------

por_linea = (amba.filter((F.col("modo") == "COLECTIVO") & (F.col("anio") == 2025))
             .groupBy("linea_canonica").agg(F.sum("cantidad").alias("usos")))

orden = Window.orderBy(F.desc("usos"), "linea_canonica")
acumulado = (por_linea
    .withColumn("ranking", F.row_number().over(orden))
    .withColumn("total_lineas", F.count("*").over(Window.partitionBy()))
    .withColumn("pct_acumulado", F.round(
        100 * F.sum("usos").over(orden.rowsBetween(Window.unboundedPreceding, Window.currentRow))
        / F.sum("usos").over(Window.partitionBy()), 1)))

def lineas_hasta(pct):
    return acumulado.filter(F.col("pct_acumulado") >= pct).agg(F.min("ranking")).first()[0]

lineas_50, lineas_80 = lineas_hasta(50), lineas_hasta(80)
display(acumulado.filter(F.col("ranking").isin(*range(1, 11), lineas_50, lineas_80)).orderBy("ranking"))
print(f"El 50% de los viajes lo hacen {lineas_50} líneas y el 80%, {lineas_80} líneas.")

# COMMAND ----------

# MAGIC %md
# MAGIC ## P5. ¿Cómo evolucionó el subte mes a mes?
# MAGIC Promedio por día hábil de cada mes y variación contra el mismo mes del año anterior con `lag(12)`.

# COMMAND ----------

p5 = (por_dia(amba.filter((F.col("modo") == "SUBTE") & (F.col("tipo_dia") == "Hábil")), "inicio_mes")
      .groupBy("inicio_mes").agg(F.round(F.avg("usos")).cast("long").alias("prom_diario")))
w_mes = Window.orderBy("inicio_mes")
p5 = (p5.withColumn("mismo_mes_anio_anterior", F.lag("prom_diario", 12).over(w_mes))
        .withColumn("var_interanual_pct",
                    F.round(100 * F.col("prom_diario") / F.col("mismo_mes_anio_anterior") - 100, 1))
        .orderBy("inicio_mes"))
display(p5)

# COMMAND ----------

# MAGIC %md
# MAGIC ## P6. ¿Qué días hábiles tuvieron caídas anómalas?
# MAGIC Cada día hábil contra el promedio de los 7 días hábiles anteriores (`rowsBetween(-7, -1)`).
# MAGIC Se excluyen el 24 y el 31 de diciembre y el inicio de la cuarentena. Las causas están verificadas en
# MAGIC `data/dias_atipicos.csv`.

# COMMAND ----------

habiles = amba.filter((F.col("tipo_dia") == "Hábil")
                      & ~((F.col("mes") == 12) & F.dayofmonth("fecha").isin(24, 31)))
p6 = (por_dia(habiles, "dia_semana")
      .withColumn("prom_7_previos", F.avg("usos").over(Window.orderBy("fecha").rowsBetween(-7, -1)))
      .withColumn("caida_pct", F.round(100 * F.col("usos") / F.col("prom_7_previos") - 100, 1))
      .withColumn("prom_7_previos", F.round("prom_7_previos").cast("long"))
      .filter(F.col("fecha") >= "2020-07-01")
      .orderBy("caida_pct")
      .limit(12))
display(p6)

# COMMAND ----------

# MAGIC %md
# MAGIC ## P7. Las 31 líneas traspasadas a la Ciudad en 2025: ¿cambió su demanda?
# MAGIC Comparación feb–oct 2024 contra feb–oct 2025, con el resto de los colectivos como grupo de control.
# MAGIC `pivot` reemplaza al `FILTER (WHERE ...)` de PostgreSQL.

# COMMAND ----------

traspasadas = (dim_linea.filter(F.col("es_amba") & (F.col("modo") == "COLECTIVO")
                                & F.col("linea_original").startswith("CABA"))
               .select("linea_canonica").distinct().withColumn("traspasada", F.lit(True)))

colectivos = (amba.filter((F.col("modo") == "COLECTIVO") & (F.col("tipo_dia") == "Hábil")
                          & F.col("mes").between(2, 10) & F.col("anio").isin(2024, 2025))
              .join(traspasadas, "linea_canonica", "left")
              .withColumn("grupo", F.when(F.col("traspasada"), "Traspasadas a CABA").otherwise("Resto AMBA")))

p7 = (por_dia(colectivos, "anio", "grupo")
      .groupBy("grupo").pivot("anio", [2024, 2025]).agg(F.round(F.avg("usos")).cast("long"))
      .withColumnRenamed("2024", "feb_oct_2024").withColumnRenamed("2025", "feb_oct_2025")
      .withColumn("var_pct", F.round(100 * F.col("feb_oct_2025") / F.col("feb_oct_2024") - 100, 1)))
display(p7)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Validación cruzada con PostgreSQL
# MAGIC Los mismos números que dio `sql/05_preguntas_negocio.sql`. Si el pipeline en Spark replica bien la limpieza y el
# MAGIC modelo, tienen que coincidir exactamente.

# COMMAND ----------

def valor(df, filtro, col):
    return df.filter(filtro).select(col).first()[0]

# El archivo de 2026 se actualiza seguido. Para comparar con PostgreSQL, 2026 se
# recalcula con el mismo corte que tenía ese análisis (30/10/2026).
p1_2026_al_corte = (por_dia(amba.filter((F.col("tipo_dia") == "Hábil") & (F.col("anio") == 2026)
                                        & (F.col("fecha") <= "2026-10-30")))
                    .agg(F.round(F.avg("usos")).cast("long")).first()[0])

esperado = [
    ("P1 · AMBA, promedio día hábil 2023", valor(p1, "anio = 2023", "promedio_diario"), 11_708_399),
    ("P1 · AMBA, promedio día hábil 2026 (hasta 30/10)", p1_2026_al_corte, 9_132_417),
    ("P2 · Colectivo, % de 2025", valor(p2, "anio = 2025 AND modo = 'COLECTIVO'", "pct_del_anio"), 85.5),
    ("P3 · Feriado vs día hábil (%)", valor(p3, "tipo_dia = 'Feriado'", "dif_vs_habil_pct"), -65.2),
    ("P4 · Líneas para el 80% de los viajes", lineas_80, 183),
    ("P5 · Subte, oct-2023", valor(p5, "inicio_mes = '2023-10-01'", "prom_diario"), 915_021),
    ("P5 · Subte, oct-2025", valor(p5, "inicio_mes = '2025-10-01'", "prom_diario"), 499_923),
    ("P6 · Mayor caída (09/05/2024, %)", valor(p6, "fecha = '2024-05-09'", "caida_pct"), -95.2),
    ("P7 · Traspasadas, var. %", valor(p7, "grupo = 'Traspasadas a CABA'", "var_pct"), -1.7),
]

validacion = spark.createDataFrame(
    [(n, str(spark_v), str(pg_v), "OK" if float(spark_v) == float(pg_v) else "DIFERENTE")
     for n, spark_v, pg_v in esperado],
    "indicador string, spark string, postgresql string, resultado string")
display(validacion)
