#Requires -Version 5.1
<#
============================================================================
MINISTERIO DE OBRAS PUBLICAS - DIRECCION GENERAL DE AGUAS (DGA)
DGA Core Tools -- by Daniel Diaz L. & AI Engine Antigravity
Herramienta : 06 - Migracion Directa In-Place Windows 10 -> Windows 11
Cometido    : Actualizar SOLO el Sistema Operativo SIN BORRAR NADA
              (Conserva 100% de archivos, perfiles, configuraciones y apps).
              No depende de ninguna accion previa del menu.
============================================================================
#>
[CmdletBinding()]
param(
    [ValidateSet('Auto','ES','MX')][string]$ForzarIdioma = 'Auto',
    [switch]$SinConfirmacion
)

$ErrorActionPreference = 'Stop'

# 1. Auto-elevacion a Administrador si no se inicio como Admin
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $esAdmin) {
    Write-Host "[*] Solicitando permisos de Administrador para iniciar la actualizacion de Windows..." -ForegroundColor Yellow
    $argList = @('-NoProfile', '-File', "`"$PSCommandPath`"")
    if ($ForzarIdioma -ne 'Auto') { $argList += @('-ForzarIdioma', $ForzarIdioma) }
    if ($SinConfirmacion) { $argList += '-SinConfirmacion' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -Wait
    exit $LASTEXITCODE
}

$KitRoot = Split-Path -Parent $PSScriptRoot
$UsbDrive = (Split-Path -Qualifier $PSScriptRoot) + '\'

# 2. Deteccion exacta del Idioma Base de Instalacion del SO (requerido por setup.exe para NO borrar apps)
$installLcid = try { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language').InstallLanguage } catch { '040A' }
$installLang = try { [Globalization.CultureInfo]::GetCultureInfo([Convert]::ToInt32($installLcid, 16)).Name } catch { 'es-ES' }
$sysLocale   = try { (Get-WinSystemLocale).Name } catch { $installLang }
$uiCulture   = [System.Globalization.CultureInfo]::CurrentUICulture.Name
$osCaption   = try { (Get-CimInstance Win32_OperatingSystem).Caption } catch { 'Windows' }
$osBuild     = try { (Get-CimInstance Win32_OperatingSystem).BuildNumber } catch { '0' }

# En Windows, 080A = es-MX; 040A / 0C0A = es-ES (Espanol Internacional)
$esBaseMexico = ($installLang -ieq 'es-MX')

# 3. Busqueda automatica de ISOs en el Kit (carpeta ISO\), raiz del USB y Descargas
$IsoES_Candidatos = @(
    (Join-Path $KitRoot 'ISO\Windows11_Client_x64_es-es_26300_9457.iso'),
    (Join-Path $UsbDrive 'ISO\Windows11_Client_x64_es-es_26300_9457.iso'),
    (Join-Path $UsbDrive 'Win11_25H2_Spanish_x64_v2.iso'),
    "C:\Users\$env:USERNAME\Downloads\pendrive-migracion\ISO\Windows11_Client_x64_es-es_26300_9457.iso",
    "C:\Users\$env:USERNAME\Downloads\Windows11_Client_x64_es-es_26300_9457.iso",
    "C:\Users\$env:USERNAME\Downloads\Nueva carpeta\Windows11_Client_x64_es-es_26300_9457.iso"
)
# Ademas cualquier ISO es-es en la carpeta ISO\
if (Test-Path -LiteralPath (Join-Path $KitRoot 'ISO')) {
    $IsoES_Candidatos += @(Get-ChildItem -LiteralPath (Join-Path $KitRoot 'ISO') -Filter '*es-es*.iso' -File | Select-Object -ExpandProperty FullName)
}

$IsoMX_Candidatos = @(
    (Join-Path $KitRoot 'ISO\Windows11_Client_x64_es-mx_26300_9457.iso'),
    (Join-Path $UsbDrive 'ISO\Windows11_Client_x64_es-mx_26300_9457.iso'),
    (Join-Path $UsbDrive 'Win11_25H2_Spanish_Mexico_x64_v2.iso'),
    "C:\Users\$env:USERNAME\Downloads\pendrive-migracion\ISO\Windows11_Client_x64_es-mx_26300_9457.iso",
    "C:\Users\$env:USERNAME\Downloads\Windows11_Client_x64_es-mx_26300_9457.iso",
    "C:\Users\$env:USERNAME\Downloads\Nueva carpeta\Windows11_Client_x64_es-mx_26300_9457.iso"
)
if (Test-Path -LiteralPath (Join-Path $KitRoot 'ISO')) {
    $IsoMX_Candidatos += @(Get-ChildItem -LiteralPath (Join-Path $KitRoot 'ISO') -Filter '*es-mx*.iso' -File | Select-Object -ExpandProperty FullName)
}

$IsoES_Path = $IsoES_Candidatos | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$IsoMX_Path = $IsoMX_Candidatos | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$SetupRoot  = Join-Path $UsbDrive 'setup.exe'

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " DGA - MIGRACION DIRECTA WINDOWS 11 (SOLO UPDATE / NO BORRA NADA) " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " Equipo Actual           : $env:COMPUTERNAME ($osCaption - Build $osBuild)" -ForegroundColor White
Write-Host " Idioma Base Instalacion : $installLang (LCID: $installLcid | UI: $uiCulture | Region: $sysLocale)" -ForegroundColor Green
Write-Host " ISO Espanol (es-ES)     : $(if ($IsoES_Path) { $IsoES_Path } else { 'No detectada' })" -ForegroundColor Gray
Write-Host " ISO Mexico  (es-MX)     : $(if ($IsoMX_Path) { $IsoMX_Path } else { 'No detectada' })" -ForegroundColor Gray
Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host " MODO IN-PLACE UPGRADE: Conserva 100% de archivos, perfiles y programas." -ForegroundColor Yellow
Write-Host " Ningun paso previo del menu (respaldo/diagnostico) es obligatorio." -ForegroundColor Yellow
Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

$idiomaRecomendado = if ($esBaseMexico) { 'MX' } else { 'ES' }

if ($ForzarIdioma -ne 'Auto') {
    $targetLanguage = $ForzarIdioma
} elseif ($SinConfirmacion) {
    $targetLanguage = $idiomaRecomendado
} else {
    Write-Host ""
    Write-Host "Seleccione el medio de actualizacion (Enter = Opcion 1 automatica):" -ForegroundColor Cyan
    if ($esBaseMexico) {
        Write-Host "  1) [RECOMENDADO - Enter] Español Mexico (es-MX) -> Coincide con idioma base del PC" -ForegroundColor Green
    } else {
        Write-Host "  1) [RECOMENDADO - Enter] Español Internacional (es-ES) -> Coincide con idioma base del PC" -ForegroundColor Green
    }
    Write-Host "  2) Forzar ISO Español Internacional (es-ES)"
    Write-Host "  3) Forzar ISO Español Mexico (es-MX)"
    Write-Host "  0) Cancelar y volver al menu"
    Write-Host ""
    $op = Read-Host "Opcion [Enter = 1]"
    if ([string]::IsNullOrWhiteSpace($op)) { $op = '1' }

    switch ($op) {
        '0' { exit 0 }
        '1' { $targetLanguage = $idiomaRecomendado }
        '2' { $targetLanguage = 'ES' }
        '3' { $targetLanguage = 'MX' }
        default { $targetLanguage = $idiomaRecomendado }
    }
}

# 4. Aplicar llaves de compatibilidad de hardware en Registro (TPM / CPU / RAM / SecureBoot / Storage)
Write-Host "`n[*] Aplicando bypass de requisitos de hardware (TPM / CPU / SecureBoot / RAM)..." -ForegroundColor Cyan
try {
    $moSetup = 'HKLM:\SYSTEM\Setup\MoSetup'
    if (-not (Test-Path $moSetup)) { New-Item -Path $moSetup -Force | Out-Null }
    Set-ItemProperty -Path $moSetup -Name 'AllowUpgradesWithUnsupportedTPMOrCPU' -Value 1 -Type DWord -Force | Out-Null

    $labConfig = 'HKLM:\SYSTEM\Setup\LabConfig'
    if (-not (Test-Path $labConfig)) { New-Item -Path $labConfig -Force | Out-Null }
    foreach ($name in @('BypassTPMCheck','BypassSecureBootCheck','BypassCPUCheck','BypassRAMCheck','BypassStorageCheck')) {
        Set-ItemProperty -Path $labConfig -Name $name -Value 1 -Type DWord -Force | Out-Null
    }
    Write-Host "    [OK] Registro configurado para permitir actualizacion sin bloqueos de hardware." -ForegroundColor Green
} catch {
    Write-Host "    [!] Aviso al escribir llaves LabConfig/MoSetup: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 5. Guardar foto rapida de inventario (no bloqueante) por si luego usa la opcion 6 (Verificar)
try {
    $raizEstado = Join-Path $env:ProgramData 'DGA\Migracion'
    . "$PSScriptRoot\migracion-core.ps1"
    Initialize-Run $raizEstado
    $invActual = Get-DgaInventory
    $runId = Get-Date -Format 'yyyyMMdd-HHmmss'
    $invPath = Join-Path $raizEstado "inventario\$runId.json"
    Write-JsonAtomic $invPath $invActual
    Write-JsonAtomic (Join-Path $raizEstado 'estado\migracion.json') ([ordered]@{
        VersionKit     = '4.1-directo'
        RunId          = $runId
        MachineGuid    = $invActual.MachineGuid
        Estado         = 'ActualizacionIniciada'
        FechaUtc       = [datetime]::UtcNow.ToString('o')
        BuildOrigen    = $invActual.Build
        VersionDestino = '10.0.26300.9457'
        EdicionDestino = $invActual.Edicion
        IdiomaDestino  = $invActual.Idioma
        Inventario     = $invPath
        Respaldo       = 'NoRequerido'
    })
} catch {
    # Nunca bloquear la migracion si falla el guardado de inventario opcional
}

# 6. Montar la ISO seleccionada y localizar setup.exe
$isoElegida = if ($targetLanguage -eq 'ES') { $IsoES_Path } else { $IsoMX_Path }
if (-not $isoElegida) {
    $isoElegida = if ($IsoES_Path) { $IsoES_Path } elseif ($IsoMX_Path) { $IsoMX_Path } else { $null }
}

$mountedDrive = $null
$executableSetup = $null

if ($isoElegida -and (Test-Path -LiteralPath $isoElegida)) {
    Write-Host "`n[*] Montando imagen ISO: $isoElegida ..." -ForegroundColor Cyan
    $diskImg = Get-DiskImage -ImagePath $isoElegida
    if (-not $diskImg.Attached) {
        $diskImg = Mount-DiskImage -ImagePath $isoElegida -PassThru -ErrorAction Stop
        Start-Sleep -Seconds 2
    }
    $vol = $diskImg | Get-Volume | Where-Object { $_.DriveLetter } | Select-Object -First 1
    if (-not $vol) {
        throw "No se pudo obtener letra de unidad para la ISO montada: $isoElegida"
    }
    $mountedDrive = "$($vol.DriveLetter):\"
    $executableSetup = Join-Path $mountedDrive 'setup.exe'
    Write-Host "    [OK] ISO disponible en unidad $mountedDrive" -ForegroundColor Green
} elseif (Test-Path -LiteralPath $SetupRoot) {
    $executableSetup = $SetupRoot
    Write-Host "`n[*] Usando setup.exe de la raiz del USB: $executableSetup" -ForegroundColor Green
} else {
    Write-Host "`n[ERROR] No se encontro el archivo ISO en '$KitRoot\ISO' ni setup.exe en el pendrive." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $executableSetup)) {
    Write-Host "`n[ERROR] No se encontro setup.exe en: $executableSetup" -ForegroundColor Red
    exit 1
}

# 7. Lanzar Windows Setup en modo In-Place Upgrade conservando archivos, perfiles y apps
$setupArgs = '/auto upgrade /dynamicupdate disable /eula accept /compat ignorewarning'

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Green
Write-Host " LISTO PARA INICIAR UPDATE DE SISTEMA OPERATIVO (SIN BORRAR NADA) " -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green
Write-Host "  Ejecutable : $executableSetup" -ForegroundColor White
Write-Host "  Argumentos : $setupArgs" -ForegroundColor White
Write-Host "  Accion     : Actualiza Windows 10 -> Windows 11 manteniendo todo intacto." -ForegroundColor Yellow
Write-Host ""

if (-not $SinConfirmacion) {
    $confirmar = Read-Host "Presione Enter (o escriba S) para lanzar la actualizacion ahora [N para cancelar]"
    if ($confirmar -match '^[Nn]') {
        Write-Host "[*] Actualizacion cancelada por el usuario." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "[*] Lanzando Windows Setup ($executableSetup $setupArgs)..." -ForegroundColor Green
$proc = Start-Process -FilePath $executableSetup -ArgumentList $setupArgs -PassThru
Write-Host "[OK] Windows Setup iniciado (PID: $($proc.Id))." -ForegroundColor Green
Write-Host "     El asistente de actualizacion continuara en pantalla sin borrar sus archivos ni programas." -ForegroundColor Cyan
exit 0

