#requires -Version 5.1
[CmdletBinding()]
param([switch]$Aprobar)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent
$mapPath=Join-Path $root 'config\medios.json'
$module=Import-Module (Join-Path $PSScriptRoot 'Migrador.psm1') -Force -PassThru
try {
    & $module { Assert-Host }
    $beforeHash=(Get-FileHash -LiteralPath $mapPath -Algorithm SHA256).Hash
    $map=Get-Content -LiteralPath $mapPath -Raw | ConvertFrom-Json
    if($map.SchemaVersion -ne 1 -or @($map.Media).Count -eq 0){throw 'Mapa vacio o esquema no admitido.'}
    $today=(Get-Date).ToString('yyyy-MM-dd')
    $operator=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    # Validacion estructural con copia en memoria: no habilita el mapa en disco.
    $candidate=$map | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    foreach($row in $candidate.Media){$row.Approved=$true;$row.ApprovedOn=$today;$row.ApprovedBy=$operator}
    foreach($row in $candidate.Media){
        $identity=[pscustomobject]@{SystemLanguage=$row.Language;Edition=$row.Edition;Architecture=$row.Architecture}
        $selected=Select-Media $identity $candidate
        if($selected.ImageIndex -ne $row.ImageIndex){throw 'Mapeo ambiguo.'}
    }
    foreach($group in @($candidate.Media | Group-Object File)){
        $rows=@($group.Group);$handle=$null
        try {
            if(@($rows.Sha256 | Select-Object -Unique).Count -ne 1){throw 'Hashes divergentes para un mismo archivo.'}
            Write-Host "Validando SHA256, firma e imagen: $($group.Name)"
            $handle=& $module {param($r,$m) Open-Media $r $m} $root $rows[0]
            $images=@(@('sources\install.wim','sources\install.esd') | ForEach-Object {Join-Path $handle.Drive $_} | Where-Object {Test-Path -LiteralPath $_})
            if($images.Count -ne 1){throw 'Imagen ambigua.'}
            foreach($row in $rows){
                $image=Get-WindowsImage -ImagePath $images[0] -Index $row.ImageIndex
                Assert-Image $image $row
                Write-Host "OK $($row.Language) / $($row.Edition) / indice $($row.ImageIndex)"
            }
        } finally {
            if($null -ne $handle){
                try {Dismount-DiskImage -ImagePath $handle.Path -ErrorAction Stop | Out-Null}
                finally {$handle.Stream.Dispose()}
            }
        }
    }
    if(-not $Aprobar){Write-Host 'Validacion tecnica completa. Mapa sin cambios. Use -Aprobar para registrar aprobacion explicita.';exit 0}
    Write-Host 'Confirme origen oficial de los hashes, licencia, soporte de la version y problemas conocidos revisados. Esta aprobacion no sustituye el piloto.'
    if((Read-Host 'Escriba APROBAR MEDIOS para habilitar este mapa') -cne 'APROBAR MEDIOS'){throw 'Aprobacion cancelada; mapa sin cambios.'}
    if((Get-FileHash -LiteralPath $mapPath -Algorithm SHA256).Hash -ne $beforeHash){throw 'Mapa modificado durante la revision; repetir.'}
    $backup=$mapPath+'.antes-aprobacion-'+[guid]::NewGuid().ToString('N')+'.json'
    Copy-Item -LiteralPath $mapPath -Destination $backup
    $temp=$mapPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    $candidate | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temp -Encoding UTF8
    [IO.File]::Replace($temp,$mapPath,$null)
    Write-Host 'Medios aprobados. No se ejecuto Setup ni se instalo Windows.'
} catch {Write-Error $_;exit 1}
