import Foundation

/// The hook events Clamshell subscribes to, under the short names the installer passes on the command line.
public enum HookEvent: String, CaseIterable {
    case start            // SessionStart
    case end              // SessionEnd
    case prompt           // UserPromptSubmit
    case pre              // PreToolUse
    case post             // PostToolUse
    case notify           // Notification
    case permissionRequest = "permreq"  // PermissionRequest
    case stop             // Stop

    /// The name Claude Code uses for this event in settings.json.
    public var claudeName: String {
        switch self {
        case .start: return "SessionStart"
        case .end: return "SessionEnd"
        case .prompt: return "UserPromptSubmit"
        case .pre: return "PreToolUse"
        case .post: return "PostToolUse"
        case .notify: return "Notification"
        case .permissionRequest: return "PermissionRequest"
        case .stop: return "Stop"
        }
    }

    /// Tool events are registered with a catch-all matcher; the rest take none.
    public var usesMatcher: Bool { self == .pre || self == .post || self == .permissionRequest }
}

/// The subset of the hook's stdin JSON we care about.
public struct HookPayload: Decodable {
    public var session_id: String?
    public var cwd: String?
    public var tool_name: String?
    public var transcript_path: String?
    public var message: String?
    public var notification_type: String?

    public init(session_id: String? = nil, cwd: String? = nil, tool_name: String? = nil,
                transcript_path: String? = nil, message: String? = nil, notification_type: String? = nil) {
        self.session_id = session_id; self.cwd = cwd; self.tool_name = tool_name
        self.transcript_path = transcript_path; self.message = message; self.notification_type = notification_type
    }
}

/// Facts about the process environment the hook runs in.
public struct HookEnvironment {
    public var entrypoint: String
    public var terminal: String
    public var parentPID: Int32
    public init(entrypoint: String = "", terminal: String = "", parentPID: Int32 = 0) {
        self.entrypoint = entrypoint; self.terminal = terminal; self.parentPID = parentPID
    }
}

public enum HookOutcome: Equatable {
    case write(SessionRecord)
    case remove(String)   // session id
    case ignore
}

/// Pure state machine: (event, previous record) → new record. Kept free of I/O so it is trivially testable.
public func reduce(event: HookEvent, payload: HookPayload, previous: SessionRecord?,
                   env: HookEnvironment, now: Double) -> HookOutcome {
    let id = sanitizedSessionID(payload.session_id)
    if event == .end { return .remove(id) }

    var r = previous ?? SessionRecord(id: id)
    r.id = id
    if let cwd = payload.cwd, !cwd.isEmpty {
        r.cwd = cwd
        r.project = (cwd as NSString).lastPathComponent
    }
    if let t = payload.transcript_path, !t.isEmpty { r.transcript = t }
    if !env.entrypoint.isEmpty { r.entrypoint = env.entrypoint }
    if !env.terminal.isEmpty { r.terminal = env.terminal }
    if env.parentPID > 0 { r.pid = env.parentPID }
    r.updatedAt = now

    switch event {
    case .start:
        // A fresh or resumed session starts at rest; this also clears a frozen state left by a crash.
        r.phase = .idle; r.tool = ""; r.turnStartedAt = 0
    case .prompt:
        r.phase = .thinking; r.tool = ""; r.turnStartedAt = now
    case .pre:
        r.phase = .tool; r.tool = payload.tool_name ?? ""
        if r.turnStartedAt == 0 { r.turnStartedAt = now }
    case .post:
        r.phase = .thinking; r.tool = ""
        if r.turnStartedAt == 0 { r.turnStartedAt = now }
    case .notify:
        // Only permission prompts matter. Other notifications (e.g. "waiting for your input") are noise.
        let m = (payload.message ?? "").lowercased()
        let isPermission = payload.notification_type == "permission_prompt"
            || m.contains("permission") || m.contains("approve") || m.contains("allow")
        guard isPermission else { return .ignore }
        r.phase = .permission; r.tool = ""
    case .permissionRequest:
        r.phase = .permission; r.tool = ""
    case .stop:
        if r.turnStartedAt > 0 { r.lastTurnSeconds = max(0, now - r.turnStartedAt) }
        r.phase = .done; r.tool = ""; r.turnStartedAt = 0
    case .end:
        break
    }
    return .write(r)
}
