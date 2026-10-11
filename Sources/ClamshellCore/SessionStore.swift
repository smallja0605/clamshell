import Foundation

/// Reads the facts the store needs about a transcript file. A protocol so tests can fake it.
public protocol TranscriptProbing {
    /// Modification time (unix seconds), 0 if the file is missing.
    func modified(_ path: String) -> Double
    /// True if the newest user/assistant message is Claude Code's "request interrupted" marker.
    func endsWithInterruption(_ path: String) -> Bool
}

/// Reads only the tail of a transcript. Results are cached by modification time, so an idle
/// transcript costs one `stat` per refresh.
public final class FileTranscriptProbe: TranscriptProbing {
    private var cache: [String: (mtime: Double, interrupted: Bool)] = [:]
    public init() {}

    public func modified(_ path: String) -> Double {
        guard !path.isEmpty,
              let d = try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
        else { return 0 }
        return d.timeIntervalSince1970
    }

    public func endsWithInterruption(_ path: String) -> Bool {
        let m = modified(path)
        if m == 0 { return false }
        if let c = cache[path], c.mtime == m { return c.interrupted }
        let result = Self.tailEndsWithInterruption(path)
        cache[path] = (m, result)
        return result
    }

    static func tailEndsWithInterruption(_ path: String, tailBytes: Int = 96 * 1024) -> Bool {
        guard let h = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? h.seek(toOffset: start)
        guard let data = try? h.readToEnd(), let text = String(data: data, encoding: .utf8) else { return false }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }          // first line is probably cut in half
        for line in lines.reversed() {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let type = obj["type"] as? String, type == "user" || type == "assistant" else { continue }
            return Self.messageText(obj).hasPrefix("[Request interrupted by user")
        }
        return false
    }

    private static func messageText(_ obj: [String: Any]) -> String {
        guard let msg = obj["message"] as? [String: Any] else { return "" }
        if let s = msg["content"] as? String { return s }
        if let parts = msg["content"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }
}

/// A session as the UI sees it.
public struct LiveSession: Equatable {
    public var record: SessionRecord
    /// What to show: `.done` collapses to `.idle`, and a frozen working state is corrected to `.idle`.
    public var phase: Phase
    public var branch: String
    public var displayName: String
    public var id: String { record.id }
}

public func isProcessAlive(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
}

public final class SessionStore {
    private let directory: URL
    private let clock: () -> Double
    private let isAlive: (Int32) -> Bool
    private let transcripts: TranscriptProbing
    private var parsed: [String: (mtime: Date, record: SessionRecord)] = [:]
    private var headCache: [String: String] = [:]   // cwd -> HEAD file path, "" = not a repository

    /// A working phase older than this without any sign of life is treated as a missed Stop.
    public var thinkingLimit: Double = 5 * 60
    public var toolLimit: Double = 30 * 60
    /// Records without a known pid are dropped once they have been quiet this long.
    public var orphanLimit: Double = 15 * 60

    public init(directory: URL = Paths.sessions,
                clock: @escaping () -> Double = { Date().timeIntervalSince1970 },
                isAlive: @escaping (Int32) -> Bool = isProcessAlive,
                transcripts: TranscriptProbing = FileTranscriptProbe()) {
        self.directory = directory; self.clock = clock; self.isAlive = isAlive; self.transcripts = transcripts
    }

