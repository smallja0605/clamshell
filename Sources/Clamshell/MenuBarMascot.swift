import Cocoa

/// A view that never intercepts clicks, so the status item's own button still opens the menu.
private class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Draws one attributed string at exactly x = 0 (NSTextField adds ~2pt of inset, which pushed the end of
/// every string past its measured width and got it clipped). `dy` shifts the text vertically for the roll
/// animations; the view is as tall as the menu bar so nothing is cut off vertically.
private final class GlyphView: PassthroughView {
    private(set) var text = NSAttributedString()
    var dy: CGFloat = 0 { didSet { if dy != oldValue { needsDisplay = true } } }

    func set(_ t: NSAttributedString) {
        guard !t.isEqual(to: text) else { return }
        text = t
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard text.length > 0 else { return }
        let size = text.size()
        text.draw(at: NSPoint(x: 0, y: ((bounds.height - size.height) / 2 + dy).rounded()))
    }
}

/// One character of the elapsed clock. When it changes, the old glyph slides up and out while the new one
/// rises from below (like the iOS clock), independently of its neighbours.
private final class ClockDigit {
    let clip = PassthroughView()
    let old = GlyphView()
    let new = GlyphView()
    var char = ""
    var from = ""
    var progress = 1.0
    var isRolling: Bool { progress < 1 }

    init() {
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.addSubview(old)
        clip.addSubview(new)
    }
}

/// Everything you see in the menu bar: the mascot, the label beside it, and the status item's own width and
/// visibility.
///
/// The item sits to the left of its neighbour and is right-anchored, so widening it pushes everything to its
/// left further left. Life cycle:
///   hidden  -> the status item is not visible at all (no icon, no click target)
///   intro   -> the item appears and widens, so the mascot crawls out leftwards while the laptop opens
///   working -> typing loop; the label types itself in, later labels roll in from below, "…" animates,
///              and the clock rolls digit by digit
///   outro   -> the label erases and the laptop closes
///   retract -> the item narrows to nothing and hides again
final class MenuBarMascot {
    private enum Phase { case hidden, intro, working, outro, retract, resting }

    struct Input {
        var working = false
        var label = ""             // e.g. "思考中…"; a trailing "…" becomes animated dots
        var clock: String? = nil   // e.g. "1分4秒"
        var amber = false          // awaiting permission: yellow label
        var template = false       // black/white silhouette instead of full colour
        var alwaysVisible = false  // stay in the menu bar (resting) when idle instead of hiding
    }

    // MARK: tuning
    private let typeInterval = 0.085       // seconds per typed character
    private let eraseInterval = 0.03
    private let rollDuration = 0.38
    private let digitRollDuration = 0.30
    private let dotInterval = 0.35
    private let idleGrace = 1.0            // keep the mascot this long after work stops (avoids flapping between turns)
    private let padLeft: CGFloat = 2, padRight: CGFloat = 2, gap: CGFloat = 4, clockGap: CGFloat = 6
    private let rollTravel: CGFloat = 13

    // MARK: state
    private let item: NSStatusItem
    private var sprites: SpriteSet
    private var input = Input()
    private var lastWanted = Date.distantPast
    private var phase: Phase = .hidden
    private var frameIndex = 0
    private var frameClock = 0.0
    private var slotWidth: CGFloat = 0        // the eased width of the mascot's own slot
    private var ticker: Timer?
    private var fast = true
    private var busy = true
    private var lastTick = Date()
    private var dt = 0.0
    private var shownImageKey = ""

    private var base = ""                     // label without its trailing dots
    private var hasDots = false
    private var revealed = 0                  // characters of `base` currently visible
    private var typeClock = 0.0
    private var dotsClock = 0.0
    private var rolling = false
    private var rollT = 0.0
    private var rollFromWidth: CGFloat = 0
    private var rollToWidth: CGFloat = 0
    private var outgoingBase = ""
    private var outgoingDots = false
    private var lastLabelKey = ""
    private var clockText = ""

    // MARK: views
    private let host = PassthroughView()
    private let mascotView = NSImageView()
    private let textClip = PassthroughView()
    private let labelA = GlyphView()
    private let labelB = GlyphView()
    private let clockHost = PassthroughView()
    private var digits: [ClockDigit] = []
    private let font = NSFont.menuBarFont(ofSize: 0)
    private lazy var digitFont = NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
    /// Automated runs (CLAMSHELL_SNAP) draw into snapshots only; they must never put a second item in the user's menu bar.
    private let testMode = ProcessInfo.processInfo.environment["CLAMSHELL_SNAP"] != nil
    private var barHeight: CGFloat { NSStatusBar.system.thickness }

    init(item: NSStatusItem, sprites: SpriteSet) {
        self.item = item
        self.sprites = sprites
        item.isVisible = false
        guard let button = item.button else { return }
        button.title = ""
        button.image = nil
        button.wantsLayer = true
        button.layer?.masksToBounds = true
        // CLAMSHELL_SNAP_DARK=1: render snapshots with the dark menu-bar appearance (for preview images).
        if ProcessInfo.processInfo.environment["CLAMSHELL_SNAP_DARK"] != nil { button.appearance = NSAppearance(named: .darkAqua) }

        host.wantsLayer = true
        button.addSubview(host)
        mascotView.imageScaling = .scaleNone
        host.addSubview(mascotView)
        textClip.wantsLayer = true
        textClip.layer?.masksToBounds = true
        textClip.addSubview(labelA)
        textClip.addSubview(labelB)
        host.addSubview(textClip)
        host.addSubview(clockHost)
        labelB.alphaValue = 0
    }

    // MARK: public

    /// Swaps the mascot artwork (takes effect immediately, even mid-animation).
    func setSprites(_ new: SpriteSet) {
        sprites = new
        shownImageKey = ""
        frameIndex = 0
        startTicker()
    }

    /// Shows the mascot for a few seconds even while idle. A hidden status item cannot be clicked, so this is how
    /// the menu stays reachable (e.g. when the app is opened again by hand).
    func peek(seconds: Double = 8) {
        lastWanted = Date().addingTimeInterval(seconds - idleGrace)
        startTicker()
    }

    func update(_ new: Input) {
        input = new
        if new.working { lastWanted = Date() }
        if phase == .intro || phase == .working { retarget(label: new.label) }
        clockText = new.clock ?? ""
        let restingStable = phase == .resting && !new.working && new.alwaysVisible
        let hiddenStable = phase == .hidden && !new.working && !new.alwaysVisible && Date().timeIntervalSince(lastWanted) >= idleGrace
        if restingStable { showRestingFrame() } else if !hiddenStable { startTicker() }
    }

    /// The idle pose: the last frame of the outro (crab alone, laptop gone). No animation needed.
    private func showRestingFrame() {
        let seq = sprites.outro.count > 0 ? sprites.outro : sprites.loop
        guard seq.count > 0 else { return }
        let i = sprites.outro.count > 0 ? seq.count - 1 : 0
        let key = "resting|\(i)|\(input.template)|\(seq.count)"
        if key != shownImageKey {
            shownImageKey = key
            mascotView.image = input.template ? seq.template[i] : seq.color[i]
            DispatchQueue.main.async { [weak self] in self?.writeSnapshot() }   // resting has no ticker, so snapshot here
        }
        mascotView.contentTintColor = input.template ? .labelColor : nil
    }

    // MARK: ticker

    private var wantVisible: Bool { input.working || Date().timeIntervalSince(lastWanted) < idleGrace }

    private func startTicker() {
        guard ticker == nil else { return }
        lastTick = Date()
        schedule(fast: true)
    }

    private func schedule(fast: Bool) {
        ticker?.invalidate()
        self.fast = fast
        let t = Timer(timeInterval: fast ? 1.0 / 60.0 : 1.0 / 20.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        let now = Date()
        dt = min(0.1, now.timeIntervalSince(lastTick))
        lastTick = now

        switch phase {
        case .hidden:
            busy = false
            if wantVisible { begin() } else if input.alwaysVisible { enterResting() }
        case .intro, .working:
            if !wantVisible { phase = .outro; frameIndex = 0; frameClock = 0 }
        case .retract:
            if wantVisible { phase = .intro; frameIndex = 0; frameClock = 0; retarget(label: input.label) }
            else if input.alwaysVisible && revealed == 0 { clearText(); phase = .resting }
        case .resting:
            if wantVisible { phase = .intro; frameIndex = 0; frameClock = 0; retarget(label: input.label) }
            else if !input.alwaysVisible { phase = .retract }
        case .outro:
            break
        }

        advanceFrames()
        advanceText()
        layout()
        snapshotIfRequested()

        if phase == .resting && !busy && !settledSnapshotTaken { settledSnapshotTaken = true; writeSnapshot() }
        if phase != .resting { settledSnapshotTaken = false }
        if phase == .hidden || (phase == .resting && !busy) { ticker?.invalidate(); ticker = nil }
        else if busy != fast { schedule(fast: busy) }
    }

    private func clearText() {
        base = ""; hasDots = false; revealed = 0; rolling = false; lastLabelKey = ""
        for d in digits { d.clip.removeFromSuperview() }
        digits.removeAll()
        labelA.set(NSAttributedString()); labelB.set(NSAttributedString())
    }

    private func begin() {
        phase = .intro; frameIndex = 0; frameClock = 0
        slotWidth = 1
        clearText()
        item.length = 1
        item.isVisible = !testMode
        retarget(label: input.label)
    }

    /// Idle but kept in the menu bar: the crab simply sits there.
    private func enterResting() {
        phase = .resting
        slotWidth = 1
        clearText()
        item.length = 1
        item.isVisible = !testMode
        showRestingFrame()
    }

    // MARK: frames

    private var currentFPS: Double { phase == .intro ? sprites.introFPS : (phase == .working ? sprites.loopFPS : sprites.outroFPS) }

    private func advanceFrames() {
        guard phase != .hidden else { return }
        if phase == .resting { showRestingFrame(); return }
        // A pack may have no opening or closing part: skip straight on.
        if phase == .intro && sprites.intro.count == 0 { phase = .working; frameIndex = 0 }
        if phase == .outro && sprites.outro.count == 0 { phase = .retract }
        frameClock += dt
        let period = 1.0 / currentFPS
        while frameClock >= period {
            frameClock -= period
            frameIndex += 1
            switch phase {
            case .intro where frameIndex >= sprites.intro.count: phase = .working; frameIndex = 0
            case .working: frameIndex %= max(1, sprites.loop.count)
            case .outro where frameIndex >= sprites.outro.count:
                phase = .retract; frameIndex = max(0, sprites.outro.count - 1)
            default: break
            }
        }
        let seq: SpriteSet.Sequence
        switch phase {
        case .intro: seq = sprites.intro
        case .working: seq = sprites.loop
        default: seq = sprites.outro.count > 0 ? sprites.outro : sprites.loop
        }
        guard seq.count > 0 else { return }
        let i = min(max(0, frameIndex), seq.count - 1)
        let key = "\(phase)|\(i)|\(input.template)"
        if key != shownImageKey {
            shownImageKey = key
            mascotView.image = input.template ? seq.template[i] : seq.color[i]
        }
        mascotView.contentTintColor = input.template ? .labelColor : nil
    }

    // MARK: text

    private func split(_ s: String) -> (String, Bool) {
        for suffix in ["…", "..."] where s.hasSuffix(suffix) { return (String(s.dropLast(suffix.count)), true) }
        return (s, false)
    }

    private func retarget(label: String) {
        let (b, d) = split(label)
        guard b != base || d != hasDots else { return }
        if base.isEmpty || revealed < base.count || b.isEmpty {
            // First text, still typing, or clearing: just aim the typewriter at the new text.
            base = b; hasDots = d
            revealed = min(revealed, b.count)
        } else {
            // A fully shown label is replaced: the new text pushes the old one up and out.
            outgoingBase = base; outgoingDots = hasDots
            rollFromWidth = measure(outgoingBase, dots: outgoingDots)
            base = b; hasDots = d; revealed = b.count
            rollToWidth = measure(b, dots: d)
            rolling = true; rollT = 0
        }
    }

    private var dotsShown: Int { Int(dotsClock / dotInterval) % 3 + 1 }
    private var leaving: Bool { phase == .outro || phase == .retract }
    private var ink: NSColor { input.amber ? .systemYellow : .labelColor }

    private func attributed(_ text: String, dots: Bool, showDots: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink])
        guard dots, showDots else { return out }
        // All three dots take up room so the label never jitters; the ones not reached yet are transparent.
        for i in 0..<3 {
            out.append(NSAttributedString(string: ".", attributes: [
                .font: font, .foregroundColor: i < dotsShown ? ink : ink.withAlphaComponent(0)]))
        }
        return out
    }

    private func measure(_ s: String, dots: Bool = false) -> CGFloat {
        guard !s.isEmpty else { return 0 }
        var w = ceil((s as NSString).size(withAttributes: [.font: font]).width) + 1
        if dots { w += ceil(("..." as NSString).size(withAttributes: [.font: font]).width) }
        return w
    }

    private func advanceText() {
        dotsClock += dt
        if rolling {
            rollT += dt / rollDuration
            if rollT >= 1 { rolling = false }
        } else if leaving || base.isEmpty {
            typeClock += dt
            while typeClock >= eraseInterval, revealed > 0 { typeClock -= eraseInterval; revealed -= 1 }
            if revealed == 0 { typeClock = 0 }
        } else if revealed < base.count {
            typeClock += dt
            while typeClock >= typeInterval, revealed < base.count { typeClock -= typeInterval; revealed += 1 }
        }
        refreshLabels()
    }

    private func refreshLabels() {
        let dotsLive = hasDots && revealed >= base.count && !leaving
        let key = "\(rolling)|\(base)|\(revealed)|\(dotsLive)|\(dotsShown)|\(outgoingBase)|\(input.amber)"
        guard key != lastLabelKey else { return }
        lastLabelKey = key
        if rolling {
            labelA.set(attributed(outgoingBase, dots: outgoingDots, showDots: true))
            labelB.set(attributed(base, dots: hasDots, showDots: true))
        } else {
            labelA.set(attributed(String(base.prefix(revealed)), dots: hasDots, showDots: dotsLive))
            labelB.set(NSAttributedString())
            labelB.alphaValue = 0
        }
    }

    // MARK: clock

    private func digitWidth(_ c: String) -> CGFloat {
        c.isEmpty ? 0 : ceil((c as NSString).size(withAttributes: [.font: digitFont]).width)
    }

    private func syncDigits(_ text: String) {
        let chars = text.map(String.init)
        while digits.count > chars.count { digits.removeLast().clip.removeFromSuperview() }
        for (i, c) in chars.enumerated() {
            if i >= digits.count {
                let d = ClockDigit()
                d.char = c
                clockHost.addSubview(d.clip)
                digits.append(d)
            } else if digits[i].char != c {
                digits[i].from = digits[i].char
                digits[i].char = c
                digits[i].progress = 0
            }
        }
        for d in digits where d.isRolling { d.progress = min(1, d.progress + dt / digitRollDuration) }
    }

    // MARK: layout

    private func ease(_ t: Double) -> CGFloat { let c = min(1, max(0, t)); return CGFloat(1 - pow(1 - c, 3)) }

    private func layout() {
        guard phase != .hidden else { return }
        let h = barHeight

        let wordWidth: CGFloat
        if rolling {
            wordWidth = rollFromWidth + (rollToWidth - rollFromWidth) * ease(rollT)
        } else {
            wordWidth = measure(String(base.prefix(revealed)), dots: hasDots && revealed >= base.count && !leaving)
        }

        // The clock appears once the label is fully typed, and never while leaving.
        let clockVisible = !clockText.isEmpty && (phase == .intro || phase == .working) && revealed >= base.count
        syncDigits(clockVisible ? clockText : "")
        var clockWidth: CGFloat = 0
        for d in digits {
            let a = digitWidth(d.char), b = digitWidth(d.from)
            clockWidth += d.isRolling ? b + (a - b) * ease(d.progress) : a
        }
        clockWidth = ceil(clockWidth)

        // Only the mascot's own slot is eased (that is what makes it crawl out and slip back); the text and
        // clock extend the item by exactly their visible width, so nothing is ever clipped while it grows.
        var extra: CGFloat = 0
        if wordWidth > 0 { extra += gap + wordWidth }
        if clockWidth > 0 { extra += (wordWidth > 0 ? clockGap : gap) + clockWidth }

        let finished = phase == .retract && revealed == 0 && extra == 0 && !input.alwaysVisible
        let fullTarget = padLeft + sprites.width + padRight
        let rest = sprites.restingExtent
        let restTarget = padLeft + rest.width + padRight
        // At rest only the crab's own pixels count, so the highlight macOS draws around the item is symmetrical.
        let settlingToRest = phase == .resting || (phase == .retract && input.alwaysVisible)
        let target: CGFloat = finished ? 0.5 : (settlingToRest ? restTarget : fullTarget)
        slotWidth += (target - slotWidth) * CGFloat(min(1, dt * (finished ? 16 : 13)))
        if abs(target - slotWidth) < 0.3 { slotWidth = target }
        item.length = max(0.5, (slotWidth + extra).rounded(.up))

        busy = rolling || digits.contains(where: \.isRolling) || abs(target - slotWidth) > 0.3
            || revealed != ((leaving || base.isEmpty) ? 0 : base.count) || leaving
            || (hasDots && revealed >= base.count)   // the dots animate

        if finished && slotWidth <= 1.2 {
            phase = .hidden
            item.isVisible = false
            return
        }

        // Content is left-anchored in the item, so it travels with the growing edge.
        host.frame = NSRect(x: 0, y: 0, width: max(item.length, padLeft + sprites.width + extra + padRight), height: h)
        // 0 = full canvas, 1 = trimmed to the resting pose; follows the slot width so it moves continuously
        let trim = fullTarget > restTarget ? min(1, max(0, (fullTarget - slotWidth) / (fullTarget - restTarget))) : 0
        mascotView.frame = NSRect(x: padLeft - rest.left * trim, y: (h - SpriteSet.height) / 2,
                                  width: sprites.width, height: SpriteSet.height)
        let textX = padLeft + sprites.width + gap
        textClip.frame = NSRect(x: textX, y: 0, width: max(0, wordWidth), height: h)

        if rolling {
            let e = ease(rollT)
            labelA.frame = NSRect(x: 0, y: 0, width: max(rollFromWidth, 1) + 4, height: h)
            labelB.frame = NSRect(x: 0, y: 0, width: max(rollToWidth, 1) + 4, height: h)
            labelA.dy = rollTravel * e;  labelA.alphaValue = 1 - e
            labelB.dy = -rollTravel * (1 - e); labelB.alphaValue = e
        } else {
            labelA.frame = NSRect(x: 0, y: 0, width: max(wordWidth, 1) + 4, height: h)
            labelA.dy = 0; labelA.alphaValue = 1
        }

        clockHost.frame = NSRect(x: textX + wordWidth + (wordWidth > 0 ? clockGap : 0), y: 0, width: clockWidth, height: h)
        var x: CGFloat = 0
        for d in digits {
            let a = digitWidth(d.char), b = digitWidth(d.from)
            let w = d.isRolling ? b + (a - b) * ease(d.progress) : a
            let e = d.isRolling ? ease(d.progress) : 1
            d.clip.frame = NSRect(x: x, y: 0, width: w, height: h)
            d.old.frame = NSRect(x: 0, y: 0, width: b + 4, height: h)
            d.new.frame = NSRect(x: 0, y: 0, width: a + 4, height: h)
            d.old.dy = rollTravel * e;  d.old.alphaValue = d.isRolling ? 1 - e : 0
            d.new.dy = -rollTravel * (1 - e); d.new.alphaValue = d.isRolling ? e : 1
            let attrs: [NSAttributedString.Key: Any] = [.font: digitFont, .foregroundColor: ink]
            d.old.set(NSAttributedString(string: d.from, attributes: attrs))
            d.new.set(NSAttributedString(string: d.char, attributes: attrs))
            x += w
        }
    }

    // MARK: developer aid

    // CLAMSHELL_SNAP=<dir> writes PNGs of the status item (no screen-recording permission needed), so the
    // animation can be inspected headlessly and in automated checks.
    private var snapCount = 0, snapClock = 0.0
    private var settledSnapshotTaken = false
    private func snapshotIfRequested() {
        guard phase != .hidden, phase != .resting else { return }
        snapClock += dt
        guard snapClock >= 0.1 else { return }
        snapClock = 0
        writeSnapshot()
    }

    private func writeSnapshot() {
        guard let dir = ProcessInfo.processInfo.environment["CLAMSHELL_SNAP"], phase != .hidden,
              let button = item.button, snapCount < 900 else { return }
        let b = button.bounds
        guard b.width > 1, let rep = button.bitmapImageRepForCachingDisplay(in: b) else { return }
        button.cacheDisplay(in: b, to: rep)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let name = String(format: "%@/snap_%03d_%@.png", dir, snapCount, "\(phase)")
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: name))
        let w = button.window?.frame.width ?? -1
        if let h = FileHandle(forWritingAtPath: dir + "/geometry.txt") ?? { FileManager.default.createFile(atPath: dir + "/geometry.txt", contents: nil); return FileHandle(forWritingAtPath: dir + "/geometry.txt") }() {
            h.seekToEndOfFile()
            h.write(Data("\(snapCount) \(phase) item.length=\(item.length) buttonWidth=\(b.width) windowWidth=\(w)\n".utf8))
            try? h.close()
        }
        snapCount += 1
    }
}
