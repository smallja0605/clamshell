// Draws the installer window's background: a pixel-art night sky over a narrow beach strip at the bottom, where the
// crab walks from the app's mound to a glowing burrow. In the middle, between the two icons, the mascot's status
// ("moving files... 1:30") sits with arrows that point from the app towards Applications.
//   swift tools/make_dmg_background.swift <outDir> <crab-fullres.png> <unused.png> ["status text"] ["1分30秒"] [crabScale]
// Writes bg.png (660x440) and bg@2x.png (1320x880). The Finder icons are laid over it at (150,200) and (510,200).
import AppKit

// 660 pt wide; 440 pt tall, of which the top 400 are always visible. Finder windows lose a variable amount of height to
// the title bar and (if the viewer has it on) the path bar, so the artwork runs a little long at the bottom instead of
// leaving a white band.
let W: CGFloat = 660, H: CGFloat = 440
let leftIconX: CGFloat = 150, rightIconX: CGFloat = 510, iconY: CGFloat = 200
let args = CommandLine.arguments
let outDir = args[1]
let crabImage = NSImage(contentsOfFile: args[2])!
let pillSprite = NSImage(contentsOfFile: args[3])!
let statusText = args.count > 4 ? args[4] : "移動檔案"
let clockText = args.count > 5 ? args[5] : "1分30秒"
let crabScaleArg: CGFloat = args.count > 6 ? CGFloat(Double(args[6]) ?? 0.6) : 0.6

struct RNG {
    var s: UInt64
    mutating func next() -> CGFloat { s = s &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((s >> 33) % 10000) / 10000 }
}

