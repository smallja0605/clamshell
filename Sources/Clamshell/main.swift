import Cocoa
import ClamshellCore

// Command line (no UI): Clamshell --make-pack <file.gif> "<name>" <output.clamshellmascot> [loop]
// Turns a GIF into a shareable mascot pack. "loop" treats the whole GIF as the typing loop (no opening/closing part).
if CommandLine.arguments.count >= 5, CommandLine.arguments[1] == "--make-pack" {
    let a = CommandLine.arguments
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("clamshell-pack-\(UUID().uuidString)")
    setenv("CLAMSHELL_HOME", scratch.path, 1)
    do {
        let info = try MascotLibrary.importGIF(at: URL(fileURLWithPath: a[2]), name: a[3],
                                               segmentation: a.count > 5 && a[5] == "loop" ? .loopOnly : .introAndOutro)
        try MascotLibrary.export(info, to: URL(fileURLWithPath: a[4]))
        print("\(info.manifest.name): \(MascotLibrary.frameURLs(in: info.directory).count) frames, intro \(info.manifest.introFrames), outro \(info.manifest.outroFrames), \(info.manifest.fps) fps")
        try? FileManager.default.removeItem(at: scratch)
        exit(0)
    } catch { print("failed: \(error)"); exit(1) }
}

// One instance at a time. The lock is held for the life of the process; the hook helper uses it to tell
// whether the app is running.
guard let lockFD = AppLock.acquire() else { exit(0) }
_ = lockFD

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.migrateFromOldIdentifier()
        controller = StatusController()
        if ProcessInfo.processInfo.environment["CLAMSHELL_SELFTEST"] != nil {
            let ok = controller?.runMenuSelfTest() ?? false
            print(ok ? "SELFTEST OK" : "SELFTEST FAILED")
            exit(ok ? 0 : 1)
        }
    }

    // Double-clicked mascot packs and GIFs dropped on the app icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        controller?.handleOpened(urls: urls)
    }

    // Re-opening the app (Spotlight, Finder) while it is hidden in idle: show the mascot briefly so the menu is reachable.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.peek()
        return true
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
