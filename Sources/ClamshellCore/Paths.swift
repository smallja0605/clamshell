import Foundation

/// Where Clamshell keeps its files. Everything lives under one directory so uninstalling is trivial,
/// and each location can be redirected with an environment variable so tests never touch real data.
public enum Paths {
    /// `~/.claude/clamshell` (override: `CLAMSHELL_HOME`).
    public static var home: URL {
        if let o = ProcessInfo.processInfo.environment["CLAMSHELL_HOME"], !o.isEmpty {
            return URL(fileURLWithPath: o, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/clamshell", isDirectory: true)
    }

    /// One JSON file per live Claude Code session.
    public static var sessions: URL { home.appendingPathComponent("sessions", isDirectory: true) }

    /// The app holds an exclusive `flock` on this file for as long as it runs; the hook helper tries the
    /// lock to learn whether the app is alive without any process-name matching.
    public static var appLock: URL { home.appendingPathComponent("app.lock") }

    /// Present after an explicit Quit so the helper does not immediately relaunch the app.
    public static var quitIntent: URL { home.appendingPathComponent("quit-intent") }

    /// Claude Code's user settings (override: `CLAMSHELL_CLAUDE_SETTINGS`).
    public static var claudeSettings: URL {
        if let o = ProcessInfo.processInfo.environment["CLAMSHELL_CLAUDE_SETTINGS"], !o.isEmpty {
            return URL(fileURLWithPath: o)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    public static func ensureDirectories() {
        try? FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    }
}
