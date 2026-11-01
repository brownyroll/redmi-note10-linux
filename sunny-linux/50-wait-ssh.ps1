<#
  50-wait-ssh.ps1 - wait until the phone answers on 192.168.42.2 (ping + TCP 22)
  .\50-wait-ssh.ps1 -Timeout 240
#>
param([int]$Timeout = 240, [string]$Target = "192.168.42.2")
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$end = (Get-Date).AddSeconds($Timeout)
$sw = [Diagnostics.Stopwatch]::StartNew()
$pingOK = $false; $sshOK = $false; $telnetOK = $false
while ((Get-Date) -lt $end) {
    $pingOK = Test-Connection -ComputerName $Target -Count 1 -Quiet -ErrorAction SilentlyContinue
    if ($pingOK) {
        foreach ($p in 22, 23) {
            try {
                $c = New-Object Net.Sockets.TcpClient
                $r = $c.ConnectAsync($Target, $p)
                if ($r.Wait(1500) -and $c.Connected) {
                    if ($p -eq 22) { $sshOK = $true } else { $telnetOK = $true }
                    $c.Close()
                }
            } catch {}
        }
    }
    if ($pingOK -and ($sshOK -or $telnetOK)) { break }
    Start-Sleep -Seconds 3
}
"[{0,4}s] ping={1}  tcp22(ssh)={2}  tcp23(telnet)={3}" -f [int]$sw.Elapsed.TotalSeconds, $pingOK, $sshOK, $telnetOK
cmd /c arp -a | Select-String '192.168.42' | Out-String
