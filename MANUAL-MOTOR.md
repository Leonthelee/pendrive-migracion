# Pendrive migrador Windows 10 → Windows 11

Motor base: 1.0.0 · Integración DGA: 4.0 · Referencias consultadas: **15 de octubre de 2026**.

Kit semiautomático para atender **31–100 equipos**, uno por sesión. Diseñado para
actualizar desde Windows conservando aplicaciones, archivos y configuraciones,
siempre que Windows Setup permita esa ruta. **No garantiza que todas las
aplicaciones funcionen después: el respaldo y el piloto son obligatorios.**

**No arrancar desde el pendrive.** Iniciar sesión en Windows 10 y ejecutar los
scripts desde allí. No hay autorun, formateo, borrado, reinicio programado,
instalación limpia, cambio de idioma ni suspensión de BitLocker en los scripts.
La actualización autorizada sí modifica Windows y puede requerir recuperación.

El ZIP no contiene ISO y **no permite migrar recién extraído**: `Config/medios.json`
está vacío. Sus ejemplos están desactivados y no tienen hashes utilizables.

## 1. Estructura definitiva

```text
PENDRIVE/
  INICIAR.bat
  README.md
  MANUAL-MOTOR.md
  config/medios.json
  config/medios.ejemplo.json
  config/software.json
  ISO/                         # ISO aprobadas incorporadas por el responsable
  scripts/Migrador.psm1
  scripts/09-migracion-segura.ps1
  scripts/04-premigracion.ps1
  scripts/menu.ps1
  scripts/07-software-dga.ps1
  reportes/                    # Reportes del motor y originales
  Operacion/CHECKLIST.md
  Operacion/control-equipos.csv
  Tests/Pruebas.ps1
  Tests/Integracion-DGA.ps1
  Tests/Adaptador-DGA.ps1
  Verificacion/                # Evidencia de pruebas simuladas
  REVISION-2026-10-15.md
```

Usar una unidad confiable con espacio suficiente para ambas ISO y reportes; como
referencia operativa, 32 GB o más, según tamaño real de las descargas. NTFS admite
archivos grandes y permisos; exFAT admite archivos grandes pero no ACL. FAT32 no
sirve para ISO de más de 4 GiB. El kit **no prepara ni formatea unidades**: copiar
la carpeta a una unidad ya preparada, sin sobrescribir archivos existentes.
Evitar rutas UNC, enlaces, dispositivos de red y ejecución desde el propio ZIP.

## 2. Alcance y requisitos

