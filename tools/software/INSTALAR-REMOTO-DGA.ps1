<#
===============================================================================
 DGA Core Tools - by Daniel Díaz L. & AI Engine Antigravity
 Módulo: Instalador Desatendido REMOTO_DGA (Dameware Remote Everywhere)
 Versión: 1.1.0 (Safe QA Hardened)
===============================================================================
#>
[CmdletBinding()]
param(
    [string]$Instalador = (Join-Path $PSScriptRoot "REMOTO_DGA.exe")
)

$ErrorActionPreference = "Stop"

# 1. Verificación de privilegios de Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Este script requiere privilegios elevados. Ejecuta como Administrador." -ForegroundColor Red
    exit 1
}

# 2. Verificación de existencia del instalador
if (-not (Test-Path -LiteralPath $Instalador)) {
    Write-Host "[ERROR] No se encontro el archivo ejecutable en: $Instalador" -ForegroundColor Red
    exit 1
}

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " DGA Core Tools - Instalacion REMOTO DGA (Dameware / DRE)" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# 3. Snapshot de servicios previos (evaluando Name y DisplayName)
$filtroServicios = 'Dameware|DRE|BASupSrvc|SolarWinds|BeAnywhere'
$antes = Get-Service | Where-Object { $_.Name -match $filtroServicios -or $_.DisplayName -match $filtroServicios } | Select-Object -ExpandProperty Name

Write-Host "[*] Iniciando instalacion silenciosa de Dameware Remote Everywhere (/S)..." -ForegroundColor Yellow
$proceso = Start-Process -FilePath $Instalador -ArgumentList "/S" -Wait -PassThru

if ($proceso.ExitCode -eq 0) {
    Write-Host "[OK] Instalador finalizado con exito (ExitCode: 0)." -ForegroundColor Green
} else {
    Write-Host "[WARN] El instalador devolvio codigo de salida: $($proceso.ExitCode)" -ForegroundColor Yellow
}

# 4. Verificación reactiva con reintentos para registro de servicios
Write-Host "[*] Esperando registro e inicio de servicios..." -ForegroundColor Yellow
$maxEspera = 15
$segundos = 0
$nuevo = $null

while ($segundos -lt $maxEspera) {
    Start-Sleep -Seconds 3
    $segundos += 3
    $despues = Get-Service | Where-Object { $_.Name -match $filtroServicios -or $_.DisplayName -match $filtroServicios } | Select-Object -ExpandProperty Name
    $nuevo = $despues | Where-Object { $antes -notcontains $_ }
    if ($nuevo) { break }
}

# 5. Configuración y arranque de servicios detectados
if ($nuevo) {
    Write-Host "[OK] Servicios detectados: $($nuevo -join ', ')" -ForegroundColor Green
    foreach ($srvName in $nuevo) {
        try {
            Set-Service -Name $srvName -StartupType Automatic
            Start-Service -Name $srvName -ErrorAction SilentlyContinue
            Write-Host "  -> Servicio '$srvName' configurado en Automatico e Iniciado." -ForegroundColor Green
        } catch {
            Write-Host "  -> [ALERTA] No se pudo configurar el servicio '$srvName': $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "[INFO] No se detectaron nuevos servicios creados en el sondeo." -ForegroundColor Yellow
    Write-Host "       Verifica manualmente en 'services.msc' o en la consola web de Dameware." -ForegroundColor Gray
}

# 6. Diagnóstico de conectividad e IP local
Write-Host ""
Write-Host "[INFO] Requisito de Red: El equipo debe tener salida HTTPS (TCP 443) hacia la nube SolarWinds/Dameware." -ForegroundColor Cyan
Write-Host "[INFO] Direcciones IPv4 locales del equipo para verificacion:" -ForegroundColor Cyan

Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^127\.|^169\.254\.' } | ForEach-Object {
    Write-Host "  -> IP Local: $($_.IPAddress) ($($_.InterfaceAlias))" -ForegroundColor White
}

Write-Host ""
Write-Host "Instalacion y chequeo finalizado." -ForegroundColor Green
