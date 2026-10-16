# Kit DGA v4 — migración supervisada de Windows 10 a Windows 11

Integración del kit previo con el motor de migración conservador. No incluye ISO.
**No ejecutar una migración hasta aprobar los medios y completar el piloto.**
No arrancar el PC desde el pendrive: ejecutar desde Windows 10.

## Qué cambió

- El menú mantiene sus siete opciones. Diagnóstico, ScanOnly y migración usan un
  único motor, `scripts/Migrador.psm1`, a través de `09-migracion-segura.ps1`.
- Idioma base del registro contrastado con API y DISM; edición y x64 exactos.
  Si Windows base es en-US, no se selecciona ES ni MX por el teclado del usuario.
- ISO intactas en `ISO/`; `config/medios.json` vacío por defecto. Se exige mapa
  único aprobado, SHA256 esperado, firma Microsoft e índice WIM/ESD coincidente.
- Windows 10 22H2 x64, TPM 2.0, Secure Boot activo, alimentación externa
  confirmada, margen de 64 GiB libres, sin reinicio pendiente ni bypass detectado.
  Son políticas conservadoras del kit; no todos son mínimos generales Microsoft.
- BitLocker conocido y saludable; `ForceKeepActive` evita suspensión automática.
  Claves de recuperación confirmadas por el operador, nunca guardadas en reportes.
- Respaldo externo obligatorio. Se rechaza disco del sistema, otra partición del
  mismo disco y disco que contiene el kit. Un recurso UNC debe ser realmente
  remoto; los alias DNS locales requieren revisión del operador.
- El respaldo deja de omitir silenciosamente enlaces/placeholders de nube:
  bloquea y pide resolver el alcance. Seleccionar carpetas de datos reales.
- Manifiesto comprobado al inicio y otra vez justo antes de Setup; scan fresco,
  confirmación de respaldo recuperable y consentimiento con nombre del equipo.
- La instalación conserva interfaz y aceptación de licencia; no instala silenciosa.
  `/noreboot` detiene únicamente el primer reinicio; los posteriores pueden ser
  automáticos. No retirar el medio hasta terminar.
- Verificación posterior conserva comparación de aplicaciones y perfiles y añade
  edición/idioma y protección BitLocker. Faltantes generan incidencia y salida 1.
  No se certifica funcionamiento de aplicaciones ni integridad de todos los datos.
- Lanzadores respetan la política de ejecución. No se cambia WSUS. Preparación
  antigua de medios SWM e instalación automática de parches/drivers quedan
  deshabilitadas; sus originales se conservan en la copia de revisión.

## Uso

1. Leer este archivo y `MANUAL-MOTOR.md`. Abrir `INICIAR.bat` con una cuenta
   administradora autorizada. Si una política bloquea scripts sin firma, solicitar
   revisión/firma institucional; no usar ExecutionPolicy Bypass.
2. Opción **1**: diagnóstico. Windows 11 de origen se registra y bloquea para
   actualización; ya no muestra el antiguo resultado YA_WINDOWS11 como apto.
3. Incorporar las ISO oficiales exactas según el manual y completar el mapa.
   El paquete no confía en una ISO por su nombre ni en hashes calculados sin
   referencia aprobada. No inventar valores para completar la configuración.
4. Opción **3**: copia de carpetas elegidas a destino externo. No es imagen del
   sistema ni respaldo completo de aplicaciones. Disponer además de recuperación
   viable, licencias, datos de todos los perfiles y restauración de muestra.
5. Opción **4**: ScanOnly con autorización explícita. Dynamic Update está activo;
   necesita conectividad autorizada. No se desactiva WSUS para habilitarla.
6. Opción **5**: pide manifiesto externo y repite todas las verificaciones.
   Solo 0xC1900210 permite avanzar. Si el respaldo tarda demasiado y el scan
   supera 30 minutos, se bloquea; organizar alcance/ventana sin saltar controles.
7. Revisar retorno de Setup y reiniciar manualmente cuando corresponda. Un retorno
   0 o 3010 no acredita instalación completada. Después usar opción **6** y el
   checklist en `Operacion/CHECKLIST.md`.
8. Las opciones **2 y 7** mantienen el subsistema de software anterior. No se han
   cambiado los instaladores ni sus argumentos. Simular y validar versiones,
   licencias, procedencia y conexión al servidor institucional antes de instalar.

## Ubicaciones

- Medio/configuración: `ISO/` y `config/medios.json`, dentro de esta carpeta.
- Reportes del motor: `reportes/fecha-GUID/resultado.json` y `resumen.csv`.
- Estado e inventario antes de instalar: `%ProgramData%\DGA\Migracion`.
- Verificador sin USB: `%ProgramData%\DGA\Migracion\verificacion\ID\VERIFICAR.cmd`.
  Ruta exacta registrada en `estado\migracion.json`. No hay tarea de continuación
  automática. El comando se ejecuta manualmente tras el reinicio.
- Copias históricas: los directorios `_backup_*` son archivos de recuperación;
  no ejecutar sus scripts ni mezclarlos con el flujo vigente.

`MANUAL-MOTOR.md` contiene requisitos Microsoft, preparación de hashes/índices,
límites de confianza y operación por oleadas. En esta integración se opera con **INICIAR.bat y el adaptador 09**, para
conservar la validación del manifiesto y el estado local.

## Comprobaciones repetibles sin instalación

Desde la carpeta del kit, en Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -File .\Tests\Pruebas.ps1
powershell.exe -NoProfile -File .\Tests\Integracion-DGA.ps1
powershell.exe -NoProfile -File .\Tests\Adaptador-DGA.ps1
```

La primera suite simula Windows/Setup, la segunda analiza integración y política
de respaldo con consultas simuladas; la tercera ejecuta el adaptador real contra
módulos ficticios en una carpeta TEMP única. Conserva esos archivos de prueba
para inspección y no los borra. Ninguna ejecuta instaladores ni modifica BitLocker.

La revisión y resultados están en `REVISION-2026-10-15.md`. Falta piloto real de
Windows 10, montaje/DISM, ScanOnly y conservación de aplicaciones. Usar 3–5
equipos representativos antes de extenderlo a 31–100 equipos.
