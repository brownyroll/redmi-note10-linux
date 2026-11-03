<#
  03-usb-net.ps1 — ตรวจว่าเครื่องบูตแล้วโผล่ผ่าน USB ไหม (RNDIS usb0 + ssh)

  .\03-usb-net.ps1            # รอสูงสุด 3 นาที
  .\03-usb-net.ps1 -Timeout 600

  ค่าตั้งต้น: หน้านาฬิกาตั้ง 192.168.42.1/24 บน adapter ที่โผล่ (script ทำให้เอง)
#>
param(
    [string]$Tools = "C:\Users\brown\Desktop\Google\Android\platform-tools",
    [int]$Timeout = 180,
    [string]$HostIP = '192.168.42.1',
    [string]$PhoneIP = '192.168.42.2'
)
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8; $OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = 'Continue'

$sw = [Diagnostics.Stopwatch]::StartNew()
$adapter = $null
Write-Host "=== รอ adapter USB (RNDIS) สูงสุด $Timeout วิ ===" -ForegroundColor Cyan

while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
    # Apple Mobile / Пctd ฯลฯ ไม่เกี่ยว — หา adapter ที่เป็น USB และห้าม Duplicate
    $a = Get-NetAdapter -ErrorAction SilentlyContinue |
         Where-Object { $_.InterfaceDescription -match 'Remote\s*NDIS|RNDIS|USB Ethernet|USB Ethernet/RNDIS' }
    if ($a) { $adapter = $a | Select-Object -First 1; break }
    Start-Sleep -Seconds 2
}

if (-not $adapter) {
    $fb = Join-Path $Tools 'fastboot.exe'
    $ad = Join-Path $Tools 'adb.exe'
    $mode = 'ไม่เห็นอะไรเลย'
    $fbOut = (& $fb devices 2>&1 | Out-String).Trim()
    if ($fbOut) { $mode = "อยู่ใน fastboot: $fbOut" }
    else { $adOut = (& $ad devices 2>&1 | Out-String).Trim(); if ($adOut -match 'List of devices attached\s*$') {} elseif ($adOut) { $mode = "adb: $adOut" } }
    Write-Host "`n[!] ไม่พบ RNDIS adapter ภายใน $Timeout วิ ($mode)" -ForegroundColor Red
    Write-Host "  ตรวจ Device Manager: ควรมีอุปกรณ์ใหม่ปรากฏ (อาจเป็น Unknown device)" -ForegroundColor Yellow
    Write-Host "  ถ้าพัง: กด Vol Down + Power ค้าง 10 วิ → fastboot → fastboot --set-active=b" -ForegroundColor Yellow
    exit 2
}

Write-Host "`n=== เจอ adapter ===" -ForegroundColor Green
$adapter | Format-List Name, InterfaceDescription, Status | Out-String | Write-Host

if ($adapter.Status -ne 'Up') {
    Write-Host "ตั้ง IP $HostIP/24 บน $($adapter.Name)..." -ForegroundColor Gray
    New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $HostIP -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    Enable-NetAdapter $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 3
} else {
    $ip = (Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
           Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress
    Write-Host "IP ปัจจุบัน: $ip" -ForegroundColor Gray
    if ($ip -ne $HostIP) {
        New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $HostIP -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    }
}

Write-Host "`n=== ping $PhoneIP ===" -ForegroundColor Cyan
$ok = $false
for ($i = 0; $i -lt 20; $i++) {
    if (Test-Connection -ComputerName $PhoneIP -Count 1 -Quiet -ErrorAction SilentlyContinue) { $ok = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ok) { Write-Host "[!] ping ไม่ได้ — แต่ adapter ขึ้นแล้ว (gadget ทำงาน, ssh อาจยังไม่ขึ้น)" -ForegroundColor Yellow; exit 3 }
Write-Host "✓ ping ผ่าน" -ForegroundColor Green

Write-Host "`n=== ssh dev@$PhoneIP ===" -ForegroundColor Cyan
Write-Host "รหัสผ่าน: ubuntu1234" -ForegroundColor Gray
& (Join-Path $Tools 'ssh.exe') -o StrictHostKeyChecking=no -o ConnectTimeout=5 "dev@$PhoneIP" 'uname -a; uptime' 2>&1 | ForEach-Object { $_ }
exit 0
