[CmdletBinding()]
param(
    [string]$ConfigDir,
    [switch]$NoFetch
)

$ErrorActionPreference = 'Stop'

if (-not $ConfigDir) {
    $ConfigDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
}

if (-not (Test-Path $ConfigDir)) {
    Write-Host "Creating $ConfigDir"
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

$src = $PSScriptRoot
$files = @('statusline.ps1', 'fetch-quota.ps1', 'update-quota.ps1')
foreach ($f in $files) {
    $from = Join-Path $src $f
    $to   = Join-Path $ConfigDir $f
    Copy-Item -Path $from -Destination $to -Force
    Write-Host "Copied $f -> $to"
}

# --- Update settings.json (merge, don't overwrite) ---
$settingsPath = Join-Path $ConfigDir 'settings.json'
$settings = if (Test-Path $settingsPath) {
    try { Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { [PSCustomObject]@{} }
} else {
    [PSCustomObject]@{}
}

$cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $ConfigDir 'statusline.ps1')`""
$statusLine = [PSCustomObject]@{ type = 'command'; command = $cmd }

if ($settings.PSObject.Properties.Name -contains 'statusLine') {
    $settings.statusLine = $statusLine
} else {
    $settings | Add-Member -NotePropertyName 'statusLine' -NotePropertyValue $statusLine
}

$json = $settings | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote statusLine config to $settingsPath"

# --- Initial quota fetch (best-effort) ---
if (-not $NoFetch) {
    Write-Host ""
    Write-Host "Fetching initial quota..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ConfigDir 'fetch-quota.ps1')
}

Write-Host ""
Write-Host "Done. Restart Claude Code to see the new statusline."
