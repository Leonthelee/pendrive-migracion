# Entrada heredada deshabilitada: no altera archivos ni monta imagenes.
param([string]$Iso,[string]$Destino)
Write-Error 'Use ISO oficiales intactas en ISO/ y config/medios.json. Consulte README.md. No se admiten medios extraidos/SWM en v4.'
exit 1
