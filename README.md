# cc-statusline

A two-line PowerShell statusline for [Claude Code](https://claude.com/claude-code) on Windows.
Shows model, project, context usage, session cost, **5-hour & weekly subscription quota with reset countdown**, plus git / venv / token stats.

中文版：[README.zh-TW.md](README.zh-TW.md)

## Preview

```
🤖 Opus 4.7 | 📁 my-project | 🧠 12% (24.0k/200.0k) | 💰 $0.1234 | ⏰ 5h 6% ⟳ 11m | 7d 2% ⟳ 6d16h
🌿 main | +0 ~2 ?1 ↑0 ↓0 *0 | 🐍 .venv | 📥 1.2k 📤 850 💾 4.5k 📖 12.0k
```

## Features

- **Real 5h / 7d quota** — same numbers as `/status` in the TUI, fetched from the OAuth `usage` endpoint
- **Background refresh** — statusline never blocks; quota cache auto-updates every 60s
- **Context window %** — based on the latest message's input + cache tokens
- **Cumulative session token totals** — input / output / cache-create / cache-read
- **Git status** — branch, staged / modified / untracked, ahead / behind, stash count
- **venv detection** — picks up `$VIRTUAL_ENV` or `$CONDA_DEFAULT_ENV`
- **Manual override** — `update-quota.ps1` if you want to type the numbers in by hand

## Requirements

- Windows + PowerShell 5.1 (built into Windows) or PowerShell 7+
- Claude Code installed and signed in via the Claude Pro / Max OAuth flow
  (the script reads the OAuth token from `.credentials.json`)
- A terminal with emoji support (Windows Terminal recommended)

## Install

Clone, then run `install.ps1`:

```powershell
git clone https://github.com/<your-username>/cc-statusline.git
cd cc-statusline
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

What it does:
1. Copies `statusline.ps1`, `fetch-quota.ps1`, `update-quota.ps1` to `$env:CLAUDE_CONFIG_DIR` (defaults to `$env:USERPROFILE\.claude`)
2. Merges a `statusLine` block into your `settings.json` (existing keys are preserved)
3. Runs `fetch-quota.ps1` once so the cache is warm before you launch Claude Code

Restart Claude Code afterwards.

### Custom config dir

Targeting a non-default config dir (e.g. a second profile):

```powershell
.\install.ps1 -ConfigDir 'C:\Users\you\.claude-second'
```

### Skip initial fetch

```powershell
.\install.ps1 -NoFetch
```

## How quota works

`fetch-quota.ps1` calls an undocumented OAuth endpoint that the Claude Code TUI itself uses:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <claudeAiOauth.accessToken from .credentials.json>
anthropic-beta: oauth-2025-04-20
```

Response (trimmed):
```json
{
  "five_hour":  { "utilization": 6.0, "resets_at": "2026-05-11T04:50:01Z" },
  "seven_day":  { "utilization": 2.0, "resets_at": "2026-05-17T21:00:01Z" }
}
```

Those values get written to `quota-cache.json` in your Claude config dir. The statusline reads the cache and, if it's older than 60 seconds, kicks off a hidden background `fetch-quota.ps1` so the next render is fresh — without slowing down the current render.

## Customization

| Want to change | File | What to edit |
| --- | --- | --- |
| Cache TTL (default 60s) | `statusline.ps1` | `if ($cacheAge -gt 60)` |
| Context window size (default 200000) | `statusline.ps1` | `$ctxLimit = 200000` (set to `1000000` for 1M Opus) |
| Reset countdown symbol | `statusline.ps1` | The two `⟳` characters in the `$line1` format string |
| Line layout | `statusline.ps1` | The `$line1` / `$line2` format strings |

## Manual quota override

If the OAuth fetch breaks for any reason, you can still type quota numbers in by hand:

```powershell
update-quota -h5 20 -h5r 1h20m -d7 50 -d7r 5d21h
update-quota -h5 35              # update only 5h percentage
update-quota -Show               # show current cached values
update-quota -Clear              # delete the cache file
```

Duration formats: `1h20m`, `5d21h`, `30m`, `90s` (combine `d` / `h` / `m` / `s`).

## Caveats

- The OAuth `usage` endpoint is **not officially documented**. Anthropic could change or remove it without notice — if that happens, `fetch-quota.ps1` silently fails and the statusline falls back to the last cached values (or `--`).
- The script reads your OAuth access token from `.credentials.json`. If your install stores credentials elsewhere (Windows Credential Manager on some setups), you'll need to adapt `fetch-quota.ps1`.
- 5h / 7d quota only applies to Pro / Max subscription users. API-key-only users will see `--`.

## Credits

The OAuth `usage` endpoint approach was discovered via [tzengyuxio/claude-statusline](https://github.com/tzengyuxio/claude-statusline) (bash version for macOS / Linux). This repo is a PowerShell rewrite for Windows with a few format / refresh tweaks.

## License

MIT — see [LICENSE](LICENSE).
