@echo off
setlocal
title DGA - Simulacion de software
powershell.exe -NoProfile -File "%~dp0scripts\07-software-dga.ps1" -Simular
echo.
echo La simulacion no ejecuta instaladores.
pause
