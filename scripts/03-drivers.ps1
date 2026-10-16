<#
============================================================================
MINISTERIO DE OBRAS PUBLICAS - DIRECCION GENERAL DE AGUAS (DGA)
DGA Core Tools -- by Daniel Diaz L. & AI Engine Antigravity
Herramienta : 03 - Diagnostico y Escaneo de Drivers
Version     : 2.1.0 (Compilacion 2026-09)
============================================================================
#>
param([string]$OutHtml = "", [switch]$SoloDiagnostico)
Write-Host "=== Diagnostico de Drivers DGA ===" -ForegroundColor Cyan
$bad = Get-PnpDevice | Where-Object { $_.Status -ne "OK" } | Select-Object FriendlyName, Status, InstanceId
$bad | Format-Table -AutoSize | Out-String | Write-Output
Write-Host "--- pnputil /scan-devices ---" -ForegroundColor Yellow
pnputil /scan-devices
# SDIO portable offline (colocar en tools\SDIO)
$sdio = Join-Path (Split-Path $PSScriptRoot | Split-Path -Parent | Join-Path -ChildPath "tools") "SDIO\SDIO_x64.exe"
if (Test-Path -LiteralPath $sdio) {
  Write-Host "SDIO encontrado: $sdio" -ForegroundColor Green
  if (-not $SoloDiagnostico) {
    $c = Read-Host "Abrir SDIO para instalar drivers offline? (S/N)"
    if ($c -eq "S" -or $c -eq "s") { Start-Process -FilePath $sdio }
  }
} else {
  Write-Host "SDIO no incluido. Descarga Snappy Driver Installer Origin portable y copialo a tools\SDIO\ para uso offline DGA." -ForegroundColor Gray
}
if ($OutHtml -and (Test-Path -LiteralPath $OutHtml)) {
  $txt = ($bad | Out-String)
  Add-Content -LiteralPath $OutHtml -Value ("<h2>Drivers con problema</h2><pre>" + $txt + "</pre>")
}
