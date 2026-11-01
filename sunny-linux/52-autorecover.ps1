param(
    [int]$TimeoutMin = 25,
    [string]$Img = "out\vendor_boot-report.img",
    [string]$FetchName = "current.log"
)
$ErrorActionPreference = 'Continue'
$t = "C:\Users\brown\Desktop\Google\Android\platform-tools"
$base = "C:\Users\brown\Documents\Default Project\sunny-linux"
Set-Location $base

Write-Host "[auto] waiting for fastboot (max $TimeoutMin min) - hold Vol-Down only"
$end = (Get-Date).AddMinutes($TimeoutMin)
$found = $false
while ((Get-Date) -lt $end) {
    $d = (& "$t\fastboot.exe" devices 2>&1 | Out-String)
    if ($d -match 'fastboot') { $found = $true; break }
    Start-Sleep -Seconds 3
}
if (-not $found) { Write-Host "[auto] no fastboot - abort"; exit 1 }

Write-Host "[auto] fastboot found -> flashing $Img"
Get-Process adb, fastboot -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 800
& "$t\fastboot.exe" flash vendor_boot $Img 2>&1 | Out-String | Write-Host
Get-Process fastboot -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
& "$t\fastboot.exe" continue 2>&1 | Out-String | Write-Host

Write-Host "[auto] booting... polling http://192.168.42.2/$FetchName"
Start-Sleep -Seconds 8
$deadline = (Get-Date).AddMinutes(8)
$got = $false
while ((Get-Date) -lt $deadline) {
    try {
        $r = Invoke-WebRequest -Uri "http://192.168.42.2/$FetchName" -UseBasicParsing -TimeoutSec 6
        $c = $r.Content
        if ($c -and $c.Length -gt 0) {
            $out = Join-Path $base "out\phone-$FetchName"
            [IO.File]::WriteAllText($out, $c, (New-Object Text.UTF8Encoding $false))
            Write-Host "[auto] GOT $FetchName ($($c.Length) chars) -> $out"
            $got = $true
            break
        }
    } catch { }
    Start-Sleep -Seconds 3
}
if (-not $got) { Write-Host "[auto] no http response (yet)" }
Write-Host "[auto] done"
