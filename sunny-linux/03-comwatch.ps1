<#
  03-comwatch.ps1 — รอ COM10 แล้วเซฟ console log (ttyGS0/ACM) ต่อเนื่อง
  .\03-comwatch.ps1 -Timeout 600 -Device COM10
#>
param([int]$Timeout = 600, [string]$Device = "COM10")
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = 'Continue'
$end = (Get-Date).AddSeconds($Timeout)
$log = New-Object System.Text.StringBuilder
while ((Get-Date) -lt $end) {
    $c = Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -eq $Device }
    if ($c) {
        try {
            $p = New-Object System.IO.Ports.SerialPort($Device, 115200, 'None', 8, 'One')
            $p.ReadTimeout = 300; $p.DtrEnable = $true; $p.RtsEnable = $true; $p.Open()
            Write-Host ("OPEN {0} @ {1}" -f $Device, (Get-Date -Format 'HH:mm:ss'))
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt 900) {
                $alive = Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -eq $Device }
                if (-not $alive) { Write-Host ("DISCONNECTED @ {0}" -f (Get-Date -Format 'HH:mm:ss')); break }
                try { $t = $p.ReadExisting(); if ($t) { [void]$log.Append($t); Write-Host -NoNewline $t } } catch {}
                Start-Sleep -Milliseconds 250
            }
            $p.Close(); break
        } catch { Start-Sleep -Seconds 2 }
    } else { Start-Sleep -Seconds 2 }
}
$girl = "C:\Users\brown\Documents\Default Project\sunny-linux\out\console-diag.log"
[IO.File]::WriteAllText($girl, $log.ToString(), [Text.Encoding]::UTF8)
Write-Host ("`nบันทึกแล้ว → {0}" -f $girl)
