# cc-statusline

給 Windows 上 [Claude Code](https://claude.com/claude-code) 用的兩行 PowerShell statusline。
顯示模型、專案、context 用量、session 成本、**5 小時與週配額（含倒數）**，再加 git / venv / token 統計。

English: [README.md](README.md)

## 預覽

![Statusline 預覽](screenshot.png)

## 功能

### 1. 🤖 模型名稱

從 Claude Code 餵進來的 stdin 取 `model.display_name`（例如 `Opus 4.7`、`Sonnet 4.6`、`Haiku 4.5`）。欄位不存在時 fallback 顯示 `Claude`。session 中切換模型時，可以一眼確認切換有生效。

範例：`🤖 Opus 4.7`

### 2. 📁 專案名稱

從 stdin 讀 `workspace.project_dir`，只取**最後一層資料夾名**（不顯示完整路徑，避免佔太多版面）。欄位不存在的話 fallback 用目前工作目錄。多開好幾個 Claude Code 視窗在不同專案間切時很有用。

範例：`📁 my-project`

### 3. 🧠 Context window 用量

讀取目前 session 的 transcript（從 Claude Code 餵進來的 `transcript_path`），抓**最後一則**訊息的 `usage` 區塊，計算：

```
context_used = input_tokens + cache_creation_input_tokens + cache_read_input_tokens
context_pct  = context_used / 200000 * 100
```

預設上限 200,000 tokens（Sonnet / Opus 標準）。如果你用的是 1M context Opus，把 `statusline.ps1` 裡的 `200000` 改成 `1000000`。

範例：`🧠 12% (24.0k/200.0k)`

### 4. 💰 Session 成本

直接讀 Claude Code 餵進來的 `cost.total_cost_usd`，四捨五入到小數點後 4 位。session 早期就能看到累積成本，不會早早變成科學記號。

範例：`💰 $0.1234`

### 5. ⏰ 真實的 5 小時 / 7 天訂閱配額

顯示**跟 Claude Code TUI 裡 `/status` 完全一樣**的數字 — 目前用量百分比，加上距離下次 reset 的倒數（`⟳`）。不是估算、不是用 token 數量推算；數字直接從 Anthropic 的 OAuth `usage` endpoint 拿，所以永遠跟 `/status` 一致。

範例：`⏰ 5h 6% ⟳ 11m | 7d 2% ⟳ 6d16h`

### 6. 🌿 Git 狀態

如果專案目錄是 git repo，會跑幾個輕量命令（`rev-parse`、`status --porcelain`、`rev-list ...@{upstream}`、`stash list`）然後顯示：

- branch 名稱
- `+N` 已 stage 的檔案數
- `~N` 已修改的檔案數
- `?N` untracked 的檔案數
- `↑N` 領先 upstream 幾個 commit
- `↓N` 落後 upstream 幾個 commit
- `*N` stash 數

範例：`🌿 main | +0 ~2 ?1 ↑0 ↓0 *0`

不是 git repo 的話會顯示 `🌿 (no repo)`，不會有錯誤訊息亂噴。

### 7. 🐍 Python venv 偵測

優先讀 `$env:VIRTUAL_ENV`，沒有就 fallback 到 `$env:CONDA_DEFAULT_ENV`。會顯示 env 名字（只取資料夾名），都沒有的話顯示 `🐍 none`。可以一眼確認 Claude Code 有沒有繼承到你預期的 venv。

### 8. 📥 📤 💾 📖 Session 累計 token 統計

讀 transcript 算 context % 的同時，腳本也會**把整個 transcript 裡每一筆** `usage` 加總起來，給你看這個 session 各類別總共燒了多少 token：

- 📥 input tokens
- 📤 output tokens
- 💾 cache-creation tokens
- 📖 cache-read tokens

對於診斷「為什麼這 session 一直在重新上傳大檔而不是讀快取」很有用。

### 9. 不阻塞的背景刷新

statusline 必須在毫秒內渲染完 — Claude Code 每次事件都會重跑這個腳本。所以 `statusline.ps1` 自己**完全不打網路**。它只讀本地的 `quota-cache.json`，發現快取超過 60 秒才會用背景隱藏程序去跑 `fetch-quota.ps1`。當下這次渲染用的是舊快取，下一次渲染才會看到新值。結果就是：API 慢或掛掉，statusline 也不會跟著卡。

### 10. 手動配額覆寫

如果 OAuth 抓壞掉（token 過期、endpoint 改了、你不是訂閱用戶），可以用 `update-quota.ps1` 手動把數字填進去，statusline 會跟自動抓的一樣顯示出來。詳見下方 [手動覆寫配額](#手動覆寫配額)。

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

## License

MIT — 見 [LICENSE](LICENSE).
