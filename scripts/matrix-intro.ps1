# ================================================================
#  MATRIX INTRO de consola — cascada columnar real
#  Goteos independientes por columna (cabeza blanca, estela verde)
#  y mensaje que emerge letra a letra en el centro, en orden aleatorio.
#  Usado por Menu_Actualizacion.bat / Ejecutar_Actualizacion.bat /
#  Ejecutar_Rapido.ps1. Tambien se puede probar directo:
#    powershell -ExecutionPolicy Bypass -File .\matrix-intro.ps1 -Duration 15
# ================================================================
param(
    [double]$Duration = 10,
    [string]$Message  = 'BIENVENIDO A WINDOWS 11 DGA'
)

try {
    $w = [Console]::WindowWidth  - 1
    $h = [Console]::WindowHeight - 1
    if ($w -lt 20 -or $h -lt 8) { return }   # consola demasiado chica: saltar intro
    [Console]::CursorVisible = $false
    [Console]::BackgroundColor = 'Black'
    Clear-Host

    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%&*+=?'.ToCharArray()
    $r     = New-Object Random
    $drops = New-Object int[] $w
    for ($i = 0; $i -lt $w; $i++) { $drops[$i] = -1 }   # -1 = columna inactiva
    $trail = 7

    $msg = $Message
    $x0  = [Math]::Max(0, [int](($w - $msg.Length) / 2))
    $my  = [int]($h / 2)
    $order    = 0..($msg.Length - 1) | Sort-Object { $r.Next() }
    $revealed = New-Object bool[] $msg.Length
    $rev = 0

    $t0 = Get-Date
    while ((((Get-Date) - $t0).TotalSeconds) -lt $Duration) {
        # activar hasta 3 columnas nuevas por fotograma
        for ($k = 0; $k -lt 3; $k++) {
            $col = $r.Next($w)
            if ($drops[$col] -lt 0) { $drops[$col] = 0 }
        }
        for ($i = 0; $i -lt $w; $i++) {
            if ($drops[$i] -lt 0) { continue }
            $y = $drops[$i]
            if ($y -lt $h) {                                   # cabeza: blanca brillante
                [Console]::SetCursorPosition($i, $y)
                [Console]::ForegroundColor = 'White'
                [Console]::Write($chars[$r.Next($chars.Length)])
            }
            $py = $y - 1
            if ($py -ge 0 -and $py -lt $h) {                   # cuerpo: verde
                [Console]::SetCursorPosition($i, $py)
                [Console]::ForegroundColor = 'Green'
                [Console]::Write($chars[$r.Next($chars.Length)])
            }
            $ty = $y - $trail
            if ($ty -ge 0 -and $ty -lt $h) {                   # cola: se borra
                [Console]::SetCursorPosition($i, $ty)
                [Console]::Write(' ')
            }
            $drops[$i]++
            if (($drops[$i] - $trail) -ge $h) { $drops[$i] = -1 }
        }
        # mensaje emergiendo (desde el segundo 3, una letra cada 0.18 s, orden aleatorio)
        $el   = ((Get-Date) - $t0).TotalSeconds
        $need = [Math]::Min($msg.Length, [Math]::Max(0, [int][Math]::Floor(($el - 3) / 0.18)))
        while ($rev -lt $need) { $revealed[$order[$rev]] = $true; $rev++ }
        for ($i = 0; $i -lt $msg.Length; $i++) {
            if ($revealed[$i]) {
                [Console]::SetCursorPosition($x0 + $i, $my)
                [Console]::ForegroundColor = 'White'
                [Console]::Write($msg[$i])
            }
        }
        Start-Sleep -Milliseconds 40
    }
    # cierre: mensaje solo, centrado, en verde
    Clear-Host
    [Console]::SetCursorPosition($x0, $my)
    [Console]::ForegroundColor = 'Green'
    [Console]::Write($msg)
    Start-Sleep -Milliseconds 1500
}
catch { }   # cualquier problema con la consola: seguir sin intro
finally {
    try { [Console]::ResetColor(); [Console]::CursorVisible = $true; Clear-Host } catch { }
}
