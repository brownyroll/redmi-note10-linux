<#
  53-upload.ps1 - push a base64 text file to the phone over the COM gadget console
  .\53-upload.ps1 -B64 out\sunnyfb.b64 -Remote /tmp/sf.b64 -Decode /tmp/sunnyfb
#>
param(
  [Parameter(Mandatory=$true)][string]$B64,
  [string]$Remote = "/tmp/sf.b64",
  [string]$Decode = "",
  [string]$Device = "COM10",
  [int]$ChunkBytes = 256,
  [int]$ChunkDelayMs = 18
)
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$alive = Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -eq $Device }
if (-not $alive) { Write-Host "[up] no $Device"; exit 2 }

$data = Get-Content -LiteralPath $B64 -Raw
$data = ($data -replace "`r", "")
if (-not $data.EndsWith("`n")) { $data += "`n" }

$p = New-Object System.IO.Ports.SerialPort($Device, 115200, 'None', 8, 'One')
$p.ReadTimeout = 200; $p.WriteTimeout = 3000; $p.DtrEnable = $true; $p.RtsEnable = $true
try { $p.Open() } catch { Write-Host ("[up] open fail: " + $_.Exception.Message); exit 3 }
Start-Sleep -Milliseconds 300
$null = $p.ReadExisting()

$tag = "UP" + (Get-Random -Minimum 1000 -Maximum 9999)
$p.WriteLine("")
$p.WriteLine("rm -f $Remote; cat > $Remote << '$tag'")
Start-Sleep -Milliseconds 150
$null = $p.ReadExisting()

$sent = 0
for ($i = 0; $i -lt $data.Length; $i += $ChunkBytes) {
  $n = [Math]::Min($ChunkBytes, $data.Length - $i)
  $p.Write($data.Substring($i, $n))
  $sent += $n
  Start-Sleep -Milliseconds $ChunkDelayMs
}
$p.WriteLine("$tag")
Start-Sleep -Milliseconds 400
Write-Host ("[up] sent {0} bytes base64" -f $sent)

$script = "ls -l $Remote; wc -c $Remote"
if ($Decode) { $script = "$script; base64 -d $Remote > $Decode && chmod +x $Decode; ls -l $Decode; sha256sum $Decode" }
$p.WriteLine($script + "; echo DONE$tag")
$end = (Get-Date).AddSeconds(20)
$sb = New-Object System.Text.StringBuilder
while ((Get-Date) -lt $end) {
  try { $t = $p.ReadExisting(); if ($t) { $null = $sb.Append($t); if ($sb.ToString() -match "DONE$tag") { break } } } catch {}
  Start-Sleep -Milliseconds 100
}
try { $p.Close() } catch {}
$out = $sb.ToString() -replace "`e\[[0-9;]*[A-Za-z]", ""
Write-Host "--------------------------------------------------"
Write-Host $out
$localHash = (Get-FileHash -LiteralPath $B64 -Algorithm SHA256).Hash
Write-Host ("[up] note: compare the sha256 above with the binary's own hash, not this one")
