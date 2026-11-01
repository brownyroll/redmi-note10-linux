<#
  03-poll-usb.ps1 — ดักรอ USB ตอนทดสอบบูต (RNDIS / COM / VID_1D6B gadget)

  .\03-poll-usb.ps1 -Timeout 180
#>
param([int]$Timeout = 180)
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8; $OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = 'Continue'

$knownPorts = (Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue).DeviceID
$sw = [Diagnostics.Stopwatch]::StartNew()
$last = ''
while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
    $devs = Get-PnPDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_1D6B|VID_18D1|RNDIS' }
    $ports = Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue |
        Where-Object { $knownPorts -notcontains $_.DeviceID }
    $snap = ($devs | ForEach-Object { $_.InstanceId }) -join ';'
    if ($snap -ne $last) {
        Write-Host ("[{0,4}s] USB: {1}" -f [int]$sw.Elapsed.TotalSeconds, ($(if ($snap) { $snap } else { 'เปลี่ยน (ไม่มีแล้ว)' }))) -ForegroundColor Cyan
        if ($devs) { $devs | Select-Object Status, FriendlyName, InstanceId | Format-Table -AutoSize | Out-String | Write-Host }
        $last = $snap
    }
    if ($ports) { Write-Host ("[{0,4}s] COM ใหม่: {1}" -f [int]$sw.Elapsed.TotalSeconds, (($ports | ForEach-Object { $_.DeviceID }) -join ',')) -ForegroundColor Green }
    Start-Sleep -Seconds 2
}
Write-Host "จบ (ไม่มีการเปลี่ยนแปลงเพิ่มจากนี้)"
