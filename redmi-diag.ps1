<#
  redmi-diag.ps1 - Redmi Note 10 (codename: sunny) fastboot diagnostic

  Read-only by default. Nothing is written to the device.

  Usage:
    .\redmi-diag.ps1                 # report only
    .\redmi-diag.ps1 -Recovery       # try booting into recovery
    .\redmi-diag.ps1 -Bootloader     # reboot back to fastboot
#>
param(
    [string]$Tools = "C:\Users\brown\Desktop\Google\Android\platform-tools",
    [switch]$Recovery,
    [switch]$Bootloader
)

$fastboot = Join-Path $Tools "fastboot.exe"
$adb      = Join-Path $Tools "adb.exe"

if (-not (Test-Path $fastboot)) { Write-Error "fastboot.exe not found in $Tools"; exit 1 }

# fastboot writes to stderr; route through cmd so we get clean text lines
function Fb {
    param([string[]]$FbArgs)
    $line = '"{0}" {1} 2>&1' -f $fastboot, ($FbArgs -join ' ')
    (& cmd /c $line | Out-String) -split "`r?`n" |
        Where-Object { $_.Trim() -and $_ -notmatch '^finished\.|^OKAY|^\.\.\.$' }
}

Write-Host "=== 1. Connection ===" -ForegroundColor Cyan
$devs = (& cmd /c "`"$fastboot`" devices 2>&1" | Out-String).Trim()
if (-not $devs) {
    Write-Host "No fastboot device." -ForegroundColor Yellow
    Write-Host "Power off (hold Power 20s), then hold VOLUME DOWN + POWER until FASTBOOT appears." -ForegroundColor Yellow
    exit 2
}
Write-Host $devs -ForegroundColor Green

Write-Host "`n=== 2. Identity / lock state ===" -ForegroundColor Cyan
foreach ($v in 'product','serialno','unlocked','secure','anti','current-slot','slot-count','hw-revision','battery-voltage','battery-soc-ok','is-userspace','kernel') {
    $r = Fb @('getvar', $v)
    if ($r) { $r | ForEach-Object { Write-Host "  $_" } }
}

Write-Host "`n=== 3. Slot health ===" -ForegroundColor Cyan
$all = Fb @('getvar','all')
$all | Where-Object { $_ -match 'slot-(unbootable|successful|retry-count)' } | ForEach-Object { Write-Host "  $_" }

Write-Host "`n=== 4. Full dump -> redmi-getvar-all.txt ===" -ForegroundColor Cyan
$all | Set-Content -Path (Join-Path $PWD 'redmi-getvar-all.txt') -Encoding UTF8
Write-Host ("  saved {0} lines" -f $all.Count)

if ($Recovery) {
    Write-Host "`n=== 5. Booting recovery ===" -ForegroundColor Cyan
    Fb @('reboot','recovery')
    Start-Sleep -Seconds 15
    Write-Host "  Watch the phone screen. If recovery appears, boot chain is OK." -ForegroundColor Yellow
}

if ($Bootloader) {
    Write-Host "`n=== 5. Rebooting to bootloader ===" -ForegroundColor Cyan
    Fb @('reboot-bootloader')
    Start-Sleep -Seconds 8
    (& cmd /c "`"$fastboot`" devices 2>&1" | Out-String).Trim() | Write-Host
}
