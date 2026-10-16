# DGA migration pilot v3 - Windows PowerShell 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-JsonAtomic($Path, $Value) {
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Path -Force
}
function Get-ExitHex([int]$Code) {
    '0x{0:X8}' -f ([BitConverter]::ToUInt32([BitConverter]::GetBytes($Code), 0))
}
function Get-ScanMeaning([string]$Code) {
    switch ($Code) {
        '0xC1900210' { 'Compatible' }
        '0xC1900208' { 'Aplicacion o controlador incompatible' }
        '0xC1900204' { 'No se pueden conservar aplicaciones y datos' }
        '0xC1900200' { 'Requisitos de hardware no cumplidos' }
        '0xC190020E' { 'Espacio insuficiente' }
        default { 'Resultado no aprobado; revisar logs de Setup' }
    }
}
function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Initialize-Run([string]$Root) {
    foreach ($folder in 'logs','estado','inventario','reportes','scripts') {
        New-Item -ItemType Directory -Path (Join-Path $Root $folder) -Force | Out-Null
    }
}
function Get-DgaInventory {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $languageId = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language').InstallLanguage
    $language = [Globalization.CultureInfo]::GetCultureInfo([Convert]::ToInt32($languageId,16)).Name
    $profiles = @(Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and $_.LocalPath } | Select-Object SID,LocalPath,Loaded)
    $apps = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName } | Select-Object DisplayName,DisplayVersion,Publisher)
    [pscustomobject]@{
        Equipo=$env:COMPUTERNAME; FechaUtc=[datetime]::UtcNow.ToString('o')
        MachineGuid=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
        SO=$os.Caption; Build=[int]$os.BuildNumber; Edicion=$cv.EditionID
        Idioma=$language; ArquitecturaCPU=[int]$cpu.Architecture; ArquitecturaSO=$os.OSArchitecture
        CPU=$cpu.Name; RAMGB=[math]::Round($cs.TotalPhysicalMemory/1GB,1)
        SystemDrive=$env:SystemDrive; LibreGB=[math]::Round($disk.FreeSpace/1GB,1)
        Perfiles=$profiles; Aplicaciones=$apps
    }
}
function Get-Preflight($Inventory) {
    $checks = New-Object System.Collections.Generic.List[object]
    $checks.Add([pscustomobject]@{Prueba='Sistema origen'; Estado=$(if($Inventory.Build -ge 22000){'YA_WINDOWS11'}elseif($Inventory.Build -ge 19045){'OK'}else{'BLOQUEO'}); Detalle=$Inventory.SO})
    $checks.Add([pscustomobject]@{Prueba='Arquitectura x64'; Estado=$(if($Inventory.ArquitecturaCPU -eq 9 -and [Environment]::Is64BitOperatingSystem){'OK'}else{'BLOQUEO'}); Detalle=$Inventory.ArquitecturaSO})
    $checks.Add([pscustomobject]@{Prueba='Espacio operativo (35 GB)'; Estado=$(if($Inventory.LibreGB -ge 35){'OK'}else{'BLOQUEO'}); Detalle="$($Inventory.LibreGB) GB en $($Inventory.SystemDrive)"})
    $checks.Add([pscustomobject]@{Prueba='RAM'; Estado=$(if($Inventory.RAMGB -ge 4){'OK'}else{'BLOQUEO'}); Detalle="$($Inventory.RAMGB) GB"})
    try {
        $tpm = Get-CimInstance -Namespace 'root\CIMV2\Security\MicrosoftTpm' -ClassName Win32_Tpm
        $ok = $tpm -and $tpm.SpecVersion -match '(^|,\s*)2\.0(,|$)' -and $tpm.IsEnabled_InitialValue -and $tpm.IsActivated_InitialValue
        $checks.Add([pscustomobject]@{Prueba='TPM 2.0'; Estado=$(if($ok){'OK'}else{'BLOQUEO'}); Detalle=$(if($tpm){$tpm.SpecVersion}else{'No detectado'})})
    } catch { $checks.Add([pscustomobject]@{Prueba='TPM 2.0';Estado='DESCONOCIDO';Detalle=$_.Exception.Message}) }
    try {
        $secure = Confirm-SecureBootUEFI
        $checks.Add([pscustomobject]@{Prueba='Secure Boot';Estado=$(if($secure){'OK'}else{'BLOQUEO'});Detalle="Activado: $secure (politica conservadora del piloto)"})
    } catch { $checks.Add([pscustomobject]@{Prueba='Secure Boot';Estado='DESCONOCIDO';Detalle=$_.Exception.Message}) }
    try {
        $sm = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
        $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or ($sm.PSObject.Properties['PendingFileRenameOperations'] -and $sm.PendingFileRenameOperations)
        $checks.Add([pscustomobject]@{Prueba='Reinicio pendiente';Estado=$(if($pending){'BLOQUEO'}else{'OK'});Detalle="Pendiente: $([bool]$pending)"})
    } catch { $checks.Add([pscustomobject]@{Prueba='Reinicio pendiente';Estado='DESCONOCIDO';Detalle=$_.Exception.Message}) }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $power = [Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus.ToString()
        $checks.Add([pscustomobject]@{Prueba='Alimentacion';Estado=$(if($power -eq 'Online'){'OK'}elseif($power -eq 'Offline'){'BLOQUEO'}else{'DESCONOCIDO'});Detalle=$power})
    } catch { $checks.Add([pscustomobject]@{Prueba='Alimentacion';Estado='DESCONOCIDO';Detalle=$_.Exception.Message}) }
    $checks.ToArray()
}
function Get-Media { throw 'Ruta de medio heredada deshabilitada. Use config/medios.json y el motor v4.' }
function Get-RegularFiles([string]$Directory) {
    # Do not follow junctions or symlinks, including redirected profile folders.
    foreach($entry in Get-ChildItem -LiteralPath $Directory -Force) {
        if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Hay enlaces o placeholders de nube en el alcance. Resolverlos antes de respaldar; no se omiten silenciosamente.'}
        if($entry.PSIsContainer){Get-RegularFiles $entry.FullName}else{$entry}
    }
}
function Assert-BackupPaths([string[]]$Sources,[string]$Destination) {
    $dest = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    if($dest -eq ([IO.Path]::GetPathRoot($dest))){throw 'El destino no puede ser la raiz de una unidad.'}
    foreach($source in $Sources) {
        $src = [IO.Path]::GetFullPath($source).TrimEnd('\') + '\'
        if($src -eq [IO.Path]::GetPathRoot($src)){throw 'No se permite respaldar la raiz completa de una unidad.'}
        if($dest.StartsWith($src,[StringComparison]::OrdinalIgnoreCase) -or $src.StartsWith($dest,[StringComparison]::OrdinalIgnoreCase)){throw 'Origen y destino de respaldo se solapan.'}
        if((Get-Item -LiteralPath $source).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Un origen es un enlace; indique su ubicacion real.'}
    }
}
function Test-BackupManifest($Manifest,$Inventory) {
    if ($Manifest.CopiaLocal -ne $false) { throw 'Copia local o ubicacion desconocida no autorizada para migrar.' }
    if (@($Manifest.Origenes).Count -eq 0) { throw 'Manifiesto sin origenes.' }
    if($Manifest.Estado -ne 'Verificado' -or $Manifest.MachineGuid -ne $Inventory.MachineGuid){throw 'Respaldo no verificado o de otro equipo.'}
    $age = [datetime]::UtcNow - [datetime]::Parse($Manifest.FechaUtc).ToUniversalTime()
    if($age.TotalHours -gt 24 -or $age.TotalSeconds -lt -300){throw 'El respaldo debe tener menos de 24 horas.'}
    if(@($Manifest.Archivos).Count -eq 0){throw 'El respaldo no contiene archivos.'}
    foreach($file in $Manifest.Archivos) {
        Assert-ExternalBackupDestination $file.Destino
        if(-not (Test-Path -LiteralPath $file.Destino -PathType Leaf)){throw "Falta copia: $($file.Destino)"}
        if((Get-FileHash -LiteralPath $file.Destino -Algorithm SHA256).Hash -ne $file.SHA256){throw "Copia modificada: $($file.Destino)"}
        if(-not (Test-Path -LiteralPath $file.Origen -PathType Leaf) -or (Get-FileHash -LiteralPath $file.Origen -Algorithm SHA256).Hash -ne $file.SHA256){throw "Origen cambio desde el respaldo: $($file.Origen)"}
    }
    # Also reject new files omitted from the last backup.
    foreach($source in $Manifest.Origenes) {
        $actual = @(Get-RegularFiles $source | ForEach-Object FullName)
        $saved = @($Manifest.Archivos | Where-Object {$_.Raiz -eq $source} | ForEach-Object Origen)
        if($actual.Count -ne $saved.Count){throw "Cambio el listado de archivos en $source. Repita el respaldo."}
        if($actual.Count -gt 0 -and (Compare-Object $actual $saved)){throw "Cambio el listado de archivos en $source. Repita el respaldo."}
    }
}

function Get-Inventory { Get-DgaInventory }

function Assert-ExternalBackupDestination([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Destino externo obligatorio.' }
    if ($Path -notmatch '^[A-Za-z]:\\' -and $Path -notmatch '^\\\\[^\\]+\\[^\\]+\\') { throw 'Use ruta absoluta de carpeta externa o UNC.' }
    $full=[IO.Path]::GetFullPath($Path)
    if ($full -match '^\\\\([^\\]+)\\') {
        $server=$Matches[1]
        if ($server -in @('localhost','127.0.0.1','::1',$env:COMPUTERNAME,'.')) { throw 'UNC local no es respaldo externo.' }
        # Un alias DNS local no puede determinarse con esta regla: requiere validacion del operador.
    } else {
        $destDisk=@(Get-Partition -DriveLetter $full.Substring(0,1) -ErrorAction Stop)
        $systemDisk=@(Get-Partition -DriveLetter $env:SystemDrive.Substring(0,1) -ErrorAction Stop)
        $kitDrive=([IO.Path]::GetPathRoot((Split-Path $PSScriptRoot -Parent))).TrimEnd('\').TrimEnd(':')
        $kitDisk=@(Get-Partition -DriveLetter $kitDrive -ErrorAction Stop)
        if ($destDisk.Count -ne 1 -or $systemDisk.Count -ne 1 -or $kitDisk.Count -ne 1 -or
            $null -eq $destDisk[0].DiskNumber -or $destDisk[0].DiskNumber -eq $systemDisk[0].DiskNumber -or
            $destDisk[0].DiskNumber -eq $kitDisk[0].DiskNumber) { throw 'Destino debe estar fuera del disco del sistema y del disco del kit.' }
    }
    # Comprueba todos los antecesores existentes; no acepta junctions que redirijan al disco local.
    $cursor=$full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Destino/antecesor es un enlace; use ubicacion real.' }
        }
        $parent=Split-Path $cursor -Parent
        if ($parent -eq $cursor) { break }
        $cursor=$parent
    }
}
