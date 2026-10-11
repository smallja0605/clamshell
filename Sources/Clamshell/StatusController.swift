import Cocoa
import ServiceManagement
import ClamshellCore

/// Owns the status item, watches the sessions directory, and builds the menu.
final class StatusController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let mascot: MenuBarMascot
    private let store = SessionStore()
    private let chime = Chime()
    private var completions = CompletionDetector()
    private var sessions: [LiveSession] = []
    private var watcher: DispatchSourceFileSystemObject?
    private var timer: Timer?

    private let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    private let helperPath: String = {
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return exe.deletingLastPathComponent().appendingPathComponent(AppInfo.helperName).path
    }()
    private var hooksDisabledForTesting: Bool { ProcessInfo.processInfo.environment["CLAMSHELL_NO_INSTALL"] != nil }

    override init() {
        mascot = MenuBarMascot(item: statusItem, sprites: SpriteSet.load(SpriteSet.Source(raw: Preferences.mascotSource)))
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        Paths.ensureDirectories()
        try? FileManager.default.removeItem(at: Paths.quitIntent)
        watchSessionsDirectory()
        // The directory watcher is instant; this timer covers what it cannot see (process death, clocks).
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
        ensureHooks()
    }

    /// Called when the user opens the app again while it is running (e.g. from Spotlight).
    func peek() { mascot.peek(seconds: 10) }

    // MARK: state

    private func watchSessionsDirectory() {
        let fd = open(Paths.sessions.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in self?.refresh() }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    private func refresh() {
        sessions = store.reload()

        for seconds in completions.observe(sessions) {
            let minimum = Preferences.chimeMinimumSeconds
            if minimum >= 0, seconds >= minimum { chime.play() }
        }

        guard let lead = leadSession(sessions), lead.phase != .idle else {
            mascot.update(.init(working: false, template: Preferences.monochrome, alwaysVisible: Preferences.alwaysShow))
            return
        }
        let label = Preferences.showLabel ? Strings.status(StatusKind.of(lead)) : ""
        var clock: String? = nil
        if Preferences.showClock, lead.phase.isWorking, lead.record.turnStartedAt > 0 {
            clock = Strings.elapsed(max(0, Int(Date().timeIntervalSince1970 - lead.record.turnStartedAt)))
        }
        mascot.update(.init(working: true, label: label, clock: clock,
                            amber: lead.phase == .permission, template: Preferences.monochrome,
                            alwaysVisible: Preferences.alwaysShow))
        statusItem.button?.toolTip = rowTitle(lead)
    }

    // MARK: hooks

    private func ensureHooks() {
        guard !hooksDisabledForTesting else { return }
        if HookInstaller.isInstalled(helper: helperPath) { return }
        if Preferences.askedAboutHooks {
            // Already consented once; the app was probably moved, so point the hooks at the new location.
            if HookInstaller.hasAnyOfOurs() { installHooks() }
            return
        }
        DispatchQueue.main.async { [weak self] in self?.askToInstallHooks() }
    }

    private func askToInstallHooks() {
        Preferences.askedAboutHooks = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = Strings.installTitle
        alert.informativeText = Strings.installBody
        alert.addButton(withTitle: Strings.installConfirm)
        alert.addButton(withTitle: Strings.installCancel)
        if alert.runModal() == .alertFirstButtonReturn { installHooks() }
    }

    private func installHooks() {
        do { try HookInstaller.install(helper: helperPath) } catch {
            let a = NSAlert(error: error)
            a.runModal()
        }
    }

    @objc private func installHooksFromMenu() {
        Preferences.askedAboutHooks = true
        installHooks()
    }

    @objc private func removeHooksFromMenu() {
        try? HookInstaller.uninstall()
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        store.rescanRepositories()
        sessions = store.reload()
        menu.removeAllItems()
        actions.removeAll()   // safe here: the previous menu's actions have already run

        menu.addItem(sectionHeader(Strings.sessions))
        let ordered = sessions.sorted { $0.record.updatedAt > $1.record.updatedAt }
        if ordered.isEmpty {
            let empty = NSMenuItem(title: Strings.noSessions, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            if NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop").first != nil {
                let open = NSMenuItem(title: Strings.openClaude, action: #selector(openClaudeDesktop), keyEquivalent: "")
                open.target = self
                menu.addItem(open)
            }
        }
        for s in ordered {
            let item = NSMenuItem(title: rowTitle(s), action: #selector(sessionClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s.record
            item.image = dot(for: s.phase)
            item.attributedTitle = rowAttributed(s)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(sectionHeader(Strings.options))
        menu.addItem(toggle(Strings.showClock, Preferences.showClock) { Preferences.showClock = $0 })
        menu.addItem(toggle(Strings.showText, Preferences.showLabel) { Preferences.showLabel = $0 })
        menu.addItem(toggle(Strings.alwaysShow, Preferences.alwaysShow) { Preferences.alwaysShow = $0 })

        let color = NSMenuItem(title: Strings.color, action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        colorMenu.addItem(choice(Strings.colorOriginal, !Preferences.monochrome) { Preferences.monochrome = false })
        colorMenu.addItem(choice(Strings.colorSystem, Preferences.monochrome) { Preferences.monochrome = true })
        color.submenu = colorMenu
        menu.addItem(color)

        menu.addItem(mascotMenuItem())

        let sound = NSMenuItem(title: Strings.sound, action: nil, keyEquivalent: "")
        let soundMenu = NSMenu()
        let current = Preferences.chimeMinimumSeconds
        soundMenu.addItem(choice(Strings.soundOff, current < 0) { Preferences.chimeMinimumSeconds = -1 })
        soundMenu.addItem(choice(Strings.soundEvery, current == 0) { Preferences.chimeMinimumSeconds = 0 })
        for minutes in [1, 5, 15] {
            soundMenu.addItem(choice(Strings.soundAtLeast(minutes: minutes), current == Double(minutes * 60)) {
                Preferences.chimeMinimumSeconds = Double(minutes * 60)
            })
        }
        sound.submenu = soundMenu
        menu.addItem(sound)

        let lang = NSMenuItem(title: Strings.language, action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for (l, name) in [(Language.auto, Strings.languageAuto), (.zh, "繁體中文"), (.en, "English")] {
            langMenu.addItem(choice(name, Language.preference == l) { Language.preference = l })
        }
        lang.submenu = langMenu
        menu.addItem(lang)

        if Bundle.main.bundleURL.pathExtension == "app" {
            menu.addItem(toggle(Strings.launchAtLogin, SMAppService.mainApp.status == .enabled) { on in
                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
            })
        }

        menu.addItem(.separator())
        let installed = HookInstaller.isInstalled(helper: helperPath)
        let hooks = NSMenuItem(title: installed ? Strings.removeHooks : Strings.installHooks,
                               action: installed ? #selector(removeHooksFromMenu) : #selector(installHooksFromMenu), keyEquivalent: "")
        hooks.target = self
        menu.addItem(hooks)
        let ver = NSMenuItem(title: Strings.version(version), action: nil, keyEquivalent: "")
        ver.isEnabled = false
        menu.addItem(ver)
        let quit = NSMenuItem(title: Strings.quit, action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: mascots

    private func reloadMascot() {
        mascot.setSprites(SpriteSet.load(SpriteSet.Source(raw: Preferences.mascotSource)))
        mascot.peek(seconds: 5)   // show the new mascot straight away
    }

    private func mascotMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: Strings.mascot, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let current = Preferences.mascotSource
        sub.addItem(choice(Strings.mascotBuiltIn, current == "builtin") { [weak self] in
            Preferences.mascotSource = "builtin"; self?.reloadMascot()
        })
        for pack in MascotLibrary.bundled() {
            sub.addItem(choice(pack.name, current == "bundled:\(pack.id)") { [weak self] in
                Preferences.mascotSource = "bundled:\(pack.id)"; self?.reloadMascot()
            })
        }
        if SpriteSet.hasLegacy {
            sub.addItem(choice(Strings.mascotLegacy, current == "legacy") { [weak self] in
                Preferences.mascotSource = "legacy"; self?.reloadMascot()
            })
        }
        let packs = MascotLibrary.installed()
        for pack in packs {
            sub.addItem(choice(pack.name, current == "pack:\(pack.id)") { [weak self] in
                Preferences.mascotSource = "pack:\(pack.id)"; self?.reloadMascot()
            })
        }
        sub.addItem(.separator())
        sub.addItem(plain(Strings.mascotImport) { [weak self] in self?.importGIF(nil) })
        if let active = packs.first(where: { "pack:\($0.id)" == current }) {
            sub.addItem(plain(Strings.mascotExport) { [weak self] in self?.exportPack(active) })
        }
        if !packs.isEmpty {
            let remove = NSMenuItem(title: Strings.mascotRemove, action: nil, keyEquivalent: "")
            let removeMenu = NSMenu()
            for pack in packs { removeMenu.addItem(plain(pack.name) { [weak self] in self?.confirmRemove(pack) }) }
            remove.submenu = removeMenu
            sub.addItem(remove)
        }
        sub.addItem(plain(Strings.mascotReveal) {
            try? FileManager.default.createDirectory(at: MascotLibrary.directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(MascotLibrary.directory)
        })
        item.submenu = sub
        return item
    }

    private func plain(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let a = Action(on: false) { _ in run() }
        actions.append(a)
        let item = NSMenuItem(title: title, action: #selector(Action.fire), keyEquivalent: "")
        item.target = a
        return item
    }

    /// Files opened with the app (double-clicked packs, GIFs dropped on its icon).
    func handleOpened(urls: [URL]) {
        for url in urls {
            switch url.pathExtension.lowercased() {
            case MascotLibrary.packExtension:
                do {
                    let info = try MascotLibrary.install(packAt: url)
                    Preferences.mascotSource = "pack:\(info.id)"
                    reloadMascot()
                } catch { showError(Strings.importFailed, Strings.importFailedBody) }
            case "gif":
                importGIF(url)
            default: break
            }
        }
    }

    /// Asks for a GIF (unless one is given), a name and how to cut it, then installs it as a mascot pack and switches to it.
    private func importGIF(_ given: URL?) {
        NSApp.activate(ignoringOtherApps: true)
        var url = given
        if url == nil {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.gif]
            panel.allowsMultipleSelection = false
            panel.message = Strings.importTitle
            guard panel.runModal() == .OK else { return }
            url = panel.url
        }
        guard let gif = url else { return }

        let alert = NSAlert()
        alert.messageText = Strings.importTitle
        alert.informativeText = Strings.importBody
        let nameField = NSTextField(string: gif.deletingPathExtension().lastPathComponent)
        let kind = NSPopUpButton(frame: .zero, pullsDown: false)
        kind.addItems(withTitles: [Strings.importSplit, Strings.importLoopOnly])
        let stack = NSStackView(views: [label(Strings.importName), nameField, label(Strings.importKind), kind])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 100)
        nameField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        kind.widthAnchor.constraint(equalToConstant: 360).isActive = true
        alert.accessoryView = stack
        alert.addButton(withTitle: Strings.importConfirm)
        alert.addButton(withTitle: Strings.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        do {
            let info = try MascotLibrary.importGIF(at: gif, name: name.isEmpty ? "Mascot" : name,
                                                   segmentation: kind.indexOfSelectedItem == 0 ? .introAndOutro : .loopOnly)
            Preferences.mascotSource = "pack:\(info.id)"
            reloadMascot()
        } catch {
            showError(Strings.importFailed, Strings.importFailedBody)
        }
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func exportPack(_ info: MascotInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = info.name + "." + MascotLibrary.packExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try MascotLibrary.export(info, to: url) } catch { showError(Strings.importFailed, "") }
    }

    private func confirmRemove(_ info: MascotInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = Strings.removeConfirm(info.name)
        alert.addButton(withTitle: Strings.remove)
        alert.addButton(withTitle: Strings.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? MascotLibrary.remove(info)
        if Preferences.mascotSource == "pack:\(info.id)" { Preferences.mascotSource = "builtin"; reloadMascot() }
    }

    private func showError(_ title: String, _ detail: String) {
        let a = NSAlert()
        a.messageText = title; a.informativeText = detail; a.alertStyle = .warning
        a.runModal()
    }

    // MARK: self-test

    /// `CLAMSHELL_SELFTEST=1`: picks menu items the way macOS does (the menu is built, closes, and only then the action
    /// runs) and checks that the preferences changed. Restores whatever it touched.
    func runMenuSelfTest() -> Bool {
        guard let menu = statusItem.menu else { return false }
        func pick(_ title: String, in menu: NSMenu) -> Bool {
            guard let i = menu.items.firstIndex(where: { $0.title == title }) else { return false }
            menu.performActionForItem(at: i)
            return true
        }
        var ok = true
        let originalClock = Preferences.showClock, originalMono = Preferences.monochrome
        menuNeedsUpdate(menu)
        menuDidCloseHook(menu)
        ok = pick(Strings.showClock, in: menu) && ok
        ok = (Preferences.showClock == !originalClock) && ok
        Preferences.showClock = originalClock

        menuNeedsUpdate(menu)
        if let sub = menu.items.first(where: { $0.title == Strings.color })?.submenu {
            let target = originalMono ? Strings.colorOriginal : Strings.colorSystem
            ok = pick(target, in: sub) && ok
            ok = (Preferences.monochrome == !originalMono) && ok
        } else { ok = false }
        Preferences.monochrome = originalMono
        return ok
    }

    private func menuDidCloseHook(_ menu: NSMenu) { /* nothing may be released when a menu closes */ }

    // MARK: menu helpers

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor])
        return item
    }

    private func rowTitle(_ s: LiveSession) -> String {
        var t = s.displayName.isEmpty ? "—" : s.displayName
        if !s.branch.isEmpty { t += " · " + s.branch }
        return t
    }

    private func rowAttributed(_ s: LiveSession) -> NSAttributedString {
        let out = NSMutableAttributedString(string: rowTitle(s), attributes: [.font: NSFont.menuFont(ofSize: 0)])
        var detail = ""
        switch s.phase {
        case .permission: detail = Strings.status(.permission)
        case .thinking, .tool:
            detail = Strings.status(StatusKind.of(s)).replacingOccurrences(of: "…", with: "")
            if s.record.turnStartedAt > 0 { detail += " " + Strings.elapsed(max(0, Int(Date().timeIntervalSince1970 - s.record.turnStartedAt))) }
        default: break
        }
        if !detail.isEmpty {
            out.append(NSAttributedString(string: "   " + detail, attributes: [
                .font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        return out
    }

    private func dot(for phase: Phase) -> NSImage? {
        let color: NSColor
        switch phase {
        case .permission: color = .systemYellow
        case .thinking, .tool: color = .systemRed
        default: color = .tertiaryLabelColor
        }
        let size = NSSize(width: 9, height: 9)
        return NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
    }

    private final class Action: NSObject {
        let run: (Bool) -> Void
        let on: Bool
        init(on: Bool, _ run: @escaping (Bool) -> Void) { self.on = on; self.run = run }
        @objc func fire() { run(!on) }
    }
    private var actions: [Action] = []

    private func toggle(_ title: String, _ isOn: Bool, _ change: @escaping (Bool) -> Void) -> NSMenuItem {
        let a = Action(on: isOn) { [weak self] v in change(v); self?.refresh() }
        actions.append(a)
        let item = NSMenuItem(title: title, action: #selector(Action.fire), keyEquivalent: "")
        item.target = a
        item.state = isOn ? .on : .off
        return item
    }

    private func choice(_ title: String, _ selected: Bool, _ pick: @escaping () -> Void) -> NSMenuItem {
        let a = Action(on: false) { [weak self] _ in pick(); self?.refresh() }
        actions.append(a)
        let item = NSMenuItem(title: title, action: #selector(Action.fire), keyEquivalent: "")
        item.target = a
        item.state = selected ? .on : .off
        return item
    }


    @objc private func sessionClicked(_ sender: NSMenuItem) {
        if let r = sender.representedObject as? SessionRecord { TerminalActivator.activate(r) }
    }

    @objc private func openClaudeDesktop() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @objc private func quitApp() {
        // The marker stops the hook helper from relaunching the app on the next event.
        FileManager.default.createFile(atPath: Paths.quitIntent.path, contents: nil)
        NSApp.terminate(nil)
    }
}
