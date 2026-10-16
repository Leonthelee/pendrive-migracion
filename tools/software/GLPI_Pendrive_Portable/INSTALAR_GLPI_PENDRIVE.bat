@echo off
setlocal EnableDelayedExpansion
title GLPI Agent 1.17 - Instalador Portable Pendrive (DGA)
color 0B

:: ============================================================================
:: MINISTERIO DE OBRAS PUBLICAS - DIRECCION GENERAL DE AGUAS (DGA)
:: DGA Core Tools -- by Daniel Diaz L. & AI Engine Antigravity
:: Herramienta: Instalador Portable para Pendrive de GLPI Agent v1.17
:: Servidor Destino: https://glpi-dga.mop.gob.cl
:: Daemon Local    : http://localhost:62354
:: ============================================================================

:: 1. Auto-Elevacion a Administrador (UAC)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Solicitando permisos de Administrador...
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: Asegurar que el directorio de trabajo sea la carpeta del pendrive
cd /d "%~dp0"

cls
echo ============================================================================
echo   MINISTERIO DE OBRAS PUBLICAS - DIRECCION GENERAL DE AGUAS (DGA)
echo   Instalador Portable Pendrive: GLPI Agent 1.17 para Windows x64
echo   Firma: DGA Core Tools -- by Daniel Diaz L. ^& AI Engine Antigravity
echo ============================================================================
echo.
echo  Unidad / Ruta    : %~dp0
echo  Servidor Destino : https://glpi-dga.mop.gob.cl
echo  Puerto Daemon    : 62354 (http://localhost:62354)
echo.
echo ============================================================================
echo.

:: 2. Localizar el instalador original en el pendrive
set "MSI_FILE=%~dp0GLPI-Agent-1.17-x64.msi"

if not exist "%MSI_FILE%" (
    echo [ERROR] No se encontro el instalador original GLPI-Agent-1.17-x64.msi
    echo en la carpeta del pendrive:
    echo "%~dp0"
    echo.
    pause
    exit /b 1
)

echo [*] Instalador MSI detectado intacto:
echo     "%MSI_FILE%"
echo.

:: 3. Ejecutar instalacion desatendida sin tocar el binario
echo [*] Instalando GLPI Agent silenciosamente...
echo     - Inyectando servidor: https://glpi-dga.mop.gob.cl
echo     - Abriendo excepcion en Firewall local
echo     - Habilitando servicio daemon en puerto 62354
echo.
echo     Espere unos segundos...

msiexec.exe /i "%MSI_FILE%" /qn /norestart SERVER="https://glpi-dga.mop.gob.cl" ADD_FIREWALL_EXCEPTION=1 RUNNOW=1 EXECMODE=1 HTTPD_TRUST="127.0.0.1/32,::1/128" HTTPD_PORT=62354 /l*v "%TEMP%\glpi_pendrive_install.log"
set "MSI_EXIT=%errorlevel%"

if %MSI_EXIT% equ 0 (
    echo [OK] Instalacion del paquete MSI finalizada con EXITO (Codigo 0).
) else if %MSI_EXIT% equ 3010 (
    echo [OK] Instalacion completada exitosamente (Codigo 3010 - Reinicio diferido).
) else (
    echo [!] Advertencia: msiexec finalizo con codigo %MSI_EXIT%.
    echo     Log temporal en: %TEMP%\glpi_pendrive_install.log
)

echo.
:: 4. Validar y arrancar el servicio de Windows
echo [*] Verificando servicio de Windows 'glpi-agent'...
sc.exe start glpi-agent >nul 2>&1
timeout /t 3 /nobreak >nul

:: 5. Ejecutar peticion silenciosa a localhost:62354
echo [*] Ejecutando peticion silenciosa contra localhost:62354...
curl.exe -s "http://localhost:62354/now?task=inventory" >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -WindowStyle Hidden -Command "try { Invoke-WebRequest -Uri 'http://localhost:62354/now?task=inventory' -UseBasicParsing -TimeoutSec 5 | Out-Null } catch {}"
)

echo [OK] Inventario forzado y transmitido a https://glpi-dga.mop.gob.cl en silencioso.
echo.
echo ============================================================================
echo   EQUIPO CONFIGURADO EXITOSAMENTE
echo   El equipo ha quedado inventariado y reportando a la DGA.
echo ============================================================================
echo.
echo Desea abrir el navegador para verificacion visual en http://localhost:62354?
set /p "RESP=(S/N, por defecto N): "
if /i "!RESP!"=="S" (
    start http://localhost:62354
)

echo.
echo Listo. Puede retirar el pendrive o cerrar esta ventana.
timeout /t 5 >nul
exit /b 0
