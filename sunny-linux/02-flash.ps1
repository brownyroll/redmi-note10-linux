<#
  02-flash.ps1 — แฟลช boot/vendor_boot/rootfs ขึ้นเครื่อง sunny จากฝั่ง Windows
  (WSL มองไม่เห็น USB จึงต้องสั่ง fastboot จาก PowerShell)

  .\02-flash.ps1 -Mode boot          # เขียน boot + vendor_boot
  .\02-flash.ps1 -Mode userdata      # เขียน rootfs.simg ลง userdata (sparse, ไม่ต้อง TWRP)
  .\02-flash.ps1 -Mode stock         # คืน boot/vendor_boot เดิมจาก logs\backup_*

  ต้องมี: out\boot.img, out\vendor_boot.img, out\rootfs.simg
#>
param(
    [ValidateSet('boot','userdata','stock','check')]
    [string]$Mode = 'check',
    [string]$Tools = "C:\Users\brown\Desktop\Google\Android\platform-tools",
    [int]$ChunkMB = 400
)
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8; $OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = 'Stop'

$Out  = Join-Path $PSScriptRoot 'out'
$Logs = Join-Path $PSScriptRoot 'logs'
$fb   = Join-Path $Tools 'fastboot.exe'

function Fb([string[]]$argv) {
    Write-Host ("  fastboot " + ($argv -join ' ')) -ForegroundColor DarkGray
    & $fb @argv 2>&1 | ForEach-Object { Write-Host "    $_" }
    return $LASTEXITCODE
}
function Need([string]$path, [string]$what) {
    if (-not (Test-Path $path)) { throw "ไม่พบ $what : $path" }
    return (Get-Item $path).Length
}
function Confirm([string]$msg) {
    Write-Host ""
    Write-Host "⚠️  $msg" -ForegroundColor Yellow
    $a = Read-Host "พิมพ์ yes เพื่อไปต่อ"
    if ($a -ne 'yes') { Write-Host "ยกเลิก" -ForegroundColor Red; exit 1 }
}

if (-not (Test-Path $fb)) { throw "ไม่พบ fastboot: $fb (ใช้ -Tools ชี้ไปที่ platform-tools)" }

# ---- ตรวจเครื่อง ---------------------------------------------------------
$devs = (& $fb devices 2>&1 | Out-String).Trim()
Write-Host "=== fastboot devices ===" -ForegroundColor Cyan
Write-Host ($(if ($devs) { $devs } else { '  (ว่าง)' }))

if ($Mode -eq 'check') {
    Write-Host "`nโหมด check เท่านั้น — ไม่ได้เขียนอะไร" -ForegroundColor Green
    Write-Host "ไฟล์ที่มี:"
    Get-ChildItem $Out -File -ErrorAction SilentlyContinue |
        Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,1)}} | Format-Table | Out-String | Write-Host
    exit 0
}
if (-not $devs) {
    Write-Host "ไม่พบเครื่องใน fastboot" -ForegroundColor Red
    Write-Host "  - ถ้าอยู่ใน Android: adb reboot bootloader" -ForegroundColor Yellow
    Write-Host "  - adb ใช้ไม่ได้ตอนอยู่ใน fastboot (ปกติ)" -ForegroundColor Yellow
    exit 2
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$log = Join-Path $Logs "flash_$stamp.txt"
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
Start-Transcript -Path $log -Force | Out-Null

try {
    switch ($Mode) {

    'boot' {
        $b = Need (Join-Path $Out 'boot.img') 'boot.img'
        $v = Need (Join-Path $Out 'vendor_boot.img') 'vendor_boot.img'
        Write-Host ("boot.img {0:N0} B / vendor_boot.img {1:N0} B" -f $b, $v) -ForegroundColor Gray
        Confirm "จะเขียน boot + vendor_boot ทับของเดิม (สำรองไว้แล้วใช่ไหม?)"
        Fb @('flash','boot', (Join-Path $Out 'boot.img')) | Out-Null
        Fb @('flash','vendor_boot', (Join-Path $Out 'vendor_boot.img')) | Out-Null
        Write-Host "`n=> ไม่แตะ vbmeta/dtbo (bootloader ปลดล็อกอยู่แล้ว)" -ForegroundColor Green
        Fb @('reboot') | Out-Null
    }

    'userdata' {
        $img = Join-Path $Out 'rootfs.simg'
        if (-not (Test-Path $img)) { throw "ไม่พบ $img — สร้างด้วย: img2simg rootfs.img rootfs.simg (ใน WSL)" }
        $sz = (Get-Item $img).Length
        Write-Host ("rootfs.simg {0:N0} B ({1:N1} MB)" -f $sz, ($sz/1MB)) -ForegroundColor Gray
        Confirm "userdata ทั้งหมดจะถูกเขียนทับ (รูป/ข้อมูลหายหมด) และใช้เวลา ~10-20 นาที"
        $rc = Fb @('flash', "-S$($ChunkMB)M", 'userdata', $img)
        if ($rc -ne 0) { throw "fastboot flash userdata ล้มเหลว (exit $rc)" }
        Write-Host "`n=> แฟลชเสร็จ — ไฟล์ระบบ 6 GB จะขยายเต็มพาร์ทิชันเองตอนบูตครั้งแรก" -ForegroundColor Green
        Write-Host "   (ถ้าไม่ขยาย: บูตแล้วสั่ง resize2fs /dev/block/by-name/userdata)" -ForegroundColor Gray
        Fb @('reboot') | Out-Null
    }

    'stock' {
        $b = Get-ChildItem (Join-Path $Logs 'backup_*\boot_a.img') -ErrorAction SilentlyContinue | Select-Object -First 1
        $v = Get-ChildItem (Join-Path $Logs 'backup_*\vendor_boot_a.img') -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $b) { throw "ไม่พบ boot_a.img ที่สำรองไว้ใน logs\backup_*" }
        Confirm "จะเขียน boot กลับเป็นของเดิม: $($b.FullName)"
        Fb @('flash','boot', $b.FullName) | Out-Null
        if ($v) { Fb @('flash','vendor_boot', $v.FullName) | Out-Null }
        Fb @('reboot') | Out-Null
    }
    }
}
finally {
    Stop-Transcript | Out-Null
    Write-Host "`nบันทึกไว้: $log" -ForegroundColor Green
}
