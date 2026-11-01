<#
  00-verify.ps1 — ยืนยันว่าเป็น Redmi Note 10 4G "sunny" จริง และบันทึกผลไว้

  .\00-verify.ps1
  .\00-verify.ps1 -SaveDir logs

  ผลลัพธ์: logs\verify_<timestamp>.txt  (+ สรุปบนจอ)
  exit code: 0 = sunny ยืนยันแล้ว, 3 = ไม่พบเครื่อง, 4 = ไม่ใช่ sunny, 5 = เครื่องยังไม่ authorize
#>
param(
    [string]$Tools = "C:\Users\brown\Desktop\Google\Android\platform-tools",
    [string]$SaveDir = (Join-Path $PSScriptRoot 'logs')
)
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8; $OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $SaveDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$log   = Join-Path $SaveDir "verify_$stamp.txt"
$script:lines = @()

function Say([string]$s, [string]$color = 'Gray') {
    Write-Host $s -ForegroundColor $color
    $script:lines += $s
}

function Run([string]$exe, [string[]]$argv) {
    if (-not (Test-Path $exe)) { return "  (ไม่พบ $exe)" }
    $out = (& cmd /c "`"$exe`" $($argv -join ' ') 2>&1" | Out-String)
    return (($out -split "`r?`n") | Where-Object { $_.Trim() } | ForEach-Object { "  $_" }) -join "`n"
}

$adb      = Join-Path $Tools 'adb.exe'
$fastboot = Join-Path $Tools 'fastboot.exe'

Say "=== verify @ $stamp ===" Cyan
Say "adb=$adb"
Say "fastboot=$fastboot"

# ---- ตรวจโหมด ------------------------------------------------------------
$fbDevs = (& cmd /c "`"$fastboot`" devices 2>&1" | Out-String).Trim()
$adRaw  = ((& cmd /c "`"$adb`" devices 2>&1" | Out-String) -split "`r?`n" | Where-Object { $_ -match '\t\S+$' }) -join ','
$adDevs = ((& cmd /c "`"$adb`" devices 2>&1" | Out-String) -split "`r?`n" | Where-Object { $_ -match '\sdevice$' }) -join ','
$adUnauth = ($adRaw -match 'unauthorized')

$mode = 'none'
if ($fbDevs)      { $mode = 'fastboot' }
elseif ($adDevs)  { $mode = 'adb' }
elseif ($adUnauth) { $mode = 'unauthorized' }

Say "`n=== mode ===" Cyan
Say "  fastboot: $(if($fbDevs){$fbDevs}else{'(ว่าง)'})"
Say "  adb     : $(if($adRaw){$adRaw}else{'(ว่าง)'})"
Say "  => $mode"

if ($mode -eq 'unauthorized') {
    Say "`n[!] เห็นเครื่องแล้ว แต่ยังไม่ authorize (adb ขึ้น unauthorized)" Yellow
    Say "    - ปลดล็อกจอ แล้วกด Allow ใน popup 'อนุญาตการดีบัก USB'" Yellow
    Say "    - ถ้าไม่มี popup: ปิด/เปิด USB debugging แล้วเสียบสายใหม่" Yellow
    Say "    - หรือสั่ง: `"$adb`" kill-server; `"$adb`" start-server" Yellow
    $script:lines | Set-Content $log -Encoding UTF8
    Write-Host "`nบันทึกไว้: $log" -ForegroundColor Green
    exit 5
}

if ($mode -eq 'none') {
    Say "`n[!] ไม่พบเครื่องทั้งสองโหมด" Yellow
    Say "    - ถ้าเครื่องอยู่หน้า FASTBOOT แต่ adb ไม่เห็น = ปกติ (adb ใช้ไม่ได้ใน fastboot)" Yellow
    Say "    - เสียบสาย USB ที่เป็น data, ปลดล็อกจอ, กด Allow ใน popup RSA" Yellow
    $script:lines | Set-Content $log -Encoding UTF8
    Write-Host "`nบันทึกไว้: $log" -ForegroundColor Green
    exit 3
}

if ($mode -eq 'fastboot') {
    Say "`n=== fastboot getvar ===" Cyan
    $all = Run $fastboot @('getvar','all')
    Say $all
    $prod = (($all -split "`n") | Where-Object { $_ -match 'product:\s*(\S+)' } | ForEach-Object { ($_ -split 'product:\s*')[1].Trim() })
    $unl  = (($all -split "`n") | Where-Object { $_ -match 'unlocked:\s*(\S+)' } | ForEach-Object { ($_ -split 'unlocked:\s*')[1].Trim() })
    Say "`n=== สรุป ===" Cyan
    Say "  product  : $prod"
    Say "  unlocked : $unl"
    if ($prod -ne 'sunny') {
        Say "  ✗ ไม่ใช่ sunny (ได้ '$prod') — หยุดตรงนี้ ห้ามแฟลช" Red
        $script:lines | Set-Content $log -Encoding UTF8; exit 4
    }
    Say "  ✓ ยืนยัน sunny" Green
    Say "`n  หมายเหตุ: adb ใช้ไม่ได้ตอนอยู่ใน fastboot — ถ้าต้องสั่ง adb ให้ทำ:" Yellow
    Say "     `"$fastboot`" reboot    # กลับเข้า Android แล้วค่อยใช้ adb" Yellow
}

if ($mode -eq 'adb') {
    Say "`n=== adb props ===" Cyan
    $props = @('ro.product.device','ro.product.model','ro.product.name','ro.build.version.release',
               'ro.build.version.incremental','ro.miui.ui.version.name','ro.boot.hardware','ro.boot.slot_suffix',
               'ro.boot.verifiedbootstate','ro.boot.flash.locked','ro.serialno')
    $vals = @{}
    foreach ($p in $props) {
        $v = (& cmd /c "`"$adb`" shell getprop $p 2>&1" | Out-String).Trim()
        $vals[$p] = $v
        Say ("  {0,-32} = {1}" -f $p, $v)
    }
    Say "`n=== สรุป ===" Cyan
    Say "  device   : $($vals['ro.product.device'])"
    Say "  slot     : $($vals['ro.boot.slot_suffix'])"
    Say "  locked   : $($vals['ro.boot.flash.locked'])"
    if ($vals['ro.product.device'] -ne 'sunny') {
        Say "  ✗ ไม่ใช่ sunny — ห้ามแฟลช" Red
        $script:lines | Set-Content $log -Encoding UTF8; exit 4
    }
    Say "  ✓ ยืนยัน sunny" Green
    Say "`n  เก็บ ROM version ไว้จับคู่ fastboot ROM ที่จะสำรอง:" Yellow
    Say "     $($vals['ro.build.version.incremental'])" Yellow
}

$script:lines | Set-Content $log -Encoding UTF8
Write-Host "`nบันทึกไว้: $log" -ForegroundColor Green
exit 0
