import Cocoa
import ClamshellCore

/// The mascot's frames. By default they come from `Resources/Sprites` (see tools/make_sprites.py); users can switch to
/// a mascot pack they imported from a GIF or installed from a `.clamshellmascot` folder (see MascotPack.swift).
///
/// A sprite set is three sequences: `intro` (laptop opens, plays once), `loop` (typing, repeats while Claude
/// works) and `outro` (laptop closes, plays once). Each frame is a PNG named `<sequence>_NN.png`; an optional
/// `<sequence>_t_NN.png` is the black/white version, otherwise one is derived from the colour frame.
struct SpriteSet {
    struct Sequence { var color: [NSImage]; var template: [NSImage]; var count: Int { color.count } }
    var intro: Sequence
    var loop: Sequence
    var outro: Sequence
    var introFPS = 10.0, loopFPS = 9.0, outroFPS = 10.0

    /// Frames are shown 18pt tall; width follows each frame's aspect ratio.
    static let height: CGFloat = 18

    /// Where artwork comes from.
    enum Source: Equatable {
        case builtIn
        case legacy              // the older single-slot custom folder (~/.claude/clamshell/mascot)
        case bundled(String)     // a pack shipped inside the app
        case pack(String)        // an installed pack (its folder name in the library)

        init(raw: String) {
            if raw == "legacy" { self = .legacy }
            else if raw.hasPrefix("bundled:") { self = .bundled(String(raw.dropFirst(8))) }
            else if raw.hasPrefix("pack:") { self = .pack(String(raw.dropFirst(5))) }
            else { self = .builtIn }
        }
        var raw: String {
            switch self { case .builtIn: return "builtin"; case .legacy: return "legacy"; case .bundled(let id): return "bundled:\(id)"; case .pack(let id): return "pack:\(id)" }
        }
    }

    static var legacyDirectory: URL { Paths.home.appendingPathComponent("mascot", isDirectory: true) }
    static var hasLegacy: Bool {
        FileManager.default.fileExists(atPath: legacyDirectory.appendingPathComponent("loop_00.png").path)
    }

    static func load(_ source: Source) -> SpriteSet {
        switch source {
        case .builtIn:
            break
        case .legacy:
            let set = loadNamedFrames(from: legacyDirectory)
            if !set.isEmpty { return set }
        case .bundled(let id):
            if let info = MascotLibrary.bundled().first(where: { $0.id == id }) {
                let set = loadPack(info)
                if !set.isEmpty { return set }
            }
        case .pack(let id):
            if let info = MascotLibrary.installed().first(where: { $0.id == id }) {
                let set = loadPack(info)
                if !set.isEmpty { return set }
            }
        }
        let bundled = Bundle.main.url(forResource: "Sprites", withExtension: nil)
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Sprites")
        return loadNamedFrames(from: bundled)
    }

    /// A pack: numbered frames plus a manifest saying how many frames open and close the animation.
    private static func loadPack(_ info: MascotInfo) -> SpriteSet {
        let all = MascotLibrary.frameURLs(in: info.directory).compactMap(image)
        let m = info.manifest
        let intro = min(max(0, m.introFrames), max(0, all.count - 2))
        let outro = min(max(0, m.outroFrames), max(0, all.count - 2 - intro))
        func seq(_ r: Range<Int>) -> Sequence {
            let imgs = Array(all[r])
            return Sequence(color: imgs, template: imgs.map { let t = silhouette(of: $0); t.isTemplate = true; return t })
        }
        var set = SpriteSet(intro: seq(0..<intro), loop: seq(intro..<(all.count - outro)), outro: seq((all.count - outro)..<all.count))
        set.introFPS = m.fps; set.loopFPS = m.fps; set.outroFPS = m.fps
        return set
    }

    /// Frames named `intro_NN.png`, `loop_NN.png`, `outro_NN.png` (the bundled artwork and the legacy folder).
    private static func loadNamedFrames(from dir: URL) -> SpriteSet {
        func sequence(_ name: String) -> Sequence {
            var color: [NSImage] = [], template: [NSImage] = []
            var i = 0
            while let c = image(dir.appendingPathComponent("\(name)_\(String(format: "%02d", i)).png")) {
                color.append(c)
                let tURL = dir.appendingPathComponent("\(name)_t_\(String(format: "%02d", i)).png")
                let t = image(tURL) ?? silhouette(of: c)
                t.isTemplate = true
                template.append(t)
                i += 1
            }
            return Sequence(color: color, template: template)
        }
        var set = SpriteSet(intro: sequence("intro"), loop: sequence("loop"), outro: sequence("outro"))
        // optional timing: {"introFPS": 11, "loopFPS": 11, "outroFPS": 11}
        if let data = try? Data(contentsOf: dir.appendingPathComponent("mascot.json")),
           let cfg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Double] {
            set.introFPS = cfg["introFPS"] ?? set.introFPS
            set.loopFPS = cfg["loopFPS"] ?? set.loopFPS
            set.outroFPS = cfg["outroFPS"] ?? set.outroFPS
        }
        return set
    }

    private static func image(_ url: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path), let img = NSImage(contentsOf: url) else { return nil }
        // The PNGs are drawn for a 2x display: report their size as `height` pt tall, keeping the aspect ratio.
        let ratio = img.size.width / max(1, img.size.height)
        img.size = NSSize(width: (height * ratio).rounded(), height: height)
        return img
    }

    /// A black/white version of a colour frame for the menu bar's monochrome mode: the body becomes solid ink,
    /// shaded areas fade to partial ink, and the darkest details (eyes, outlines) become see-through holes.
    private static func silhouette(of source: NSImage) -> NSImage {
        guard let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return source }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return source }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let hole = 0.30, solid = 0.55
        for i in 0..<(w * h) {
            let o = i * 4
            let a = Double(px[o + 3]) / 255
            guard a > 0 else { continue }
            let lum = (0.299 * Double(px[o]) + 0.587 * Double(px[o + 1]) + 0.114 * Double(px[o + 2])) / (255 * a)
            let ink = lum < hole ? 0 : min(1, (lum - hole) / (solid - hole))
            px[o] = 0; px[o + 1] = 0; px[o + 2] = 0
            px[o + 3] = UInt8(max(0, min(255, a * ink * 255)))
        }
        guard let out = ctx.makeImage() else { return source }
        let img = NSImage(cgImage: out, size: source.size)
        img.isTemplate = true
        return img
    }

    /// Horizontal extent (in points) of the pixels actually drawn in the resting frame (the outro's last frame).
    /// The frames share one wide canvas so the animation can move around inside it, but the resting pose may
    /// fill only part of it; trimming keeps the menu-bar highlight symmetrical around the crab.
    var restingExtent: (left: CGFloat, width: CGFloat) {
        guard let img = outro.color.last ?? loop.color.first else { return (0, width) }
        return SpriteSet.opaqueExtent(of: img) ?? (0, width)
    }

    static func opaqueExtent(of image: NSImage) -> (left: CGFloat, width: CGFloat)? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width > 0 else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, maxX = -1
        for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 20 { minX = min(minX, x); maxX = max(maxX, x) } }
        guard maxX >= minX else { return nil }
        let perPixel = image.size.width / CGFloat(w)
        return (CGFloat(minX) * perPixel, CGFloat(maxX - minX + 1) * perPixel)
    }

    var isEmpty: Bool { loop.count == 0 }
    var width: CGFloat { loop.color.first?.size.width ?? 33 }
}
