# cc-statusline

給 Windows 上 [Claude Code](https://claude.com/claude-code) 用的兩行 PowerShell statusline。
顯示模型、專案、context 用量、session 成本、**5 小時與週配額（含倒數）**，再加 git / venv / token 統計。

English: [README.md](README.md)

## 預覽

```
🤖 Opus 4.7 | 📁 my-project | 🧠 12% (24.0k/200.0k) | 💰 $0.1234 | ⏰ 5h 6% ⟳ 11m | 7d 2% ⟳ 6d16h
🌿 main | +0 ~2 ?1 ↑0 ↓0 *0 | 🐍 .venv | 📥 1.2k 📤 850 💾 4.5k 📖 12.0k
```

## 功能

- **真實的 5h / 7d 配額** — 跟 TUI 裡 `/status` 看到的數字一樣，從 OAuth `usage` endpoint 抓
- **背景刷新** — statusline 渲染從不卡住；快取超過 60 秒就背景觸發更新
- **Context window 百分比** — 用最後一則訊息的 input + cache token 算
- **Session 累計 token** — input / output / cache-create / cache-read
- **Git 狀態** — branch、staged / modified / untracked、ahead / behind、stash 數
- **venv 偵測** — 自動讀 `$VIRTUAL_ENV` 或 `$CONDA_DEFAULT_ENV`
- **手動覆寫** — 提供 `update-quota.ps1`，自動抓壞掉時可以手動填數字

## 需求

- Windows + PowerShell 5.1（內建）或 PowerShell 7+
- Claude Code 已安裝且用 Pro / Max OAuth 登入過
  （腳本會從 `.credentials.json` 讀 OAuth token）
- 終端機要支援 emoji（建議用 Windows Terminal）

## 安裝

clone 後跑 `install.ps1`：

```powershell
git clone https://github.com/<your-username>/cc-statusline.git
cd cc-statusline
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

它會做這些事：
1. 把 `statusline.ps1`、`fetch-quota.ps1`、`update-quota.ps1` 複製到 `$env:CLAUDE_CONFIG_DIR`（預設 `$env:USERPROFILE\.claude`）
2. 把 `statusLine` 區塊 merge 進你的 `settings.json`（既有設定不會被覆蓋）
3. 跑一次 `fetch-quota.ps1` 暖快取，這樣 Claude Code 一啟動就看得到數字

裝完後重啟 Claude Code。

### 指定其他 config 目錄

要裝到非預設目錄（例如第二個 profile）：

```powershell
.\install.ps1 -ConfigDir 'C:\Users\you\.claude-second'
```

### 跳過初始 fetch

```powershell
.\install.ps1 -NoFetch
```

## 配額怎麼來的

`fetch-quota.ps1` 會打 Claude Code TUI 內部使用的、未公開的 OAuth endpoint：

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <.credentials.json 裡的 claudeAiOauth.accessToken>
anthropic-beta: oauth-2025-04-20
```

回傳（節錄）：
```json
{
  "five_hour":  { "utilization": 6.0, "resets_at": "2026-05-11T04:50:01Z" },
  "seven_day":  { "utilization": 2.0, "resets_at": "2026-05-17T21:00:01Z" }
}
```

這些值會寫到 Claude config 目錄下的 `quota-cache.json`。statusline 渲染時讀這個快取，如果發現超過 60 秒，就背景開一個隱藏的 `fetch-quota.ps1` 去更新——下次渲染就會看到新值，目前這次不會被拖慢。

## 客製化

| 想改什麼 | 改哪個檔案 | 改哪一行 |
| --- | --- | --- |
| 快取 TTL（預設 60 秒） | `statusline.ps1` | `if ($cacheAge -gt 60)` |
| Context window 大小（預設 200000） | `statusline.ps1` | `$ctxLimit = 200000`（1M Opus 改 `1000000`） |
| Reset 倒數符號 | `statusline.ps1` | `$line1` format string 裡的兩個 `⟳` |
| 整體版型 | `statusline.ps1` | `$line1` / `$line2` format strings |

## 手動覆寫配額

OAuth 抓壞掉的話可以手動填：

```powershell
update-quota -h5 20 -h5r 1h20m -d7 50 -d7r 5d21h
update-quota -h5 35              # 只更新 5h 百分比
update-quota -Show               # 顯示目前快取值
update-quota -Clear              # 砍掉快取檔
```

時間格式：`1h20m`、`5d21h`、`30m`、`90s`（可以混搭 `d` / `h` / `m` / `s`）。

## 注意事項

- OAuth `usage` endpoint **沒有官方文件**。Anthropic 可以隨時改或拿掉——如果掛了，`fetch-quota.ps1` 會 silent 失敗，statusline 會 fallback 到上一份快取（或顯示 `--`）。
- 腳本從 `.credentials.json` 讀 OAuth access token。如果你的安裝把 credential 放在別處（某些設定會用 Windows Credential Manager），需要自己改 `fetch-quota.ps1`。
- 5h / 7d 配額只對 Pro / Max 訂閱用戶有意義。純 API key 用戶會看到 `--`。

## 致謝

OAuth `usage` endpoint 的方法是從 [tzengyuxio/claude-statusline](https://github.com/tzengyuxio/claude-statusline)（macOS / Linux 的 bash 版本）發現的。這個 repo 是 Windows PowerShell 重寫版，並做了一些格式 / 刷新邏輯的調整。

## License

MIT — 見 [LICENSE](LICENSE).