    /// Re-reads the sessions directory. Cheap enough to call a few times per second.
    public func reload() -> [LiveSession] {
        let fm = FileManager.default
        let now = clock()
        let names = ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".json") }
        var records: [SessionRecord] = []
        var seen = Set<String>()

        for name in names {
            let url = directory.appendingPathComponent(name)
            seen.insert(name)
            let mtime = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
            var record: SessionRecord
            if let c = parsed[name], c.mtime == mtime {
                record = c.record
            } else if let data = try? Data(contentsOf: url), let r = try? JSONDecoder().decode(SessionRecord.self, from: data) {
                record = r
                parsed[name] = (mtime, r)
            } else {
                continue   // half-written or foreign file
            }
            // A session lives exactly as long as its `claude` process.
            let dead = record.pid > 0 ? !isAlive(record.pid) : (now - record.updatedAt > orphanLimit)
            if dead { try? fm.removeItem(at: url); parsed[name] = nil; continue }
            records.append(record)
        }
        for k in parsed.keys where !seen.contains(k) { parsed[k] = nil }

        // Same-named projects get their parent folder as a qualifier so the rows stay distinguishable.
        let dirsByProject = Dictionary(grouping: records.filter { !$0.cwd.isEmpty }, by: \.project)
            .mapValues { Set($0.map(\.cwd)) }

        return records.map { r in
            var name = r.project
            if !r.cwd.isEmpty, (dirsByProject[r.project]?.count ?? 0) > 1 {
                let parent = ((r.cwd as NSString).deletingLastPathComponent as NSString).lastPathComponent
                if !parent.isEmpty { name = parent + "/" + r.project }
            }
            return LiveSession(record: r, phase: effectivePhase(r, now: now), branch: branch(forCwd: r.cwd), displayName: name)
        }
    }

    func effectivePhase(_ r: SessionRecord, now: Double) -> Phase {
        switch r.phase {
        case .idle, .done:
            return .idle
        case .thinking, .tool, .permission:
            // Esc fires no hook, so the transcript is the only witness of an interrupted turn. It only counts
            // if the transcript was written after our last hook event (a prompt can race its own line).
            if !r.transcript.isEmpty,
               transcripts.modified(r.transcript) >= r.updatedAt,
               transcripts.endsWithInterruption(r.transcript) { return .idle }
            let quietSince = max(r.updatedAt, transcripts.modified(r.transcript))
            switch r.phase {
            case .thinking where now - quietSince > thinkingLimit: return .idle
            case .tool where now - quietSince > toolLimit: return .idle
            default: return r.phase
            }
        }
    }

    // MARK: git branch

    /// Branch name (or short SHA when detached) of `cwd`, "" outside a repository. Reads `.git/HEAD` directly.
    func branch(forCwd cwd: String) -> String {
        guard !cwd.isEmpty else { return "" }
        if headCache[cwd] == nil { headCache[cwd] = Self.findHead(from: cwd) ?? "" }
        guard let head = headCache[cwd], !head.isEmpty,
              let text = try? String(contentsOfFile: head, encoding: .utf8) else { return "" }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref: refs/heads/") { return String(line.dropFirst("ref: refs/heads/".count)) }
        return line.count >= 7 ? String(line.prefix(7)) : ""
    }

    /// Forget "not a repository" answers so a freshly `git init`-ed folder is noticed.
    public func rescanRepositories() { headCache = headCache.filter { !$0.value.isEmpty } }

    private static func findHead(from cwd: String) -> String? {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: cwd)
        for _ in 0..<12 {
            let dot = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dot.path, isDirectory: &isDir) {
                if isDir.boolValue { return dot.appendingPathComponent("HEAD").path }
                // worktree / submodule: ".git" is a file reading "gitdir: <path>"
                if let t = try? String(contentsOf: dot, encoding: .utf8), t.hasPrefix("gitdir:") {
                    let p = t.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                    let base = p.hasPrefix("/") ? URL(fileURLWithPath: p) : dir.appendingPathComponent(p)
                    return base.appendingPathComponent("HEAD").path
                }
                return nil
            }
            let parent = dir.deletingLastPathComponent()
            if parent == dir { break }
            dir = parent
        }
        return nil
    }
}

/// Which session the menu-bar mascot reports on: a permission wait beats plain work; ties go to the freshest.
public func leadSession(_ sessions: [LiveSession]) -> LiveSession? {
    func rank(_ p: Phase) -> Int { p == .permission ? 2 : (p.isWorking ? 1 : 0) }
    return sessions.max { a, b in
        let ra = rank(a.phase), rb = rank(b.phase)
        return ra == rb ? a.record.updatedAt < b.record.updatedAt : ra < rb
    }
}

/// Spots turns that just finished normally (for the completion chime). Interrupted turns do not count.
public struct CompletionDetector {
    private var lastSeen: [String: Phase] = [:]
    public init() {}

    /// Returns the duration (seconds) of every turn that finished since the previous call.
    public mutating func observe(_ sessions: [LiveSession]) -> [Double] {
        var finished: [Double] = []
        var next: [String: Phase] = [:]
        for s in sessions {
            let was = lastSeen[s.id]
            if s.record.phase == .done, was != nil, was != .idle { finished.append(s.record.lastTurnSeconds) }
            // remember the *record* phase so done→done does not repeat
            next[s.id] = s.record.phase == .done ? .idle : s.phase
        }
        lastSeen = next
        return finished
    }
}
