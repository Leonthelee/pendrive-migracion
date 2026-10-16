# Entrada unica al motor v4. El antiguo orquestador ya no se invoca desde el menu.
[CmdletBinding()]
param()
Write-Host 'MIGRACION WINDOWS 10 -> 11 / KIT DGA v4' -ForegroundColor Cyan
Write-Host '1) Diagnostico sin instalacion'
Write-Host '2) Analizar compatibilidad con Windows Setup (sin migrar)'
Write-Host '3) Migrar (respaldo verificado + ScanOnly obligatorio)'
Write-Host '4) Verificar despues del reinicio'
Write-Host '0) Volver'
$op=Read-Host 'Opcion'
$action=switch($op){'1'{'Diagnostico'}'2'{'Compatibilidad'}'3'{'Migrar'}'4'{'Verificar'}default{''}}
if($action){& powershell.exe -NoProfile -File "$PSScriptRoot\09-migracion-segura.ps1" -Accion $action;exit $LASTEXITCODE}
