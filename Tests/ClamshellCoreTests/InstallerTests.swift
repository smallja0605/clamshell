import XCTest
@testable import ClamshellCore

final class InstallerTests: XCTestCase {
    let helper = "/Applications/Clamshell.app/Contents/MacOS/clamshell-hook"

    func testMergeKeepsForeignHooksAndSettings() {
        let original: [String: Any] = [
            "model": "opus",
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]],
        ]
        let merged = HookInstaller.merged(original, helper: helper)
        XCTAssertEqual(merged["model"] as? String, "opus")
        let stop = (merged["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        XCTAssertEqual(stop.count, 2)
        XCTAssertTrue(HookInstaller.isInstalled(merged, helper: helper))
    }

    func testMergeIsIdempotent() {
        let once = HookInstaller.merged([:], helper: helper)
        let twice = HookInstaller.merged(once, helper: helper)
        let a = try! JSONSerialization.data(withJSONObject: once, options: .sortedKeys)
        let b = try! JSONSerialization.data(withJSONObject: twice, options: .sortedKeys)
        XCTAssertEqual(a, b)
    }

    func testMovedAppIsDetectedAsNotInstalled() {
        let merged = HookInstaller.merged([:], helper: helper)
        XCTAssertFalse(HookInstaller.isInstalled(merged, helper: "/Users/me/Clamshell.app/Contents/MacOS/clamshell-hook"))
    }

    func testStripRemovesOnlyOurs() {
        let original: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]]]
        let stripped = HookInstaller.stripped(HookInstaller.merged(original, helper: helper))
        XCTAssertFalse(HookInstaller.hasAnyOfOurs(stripped))
        let hooks = stripped["hooks"] as! [String: Any]
        XCTAssertEqual(Array(hooks.keys), ["Stop"])
    }

    func testStripOfEmptySettingsDropsHooksKey() {
        let stripped = HookInstaller.stripped(HookInstaller.merged([:], helper: helper))
        XCTAssertNil(stripped["hooks"])
    }

    func testPathsWithSpacesAndQuotesAreQuoted() {
        XCTAssertEqual(HookInstaller.command(helper: "/a b/it's/clamshell-hook", event: .stop),
                       "'/a b/it'\\''s/clamshell-hook' stop")
    }

    func testFileRoundTripAndBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clamshell-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")
        try Data(#"{"theme":"dark"}"#.utf8).write(to: url)
        try HookInstaller.install(helper: helper, settingsURL: url)
        XCTAssertTrue(HookInstaller.isInstalled(helper: helper, settingsURL: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("bak-clamshell").path))
        try HookInstaller.uninstall(settingsURL: url)
        XCTAssertFalse(HookInstaller.isInstalled(helper: helper, settingsURL: url))
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        XCTAssertEqual(after["theme"] as? String, "dark")
    }

    func testCorruptSettingsAreNeverOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clamshell-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")
        try Data("not json {".utf8).write(to: url)
        XCTAssertThrowsError(try HookInstaller.install(helper: helper, settingsURL: url))
        XCTAssertEqual(try String(contentsOf: url), "not json {")
    }
}
