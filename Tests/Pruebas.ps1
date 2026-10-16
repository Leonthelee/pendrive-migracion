#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '..\Scripts\Migrador.psm1') -Force
$script:Count = 0
function Check($Name, [scriptblock]$Body) {
    & $Body
    $script:Count++
    Write-Output "OK $Name"
}
function Reject([scriptblock]$Body) {
    $rejected = $false
    try { & $Body | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Se esperaba bloqueo.' }
}
function Equal($Actual, $Expected) {
    if ($Actual -cne $Expected) { throw "Esperado [$Expected]; obtenido [$Actual]" }
}
function Inventory {
    [pscustomobject]@{
        Computer='PILOTO'; MachineId='12345678-1234-1234-1234-123456789abc'
        Build=19045; ProductType=1; Edition='Professional'; Architecture='x64'
        OriginalLanguage='es-MX'; SystemLanguage='es-MX'; DismLanguage='es-MX'
        MemoryGB=8; DiskGB=256; FreeGB=100; CpuCores=4; CpuMHz=2400
        TpmReady=$true; Tpm20=$true; SecureBoot=$true; PowerOnline=$true; PendingReboot=$false
        BypassDetected=$false; SMode=$false; SetupRunning=$false
        BitLockerKnown=$true; Encrypted=$true; BitLockerHealthy=$true
        Errors=@()
    }
}
function Mapping {
    [pscustomobject]@{ SchemaVersion=1; Media=@([pscustomobject]@{
        Language='es-MX'; Edition='Professional'; Architecture='x64'
        File='W11-MX.iso'; Sha256=('A'*64); ImageIndex=6
        ImageVersion='10.0.26200.1000'; Release='25H2'
        Approved=$true; SourceUrl='https://www.microsoft.com/software-download/windows11'
        ApprovedOn=(Get-Date).ToString('yyyy-MM-dd'); ApprovedBy='OPERADOR'
    }) }
}
Check 'inventario admisible' { Assert-Inventory (Inventory) }
foreach ($field in @('SystemLanguage','DismLanguage','OriginalLanguage')) {
    Check "idioma divergente $field" { $i=Inventory; $i.$field='es-ES'; Reject { Assert-Inventory $i } }
}
foreach ($field in @('TpmReady','Tpm20','SecureBoot','PowerOnline','BitLockerKnown','BitLockerHealthy')) {
    Check "control negativo $field" { $i=Inventory; $i.$field=$false; Reject { Assert-Inventory $i } }
}
foreach ($field in @('PendingReboot','BypassDetected','SMode','SetupRunning')) {
    Check "bloqueo $field" { $i=Inventory; $i.$field=$true; Reject { Assert-Inventory $i } }
}
foreach ($field in @('MemoryGB','DiskGB','FreeGB','CpuCores','CpuMHz')) {
    Check "recurso insuficiente $field" { $i=Inventory; $i.$field=0; Reject { Assert-Inventory $i } }
}
Check 'error de consulta' { $i=Inventory; $i.Errors=@('WMI'); Reject { Assert-Inventory $i } }
Check 'campo ausente' { $i=Inventory; $i.PSObject.Properties.Remove('TpmReady'); Reject { Assert-Inventory $i } }
Check 'arquitectura ARM bloqueada' { $i=Inventory; $i.Architecture='arm64'; Reject { Assert-Inventory $i } }
Check 'origen antiguo bloqueado' { $i=Inventory; $i.Build=19044; Reject { Assert-Inventory $i } }
Check 'Windows 11 origen bloqueado' { $i=Inventory; $i.Build=26100; Reject { Assert-Inventory $i } }
Check 'LTSC bloqueado' { $i=Inventory; $i.Edition='EnterpriseS'; Reject { Assert-Inventory $i } }
Check 'mapeo exacto' { Equal (Select-Media (Inventory) (Mapping)).File 'W11-MX.iso' }
Check 'sin fallback MX ES' { $m=Mapping; $m.Media[0].Language='es-ES'; Reject { Select-Media (Inventory) $m } }
Check 'N no equivale a no N' { $m=Mapping; $m.Media[0].Edition='ProfessionalN'; Reject { Select-Media (Inventory) $m } }
Check 'mapeo duplicado' { $m=Mapping; $m.Media+= $m.Media[0]; Reject { Select-Media (Inventory) $m } }
Check 'sin aprobacion' { $m=Mapping; $m.Media[0].Approved=$false; Reject { Select-Media (Inventory) $m } }
Check 'mapa vacio bloquea' { Reject { Select-Media (Inventory) ([pscustomobject]@{SchemaVersion=1;Media=@()}) } }
Check 'falta hash bloquea' { $m=Mapping; $m.Media[0].PSObject.Properties.Remove('Sha256'); Reject { Select-Media (Inventory) $m } }
Check 'fuente no oficial bloquea' { $m=Mapping; $m.Media[0].SourceUrl='https://example.org/iso'; Reject { Select-Media (Inventory) $m } }
Check 'fecha futura bloquea' { $m=Mapping; $m.Media[0].ApprovedOn=(Get-Date).AddDays(2).ToString('yyyy-MM-dd'); Reject { Select-Media (Inventory) $m } }
Check 'indice string bloquea' { $m=Mapping; $m.Media[0].ImageIndex='6'; Reject { Select-Media (Inventory) $m } }
Check 'aprobacion string no booleano' { $m=Mapping; $m.Media[0].Approved='true'; Reject { Select-Media (Inventory) $m } }
Check 'hash ficticio cero' { $m=Mapping; $m.Media[0].Sha256='0'*64; Reject { Select-Media (Inventory) $m } }
Check 'traversal' { $m=Mapping; $m.Media[0].File='..\evil.iso'; Reject { Select-Media (Inventory) $m } }
Check 'inyeccion ruta' { $m=Mapping; $m.Media[0].File='x" /auto clean.iso'; Reject { Select-Media (Inventory) $m } }
Check 'aprobacion vencida' { $m=Mapping; $m.Media[0].ApprovedOn='2020-01-01'; Reject { Select-Media (Inventory) $m } }
Check '26H1 bloqueada' { $m=Mapping; $m.Media[0].Release='26H1'; Reject { Select-Media (Inventory) $m } }
Check 'codigo scan firmado' { Equal (Convert-ExitCode -1047526896) '0xC1900210' }
Check 'codigo scan unsigned' { Equal (Convert-ExitCode 3247440400) '0xC1900210' }
Check 'scan correcto' { Assert-ScanCode '0xC1900210' }
foreach ($code in @('0x00000000','0xC1900208','0xC1900204','0xC1900200','0xC190020E','0xC190010E','0xDEADBEEF')) {
    Check "scan bloqueado $code" { Reject { Assert-ScanCode $code } }
}
Check 'argumentos scan sin ignorar advertencias' {
    $a=Get-SetupArguments -Scan -Index 6
    if ($a -notmatch '/compat scanonly' -or $a -match 'ignorewarning' -or $a -notmatch '/bitlocker forcekeepactive') { throw $a }
}
Check 'argumentos migracion visibles sin aceptar licencia' {
    $a=Get-SetupArguments -Index 6
    if ($a -notmatch '/auto upgrade' -or $a -match '/quiet|/eula|/compat|/auto clean|/auto dataonly') { throw $a }
}
Check 'hash discordante' { Reject { Assert-Hash ('A'*64) ('B'*64) } }
Check 'hash concordante' { Assert-Hash ('a'*64) ('A'*64) }
Check 'metadatos correctos' {
    $x=[pscustomobject]@{EditionId='Professional';Architecture=9;Version='10.0.26200.1000';DefaultLanguage='es-MX';Languages=@('es-MX')}
    Assert-Image $x (Mapping).Media[0]
    foreach ($p in @('EditionId','Architecture','Version','DefaultLanguage')) {
        $bad=$x.PSObject.Copy(); $bad.$p='0'; Reject { Assert-Image $bad (Mapping).Media[0] }
    }
}
Check 'consentimiento incorrecto bloquea' {
    $m=Get-Module Migrador
    & $m { function Read-Host { 'NO' }; $blocked=$false; try { Confirm-Exact 'X' 'SI' } catch { $blocked=$true }; if(-not $blocked){throw 'No bloqueo'} }
}
function WorkflowTest {
    param([string]$Mode='Migracion',[string]$ScanCode='0xC1900210',[string]$RejectPrompt='',
        [int]$ExpectedScans=1,[int]$ExpectedInstalls=0,[bool]$ExpectedError=$true,[switch]$BadInventory,[switch]$ReportFailure,[switch]$StateChange,
        [string]$InstallCode='0x00000000',[switch]$CallbackFailure)
    $mod=Get-Module Migrador
    & $mod {
        param($inv,$map,$mode,$scanCode,$rejectPrompt,$expectedScans,$expectedInstalls,$expectedError,$badInventory,$reportFailure,$stateChange,$installCode,$callbackFailure)
        $script:fakeInv=$inv; $script:fakeMap=$map; $script:fakeScanCode=$scanCode
        $script:fakeReject=$rejectPrompt; $script:fakeScans=0; $script:fakeInstalls=0
        $script:fakeGets=0; $script:fakeStateChange=$stateChange
        $script:fakeReportFailure=$reportFailure
        $script:fakeInstallCode=$installCode
        $script:fakeCallbackFailure=$callbackFailure
        if ($badInventory) {$script:fakeInv.TpmReady=$false}
        function Assert-Host {}
        function Assert-NoExternalConfig {}
        function Get-Inventory {
            $script:fakeGets++
            $copy=$script:fakeInv.PSObject.Copy()
            if ($script:fakeStateChange -and $script:fakeGets -ge 3) {$copy.FreeGB=1}
            $copy
        }
        function Get-Content { $script:fakeMap | ConvertTo-Json -Depth 6 }
        function New-Report {
            [pscustomobject]@{Directory='SIMULADO';Data=[ordered]@{Inventory=$null;Media=$null;Status='Inicio';ScanExit=$null;SetupExit=$null;Consents=@();Error=$null}}
        }
        function Save-Report { if($script:fakeReportFailure){throw 'Disco reportes no disponible'} }
        function Open-Media { [pscustomobject]@{Setup='SIMULADO';Path='SIMULADO';Stream=(New-Object IO.MemoryStream)} }
        function Dismount-DiskImage {}
        function Read-Host {
            param([string]$Prompt)
            if ($script:fakeReject -and $Prompt -like "*$script:fakeReject*") { return 'NO' }
            if ($Prompt -like 'ID del respaldo*') {return 'BACKUP-001'}
            if ($Prompt.StartsWith('Escriba exactamente: ')) { return $Prompt.Substring(21) }
            throw "Prompt no contemplado: $Prompt"
        }
        function Invoke-SetupProcess {
            param($Setup,$Arguments)
            if ($Arguments -match '/compat scanonly') { $script:fakeScans++; return $script:fakeScanCode }
            $script:fakeInstalls++; return $script:fakeInstallCode
        }
        $failed=$false
        try { Invoke-MigrationWorkflow -Mode $mode -Root 'SIMULADO' -BeforeInstall {
            param($media,$report,$fresh)
            if ($script:fakeScans -ne 1 -or $report.Data.Consents[-1].Action -ne 'MIGRAR PILOTO') { throw 'Validacion del respaldo antes del consentimiento/scan' }
            if ($script:fakeCallbackFailure) { throw 'Respaldo cambio desde la comprobacion inicial' }
        } } catch { $failed=$true }
        if ($script:fakeScans -ne $expectedScans -or $script:fakeInstalls -ne $expectedInstalls -or $failed -ne $expectedError) {
            throw "Flujo: scans=$script:fakeScans installs=$script:fakeInstalls error=$failed; esperado $expectedScans/$expectedInstalls/$expectedError"
        }
    } (Inventory) (Mapping) $Mode $ScanCode $RejectPrompt $ExpectedScans $ExpectedInstalls $ExpectedError $BadInventory.IsPresent $ReportFailure.IsPresent $StateChange.IsPresent $InstallCode $CallbackFailure.IsPresent
}
Check 'flujo diagnostico nunca monta ni instala' { WorkflowTest -Mode Diagnostico -ExpectedScans 0 -ExpectedError $false }
Check 'flujo scan nunca instala' { WorkflowTest -Mode Compatibilidad -ExpectedError $false }
foreach($c in @('0x00000000','0xC1900208','0xC1900204','0xC1900200','0xC190020E','0xDEADBEEF')) {
    Check "flujo codigo $c impide instalar" { WorkflowTest -ScanCode $c }
}
foreach($p in @('VALIDAR MEDIO','REVISION TECNICA COMPLETA','ACEPTO EULA Y ANALISIS')) {
    Check "flujo rechazo $p" { WorkflowTest -RejectPrompt $p -ExpectedScans 0 }
}
foreach($p in @('RESPALDO VERIFICADO','ID del respaldo','RECUPERACION VERIFICADA','MIGRAR PILOTO')) {
    Check "flujo rechazo $p" { WorkflowTest -RejectPrompt $p }
}
Check 'flujo inventario bloqueado' { WorkflowTest -BadInventory -ExpectedScans 0 }
Check 'flujo reporte no escribible bloquea' { WorkflowTest -ReportFailure -ExpectedScans 0 }
Check 'flujo estado cambia tras scan bloquea' { WorkflowTest -StateChange }
Check 'flujo autorizado repite scan y solo entonces instala' { WorkflowTest -ExpectedInstalls 1 -ExpectedError $false }
Check 'flujo Setup devuelve error sin declarar exito' { WorkflowTest -ExpectedInstalls 1 -InstallCode '0xC1900101' }
Check 'respaldo invalidado antes de instalar bloquea Setup' { WorkflowTest -CallbackFailure }
Write-Output "TOTAL: $script:Count pruebas correctas. Setup, montaje, CIM, BitLocker y reportes de flujo fueron simulados."
