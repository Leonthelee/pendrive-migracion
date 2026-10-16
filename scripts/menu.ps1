$ErrorActionPreference='Stop'
while($true){
    Write-Host "`n=== DGA - MIGRACION v4 / PILOTO ===" -ForegroundColor Cyan
    Write-Host "Equipo: $env:COMPUTERNAME | Trabajo local: $env:ProgramData\DGA\Migracion"
    Write-Host '1) DIAGNOSTICO del equipo (primera prueba, no instala)'
    Write-Host '2) SIMULAR software y comprobar rutas (no instala)'
    Write-Host '3) RESPALDAR carpetas seleccionadas (opcional)'
    Write-Host '4) ANALIZAR compatibilidad con Windows Setup (no migra)'
    Write-Host '5) MIGRAR Windows 10 a Windows 11'
    Write-Host '6) VERIFICAR Windows despues del reinicio'
    Write-Host '7) SOFTWARE: elegir paquetes para instalar'
    Write-Host '0) Salir'
    $op=Read-Host 'Opcion'
    switch($op){
        '1' {& powershell.exe -NoProfile -File "$PSScriptRoot\09-migracion-segura.ps1" -Accion Diagnostico}
        '2' {& powershell.exe -NoProfile -File "$PSScriptRoot\07-software-dga.ps1" -Simular}
        '3' {& powershell.exe -NoProfile -File "$PSScriptRoot\04-premigracion.ps1"}
        '4' {& powershell.exe -NoProfile -File "$PSScriptRoot\09-migracion-segura.ps1" -Accion Compatibilidad}
        '5' {& powershell.exe -NoProfile -File "$PSScriptRoot\09-migracion-segura.ps1" -Accion Migrar}
        '6' {& powershell.exe -NoProfile -File "$PSScriptRoot\09-migracion-segura.ps1" -Accion Verificar}
        '7' {& powershell.exe -NoProfile -File "$PSScriptRoot\07-software-dga.ps1"}
        '0' {exit 0}
        default {Write-Host 'Opcion no valida';continue}
    }
    Write-Host "Codigo de salida: $LASTEXITCODE"
    Read-Host 'Enter para volver al menu' | Out-Null
}
