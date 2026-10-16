[CmdletBinding()]
param(
    [string]$DestinoRespaldo,
    [string[]]$Origenes,
    [switch]$SoloChequeo,
    [string]$Raiz=(Join-Path $env:ProgramData 'DGA\Migracion')
)
. "$PSScriptRoot\migracion-core.ps1"
if($SoloChequeo){ & powershell.exe -NoProfile -File "$PSScriptRoot\09-migracion-segura.ps1" -Accion Diagnostico -Raiz $Raiz; exit $LASTEXITCODE }
try {
    if(-not(Test-Admin)){throw 'Ejecute como administrador para leer los perfiles que desea respaldar.'}
    Initialize-Run $Raiz
    $inv=Get-Inventory
    if(-not $Origenes){
        Write-Host 'Perfiles detectados (no seleccione el perfil completo mientras este en uso):' -ForegroundColor Cyan
        $inv.Perfiles | Format-Table LocalPath,Loaded
        Write-Host 'Indique carpetas reales: Documentos, Escritorio, proyectos y datos de aplicaciones necesarios.'
        Write-Host 'Separe rutas con punto y coma. Cierre las aplicaciones. No se siguen enlaces/junctions.'
        $Origenes=@((Read-Host 'Carpetas a respaldar').Split(';') | ForEach-Object {$_.Trim().Trim('"')} | Where-Object {$_})
    }
    if(-not $Origenes.Count){throw 'Debe seleccionar al menos una carpeta.'}
    $Origenes=@($Origenes | ForEach-Object {(Resolve-Path -LiteralPath $_).ProviderPath.TrimEnd('\')} | Select-Object -Unique)
    if (-not $DestinoRespaldo) { $DestinoRespaldo=Read-Host 'Carpeta de respaldo en OTRO disco fisico o recurso UNC externo (nunca este pendrive)' }
    Assert-ExternalBackupDestination $DestinoRespaldo
    $destBase=[IO.Path]::GetFullPath($DestinoRespaldo)
    Assert-BackupPaths $Origenes $destBase
    $local=([IO.Path]::GetPathRoot($destBase).TrimEnd('\') -ieq $env:SystemDrive)
    $runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $destination=Join-Path $destBase "$($inv.Equipo)\$runId"
    Write-Host "Destino: $destination" -ForegroundColor Cyan
    Write-Host ('Alcance: '+($Origenes -join '; '))
    if($local){Write-Host 'COPIA LOCAL en el disco del sistema. No protege ante averia del disco ni sustituye una imagen completa.' -ForegroundColor Yellow}
    if((Read-Host 'Escriba COPIAR para respaldar estas carpetas') -cne 'COPIAR'){throw 'Respaldo cancelado.'}
    $allFiles=New-Object System.Collections.Generic.List[object]
    $bytes=[long]0
    foreach($source in $Origenes){
        if(-not(Test-Path -LiteralPath $source -PathType Container)){throw "No es una carpeta: $source"}
        foreach($file in Get-RegularFiles $source){
            $bytes+=$file.Length
            $allFiles.Add([pscustomobject]@{Raiz=$source;Origen=$file.FullName;Bytes=$file.Length})
        }
    }
    if(-not $allFiles.Count){throw 'Los origenes no contienen archivos normales; revise enlaces y archivos de nube.'}
    $destRoot=[IO.Path]::GetPathRoot($destBase)
    if($destRoot -match '^[A-Za-z]:\\$'){
        $drive=New-Object IO.DriveInfo $destRoot
        $reserve=if($local){35GB}else{1GB}
        if($drive.AvailableFreeSpace -lt ($bytes+$reserve)){throw 'Espacio insuficiente para la copia y el margen requerido.'}
        if($drive.DriveFormat -eq 'FAT32' -and @($allFiles | Where-Object Bytes -ge 4GB).Count){throw 'FAT32 no permite uno de los archivos seleccionados (4 GB o mas).'}
    }
    New-Item -ItemType Directory -Path $destination | Out-Null
    $manifest=[ordered]@{Version=1;Equipo=$inv.Equipo;MachineGuid=$inv.MachineGuid;FechaUtc=[datetime]::UtcNow.ToString('o');Estado='EnCurso';CopiaLocal=$local;Origenes=$Origenes;Exclusiones='Reparse points (junctions/symlinks/nube). No es imagen del sistema.';Archivos=@()}
    $manifestPath=Join-Path $destination 'manifiesto.json'
    Write-JsonAtomic $manifestPath $manifest
    $entries=New-Object System.Collections.Generic.List[object]
    $index=0
    foreach($source in $Origenes){
        $index++
        $target=Join-Path $destination ('datos\{0:D3}' -f $index)
        # No /MIR, /PURGE or root copy. Every run has a new destination.
        & robocopy.exe $source $target /E /XJ /XA:L /R:1 /W:1 /COPY:DAT /DCOPY:DAT /NP /NFL /NDL "/LOG:$(Join-Path $destination "robocopy-$index.log")"
        $code=$LASTEXITCODE
        if($code -ge 8){throw "Robocopy fallo con codigo $code en $source. Consulte el log."}
        foreach($file in @($allFiles | Where-Object Raiz -eq $source)){
            $relative=$file.Origen.Substring($source.Length).TrimStart('\')
            $copy=Join-Path $target $relative
            $sourceHash=(Get-FileHash -LiteralPath $file.Origen -Algorithm SHA256).Hash
            if((Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash -ne $sourceHash){throw "Verificacion SHA256 fallo: $($file.Origen)"}
            $entries.Add([pscustomobject]@{Raiz=$source;Origen=$file.Origen;Destino=$copy;Bytes=$file.Bytes;SHA256=$sourceHash})
        }
    }
    $manifest.Archivos=$entries.ToArray()
    $manifest.Estado='Verificado'
    $manifest.FechaUtc=[datetime]::UtcNow.ToString('o')
    # Validate source list again to detect files created during copying.
    Test-BackupManifest ([pscustomobject]$manifest) $inv
    Write-JsonAtomic $manifestPath $manifest
    Write-JsonAtomic (Join-Path $Raiz 'estado\ultimo-respaldo.json') @{Manifiesto=$manifestPath;Equipo=$inv.Equipo;FechaUtc=$manifest.FechaUtc}
    Write-Host "COPIA VERIFICADA ($($entries.Count) archivos): $manifestPath" -ForegroundColor Green
    Write-Host 'Pruebe abrir documentos desde la copia antes de migrar.'
    exit 0
} catch {
    Write-Host "RESPALDO NO APROBADO: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
