import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// A mascot pack is a folder (`Name.clamshellmascot` when shared) holding numbered frames and a manifest:
///
///     mascot.json          {"name": "My crab", "author": "me", "fps": 10, "introFrames": 8, "outroFrames": 6}
///     frame_000.png …      the whole animation in order
///
/// The first `introFrames` frames play once when work starts (e.g. a laptop opening), the last `outroFrames` play
/// once when it ends, and everything in between loops while Claude works. Frames are drawn 18pt tall, so PNGs
/// should be 36px tall (2x); the width follows the artwork.
public struct MascotManifest: Codable, Equatable {
    public var name: String
    public var author: String?
    public var fps: Double
    public var introFrames: Int
    public var outroFrames: Int

    public init(name: String, author: String? = nil, fps: Double = 10, introFrames: Int = 0, outroFrames: Int = 0) {
        self.name = name; self.author = author; self.fps = fps; self.introFrames = introFrames; self.outroFrames = outroFrames
    }
}

public struct MascotInfo: Equatable, Identifiable {
    public var id: String                 // folder name inside the library (or the bundled pack's name)
    public var manifest: MascotManifest
    public var directory: URL
    public var isBundled = false          // shipped inside the app: selectable, but not removable
    public var name: String { manifest.name }

    public init(id: String, manifest: MascotManifest, directory: URL, isBundled: Bool = false) {
        self.id = id; self.manifest = manifest; self.directory = directory; self.isBundled = isBundled
    }
}

public enum MascotError: Error, Equatable {
    case notAGIF, noFrames, emptyArtwork, invalidPack, writeFailed
}

public enum MascotLibrary {
    public static let packExtension = "clamshellmascot"

    /// `~/.claude/clamshell/mascots/`
    public static var directory: URL { Paths.home.appendingPathComponent("mascots", isDirectory: true) }

    public static func manifest(in dir: URL) -> MascotManifest? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("mascot.json")) else { return nil }
        return try? JSONDecoder().decode(MascotManifest.self, from: data)
    }

    public static func frameURLs(in dir: URL) -> [URL] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasPrefix("frame_") && $0.hasSuffix(".png") }.sorted()
        return names.map { dir.appendingPathComponent($0) }
    }

    /// Every valid pack in the library, sorted by name.
    public static func installed() -> [MascotInfo] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { n -> MascotInfo? in
            let dir = directory.appendingPathComponent(n, isDirectory: true)
            guard let m = manifest(in: dir), !frameURLs(in: dir).isEmpty else { return nil }
            return MascotInfo(id: n, manifest: m, directory: dir)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Packs shipped inside the app (`Contents/Resources/Mascots/*.clamshellmascot`, put there by `build-app.sh --with-extras`).
    public static func bundled(in dir: URL? = nil) -> [MascotInfo] {
        guard let root = dir ?? Bundle.main.resourceURL?.appendingPathComponent("Mascots", isDirectory: true) else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { $0.hasSuffix("." + packExtension) }.compactMap { n -> MascotInfo? in
            let d = root.appendingPathComponent(n, isDirectory: true)
            guard let m = manifest(in: d), !frameURLs(in: d).isEmpty else { return nil }
            return MascotInfo(id: (n as NSString).deletingPathExtension, manifest: m, directory: d, isBundled: true)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A folder name for `name` that does not collide with an installed pack.
    static func uniqueID(for name: String) -> String {
        let safe = String(name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }.prefix(40))
        let base = safe.trimmingCharacters(in: CharacterSet(charactersIn: "-")).isEmpty ? "mascot" : safe
        var id = base, n = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(id).path) { id = "\(base)-\(n)"; n += 1 }
        return id
    }

    /// Installs a shared `.clamshellmascot` folder (or any folder with the same layout) into the library.
    @discardableResult
    public static func install(packAt url: URL) throws -> MascotInfo {
        guard var m = manifest(in: url), !frameURLs(in: url).isEmpty else { throw MascotError.invalidPack }
        let count = frameURLs(in: url).count
        // keep a hand-edited manifest honest: at least two frames must be left for the typing loop
        m.introFrames = max(0, min(m.introFrames, count - 2))
        m.outroFrames = max(0, min(m.outroFrames, count - 2 - m.introFrames))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = uniqueID(for: url.deletingPathExtension().lastPathComponent)
        let dest = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.copyItem(at: url, to: dest)
        try write(m, to: dest)
        return MascotInfo(id: id, manifest: m, directory: dest)
    }

    public static func remove(_ info: MascotInfo) throws {
        guard info.directory.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return }
        try FileManager.default.removeItem(at: info.directory)
    }

    /// Copies a pack out as a shareable `.clamshellmascot` folder.
    public static func export(_ info: MascotInfo, to url: URL) throws {
        var target = url
        if target.pathExtension != packExtension { target.appendPathExtension(packExtension) }
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.copyItem(at: info.directory, to: target)
    }

    static func write(_ m: MascotManifest, to dir: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(m).write(to: dir.appendingPathComponent("mascot.json"))
    }

    /// Imports a GIF as a new pack.
    @discardableResult
    public static func importGIF(at url: URL, name: String, author: String? = nil, segmentation: GIFImporter.Segmentation) throws -> MascotInfo {
        let decoded = try GIFImporter.decode(url)
        let frames = try GIFImporter.prepare(decoded.frames)
        let split = GIFImporter.split(frameCount: frames.count, segmentation)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = uniqueID(for: name)
        let dest = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        do {
            for (i, f) in frames.enumerated() {
                try GIFImporter.writePNG(f, to: dest.appendingPathComponent(String(format: "frame_%03d.png", i)))
            }
            try write(MascotManifest(name: name, author: author, fps: decoded.fps, introFrames: split.intro, outroFrames: split.outro), to: dest)
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw error
        }
        return MascotInfo(id: id, manifest: MascotManifest(name: name, author: author, fps: decoded.fps, introFrames: split.intro, outroFrames: split.outro), directory: dest)
    }
}

