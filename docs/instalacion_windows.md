# Cómo correr el proyecto en Windows

Tiempo estimado: 30–40 minutos la primera vez.

## 1. Instalar PostgreSQL

1. Descargá el instalador desde https://www.postgresql.org/download/windows/ (botón *Download the installer*, la versión más nueva).
2. En el instalador dejá marcados: **PostgreSQL Server** y **Command Line Tools**. Stack Builder no hace falta.
3. Elegí una contraseña para el usuario `postgres` y **anotala**.
4. Puerto: dejá el 5432. Idioma (*locale*): el que venga por defecto.

## 2. Instalar DBeaver (para escribir consultas)

1. Descargá DBeaver Community desde https://dbeaver.io/download/
2. Abrilo → *Nueva conexión* → PostgreSQL → host `localhost`, base `sube`, usuario `postgres` y tu contraseña. Si te pide descargar el driver, aceptá.
   (Hacé este paso después del 4, cuando la base `sube` ya exista.)

## 3. Armar la carpeta del proyecto

1. Cloná el repositorio (`git clone https://github.com/CaroBailon/sube-amba.git`) o descargalo como zip desde GitHub, en una carpeta sin tildes ni espacios, por ejemplo `C:\proyectos\sube-amba`.
2. Copiá los 7 CSV (`dat-ab-usos-2020.csv` … `dat-ab-usos-2026.csv`) dentro de `data\raw\`.

## 4. Ejecutar el pipeline

Doble clic en **`ejecutar_todo.bat`**. Te pide la contraseña de `postgres` una sola vez y corre los 4 scripts. Tarda entre 1 y 3 minutos.

Al final tenés que ver la tabla de controles con **OK en las 6 filas**.

Si algo falla, el mensaje indica en qué script y en qué línea se cortó. El error más común es que falte alguno de los 7 CSV en `data\raw\` o que tenga otro nombre.

## 5. Conectar Power BI

1. Instalá **Power BI Desktop** desde Microsoft Store (gratis).
2. *Obtener datos* → *Base de datos PostgreSQL* → servidor `localhost`, base de datos `sube` → modo **Importar**.
3. Usuario `postgres` y tu contraseña (pestaña *Base de datos*, no *Windows*).
4. Marcá las 4 tablas del esquema `dw`: `dw.fact_usos`, `dw.dim_fecha`, `dw.dim_linea`, `dw.dim_empresa`.
5. En la vista *Modelo*, verificá que Power BI haya creado estas relaciones (si no, arrastralas):
   - `fact_usos[fecha]` → `dim_fecha[fecha]`
   - `fact_usos[linea_key]` → `dim_linea[linea_key]`
   - `fact_usos[empresa_key]` → `dim_empresa[empresa_key]`
6. Marcá `dim_fecha` como **tabla de fechas** (clic derecho → *Marcar como tabla de fechas* → columna `fecha`).

Si al conectar aparece un error de certificado SSL, en la ventana de conexión desmarcá *Cifrar conexión*. Es seguro porque la base está en tu propia computadora.
