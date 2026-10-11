import XCTest
@testable import ClamshellCore

final class HookRunnerTests: XCTestCase {
    var home: URL!
    var sessions: URL { home.appendingPathComponent("sessions") }
    let env = HookEnvironment(entrypoint: "cli", terminal: "Apple_Terminal", parentPID: getpid())

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("clamshell-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        setenv("CLAMSHELL_HOME", home.path, 1)
    }

    override func tearDown() { unsetenv("CLAMSHELL_HOME") }

    private func fire(_ e: HookEvent, _ json: String, at now: Double) {
        HookRunner.run(event: e, input: Data(json.utf8), env: env, sessionsDir: sessions, now: now, launchApp: false)
    }

    func testAFullTurnThroughTheRealRunner() {
        fire(.start, #"{"session_id":"abc","cwd":"/w/demo"}"#, at: 100)
        XCTAssertEqual(SessionFiles.read(id: "abc", in: sessions)?.phase, .idle)
        fire(.prompt, #"{"session_id":"abc","cwd":"/w/demo"}"#, at: 110)
        fire(.pre, #"{"session_id":"abc","tool_name":"Edit"}"#, at: 115)
        let mid = SessionFiles.read(id: "abc", in: sessions)
        XCTAssertEqual(mid?.phase, .tool); XCTAssertEqual(mid?.tool, "Edit"); XCTAssertEqual(mid?.project, "demo")
        fire(.stop, #"{"session_id":"abc"}"#, at: 130)
        let done = SessionFiles.read(id: "abc", in: sessions)
        XCTAssertEqual(done?.phase, .done); XCTAssertEqual(done?.lastTurnSeconds, 20)
        fire(.end, #"{"session_id":"abc"}"#, at: 140)
        XCTAssertNil(SessionFiles.read(id: "abc", in: sessions))
    }

    func testGarbageInputNeverCrashes() {
        fire(.prompt, "this is not json", at: 1)
        XCTAssertEqual(SessionFiles.read(id: "unknown", in: sessions)?.phase, .thinking)
        fire(.stop, "", at: 2)
    }

    func testSessionStartClearsTheQuitMarker() throws {
        try Data().write(to: Paths.quitIntent)
        fire(.start, #"{"session_id":"abc"}"#, at: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: Paths.quitIntent.path))
    }

    func testAppLockIsExclusive() {
        XCTAssertFalse(AppLock.isAppRunning())
        let fd = AppLock.acquire()
        XCTAssertNotNil(fd)
        XCTAssertTrue(AppLock.isAppRunning())
        XCTAssertNil(AppLock.acquire(), "a second instance must not get the lock")
        close(fd!)
        XCTAssertFalse(AppLock.isAppRunning())
    }
}
