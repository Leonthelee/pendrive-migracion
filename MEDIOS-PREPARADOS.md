# Medios encontrados y preparados — 15 de octubre de 2026

Las dos ISO de Descargas coinciden exactamente con los SHA256 publicados por
[Microsoft](https://www.microsoft.com/en-us/software-download/windows11).
Ambos setup.exe tienen firma Microsoft válida. Se montaron en solo lectura y
se desmontaron al terminar. No se ejecutó Setup.

| Medio | Arquitectura | Versión interna | Índice Pro |
|---|---|---|---|
| es-ES | x64 | 10.0.26300.9457 | 6 |
| es-MX | x64 | 10.0.26300.9457 | 4 |

Se prepararon 11 entradas de las ediciones admitidas por el motor. Las ediciones
Pro Education y Workstations detectadas no se añadieron: están fuera del alcance
actual del motor. No se encontró Enterprise en estos medios. No sustituirla por Pro.

## Estado: preparado, todavía NO aprobado

Los índices se leyeron del XML interno de WIM mediante 7-Zip. La herramienta
reportó una advertencia de conteo de referencias, aunque extrajo el XML con código
0. No se interpreta esto como prueba de corrupción: el hash completo coincide
con Microsoft. Tampoco se omite la comprobación nativa necesaria.

DISM no pudo consultar la imagen: error 740, sesión sin elevación. Por ello todas
las entradas tienen Approved=false. El motor bloquea su uso hasta la validación
nativa y aprobación explícita. No se ejecutó ScanOnly ni se validó una migración.

## Siguiente paso en Windows PowerShell 5.1 como administrador

Desde esta carpeta, ejecutar:

```powershell
.\scripts\10-Validar-Medios.ps1 -Aprobar
```

El validador recalcula hashes, verifica firma, monta cada ISO solo lectura,
contrasta cada índice con DISM y desmonta. Si todo coincide y el responsable
confirma APROBAR MEDIOS, guarda copia del mapa anterior y registra la aprobación.
No instala Windows, no modifica BitLocker y no cambia la política de ejecución.
Si una política institucional bloquea el script, solicitar revisión/firma a TI.
Después realizar el piloto con INICIAR.bat, diagnóstico y ScanOnly.

## Espacio y enlaces físicos

Las ISO están disponibles dentro de ISO/ mediante enlaces físicos NTFS a los
archivos de Descargas. Son los mismos bytes, no copias adicionales ni accesos
directos. Las rutas originales se conservan. Modificar el contenido desde una
ruta también cambia lo que se ve desde la otra: no editar las ISO.

Copiar la carpeta a un pendrive en otro volumen materializa las ISO completas y
requiere al menos unos 17,8 GB para los dos medios, más el resto del kit. Revisar
el tamaño total de tools/software y dejar margen. No usar FAT32. El hash se volverá
a comprobar antes de cada uso. Los archivos originales no se borraron ni movieron.

Esta actualización sustituye la indicación de mapa vacío en los informes de la
revisión anterior: ahora está poblado, pero pendiente de aprobación.
