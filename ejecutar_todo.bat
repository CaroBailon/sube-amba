@echo off
REM ==================================================================
REM  Ejecuta todo el pipeline: carga, limpieza, modelo y controles.
REM  Doble clic sobre este archivo (o ejecutalo desde la consola).
REM ==================================================================
chcp 65001 >nul
cd /d "%~dp0"

REM Busca psql: primero en el PATH, si no en la carpeta de instalacion
set "PSQL=psql"
where psql >nul 2>nul
if errorlevel 1 (
    for /d %%d in ("C:\Program Files\PostgreSQL\*") do set "PSQL=%%d\bin\psql.exe"
)

set /p PGPASSWORD=Contrasena del usuario postgres:

echo.
echo Creando la base "sube" (si ya existe, el error se puede ignorar)...
"%PSQL%" -U postgres -c "CREATE DATABASE sube;"

for %%f in (01_cargar_crudos 02_limpiar 03_modelo_estrella 04_controles_calidad) do (
    echo.
    echo ===== %%f =====
    "%PSQL%" -U postgres -d sube -v ON_ERROR_STOP=1 -f sql\%%f.sql
    if errorlevel 1 goto error
)

echo.
echo Listo. Revisa que todos los controles digan OK.
set PGPASSWORD=
pause
exit /b 0

:error
echo.
echo Hubo un error en el paso anterior. Revisa el mensaje de arriba: indica el script y la linea.
echo Lo mas comun: falta alguno de los 7 CSV en data\raw\ o tiene otro nombre.
set PGPASSWORD=
pause
exit /b 1
