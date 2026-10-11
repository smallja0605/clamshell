import Foundation

public enum Language: String, CaseIterable {
    case auto, zh, en

    private static let key = "language"

    /// The user's choice (stored in defaults), "auto" by default.
    public static var preference: Language {
        get { Language(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// The language actually in effect: `.zh` or `.en`.
    public static var effective: Language {
        switch preference {
        case .zh, .en: return preference
        case .auto: return (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? .zh : .en
        }
    }
}

/// What the label next to the mascot says.
public enum StatusKind: Equatable {
    case thinking, command, editing, writing, reading, searching, webSearch, webFetch
    case delegating, planning, usingTool, permission, working

    /// Maps a Claude Code tool name (or MCP tool) to what the user would call it.
    public static func forTool(_ name: String) -> StatusKind {
        switch name {
        case "Bash", "BashOutput", "KillShell": return .command
        case "Edit", "MultiEdit", "NotebookEdit": return .editing
        case "Write": return .writing
        case "Read", "NotebookRead": return .reading
        case "Grep", "Glob", "LS": return .searching
        case "WebSearch": return .webSearch
        case "WebFetch": return .webFetch
        case "Task", "Agent": return .delegating
        case "TodoWrite", "ExitPlanMode": return .planning
        default: return name.isEmpty ? .working : .usingTool
        }
    }

    public static func of(_ s: LiveSession) -> StatusKind {
        switch s.phase {
        case .permission: return .permission
        case .tool: return forTool(s.record.tool)
        case .thinking: return .thinking
        case .idle, .done: return .working
        }
    }
}

public enum Strings {
    private static var zh: Bool { Language.effective == .zh }

    /// The label text, ending in "…" (the mascot animates that as moving dots).
    public static func status(_ k: StatusKind) -> String {
        let t: String
        switch k {
        case .thinking:   t = zh ? "思考中" : "Thinking"
        case .command:    t = zh ? "執行指令中" : "Running command"
        case .editing:    t = zh ? "編輯中" : "Editing"
        case .writing:    t = zh ? "寫入中" : "Writing"
        case .reading:    t = zh ? "閱讀中" : "Reading"
        case .searching:  t = zh ? "搜尋中" : "Searching"
        case .webSearch:  t = zh ? "搜尋網路中" : "Searching the web"
        case .webFetch:   t = zh ? "瀏覽網頁中" : "Browsing"
        case .delegating: t = zh ? "委派中" : "Delegating"
        case .planning:   t = zh ? "規劃中" : "Planning"
        case .usingTool:  t = zh ? "使用工具中" : "Using a tool"
        case .working:    t = zh ? "工作中" : "Working"
        case .permission: return zh ? "等待授權" : "Awaiting permission"
        }
        return t + "…"
    }

    /// "1m 4s" / "43s", or "1分4秒" / "43秒".
    public static func elapsed(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        if zh { return m > 0 ? "\(m)分\(s)秒" : "\(s)秒" }
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    // Menu
    public static var sessions: String { zh ? "工作階段" : "Sessions" }
    public static var noSessions: String { zh ? "目前沒有進行中的工作階段" : "No active sessions" }
    public static var openClaude: String { zh ? "開啟 Claude" : "Open Claude" }
    public static var options: String { zh ? "選項" : "Options" }
    public static var showClock: String { zh ? "顯示計時" : "Show timer" }
    public static var showText: String { zh ? "顯示文字" : "Show text" }
    public static var alwaysShow: String { zh ? "永遠顯示在選單列" : "Always show in menu bar" }
    public static var color: String { zh ? "顏色" : "Color" }
    public static var colorOriginal: String { zh ? "原色" : "Original" }
    public static var colorSystem: String { zh ? "跟隨系統（黑／白）" : "Match menu bar (black/white)" }
    public static var sound: String { zh ? "完成提示音" : "Completion sound" }
    public static var soundOff: String { zh ? "關閉" : "Off" }
    public static var soundEvery: String { zh ? "每次完成" : "Every turn" }
    public static func soundAtLeast(minutes: Int) -> String { zh ? "\(minutes) 分鐘以上" : "\(minutes) min or more" }
    public static var mascot: String { zh ? "吉祥物" : "Mascot" }
    public static var mascotBuiltIn: String { zh ? "內建小螃蟹" : "Built-in crab" }
    public static var mascotLegacy: String { zh ? "自訂（舊版匯入）" : "Custom (earlier import)" }
    public static var mascotImport: String { zh ? "匯入 GIF…" : "Import GIF…" }
    public static var mascotExport: String { zh ? "匯出目前吉祥物…" : "Export current mascot…" }
    public static var mascotRemove: String { zh ? "移除吉祥物" : "Remove mascot" }
    public static var mascotReveal: String { zh ? "在 Finder 顯示吉祥物資料夾" : "Show mascots in Finder" }
    public static var importTitle: String { zh ? "匯入吉祥物" : "Import a mascot" }
    public static var importBody: String {
        zh ? "把這個 GIF 轉成吉祥物。請確認你有權使用這個圖片。\n之後想調整開場與收尾的畫格數，可以編輯該資料夾裡的 mascot.json。"
           : "Turns this GIF into a mascot. Please make sure you have the right to use the image.\nTo adjust how many frames open and close the animation, edit mascot.json in its folder."
    }
    public static var importName: String { zh ? "名稱" : "Name" }
    public static var importKind: String { zh ? "動畫類型" : "Animation" }
    public static var importLoopOnly: String { zh ? "整段循環播放（沒有開場／收尾）" : "Loop the whole thing (no opening/closing)" }
    public static var importSplit: String { zh ? "前段是開場、後段是收尾（自動切分）" : "Opening at the start, closing at the end (auto-split)" }
    public static var importConfirm: String { zh ? "匯入" : "Import" }
    public static var cancel: String { zh ? "取消" : "Cancel" }
    public static var importFailed: String { zh ? "無法匯入這個檔案" : "Could not import this file" }
    public static var importFailedBody: String { zh ? "請確認它是有內容的 GIF 動畫。" : "Make sure it is a GIF animation with visible artwork." }
    public static func removeConfirm(_ name: String) -> String { zh ? "要移除「\(name)」嗎？" : "Remove “\(name)”?" }
    public static var remove: String { zh ? "移除" : "Remove" }
    public static var language: String { zh ? "語言" : "Language" }
    public static var languageAuto: String { zh ? "自動" : "Automatic" }
    public static var launchAtLogin: String { zh ? "登入時啟動" : "Launch at login" }
    public static var quit: String { zh ? "結束 Clamshell" : "Quit Clamshell" }
    public static func version(_ v: String) -> String { zh ? "版本 \(v)" : "Version \(v)" }

    // First-run consent
    public static var installTitle: String { zh ? "要讓 Clamshell 連上 Claude Code 嗎？" : "Connect Clamshell to Claude Code?" }
    public static var installBody: String {
        zh ? "Clamshell 需要在 ~/.claude/settings.json 加入幾個 hook，才能知道 Claude 什麼時候在工作。原檔會先備份，隨時可以從選單移除。"
           : "Clamshell adds a few hooks to ~/.claude/settings.json so it can tell when Claude is working. The file is backed up first, and you can remove the hooks from the menu at any time."
    }
    public static var installConfirm: String { zh ? "安裝" : "Install" }
    public static var installCancel: String { zh ? "稍後" : "Not now" }
    public static var removeHooks: String { zh ? "移除 Claude Code 連線…" : "Remove Claude Code hooks…" }
    public static var installHooks: String { zh ? "安裝 Claude Code 連線…" : "Install Claude Code hooks…" }
}
