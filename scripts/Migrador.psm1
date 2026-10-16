#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-Exact {
    param([string]$Message, [string]$Expected)
    Write-Host $Message
    if ((Read-Host "Escriba exactamente: $Expected") -cne $Expected) {
        throw 'Consentimiento ausente o incorrecto. Operacion cancelada.'
    }
}

function Assert-Host {
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess) {
        throw 'Use Windows PowerShell 5.1 de 64 bits, no PowerShell 7 ni x86.'
    }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Abra Windows PowerShell como administrador autorizado.'
    }
    if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { throw 'WinPE no admitido.' }
}

function Get-Inventory {
    $d=[ordered]@{
        Computer=$env:COMPUTERNAME; MachineId=$null; CollectedUtc=[DateTime]::UtcNow.ToString('o')
        Build=$null; ProductType=$null; Edition=$null; Architecture=$null
        OriginalLanguage=$null; SystemLanguage=$null; DismLanguage=$null
        UserLanguage=(Get-UICulture).Name; MemoryGB=$null; DiskGB=$null; FreeGB=$null
        CpuName=$null; CpuCores=$null; CpuMHz=$null; TpmReady=$null; Tpm20=$null
        SecureBoot=$null; PowerOnline=$null; PendingReboot=$null; BypassDetected=$null; SMode=$null
        SetupRunning=$null; BitLockerKnown=$false; Encrypted=$null; BitLockerHealthy=$null
        Volumes=@(); Errors=@()
    }
    try {
        $os=Get-CimInstance Win32_OperatingSystem
        $cs=Get-CimInstance Win32_ComputerSystem
        $cpu=@(Get-CimInstance Win32_Processor)
        $d.MachineId=(Get-CimInstance Win32_ComputerSystemProduct).UUID
        $d.Build=[int]$os.BuildNumber; $d.ProductType=[int]$os.ProductType
        $cv=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $d.Edition=$cv.EditionID
        if ([Environment]::Is64BitOperatingSystem -and @($cpu | Where-Object {$_.Architecture -ne 9}).Count -eq 0) {
            $d.Architecture='x64'
        } else { $d.Architecture='NoAdmitida' }
        $d.MemoryGB=[math]::Round($cs.TotalPhysicalMemory/1GB,2)
        $d.CpuName=($cpu.Name -join '; ')
        $d.CpuCores=($cpu | Measure-Object NumberOfCores -Sum).Sum
        $d.CpuMHz=($cpu | Measure-Object MaxClockSpeed -Minimum).Minimum
        $disk=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
        $d.DiskGB=[math]::Round($disk.Size/1GB,2); $d.FreeGB=[math]::Round($disk.FreeSpace/1GB,2)
    } catch { $d.Errors+='Inventario CIM o edicion no disponible' }
    try {
        $lang=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language').InstallLanguage
        if ($lang -notmatch '^[0-9a-fA-F]{4}$') { throw 'LCID invalido' }
        $d.OriginalLanguage=[Globalization.CultureInfo]::GetCultureInfo([Convert]::ToInt32($lang,16)).Name
        if (-not ('Migrador.NativeLanguage' -as [type])) {
            Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
namespace Migrador {
 public static class NativeLanguage {
  [DllImport("kernel32.dll")] public static extern ushort GetSystemDefaultUILanguage();
 }
}
'@
        }
        $d.SystemLanguage=[Globalization.CultureInfo]::GetCultureInfo([int][Migrador.NativeLanguage]::GetSystemDefaultUILanguage()).Name
        $intl=& "$env:SystemRoot\System32\dism.exe" /Online /Get-Intl /English 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'DISM fallo' }
        $matches=@($intl | Select-String '^\s*Default system UI language\s*:\s*([a-zA-Z0-9-]+)\s*$')
        if ($matches.Count -ne 1) { throw 'Idioma DISM ambiguo' }
        $d.DismLanguage=$matches[0].Matches[0].Groups[1].Value
    } catch { $d.Errors+='No se pudo verificar idioma original/predeterminado con registro, API y DISM' }
    try {
        $tpm=Get-Tpm
        $spec=(Get-CimInstance -Namespace 'root\CIMV2\Security\MicrosoftTpm' -ClassName Win32_Tpm).SpecVersion
        $d.TpmReady=($tpm.TpmPresent -and $tpm.TpmReady)
        $d.Tpm20=($spec -match '(^|[,\s])2\.0($|[,\s])')
        $d.SecureBoot=[bool](Confirm-SecureBootUEFI)
    } catch { $d.Errors+='TPM o Secure Boot desconocido/no consultable' }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $power=[Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus.ToString()
        if ($power -eq 'Unknown') { throw 'Alimentacion desconocida' }
        $d.PowerOnline=($power -eq 'Online')
    } catch { $d.Errors+='No se pudo confirmar alimentacion electrica externa' }
    try {
        $volumes=@(Get-BitLockerVolume)
        if ($volumes.Count -eq 0 -or $env:SystemDrive -notin $volumes.MountPoint) { throw 'Falta unidad del sistema' }
        $healthy=$true; $encrypted=$false
        foreach ($v in $volumes) {
            $status=[string]$v.VolumeStatus; $protection=[string]$v.ProtectionStatus
            $locked=[string]$v.LockStatus
            $plain=($status -eq 'FullyDecrypted' -and $v.EncryptionPercentage -eq 0 -and $protection -eq 'Off')
            $protected=($status -eq 'FullyEncrypted' -and $v.EncryptionPercentage -eq 100 -and $protection -eq 'On')
            if ($locked -ne 'Unlocked' -or -not ($plain -or $protected)) { $healthy=$false }
            if (-not $plain) { $encrypted=$true }
            # Nunca serializar el objeto BitLocker: contiene protectores y potenciales secretos.
            $d.Volumes+= [pscustomobject]@{MountPoint=$v.MountPoint;Status=$status;Protection=$protection;Lock=$locked}
        }
        $d.BitLockerKnown=$true; $d.BitLockerHealthy=$healthy; $d.Encrypted=$encrypted
    } catch { $d.Errors+='BitLocker/cifrado de dispositivo no consultable; revision manual necesaria' }
    try {
        $pending=(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
                 (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
        $sm=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
        if ($sm.PSObject.Properties.Name -contains 'PendingFileRenameOperations') {
            $pending=$pending -or @($sm.PendingFileRenameOperations).Count -gt 0
        }
        $setup=Get-ItemProperty 'HKLM:\SYSTEM\Setup'
        $d.PendingReboot=[bool]($pending -or $setup.SystemSetupInProgress -ne 0)
        $d.SetupRunning=@(Get-Process -ErrorAction Stop | Where-Object {$_.ProcessName -in @('setup','setuphost','setupprep')}).Count -gt 0
        $d.BypassDetected=$false
        foreach ($path in @('HKLM:\SYSTEM\Setup\LabConfig','HKLM:\SYSTEM\Setup\MoSetup')) {
            if (Test-Path $path) {
                $props=Get-ItemProperty $path
                foreach ($prop in $props.PSObject.Properties) {
                    if (($prop.Name -like 'Bypass*' -or $prop.Name -eq 'AllowUpgradesWithUnsupportedTPMOrCPU') -and $prop.Value -ne 0) { $d.BypassDetected=$true }
                }
            }
        }
        $d.SMode=$false
        $ci='HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy'
        if (Test-Path $ci) {
            $p=Get-ItemProperty $ci
            if ($p.PSObject.Properties.Name -contains 'SkuPolicyRequired') { $d.SMode=($p.SkuPolicyRequired -ne 0) }
        }
    } catch { $d.Errors+='No se pudo comprobar reinicio, Setup o politicas de compatibilidad' }
    [pscustomobject]$d
}

function Assert-Inventory {
    param($Inventory)
    $i=$Inventory
    foreach ($name in @('MachineId','Build','ProductType','Edition','Architecture','OriginalLanguage','SystemLanguage','DismLanguage',
        'MemoryGB','DiskGB','FreeGB','CpuCores','CpuMHz','TpmReady','Tpm20','SecureBoot','PowerOnline','PendingReboot',
        'BypassDetected','SMode','SetupRunning','BitLockerKnown','Encrypted','BitLockerHealthy','Errors')) {
        if ($i.PSObject.Properties.Name -notcontains $name -or $null -eq $i.$name) { throw "Dato obligatorio desconocido: $name" }
    }
    if (@($i.Errors).Count -gt 0) { throw ('Diagnostico incompleto: ' + ($i.Errors -join '; ')) }
    if ($i.MachineId -notmatch '^[0-9a-fA-F-]{36}$' -or $i.MachineId -match '^(0|-)+$|^(F|-)+$') { throw 'Identidad del equipo desconocida.' }
    if ($i.Build -ne 19045 -or $i.ProductType -ne 1) { throw 'Politica: solo Windows 10 22H2 cliente (19045).' }
    if ($i.Architecture -ne 'x64') { throw 'Solo Windows x64. x86 y ARM requieren otro proyecto.' }
    if ($i.Edition -notin @('Core','CoreN','CoreSingleLanguage','Professional','ProfessionalN','Education','EducationN','Enterprise','EnterpriseN')) {
        throw 'Edicion fuera de alcance: LTSC/IoT/Server/Evaluation y otras no autorizadas.'
    }
    if ([string]::IsNullOrWhiteSpace($i.SystemLanguage) -or $i.SystemLanguage -ne $i.OriginalLanguage -or $i.SystemLanguage -ne $i.DismLanguage) {
        throw 'Idioma original y predeterminado no coinciden o son desconocidos. No hay fallback.'
    }
    foreach ($name in @('TpmReady','Tpm20','SecureBoot','PowerOnline','BitLockerKnown','BitLockerHealthy')) {
        if ($i.$name -isnot [bool] -or $i.$name -ne $true) { throw "Control no satisfecho: $name" }
    }
    foreach ($name in @('PendingReboot','BypassDetected','SMode','SetupRunning')) {
        if ($i.$name -isnot [bool] -or $i.$name -ne $false) { throw "Condicion bloqueante: $name" }
    }
    if ($i.Encrypted -isnot [bool]) { throw 'Cifrado desconocido.' }
    if ($i.MemoryGB -lt 4 -or $i.DiskGB -lt 64 -or $i.FreeGB -lt 64 -or $i.CpuCores -lt 2 -or $i.CpuMHz -lt 1000) {
        throw 'Recursos insuficientes: 4 GiB RAM, 64 GiB volumen y libres, 2 nucleos, 1 GHz. Setup puede exigir mas.'
    }
}

function Select-Media {
    param($Inventory, $Map)
    if ($Map.SchemaVersion -ne 1) { throw 'Version de mapeo no admitida.' }
    $items=@($Map.Media | Where-Object {
        $_.Language -eq $Inventory.SystemLanguage -and $_.Edition -eq $Inventory.Edition -and $_.Architecture -eq $Inventory.Architecture
    })
    if ($items.Count -ne 1) { throw 'Debe existir exactamente un mapeo para idioma + edicion + arquitectura.' }
    $m=$items[0]
    if ($m.Approved -isnot [bool] -or -not $m.Approved) { throw 'Medio sin aprobacion.' }
    if ($m.File -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]*\.iso$') { throw 'Use solo nombre ISO simple, sin rutas, espacios ni argumentos.' }
    if ($m.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or $m.Sha256 -eq ('0'*64)) { throw 'SHA256 aprobado ausente/invalido.' }
    if ($m.Architecture -ne 'x64' -or $m.ImageIndex -isnot [int] -or $m.ImageIndex -lt 1) { throw 'Indice/arquitectura invalido.' }
    if ($m.ImageVersion -notmatch '^10\.0\.\d+\.\d+$' -or ([version]$m.ImageVersion).Build -lt 22000) { throw 'Version de imagen no es Windows 11.' }
    if ($m.Release -notmatch '^\d{2}H2$') { throw 'Solo medios generales H2; no 26H1 ni Insider/LTSC.' }
    $uri=[uri]$m.SourceUrl
    if ($uri.Scheme -ne 'https' -or $uri.Host -notmatch '(^|\.)microsoft\.com$|(^|\.)visualstudio\.com$') { throw 'Fuente de aprobacion debe ser portal oficial Microsoft HTTPS.' }
    if ([string]::IsNullOrWhiteSpace($m.ApprovedBy)) { throw 'Falta responsable de aprobacion.' }
    $date=[datetime]::ParseExact($m.ApprovedOn,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
    $age=((Get-Date).Date-$date.Date).TotalDays
    if ($age -lt 0 -or $age -gt 30) { throw 'Aprobacion futura o de mas de 30 dias: revalidar soporte y problemas conocidos.' }
    return $m
}

function Assert-Hash {
    param([string]$Actual,[string]$Expected)
    if ($Actual -notmatch '^[0-9a-fA-F]{64}$' -or $Expected -notmatch '^[0-9a-fA-F]{64}$' -or $Actual -ine $Expected) { throw 'SHA256 no coincide con el aprobado. No usar medio.' }
}
function Assert-Image {
    param($Image,$Media)
    if ($Image.EditionId -ne $Media.Edition -or [string]$Image.Architecture -ne '9' -or
        [string]$Image.Version -ne $Media.ImageVersion -or [string]$Image.DefaultLanguage -ne $Media.Language -or
        $Media.Language -notin @($Image.Languages | ForEach-Object {[string]$_})) {
        throw 'Metadatos WIM/ESD no coinciden exactamente con mapeo: idioma, edicion, arquitectura o version.'
    }
}
function Open-Media {
    param([string]$Root,$Media)
    $folder=Join-Path $Root 'ISO'
    $path=Join-Path $folder $Media.File
    foreach ($item in @((Get-Item -LiteralPath $Root),(Get-Item -LiteralPath $folder),(Get-Item -LiteralPath $path))) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'No se permiten enlaces/reparse points en el medio.' }
    }
    # Bloquea escrituras y sustitucion del archivo durante toda la sesion.
    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $mounted=$false
    try {
        Assert-Hash (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash $Media.Sha256
        $existing=Get-DiskImage -ImagePath $path
        if ($existing.Attached) { throw 'ISO ya montada. Desmontela manualmente antes de iniciar.' }
        $disk=Mount-DiskImage -ImagePath $path -Access ReadOnly -PassThru
        $mounted=$true
        $volumes=@($disk | Get-Volume | Where-Object {$_.DriveLetter})
        if ($volumes.Count -ne 1) { throw 'Letra del medio montado ambigua.' }
        $drive="$($volumes[0].DriveLetter):\"
        $setup=Join-Path $drive 'setup.exe'
        $sig=Get-AuthenticodeSignature -LiteralPath $setup
        if ($sig.Status -ne 'Valid' -or $null -eq $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(,|$)') { throw 'Firma Microsoft de setup.exe no valida.' }
        $images=@(@('sources\install.wim','sources\install.esd') | ForEach-Object {Join-Path $drive $_} | Where-Object {Test-Path -LiteralPath $_})
        if ($images.Count -ne 1) { throw 'Se requiere exactamente install.wim o install.esd.' }
        foreach ($name in @('autounattend.xml','unattend.xml','setupconfig.ini','sources\unattend.xml','sources\setupconfig.ini')) {
            if (Test-Path -LiteralPath (Join-Path $drive $name)) { throw 'Configuracion de instalacion externa en medio no admitida.' }
        }
        $image=Get-WindowsImage -ImagePath $images[0] -Index $Media.ImageIndex
        Assert-Image $image $Media
        [pscustomobject]@{Path=$path; Setup=$setup; Drive=$drive; Stream=$stream; Mounted=$true}
    } catch {
        if ($mounted) { Dismount-DiskImage -ImagePath $path -ErrorAction Continue | Out-Null }
        $stream.Dispose()
        throw
    }
}
function Convert-ExitCode {
    param([long]$Code)
    '0x{0:X8}' -f ($Code -band 4294967295L)
}
function Assert-ScanCode {
    param([string]$Code)
    $reasons=@{'0xC1900208'='Aplicaciones/controladores incompatibles';'0xC1900204'='No se pueden conservar aplicaciones';
        '0xC1900200'='Hardware no elegible';'0xC190020E'='Espacio insuficiente';'0xC190010E'='Licencia no aceptada'}
    if ($Code -ne '0xC1900210') {
        $reason='Resultado no autorizado (incluso 0 no habilita migracion)'
        if ($reasons.ContainsKey($Code)) {$reason=$reasons[$Code]}
        throw "ScanOnly bloqueado: $Code. $reason. Consulte Panther; no ignore advertencias."
    }
}
function Get-SetupArguments {
    param([switch]$Scan,[ValidateRange(1,999)][int]$Index)
    $argsText="/auto upgrade /imageindex $Index /dynamicupdate enable /bitlocker forcekeepactive /noreboot"
    if ($Scan) { $argsText+=' /quiet /eula accept /compat scanonly' }
    $argsText
}
function Invoke-SetupProcess {
    param([string]$Setup,[string]$Arguments)
    $p=Start-Process -FilePath $Setup -ArgumentList $Arguments -PassThru -Wait
    if ($null -eq $p.ExitCode) { throw 'Setup no devolvio codigo verificable.' }
    Convert-ExitCode $p.ExitCode
}
function Assert-NoExternalConfig {
    param([string]$Root)
    foreach ($path in @((Join-Path $Root 'setupconfig.ini'),(Join-Path (Get-Location).Path 'setupconfig.ini'),
        "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\WSUS\SetupConfig.ini",
        "$env:SystemDrive\autounattend.xml","$env:SystemRoot\Panther\Unattend\Unattend.xml","$env:SystemRoot\Panther\unattend.xml")) {
        if (Test-Path -LiteralPath $path) { throw 'Configuracion externa existente: requiere revision fuera de este flujo.' }
    }
}
function New-Report {
    param([string]$Root,[string]$Mode)
    $id=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N')
    $dir=Join-Path (Join-Path $Root 'Reportes') $id
    New-Item -ItemType Directory -Path $dir -ErrorAction Stop | Out-Null
    [pscustomobject]@{Directory=$dir; Data=[ordered]@{SchemaVersion=1;RunId=$id;Computer=$env:COMPUTERNAME;
        Mode=$Mode;StartedUtc=[datetime]::UtcNow.ToString('o');Status='Iniciado';Inventory=$null;Media=$null;
        ScanExit=$null;SetupExit=$null;Consents=@();Error=$null}}
}
function Save-Report {
    param($Report)
    $Report.Data['UpdatedUtc']=[datetime]::UtcNow.ToString('o')
    $Report.Data | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Report.Directory 'resultado.json') -Encoding UTF8
    $d=$Report.Data
    # CSV de campos controlados; sin texto libre, para evitar formulas de hojas de calculo.
    [pscustomobject]@{RunId=$d.RunId;Mode=$d.Mode;Status=$d.Status;ScanExit=$d.ScanExit;SetupExit=$d.SetupExit} |
        Export-Csv -LiteralPath (Join-Path $Report.Directory 'resumen.csv') -NoTypeInformation -Encoding UTF8
}
function Add-Consent {
    param($Report,[string]$Message,[string]$Expected)
    Confirm-Exact $Message $Expected
    $Report.Data.Consents+= [pscustomobject]@{Action=$Expected;Utc=[datetime]::UtcNow.ToString('o')}
    Save-Report $Report
}

function Invoke-MigrationWorkflow {
    [CmdletBinding()]
    param([ValidateSet('Diagnostico','Compatibilidad','Migracion')][string]$Mode,[string]$Root,[scriptblock]$BeforeInstall)
    Assert-Host
    $mutex=New-Object Threading.Mutex($false,'Global\PendriveMigradorW11')
    $held=$false; $report=$null; $mediaHandle=$null; $launched=$false
    try {
        try { $held=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $held=$true }
        if (-not $held) { throw 'Ya hay una sesion del migrador en este equipo.' }
        $report=New-Report $Root $Mode
        Save-Report $report
        $inventory=Get-Inventory
        $report.Data.Inventory=$inventory
        Save-Report $report
        Assert-Inventory $inventory
        if ($Mode -eq 'Diagnostico') {
            $report.Data.Status='PrechequeoAptoNoAutorizaMigracion'
            Save-Report $report
            Write-Host 'Prechequeo completado. Aun faltan medio, revision humana y ScanOnly.'
            return
        }
        Assert-NoExternalConfig $Root
        $map=Get-Content -LiteralPath (Join-Path $Root 'Config\medios.json') -Raw | ConvertFrom-Json
        $media=Select-Media $inventory $map
        $report.Data.Media=$media
        Save-Report $report
        Add-Consent $report 'Se verificara SHA256, se montara la ISO en solo lectura y se consultara su imagen.' 'VALIDAR MEDIO'
        $mediaHandle=Open-Media $Root $media
        Write-Host "Equipo: $($inventory.Computer) | $($inventory.Edition) | $($inventory.SystemLanguage) | $($media.File)"
        Add-Consent $report ('Confirme revision de CPU admitida, graficos/pantalla, salud de version, bloqueos de Windows Update, ' +
            'licencia, aplicaciones criticas y alimentacion estable. No use ISO para saltarse un safeguard hold.') 'REVISION TECNICA COMPLETA'
        Add-Consent $report ('ScanOnly no instala Windows, pero escribe temporales/logs y Dynamic Update contacta Microsoft. ' +
            'Lea los terminos oficiales: https://www.microsoft.com/useterms . Confirme autorizacion para aceptar EULA y ejecutar este analisis.') 'ACEPTO EULA Y ANALISIS'
        # Vuelve a comprobar estado tras la interaccion del operador.
        $fresh=Get-Inventory; Assert-Inventory $fresh
        if ($fresh.MachineId -ne $inventory.MachineId -or $fresh.SystemLanguage -ne $media.Language -or $fresh.Edition -ne $media.Edition) { throw 'Cambio de identidad/configuracion durante sesion.' }
        $code=Invoke-SetupProcess $mediaHandle.Setup (Get-SetupArguments -Scan -Index $media.ImageIndex)
        $report.Data.ScanExit=$code
        $scanTime=[datetime]::UtcNow
        Save-Report $report
        Assert-ScanCode $code
        $report.Data.Status='ScanAptoNoEsInstalacion'; Save-Report $report
        if ($Mode -eq 'Compatibilidad') { return }
        Add-Consent $report ('Confirme respaldo externo reciente de TODOS los perfiles/datos y aplicaciones recuperables, ' +
            'restauracion de muestra verificada, licencias/instaladores y plan de recuperacion. Un punto de restauracion o sincronizacion no basta.') "RESPALDO VERIFICADO $($inventory.Computer)"
        $ticket=Read-Host 'ID del respaldo/ticket (opcional: presione Enter para SIN-RESPALDO, o 6-80 caracteres)'
        if ([string]::IsNullOrWhiteSpace($ticket)) { $ticket='SIN-RESPALDO' }
        if ($ticket -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{5,79}$') { throw 'Referencia de respaldo invalida.' }
        $report.Data['BackupReference']=$ticket
        Save-Report $report
        if ($fresh.Encrypted) {
            Add-Consent $report 'Confirme claves de recuperacion accesibles y verificadas para todas las unidades cifradas, guardadas FUERA de este pendrive. No escriba las claves aqui.' "RECUPERACION VERIFICADA $($inventory.Computer)"
        }
        Add-Consent $report ('Se iniciara Setup /auto upgrade. Puede empezar a modificar Windows tras aceptar la licencia. ' +
            'Guarde trabajos y cierre aplicaciones. /noreboot detiene solo el PRIMER reinicio; reinicios posteriores son automaticos. ' +
            'No desconecte el medio. No se garantiza recuperacion sin respaldo.') "MIGRAR $($inventory.Computer)"
        if (([datetime]::UtcNow-$scanTime).TotalMinutes -gt 30) { throw 'Scan de mas de 30 minutos: vuelva a ejecutar el flujo.' }
        if ($null -ne $BeforeInstall) { & $BeforeInstall $media $report $fresh | Out-Null }
        if (([datetime]::UtcNow-$scanTime).TotalMinutes -gt 30) { throw 'Scan caduco durante validacion del respaldo; repetir.' }
        $last=Get-Inventory; Assert-Inventory $last
        if ($last.MachineId -ne $fresh.MachineId -or $last.SystemLanguage -ne $media.Language -or $last.Edition -ne $media.Edition -or $last.Encrypted -ne $fresh.Encrypted) { throw 'Estado cambio tras el scan; repetir flujo.' }
        Assert-NoExternalConfig $Root
        $report.Data.Status='SetupAutorizadoPendienteResultado'; Save-Report $report
        $launched=$true
        $result=Invoke-SetupProcess $mediaHandle.Setup (Get-SetupArguments -Index $media.ImageIndex)
        $report.Data.SetupExit=$result
        $report.Data.Status='SetupRetornoRequiereRevision'
        Save-Report $report
        if ($result -notin @('0x00000000','0x00000BC2')) { throw "Setup devolvio $result. Operacion no completada; revisar logs y estado antes de reintentar." }
        Write-Host "Setup devolvio $result. No equivale a migracion terminada. Revise interfaz/logs, reinicie manualmente cuando proceda y ejecute checklist posterior."
    } catch {
        if ($null -ne $report) {
            $report.Data.Status='BloqueadoOError'
            $report.Data.Error=$_.Exception.Message
            try { Save-Report $report } catch { Write-Warning 'No se pudo guardar reporte final. No continuar.' }
        }
        throw
    } finally {
        if ($null -ne $mediaHandle) {
            if (-not $launched) {
                try { Dismount-DiskImage -ImagePath $mediaHandle.Path | Out-Null } catch { Write-Warning 'No se pudo desmontar la ISO; revisar manualmente.' }
            } else { Write-Host 'ISO queda montada para Setup. No retire el pendrive durante la actualizacion.' }
            $mediaHandle.Stream.Dispose()
        }
        if ($null -ne $report) { Write-Host "Reportes: $($report.Directory)" }
        if ($held) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
Export-ModuleMember -Function Assert-Inventory,Select-Media,Assert-Hash,Assert-Image,Convert-ExitCode,Assert-ScanCode,Get-SetupArguments,Invoke-MigrationWorkflow
