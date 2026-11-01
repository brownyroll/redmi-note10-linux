<#
  03-comlog.ps1 — ต่อ serial COM (ttyGS0/ACM) และเซฟ console log ไฟล์
  .\03-comlog.ps1 -Port COM10 -Timeout 180 -OutFile.\console.log
#>
param([string]$Port = "COM10", [int]$Timeout = 180, [string]$OutFile = ".\console.log")
$ErrorActionPreference = 'Continue'
try { $p = New-Object System.IO.Ports.SerialPort($Port, 115200, 'None', 8, 'One'); $p.ReadTimeout = 500; $p.DtrEnable = $true; $p.RtsEnable = $true; $p.Open() } catch {
  Write-Host "เปิด $Port ไม่ได้: $($_.Exception.Message)"; exit 1
}
Write-Host "บันทึกจาก $Port → $OutFile (สูงสุด $Timeout วิ) — Ctrl+C เพื่อหยุด"
$sw = [Diagnostics.Stopwatch]::StartNew()
$buf = New-Object System.Text.StringBuilder
while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
  try { $line = $p.ReadExisting(); if ($line) { [void]$buf.Append($line); Write-Host -NoNewline $line } } catch {}
  Start-Sleep -Milliseconds 200
}
$p.Close()
[IO.File]::WriteAllText((Join-Path (Get-Location) $OutFile), $buf.ToString(), [Text.Encoding]::UTF8)
Write-Host "`nบันทึกแล้ว → ((Resolve-Path $OutFile))"
