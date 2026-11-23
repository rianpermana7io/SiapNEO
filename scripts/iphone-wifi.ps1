<#
.SYNOPSIS
    Wireless Debugging & Auto-Connect Helper untuk iPhone Rian (iOS 16.2).
.EXAMPLE
    .\iphone-wifi.ps1 auto-start       # Jalankan auto-connect/disconnect di background
    .\iphone-wifi.ps1 auto-status      # Cek status daemon (TERHUBUNG / MATI)
    .\iphone-wifi.ps1 auto-stop        # Matikan daemon
    .\iphone-wifi.ps1 install-startup  # Aktifkan auto-jalan setiap login Windows
    .\iphone-wifi.ps1 remove-startup   # Hapus auto-jalan Windows
    .\iphone-wifi.ps1 status           # Cek koneksi Wi-Fi iPhone langsung
    .\iphone-wifi.ps1 push "C:\Users\ACER\Downloads\SIAPNeo-iOS-v1.19.7.ipa"
    .\iphone-wifi.ps1 apps siap
    .\iphone-wifi.ps1 syslog SIAPNeo
#>
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$PassThruArgs
)

$ScriptDir   = $PSScriptRoot
$CliScript   = Join-Path $ScriptDir "iphone_wifi.py"
$DaemonScript = Join-Path $ScriptDir "iphone_wifi_daemon.py"
$CacheDir    = Join-Path $env:USERPROFILE ".pymobiledevice3"
$PidFile     = Join-Path $CacheDir "wifi_debug_daemon.pid"
$StateFile   = Join-Path $CacheDir "wifi_debug_state.json"
$StartupVbs  = Join-Path ([Environment]::GetFolderPath("Startup")) "SIAPNeo-iPhone-AutoWiFiDebug.vbs"

$cmd = if ($PassThruArgs -and $PassThruArgs.Count -gt 0) { $PassThruArgs[0].ToLower() } else { "status" }

function Get-DaemonProcess {
    if (Test-Path $PidFile) {
        $rawPid = (Get-Content $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
        if ($rawPid -match '^\d+$') {
            $p = Get-Process -Id ([int]$rawPid) -ErrorAction SilentlyContinue
            if ($p) { return $p }
        }
    }
    return $null
}

switch ($cmd) {
    "auto-start" {
        $existing = Get-DaemonProcess
        if ($existing) {
            Write-Host "Auto Wi-Fi Debugging Daemon sudah berjalan (PID: $($existing.Id))." -ForegroundColor Green
            Write-Host "Panel status lokal: http://127.0.0.1:8765/" -ForegroundColor Cyan
            exit 0
        }
        $pyw = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source
        if (-not $pyw) { $pyw = (Get-Command python.exe).Source }
        Start-Process -FilePath $pyw -ArgumentList "`"$DaemonScript`"" -WindowStyle Hidden
        Start-Sleep -Seconds 2
        $started = Get-DaemonProcess
        if ($started) {
            Write-Host "Auto Wi-Fi Debugging Daemon AKTIF (PID: $($started.Id))." -ForegroundColor Green
            Write-Host "Panel status lokal: http://127.0.0.1:8765/" -ForegroundColor Cyan
        } else {
            Write-Warning "Daemon dimulai; periksa log di $CacheDir\wifi_debug_daemon.log"
        }
    }
    "auto-stop" {
        $existing = Get-DaemonProcess
        if ($existing) {
            Stop-Process -Id $existing.Id -Force
            Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
            Write-Host "Auto Wi-Fi Debugging Daemon dimatikan (PID $($existing.Id))." -ForegroundColor Yellow
        } else {
            Write-Host "Daemon sedang tidak berjalan." -ForegroundColor Gray
        }
    }
    "auto-status" {
        $existing = Get-DaemonProcess
        if ($existing) {
            Write-Host "Daemon: BERJALAN (PID $($existing.Id)) | Panel: http://127.0.0.1:8765/" -ForegroundColor Green
        } else {
            Write-Host "Daemon: TIDAK BERJALAN" -ForegroundColor Yellow
        }
        if (Test-Path $StateFile) {
            Get-Content $StateFile
        }
    }
    "install-startup" {
        $pyw = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source
        if (-not $pyw) { $pyw = (Get-Command python.exe).Source }
        $vbs = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run Chr(34) & "$pyw" & Chr(34) & " " & Chr(34) & "$DaemonScript" & Chr(34), 0, False
"@
        Set-Content -Path $StartupVbs -Value $vbs -Encoding ASCII
        Write-Host "Auto-start Windows login AKTIF: $StartupVbs" -ForegroundColor Green
    }
    "remove-startup" {
        if (Test-Path $StartupVbs) {
            Remove-Item $StartupVbs -Force
            Write-Host "Auto-start Windows login dihapus." -ForegroundColor Yellow
        } else {
            Write-Host "Auto-start belum terpasang." -ForegroundColor Gray
        }
    }
    default {
        if (-not $PassThruArgs -or $PassThruArgs.Count -eq 0) {
            python "$CliScript" status
        } else {
            python "$CliScript" @PassThruArgs
        }
    }
}
