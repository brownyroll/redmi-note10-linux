<#
  01-backup.ps1 — สำรองข้อมูลก่อนเขียนทับเครื่อง sunny

  โหมด:
    .\01-backup.ps1 -Mode getvar                 # บันทึกสถานะเครื่อง (ทำได้ทุกเมื่อ)
    .\01-backup.ps1 -Mode partitions -Twrp twrp-sunny.img   # dump modem/persist/boot ผ่าน TWRP ชั่วคราว
    .\01-backup.ps1 -Mode firmware -RomUrl "https://.../sunny_global_images_V13....tgz"

  ปลายทาง: .\logs\backup_<timestamp>\

  ⚠️  -Mode partitions จะบูต TWRP (ไม่แฟลช ไม่เขียนพาร์ทิชัน) แล้ว dump อ่านอย่างเดียว
      รากฐานสำคัญ: modem / modemst1 / modemst2 / fsg / fsc / persist  ← หายแล้วจบ
#>
param(
    [ValidateSet('getvar','partitions','firmware')]
    [string]$Mode = 'getvar',
    [string]$Tools = "C:\Users\brown\Desktop\Google\Android\platform-tools",
    [string]$Twrp,
    [string]$RomUrl
)

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = 'Stop'
$stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$dest    = Join-Path $PSScriptRoot "logs\backup_$stamp"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$adb      = Join-Path $Tools 'adb.exe'
$fastboot = Join-Path $Tools 'fastboot.exe'

