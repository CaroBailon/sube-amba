# Explorador web: cómo está hecho y por qué

**Página:** [carobailon.github.io/sube-amba](https://carobailon.github.io/sube-amba/)

Una página interactiva para que cualquier persona explore los datos sin instalar nada: evolución por modo, el subte por línea, un buscador de colectivos y los días atípicos. Es el último eslabón del proyecto:

```
CSV de SUBE ──► PostgreSQL (limpieza + modelo estrella) ──► dashboard/datos/*.csv ──► web/exportar_datos.py ──► docs/data/*.json ──► docs/index.html
```

## Cómo actualizarla

```bash
python web/exportar_datos.py      # regenera docs/data/*.json desde dashboard/datos/
```

Para verla en la computadora: `cd docs` y `python -m http.server`, y abrir `http://localhost:8000`. (Abrir el `index.html` con doble clic no funciona: el navegador bloquea la lectura de los JSON desde archivos locales.)

## Decisiones y por qué

### 1. Una página estática, sin servidor
**Opciones:** Streamlit, una API con base de datos, o HTML + JavaScript estático.
**Elegí:** estática (HTML, CSS y JavaScript) publicada con GitHub Pages.
**Por qué:** los datos no cambian mientras alguien mira la página, así que no hace falta un servidor que calcule. Una página estática es gratis, carga rápido, no se "duerme" (como los servicios gratuitos de Streamlit o Render) y vive en el mismo repo que el análisis, con mi nombre en la URL.
**Lo que cedí:** no puedo hacer consultas arbitrarias sobre el millón de filas; todo lo que se puede explorar está precalculado.

### 2. Agregar antes de publicar: de 20 MB a 340 KB
**Problema:** `fact_usos_amba.csv` tiene ~1 millón de filas (20 MB). Mandarlo al navegador haría la página lenta, sobre todo en el celular.
**Elegí:** un script de Python que agrega los datos al nivel que cada gráfico necesita (mes × modo × tipo de día, mes × línea, día × grupo) y genera seis JSON chicos.
**Por qué:** cada sección necesita a lo sumo unos miles de números. Calcular una vez en Python es más rápido y más fácil de verificar que hacerlo en cada visita.

### 3. Una sola fuente de verdad
**Elegí:** que el script lea los mismos CSV que usa Power BI (`dashboard/datos/`), generados por `sql/06_exportar_powerbi.sql`.
**Por qué:** si la web leyera los datos crudos tendría que repetir la limpieza, y dos limpiezas terminan dando números distintos. Así, la limpieza vive en un solo lugar y la web, Power BI, Excel y el notebook de Databricks muestran lo mismo.
**Cómo lo verifiqué:** los números de la página coinciden con los del SQL (11.708.399 viajes por día hábil en 2023, 915.021 → 460.667 en el subte, −36,6% en la línea H). Al principio el premetro daba +242,3% en la web y +242,4% en el SQL: la página calculaba la variación a partir de valores ya redondeados. Lo corregí guardando un decimal.

### 4. Promedios por día, con el calendario como divisor
**Problema:** un mes tiene 18 días hábiles y otro 22; 2026 está incompleto. Comparar totales mezcla "viajó menos gente" con "hubo menos días".
**Elegí:** viajes del mes ÷ días de ese tipo **según el calendario** (no según los días con datos).
**Por qué:** si una línea no tuvo viajes un día, ese día cuenta como cero y no achica el divisor. Así la caída de la línea D en febrero de 2024 se ve como lo que fue: un cierre.

### 5. Índices para comparar cosas de distinto tamaño
**Problema:** el colectivo mueve 10 millones de viajes por día y el subte medio millón. En el mismo gráfico, el subte es una línea plana abajo.
**Elegí:** una opción de índice (2023 = 100, u octubre de 2023 = 100 en el subte) que pone todas las series en la misma escala.
**Por qué:** la pregunta casi nunca es "¿quién mueve más gente?" sino "¿quién cambió más?". En el buscador de colectivos el índice permite ver si una línea perdió más o menos pasajeros que el total.

### 6. Revisar las anomalías antes de publicar
Al probar la página, la línea D aparecía en cero en febrero de 2024. Antes de asumir que era un error del dato lo verifiqué: estuvo **cerrada por obras entre el 8 de enero y el 7 de marzo de 2024**. Quedó explicado en una nota debajo del gráfico. Es la misma lógica que el 10/12/2021: antes de explicar un número, entender cómo se mide.

### 7. Valores por defecto que no engañen
El buscador mostraba primero la línea más usada de 2025, que resultó ser la **501G (Moreno)**: figura primera solo porque se informa agrupada. La cambié por la **línea 60**, una línea conocida y no agrupada, y dejé la aclaración en una nota.

### 8. Diseño pensado para quien lo mira
- **Colores oficiales del subte** (A celeste, B roja, C azul, D verde, E violeta, H amarilla): cualquiera que viaje en subte reconoce las líneas sin leer la leyenda.
- **Funciona en el celular**: los controles se apilan, las tablas anchas se desplazan dentro de su recuadro y el rótulo del aumento se mueve si no entra.
- **Accesible**: controles nativos (`select`, `radio`, `checkbox`) que se usan con teclado, áreas táctiles de al menos 44 px y una descripción de cada gráfico para lectores de pantalla.
- **Link compartible**: el buscador guarda la línea en la URL (`?linea=Línea 152`), así se puede mandar una vista exacta.
- **Trazabilidad**: la sección "Sobre los datos" muestra el período, la fecha de generación y cómo se calcula cada número.

### 9. Herramientas
- **Chart.js** para los gráficos: liviano, sin paso de compilación y suficiente para líneas y barras. Plotly hubiera sumado ~3 MB para funciones que no uso.
- **Sin frameworks** (React, Vue): para cuatro secciones, JavaScript simple es más fácil de leer y mantener.
- **Probada con Chrome sin interfaz (Playwright)** en escritorio y celular: errores de consola, interacciones del buscador y de la tabla, y capturas de cada sección.

## Qué haría con más tiempo
- Un mapa por municipio, que hoy no es posible: el municipio falta en el 60% de los registros.
- Comparar viajes con población o con oferta de servicio, para hablar de tasas y no solo de cantidades.
- Automatizar la actualización mensual con GitHub Actions: descargar los CSV nuevos, correr el pipeline y regenerar los JSON.
