import Foundation

/// Adds and removes Clamshell's hooks in Claude Code's settings.json, leaving everything else untouched.
public enum HookInstaller {
    public enum InstallError: Error { case unreadableSettings }

    static let seconds = 5   // hooks must never hold Claude up

    public static func command(helper: String, event: HookEvent) -> String {
        "'" + helper.replacingOccurrences(of: "'", with: "'\\''") + "' " + event.rawValue
    }

    static func isOurs(_ command: String) -> Bool { command.contains(AppInfo.helperName) }

    private static func hookEntries(_ value: Any?) -> [[String: Any]] { (value as? [[String: Any]]) ?? [] }

    /// `settings` with every Clamshell hook removed (and emptied containers dropped).
    public static func stripped(_ settings: [String: Any]) -> [String: Any] {
        var out = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return out }
        for (event, value) in hooks {
            let kept: [[String: Any]] = hookEntries(value).compactMap { entry in
                var e = entry
                let inner = hookEntries(entry["hooks"]).filter { !isOurs(($0["command"] as? String) ?? "") }
                if inner.isEmpty { return nil }
                e["hooks"] = inner
                return e
            }
            if kept.isEmpty { hooks[event] = nil } else { hooks[event] = kept }
        }
        out["hooks"] = hooks.isEmpty ? nil : hooks
        return out
    }

    /// `settings` with Clamshell's hooks (re)added, pointing at `helper`.
    public static func merged(_ settings: [String: Any], helper: String) -> [String: Any] {
        var out = stripped(settings)
        var hooks = (out["hooks"] as? [String: Any]) ?? [:]
        for event in HookEvent.allCases {
            var list = hookEntries(hooks[event.claudeName])
            var entry: [String: Any] = ["hooks": [["type": "command", "command": command(helper: helper, event: event), "timeout": seconds]]]
            if event.usesMatcher { entry["matcher"] = "*" }
            list.append(entry)
            hooks[event.claudeName] = list
        }
        out["hooks"] = hooks
        return out
    }

    /// True when every event already points at exactly this helper path.
    public static func isInstalled(_ settings: [String: Any], helper: String) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return HookEvent.allCases.allSatisfy { event in
            hookEntries(hooks[event.claudeName]).contains { entry in
                hookEntries(entry["hooks"]).contains { ($0["command"] as? String) == command(helper: helper, event: event) }
            }
        }
    }

    public static func hasAnyOfOurs(_ settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { v in
            hookEntries(v).contains { hookEntries($0["hooks"]).contains { isOurs(($0["command"] as? String) ?? "") } }
        }
    }

    // MARK: file level

    public static func load(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw InstallError.unreadableSettings }
        return obj
    }

    static func save(_ settings: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (data + Data("\n".utf8)).write(to: url, options: .atomic)
    }

    /// Backs the file up once (`settings.json.bak-clamshell`), then writes the merged settings.
    public static func install(helper: String, settingsURL: URL = Paths.claudeSettings) throws {
        let current = try load(settingsURL)
        let backup = settingsURL.appendingPathExtension("bak-clamshell")
        if FileManager.default.fileExists(atPath: settingsURL.path), !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.copyItem(at: settingsURL, to: backup)
        }
        try save(merged(current, helper: helper), to: settingsURL)
    }

    public static func uninstall(settingsURL: URL = Paths.claudeSettings) throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        try save(stripped(try load(settingsURL)), to: settingsURL)
    }

    public static func hasAnyOfOurs(settingsURL: URL = Paths.claudeSettings) -> Bool {
        guard let s = try? load(settingsURL) else { return false }
        return hasAnyOfOurs(s)
    }

    public static func isInstalled(helper: String, settingsURL: URL = Paths.claudeSettings) -> Bool {
        guard let s = try? load(settingsURL) else { return false }
        return isInstalled(s, helper: helper)
    }
}
