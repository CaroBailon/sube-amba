// Explorador de movilidad en el AMBA con datos de SUBE.
// Lee los JSON de data/ (generados por web/exportar_datos.py) y dibuja los gráficos con Chart.js.

const COLORES = {
  COLECTIVO: "#1565D8", TREN: "#0F766E", SUBTE: "#C2410C",
  // Colores oficiales de cada línea de subte, para que se reconozcan sin leer la leyenda
  "Subte A": "#18A9E2", "Subte B": "#E2231A", "Subte C": "#1F5AA6", "Subte D": "#00A665",
  "Subte E": "#6C2C91", "Subte H": "#E0A100", Premetro: "#6B7280",
  linea: "#C2410C", total: "#6B7280",
};
const NOMBRE_MODO = { COLECTIVO: "Colectivo", TREN: "Tren", SUBTE: "Subte" };
const MES_AUMENTO = "2024-05";

const num = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 0 });
const dec = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 1, minimumFractionDigits: 1 });
const pct = (v) => (v > 0 ? "+" : v < 0 ? "−" : "") + dec.format(Math.abs(v)) + "%";
const NOMBRES_MES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
const etiquetaMes = (m) => NOMBRES_MES[+m.slice(5, 7) - 1] + " " + m.slice(0, 4);
const etiquetaFecha = (f) => new Date(f + "T12:00:00").toLocaleDateString("es-AR", { weekday: "short", day: "numeric", month: "short", year: "numeric" });

Chart.defaults.font.family = "Inter, system-ui, sans-serif";
Chart.defaults.font.size = 13;
Chart.defaults.color = "#4B5563";

// Línea vertical que marca el aumento de tarifa del subte (plugin propio, sin dependencias)
const marcaAumento = {
  id: "marcaAumento",
  afterDatasetsDraw(chart, _args, opts) {
    if (!opts || !opts.mes) return;
    const i = chart.data.labels.indexOf(opts.mes);
    if (i < 0) return;
    const x = chart.scales.x.getPixelForValue(i);
    const { top, bottom } = chart.chartArea;
    const ctx = chart.ctx;
    ctx.save();
    ctx.strokeStyle = "#C2410C"; ctx.lineWidth = 2; ctx.setLineDash([6, 6]);
    ctx.beginPath(); ctx.moveTo(x, top); ctx.lineTo(x, bottom); ctx.stroke();
    ctx.setLineDash([]); ctx.fillStyle = "#C2410C"; ctx.font = "600 12px Inter, sans-serif";
    const texto = "Aumento del subte";
    const ancho = ctx.measureText(texto).width;
    // Si no entra a la derecha de la línea (pantallas chicas), se escribe a la izquierda
    const xTexto = x + 6 + ancho > chart.chartArea.right ? x - 6 - ancho : x + 6;
    ctx.fillText(texto, xTexto, top + 14);
    ctx.restore();
  },
};
Chart.register(marcaAumento);

function opcionesLinea({ indice = false, marcar = false } = {}) {
  return {
    responsive: true, maintainAspectRatio: false, animation: false,
    interaction: { mode: "index", intersect: false },
    elements: { point: { radius: 0, hoverRadius: 4 }, line: { borderWidth: 2.5, tension: 0 } },
    scales: {
      x: { grid: { display: false }, ticks: { maxRotation: 0, autoSkip: true, maxTicksLimit: 8, callback(v) { return etiquetaMes(this.getLabelForValue(v)); } } },
      y: { beginAtZero: !indice, grid: { color: "#E5E7EB" }, ticks: { callback: (v) => num.format(v) } },
    },
    plugins: {
      legend: { position: "bottom", labels: { boxWidth: 14, boxHeight: 14 } },
      tooltip: { callbacks: { title: (it) => etiquetaMes(it[0].label), label: (c) => `${c.dataset.label}: ${c.raw == null ? "sin datos" : num.format(c.raw)}` } },
      marcaAumento: { mes: marcar ? MES_AUMENTO : null },
    },
  };
}

function dataset(etiqueta, valores, color, extra = {}) {
  return { label: etiqueta, data: valores, borderColor: color, backgroundColor: color, spanGaps: false, ...extra };
}

// Índice: cada valor dividido por la base (promedio de los meses elegidos) × 100
function aIndice(valores, meses, mesesBase) {
  const base = valores.filter((_, i) => mesesBase(meses[i]) && valores[i] != null);
  const prom = base.reduce((a, b) => a + b, 0) / (base.length || 1);
  return valores.map((v) => (v == null || !prom ? null : Math.round((v / prom) * 1000) / 10));
}

function medidaElegida(nombre) { return document.querySelector(`input[name="${nombre}"]:checked`).value; }

