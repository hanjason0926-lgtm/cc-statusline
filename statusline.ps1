$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

$stdin = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
$raw = $stdin.ReadToEnd()
try { $data = $raw | ConvertFrom-Json } catch { $data = $null }

function PrettyModel($id) {
    if (-not $id) { return 'Claude' }
    if ($id -match '(?i)(opus|sonnet|haiku)-(\d+)-(\d+)') {
        $tier = (Get-Culture).TextInfo.ToTitleCase($Matches[1].ToLower())
        return "$tier $($Matches[2]).$($Matches[3])"
    }
    return $id
}
$model = if ($data.model.display_name) {
    $data.model.display_name
} elseif ($data.model.id) {
    PrettyModel $data.model.id
} else {
    'Claude'
}
$projectDir  = if ($data.workspace.project_dir) { $data.workspace.project_dir } else { (Get-Location).Path }
$projectName = Split-Path $projectDir -Leaf
$cost        = if ($data.cost.total_cost_usd) { [double]$data.cost.total_cost_usd } else { 0 }
$transcript  = $data.transcript_path

function FmtTok($n) {
    $n = [int]$n
    if ($n -ge 1000000) { return ('{0:N2}M' -f ($n/1000000)) }
    if ($n -ge 1000)    { return ('{0:N1}k' -f ($n/1000))    }
    return "$n"
}

# --- Token usage ---
$ctxUsed = 0
$cumulTotal = 0
$sumIn = 0; $sumOut = 0; $sumCC = 0; $sumCR = 0
if ($transcript -and (Test-Path $transcript)) {
    $lastUsage = $null
    Get-Content $transcript -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $obj = $_ | ConvertFrom-Json -ErrorAction Stop
            $u = $obj.message.usage
            if ($u) {
                $sumIn  += [int]$u.input_tokens
                $sumOut += [int]$u.output_tokens
                $sumCC  += [int]$u.cache_creation_input_tokens
                $sumCR  += [int]$u.cache_read_input_tokens
                $lastUsage = $u
            }
        } catch {}
    }
    if ($lastUsage) {
        $ctxUsed = [int]$lastUsage.input_tokens + [int]$lastUsage.cache_creation_input_tokens + [int]$lastUsage.cache_read_input_tokens
    }
    $cumulTotal = $sumIn + $sumOut + $sumCC + $sumCR
}
$ctxLimit = 200000
$ctxPct   = if ($ctxLimit -gt 0) { [math]::Round($ctxUsed * 100 / $ctxLimit, 0) } else { 0 }

# --- Quota cache (auto-refreshed by fetch-quota.ps1) ---
$h5Pct = '--'; $h5Reset = '--'
$d7Pct = '--'; $d7Reset = '--'
$quotaCache = Join-Path $env:CLAUDE_CONFIG_DIR 'quota-cache.json'
$now = [int][DateTimeOffset]::Now.ToUnixTimeSeconds()
$cacheAge = if (Test-Path $quotaCache) { $now - [int]((Get-Item $quotaCache).LastWriteTime.ToUniversalTime() - [datetime]'1970-01-01').TotalSeconds } else { [int]::MaxValue }
if ($cacheAge -gt 60) {
    $fetcher = Join-Path $env:CLAUDE_CONFIG_DIR 'fetch-quota.ps1'
    if (Test-Path $fetcher) {
        Start-Process -WindowStyle Hidden -FilePath 'powershell.exe' `
            -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$fetcher,'-Quiet' | Out-Null
    }
}
if (Test-Path $quotaCache) {
    try {
        $q = Get-Content $quotaCache -Raw | ConvertFrom-Json
        function FmtDur($s) {
            $s = [int]$s
            if ($s -le 0) { return '0m' }
            $d = [math]::Floor($s / 86400); $s -= $d*86400
            $h = [math]::Floor($s / 3600);  $s -= $h*3600
            $m = [math]::Floor($s / 60)
            if ($d -gt 0) { return ('{0}d{1}h' -f $d,$h) }
            if ($h -gt 0) { return ('{0}h{1}m' -f $h,$m) }
            return ('{0}m' -f $m)
        }
        if ($null -ne $q.h5_pct)      { $h5Pct = "$($q.h5_pct)%" }
        if ($null -ne $q.h5_reset_at) { $h5Reset = FmtDur ([int]$q.h5_reset_at - $now) }
        if ($null -ne $q.d7_pct)      { $d7Pct = "$($q.d7_pct)%" }
        if ($null -ne $q.d7_reset_at) { $d7Reset = FmtDur ([int]$q.d7_reset_at - $now) }
    } catch {}
}

# --- Compose Line 1 (emoji as literals) ---
$ctxStr  = "{0}% ({1}/{2})" -f $ctxPct, (FmtTok $ctxUsed), (FmtTok $ctxLimit)
$costStr = '${0}' -f [math]::Round($cost,4)
$line1 = "🤖 {0} | 🧠 {1} | 💰 {2} | ⏰ 5h {3} ⟳ {4} | 7d {5} ⟳ {6}" -f `
    $model, $ctxStr, $costStr, $h5Pct, $h5Reset, $d7Pct, $d7Reset

# --- Line 2: git + venv ---
$branch = $null
$staged = 0; $modified = 0; $untracked = 0; $ahead = 0; $behind = 0; $stashCount = 0
if ($projectDir -and (Test-Path $projectDir)) {
    Push-Location $projectDir
    try { $branch = & git rev-parse --abbrev-ref HEAD 2>$null } catch {}
    if ($branch) {
        $status = & git status --porcelain 2>$null
        foreach ($l in $status) {
            if ($l.Length -lt 2) { continue }
            if ($l.StartsWith('??')) { $untracked++; continue }
            $x = $l[0]; $y = $l[1]
            if ('MADRC'.Contains($x)) { $staged++ }
            if ('MD'.Contains($y))    { $modified++ }
        }
        $ab = & git rev-list --left-right --count 'HEAD...@{upstream}' 2>$null
        if ($ab) {
            $parts = $ab -split "\s+"
            if ($parts.Length -ge 2) { $ahead = [int]$parts[0]; $behind = [int]$parts[1] }
        }
        $sl = & git stash list 2>$null
        if ($sl) { $stashCount = ($sl | Measure-Object -Line).Lines }
    }
    Pop-Location
}

if ($branch) {
    $line2 = "📁 {0} | 🌿 {1} | +{2} ~{3} ?{4} ↑{5} ↓{6} *{7}" -f $projectName, $branch, $staged, $modified, $untracked, $ahead, $behind, $stashCount
} elseif ($projectDir) {
    $line2 = "📁 {0} | 🌿 (no repo)" -f $projectName
} else {
    $line2 = "📁 (no project dir) | 🌿 (no project dir)"
}

if ($env:VIRTUAL_ENV) {
    $line2 += " | 🐍 " + (Split-Path $env:VIRTUAL_ENV -Leaf)
} elseif ($env:CONDA_DEFAULT_ENV) {
    $line2 += " | 🐍 " + $env:CONDA_DEFAULT_ENV
} else {
    $line2 += " | 🐍 none"
}

$line2 += " | 📥 {0} 📤 {1} 💾 {2} 📖 {3}" -f (FmtTok $sumIn), (FmtTok $sumOut), (FmtTok $sumCC), (FmtTok $sumCR)

[Console]::Out.WriteLine($line1)
[Console]::Out.WriteLine($line2)
