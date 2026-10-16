@echo off
setlocal
title DGA - Migracion v4 - Piloto
pushd "%~dp0"
rem --- Intro HTML en el navegador ---
if exist "%~dp0intro.html" start "" "%~dp0intro.html"
rem --- Intro estilo Matrix en consola (el menu sigue aunque falle) ---
if exist "%~dp0scripts\matrix-intro.ps1" powershell.exe -NoProfile -File "%~dp0scripts\matrix-intro.ps1" -Duration 6
powershell.exe -NoProfile -File "%~dp0scripts\menu.ps1"
set "RESULTADO=%ERRORLEVEL%"
popd
if not "%RESULTADO%"=="0" pause
exit /b %RESULTADO%
