@echo off
REM ===============================================================================
REM  DGA Core Tools - by Daniel Díaz L. & AI Engine Antigravity
REM  Lanzador con auto-elevacion UAC para INSTALAR-REMOTO-DGA.ps1
REM ===============================================================================
setlocal EnableDelayedExpansion

set "PS_SCRIPT=%~dp0INSTALAR-REMOTO-DGA.ps1"

if not exist "!PS_SCRIPT!" (
    echo [ERROR] No se encuentra el archivo: !PS_SCRIPT!
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"!PS_SCRIPT!\"'"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!PS_SCRIPT!"
pause