func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)          // the context scales points to pixels by itself
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    ctx.interpolationQuality = .none
    ctx.setShouldAntialias(false)

    // Everything below is laid out with y measured from the TOP of the window.
    func Y(_ top: CGFloat, _ h: CGFloat = 0) -> CGFloat { H - top - h }
    func box(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat, _ col: NSColor) {
        ctx.setFillColor(col.cgColor); ctx.fill(CGRect(x: x, y: Y(top, h), width: w, height: h))
    }
    /// Banded gradient: reads as pixel art instead of a smooth blend.
    func gradient(_ top: CGFloat, _ h: CGFloat, from a: NSColor, to b: NSColor, steps: Int = 28) {
        for i in 0..<steps {
            let t = CGFloat(i) / CGFloat(steps - 1)
            let col = NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                              green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                              blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
            box(0, top + h * CGFloat(i) / CGFloat(steps), W, h / CGFloat(steps) + 1, col)
        }
    }

    // Layout of the scene
    let seaTop: CGFloat = 340, sandTop: CGFloat = 362
    let textRect = CGRect(x: 200, y: 176, width: 260, height: 54)     // keep stars out from behind the status text

    // ---- sky: stars and a pixel crescent moon ----
    gradient(0, seaTop, from: c(0x070a2c), to: c(0x5b3d86), steps: 36)
    var rng = RNG(s: 42)
    for _ in 0..<120 {
        let x = (rng.next() * W / 4).rounded() * 4, y = (rng.next() * (seaTop - 24) / 4).rounded() * 4
        let big = rng.next() > 0.88
        if textRect.insetBy(dx: -6, dy: -6).contains(CGPoint(x: x, y: y)) { continue }
        box(x, y, big ? 4 : 2, big ? 4 : 2, c(0xffffff, 0.35 + rng.next() * 0.6))
        if big {
            box(x - 4, y, 4, 4, c(0xffffff, 0.25)); box(x + 4, y, 4, 4, c(0xffffff, 0.25))
            box(x, y - 4, 4, 4, c(0xffffff, 0.25)); box(x, y + 4, 4, 4, c(0xffffff, 0.25))
        }
    }
    let mx: CGFloat = 575, my: CGFloat = 72, u: CGFloat = 4
    for gy in -7...7 {
        for gx in -7...7 {
            let inMoon = hypot(CGFloat(gx), CGFloat(gy)) <= 6.6
            let cut = hypot(CGFloat(gx) - 3, CGFloat(gy) + 1) <= 5.6
            if inMoon && !cut { box(mx + CGFloat(gx) * u, my + CGFloat(gy) * u, u, u, c(0xffeaa8)) }
        }
    }

    // ---- sea (narrow), with the moon's reflection ----
    gradient(seaTop, sandTop - seaTop, from: c(0x172060), to: c(0x1f3a86), steps: 6)
    for row in 0..<3 {
        var x = CGFloat(row * 18)
        while x < W { box(x, seaTop + 4 + CGFloat(row) * 6, 16, 2, c(0x6fa0ff, 0.45)); x += 44 + CGFloat((row * 7) % 5) * 6 }
    }
    for i in 0..<4 { box(mx - CGFloat(14 - i * 3), seaTop + 2 + CGFloat(i) * 4, CGFloat(28 - i * 6), 2, c(0xffeaa8, 0.5)) }

    // ---- sand strip ----
    gradient(sandTop, H - sandTop, from: c(0x8a6f9c), to: c(0x3a2d55), steps: 8)
    box(0, sandTop - 3, W, 3, c(0xffffff, 0.35))
    var foam: CGFloat = 0
    while foam < W { box(foam, sandTop - 2, 12, 2, c(0xffffff, 0.5)); foam += 36 }
    rng = RNG(s: 7)
    for _ in 0..<70 { box((rng.next() * W / 2).rounded() * 2, (sandTop + 4 + rng.next() * (H - sandTop - 6) / 2).rounded() * 1, 2, 2, c(0x000000, 0.18 + rng.next() * 0.2)) }
    for _ in 0..<30 { box((rng.next() * W / 2).rounded() * 2, (sandTop + 4 + rng.next() * (H - sandTop - 6) / 2).rounded() * 1, 2, 2, c(0xffffff, 0.15 + rng.next() * 0.2)) }

    // ---- left: the app's mound, right: the glowing burrow (both sit right under their icons) ----
    for i in 0..<4 { let w = CGFloat(110 - i * 20); box(leftIconX - w / 2, sandTop + 2 + CGFloat(i) * 3, w, 3, c(0xb59ac8, 0.55 - CGFloat(i) * 0.1)) }
    for i in 0..<7 { let r = CGFloat(72 - i * 8); box(rightIconX - r, sandTop - 14 + CGFloat(i) * 2, r * 2, 2, c(0xffb36b, 0.05 + CGFloat(i) * 0.014)) }
    for i in 0..<4 { let w = CGFloat(104 - i * 20); box(rightIconX - w / 2, sandTop + 2 + CGFloat(i) * 3, w, 3, c(0x1a1030, 0.8 - CGFloat(i) * 0.12)) }
    box(rightIconX - 40, sandTop - 1, 80, 3, c(0xffd08a, 0.8))
    for (rx, ry, rw, rh) in [(rightIconX - 62, sandTop - 4, 14.0, 10.0), (rightIconX + 50, sandTop - 3, 16.0, 11.0)] {
        box(rx, ry, rw, rh, c(0x2c2447)); box(rx, ry, rw, 3, c(0x6a5a8a))
    }

    // ---- footprints trailing behind the crab ----
    for i in 0..<6 {
        let fx = 196 + CGFloat(i) * 20, fy: CGFloat = 384 + (i % 2 == 0 ? 0 : 6)
        box(fx, fy, 3, 3, c(0x2a1f45, 0.6)); box(fx + 5, fy + 2, 3, 3, c(0x2a1f45, 0.6))
    }

    // ---- little decorations on the sand ----
    func starfish(_ x: CGFloat, _ y: CGFloat) {
        let col = c(0xff8a5c)
        box(x + 6, y, 4, 4, col); box(x + 2, y + 4, 12, 4, col); box(x, y + 6, 16, 4, col)
        box(x + 4, y + 10, 4, 4, col); box(x + 8, y + 10, 4, 4, col); box(x + 7, y + 6, 2, 2, c(0xffc2a0))
    }
    starfish(30, 372); starfish(618, 376)
    for (sx, sy) in [(84.0, 390.0), (420.0, 392.0), (590.0, 392.0)] {
        box(CGFloat(sx), CGFloat(sy), 8, 4, c(0xf3e6ff, 0.8)); box(CGFloat(sx) + 2, CGFloat(sy) - 2, 4, 2, c(0xf3e6ff, 0.8))
    }

    // ---- the crab with its laptop, walking on the sand (real artwork, hard pixel edges) ----
    let crabScale: CGFloat = crabScaleArg
    let cw = crabImage.size.width * crabScale, ch = crabImage.size.height * crabScale
    let crabX: CGFloat = 330, crabBottom: CGFloat = 392
    ctx.setFillColor(c(0x000000, 0.28).cgColor)
    ctx.fill(CGRect(x: crabX - cw / 2 + 6, y: Y(crabBottom - 1, 4), width: cw - 12, height: 4))
    crabImage.draw(in: NSRect(x: crabX - cw / 2, y: Y(crabBottom - ch, ch), width: cw, height: ch), from: .zero, operation: .sourceOver, fraction: 1)

    // ---- plates behind the two icon labels: Finder draws them black or white depending on the viewer's appearance,
    //      so a mid-tone plate keeps both readable on the dark sky ----
    ctx.setShouldAntialias(true)
    for x in [leftIconX, rightIconX] {
        let r = NSRect(x: x - 62, y: Y(260, 24), width: 124, height: 24)
        let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
        c(0x9a8cc6, 0.96).setFill(); path.fill()
        c(0xffffff, 0.35).setStroke(); path.lineWidth = 1; path.stroke()
    }
    ctx.setShouldAntialias(false)

    // ---- the status between the icons: no bubble, just the mascot + text, flanked by arrows pointing at Applications ----
    ctx.setShouldAntialias(true)
    // Text only (the mascot already appears in the icon and on the beach), sized to fill the width the mascot + text used to take.
    let size: CGFloat = 18
    let font = NSFont.systemFont(ofSize: size, weight: .semibold)
    let text = NSMutableAttributedString(string: statusText + "...", attributes: [.font: font, .foregroundColor: NSColor.white])
    text.append(NSAttributedString(string: "  " + clockText, attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold), .foregroundColor: NSColor.white]))
    let shadow = NSMutableAttributedString(attributedString: text)
    shadow.addAttribute(.foregroundColor, value: c(0x000000, 0.55), range: NSRange(location: 0, length: shadow.length))
    let contentW = ceil(text.size().width)
    let startX = (leftIconX + rightIconX) / 2 - contentW / 2
    let lineH = ceil(text.size().height)
    let textTop = iconY - lineH / 2
    shadow.draw(at: NSPoint(x: startX + 1, y: Y(textTop, lineH) - 1))
    text.draw(at: NSPoint(x: startX, y: Y(textTop, lineH)))

    // pixel chevrons ">>" on both sides, pointing right (from the app towards Applications); the nearer pair is brighter
    ctx.setShouldAntialias(false)
    func chevrons(from x: CGFloat, count: Int) {
        let p: CGFloat = 3
        for n in 0..<count {
            let ox = x + CGFloat(n) * 11
            let col = c(0xffb89a, 0.5 + 0.5 * CGFloat(n + 1) / CGFloat(count))
            for k in 0..<4 {
                // upper arm slopes down to the tip, lower arm slopes up to it
                box(ox + CGFloat(k) * p, iconY - CGFloat(4 - k) * p, p, p, col)
                box(ox + CGFloat(k) * p, iconY + CGFloat(3 - k) * p, p, p, col)
            }
        }
    }
    chevrons(from: startX - 12 - 2 * 11, count: 2)
    chevrons(from: startX + contentW + 10, count: 2)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
save(render(scale: 1), "bg.png")
save(render(scale: 2), "bg@2x.png")
print("wrote backgrounds to \(outDir)")
