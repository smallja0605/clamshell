import XCTest
@testable import ClamshellCore

final class FakeTranscripts: TranscriptProbing {
    var mtimes: [String: Double] = [:]
    var interrupted: Set<String> = []
    func modified(_ path: String) -> Double { mtimes[path] ?? 0 }
    func endsWithInterruption(_ path: String) -> Bool { interrupted.contains(path) }
}

final class SessionStoreTests: XCTestCase {
    var dir: URL!
    var now = 10_000.0
    var alive = Set<Int32>([100, 200])
    let fake = FakeTranscripts()

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("clamshell-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func store() -> SessionStore {
        SessionStore(directory: dir, clock: { self.now }, isAlive: { self.alive.contains($0) }, transcripts: fake)
    }

    private func put(_ r: SessionRecord) { try! SessionFiles.write(r, in: dir) }

    func testDeadProcessIsReapedAndItsFileRemoved() {
        put(SessionRecord(id: "a", phase: .thinking, pid: 999, updatedAt: now))
        XCTAssertTrue(store().reload().isEmpty)
        XCTAssertNil(SessionFiles.read(id: "a", in: dir))
    }

    func testDoneCollapsesToIdle() {
        put(SessionRecord(id: "a", phase: .done, pid: 100, updatedAt: now))
        XCTAssertEqual(store().reload().first?.phase, .idle)
    }

    func testFrozenThinkingTimesOut() {
        put(SessionRecord(id: "a", phase: .thinking, pid: 100, updatedAt: now - 400))
        XCTAssertEqual(store().reload().first?.phase, .idle)
        put(SessionRecord(id: "a", phase: .thinking, pid: 100, updatedAt: now - 100))
        XCTAssertEqual(store().reload().first?.phase, .thinking)
    }

    func testLongToolCallSurvivesLongerThanThinking() {
        put(SessionRecord(id: "a", phase: .tool, tool: "Bash", pid: 100, updatedAt: now - 20 * 60))
        XCTAssertEqual(store().reload().first?.phase, .tool)
    }

    func testTranscriptActivityKeepsThinkingAlive() {
        put(SessionRecord(id: "a", phase: .thinking, transcript: "/t", pid: 100, updatedAt: now - 400))
        fake.mtimes["/t"] = now - 5
        XCTAssertEqual(store().reload().first?.phase, .thinking)
    }

    func testInterruptionEndsTheTurn() {
        put(SessionRecord(id: "a", phase: .thinking, transcript: "/t", pid: 100, updatedAt: now - 10))
        fake.mtimes["/t"] = now - 2
        fake.interrupted = ["/t"]
        XCTAssertEqual(store().reload().first?.phase, .idle)
    }

    func testInterruptionMarkerOlderThanTheLastHookIsIgnored() {
        // a new prompt raced ahead of its own transcript line
        put(SessionRecord(id: "a", phase: .thinking, transcript: "/t", pid: 100, updatedAt: now - 1))
        fake.mtimes["/t"] = now - 30
        fake.interrupted = ["/t"]
        XCTAssertEqual(store().reload().first?.phase, .thinking)
    }

    func testSameNamedProjectsGetAParentQualifier() {
        put(SessionRecord(id: "a", project: "site", cwd: "/work/site", pid: 100, updatedAt: now))
        put(SessionRecord(id: "b", project: "site", cwd: "/tmp/site", pid: 200, updatedAt: now))
        let names = Set(store().reload().map(\.displayName))
        XCTAssertEqual(names, ["work/site", "tmp/site"])
    }

    func testLeadPrefersPermissionThenFreshestWork() {
        func s(_ id: String, _ p: Phase, _ t: Double) -> LiveSession {
            LiveSession(record: SessionRecord(id: id, phase: p, updatedAt: t), phase: p, branch: "", displayName: id)
        }
        XCTAssertEqual(leadSession([s("a", .thinking, 5), s("b", .permission, 1), s("c", .thinking, 9)])?.id, "b")
        XCTAssertEqual(leadSession([s("a", .thinking, 5), s("c", .tool, 9)])?.id, "c")
        XCTAssertEqual(leadSession([s("a", .idle, 5)])?.id, "a")
        XCTAssertNil(leadSession([]))
    }

    func testBranchIsReadFromHead() throws {
        let repo = dir.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "ref: refs/heads/feature/x\n".write(to: repo.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        put(SessionRecord(id: "a", project: "repo", cwd: repo.path, pid: 100, updatedAt: now))
        XCTAssertEqual(store().reload().first?.branch, "feature/x")
    }
}

final class CompletionDetectorTests: XCTestCase {
    private func s(_ phase: Phase, rec: Phase? = nil, secs: Double = 0) -> LiveSession {
        LiveSession(record: SessionRecord(id: "a", phase: rec ?? phase, lastTurnSeconds: secs), phase: phase, branch: "", displayName: "a")
    }

    func testChimesOnceWhenAWorkingTurnFinishes() {
        var d = CompletionDetector()
        XCTAssertEqual(d.observe([s(.thinking)]), [])
        XCTAssertEqual(d.observe([s(.idle, rec: .done, secs: 42)]), [42])
        XCTAssertEqual(d.observe([s(.idle, rec: .done, secs: 42)]), [])
    }

    func testNoChimeForAppStartingOnAnAlreadyFinishedSession() {
        var d = CompletionDetector()
        XCTAssertEqual(d.observe([s(.idle, rec: .done, secs: 9)]), [])
    }

    func testInterruptedTurnDoesNotChime() {
        var d = CompletionDetector()
        _ = d.observe([s(.thinking)])
        XCTAssertEqual(d.observe([s(.idle, rec: .thinking)]), [])
    }
}

final class TranscriptProbeTests: XCTestCase {
    private func write(_ lines: [String]) -> String {
        let p = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID().uuidString).jsonl").path
        try! (lines.joined(separator: "\n") + "\n").write(toFile: p, atomically: true, encoding: .utf8)
        return p
    }

    func testInterruptMarkerAsLastMessageEvenWithTrailingBookkeepingLines() {
        let p = write([
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"working"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#,
            #"{"type":"cost-state","totalCostUSD":1}"#,
        ])
        XCTAssertTrue(FileTranscriptProbe().endsWithInterruption(p))
    }

    func testNewerMessageAfterTheMarkerClearsIt() {
        let p = write([
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":"try again"}}"#,
        ])
        XCTAssertFalse(FileTranscriptProbe().endsWithInterruption(p))
    }

    func testToolUseVariantOfTheMarker() {
        let p = write([#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#])
        XCTAssertTrue(FileTranscriptProbe().endsWithInterruption(p))
    }

    func testMissingFileIsNotAnInterruption() {
        XCTAssertFalse(FileTranscriptProbe().endsWithInterruption("/nonexistent/file.jsonl"))
    }
}

final class StringsTests: XCTestCase {
    func testElapsedFormats() {
        Language.preference = .zh
        XCTAssertEqual(Strings.elapsed(43), "43秒"); XCTAssertEqual(Strings.elapsed(64), "1分4秒")
        Language.preference = .en
        XCTAssertEqual(Strings.elapsed(43), "43s"); XCTAssertEqual(Strings.elapsed(64), "1m 4s")
        Language.preference = .auto
    }

    func testStatusLabelsEndWithAnEllipsisExceptPermission() {
        Language.preference = .zh
        XCTAssertEqual(Strings.status(.thinking), "思考中…")
        XCTAssertEqual(Strings.status(.permission), "等待授權")
        Language.preference = .auto
    }
}
