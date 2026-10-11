import XCTest
@testable import ClamshellCore

final class HookEngineTests: XCTestCase {
    let env = HookEnvironment(entrypoint: "cli", terminal: "iTerm.app", parentPID: 4242)

    private func apply(_ e: HookEvent, _ p: HookPayload, _ prev: SessionRecord?, at now: Double = 1000) -> SessionRecord {
        guard case .write(let r) = reduce(event: e, payload: p, previous: prev, env: env, now: now) else {
            XCTFail("expected a write"); return SessionRecord(id: "x")
        }
        return r
    }

    func testPromptStartsATurn() {
        let r = apply(.prompt, HookPayload(session_id: "s1", cwd: "/work/demo"), nil)
        XCTAssertEqual(r.phase, .thinking)
        XCTAssertEqual(r.turnStartedAt, 1000)
        XCTAssertEqual(r.project, "demo")
        XCTAssertEqual(r.pid, 4242)
        XCTAssertEqual(r.terminal, "iTerm.app")
    }

    func testToolThenPostKeepsTheTurnClock() {
        var r = apply(.prompt, HookPayload(session_id: "s1"), nil, at: 1000)
        r = apply(.pre, HookPayload(session_id: "s1", tool_name: "Bash"), r, at: 1005)
        XCTAssertEqual(r.phase, .tool); XCTAssertEqual(r.tool, "Bash"); XCTAssertEqual(r.turnStartedAt, 1000)
        r = apply(.post, HookPayload(session_id: "s1"), r, at: 1010)
        XCTAssertEqual(r.phase, .thinking); XCTAssertEqual(r.tool, ""); XCTAssertEqual(r.turnStartedAt, 1000)
    }

    func testStopRecordsTurnLength() {
        var r = apply(.prompt, HookPayload(session_id: "s1"), nil, at: 1000)
        r = apply(.stop, HookPayload(session_id: "s1"), r, at: 1042)
        XCTAssertEqual(r.phase, .done); XCTAssertEqual(r.lastTurnSeconds, 42); XCTAssertEqual(r.turnStartedAt, 0)
    }

    func testOnlyPermissionNotificationsCount() {
        let idle = apply(.start, HookPayload(session_id: "s1"), nil)
        XCTAssertEqual(reduce(event: .notify, payload: HookPayload(session_id: "s1", message: "Claude is waiting for your input"),
                              previous: idle, env: env, now: 5), .ignore)
        let r = apply(.notify, HookPayload(session_id: "s1", message: "Claude needs your permission to use Bash"), idle)
        XCTAssertEqual(r.phase, .permission)
        let t = apply(.notify, HookPayload(session_id: "s1", notification_type: "permission_prompt"), idle)
        XCTAssertEqual(t.phase, .permission)
    }

    func testSessionEndRemoves() {
        XCTAssertEqual(reduce(event: .end, payload: HookPayload(session_id: "abc"), previous: nil, env: env, now: 1), .remove("abc"))
    }

    func testSessionIDIsSanitised() {
        XCTAssertEqual(sanitizedSessionID("../../etc/passwd"), "....etcpasswd")
        XCTAssertEqual(sanitizedSessionID(nil), "unknown")
        XCTAssertEqual(sanitizedSessionID(String(repeating: "a", count: 200)).count, 64)
    }

    func testToolNamesMapToStatuses() {
        XCTAssertEqual(StatusKind.forTool("Bash"), .command)
        XCTAssertEqual(StatusKind.forTool("Grep"), .searching)
        XCTAssertEqual(StatusKind.forTool("mcp__github__create_issue"), .usingTool)
        XCTAssertEqual(StatusKind.forTool(""), .working)
    }
}
