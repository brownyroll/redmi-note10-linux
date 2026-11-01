<#
  setup-phone-server.ps1 - เตรียม Redmi Note 10 4G (sunny) ให้เป็น Ubuntu server

  รันจาก PC (ต่อ USB):
      .\setup-phone-server.ps1              # ตรวจเครื่อง + push ไฟล์ + เปิด Termux
      .\setup-phone-server.ps1 -InstallApk   # adb install Termux ให้ด้วย
      .\setup-phone-server.ps1 -Ip           # ดู IP เครื่อง (LAN / tailscale)
      .\setup-phone-server.ps1 -Test dev@100.64.0.5 -Port 2222   # ทดสอบ ssh

  ไม่เขียนอะไรลงพาร์ทิชันของเครื่อง — แค่ push ไฟล์ลง /sdcard/Download
#>
param(
    [string]$Tools = "C:\Users\brown\Desktop\Google\Android\platform-tools",
    [switch]$InstallApk,
    [switch]$Ip,
    [string]$Test,
    [int]$Port = 2222,
    [string]$User = "dev"
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-Adb {
    $p = Join-Path $Tools 'adb.exe'
    if (Test-Path $p) { return $p }
    $c = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    throw "ไม่พบ adb.exe (คาดที่ $Tools)"
}
$adb = Find-Adb

function Adb { param([string[]]$A) (& $adb @A 2>&1 | Out-String).Trim() }

function Require-Device {
    $raw = Adb @('devices')
    $d = @($raw -split "`r?`n" | Where-Object { $_ -match '\sdevice$' })
    if ($d.Count -eq 0) {
        Write-Host "ไม่เห็นเครื่องในโหมด adb" -ForegroundColor Yellow
        Write-Host "  1) เปิด USB debugging (ตัวเลือกผู้พัฒนา)" -ForegroundColor Yellow
        Write-Host "  2) เสียบสาย, กด Allow ใน popup RSA" -ForegroundColor Yellow
        Write-Host "  3) ถ้าตอนนี้อยู่ fastboot: fastboot reboot" -ForegroundColor Yellow
        exit 2
    }
}

# ---------------------------------------------------------------- -Test
if ($Test) {
    Write-Host "==> ssh $Test -p $Port" -ForegroundColor Cyan
    & ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -p $Port $Test 'uname -a; id; uptime'
    exit $LASTEXITCODE
}

Require-Device

# ---------------------------------------------------------------- ข้อมูลเครื่อง
Write-Host "==> ข้อมูลเครื่อง" -ForegroundColor Cyan
$props = @('ro.product.device','ro.product.model','ro.build.version.release','ro.build.version.incremental','ro.miui.ui.version.name','ro.mi.os.version.name')
foreach ($p in $props) {
    $v = Adb @('shell', "getprop $p")
    if ($v) { Write-Host ("  {0,-32} {1}" -f $p, $v) }
}
$dev = Adb @('shell', 'getprop ro.product.device')
if ($dev -and $dev -ne 'sunny') { Write-Host "  [!] device=$dev (สคริปต์นี้ออกแบบสำหรับ sunny)" -ForegroundColor Yellow }

# ---------------------------------------------------------------- -Ip
if ($Ip) {
    Write-Host "`n==> IP" -ForegroundColor Cyan
    $wlan = Adb @('shell', 'ip -4 addr show wlan0')
    ($wlan -split "`r?`n" | Where-Object { $_ -match 'inet ' }) | ForEach-Object { Write-Host "  LAN: $($_.Trim())" }
    $ts = Adb @('shell', 'ip -4 addr show tailscale0')
    if ($ts -match 'inet ([\d\.]+)') { Write-Host "  Tailscale: $($Matches[1])" }
    else { Write-Host "  Tailscale: ไม่พบ tailscale0 (ยังไม่ได้เปิด VPN)" -ForegroundColor Yellow }
    Write-Host "`n  ssh $User@<IP> -p $Port"
    exit 0
}

# ---------------------------------------------------------------- APK
$apks = @(Get-ChildItem (Join-Path $here 'apk') -Filter 'termux*.apk' -ErrorAction SilentlyContinue)
if ($InstallApk) {
    if (-not $apks) {
        Write-Host "ไม่พบ apk\termux*.apk — โหลดก่อน:" -ForegroundColor Yellow
        Write-Host "  https://github.com/termux/termux-app/releases  (arm64-v8a)" -ForegroundColor Yellow
    } else {
        foreach ($a in $apks) {
            Write-Host "`n==> adb install $($a.Name)" -ForegroundColor Cyan
            $r = Adb @('install', '-r', $a.FullName)
            Write-Host $r
            if ($r -match 'USER_RESTRICTED|INSTALL_FAILED') {
                Write-Host "MIUI บล็อกการติดตั้งผ่าน USB — ใช้วิธีสำรอง:" -ForegroundColor Yellow
                Adb @('push', $a.FullName, '/sdcard/Download/') | Out-Null
                Write-Host "  ไฟล์อยู่ที่ /sdcard/Download/$($a.Name) → แตะติดตั้งบนมือถือ" -ForegroundColor Yellow
            }
        }
    }
}

# ---------------------------------------------------------------- push bootstrap
Write-Host "`n==> push bootstrap-ubuntu.sh" -ForegroundColor Cyan
$boot = Join-Path $here 'bootstrap-ubuntu.sh'
if (-not (Test-Path $boot)) { throw "ไม่พบ $boot" }
# แปลงเป็น LF กัน bash อ่าน CRLF พัง
$txt = (Get-Content $boot -Raw) -replace "`r`n", "`n"
$tmp = Join-Path $env:TEMP 'bootstrap-ubuntu.sh'
[IO.File]::WriteAllText($tmp, $txt, (New-Object System.Text.UTF8Encoding($false)))
Adb @('push', $tmp, '/sdcard/Download/bootstrap-ubuntu.sh') | Out-Null
Write-Host "  -> /sdcard/Download/bootstrap-ubuntu.sh"

# ---------------------------------------------------------------- เปิด Termux
Write-Host "`n==> เปิด Termux" -ForegroundColor Cyan
$pkg = Adb @('shell', 'pm list packages com.termux')
if ($pkg -match 'com\.termux$') {
    Adb @('shell', 'am start -n com.termux/com.termux.app.TermuxActivity') | Out-Null
} else {
    Write-Host "  ยังไม่ได้ติดตั้ง Termux — รันด้วย -InstallApk หรือติดตั้งเองจาก F-Droid" -ForegroundColor Yellow
}

Write-Host @"

---------------------------- ทำต่อบนมือถือ ----------------------------
ใน Termux พิมพ์ (บรรทัดเดียว):

  termux-setup-storage && bash /sdcard/Download/bootstrap-ubuntu.sh

จากนั้น:

  ~/start-ubuntu        # เปิด Ubuntu + sshd
  ~/ubuntu-shell        # เข้า Ubuntu

กลับมา PC เช็ค IP:   .\setup-phone-server.ps1 -Ip
ทดสอบ ssh:          .\setup-phone-server.ps1 -Test dev@<IP> -Port 2222
----------------------------------------------------------------------
"@ -ForegroundColor Green
