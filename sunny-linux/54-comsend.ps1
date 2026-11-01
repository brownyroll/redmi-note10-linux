<#
  54-comsend.ps1 - write raw bytes (hex) to the COM port, then capture output
  .\54-comsend.ps1 -Hex "1d" -Wait 4
#>
param([string]$Hex = "0d", [int]$Wait = 4, [string]$Device = "COM10")
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$alive = Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -eq $Device }
if (-not $alive) { Write-Host "[send] no $Device"; exit 2 }
$bytes = [byte[]]($Hex -split '\s+' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) })
$p = New-Object System.IO.Ports.SerialPort($Device, 115200, 'None', 8, 'One')
$p.ReadTimeout = 200; $p.DtrEnable = $true; $p.RtsEnable = $true
try { $p.Open() } catch { Write-Host ("[send] open fail: " + $_.Exception.Message); exit 3 }
Start-Sleep -Milliseconds 300
$null = $p.ReadExisting()
$p.Write($bytes, 0, $bytes.Length)
$end = (Get-Date).AddSeconds($Wait)
$sb = New-Object System.Text.StringBuilder
while ((Get-Date) -lt $end) {
  try { $t = $p.ReadExisting(); if ($t) { $null = $sb.Append($t) } } catch {}
  Start-Sleep -Milliseconds 100
}
try { $p.Close() } catch {}
Write-Host ("[send] " + $Hex)
Write-Host "--------------------------------------------------"
Write-Host ($sb.ToString() -replace "`e\[[0-9;]*[A-Za-z]", "")
