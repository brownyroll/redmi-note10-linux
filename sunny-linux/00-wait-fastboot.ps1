<#
  00-wait-fastboot.ps1 — รอเครื่องเข้า fastboot แล้วยืนยันรุ่นให้อัตโนมัติ

  .\00-wait-fastboot.ps1              # รอ 300 วิ
  .\00-wait-fastboot.ps1 -Timeout 600

  ใช้ตอน adb ยัง unauthorized (สั่ง adb reboot bootloader ไม่ได้)
  ระหว่างรอ ให้กดปุ่มบนเครื่อง: Volume Down + Power ค้าง ~10 วิ
#>
param(
    [string]$Tools = "C:\Users\brown\Desktop\Google\Android\platform-tools",
    [int]$Timeout = 300
)
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8; $OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = 'Continue'   # fastboot เขียน progress/คำเตือนลง stderr — ห้ามให้ Stop

$fb = Join-Path $Tools 'fastboot.exe'
$ad = Join-Path $Tools 'adb.exe'
if (-not (Test-Path $fb)) { throw "ไม่พบ fastboot: $fb" }

Write-Host "=== รอเครื่องเข้า fastboot (สูงสุด $Timeout วิ) ===" -ForegroundColor Cyan
Write-Host "  กด Volume Down + Power ค้าง ~10 วิ จนเห็นโลโก้ FASTBOOT" -ForegroundColor Yellow
Write-Host "  (ถ้าจอยังติดล็อก ให้ปลดล็อกก่อน)" -ForegroundColor Yellow

$sw = [Diagnostics.Stopwatch]::StartNew()
$found = $null
while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
    $out = (& $fb devices 2>&1 | Out-String).Trim()
    if ($out) { $found = $out; break }
    Start-Sleep -Seconds 2
}

if (-not $found) {
    $adOut = (& $ad devices 2>&1 | Out-String).Trim()
    Write-Host "`n[!] ยังไม่เห็นเครื่องใน fastboot ภายใน $Timeout วิ" -ForegroundColor Red
    Write-Host "  adb ตอนนี้: $adOut" -ForegroundColor Gray
    if ($adOut -match 'unauthorized') {
        Write-Host "  หมายเหตุ: unauthorized = สั่ง 'adb reboot bootloader' ไม่ได้ ต้องใช้ปุ่มบนเครื่องเท่านั้น" -ForegroundColor Yellow
        Write-Host "  ถ้าอยากให้ adb ใช้ได้: ปลดล็อกจอ → กด Allow ใน popup 'อนุญาตการดีบัก USB'" -ForegroundColor Yellow
    }
    exit 3
}

Write-Host "`n=== เจอแล้ว ===" -ForegroundColor Green
Write-Host $found
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$log = Join-Path (Join-Path $PSScriptRoot 'logs') "fastboot_$stamp.txt"
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null

$all = (& $fb getvar all 2>&1 | Out-String)
$lines = @("=== fastboot @ $stamp ===", $found, "", $all)
$lines | Set-Content $log -Encoding UTF8

$prod = ([regex]::Match($all, 'product:\s*(\S+)')).Groups[1].Value
$unl  = ([regex]::Match($all, 'unlocked:\s*(\S+)')).Groups[1].Value
Write-Host ("  product  : {0}" -f $prod)
Write-Host ("  unlocked : {0}" -f $unl)
Write-Host "  บันทึกไว้: $log" -ForegroundColor Green
if ($prod -ne 'sunny') { Write-Host "  ✗ ไม่ใช่ sunny — ห้ามแฟลช" -ForegroundColor Red; exit 4 }
Write-Host "  ✓ ยืนยัน sunny — พร้อมแฟลช" -ForegroundColor Green
exit 0
