#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$UnidadDestino,
    [switch]$SoloCalcular,
    [switch]$VerificarHashesDestino
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$raizKit = Split-Path -Parent $PSScriptRoot
$mapaMediosPath = Join-Path $raizKit 'config\medios.json'

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " DGA - Empaquetado y Copia Segura a Pendrive Fisico (NTFS / exFAT)" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Calculo de peso real materializado (incluyendo HardLinks de ISO)
$archivosKit = Get-ChildItem -LiteralPath $raizKit -Recurse -File -Force | Where-Object {
    $_.FullName -notmatch '\\\.git(\\|$)' -and
    $_.FullName -notmatch '\\_backup'
}

$bytesIso = ($archivosKit | Where-Object { $_.Extension -ieq '.iso' } | Measure-Object -Property Length -Sum).Sum
if (-not $bytesIso) { $bytesIso = 0 }

$bytesTools = ($archivosKit | Where-Object { $_.FullName -match '\\tools\\' } | Measure-Object -Property Length -Sum).Sum
if (-not $bytesTools) { $bytesTools = 0 }

$bytesTotal = ($archivosKit | Measure-Object -Property Length -Sum).Sum
if (-not $bytesTotal) { $bytesTotal = 0 }

$margenBytes = 1GB
$requeridoBytes = $bytesTotal + $margenBytes

Write-Host ""
Write-Host "[*] Desglose de peso real al materializar en USB:" -ForegroundColor Yellow
Write-Host ("  -> Imagenes ISO (es-ES + es-MX) : {0:N2} GiB ({1:N2} GB)" -f ($bytesIso / 1GB), ($bytesIso / 1e9))
Write-Host ("  -> Herramientas (tools/software): {0:N2} MiB ({1:N2} MB)" -f ($bytesTools / 1MB), ($bytesTools / 1e6))
Write-Host ("  -> Total Kit Materializado      : {0:N2} GiB ({1:N2} GB)" -f ($bytesTotal / 1GB), ($bytesTotal / 1e9))
Write-Host ("  -> Minimo recomendado en USB    : {0:N2} GiB (incluye 1 GiB de margen)" -f ($requeridoBytes / 1GB))
Write-Host ""

if ($SoloCalcular) {
    exit 0
}

# 2. Seleccion y validacion de unidad destino
if ([string]::IsNullOrWhiteSpace($UnidadDestino)) {
    Write-Host "[*] Volumenes detectados en el equipo:" -ForegroundColor Cyan
    Get-Volume | Where-Object { $_.DriveLetter } | Select-Object DriveLetter, FileSystemLabel, FileSystem, DriveType,
        @{N='TamanoGiB';E={[math]::Round($_.Size/1GB, 2)}},
        @{N='LibreGiB';E={[math]::Round($_.SizeRemaining/1GB, 2)}} | Format-Table -AutoSize

    $UnidadDestino = Read-Host "Ingrese la letra de la unidad USB destino (ej. E o E:)"
}

$letra = ($UnidadDestino -replace '[^a-zA-Z]', '').ToUpperInvariant()
if ($letra.Length -ne 1) {
    throw "Letra de unidad invalida: '$UnidadDestino'."
}

$unidadSistema = ($env:SystemDrive -replace '[^a-zA-Z]', '').ToUpperInvariant()
$unidadOrigen = ((Split-Path -Qualifier $raizKit) -replace '[^a-zA-Z]', '').ToUpperInvariant()

if ($letra -eq $unidadSistema) {
    throw "BLOQUEADO: No se permite empaquetar sobre la unidad del sistema ($unidadSistema`:)."
}
if ($letra -eq $unidadOrigen) {
    throw "BLOQUEADO: La unidad destino ($letra`:) es el mismo volumen donde reside el kit origen."
}

$vol = Get-Volume -DriveLetter $letra -ErrorAction Stop
if ($vol.FileSystem -notin @('NTFS', 'exFAT')) {
    throw "BLOQUEADO: El volumen $letra`: tiene formato '$($vol.FileSystem)'. Las ISO de ~9 GB superan el limite de 4 GB de FAT32. Formatee el pendrive en NTFS o exFAT."
}

if ($vol.SizeRemaining -lt $requeridoBytes) {
    $libreGiB = [math]::Round($vol.SizeRemaining / 1GB, 2)
    $reqGiB = [math]::Round($requeridoBytes / 1GB, 2)
    throw "BLOQUEADO: Espacio insuficiente en $letra`: ($libreGiB GiB libres; se requieren al menos $reqGiB GiB)."
}

$destinoRoot = "$letra`:\PENDRIVE_MIGRACION_DGA"
Write-Host "[OK] Unidad $letra`: validada ($($vol.FileSystem), $([math]::Round($vol.SizeRemaining/1GB, 2)) GiB libres)." -ForegroundColor Green
Write-Host "[*] Copiando kit completo y materializando ISOs hacia: $destinoRoot ..." -ForegroundColor Yellow

if (-not (Test-Path -LiteralPath $destinoRoot)) {
    New-Item -ItemType Directory -Path $destinoRoot -Force | Out-Null
}

# 3. Copia estructurada con Robocopy (excluyendo .git y _backup*)
$argumentosRobocopy = @(
    $raizKit,
    $destinoRoot,
    '/E',
    '/COPY:DAT',
    '/DCOPY:T',
    '/R:2',
    '/W:2',
    '/XD', '.git', '_backup*',
    '/NP'
)

& robocopy @argumentosRobocopy
$rc = $LASTEXITCODE
if ($rc -ge 8) {
    throw "Error durante la copia con robocopy (ExitCode: $rc)."
}

Write-Host "[OK] Copia completada correctamente en $destinoRoot (Robocopy ExitCode: $rc)." -ForegroundColor Green

# 4. Verificacion de hashes SHA256 en el destino si se solicita o para ISOs del mapa
if ($VerificarHashesDestino -and (Test-Path -LiteralPath $mapaMediosPath)) {
    Write-Host "[*] Verificando integridad SHA256 de las ISOs copiadas en el pendrive..." -ForegroundColor Yellow
    $mapa = Get-Content -LiteralPath $mapaMediosPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $isosUnicas = $mapa.Media | Select-Object -Property File, Sha256 -Unique
    foreach ($iso in $isosUnicas) {
        $rutaIsoUsb = Join-Path $destinoRoot ("ISO\" + $iso.File)
        if (-not (Test-Path -LiteralPath $rutaIsoUsb)) {
            throw "Falta la ISO esperada en el pendrive: $rutaIsoUsb"
        }
        $hashReal = (Get-FileHash -LiteralPath $rutaIsoUsb -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($hashReal -ne $iso.Sha256.ToUpperInvariant()) {
            throw "Hash SHA256 incorrecto en USB para $($iso.File). Esperado: $($iso.Sha256) | Actual: $hashReal"
        }
        Write-Host "  -> [OK] $($iso.File) : SHA256 verificado ($hashReal)" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "[LISTO] Kit listo para terreno en: $destinoRoot" -ForegroundColor Green
exit 0
