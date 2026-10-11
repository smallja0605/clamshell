# Clamshell 🦀

A tiny pixel crab that lives in your macOS menu bar and works whenever [Claude Code](https://claude.com/claude-code) does.

Send a prompt and it crawls out from behind its neighbour, opens a laptop and starts typing. When Claude is done it
closes the laptop and slips out of sight. While Claude is idle, there is nothing in your menu bar at all.

> 繁體中文說明在[下方](#繁體中文)。　Windows version: not yet.

<p align="center">
  <img src="design/preview.gif" alt="The built-in crab opening its laptop, typing, and leaving" width="360"><br>
  <sub>The built-in crab. The text types itself in, new statuses roll up from below, and the clock turns over digit by digit.</sub>
</p>

### 🦀 Prefer the pixel crab that Claude Code itself uses?

It is included as an **optional extra** and works exactly the same way:

<p align="center">
  <img src="extras/claude-crab/preview.gif" alt="The Claude Code crab, as an optional extra" width="346">
</p>

Get it from [`extras/claude-crab/`](extras/claude-crab/) — double-click `ClaudeCrab.clamshellmascot`, or build with
`./scripts/build-app.sh --with-extras`. See [Extras: the Claude Code crab](#extras-the-claude-code-crab) for details.
It is kept separate from the MIT-licensed code (read its [NOTICE](extras/claude-crab/NOTICE.md)), and the crab you get
out of the box is an original one.

## What it does

| Moment | What you see |
| --- | --- |
| Claude is idle | Nothing. The item is hidden, not just empty (or park the crab there with *Always show in menu bar*) |
| You send a prompt | The crab crawls out and opens its laptop |
| Claude is working | It types. The status text types itself in ("思考中…" / "Thinking…"), the dots keep moving, a new status rolls up from below and pushes the old one out, and the clock turns over digit by digit |
| Claude needs your permission | The label turns yellow: "等待授權" / "Awaiting permission" |
| Claude finishes | The text erases, the laptop closes, the crab slips away (optionally with a chime) |

Click the item to see every running session: project, git branch, state and elapsed time. Clicking a row brings the
terminal or app that session runs in to the front. If the crab is hidden and you need the menu, open Clamshell again from
Spotlight and it peeks out for a few seconds.

Status text is shown in Traditional Chinese or English, following your system language (change it under *Language*).

## Install

Requires macOS 13 or later (Apple silicon or Intel).

### Download

Get `Clamshell-<version>.dmg` from the [Releases](../../releases) page, open it and drag Clamshell to *Applications*. Check the download
against `SHA256SUMS.txt` if you like (`shasum -a 256 -c SHA256SUMS.txt`).

Clamshell is not signed with an Apple Developer ID yet, so macOS warns the first time you open it:

- **macOS 15 and later:** open the app once, then go to *System Settings → Privacy & Security*, scroll down and click *Open Anyway*.
- **macOS 14 and earlier:** right-click the app and choose *Open*.

### Homebrew

```bash
brew install --cask smallja0605/clamshell/clamshell
```

That adds the [`smallja0605/homebrew-clamshell`](https://github.com/smallja0605/homebrew-clamshell) tap and installs the app into *Applications*.
The first-open warning above applies here too. Update with `brew upgrade --cask clamshell`. To uninstall, first choose
*Remove Claude Code hooks…* from Clamshell's menu (so no hook is left pointing at a missing app), then
`brew uninstall --cask clamshell` (add `--zap` to also delete its settings and data).

### Build from source

```bash
git clone <this repository> && cd clamshell
./scripts/build-app.sh          # builds dist/Clamshell.app (ad-hoc signed — fine for your own Mac)
open dist/Clamshell.app
```

An app you built yourself is not quarantined, so it opens without the warning above.

On first launch Clamshell asks before it touches anything. If you agree, it adds a few hooks to
`~/.claude/settings.json` (a backup is saved next to it as `settings.json.bak-clamshell`). The hooks run a small native
helper, `clamshell-hook`, that is bundled inside the app — **no Node.js or other runtime needed**. You can remove them
at any time from the menu (*Remove Claude Code hooks…*).

Want the Claude Code crab built into your copy? Add `--with-extras`: `./scripts/build-app.sh --with-extras`.

Want an installer image with a drag-to-Applications window?

```bash
./scripts/build-app.sh --dmg    # dist/Clamshell.dmg
```

## Mascots

Clamshell ships with one built-in crab. You can switch to another mascot, or make your own, from the menu → *Mascot*.

### Extras: the Claude Code crab

The pixel crab that Claude Code itself uses is available as an **optional extra** in [`extras/claude-crab/`](extras/claude-crab/).
It is kept apart from the rest of the project on purpose: it is not original to this project, it is **not covered by the MIT licence**,
and the default build does not include it (read its [NOTICE](extras/claude-crab/NOTICE.md) first).

There are two ways to get it:

- **Install the pack:** download [`ClaudeCrab.clamshellmascot`](extras/claude-crab/ClaudeCrab.clamshellmascot) and double-click it
  (Clamshell must be installed). It then shows up under *Mascot*.
- **Build it in:** `./scripts/build-app.sh --with-extras` bundles every pack from [`extras/`](extras/) into the app.

### Use your own animation

**Import a GIF.** Menu → *Mascot* → *Import GIF…*, or drop a GIF on the app icon. Clamshell removes a flat background,
crops the artwork, and cuts the animation into three parts:

- an **opening** that plays once when work starts (for example, taking out a laptop),
- a **loop** that repeats while Claude works,
- a **closing** that plays once when it finishes.

Choose *auto-split* (roughly the first third is the opening, the last fifth the closing) or *loop the whole thing* if your
GIF has no opening or closing. The result is a **mascot pack** you can switch to, export, share, or remove from the same menu.

**Mascot packs** are plain folders, so they are easy to make by hand or with any tool. A pack named `My crab` is
`My crab.clamshellmascot/`, and double-clicking one installs it:

```
My crab.clamshellmascot/
├── mascot.json        {"name": "My crab", "author": "you", "fps": 10, "introFrames": 8, "outroFrames": 6}
├── frame_000.png      the whole animation, in order
├── frame_001.png
└── …
```

- The first `introFrames` frames play once at the start, the last `outroFrames` frames play once at the end, everything in
  between loops. Set both to `0` for a pure loop. At least two frames are always kept for the loop.
- Frames are shown 18 pt tall, so make them **36 px tall** (the width follows your artwork) with a transparent background.
- The black-and-white menu bar mode (*Color → Match menu bar*) is derived automatically from your colours.
- Packs live in `~/.claude/clamshell/mascots/`. Edit `mascot.json` there to change the cut points or speed, and re-select
  the mascot to reload it.

You can also make a pack from the command line, without opening the app:

```bash
dist/Clamshell.app/Contents/MacOS/Clamshell --make-pack animation.gif "My crab" "My crab.clamshellmascot"
```

> **About the artwork you import.** Clamshell is only the tool. It contains no third-party characters, and importing a
> picture does not give you any rights to it. Make sure you are allowed to use, and especially to share, whatever you import.

## How it works

```
Claude Code ──hook event──▶ clamshell-hook ──writes──▶ ~/.claude/clamshell/sessions/<id>.json
                                                              │  (directory watcher)
                                                              ▼
                                              Clamshell.app  ──▶ menu-bar mascot + menu
```

- `Sources/ClamshellCore` — everything that can be tested without a screen: the hook state machine, the session store
  (a session lives exactly as long as its `claude` process; a missed *Stop* or an interrupted turn is detected from the
  transcript so the crab never gets stuck), the `settings.json` installer, mascot packs and the GIF importer, strings.
- `Sources/clamshell-hook` — the helper Claude Code runs. Headless, starts instantly, and always exits 0 so it can never
  break or slow down a session. If the app isn't running it launches it (unless you quit it on purpose).
- `Sources/Clamshell` — the app: `MenuBarMascot` is the animation engine (width, typewriter, rolling text, dots, clock),
  `StatusController` owns the menu and preferences.
- `tools/` — generators for the built-in crab, the chime, the icon and the installer artwork, so every asset can be rebuilt
  from source.

## Privacy

Clamshell reads only the small status files its own hook writes, and the tail of a session's transcript to notice an
interrupted turn. Nothing leaves your Mac; there is no networking code.

## Development

```bash
swift test                      # unit tests
./scripts/simulate.sh           # runs the real app and the real hook helper in an isolated home folder
python3 tools/make_sprites.py   # redraw the built-in crab (poses are plain parameters in that file)
./scripts/build-app.sh --dmg    # app + styled installer
```

Environment variables for testing: `CLAMSHELL_HOME` (data folder), `CLAMSHELL_CLAUDE_SETTINGS` (settings file to edit),
`CLAMSHELL_NO_INSTALL=1` (never touch Claude's settings), `CLAMSHELL_SNAP=<dir>` (write PNG snapshots of the menu-bar item —
handy because it needs no screen-recording permission), `CLAMSHELL_SELFTEST=1` (exercise the menu's actions and exit).

## Licence and credits

MIT — see [LICENSE](LICENSE). The built-in crab, icon, sound and installer artwork are original to this project.
Everything under [`extras/`](extras/) is **excluded** from that licence and has its own notice.

Clamshell is not affiliated with or endorsed by Anthropic. "Claude" and "Claude Code" are trademarks of Anthropic.

---

## 繁體中文

Clamshell 是 Claude Code 的 macOS 選單列小幫手：一隻像素小螃蟹。

你送出訊息，它就從旁邊的圖示後面爬出來、打開筆電開始打字；Claude 做完了，它蓋上筆電消失。
Claude 閒置時選單列上完全沒有東西（也可以勾選「永遠顯示在選單列」讓它待機）。

### 🦀 想用 Claude Code 自己的那隻小螃蟹？

它放在選用的附加包 [`extras/claude-crab/`](extras/claude-crab/)：雙擊 `ClaudeCrab.clamshellmascot` 就會裝進「吉祥物」選單，
或用 `./scripts/build-app.sh --with-extras` 打包進 App（預覽圖在上方英文段落）。它不在 MIT 授權範圍內，使用前請看該資料夾的
[NOTICE](extras/claude-crab/NOTICE.md)；預設內建的是一隻原創的小螃蟹。

**效果**
- 狀態文字以打字機效果出現，換成新狀態時，新字由下往上頂掉舊字；「…」是持續移動的進度動畫。
- 計時只有變動的那一位數字會翻動（例如 `1分29秒` → `1分30秒`）。
- 需要你授權時，文字變黃色「等待授權」。
- 點選單可看所有進行中的工作階段（專案、git 分支、狀態、已花時間），點一列會把對應的終端機或 App 帶到最前面。
- 狀態文字依系統語言顯示繁體中文或英文，也可在選單的「語言」手動切換。

**安裝**（需要 macOS 13 以上）

可以從 [Releases](../../releases) 下載 `Clamshell-<版本>.dmg`，或自己編譯：

```bash
./scripts/build-app.sh      # 產生 dist/Clamshell.app（自己編譯的 App 不會有下載警告）
open dist/Clamshell.app
```

也可以用 Homebrew 安裝：`brew install --cask smallja0605/clamshell/clamshell`（更新用 `brew upgrade --cask clamshell`；
解除安裝前請先在選單按「移除 Claude Code 連線…」，再執行 `brew uninstall --cask clamshell`）。

下載來的 App 因為還沒有 Apple 開發者簽章，第一次開啟 macOS 會警告：**macOS 15 以後**請先開一次，再到「系統設定 → 隱私權與安全性」往下捲，
按「仍要打開」；**macOS 14 以前**對 App 按右鍵 → 打開。

第一次開啟時，Clamshell 會先詢問，你同意才會在 `~/.claude/settings.json` 加入 hook（會先備份成
`settings.json.bak-clamshell`），不需要安裝 Node.js；隨時可以從選單「移除 Claude Code 連線…」拿掉。

**自訂吉祥物**
- 選單 →「吉祥物」→「匯入 GIF…」，或把 GIF 拖到 App 圖示上。Clamshell 會自動去背、裁切，並切成「開場（播一次）／打字循環／收尾（播一次）」三段；
  如果你的 GIF 沒有開場收尾，選「整段循環播放」即可。
- 匯入後會變成一個「吉祥物包」（`.clamshellmascot` 資料夾，裡面是 `mascot.json` 加上依序編號的 PNG 畫格），可以切換、匯出分享、移除；
  雙擊別人給你的 `.clamshellmascot` 就會安裝。
- 想微調開場與收尾的畫格數或速度，編輯 `~/.claude/clamshell/mascots/<名稱>/mascot.json` 即可。
- 匯入的圖片請確認你有權使用與分享，Clamshell 只是工具，預設不附帶任何第三方角色。
- **Claude Code 的小螃蟹**放在選用的附加包 [`extras/claude-crab/`](extras/claude-crab/)：雙擊 `ClaudeCrab.clamshellmascot` 就會裝進「吉祥物」選單，
  或用 `./scripts/build-app.sh --with-extras` 打包進 App。它**不在 MIT 授權範圍內**，使用前請先看該資料夾的 `NOTICE.md`。

**開發**：`swift test` 跑測試；`./scripts/simulate.sh` 用真正的 App 與 hook 在隔離環境跑一輪並輸出畫面截圖；
`./scripts/build-app.sh --dmg` 產生安裝檔。
