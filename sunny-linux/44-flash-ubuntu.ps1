<#
  44-flash-ubuntu.ps1 — แฟลช Ubuntu rootfs + initramfs (vendor_boot) และ RAM-boot kernel fbcon
  .\44-flash-ubuntu.ps1                 # แฟลช userdata + vendor_boot แล้ว reboot ด้วย kernel เดิม (YAAP)
  .\44-flash-ubuntu.ps1 -RamBootFbcon   # แฟลช แล้ว RAM-boot kernel ที่ build เอง (มี fbcon/จอ)
  .\44-flash-ubuntu.ps1 -NoUserdata     # ข้ามการแฟลช userdata (rootfs ไม่เปลี่ยน)
#>
param(
  [switch]$RamBootFbcon,
  [switch]$NoUserdata
)
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$t   = "C:\Users\brown\Desktop\Google\Android\platform-tools"
$dir = "C:\Users\brown\Documents\Default Project\sunny-linux"
Set-Location $dir

# adb ที่ค้างอยู่จะยึด USB จน fastboot เขียนไม่ได้ (semaphore timeout)
Get-Process adb,fastboot -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$dev = (& "$t\fastboot.exe" devices 2>&1 | Out-String).Trim()
Write-Host "fastboot devices -> $dev"
if ($dev -notmatch 'fastboot') {
  Write-Host "!! ไม่พบเครื่องในโหมด fastboot — กด Vol Down + Power ค้าง ~10 วิ"
  exit 1
}

if (-not $NoUserdata) {
  Write-Host "==> flash userdata (rootfs Ubuntu, sparse)"
  & "$t\fastboot.exe" flash userdata out\rootfs.simg
}

Write-Host "==> flash vendor_boot (initramfs จริง: หา /dev/sda17 + sunny-init)"
& "$t\fastboot.exe" flash vendor_boot out\vendor_boot.img

if ($RamBootFbcon) {
  Write-Host "==> RAM-boot kernel ที่ build เอง (fbcon) — boot partition ยังเป็น YAAP"
  & "$t\fastboot.exe" boot out\boot.img
} else {
  Write-Host "==> reboot ด้วย kernel เดิมใน boot partition"
  & "$t\fastboot.exe" reboot
}
