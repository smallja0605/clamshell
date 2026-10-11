import Cocoa
import ClamshellCore

/// Brings the app a session is running in to the front when its menu row is clicked.
/// (Focusing the exact window or tab would need Automation permission, so this stops at the app.)
enum TerminalActivator {
    private static let terminals: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "vscode": "com.microsoft.VSCode",
        "WezTerm": "com.github.wez.wezterm",
        "ghostty": "com.mitchellh.ghostty",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "Hyper": "co.zeit.hyper",
        "Alacritty": "org.alacritty",
        "kitty": "net.kovidgoyal.kitty",
        "Tabby": "org.tabby",
    ]

    static func bundleID(for record: SessionRecord) -> String? {
        if record.entrypoint == "claude-desktop" { return "com.anthropic.claudefordesktop" }
        return terminals[record.terminal]
    }

    static func activate(_ record: SessionRecord) {
        guard let id = bundleID(for: record) else { return }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            running.activate(options: [.activateAllWindows])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
