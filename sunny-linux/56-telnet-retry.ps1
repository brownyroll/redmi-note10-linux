param(
    [string]$Cmd = "echo M1; cat /proc/uptime; echo M2; ps; echo M3; ls /tmp/www; echo M4; dmesg | tail -n 10; echo M5",
    [int]$WaitSec = 10,
    [int]$TrySec = 150,
    [string]$HostIp = "192.168.42.2",
    [int]$Port = 23
)
$ErrorActionPreference = 'Continue'
$deadline = (Get-Date).AddSeconds($TrySec)
$ok = $false
while ((Get-Date) -lt $deadline) {
    try {
        $c = New-Object Net.Sockets.TcpClient
        $r = $c.ConnectAsync($HostIp, $Port)
        if ($r.Wait(2000) -and $c.Connected) {
            $ns = $c.GetStream()
            Start-Sleep -Milliseconds 600
            while ($ns.DataAvailable) { $b = New-Object byte[] 4096; [void]$ns.Read($b, 0, $b.Length) }
            $bytes = [Text.Encoding]::ASCII.GetBytes($Cmd + "`n")
            $ns.Write($bytes, 0, $bytes.Length)
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $buf = New-Object System.Text.StringBuilder
            while ($sw.Elapsed.TotalSeconds -lt $WaitSec) {
                while ($ns.DataAvailable) {
                    $b = New-Object byte[] 8192
                    $n = $ns.Read($b, 0, $b.Length)
                    [void]$buf.Append([Text.Encoding]::UTF8.GetString($b, 0, $n))
                }
                Start-Sleep -Milliseconds 120
            }
            $c.Close()
            Write-Host "[telnet] CONNECTED at $((Get-Date).ToString('HH:mm:ss'))"
            Write-Host $buf.ToString()
            $ok = $true
            break
        }
        $c.Close()
    } catch { }
    Start-Sleep -Milliseconds 1500
}
if (-not $ok) { Write-Host "[telnet] never connected in $TrySec s" }
