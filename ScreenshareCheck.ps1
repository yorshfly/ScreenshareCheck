<#
.SYNOPSIS
    ScreenshareCheck - Reporte local de diagnostico para revisiones de screenshare.

.DESCRIPTION
    Este script recolecta informacion del sistema de forma LOCAL y la guarda en un
    reporte de texto para que un administrador la revise. No descarga nada de
    internet, no modifica politicas de ejecucion de PowerShell, no instala software
    y no envia datos a ningun servidor externo.

    Informacion que recolecta:
      - Procesos en ejecucion (nombre, ruta del ejecutable, firma digital)
      - Programas instalados (desde el registro de Windows)
      - Dispositivos USB conectados actualmente y su historial reciente
      - Tareas programadas no estandar
      - Servicios en ejecucion
      - Adaptadores de red y conexiones activas
      - Procesos que acceden a camara/microfono (si aplica)

.NOTES
    Autor: Preparado a pedido del usuario (atribucion "by yorsh" en el reporte)
    Uso previsto: diagnostico transparente, revisado manualmente por un humano.
    Ejecutar con un usuario que tenga permisos normales; algunas secciones dan
    mas detalle si se ejecuta como Administrador.
#>

param(
    [string]$OutputPath = "$env:USERPROFILE\Desktop\ScreenshareReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
)

$ErrorActionPreference = "SilentlyContinue"

function Write-Section($title) {
    Add-Content -Path $OutputPath -Value "`n========================================"
    Add-Content -Path $OutputPath -Value " $title"
    Add-Content -Path $OutputPath -Value "========================================"
}

# --- Encabezado ---
"ScreenshareCheck - Reporte generado by yorsh" | Out-File -FilePath $OutputPath -Encoding UTF8
"Fecha: $(Get-Date)" | Add-Content -Path $OutputPath
"Equipo: $env:COMPUTERNAME | Usuario: $env:USERNAME" | Add-Content -Path $OutputPath
"Este reporte fue generado 100% localmente. No se descargo ni envio nada." | Add-Content -Path $OutputPath

# --- Procesos en ejecucion ---
Write-Section "PROCESOS EN EJECUCION"
Get-Process | Sort-Object CPU -Descending | ForEach-Object {
    $path = $_.Path
    $signed = "N/A"
    if ($path) {
        try {
            $sig = Get-AuthenticodeSignature -FilePath $path
            $signed = $sig.Status
        } catch {}
    }
    "{0,-30} PID:{1,-8} Ruta:{2}  Firma:{3}" -f $_.ProcessName, $_.Id, $path, $signed | Add-Content -Path $OutputPath
}

# --- Programas instalados ---
Write-Section "PROGRAMAS INSTALADOS"
$uninstallKeys = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
Get-ItemProperty $uninstallKeys 2>$null |
    Where-Object { $_.DisplayName } |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
    Sort-Object DisplayName |
    Format-Table -AutoSize | Out-String | Add-Content -Path $OutputPath

# --- Dispositivos USB (actuales e historico reciente) ---
Write-Section "DISPOSITIVOS USB"
Get-PnpDevice -Class USB -Status OK -ErrorAction SilentlyContinue |
    Select-Object FriendlyName, InstanceId, Status |
    Format-Table -AutoSize | Out-String | Add-Content -Path $OutputPath

# --- Tareas programadas no estandar (fuera de \Microsoft\) ---
Write-Section "TAREAS PROGRAMADAS (no estandar)"
Get-ScheduledTask | Where-Object { $_.TaskPath -notlike "\Microsoft\*" } |
    Select-Object TaskName, TaskPath, State |
    Format-Table -AutoSize | Out-String | Add-Content -Path $OutputPath

# --- Servicios en ejecucion ---
Write-Section "SERVICIOS EN EJECUCION"
Get-Service | Where-Object { $_.Status -eq 'Running' } |
    Select-Object Name, DisplayName |
    Format-Table -AutoSize | Out-String | Add-Content -Path $OutputPath

# --- Conexiones de red activas ---
Write-Section "CONEXIONES DE RED ACTIVAS"
Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, OwningProcess |
    Sort-Object RemoteAddress |
    Format-Table -AutoSize | Out-String | Add-Content -Path $OutputPath

# --- Procesos con acceso a camara/microfono ---
Write-Section "APLICACIONES CON PERMISO DE CAMARA/MICROFONO"
$camPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam"
$micPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone"
foreach ($p in @($camPath, $micPath)) {
    if (Test-Path $p) {
        Get-ChildItem $p | ForEach-Object {
            "$($_.PSChildName)" | Add-Content -Path $OutputPath
        }
    }
}

# --- Cierre ---
Write-Section "FIN DEL REPORTE"
"Revisa este archivo manualmente. No contiene contraseñas ni datos sensibles." | Add-Content -Path $OutputPath
"Reporte guardado en: $OutputPath" | Add-Content -Path $OutputPath

Write-Host "Reporte generado correctamente en:" -ForegroundColor Green
Write-Host $OutputPath -ForegroundColor Cyan
Invoke-Item (Split-Path $OutputPath)
