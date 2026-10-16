@echo off
setlocal
cd /d "%~dp0"
echo ==================================================================
echo  DGA - Empaquetador Seguro a Pendrive USB (NTFS / exFAT)
echo ==================================================================
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -File "%~dp0scripts\11-Empaquetar-Pendrive.ps1" -VerificarHashesDestino
set "EXITCODE=%ERRORLEVEL%"
echo.
pause
exit /b %EXITCODE%
