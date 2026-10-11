import Foundation

/// What Claude is doing in one session, as far as the hooks can tell.
public enum Phase: String, Codable, Equatable {
    case idle        // session open, nothing running
    case thinking    // a prompt was submitted / a tool just returned
    case tool        // a tool call is in flight
    case permission  // waiting for the user to allow something
    case done        // the last turn finished

    public var isWorking: Bool { self == .thinking || self == .tool }
}

/// The on-disk record for one session (`sessions/<id>.json`). Written by `clamshell-hook`, read by the app.
public struct SessionRecord: Codable, Equatable {
    public var id: String
    public var phase: Phase
    public var tool: String            // tool name while `phase == .tool`, else ""
    public var project: String         // basename of the working directory
    public var cwd: String
    public var transcript: String      // path of the conversation transcript, used for interrupt detection
    public var entrypoint: String      // CLAUDE_CODE_ENTRYPOINT: "cli", "claude-desktop", …
    public var terminal: String        // TERM_PROGRAM, used to bring the right app forward
    public var pid: Int32              // the `claude` process; 0 when unknown
    public var turnStartedAt: Double   // unix seconds the current turn began; 0 when no turn is running
    public var lastTurnSeconds: Double // how long the most recent finished turn took
    public var updatedAt: Double

    public init(id: String, phase: Phase = .idle, tool: String = "", project: String = "", cwd: String = "",
                transcript: String = "", entrypoint: String = "", terminal: String = "", pid: Int32 = 0,
                turnStartedAt: Double = 0, lastTurnSeconds: Double = 0, updatedAt: Double = 0) {
        self.id = id; self.phase = phase; self.tool = tool; self.project = project; self.cwd = cwd
        self.transcript = transcript; self.entrypoint = entrypoint; self.terminal = terminal; self.pid = pid
        self.turnStartedAt = turnStartedAt; self.lastTurnSeconds = lastTurnSeconds; self.updatedAt = updatedAt
    }
}

public func sanitizedSessionID(_ raw: String?) -> String {
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-")
    let cleaned = String((raw ?? "").filter { allowed.contains($0) }.prefix(64))
    return cleaned.isEmpty ? "unknown" : cleaned
}
