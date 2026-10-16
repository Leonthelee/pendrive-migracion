<#
============================================================================
MINISTERIO DE OBRAS PUBLICAS - DIRECCION GENERAL DE AGUAS (DGA)
DGA Core Tools -- by Daniel Diaz L. & AI Engine Antigravity
Herramienta : 01 - Inventario Completo y Reporte HTML
Version     : 2.1.0 (Compilacion 2026-09)
============================================================================
#>
param([string]$OutHtml = "")
if (-not $OutHtml) {
  $Base = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
  $OutHtml = Join-Path $Base ("reportes\REPORTE-" + $env:COMPUTERNAME + "-" + (Get-Date -Format "yyyyMMdd-HHmm") + ".html")
}
$os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 Name, NumberOfCores, MaxClockSpeed
$ram = Get-CimInstance Win32_ComputerSystem | Select-Object TotalPhysicalMemory
$ramGB = [math]::Round($ram.TotalPhysicalMemory / 1GB, 1)
$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID, @{n="GBLibre";e={[math]::Round($_.FreeSpace/1GB,1)}}, @{n="GBTotal";e={[math]::Round($_.Size/1GB,1)}}
$gpu = Get-CimInstance Win32_VideoController | Select-Object Name, AdapterRAM
$drivers = pnputil /enum-drivers 2>&1 | Out-String
$driversProb = Get-PnpDevice | Where-Object { $_.Status -ne "OK" } | Select-Object FriendlyName, Status, Class | Format-Table -AutoSize | Out-String
$updates = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 15 HotFixID, Description, InstalledOn | ConvertTo-Html -Fragment
$html = @"
<html><head><meta charset='utf-8'><title>Reporte $env:COMPUTERNAME</title></head><body>
<h1>Inventario $env:COMPUTERNAME - $(Get-Date)</h1>
<h2>SO</h2><pre>$($os | Out-String)</pre>
<h2>CPU</h2><pre>$($cpu | Out-String)</pre>
<h2>RAM GB: $ramGB</h2>
<h2>Discos</h2><pre>$($disks | Out-String)</pre>
<h2>GPU</h2><pre>$($gpu | Out-String)</pre>
<h2>Dispositivos con problema</h2><pre>$driversProb</pre>
<h2>Ultimos 15 parches</h2>$updates
<h2>Drivers (pnputil, extracto)</h2><pre>$($drivers.Substring(0,[Math]::Min(8000,$drivers.Length)))</pre>
</body></html>
"@
New-Item -ItemType Directory -Path (Split-Path $OutHtml) -Force | Out-Null
Set-Content -LiteralPath $OutHtml -Value $html -Encoding UTF8
Write-Host "Reporte generado con exito: $OutHtml" -ForegroundColor Green
