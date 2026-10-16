#requires -Version 5.1
# Prueba el adaptador REAL en procesos aislados con modulos Windows sustituidos.
# No requiere administrador. Conserva los fixtures bajo TEMP para inspeccion.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $env:TEMP ('DGA-Pruebas-'+[guid]::NewGuid().ToString('N'))
$priorRoot=$env:DGA_TEST_ROOT; $priorCase=$env:DGA_TEST_CASE
try {
    New-Item -ItemType Directory -Path "$fixture\scripts","$fixture\estado","$fixture\inventario","$fixture\reportes" | Out-Null
    $env:DGA_TEST_ROOT=$fixture; $env:DGA_TEST_CASE='Migrar'
    Copy-Item -LiteralPath "$root\scripts\09-migracion-segura.ps1" -Destination "$fixture\scripts\09-migracion-segura.ps1"
    @'
$ErrorActionPreference='Stop'
function Test-Admin { $true }
function Initialize-Run($Root) { foreach($f in 'estado','inventario','reportes','scripts'){New-Item -ItemType Directory -Path (Join-Path $Root $f) -Force | Out-Null} }
function Write-JsonAtomic($Path,$Value) { $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8 }
function Get-DgaInventory {
    $apps=@([pscustomobject]@{DisplayName='Aplicacion Piloto'})
    if($env:DGA_TEST_CASE -eq 'AppPerdida'){$apps=@()}
    [pscustomobject]@{Equipo='PILOTO';MachineGuid='ID-PILOTO';Build=$(if($env:DGA_TEST_CASE -eq 'Migrar'){19045}else{26300});Edicion='Professional';Idioma='es-MX';Aplicaciones=$apps;Perfiles=@([pscustomobject]@{SID='S-TEST'})}
}
function Test-BackupManifest($Manifest,$Inventory) {
    Add-Content -LiteralPath (Join-Path $env:DGA_TEST_ROOT 'backup-count.txt') -Value 'validado'
    if($env:DGA_TEST_CASE -eq 'RespaldoInvalido'){throw 'Respaldo no autorizado'}
}
function Get-BitLockerVolume {
    if($env:DGA_TEST_CASE -eq 'CifradoDesconocido'){throw 'No consultable'}
    [pscustomobject]@{MountPoint=$env:SystemDrive;VolumeStatus=$(if($env:DGA_TEST_CASE -eq 'CifradoPerdido'){'FullyDecrypted'}else{'FullyEncrypted'});ProtectionStatus=$(if($env:DGA_TEST_CASE -eq 'CifradoPerdido'){'Off'}else{'On'});LockStatus='Unlocked'}
}
'@ | Set-Content "$fixture\scripts\migracion-core.ps1" -Encoding UTF8
    @'
function Invoke-MigrationWorkflow {
    param($Mode,$Root,[scriptblock]$BeforeInstall)
    if($Mode -ne 'Migracion'){return}
    $media=[pscustomobject]@{ImageVersion='10.0.26300.1';Edition='Professional';Language='es-MX'}
    $report=[pscustomobject]@{Directory=(Join-Path $env:DGA_TEST_ROOT 'reportes')}
    $fresh=[pscustomobject]@{Volumes=@([pscustomobject]@{MountPoint=$env:SystemDrive;Protection='On'})}
    & $BeforeInstall $media $report $fresh
    Set-Content -LiteralPath (Join-Path $env:DGA_TEST_ROOT 'setup-simulado.txt') -Value 'SIMULADO, NO SE EJECUTO SETUP'
}
Export-ModuleMember -Function Invoke-MigrationWorkflow
'@ | Set-Content "$fixture\scripts\Migrador.psm1" -Encoding UTF8
    '{}' | Set-Content "$fixture\respaldo.json"
    & powershell.exe -NoProfile -File "$fixture\scripts\09-migracion-segura.ps1" -Accion Migrar -Raiz $fixture -ManifiestoRespaldo "$fixture\respaldo.json"
    if($LASTEXITCODE -ne 0){throw 'Adaptador no completa flujo simulado'}
    $state=Get-Content "$fixture\estado\migracion.json" -Raw | ConvertFrom-Json
    if($state.Estado -ne 'PendienteReinicio' -or -not(Test-Path -LiteralPath $state.Verificador)){throw 'Estado/verificador no creados'}
    if(@(Get-Content "$fixture\backup-count.txt").Count -ne 2){throw 'No revalida manifiesto al final'}
    Write-Output 'OK adaptador: doble validacion de respaldo, estado persistente y verificador local'
    # El estado pendiente debe impedir repetir la migracion.
    & powershell.exe -NoProfile -File "$fixture\scripts\09-migracion-segura.ps1" -Accion Migrar -Raiz $fixture -ManifiestoRespaldo "$fixture\respaldo.json"
    if($LASTEXITCODE -eq 0){throw 'Permite repetir migracion pendiente'}
    Write-Output 'OK adaptador: instalacion pendiente bloquea reejecucion'
    foreach($case in @('Normal','AppPerdida','CifradoDesconocido','CifradoPerdido')) {
        $env:DGA_TEST_CASE=$case
        & powershell.exe -NoProfile -File "$fixture\scripts\09-migracion-segura.ps1" -Accion Verificar -Raiz $fixture
        $code=$LASTEXITCODE
        if(($case -eq 'Normal' -and $code -ne 0) -or ($case -ne 'Normal' -and $code -eq 0)){throw "Resultado incorrecto: $case"}
        Write-Output "OK adaptador: postverificacion $case"
    }
    Write-Output 'TOTAL ADAPTADOR: 6 escenarios correctos. Hardware, respaldo y motor Setup simulados.'
    Write-Output "Fixtures conservados: $fixture"
} finally {
    $env:DGA_TEST_ROOT=$priorRoot; $env:DGA_TEST_CASE=$priorCase
}
