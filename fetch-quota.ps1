[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$credPath  = Join-Path $cfg '.credentials.json'
$cachePath = Join-Path $cfg 'quota-cache.json'

if (-not (Test-Path $credPath)) {
    if (-not $Quiet) { Write-Host "No credentials at $credPath" }
    exit 1
}

$cred = Get-Content $credPath -Raw | ConvertFrom-Json
$token = $cred.claudeAiOauth.accessToken
if (-not $token) {
    if (-not $Quiet) { Write-Host "No claudeAiOauth.accessToken in $credPath" }
    exit 1
}

$headers = @{
    'Authorization'  = "Bearer $token"
    'anthropic-beta' = 'oauth-2025-04-20'
}

try {
    $resp = Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -Headers $headers -TimeoutSec 10
} catch {
    if (-not $Quiet) { Write-Host "API call failed: $($_.Exception.Message)" }
    exit 1
}

function ToEpoch($iso) {
    if (-not $iso) { return $null }
    return [int]([DateTimeOffset]::Parse($iso)).ToUnixTimeSeconds()
}

$now = [int][DateTimeOffset]::Now.ToUnixTimeSeconds()
$ex  = $resp.extra_usage

$obj = [ordered]@{
    h5_pct      = if ($resp.five_hour) { [int][math]::Round([double]$resp.five_hour.utilization, 0, [MidpointRounding]::AwayFromZero) } else { $null }
    h5_reset_at = if ($resp.five_hour) { ToEpoch $resp.five_hour.resets_at } else { $null }
    d7_pct      = if ($resp.seven_day) { [int][math]::Round([double]$resp.seven_day.utilization, 0, [MidpointRounding]::AwayFromZero) } else { $null }
    d7_reset_at = if ($resp.seven_day) { ToEpoch $resp.seven_day.resets_at } else { $null }
    ex_enabled  = if ($ex) { [bool]$ex.is_enabled } else { $false }
    ex_pct      = if ($ex) { [int][math]::Round([double]$ex.utilization, 0, [MidpointRounding]::AwayFromZero) } else { $null }
    ex_used     = if ($ex) { [int]$ex.used_credits } else { $null }
    ex_limit    = if ($ex) { [int]$ex.monthly_limit } else { $null }
    fetched_at  = $now
}

$json = $obj | ConvertTo-Json -Compress
[System.IO.File]::WriteAllText($cachePath, $json, [System.Text.UTF8Encoding]::new($false))

if (-not $Quiet) {
    Write-Host "Updated $cachePath"
    Write-Host $json
}
