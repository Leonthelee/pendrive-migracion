$ErrorActionPreference='Stop'
while($true){
    Write-Host "`n==================================================================" -ForegroundColor Cyan
    Write-Host " DGA - SUITE MIGRACION WINDOWS 11 (UPDATE DIRECTO SIN BORRAR NADA)" -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "Equipo: $env:COMPUTERNAME | Trabajo local: $env:ProgramData\DGA\Migracion" -ForegroundColor Gray
    Write-Host "Nota  : Todas las opciones son independientes (ninguna bloquea otra)." -ForegroundColor DarkCyan
    Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host '  5) [PRINCIPAL] MIGRAR Windows 10 a Windows 11 (Solo Update SO / No borra nada)' -ForegroundColor Green
    Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host '  1) [Opcional] DIAGNOSTICO rapido del equipo (informativo)'
    Write-Host '  2) [Opcional] SIMULAR software DGA y comprobar rutas'
    Write-Host '  3) [Opcional] RESPALDAR carpetas seleccionadas a unidad externa'
    Write-Host '  4) [Opcional] ANALIZAR compatibilidad con Windows Setup (ScanOnly)'
    Write-Host '  6) [Opcional] VERIFICAR estado de Windows despues del reinicio'
    Write-Host '  7) [Opcional] SOFTWARE DGA: elegir paquetes para instalar'
    Write-Host '  0) Salir'
    Write-Host ""
    $op=Read-Host 'Opcion (5 = Migrar directo)'
    switch($op){
        '1' {& powershell.exe -NoProfile -File "$PSScriptRoot\09-migracion-segura.ps1" -Accion Diagnostico}
        '2' {& powershell.exe -NoProfile -File "$PSScriptRoot\07-software-dga.ps1" -Simular}
        '3' {& powershell.exe -NoProfile -File "$PSScriptRoot\04-premigracion.ps1"}
        '4' {& powershell.exe -NoProfile -File "$PSScriptRoot\09-migracion-segura.ps1" -Accion Compatibilidad}
        '5' {& powershell.exe -NoProfile -File "$PSScriptRoot\06-migracion-win11.ps1"}
        '6' {& powershell.exe -NoProfile -File "$PSScriptRoot\09-migracion-segura.ps1" -Accion Verificar}
        '7' {& powershell.exe -NoProfile -File "$PSScriptRoot\07-software-dga.ps1"}
        '0' {exit 0}
        default {Write-Host 'Opcion no valida' -ForegroundColor Yellow;continue}
    }
    Write-Host "Codigo de salida: $LASTEXITCODE" -ForegroundColor Gray
    Read-Host 'Presione Enter para volver al menu' | Out-Null
}

