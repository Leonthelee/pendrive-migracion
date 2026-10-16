@echo off
:: ============================================================================
:: MINISTERIO DE OBRAS PUBLICAS - DIRECCION GENERAL DE AGUAS (DGA)
:: DGA Core Tools -- by Daniel Diaz L. & AI Engine Antigravity
:: Herramienta: Forzar Inventario GLPI Silencioso (localhost:62354)
:: ============================================================================

:: Ejecucion 100% silenciosa sin mostrar ventanas
curl.exe -s "http://localhost:62354/now?task=inventory" >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -WindowStyle Hidden -Command "try { Invoke-WebRequest -Uri 'http://localhost:62354/now?task=inventory' -UseBasicParsing -TimeoutSec 5 | Out-Null } catch {}"
)
exit /b 0