function checkboxes(contenedor, items, marcados, alCambiar) {
  const fs = document.getElementById(contenedor);
  items.forEach(({ valor, texto }) => {
    const l = document.createElement("label");
    l.innerHTML = `<input type="checkbox" value="${valor}" ${marcados.includes(valor) ? "checked" : ""}> ${texto}`;
    fs.appendChild(l);
  });
  fs.addEventListener("change", alCambiar);
  return () => [...fs.querySelectorAll("input:checked")].map((i) => i.value);
}

async function cargar(nombre) {
  const r = await fetch(`data/${nombre}.json`);
  if (!r.ok) throw new Error(`No se pudo cargar ${nombre}.json`);
  return r.json();
}

// ---------------------------------------------------------------------------
async function iniciar() {
  const [modos, subte, cole, diario, atipicos, meta] = await Promise.all(
    ["modos", "subte", "colectivos", "diario", "atipicos", "meta"].map(cargar));

  // Sobre los datos
  document.getElementById("meta-fuente").textContent = meta.fuente;
  const fechaLarga = (f) => new Date(f + "T12:00:00").toLocaleDateString("es-AR", { day: "numeric", month: "long", year: "numeric" });
  document.getElementById("meta-periodo").textContent = `del ${fechaLarga(meta.desde)} al ${fechaLarga(meta.hasta)}`;
  document.getElementById("meta-generado").textContent = meta.generado.split("-").reverse().join("/");

  // ---- Indicadores ----
  const anual = (anio) => {
    const idx = modos.meses.map((m, i) => (m.startsWith(anio) ? i : -1)).filter((i) => i >= 0);
    const viajes = idx.reduce((s, i) => s + modos.modos.reduce((t, m) => t + modos.usos[m]["Hábil"][i], 0), 0);
    const dias = idx.reduce((s, i) => s + modos.dias["Hábil"][i], 0);
    return viajes / dias;
  };
  const ultimoAnio = modos.meses.at(-1).slice(0, 4);
  document.getElementById("kpi-amba").textContent = pct((anual(ultimoAnio) / anual("2023") - 1) * 100);
  const iOct23 = subte.meses.indexOf("2023-10"), iOct26 = subte.meses.indexOf("2026-10");
  document.getElementById("kpi-subte").textContent = pct((subte.total[iOct26] / subte.total[iOct23] - 1) * 100);
  const viajes2025 = (m) => modos.meses.reduce((s, mes, i) => s + (mes.startsWith("2025") ? modos.tipos.reduce((t, tp) => t + modos.usos[m][tp][i], 0) : 0), 0);
  const total2025 = modos.modos.reduce((s, m) => s + viajes2025(m), 0);
  document.getElementById("kpi-cole").textContent = dec.format((viajes2025("COLECTIVO") / total2025) * 100) + "%";

  // ---- 1. Por modo ----
  const grafModos = new Chart(document.getElementById("graf-modos"), { type: "line", data: { labels: modos.meses, datasets: [] }, options: opcionesLinea() });
  const modosElegidos = checkboxes("modos-check", modos.modos.map((m) => ({ valor: m, texto: NOMBRE_MODO[m] })), modos.modos, dibujarModos);
  document.getElementById("modos-tipo").addEventListener("change", dibujarModos);
  document.querySelectorAll('input[name="modos-medida"]').forEach((r) => r.addEventListener("change", dibujarModos));

  function promedioModo(modo, tipo) {
    const tipos = tipo === "Todos" ? modos.tipos : [tipo];
    return modos.meses.map((_, i) => {
      const viajes = tipos.reduce((s, t) => s + modos.usos[modo][t][i], 0);
      const dias = tipos.reduce((s, t) => s + modos.dias[t][i], 0);
      return dias ? Math.round(viajes / dias) : null; // un mes sin feriados no tiene promedio de feriado
    });
  }

  function dibujarModos() {
    const tipo = document.getElementById("modos-tipo").value;
    const indice = medidaElegida("modos-medida") === "indice";
    grafModos.data.datasets = modosElegidos().map((m) => {
      let v = promedioModo(m, tipo);
      if (indice) v = aIndice(v, modos.meses, (mes) => mes.startsWith("2023"));
      return dataset(NOMBRE_MODO[m], v, COLORES[m], { spanGaps: true });
    });
    grafModos.options = opcionesLinea({ indice });
    grafModos.update();
    document.getElementById("modos-nota").textContent = ["Feriado", "No laborable"].includes(tipo)
      ? "Hay pocos feriados y puentes por mes, así que la serie salta más y los meses sin ese tipo de día se unen con una línea recta."
      : "2020 y 2021 están marcados por la pandemia: la comparación más útil es contra 2023, el año de mayor demanda.";
  }
  dibujarModos();

  // ---- 2. Subte por línea ----
  const grafSubte = new Chart(document.getElementById("graf-subte"), { type: "line", data: { labels: subte.meses, datasets: [] }, options: opcionesLinea({ marcar: true }) });
  const subteElegidas = checkboxes("subte-check", subte.lineas.map((l) => ({ valor: l, texto: l.replace("Subte ", "Línea ") })),
    subte.lineas.filter((l) => l !== "Premetro"), dibujarSubte);
  document.querySelectorAll('input[name="subte-medida"]').forEach((r) => r.addEventListener("change", dibujarSubte));

  function dibujarSubte() {
    const indice = medidaElegida("subte-medida") === "indice";
    grafSubte.data.datasets = subteElegidas().map((l) => {
      let v = subte.promedio[l];
      if (indice) v = aIndice(v, subte.meses, (mes) => mes === "2023-10");
      return dataset(l.replace("Subte ", "Línea "), v, COLORES[l]);
    });
    grafSubte.options = opcionesLinea({ indice, marcar: true });
    grafSubte.update();
  }
  dibujarSubte();

  const filas = subte.lineas.map((l) => ({ l, a: subte.promedio[l][iOct23], b: subte.promedio[l][iOct26] }))
    .map((f) => ({ ...f, v: (f.b / f.a - 1) * 100 })).sort((x, y) => x.v - y.v);
  filas.push({ l: "Total subte", a: subte.total[iOct23], b: subte.total[iOct26], v: (subte.total[iOct26] / subte.total[iOct23] - 1) * 100, total: true });
  document.querySelector("#subte-tabla tbody").innerHTML = filas.map((f) =>
    `<tr${f.total ? ' style="font-weight:700"' : ""}><td>${f.l.replace("Subte ", "Línea ")}</td><td class="num">${num.format(f.a)}</td><td class="num">${num.format(f.b)}</td><td class="num">${pct(f.v)}</td></tr>`).join("");

  // ---- 3. Colectivos ----
  const lista = document.getElementById("cole-lista");
  lista.innerHTML = cole.lineas.map((l) => `<option value="${l.nombre}"></option>`).join("");
  const grafCole = new Chart(document.getElementById("graf-cole"), { type: "line", data: { labels: cole.meses, datasets: [] }, options: opcionesLinea() });
  const busca = document.getElementById("cole-busca");
  const porNombre = new Map(cole.lineas.map((l, i) => [l.nombre.toLowerCase(), i]));
  const anuales = (serie, anio) => {
    const v = serie.filter((x, i) => x != null && cole.meses[i].startsWith(anio));
    return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null;
  };

  function encontrar(texto) {
    const t = texto.trim().toLowerCase();
    if (!t) return -1;
    if (porNombre.has(t)) return porNombre.get(t);
    if (porNombre.has("línea " + t)) return porNombre.get("línea " + t);
    const i = cole.lineas.findIndex((l) => l.nombre.toLowerCase().startsWith("línea " + t + " "));
    return i;
  }

  function dibujarCole(actualizarUrl = true) {
    const i = encontrar(busca.value);
    const aviso = document.getElementById("cole-aviso");
    if (i < 0) {
      aviso.textContent = busca.value.trim() ? "No encontré esa línea. Probá con el número solo, por ejemplo 60 o 152." : "";
      return;
    }
    aviso.textContent = "";
    const linea = cole.lineas[i], serie = cole.promedio[i];
    const indice = medidaElegida("cole-medida") === "indice";
    const p23 = anuales(serie, "2023"), p25 = anuales(serie, "2025");
    const t23 = anuales(cole.total, "2023"), t25 = anuales(cole.total, "2025");
    const varLinea = p23 && p25 ? (p25 / p23 - 1) * 100 : null;
    const varTotal = (t25 / t23 - 1) * 100;
    document.getElementById("cole-ficha").innerHTML = `
      <div><span class="dato">${linea.nombre}</span><span class="rotulo">Jurisdicción: ${(linea.jurisdiccion || "sin dato").toLowerCase()}</span></div>
      <div><span class="dato">${p25 ? num.format(p25) : "—"}</span><span class="rotulo">viajes por día hábil en 2025</span></div>
      <div><span class="dato">${linea.ranking_2025 ? linea.ranking_2025 + "ª" : "—"}</span><span class="rotulo">de ${cole.total_lineas_2025} líneas por viajes en 2025</span></div>
      <div><span class="dato">${varLinea == null ? "—" : pct(varLinea)}</span><span class="rotulo">2025 vs. 2023 (total colectivos: ${pct(varTotal)})</span></div>`;
    const sets = indice
      ? [dataset(linea.nombre, aIndice(serie, cole.meses, (m) => m.startsWith("2023")), COLORES.linea),
         dataset("Total colectivos", aIndice(cole.total, cole.meses, (m) => m.startsWith("2023")), COLORES.total, { borderDash: [6, 4] })]
      : [dataset(linea.nombre, serie, COLORES.linea)];
    grafCole.data.datasets = sets;
    grafCole.options = opcionesLinea({ indice });
    grafCole.update();
    // Solo cuando la persona busca una línea: así el link de la portada queda limpio
    if (actualizarUrl) history.replaceState(null, "", `?linea=${encodeURIComponent(linea.nombre)}#colectivos`);
  }
  busca.addEventListener("input", () => dibujarCole());
  busca.addEventListener("change", () => dibujarCole());
  document.querySelectorAll('input[name="cole-medida"]').forEach((r) => r.addEventListener("change", () => dibujarCole()));
  const inicial = new URLSearchParams(location.search).get("linea");
  // Por defecto, una línea conocida y no agrupada (la 501G figura primera solo porque se informa agrupada)
  const porDefecto = cole.lineas.find((l) => l.nombre === "Línea 60") || cole.lineas[0];
  busca.value = inicial || porDefecto.nombre;
  dibujarCole(false);

  // ---- 4. Días atípicos ----
  const grafAtip = new Chart(document.getElementById("graf-atip"), {
    type: "bar", data: { labels: [], datasets: [] },
    options: {
      responsive: true, maintainAspectRatio: false, animation: false,
      scales: {
        x: { stacked: true, grid: { display: false }, ticks: { maxRotation: 0, autoSkip: true, maxTicksLimit: 7 } },
        y: { stacked: true, grid: { color: "#E5E7EB" }, ticks: { callback: (v) => num.format(v / 1e6) + " M" } },
      },
      plugins: {
        legend: { position: "bottom", labels: { boxWidth: 14, boxHeight: 14 } },
        tooltip: { callbacks: { title: (it) => etiquetaFecha(grafAtip.$fechas[it[0].dataIndex]), label: (c) => `${c.dataset.label}: ${num.format(c.raw)}` } },
      },
    },
  });

  function colorBarra(base, fechas, tipos, evento) {
    return fechas.map((f, i) => (f === evento ? (base === "c" ? "#C2410C" : "#F59E0B") : tipos[i] === "Hábil" ? (base === "c" ? "#1565D8" : "#0F766E") : (base === "c" ? "#BFD3F2" : "#B7DCD8")));
  }

  function mostrarEvento(ev, fila) {
    document.querySelectorAll("#atip-tabla tr.activo").forEach((tr) => tr.classList.remove("activo"));
    fila.classList.add("activo");
    const i = diario.fechas.indexOf(ev.fecha);
    const desde = Math.max(0, i - 10), hasta = Math.min(diario.fechas.length, i + 5);
    const fechas = diario.fechas.slice(desde, hasta), tipos = diario.tipo.slice(desde, hasta);
    grafAtip.$fechas = fechas;
    grafAtip.data.labels = fechas.map((f) => new Date(f + "T12:00:00").toLocaleDateString("es-AR", { day: "numeric", month: "numeric" }));
    grafAtip.data.datasets = [
      { label: "Colectivo", data: diario.colectivo.slice(desde, hasta), backgroundColor: colorBarra("c", fechas, tipos, ev.fecha) },
      { label: "Tren y subte", data: diario.tren_subte.slice(desde, hasta), backgroundColor: colorBarra("t", fechas, tipos, ev.fecha) },
    ];
    grafAtip.update();
    const c = diario.colectivo[i], t = diario.tren_subte[i];
    document.getElementById("atip-detalle").innerHTML =
      `<strong>${etiquetaFecha(ev.fecha)} · ${ev.tipo}.</strong> ${ev.causa}. Ese día se registraron ${num.format(c + t)} viajes (${num.format(c)} en colectivo), ${String(ev.caida_pct).replace("-", "−")}% contra la semana previa.`;
  }

  const cuerpo = document.querySelector("#atip-tabla tbody");
  atipicos.forEach((ev, k) => {
    const tr = document.createElement("tr");
    tr.innerHTML = `<td><button type="button">${ev.fecha.split("-").reverse().join("/")}</button></td><td>${ev.tipo}</td><td class="num">${String(ev.caida_pct).replace("-", "−")}%</td>`;
    tr.querySelector("button").addEventListener("click", () => mostrarEvento(ev, tr));
    cuerpo.appendChild(tr);
    if (k === 0) mostrarEvento(ev, tr);
  });
}

iniciar().catch((e) => {
  console.error(e);
  document.querySelector("main").insertAdjacentHTML("afterbegin",
    `<p class="aviso" role="alert">No se pudieron cargar los datos. Si abriste el archivo directamente, servilo con un servidor local (python -m http.server).</p>`);
});
