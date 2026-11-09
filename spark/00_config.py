# Databricks notebook source
# MAGIC %md
# MAGIC # 00 · Configuración
# MAGIC Catálogo, esquema y volumen donde viven los datos. Lo ejecutan los demás notebooks con `%run ./00_config`.
# MAGIC
# MAGIC En Databricks Free Edition el catálogo por defecto es `workspace`. Los CSV crudos se suben al volumen `crudos`.

# COMMAND ----------

CATALOGO = "workspace"
ESQUEMA = "sube"
VOLUMEN = f"/Volumes/{CATALOGO}/{ESQUEMA}/crudos"

spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOGO}.{ESQUEMA}")
spark.sql(f"CREATE VOLUME IF NOT EXISTS {CATALOGO}.{ESQUEMA}.crudos")
spark.sql(f"USE {CATALOGO}.{ESQUEMA}")

print(f"Trabajando en {CATALOGO}.{ESQUEMA} · archivos en {VOLUMEN}")
