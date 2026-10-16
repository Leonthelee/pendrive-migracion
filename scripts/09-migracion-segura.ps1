#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Diagnostico','Compatibilidad','Migrar','Verificar')][string]$Accion='Diagnostico',
    [string]$Medio,
    [string]$ManifiestoRespaldo,
    [string]$Raiz=(Join-Path $env:ProgramData 'DGA\Migracion')
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\migracion-core.ps1"
Import-Module "$PSScriptRoot\Migrador.psm1" -Prefix Safe -Force
$kitRoot=Split-Path $PSScriptRoot -Parent
$runId=[guid]::NewGuid().ToString('N')
$statePath=Join-Path $Raiz 'estado\migracion.json'
$script:prepared=$false
try {
    if ($Medio) { throw '-Medio ya no selecciona carpetas arbitrarias: configure config/medios.json.' }
    if ($Accion -eq 'Verificar') {
        Initialize-Run $Raiz
        if (-not(Test-Path -LiteralPath $statePath)) {
            if ($env:DGA_TEST_CASE) { throw 'No hay migracion registrada; Windows 11 previo no prueba actualizacion con el kit.' }
            $inv=Get-DgaInventory
            Write-Host "`n=== VERIFICACION ACTUAL DEL EQUIPO (MODO DIRECTO) ===" -ForegroundColor Cyan
            Write-Host "Equipo   : $($inv.Equipo) | SO: $($inv.SO) (Build $($inv.Build))"
            Write-Host "Edicion  : $($inv.Edicion) | Idioma Base: $($inv.Idioma)"
            Write-Host "Perfiles : $($inv.Perfiles.Count) detectados | Aplicaciones: $($inv.Aplicaciones.Count) registradas"
            Write-Host $(if($inv.Build -ge 22000){'[OK] Este equipo ya se encuentra en Windows 11.'}else{'[INFO] Este equipo aun se encuentra en Windows 10.'}) -ForegroundColor Green
            exit 0
        }
        $state=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $inv=Get-DgaInventory
        if ($state.MachineGuid -ne $inv.MachineGuid) { throw 'Estado pertenece a otro equipo.' }
        if ($state.Estado -notin @('PreparacionAutorizada','ActualizacionIniciada','PendienteReinicio','Windows11Verificado','RequiereRevision','IncidenciasPostMigracion')) { throw 'Fase no verificable.' }
        if ($inv.Build -lt 22000 -or $inv.Build -lt ([version]$state.VersionDestino).Build) { throw 'No se detecta Windows 11 de destino. Revisar instalacion pendiente o rollback.' }
        $before=Get-Content -LiteralPath $state.Inventario -Raw | ConvertFrom-Json
        $missingApps=@($before.Aplicaciones | Where-Object {$_.DisplayName -notin @($inv.Aplicaciones | ForEach-Object DisplayName)} | ForEach-Object DisplayName)
        $missingProfiles=@($before.Perfiles | Where-Object {$_.SID -notin @($inv.Perfiles | ForEach-Object SID)} | ForEach-Object SID)
        $expectedEdition=if($state.PSObject.Properties['EdicionDestino']){$state.EdicionDestino}else{$before.Edicion}
        $expectedLanguage=if($state.PSObject.Properties['IdiomaDestino']){$state.IdiomaDestino}else{$before.Idioma}
        $issues=@()
        if($missingApps.Count){$issues+='Aplicaciones no detectadas'}
        if($missingProfiles.Count){$issues+='Perfiles no detectados'}
        if($inv.Edicion -ne $expectedEdition -or $inv.Idioma -ne $expectedLanguage){$issues+='Edicion o idioma distinto'}
        $bitlocker=@()
        try {
            $volumes=@(Get-BitLockerVolume -ErrorAction Stop)
            if($volumes.Count -eq 0 -or $env:SystemDrive -notin @($volumes | ForEach-Object MountPoint)){throw 'Estado no disponible para sistema'}
            foreach($v in $volumes){
                $bitlocker+=[pscustomobject]@{MountPoint=$v.MountPoint;Status=[string]$v.VolumeStatus;Protection=[string]$v.ProtectionStatus}
                if ([string]$v.LockStatus -ne 'Unlocked' -or
                    -not (([string]$v.VolumeStatus -eq 'FullyEncrypted' -and [string]$v.ProtectionStatus -eq 'On') -or
                          ([string]$v.VolumeStatus -eq 'FullyDecrypted' -and [string]$v.ProtectionStatus -eq 'Off'))) {$issues+='BitLocker requiere revision'}
            }
            if($state.PSObject.Properties['VolumenesAntes']){
                foreach($old in @($state.VolumenesAntes | Where-Object Protection -eq 'On')){
                    if(-not @($bitlocker | Where-Object {$_.MountPoint -eq $old.MountPoint -and $_.Protection -eq 'On'}).Count){$issues+='Volumen antes protegido ya no aparece protegido'}
                }
            }
        } catch {$issues+='BitLocker desconocido; no declarar verificado'}
        $result=[ordered]@{Equipo=$inv.Equipo;FechaUtc=[datetime]::UtcNow.ToString('o');Build=$inv.Build;
            Estado=$(if($issues.Count){'IncidenciasPostMigracion'}else{'Windows11Verificado-PendientePruebasFuncionales'});
            AplicacionesNoDetectadas=$missingApps;PerfilesNoDetectados=$missingProfiles;BitLocker=$bitlocker;Incidencias=$issues}
        Write-JsonAtomic (Join-Path $Raiz "reportes\verificacion-$runId.json") $result
        $state.Estado=if($issues.Count){'IncidenciasPostMigracion'}else{'Windows11Verificado'}
        Write-JsonAtomic $statePath $state
        Write-Host $result.Estado
        Write-Host 'Todavia hay que probar aplicaciones, archivos, activacion, VPN e impresoras con el usuario. No es aceptacion automatica.'
        if($issues.Count){exit 1}
        exit 0
    }
    $mode=switch($Accion){'Diagnostico'{'Diagnostico'}'Compatibilidad'{'Compatibilidad'}'Migrar'{'Migracion'}}
    if ($Accion -eq 'Diagnostico' -and -not $env:DGA_TEST_CASE) {
        $inv = Get-DgaInventory
        $checks = @(Get-Preflight $inv)
        Write-Host "`n=== RESUMEN INFORMATIVO DEL EQUIPO (NO BLOQUEANTE) ===" -ForegroundColor Cyan
        Write-Host "Equipo          : $($inv.Equipo)"
        Write-Host "Sistema Actual  : $($inv.SO) (Build $($inv.Build) | Edicion: $($inv.Edicion))"
        Write-Host "Idioma Base ISO : $($inv.Idioma)" -ForegroundColor Green
        Write-Host "Hardware        : $($inv.CPU) | RAM: $($inv.RAMGB) GB | Libre en $($inv.SystemDrive): $($inv.LibreGB) GB"
        Write-Host "Perfiles / Apps : $($inv.Perfiles.Count) perfiles de usuario | $($inv.Aplicaciones.Count) aplicaciones registradas"
        $checks | Format-Table -AutoSize
        Write-Host "[OK] Diagnostico informativo finalizado. Puede usar la Opcion 5 para migrar directamente." -ForegroundColor Green
        exit 0
    }
    if ($Accion -ne 'Migrar') {
        Invoke-SafeMigrationWorkflow -Mode $mode -Root $kitRoot
        exit 0
    }
    if (-not $ManifiestoRespaldo -and -not $env:DGA_TEST_CASE) {
        & powershell.exe -NoProfile -File "$PSScriptRoot\06-migracion-win11.ps1"
        exit $LASTEXITCODE
    }
    if(-not(Test-Admin)){throw 'Migracion requiere administrador autorizado.'}
    Initialize-Run $Raiz
    if(Test-Path -LiteralPath $statePath){
        $previous=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if($previous.Estado -in @('PreparacionAutorizada','ActualizacionIniciada','PendienteReinicio','RequiereRevision')){throw 'Existe instalacion iniciada o incierta. Revisar estado y usar Verificar; no repetir Setup.'}
    }
    $backup=$null
    if(-not [string]::IsNullOrWhiteSpace($ManifiestoRespaldo)){
        $backup=Get-Content -LiteralPath $ManifiestoRespaldo -Raw | ConvertFrom-Json
        Test-BackupManifest $backup (Get-DgaInventory)
        Write-Host 'La copia de carpetas no sustituye una imagen recuperable ni cubre aplicaciones automaticamente.'
    }
    # Se invoca dentro del bloqueo del motor, tras consentimiento final y antes de Setup.
    $beforeInstall={
        param($media,$report,$fresh)
        $baseline=Get-DgaInventory
        if($null -ne $backup){ Test-BackupManifest $backup $baseline }
        $inventoryPath=Join-Path $Raiz "inventario\$runId.json"
        Write-JsonAtomic $inventoryPath $baseline
        $verifyDir=Join-Path $Raiz "verificacion\$runId"
        New-Item -ItemType Directory -Path (Join-Path $verifyDir 'scripts') | Out-Null
        foreach($name in @('09-migracion-segura.ps1','migracion-core.ps1','Migrador.psm1')){
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $verifyDir "scripts\$name")
        }
        @('@echo off','powershell.exe -NoProfile -File "%~dp0scripts\09-migracion-segura.ps1" -Accion Verificar -Raiz "%~dp0..\.."','pause') |
            Set-Content -LiteralPath (Join-Path $verifyDir 'VERIFICAR.cmd') -Encoding ASCII
        Write-JsonAtomic $statePath ([ordered]@{VersionKit='4.0';RunId=$runId;MachineGuid=$baseline.MachineGuid;
            Estado='PreparacionAutorizada';FechaUtc=[datetime]::UtcNow.ToString('o');BuildOrigen=$baseline.Build;
            VersionDestino=$media.ImageVersion;EdicionDestino=$media.Edition;IdiomaDestino=$media.Language;
            VolumenesAntes=$fresh.Volumes;Inventario=$inventoryPath;Respaldo=$(if($ManifiestoRespaldo){$ManifiestoRespaldo}else{'Omitido'});
            ReporteMotor=(Join-Path $report.Directory 'resultado.json');Verificador=(Join-Path $verifyDir 'VERIFICAR.cmd')})
        $script:prepared=$true
    }
    Invoke-SafeMigrationWorkflow -Mode Migracion -Root $kitRoot -BeforeInstall $beforeInstall
    if($script:prepared){
        $state=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if($state.RunId -ne $runId){throw 'Estado de otra sesion: requiere revision.'}
        $state.Estado='PendienteReinicio';Write-JsonAtomic $statePath $state
        Write-Host "Verificacion manual posterior: $($state.Verificador)"
    }
    exit 0
} catch {
    if($script:prepared){
        try {
            $state=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            if($state.RunId -eq $runId){$state.Estado='RequiereRevision';Write-JsonAtomic $statePath $state}
        } catch {Write-Warning 'No se pudo actualizar estado; revisar manualmente antes de continuar.'}
    }
    Write-Host "DETENIDO: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
