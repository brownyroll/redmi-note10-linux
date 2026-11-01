param([string]$Name = "current.log", [string]$Out = "")
$ErrorActionPreference = 'Continue'
if (-not $Out) { $Out = "C:\Users\brown\Documents\Default Project\sunny-linux\out\phone-$Name" }
$url = "http://192.168.42.2/$Name"
try {
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 12
    [IO.File]::WriteAllText($Out, $r.Content, (New-Object Text.UTF8Encoding $false))
    Write-Host "[fetch] $url -> $Out ($($r.Content.Length) chars)"
    Write-Host $r.Content
} catch {
    Write-Host "[fetch] FAIL $url : $($_.Exception.Message)"
}
