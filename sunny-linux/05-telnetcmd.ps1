<#
  05-telnetcmd.ps1 — telnet 192.168.42.2:23 ส่งคำสั่งแล้วอ่านกลับ
  .\05-telnetcmd.ps1 -Cmd "ls" -Wait 8
#>
param([string]$Cmd, [int]$Wait = 8, [string]$Host_ip = "192.168.42.2", [int]$Port = 23)
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try {
  $c = New-Object Net.Sockets.TcpClient
  $c.Connect($Host_ip, $Port)
  $ns = $c.GetStream()
  Start-Sleep -Milliseconds 500
  while ($ns.DataAvailable) { $b = New-Object byte[] 4096; [void]$ns.Read($b,0,$b.Length) }
  $bytes = [Text.Encoding]::ASCII.GetBytes($Cmd + "`n")
  $ns.Write($bytes, 0, $bytes.Length)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $buf = New-Object System.Text.StringBuilder
  while ($sw.Elapsed.TotalSeconds -lt $Wait) {
    while ($ns.DataAvailable) {
      $b = New-Object byte[] 8192
      $n = $ns.Read($b, 0, $b.Length)
      [void]$buf.Append([Text.Encoding]::UTF8.GetString($b, 0, $n))
    }
    Start-Sleep -Milliseconds 150
  }
  $c.Close()
  Write-Host ($buf.ToString())
} catch {
  Write-Host ("telnet fail: " + $_.Exception.Message)
}
