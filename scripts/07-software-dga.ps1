[CmdletBinding()]
param([switch]$SoloDameware,[switch]$TodoBase,[switch]$Silencioso,[switch]$Simular,[switch]$Confirmado,[string]$Paquete,[string]$Raiz=(Join-Path $env:ProgramData 'DGA\Migracion'))
. "$PSScriptRoot\migracion-core.ps1"
$ErrorActionPreference='Stop'
function Find-Package($Item) {
    $usb=(Split-Path -Qualifier $PSScriptRoot)+'\'
    foreach($dir in @((Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\software'),(Join-Path $usb 'DGA\Dejar instalados por defecto'))) {
        if(Test-Path -LiteralPath $dir){
            $found=@(Get-ChildItem -LiteralPath $dir -Filter $Item.patron -File -Recurse)
            if($found.Count -gt 1){throw "Varios instaladores para $($Item.id) en $dir; deje una version aprobada."}
            if($found.Count -eq 1){return $found[0].FullName}
        }
    }
    $dir=if($Item.id -eq 'RSAT'){Join-Path $usb 'DGA\Forzar actualizaciones'}else{Join-Path $usb 'DGA'}
    if(Test-Path -LiteralPath $dir){
        $found=@(Get-ChildItem -LiteralPath $dir -Filter $Item.patron -File)
        if($found.Count -eq 1){return $found[0].FullName}
        if($found.Count -gt 1){throw "Varios instaladores para $($Item.id)."}
    }
    return $null
}
function Get-Detection($Item) {
    $apps=@(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object {$_.PSObject.Properties['DisplayName'] -and $Item.programa -and $_.DisplayName -like $Item.programa})
    $services=@(Get-Service -ErrorAction Stop | Where-Object {$Item.servicio -and $_.Name -match $Item.servicio})
    [pscustomobject]@{Detectado=($apps.Count -gt 0 -or $services.Count -gt 0);Versiones=@($apps | Select-Object DisplayName,DisplayVersion);Servicios=@($services | Select-Object Name,Status)}
}
try {
    if($Silencioso -and -not $Simular -and -not $Confirmado){throw '-Silencioso requiere -Confirmado. No se solicitara entrada interactiva.'}
    if(($Confirmado -or $Silencioso) -and -not $Simular -and -not ($Paquete -or $TodoBase -or $SoloDameware)){throw 'Indique -Paquete, -TodoBase o -SoloDameware en modo no interactivo.'}
    Initialize-Run $Raiz
    $config=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\software.json') -Raw | ConvertFrom-Json
    if($SoloDameware){$Paquete='DameWare'}
    if($TodoBase){$Paquete='BASE'}
    if(-not $Paquete -and -not $Simular){
        Write-Host 'Software DGA v3 - piloto' -ForegroundColor Cyan
        Write-Host 'D = diagnostico/simulacion de todos los paquetes (sin instalar)'
        Write-Host 'BASE = DameWare, GLPI, Aranda, Sophos, VPN'
        Write-Host 'Individual: DameWare, GLPI, Aranda, Sophos, VPN, Java, QGIS, HEC-RAS, RSAT'
        Write-Host '0 = volver'
        $Paquete=Read-Host 'Seleccione'
        if($Paquete -eq '0'){exit 0}
        if($Paquete -eq 'D'){$Simular=$true;$Paquete=''}
    }
    $selected=@($config.paquetes | Where-Object {($Simular -and -not $Paquete) -or ($Paquete -eq 'BASE' -and $_.base) -or $_.id -eq $Paquete})
    if(-not $selected.Count){throw 'Paquete no reconocido.'}
    if(-not $Simular -and -not(Test-Admin)){throw 'Instalacion requiere administrador.'}
    # Paquete BASE interactivo: una sola confirmacion en vez de una por programa. -Confirmado la omite (despliegue desatendido).
    if(-not $Simular -and $Paquete -eq 'BASE' -and -not $Confirmado){
        Write-Host ('Se instalaran en este equipo: '+(($selected | ForEach-Object id) -join ', ')) -ForegroundColor Cyan
        if((Read-Host 'Escriba INSTALAR BASE para continuar') -cne 'INSTALAR BASE'){throw 'Instalacion cancelada.'}
        $Confirmado=$true
    }
    $results=New-Object System.Collections.Generic.List[object]
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $restart=$false
    foreach($item in $selected){
        $row=[ordered]@{Paquete=$item.id;Estado='Pendiente';Instalador='';Deteccion=$null;Codigo=$null;Error=''}
        try {
            $detection=Get-Detection $item
            $row.Deteccion=$detection
            $installer=Find-Package $item
            $row.Instalador=$installer
            if($detection.Detectado){$row.Estado='YaDetectado-RevisarVersion'}
            elseif(-not $installer){$row.Estado='FaltaInstalador'}
            elseif($item.tipo -eq 'manual'){$row.Estado='InstalacionManual-RevisarConTecnico'}
            elseif($restart){$row.Estado='PendientePorReinicio'}
            else {
                $signature=Get-AuthenticodeSignature -LiteralPath $installer
                $pin=if($item.PSObject.Properties['sha256'] -and $item.sha256){[string]$item.sha256}else{''}
                if($pin){
                    # Hash aprobado en config\software.json: es la unica via para instaladores sin firma.
                    $actualHash=(Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
                    if($actualHash -ine $pin){throw "SHA256 del instalador no coincide con el aprobado en config\software.json ($actualHash)."}
                    $signer=if($signature.Status -eq 'Valid'){$signature.SignerCertificate.Subject}else{'sin firma digital; coincide con hash configurado (no acredita origen)'}
                } else {
                    if($signature.Status -ne 'Valid'){throw 'Firma digital no valida; revisar paquete antes de instalar.'}
                    $signer=$signature.SignerCertificate.Subject
                }
                $row['Firma']=$signature.Status.ToString()
                $row['Validacion']=if($pin){'HashConfiguradoCoincide'}else{'FirmaValida'}
                if(-not $Silencioso){
                    Write-Host "$($item.id): $installer" -ForegroundColor Cyan
                    Write-Host "Firmante: $signer"
                }
                if($Simular){$row.Estado='ValidacionPasada-NoEjecutado'}
                elseif(-not $Confirmado -and (Read-Host 'Escriba INSTALAR para ejecutar este paquete') -cne 'INSTALAR'){$row.Estado='Cancelado'}
                else {
                    if($item.tipo -eq 'msi'){
                        $log=Join-Path $Raiz "logs\$($item.id)-$stamp.log"
                        $proc=Start-Process msiexec.exe -ArgumentList "/i `"$installer`" $($item.argumentos) /L*v `"$log`"" -Wait -PassThru -WindowStyle Hidden
                    } else {$proc=Start-Process -FilePath $installer -ArgumentList $item.argumentos -Wait -PassThru -WindowStyle Hidden}
                    $row.Codigo=$proc.ExitCode
                    if($proc.ExitCode -in @(1641,3010)){$row.Estado='ReinicioRequerido-PendienteVerificacion';$restart=$true}
                    elseif($proc.ExitCode -ne 0){$row.Estado='FalloInstalador'}
                    else {
                        $after=Get-Detection $item
                        $row.Deteccion=$after
                        $row.Estado=if($after.Detectado){'InstaladoDetectado-PendientePruebaFuncional'}else{'NoVerificado'}
                    }
                }
            }
        } catch {$row.Estado='Error';$row.Error=$_.Exception.Message}
        $results.Add([pscustomobject]$row)
        Write-JsonAtomic (Join-Path $Raiz "reportes\software-$stamp.json") $results.ToArray()
    }
    if(-not $Silencioso){
        $results | Select-Object Paquete,Estado,Instalador | Format-Table -AutoSize
        Write-Host "Reporte: $Raiz\reportes\software-$stamp.json"
    }
    if(@($results | Where-Object {$_.Estado -in @('Error','FalloInstalador','NoVerificado','FaltaInstalador')}).Count){exit 1}
    if($restart){exit 3010}
    exit 0
} catch {Write-Host "SOFTWARE DETENIDO: $($_.Exception.Message)" -ForegroundColor Red;exit 1}