function Cmd([string]$exe, [string[]]$argv) {
    (& cmd /c "`"$exe`" $($argv -join ' ') 2>&1" | Out-String).Trim()
}

function FbDevices { (Cmd $fastboot @('devices')) }
function AdbDevices {
    ((Cmd $adb @('devices')) -split "`r?`n" | Where-Object { $_ -match '\sdevice$' }) -join ','
}

Write-Host "==> ปลายทาง: $dest" -ForegroundColor Cyan

# ---------------------------------------------------------------- getvar
Write-Host "`n[1/3] getvar all" -ForegroundColor Cyan
if (-not (FbDevices)) {
    Write-Host "  เครื่องไม่ได้อยู่ใน fastboot — ข้าม (รันใหม่ตอนอยู่ fastboot)" -ForegroundColor Yellow
} else {
    $all = Cmd $fastboot @('getvar','all')
    $all | Set-Content (Join-Path $dest 'getvar-all.txt') -Encoding UTF8
    if ($all -notmatch 'product:\s*sunny') {
        Write-Host "  ✗ product ไม่ใช่ sunny — หยุด" -ForegroundColor Red; exit 4
    }
    Write-Host "  ✓ sunny — บันทึก getvar-all.txt แล้ว" -ForegroundColor Green
}

# ---------------------------------------------------------------- partitions
$parts = @('modem','modemst1','modemst2','fsg','fsc','persist','metadata','misc','devinfo',
           'boot_a','vendor_boot_a','dtbo_a','vbmeta_a','vbmeta_system_a','abl_a','xbl_a')
$sizes = @{ modem='256M'; modemst1='2M'; modemst2='2M'; fsg='2M'; fsc='128K'; persist='32M';
            metadata='16M'; misc='1M'; devinfo='4K'; boot_a='128M'; vendor_boot_a='96M';
            dtbo_a='24M'; vbmeta_a='64K'; vbmeta_system_a='64K'; abl_a='8M'; xbl_a='7M' }

if ($Mode -eq 'partitions') {
    Write-Host "`n[2/3] dump พาร์ทิชันผ่าน TWRP" -ForegroundColor Cyan
    if (-not $Twrp -or -not (Test-Path $Twrp)) { throw "ต้องระบุ -Twrp path ของ TWRP สำหรับ sunny" }
    if (-not (FbDevices)) { throw "ต้องอยู่ใน fastboot ก่อน (adb ใช้ไม่ได้ในโหมดนี้)" }

    Write-Host "  บูต TWRP ชั่วคราว (ไม่แฟลช): $Twrp" -ForegroundColor Yellow
    Cmd $fastboot @('boot', $Twrp) | Out-Null
    Write-Host "  รอ adb ใน TWRP..." -ForegroundColor Yellow
    $ok = $false
    for ($i=0; $i -lt 40; $i++) {
        Start-Sleep -Seconds 3
        if ((Cmd $adb @('shell','echo ok')) -match 'ok') { $ok = $true; break }
    }
    if (-not $ok) { throw "TWRP ไม่ขึ้น adb — ตรวจ TWRP ให้ตรงรุ่น sunny" }

    Cmd $adb @('shell','mkdir -p /sdcard/sunny-backup') | Out-Null
    foreach ($p in $parts) {
        Write-Host "  dd $p ($($sizes[$p]))" -NoNewline
        $r = Cmd $adb @('shell', "dd if=/dev/block/by-name/$p of=/sdcard/sunny-backup/$p.img bs=1M 2>&1")
        if ($r -match 'No such file|error') { Write-Host "  ✗ $r" -ForegroundColor Red }
        else { Write-Host "  ok" -ForegroundColor Green }
    }
    Write-Host "  adb pull → $dest" -ForegroundColor Cyan
    Cmd $adb @('pull','/sdcard/sunny-backup', $dest) | Out-Null

    Write-Host "  ตรวจ md5 ที่ดึงมา" -ForegroundColor Cyan
    $report = @()
    Get-ChildItem $dest -Filter *.img | ForEach-Object {
        $local = (Get-FileHash $_.FullName -Algorithm MD5).Hash.ToLower()
        $remote = (Cmd $adb @('shell', "md5sum /sdcard/sunny-backup/$($_.Name)") -split '\s+')[0]
        $match = if ($remote -eq $local) { 'OK' } else { 'MISMATCH' }
        $report += "{0,-18} {1,12} {2}" -f $_.Name, $_.Length, $match
        if ($match -ne 'OK') { Write-Host "  ✗ $($_.Name) md5 ไม่ตรง" -ForegroundColor Red }
    }
    $report | Set-Content (Join-Path $dest 'md5-report.txt') -Encoding UTF8
    $report | ForEach-Object { Write-Host "    $_" }

    Write-Host "`n  TWRP ยังทำงานอยู่ — ทางเลือก:" -ForegroundColor Yellow
    Write-Host "    reboot เข้า Android : $adb reboot" -ForegroundColor Yellow
    Write-Host "    กลับ fastboot       : $adb reboot bootloader" -ForegroundColor Yellow
}

# ---------------------------------------------------------------- firmware
if ($Mode -eq 'firmware') {
    Write-Host "`n[2/3] ดาวน์โหลด fastboot ROM (full stock)" -ForegroundColor Cyan
    if (-not $RomUrl) {
        Write-Host "  ต้องระบุ -RomUrl" -ForegroundColor Yellow
        Write-Host "  หา ROM ให้ตรง build ปัจจุบันได้ที่:" -ForegroundColor Yellow
        Write-Host "    https://xiaomifirmwareupdater.com/miui/sunny/" -ForegroundColor Yellow
        Write-Host "  (เลือก Fastboot → Recovery? ต้องเอา Fastboot/ TGZ สำหรับสำรอง firmware)" -ForegroundColor Yellow
    } else {
        $file = Join-Path $dest (Split-Path $RomUrl -Leaf)
        Write-Host "  → $file" -ForegroundColor Cyan
        curl.exe -L --retry 3 --progress-bar -o $file $RomUrl
        if ($LASTEXITCODE -ne 0) { throw "ดาวน์โหลดล้มเหลว" }
        Get-FileHash $file -Algorithm SHA256 | Select-Object Hash, Path |
            Format-List | Out-String | Set-Content (Join-Path $dest 'rom-sha256.txt') -Encoding UTF8
        Write-Host "  ✓ เสร็จ ($([math]::Round((Get-Item $file).Length/1GB,2)) GB)" -ForegroundColor Green
    }
}

Write-Host "`n[3/3] สรุป" -ForegroundColor Cyan
Get-ChildItem $dest -Recurse -File | Select-Object Name, Length |
    Format-Table -AutoSize | Out-String | Write-Host
Write-Host "บันทึกไว้ที่: $dest" -ForegroundColor Green
