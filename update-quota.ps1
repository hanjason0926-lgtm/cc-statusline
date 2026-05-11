[CmdletBinding()]
param(
    [int]$h5,
    [string]$h5r,
    [int]$d7,
    [string]$d7r,
    [switch]$Clear,
    [switch]$Show
)

$ErrorActionPreference = 'Stop'

function ParseDuration([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return 0 }
    $total = 0
    foreach ($m in [regex]::Matches($s, '(\d+)\s*([dhms])')) {
        $n = [int]$m.Groups[1].Value
        switch ($m.Groups[2].Value) {
            'd' { $total += $n * 86400 }
            'h' { $total += $n * 3600 }
            'm' { $total += $n * 60 }
            's' { $total += $n }
        }
    }
    if ($total -eq 0 -and $s -match '^\d+$') { $total = [int]$s }
    return $total
}

$cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$cachePath = Join-Path $cfg 'quota-cache.json'

if ($Clear) {
    if (Test-Path $cachePath) { Remove-Item $cachePath -Force; Write-Host "Cleared $cachePath" }
    else { Write-Host "Nothing to clear." }
    return
}

# Load existing cache (merge semantics so partial updates don't wipe other fields)
$obj = [ordered]@{}
if (Test-Path $cachePath) {
    try {
        $raw = Get-Content $cachePath -Raw | ConvertFrom-Json
        foreach ($p in $raw.PSObject.Properties) { $obj[$p.Name] = $p.Value }
    } catch {}
}

$now = [int][DateTimeOffset]::Now.ToUnixTimeSeconds()
$changed = $false

if ($PSBoundParameters.ContainsKey('h5'))  { $obj['h5_pct'] = $h5; $changed = $true }
if ($PSBoundParameters.ContainsKey('h5r')) {
    $obj['h5_reset_at'] = $now + (ParseDuration $h5r)
    $changed = $true
}
if ($PSBoundParameters.ContainsKey('d7'))  { $obj['d7_pct'] = $d7; $changed = $true }
if ($PSBoundParameters.ContainsKey('d7r')) {
    $obj['d7_reset_at'] = $now + (ParseDuration $d7r)
    $changed = $true
}

if ($Show -or -not $changed) {
    Write-Host "Cache file: $cachePath"
    if ($obj.Count -eq 0) {
        Write-Host '(empty - no quota data yet)'
    } else {
        $h5pct = if ($null -ne $obj.h5_pct) { "$($obj.h5_pct)%" } else { '--' }
        $d7pct = if ($null -ne $obj.d7_pct) { "$($obj.d7_pct)%" } else { '--' }
        $h5left = if ($null -ne $obj.h5_reset_at) { "$([int]$obj.h5_reset_at - $now)s" } else { '--' }
        $d7left = if ($null -ne $obj.d7_reset_at) { "$([int]$obj.d7_reset_at - $now)s" } else { '--' }
        Write-Host ("Current: 5h {0} reset_in {1}  |  7d {2} reset_in {3}" -f $h5pct, $h5left, $d7pct, $d7left)
    }
    Write-Host ''
    Write-Host 'Usage:'
    Write-Host '  update-quota -h5 20 -h5r 1h20m -d7 50 -d7r 5d21h'
    Write-Host '  update-quota -h5 35              # update only 5h percentage'
    Write-Host '  update-quota -Clear              # delete cache'
    Write-Host '  update-quota -Show               # show current values'
    Write-Host 'Duration formats: 1h20m, 5d21h, 30m, 90s (combine d/h/m/s)'
    return
}

$obj['fetched_at'] = $now
$json = ($obj | ConvertTo-Json -Compress)
[System.IO.File]::WriteAllText($cachePath, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "Updated $cachePath"
Write-Host $json
