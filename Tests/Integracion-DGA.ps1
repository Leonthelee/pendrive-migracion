#requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent
$script:count=0
function Test($Name,[scriptblock]$Body){ & $Body; $script:count++; Write-Output "OK $Name" }
function Reject([scriptblock]$Body){$blocked=$false;try{& $Body | Out-Null}catch{$blocked=$true};if(-not $blocked){throw 'Falta bloqueo'}}
Test 'motor integrado existe' {if(-not(Test-Path "$root\scripts\Migrador.psm1")){throw 'Falta motor endurecido'}}
Test 'entradas activas respetan politica' {
    foreach($p in @('INICIAR.bat','PRUEBA-DIAGNOSTICO.bat','PRUEBA-SOFTWARE.bat','scripts\menu.ps1','scripts\04-premigracion.ps1','scripts\06-migracion-win11.ps1','scripts\09-migracion-segura.ps1')) {
        if((Get-Content -LiteralPath (Join-Path $root $p) -Raw) -match '(?i)-ExecutionPolicy\s+Bypass'){throw "Bypass en $p"}
    }
}
Test 'adaptador usa motor y verificacion final de respaldo' {
    $t=Get-Content "$root\scripts\09-migracion-segura.ps1" -Raw
    if($t -notmatch 'Invoke-SafeMigrationWorkflow' -or $t -notmatch 'BeforeInstall' -or $t -notmatch 'Test-BackupManifest' -or $t -match 'Start-Process'){throw 'Flujo incorrecto'}
}
Test 'sin destino local por defecto' {if((Get-Content "$root\scripts\04-premigracion.ps1" -Raw) -match 'DestinoRespaldo=\(Join-Path'){throw 'Destino local por defecto'}}
Test 'preparador antiguo ya no busca ISO automaticamente' {if((Get-Content "$root\scripts\00-preparar-medio-ES.ps1" -Raw) -match 'Mount-DiskImage|robocopy|Split-Image'){throw 'Preparador antiguo sigue activo'}}
Test 'sin bypass WSUS ni postinstalacion automatica heredada' {
    if((Get-Content "$root\scripts\02-windows-update.ps1" -Raw) -match 'Set-ItemProperty|Restart-Service'){throw 'Modifica WSUS'}
    if((Get-Content "$root\scripts\05-post-standalone.ps1" -Raw) -match 'Start-Process|Restart-Computer|add-package|add-driver'){throw 'Instala automaticamente'}
}
. "$root\scripts\migracion-core.ps1"
Test 'destino en disco sistema rechazado' {
    function Get-Partition {param($DriveLetter) [pscustomobject]@{DiskNumber=0}}
    Reject { Assert-ExternalBackupDestination 'C:\respaldo' }
}
Test 'otra particion mismo disco rechazada' {
    function Get-Partition {param($DriveLetter) [pscustomobject]@{DiskNumber=0}}
    Reject { Assert-ExternalBackupDestination 'Z:\respaldo' }
}
Test 'identidad de disco desconocida rechazada' {
    function Get-Partition {throw 'No consultable'}
    Reject { Assert-ExternalBackupDestination 'Z:\respaldo' }
}
Test 'otro disco fisico aceptado con consultas simuladas' {
    function Get-Partition {param($DriveLetter) [pscustomobject]@{DiskNumber=$(if($DriveLetter -eq 'Z'){9}else{0})}}
    function Test-Path {param($LiteralPath) $false}
    Assert-ExternalBackupDestination 'Z:\respaldo'
}
Test 'UNC localhost rechazado' { Reject { Assert-ExternalBackupDestination '\\localhost\share\copia' } }
Test 'manifest local rechazado antes de hashear archivos' {
    $m=[pscustomobject]@{Estado='Verificado';MachineGuid='ID';CopiaLocal=$true;Archivos=@();FechaUtc=[datetime]::UtcNow.ToString('o')}
    Reject { Test-BackupManifest $m ([pscustomobject]@{MachineGuid='ID'}) }
}
Test 'manifest sin origenes rechazado' {
    $m=[pscustomobject]@{Estado='Verificado';MachineGuid='ID';CopiaLocal=$false;Archivos=@([pscustomobject]@{Origen='C:\datos\a';Destino='Z:\copia\a';SHA256=('A'*64)});Origenes=@();FechaUtc=[datetime]::UtcNow.ToString('o')}
    Reject { Test-BackupManifest $m ([pscustomobject]@{MachineGuid='ID'}) }
}
Test 'postverificacion no declara completado con faltantes' {
    $t=Get-Content "$root\scripts\09-migracion-segura.ps1" -Raw
    if($t -notmatch 'IncidenciasPostMigracion' -or $t -notmatch 'BitLocker' -or $t -notmatch 'EdicionDestino'){throw 'Postverificacion incompleta'}
}
Test 'todos los scripts activos analizan en PS5' {
    foreach($f in Get-ChildItem "$root\scripts","$root\Tests" -File | Where-Object {$_.Extension -in @('.ps1','.psm1')}){
        $tokens=$null;$errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)
        if(@($errors).Count){throw ($errors|Out-String)}
    }
}
Test 'ejemplos PowerShell de los manuales analizan sin ejecutarse' {
    foreach($name in @('README.md','MANUAL-MOTOR.md')){
        $text=Get-Content -LiteralPath (Join-Path $root $name) -Raw -Encoding UTF8
        foreach($block in [regex]::Matches($text,'(?s)```powershell\s*\r?\n(.*?)```')){
            $tokens=$null;$errors=$null
            [void][Management.Automation.Language.Parser]::ParseInput($block.Groups[1].Value,[ref]$tokens,[ref]$errors)
            if(@($errors).Count){throw ($errors|Out-String)}
        }
    }
}
Write-Output "TOTAL DGA: $script:count pruebas correctas; sin ejecutar instaladores ni consultas de hardware reales."
