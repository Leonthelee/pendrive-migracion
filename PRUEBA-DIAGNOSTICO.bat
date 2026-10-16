@echo off
setlocal
title DGA - Diagnostico sin migracion
powershell.exe -NoProfile -File "%~dp0scripts\09-migracion-segura.ps1" -Accion Diagnostico
echo.
echo El diagnostico no instala ni reinicia. Revise el resultado anterior.
pause
