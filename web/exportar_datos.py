"""
Genera los datos de la página interactiva (docs/) a partir de los CSV del modelo.

Entrada:  dashboard/datos/  (los mismos archivos que usa Power BI, generados por sql/06_exportar_powerbi.sql)
Salida:   docs/data/*.json  (agregados chicos que el navegador puede cargar rápido)

Uso:      python web/exportar_datos.py
"""
import json
from pathlib import Path

import pandas as pd

RAIZ = Path(__file__).resolve().parent.parent
ENTRADA = RAIZ / "dashboard" / "datos"
SALIDA = RAIZ / "docs" / "data"
SALIDA.mkdir(parents=True, exist_ok=True)

MODOS = ["COLECTIVO", "TREN", "SUBTE"]
TIPOS = ["Hábil", "Sábado", "Domingo", "Feriado", "No laborable"]


def guardar(nombre, objeto):
    ruta = SALIDA / nombre
    ruta.write_text(json.dumps(objeto, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"{nombre:<18} {ruta.stat().st_size / 1024:7.1f} KB")


def redondear(serie, decimales=0):
    """Redondea, y deja None donde no hay dato (JSON no tiene NaN).
    Con decimales=1 las variaciones que calcula la página coinciden con las del SQL."""
    if decimales:
        return [None if pd.isna(v) else round(float(v), decimales) for v in serie]
    return [None if pd.isna(v) else int(round(v)) for v in serie]


# --- Carga -------------------------------------------------------------
fact = pd.read_csv(ENTRADA / "fact_usos_amba.csv", parse_dates=["fecha"])
fechas = pd.read_csv(ENTRADA / "dim_fecha.csv", parse_dates=["fecha", "inicio_mes"])
lineas = pd.read_csv(ENTRADA / "dim_linea.csv")
atipicos = pd.read_csv(ENTRADA / "dias_atipicos.csv", parse_dates=["fecha"])

# El calendario se recorta al período con datos
desde, hasta = fact["fecha"].min(), fact["fecha"].max()
fechas = fechas[(fechas["fecha"] >= desde) & (fechas["fecha"] <= hasta)]

usos = (fact.merge(lineas[["linea_key", "modo", "linea_canonica", "jurisdiccion_principal"]], on="linea_key")
            .merge(fechas[["fecha", "inicio_mes", "tipo_dia"]], on="fecha"))

meses = sorted(fechas["inicio_mes"].unique())
etiquetas_mes = [pd.Timestamp(m).strftime("%Y-%m") for m in meses]

# Días de cada tipo en cada mes, desde el CALENDARIO (no desde los datos):
# así un día sin viajes de una línea cuenta como cero y no achica el divisor.
dias = (fechas.groupby(["inicio_mes", "tipo_dia"]).size()
              .unstack(fill_value=0).reindex(index=meses, columns=TIPOS, fill_value=0))
dias_habiles = dias["Hábil"]

# --- 1. Evolución por modo y tipo de día --------------------------------
por_modo = (usos.groupby(["modo", "tipo_dia", "inicio_mes"])["cantidad"].sum()
                .unstack("inicio_mes").reindex(columns=meses).fillna(0))
guardar("modos.json", {
    "meses": etiquetas_mes,
    "tipos": TIPOS,
    "modos": MODOS,
    # usos[modo][tipo] = viajes totales de cada mes; el promedio diario se calcula en la página
    "usos": {m: {t: [int(v) for v in por_modo.loc[(m, t)]] if (m, t) in por_modo.index else [0] * len(meses)
                 for t in TIPOS} for m in MODOS},
    "dias": {t: [int(v) for v in dias[t]] for t in TIPOS},
})


def promedio_habil(df, columna):
    """Promedio de viajes por día hábil de cada mes, para cada valor de `columna`."""
    habiles = df[df["tipo_dia"] == "Hábil"]
    total_mes = (habiles.groupby([columna, "inicio_mes"])["cantidad"].sum()
                        .unstack("inicio_mes").reindex(columns=meses))
    return total_mes.div(dias_habiles.values, axis=1)  # meses sin registros quedan en NaN


# --- 2. Subte por línea ---------------------------------------------------
subte = promedio_habil(usos[usos["modo"] == "SUBTE"], "linea_canonica")
orden_subte = ["Subte A", "Subte B", "Subte C", "Subte D", "Subte E", "Subte H", "Premetro"]
guardar("subte.json", {
    "meses": etiquetas_mes,
    "lineas": orden_subte,
    "promedio": {l: redondear(subte.loc[l], 1) for l in orden_subte},
    "total": redondear(subte.sum(axis=0, min_count=1), 1),
})

# --- 3. Colectivos por línea ----------------------------------------------
colectivos = usos[usos["modo"] == "COLECTIVO"]
cole = promedio_habil(colectivos, "linea_canonica")
juris = (colectivos.groupby("linea_canonica")["jurisdiccion_principal"]
                   .agg(lambda s: s.mode().iat[0] if not s.mode().empty else None))
total_2025 = colectivos[colectivos["fecha"].dt.year == 2025].groupby("linea_canonica")["cantidad"].sum()
ranking = total_2025.rank(ascending=False, method="min")
nombres = sorted(cole.index, key=lambda n: (len(n), n))  # "Línea 2" antes que "Línea 10"
guardar("colectivos.json", {
    "meses": etiquetas_mes,
    "lineas": [{"nombre": n,
                "jurisdiccion": juris.get(n),
                "ranking_2025": None if pd.isna(ranking.get(n)) else int(ranking[n])} for n in nombres],
    "total_lineas_2025": int(total_2025.size),
    "promedio": [redondear(cole.loc[n]) for n in nombres],
    "total": redondear(cole.sum(axis=0, min_count=1)),
})

# --- 4. Serie diaria y días atípicos --------------------------------------
diario = (usos.assign(grupo=usos["modo"].where(usos["modo"] == "COLECTIVO", "TREN_SUBTE"))
              .groupby(["fecha", "grupo"])["cantidad"].sum().unstack(fill_value=0)
              .reindex(fechas["fecha"].sort_values(), fill_value=0))
tipo_por_fecha = fechas.set_index("fecha")["tipo_dia"]
guardar("diario.json", {
    "fechas": [f.strftime("%Y-%m-%d") for f in diario.index],
    "tipo": [tipo_por_fecha[f] for f in diario.index],
    "colectivo": [int(v) for v in diario["COLECTIVO"]],
    "tren_subte": [int(v) for v in diario["TREN_SUBTE"]],
})
guardar("atipicos.json", [
    {"fecha": r.fecha.strftime("%Y-%m-%d"), "caida_pct": int(r.caida_pct),
     "tipo": r.tipo_evento, "causa": r.causa}
    for r in atipicos.sort_values("caida_pct").itertuples()
])

# --- Trazabilidad -----------------------------------------------------------
guardar("meta.json", {
    "desde": desde.strftime("%Y-%m-%d"),
    "hasta": hasta.strftime("%Y-%m-%d"),
    "generado": pd.Timestamp.now(tz="America/Argentina/Buenos_Aires").strftime("%Y-%m-%d"),
    "fuente": "SUBE – Cantidad de transacciones (usos) por fecha. Ministerio de Transporte (datos.transporte.gob.ar).",
})
