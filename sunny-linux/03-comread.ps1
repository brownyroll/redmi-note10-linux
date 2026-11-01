<#
  03-comread.ps1 - ต่อ COM แบบอ่าน-เขียน log ไฟล์ (ตรวจ ttyGS0 serial)
  .\03-comread.ps1 -Timeout 420 -OutFile .\console-diag.log
#>
param([int]$Timeout = 420, [string]$OutFile = ".\console-diag.log", [string]$Device = "COM10")
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = 'Continue'
$end = (Get-Date).AddSeconds($Timeout)
$log = New-Object System.Text.StringBuilder
$p = $null
while ((Get-Date) -lt $end) {
    if (-not $p) {
        $alive = Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -eq $Device }
        if ($alive) {
            try {
                $p = New-Object System.IO.Ports.SerialPort($Device, 115200, 'None', 8, 'One')
                $p.ReadTimeout = 200; $p.DtrEnable = $true; $p.RtsEnable = $true; $p.Open()
                Write-Host ("[comread] OPEN {0} @ {1}" -f $Device, (Get-Date -Format 'HH:mm:ss'))
            } catch { $p = $null; Start-Sleep -Seconds 2 }
        } else { Start-Sleep -Seconds 2 }
    } else {
        $alive = Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -eq $Device }
        if (-not $alive) {
            Write-Host ("[comread] DISCONNECTED @ {0}" -f (Get-Date -Format 'HH:mm:ss'))
            try { $p.Close() } catch {}
            $p = $null
            break
        }
        try { $t = $p.ReadExisting(); if ($t) { [void]$log.Append($t); Write-Host -NoNewline $t } } catch {}
        Start-Sleep -Milliseconds 200
    }
}
try { if ($p) { $p.Close() } } catch {}
[IO.File]::WriteAllText((Join-Path (Get-Location) $OutFile), $log.ToString(), [Text.Encoding]::UTF8)
Write-Host ("[comread] saved {0}" -f (Join-Path (Get-Location) $OutFile))