public enum GIFImporter {
    /// How to cut the animation into intro / loop / outro.
    public enum Segmentation { case loopOnly, introAndOutro }

    /// Frame counts for the two one-shot parts; everything else loops.
    public static func split(frameCount n: Int, _ s: Segmentation) -> (intro: Int, outro: Int) {
        guard s == .introAndOutro, n >= 5 else { return (0, 0) }
        var intro = Int((Double(n) * 0.33).rounded()), outro = Int((Double(n) * 0.2).rounded())
        intro = max(1, intro); outro = max(1, outro)
        while n - intro - outro < 2 { if intro > outro { intro -= 1 } else { outro -= 1 } }
        return (intro, outro)
    }

    /// Frames of a GIF with the playback speed implied by its delays.
    public static func decode(_ url: URL) throws -> (frames: [CGImage], fps: Double) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw MascotError.notAGIF }
        let n = CGImageSourceGetCount(src)
        guard n > 0 else { throw MascotError.noFrames }
        var frames: [CGImage] = [], delays: [Double] = []
        for i in 0..<n {
            guard let f = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(f)
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            delays.append(d > 0.011 ? d : 0.1)   // browsers treat ~0 delays as 100 ms
        }
        guard !frames.isEmpty else { throw MascotError.noFrames }
        // The first frame often lingers for a long time; the median is a steadier measure of the animation's speed.
        let median = delays.sorted()[delays.count / 2]
        return (frames, min(24, max(4, 1 / median)))
    }

    /// Removes a flat background colour (if the GIF has one), crops every frame to the combined artwork area, and scales to 36px tall.
    public static func prepare(_ source: [CGImage], targetHeight: Int = 36) throws -> [CGImage] {
        guard let first = source.first else { throw MascotError.noFrames }
        let w = first.width, h = first.height
        var buffers = source.map { rgba($0, width: w, height: h) }
        guard buffers.count == source.count else { throw MascotError.noFrames }

        // Background: the four corners agree and are opaque -> that colour is the backdrop, make it see-through.
        let b0 = buffers[0]
        func px(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) { let o = (y * w + x) * 4; return (b0[o], b0[o + 1], b0[o + 2], b0[o + 3]) }
        let corners = [px(0, 0), px(w - 1, 0), px(0, h - 1), px(w - 1, h - 1)]
        if corners.allSatisfy({ $0.3 > 250 && abs(Int($0.0) - Int(corners[0].0)) < 3 && abs(Int($0.1) - Int(corners[0].1)) < 3 && abs(Int($0.2) - Int(corners[0].2)) < 3 }) {
            let key = corners[0]
            for b in 0..<buffers.count {
                for i in 0..<(w * h) {
                    let o = i * 4
                    if abs(Int(buffers[b][o]) - Int(key.0)) < 8, abs(Int(buffers[b][o + 1]) - Int(key.1)) < 8, abs(Int(buffers[b][o + 2]) - Int(key.2)) < 8 {
                        buffers[b][o] = 0; buffers[b][o + 1] = 0; buffers[b][o + 2] = 0; buffers[b][o + 3] = 0
                    }
                }
            }
        }

        // Union of the artwork over all frames.
        var minX = w, minY = h, maxX = -1, maxY = -1
        for b in buffers {
            for y in 0..<h { for x in 0..<w where b[(y * w + x) * 4 + 3] > 16 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            } }
        }
        guard maxX >= minX, maxY >= minY else { throw MascotError.emptyArtwork }
        let cw = maxX - minX + 1, ch = maxY - minY + 1
        let outW = max(1, min(160, Int((Double(targetHeight) * Double(cw) / Double(ch)).rounded())))

        return try buffers.map { b in
            var buf = b
            guard let full = buf.withUnsafeMutableBytes({ p -> CGImage? in
                CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
            }), let cropped = full.cropping(to: CGRect(x: minX, y: minY, width: cw, height: ch)),
            let ctx = CGContext(data: nil, width: outW, height: targetHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw MascotError.emptyArtwork }
            ctx.interpolationQuality = .high
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: outW, height: targetHeight))
            guard let out = ctx.makeImage() else { throw MascotError.emptyArtwork }
            return out
        }
    }

    private static func rgba(_ image: CGImage, width w: Int, height h: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { p in
            guard let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw MascotError.writeFailed }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw MascotError.writeFailed }
    }
}
