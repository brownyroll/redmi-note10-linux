param([int]$Minutes = 12, [string]$Out = "C:\Users\brown\Documents\Default Project\sunny-linux\out\phone-watch.log")
$ErrorActionPreference = 'Continue'
$seen = @{}
$deadline = (Get-Date).AddMinutes($Minutes)
function Log([string]$s) {
    $ts = (Get-Date).ToString("HH:mm:ss")
    Add-Content -Path $Out -Value "[$ts] $s" -Encoding UTF8
    Write-Host "[$ts] $s"
}
Log "--- watch start ---"
while ((Get-Date) -lt $deadline) {
    $names = @("current.log")
    try {
        $r = Invoke-WebRequest -Uri "http://192.168.42.2/current.log" -UseBasicParsing -TimeoutSec 4
        $c = $r.Content
        $key = "$($c.Length)"
        $stamp = (Get-Date).ToString("HHmmss")
        $snap = "C:\Users\brown\Documents\Default Project\sunny-linux\out\current-$stamp.log"
        [IO.File]::WriteAllText($snap, $c, (New-Object Text.UTF8Encoding $false))
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $lines = $c -split "`r?`n"
            $head = ($lines | Select-Object -First 3) -join " | "
            $tail = ($lines | Select-Object -Last 3) -join " | "
            Log "current.log $($c.Length) chars :: HEAD: $head :: TAIL: $tail :: saved $snap"
        }
    } catch { }
    # also try stage logs
    foreach ($n in 0..5) {
        $u = "http://192.168.42.2/stage$n.log"
        try {
            $r2 = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 3
            if ($r2.Content.Length -gt 0) {
                $k2 = "s$n-$($r2.Content.Length)"
                if (-not $seen.ContainsKey($k2)) {
                    $seen[$k2] = $true
                    [IO.File]::WriteAllText("C:\Users\brown\Documents\Default Project\sunny-linux\out\stage$n.log", $r2.Content, (New-Object Text.UTF8Encoding $false))
                    Log "GOT stage$n.log ($($r2.Content.Length) chars)"
                }
            }
        } catch { }
    }
    Start-Sleep -Seconds 2
}
Log "--- watch end ---"
