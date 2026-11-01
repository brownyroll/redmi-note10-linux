<#
  51-comdump.ps1 - raw dump of a COM port (default COM10), shows exactly what the phone sends
  .\51-comdump.ps1 -Timeout 40
#>
param([int]$Timeout = 40, [string]$Device = "COM10")
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$end = (Get-Date).AddSeconds($Timeout)
$p = $null
while ((Get-Date) -lt $end) {
    if (-not $p) {
        $alive = Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -eq $Device }
        if (-not $alive) { Write-Host "[nodump] $Device ไม่มี"; Start-Sleep 2; continue }
        try {
            $p = New-Object System.IO.Ports.SerialPort($Device, 115200, 'None', 8, 'One')
            $p.ReadTimeout = 300; $p.DtrEnable = $true; $p.RtsEnable = $true
            $p.Open()
            Write-Host "[nodump] OPEN $Device $(Get-Date -Format 'HH:mm:ss')"
        } catch {
            Write-Host ("[nodump] open fail: " + $_.Exception.Message)
            $p = $null; Start-Sleep 2
        }
        continue
    }
    try {
        $t = $p.ReadExisting()
        if ($t) { Write-Host -NoNewline $t }
    } catch {}
    $alive = Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -eq $Device }
    if (-not $alive) { Write-Host "[nodump] DISCONNECTED $(Get-Date -Format 'HH:mm:ss')"; break }
    Start-Sleep -Milliseconds 150
}
if ($p) { try { $p.Close() } catch {} }
