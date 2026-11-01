<#
  52-comdo.ps1 - send a command to the phone shell over COM gadget and capture output
  .\52-comdo.ps1 -Cmd "uname -a" -Wait 6
#>
param([string]$Cmd = "echo hello", [int]$Wait = 6, [string]$Device = "COM10", [switch]$Raw, [string]$File)
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if ($File) { $Cmd = (@(Get-Content -LiteralPath $File -Encoding UTF8) -join "`n") }
$alive = Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -eq $Device }
if (-not $alive) { Write-Host "[comdo] no $Device"; exit 2 }
$p = New-Object System.IO.Ports.SerialPort($Device, 115200, 'None', 8, 'One')
$p.ReadTimeout = 300; $p.DtrEnable = $true; $p.RtsEnable = $true
try { $p.Open() } catch { Write-Host ("[comdo] open fail: " + $_.Exception.Message); exit 3 }
Start-Sleep -Milliseconds 400
$null = $p.ReadExisting()
$mark = "END" + (Get-Random -Minimum 100 -Maximum 999)
$p.Write("`n" + $Cmd + "; echo $mark" + "`n")
$end = (Get-Date).AddSeconds($Wait)
$sb = New-Object System.Text.StringBuilder
while ((Get-Date) -lt $end) {
    try {
        $t = $p.ReadExisting()
        if ($t) { $null = $sb.Append($t); if ($sb.ToString() -match $mark) { break } }
    } catch {}
    Start-Sleep -Milliseconds 100
}
try { $p.Close() } catch {}
$out = $sb.ToString()
if (-not $Raw) { $out = $out -replace "`e\[[0-9;]*[A-Za-z]", "" }
Write-Host ("[comdo] " + $Cmd)
Write-Host "--------------------------------------------------"
Write-Host $out
