<#
  03-comcmd.ps1 — เปิด COM, พิมพ์คำสั่งหนึ่งบรรทัด แล้วอ่านกลับเป็นเวลา N วินาที
  .\03-comcmd.ps1 -Cmd "ip addr" -Wait 8
  (shell บน ttyGS0 ฝั่งเครื่องยังมีชีวิต — port ปิด/เปิดใหม่ไม่กระทบ session)
#>
param(
  [Parameter(Mandatory=$true)][string]$Cmd,
  [int]$Wait = 8,
  [string]$Device = "COM10",
  [switch]$CtrlC
)
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try {
  $p = New-Object System.IO.Ports.SerialPort($Device, 115200, 'None', 8, 'One')
  $p.ReadTimeout = 300; $p.DtrEnable = $true; $p.RtsEnable = $true
  $p.NewLine = "`n"
  $p.Open()
  # เคลียร์ของเก่าที่ค้างอยู่ใน buffer
  Start-Sleep -Milliseconds 300
  [void]$p.ReadExisting()
  if ($CtrlC) { $p.Write([char]3); Start-Sleep -Milliseconds 300; [void]$p.ReadExisting() }
  $p.WriteLine($Cmd)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $buf = New-Object System.Text.StringBuilder
  while ($sw.Elapsed.TotalSeconds -lt $Wait) {
    try { $t = $p.ReadExisting(); if ($t) { [void]$buf.Append($t) } }
    catch {}
    Start-Sleep -Milliseconds 200
  }
  Write-Host ("=== cmd: {0} ===" -f $Cmd)
  Write-Host $buf.ToString()
  $p.Close()
} catch {
  Write-Host ("comcmd fail: " + $_.Exception.Message)
}