Microsoft publica CPU compatible de 64 bits, 2 núcleos y 1 GHz; 4 GB de RAM;
almacenamiento de 64 GB; UEFI con capacidad Secure Boot; TPM 2.0; DirectX 12/WDDM
2.0 y pantalla 720p de más de 9 pulgadas. La elegibilidad de CPU no se deduce solo
de su velocidad. Para actualización directa se exige Windows 10 2004 o posterior
y las actualizaciones indicadas por Microsoft. [Requisitos oficiales](https://learn.microsoft.com/en-us/windows/whats-new/windows-11-requirements).

**Política deliberadamente más restrictiva de este kit:**

- Origen Windows 10 **22H2, build 19045, x64**, cliente. Actualizaciones y licencia
  revisadas por el operador; este kit no instala parches previos.
- 4 GiB de RAM, volumen del sistema de al menos 64 GiB y **64 GiB libres**.
  Ese margen libre es política del kit; Setup puede necesitar más.
- Secure Boot **habilitado**, TPM 2.0 listo. No cambia firmware ni registro.
- Ediciones `Core`, `CoreN`, `CoreSingleLanguage`, `Professional`, `ProfessionalN`,
  `Education`, `EducationN`, `Enterprise`, `EnterpriseN`; siempre misma edición.
- Se bloquean x86, ARM64, Windows 11 de origen, Server, LTSC, IoT, Evaluation,
  modo S y ediciones no enumeradas. No implica que todas carezcan de otra ruta
  admitida; requieren un proyecto específico fuera de este paquete.
- Cifrado consultable con `Get-BitLockerVolume`. Volúmenes completamente
  descifrados o completamente cifrados/protegidos y desbloqueados. Se bloquean
  suspensión, conversión en curso, unidades bloqueadas y estado desconocido.
  Algunos Home no exponen ese cmdlet: el kit bloqueará, sin asumir descifrado.
- Sin reinicio pendiente detectado, otro Setup activo ni bypass detectado.
- Windows PowerShell **5.1 de 64 bits**, elevado, módulos nativos DISM/Storage/
  TrustedPlatformModule/BitLocker disponibles. PowerShell 7 no ejecuta el flujo.

Al consultar la información oficial, 26H2 figura como versión general actual y
25H2 sigue en soporte. **26H1 no es el destino de este proyecto**. No se fija una
ISO como universal: antes de cada oleada hay que revisar soporte por edición,
problemas conocidos, salvaguardas y compatibilidad del fabricante.
[Versiones y soporte](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information) ·
[Estado de 26H2](https://learn.microsoft.com/en-us/windows/release-health/status-windows-11-26h2).

El mapa admite medios generales H2 aprobados. No consulta automáticamente el
estado de soporte en Internet: exige revisión humana y aprobación renovada como
máximo cada 30 días. Fecha futura o vencida bloquea. El reloj debe ser correcto.

## 3. Idioma original, idioma del sistema y edición

Se registran separadamente:

| Campo | Procedencia | Uso |
|---|---|---|
| `OriginalLanguage` | `InstallLanguage` del registro, LCID hexadecimal | Indicio del idioma base instalado |
| `SystemLanguage` | API `GetSystemDefaultUILanguage` | Idioma UI predeterminado del sistema |
| `DismLanguage` | `DISM /Online /Get-Intl /English` | Contraste independiente |
| `UserLanguage` | Cultura UI del usuario | Informativo, nunca selecciona ISO |

Se exige que los primeros tres coincidan. El registro no es prueba histórica
infalible: imágenes modificadas o cambios previos pueden producir discrepancias.
En ese caso se bloquea y se investiga; no se cambian valores para forzar el pase.

Desde Windows 11 22H2, `/auto upgrade` requiere el mismo idioma UI predeterminado
del sistema y del medio. [Opciones oficiales de Setup](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-command-line-options?view=windows-11).

`es-MX` y `es-ES` son diferentes. Un usuario con teclado mexicano sobre Windows
base `en-US` necesita un medio `en-US` aprobado. El país o nombre comercial de
la descarga no decide el idioma: se inspecciona el índice dentro de la ISO.
No existe fallback a español de España o a otro idioma.

N y no N tampoco son intercambiables para este objetivo. El kit no cambia Home
a Pro ni ediciones de volumen. Consulte las [rutas oficiales de actualización](https://learn.microsoft.com/en-us/windows/deployment/upgrade/windows-upgrade-paths).

## 4. Incorporar y aprobar las ISO

Este procedimiento se realiza **una vez por medio/edición** en un equipo de
preparación autorizado, antes del piloto. Los comandos de montaje de esta
sección no se ejecutaron al construir el ZIP.

1. Descargar ISO sin modificar desde [Microsoft](https://www.microsoft.com/software-download/windows11)
   o desde el portal oficial de licencias de la organización para Enterprise.
   Elegir idioma y arquitectura correctos. No usar medios con bypass, Insider,
   desatendidos o personalizados. Revisar problemas conocidos antes de aprobar.
2. Obtener el **SHA256 publicado para esa descarga exacta**, desde la sección de
   verificación del portal oficial. Conservar la referencia en el registro de
   aprobación separado. Si el canal no proporciona un hash confiable, obtener
   validación de cadena de suministro del responsable; no inventar el hash.
   Este kit requiere un hash aprobado para continuar.
3. Comparar el valor publicado con el calculado; no basta con calcular un hash
   de un archivo desconocido y declararlo confiable. El hash del ZIP del kit y
   el hash de cada ISO son distintos.

Ejemplo (sustituir E: por la letra real):

```powershell
$kit = 'E:\PENDRIVE'
$iso = Join-Path $kit 'ISO\W11-MX-x64.iso'
Get-FileHash -LiteralPath $iso -Algorithm SHA256
```

4. Después de comparar el hash, montar en solo lectura e inspeccionar índices:

```powershell
$diskImage = Mount-DiskImage -ImagePath $iso -Access ReadOnly -PassThru
try {
    $vols = @($diskImage | Get-Volume | Where-Object { $_.DriveLetter })
    if ($vols.Count -ne 1) { throw 'Medio ambiguo' }
    $drive = "$($vols[0].DriveLetter):\"
    $images = @(@('sources\install.wim','sources\install.esd') |
        ForEach-Object { Join-Path $drive $_ } | Where-Object { Test-Path -LiteralPath $_ })
    if ($images.Count -ne 1) { throw 'Imagen ambigua' }
    Get-WindowsImage -ImagePath $images[0] |
        Select-Object ImageIndex, ImageName
    $indice = 1 # Cambiar por el indice de la edicion requerida; no asumir que es 1 o 6.
    Get-WindowsImage -ImagePath $images[0] -Index $indice |
        Select-Object ImageIndex, EditionId, Architecture, Version, Languages, DefaultLanguage
} finally {
    Dismount-DiskImage -ImagePath $iso
}
```

Si DISM del equipo no entiende la imagen o no expone los metadatos, no adivinar.
Preparar en un entorno de administración compatible y resolver la validación del
equipo origen antes de desplegar. El script de migración volverá a consultarlos.

5. Editar `Config/medios.json` usando el ejemplo como **estructura**, no como datos
   reales. Crear una sola entrada por combinación exacta idioma/edición/x64.
   `ImageIndex`, `ImageVersion`, idioma y edición salen de DISM; `Architecture`
   del mapa es `x64` y en DISM debe ser `9`. Registrar la versión completa.
6. Completar `File` (solo nombre simple dentro de ISO), `Sha256`, `Release`
   real del medio, `SourceUrl` oficial HTTPS, `ApprovedOn` (`yyyy-MM-dd`),
   `ApprovedBy` (ID del responsable) y `Approved: true` solo tras la revisión.
   El ejemplo de versión/índice es ilustrativo, **no certifica una ISO existente**.
7. Si una misma ISO tiene Home y Pro, crear dos entradas con sus propios índices.
   Para idiomas distintos usar medios distintos. Un mapeo duplicado bloquea,
   aunque una de sus entradas esté desactivada: retirar la entrada obsoleta del
   mapa activo con revisión del responsable.
8. Probar el medio en el piloto. Mantener una copia maestra protegida y distribuir
   copias controladas; registrar versión del kit y hashes por oleada.

En ejecución se recalcula el hash, se verifica la firma Authenticode de
`setup.exe`, se monta solo lectura y se contrasta el índice WIM/ESD con el mapa.
Una ISO ya montada se rechaza: desmontarla manualmente y repetir. El archivo se
mantiene abierto sin compartir escritura durante la sesión.

## 5. Operación en cada equipo

Abrir **Windows PowerShell como administrador**, de 64 bits, con una cuenta
autorizada. Respetar GPO, WDAC, AppLocker y política de ejecución. El kit no está
firmado: si la organización exige firma, someterlo a revisión y firma interna.
No usar `ExecutionPolicy Bypass`, desactivar controles ni desbloquear archivos
en masa para ejecutarlo.

Los siguientes comandos se ejecutan **uno por uno**; no pegar todos como lote:

```powershell
Set-Location 'E:\PENDRIVE'
powershell.exe -NoProfile -File .\Scripts\09-migracion-segura.ps1 -Accion Diagnostico
```

El diagnóstico consulta el equipo y escribe un reporte; no monta ISO ni ejecuta
Setup. DISM puede escribir sus propios logs. Revisar `resultado.json`, incluso
si aparece bloqueo. Un prechequeo apto **no certifica compatibilidad**.

```powershell
powershell.exe -NoProfile -File .\Scripts\09-migracion-segura.ps1 -Accion Compatibilidad
```

Este paso pide autorización para validar/montar el medio, confirmación de la
revisión técnica y aceptación expresa de licencia/análisis. Ejecuta ScanOnly
con Dynamic Update activado: requiere conectividad autorizada y puede descargar
componentes y escribir temporales. No se configura un modo offline alternativo.

Solo `0xC1900210` habilita el siguiente paso. `0`, errores, códigos desconocidos
y advertencias bloquean. La conversión admite códigos nativos firmados.

| Código | Acción |
|---|---|
| `0xC1900210` | Análisis sin bloqueos; aún no es instalación |
| `0xC1900208` | Revisar aplicación/controlador señalado |
| `0xC1900204` | No disponible conservar aplicaciones; no continuar |
| `0xC1900200` | Requisitos de hardware no satisfechos |
| `0xC190020E` | Espacio insuficiente; el script no borra nada |
| `0xC190010E` | Revisar aceptación de licencia |
| Otro, incluido `0x00000000` | No autorizado para migrar |

Interpretación basada en las [opciones de Setup](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-command-line-options?view=windows-11).

Después del respaldo y la ventana de mantenimiento:

```powershell
powershell.exe -NoProfile -File .\Scripts\09-migracion-segura.ps1 -Accion Migrar
```

El paso 03 **repite diagnóstico, hash, validación y ScanOnly**. No importa ni
confía en reportes guardados. Luego solicita:

1. `RESPALDO VERIFICADO NOMBRE-EQUIPO`: respaldo externo reciente y recuperable.
2. ID de respaldo/ticket, de 6–80 caracteres simples. Nunca contraseñas ni claves.
3. Si hay cifrado: `RECUPERACION VERIFICADA NOMBRE-EQUIPO`, para todas las unidades.
4. `MIGRAR NOMBRE-EQUIPO`: consentimiento final para modificar Windows.

Cualquier respuesta distinta cancela. Se repite el inventario después del
consentimiento; un cambio bloqueante impide iniciar. El scan caduca a los 30
minutos. No hay parámetros para saltar las confirmaciones.

El comando de instalación se construye internamente: `/auto upgrade`, índice
validado, Dynamic Update, BitLocker activo y `/noreboot`. Se muestra la interfaz
y la licencia de Setup; no se usa `/quiet` ni se acepta la licencia por argumento
en la instalación. **Después de su confirmación puede comenzar la actualización;
no espere una segunda aprobación propia del kit.** Si la interfaz ofrece
conservar solo archivos, instalación limpia, otra edición o idioma, cancelar y
revisar. No convertir manualmente el comando a otra modalidad.

`/noreboot` suprime solo el primer reinicio; los posteriores pueden ser
automáticos. Al terminar la fase inicial, revisar estado y logs antes de
reiniciar manualmente dentro de la ventana. No relanzar Setup para intentar
reanudar una instalación ya preparada. No cerrar a la fuerza ni retirar el USB.

El script espera a Setup sin matarlo por tiempo límite. Si tarda demasiado,
revisar actividad y logs con el procedimiento de soporte; no matar procesos por
considerarlos congelados sin diagnóstico. Si Setup ya se inició, la ISO queda
montada. En scan/cancelación previa se desmonta solamente el medio de la sesión.

## 6. BitLocker, respaldo y recuperación

Se usa `ForceKeepActive`: si Setup no puede continuar con BitLocker activo,
debe fallar. No se suspende ni descifra automáticamente. Cualquier necesidad de
suspensión se deriva a un procedimiento separado y autorizado.

La confirmación de respaldo es una **declaración del operador**, no una prueba
automática de que existe o se puede restaurar. El kit no copia datos, no crea
imágenes de disco y no valida servidores de backup. Antes de confirmar:

- Respaldo externo reciente de todos los perfiles, carpetas fuera del perfil,
  bases locales y datos de aplicaciones; cerrar apps para consistencia.
- Restauración de muestra comprobada y método viable para recuperar el equipo
  completo, aplicaciones/licencias y configuraciones. Anotar el ticket externo.
- Claves de recuperación BitLocker verificadas mediante el repositorio
  corporativo autorizado, fuera del USB y sin copiarlas a los reportes.
- Verificar también EFS, certificados y cifrado de terceros: el kit no los
  detecta exhaustivamente. BitLocker consultable no prueba ausencia de otro cifrado.
- Medio de recuperación y acceso de soporte listos. La reversión de Windows
  puede no estar disponible y no reemplaza el respaldo. No borrar Windows.old
  ni archivos de recuperación durante la aceptación.

## 7. Reportes, errores y protección

Cada ejecución crea una carpeta nueva con GUID. JSON contiene inventario,
volúmenes (sin protectores), medio aprobado, consentimientos con hora UTC,
códigos y estado. CSV resume ejecución/códigos; el nombre y UUID quedan en JSON.
El ID del ticket no debe contener datos sensibles. No hay transcripción de la
sesión ni volcado de claves. Los mensajes de error pueden incluir rutas técnicas.

`SetupRetornoRequiereRevision` con código 0/3010 **no significa Windows 11
instalado**. El script termina antes de verificar el resultado tras reinicios.
`BloqueadoOError` requiere revisión. Si no se puede escribir el reporte antes
del lanzamiento, no se instala. Una pérdida del USB después de iniciar Setup
puede impedir guardar el resultado; revisar logs del equipo.

Para investigar, consultar localmente `C:\$WINDOWS.~BT\Sources\Panther`,
`C:\$WINDOWS.~BT\Sources\Rollback` y `C:\Windows\Panther` cuando existan.
Los logs de Setup pueden contener datos personales: no se exportan automáticamente.
El kit no limpia logs ni temporales.

Acceso a los reportes limitado al equipo de soporte; transferirlos al repositorio
corporativo protegido al terminar la oleada, y aplicar su retención definida.
No guardar respaldos personales ni claves en el pendrive. Mantener copia maestra
del kit/mapa protegida y controlar su distribución.

**Límite de confianza:** equipo administrador, scripts, mapa y USB deben ser
confiables. Un hash junto al archivo no defiende contra quien puede reemplazar
ambos. El kit no es una barrera frente a un administrador malicioso ni detecta
todas las modificaciones históricas del sistema. Firmar scripts y custodiar
hashes/aprobaciones en un canal independiente según la política institucional.
Las comprobaciones de bypass/configuración son conservadoras pero no exhaustivas.

## 8. Despliegue de 31–100 equipos

1. Inventariar todos con paso 01 y agrupar por idioma base, edición, hardware,
   aplicaciones críticas y cifrado. Resolver desconocidos antes de programar.
2. Preparar ISO y mapas de esos grupos. No comprar ni cambiar ediciones desde el kit.
3. Piloto de 3–5 equipos representativos, incluyendo MX, ES y cifrado cuando
   existan. Validar aplicaciones, impresión, VPN y recuperación con usuarios.
4. Observar al menos una jornada de uso; pausar si aparece un incidente grave.
5. Oleadas iniciales de 5–10 equipos con técnico presente; ajustar el tamaño
   según duración real, ancho de banda, disponibilidad de USB y capacidad de soporte.
6. Usar una copia controlada por equipo concurrente. No ejecutar el script de
   migración por remoting, tarea programada ni bucle masivo. Un mutex bloquea
   sesiones simultáneas del kit en el mismo equipo; no bloquea a otros administradores.
7. Completar `Operacion/CHECKLIST.md` y `control-equipos.csv` tras cada equipo.
   No dar por aceptado un equipo solo porque terminó el proceso inicial.

## 9. Repetir las pruebas de la integración

Seguir los tres comandos de Tests indicados en README.md. Son pruebas simuladas;
no ejecutan Windows Setup. La suite de integración también analiza la sintaxis
de scripts y ejemplos PowerShell de ambos manuales, sin ejecutar esos ejemplos.

La revisión y límites constan en REVISION-2026-10-15.md; las salidas están en
Verificacion/. El registro de aplicación conserva hashes anteriores y nuevos
de los archivos cambiados. Mantener esa referencia fuera del pendrive.

**No se ha probado una actualización real ni conservación real de aplicaciones
con este paquete.** El piloto es necesario antes de extenderlo a la flota.
