@echo off
setlocal EnableDelayedExpansion
title Copiar Toolkit GLPI a Pendrive - DGA Core Tools
color 0B

echo ============================================================================
echo   COPIAR TOOLKIT GLPI PORTABLE A PENDRIVE
echo   DGA Core Tools -- by Daniel Diaz L. & AI Engine Antigravity
echo ============================================================================
echo.

echo Detectando unidades disponibles...
powershell -NoProfile -Command "Get-WmiObject Win32_LogicalDisk | Select-Object DeviceID, VolumeName, @{Name='TamanoGB';Expression={[Math]::Round($_.Size/1GB,1)}}, @{Name='LibreGB';Expression={[Math]::Round($_.FreeSpace/1GB,1)}} | Format-Table -AutoSize"

echo.
set "LETRA="
set /p "LETRA=Ingrese la letra de su pendrive (por ejemplo E o F): "
if "%LETRA%"=="" (
    echo No se especifico ninguna letra. Operacion cancelada.
    pause
    exit /b 1
)

set "LETRA=%LETRA::=%"
set "DESTINO=%LETRA%:\GLPI_Portable_DGA"

echo.
echo [*] Creando carpeta en el pendrive: %DESTINO%
mkdir "%DESTINO%" >nul 2>&1

echo [*] Copiando instalador original MSI (23 MB)...
copy /y "%~dp0GLPI-Agent-1.17-x64.msi" "%DESTINO%\"

echo [*] Copiando scripts portables...
copy /y "%~dp0INSTALAR_GLPI_PENDRIVE.bat" "%DESTINO%\"
copy /y "%~dp0EJECUTAR_SILENCIOSO_LOCALHOST_62354.bat" "%DESTINO%\"
copy /y "%~dp0VERIFICAR_ESTADO_GLPI.bat" "%DESTINO%\"
copy /y "%~dp0LEEME_PENDRIVE.txt" "%DESTINO%\"

echo.
echo ============================================================================
echo   COPIA COMPLETADA CON EXITO EN: %DESTINO%
echo   Ahora puede llevar el pendrive y conectar en cualquier equipo de la red.
echo ============================================================================
echo.
pause
