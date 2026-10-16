param([switch]$Reiniciar)
if ($Reiniciar) { Write-Error 'Reinicio automatico deshabilitado.'; exit 1 }
& powershell.exe -NoProfile -File "$PSScriptRoot\09-migracion-segura.ps1" -Accion Verificar
exit $LASTEXITCODE
