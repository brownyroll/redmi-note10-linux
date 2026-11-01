param(
    [int]$TimeoutMin = 30,
    [string]$Img = "out\vendor_boot-tele.img",
    [int]$DumpSec = 300
)
$ErrorActionPreference = 'Continue'
$t = "C:\Users\brown\Desktop\Google\Android\platform-tools"
$base = "C:\Users\brown\Documents\Default Project\sunny-linux"
Set-Location $base

Write-Host "[go] waiting for fastboot (max $TimeoutMin min)"
$end = (Get-Date).AddMinutes($TimeoutMin)
$found = $false
while ((Get-Date) -lt $end) {
    $d = (& "$t\fastboot.exe" devices 2>&1 | Out-String)
    if ($d -match 'fastboot') { $found = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $found) { Write-Host "[go] timeout: no fastboot"; exit 1 }

Write-Host "[go] flashing $Img"
Get-Process adb -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 600
& "$t\fastboot.exe" flash vendor_boot $Img 2>&1 | Out-String | Write-Host
Get-Process fastboot -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 600
& "$t\fastboot.exe" continue 2>&1 | Out-String | Write-Host

Start-Sleep -Seconds 5
Write-Host "[go] dumping COM10 for $DumpSec s -> out\console-tele.log"
powershell -NoProfile -ExecutionPolicy Bypass -File .\51-comdump.ps1 -Timeout $DumpSec 2>&1 | Tee-Object -FilePath "out\console-tele.log" | Out-Null
Write-Host "[go] done"
