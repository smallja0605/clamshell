import Foundation

/// The body of `clamshell-hook <event>`: read the payload from stdin, advance the session's record, make
/// sure the app is running. Lives in the library so it can be tested; the executable is a one-line wrapper.
public enum HookRunner {
    /// Reads stdin without ever hanging: gives up after `timeout` seconds of silence.
    public static func readStandardInput(timeout: TimeInterval = 1.0) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var p = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            let ready = poll(&p, 1, 100)
            if ready > 0 {
                let n = read(STDIN_FILENO, &buffer, buffer.count)
                if n <= 0 { break }               // EOF
                data.append(buffer, count: n)
            } else if ready < 0 && errno != EINTR { break }
        }
        return data
    }

    public static func run(event: HookEvent, input: Data, env: HookEnvironment,
                           sessionsDir: URL = Paths.sessions, now: Double = Date().timeIntervalSince1970,
                           launchApp: Bool = true) {
        let payload = (try? JSONDecoder().decode(HookPayload.self, from: input)) ?? HookPayload()
        let id = sanitizedSessionID(payload.session_id)
        let previous = SessionFiles.read(id: id, in: sessionsDir)

        if event == .start { try? FileManager.default.removeItem(at: Paths.quitIntent) }

        switch reduce(event: event, payload: payload, previous: previous, env: env, now: now) {
        case .write(let record): try? SessionFiles.write(record, in: sessionsDir)
        case .remove(let id): SessionFiles.remove(id: id, in: sessionsDir)
        case .ignore: break
        }
        if launchApp, event != .end { launchAppIfNeeded() }
    }

    /// A session with no app to show it relaunches the app, unless the user explicitly quit it.
    static func launchAppIfNeeded() {
        guard !AppLock.isAppRunning(), !FileManager.default.fileExists(atPath: Paths.quitIntent.path) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-g", "-b", AppInfo.bundleID]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
