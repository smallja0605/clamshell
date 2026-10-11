import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ClamshellCore

final class MascotPackTests: XCTestCase {
    var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("clamshell-mascot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("CLAMSHELL_HOME", home.path, 1)
    }

    override func tearDown() { unsetenv("CLAMSHELL_HOME") }

    // MARK: helpers

    /// A GIF of `count` frames, each 40x30 with a coloured 10x10 square that moves right; optional opaque backdrop.
    private func makeGIF(count: Int, backdrop: (UInt8, UInt8, UInt8)? = nil, delay: Double = 0.1) throws -> URL {
        let url = home.appendingPathComponent("test-\(UUID().uuidString).gif")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil)!
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for i in 0..<count {
            let ctx = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            if let b = backdrop {
                ctx.setFillColor(CGColor(red: CGFloat(b.0) / 255, green: CGFloat(b.1) / 255, blue: CGFloat(b.2) / 255, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
            }
            ctx.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 1))
            ctx.fill(CGRect(x: 10 + i * 2, y: 10, width: 10, height: 10))
            CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    // MARK: segmentation

    func testSegmentationLeavesAtLeastTwoLoopFrames() {
        for n in 1...80 {
            let s = GIFImporter.split(frameCount: n, .introAndOutro)
            XCTAssertGreaterThanOrEqual(n - s.intro - s.outro, min(n, 2), "n=\(n)")
            XCTAssertGreaterThanOrEqual(s.intro, 0); XCTAssertGreaterThanOrEqual(s.outro, 0)
        }
        XCTAssertEqual(GIFImporter.split(frameCount: 36, .introAndOutro).intro, 12)
        XCTAssertEqual(GIFImporter.split(frameCount: 36, .introAndOutro).outro, 7)
        XCTAssertEqual(GIFImporter.split(frameCount: 36, .loopOnly).intro, 0)
        XCTAssertEqual(GIFImporter.split(frameCount: 3, .introAndOutro).intro, 0, "too short to split")
    }

    // MARK: decoding and preparing

    func testDecodeReadsFramesAndSpeed() throws {
        let d = try GIFImporter.decode(try makeGIF(count: 5, delay: 0.1))
        XCTAssertEqual(d.frames.count, 5)
        XCTAssertEqual(d.fps, 10, accuracy: 0.5)
    }

    func testPrepareCropsToArtworkAndScalesTo36Tall() throws {
        let d = try GIFImporter.decode(try makeGIF(count: 4))
        let out = try GIFImporter.prepare(d.frames)
        XCTAssertEqual(out.count, 4)
        XCTAssertTrue(out.allSatisfy { $0.height == 36 })
        XCTAssertTrue(out.allSatisfy { $0.width == out[0].width }, "all frames share one canvas")
        // artwork spans x 10...26 (10px square moving 6px) and 10px tall: aspect 16:10 -> about 58px wide at 36 tall
        XCTAssertEqual(out[0].width, 58, accuracy: 2)
    }

    func testFlatBackdropIsRemoved() throws {
        let d = try GIFImporter.decode(try makeGIF(count: 6, backdrop: (30, 60, 200)))
        let out = try GIFImporter.prepare(d.frames)
        // Artwork alone: 20x10 px (aspect 2:1) -> 72px wide at 36 tall. If the backdrop were kept, the crop would be the
        // whole 40x30 frame (aspect 4:3) -> 48px wide.
        XCTAssertEqual(out[0].width, 72, accuracy: 2)
    }

    func testEmptyArtworkIsRejected() throws {
        let ctx = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        XCTAssertThrowsError(try GIFImporter.prepare([ctx.makeImage()!])) { XCTAssertEqual($0 as? MascotError, .emptyArtwork) }
    }

    func testNotAGIFIsRejected() {
        let bogus = home.appendingPathComponent("x.gif")
        try? Data("nope".utf8).write(to: bogus)
        XCTAssertThrowsError(try GIFImporter.decode(bogus))
    }

    // MARK: library

    func testImportInstallsAPackThatListsAndRemoves() throws {
        let gif = try makeGIF(count: 10)
        let info = try MascotLibrary.importGIF(at: gif, name: "My crab", segmentation: .introAndOutro)
        XCTAssertEqual(info.manifest.introFrames, 3)
        XCTAssertEqual(info.manifest.outroFrames, 2)
        XCTAssertEqual(MascotLibrary.frameURLs(in: info.directory).count, 10)

        let listed = MascotLibrary.installed()
        XCTAssertEqual(listed.map(\.name), ["My crab"])
        XCTAssertEqual(listed.first?.manifest, info.manifest)

        try MascotLibrary.remove(info)
        XCTAssertTrue(MascotLibrary.installed().isEmpty)
    }

    func testTwoImportsWithTheSameNameDoNotCollide() throws {
        let a = try MascotLibrary.importGIF(at: try makeGIF(count: 4), name: "crab", segmentation: .loopOnly)
        let b = try MascotLibrary.importGIF(at: try makeGIF(count: 4), name: "crab", segmentation: .loopOnly)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(MascotLibrary.installed().count, 2)
    }

    func testExportAndReinstallRoundTrip() throws {
        let info = try MascotLibrary.importGIF(at: try makeGIF(count: 8), name: "Round trip", author: "me", segmentation: .introAndOutro)
        let shared = home.appendingPathComponent("Round trip")
        try MascotLibrary.export(info, to: shared)
        let packURL = shared.appendingPathExtension(MascotLibrary.packExtension)
        XCTAssertTrue(FileManager.default.fileExists(atPath: packURL.path))

        try MascotLibrary.remove(info)
        let again = try MascotLibrary.install(packAt: packURL)
        XCTAssertEqual(again.manifest, info.manifest)
        XCTAssertEqual(again.manifest.author, "me")
    }

    func testHandEditedManifestIsClampedOnInstall() throws {
        let info = try MascotLibrary.importGIF(at: try makeGIF(count: 6), name: "edited", segmentation: .loopOnly)
        var m = info.manifest; m.introFrames = 50; m.outroFrames = 50
        try MascotLibrary.write(m, to: info.directory)
        let shared = home.appendingPathComponent("edited.\(MascotLibrary.packExtension)")
        try FileManager.default.copyItem(at: info.directory, to: shared)
        try MascotLibrary.remove(info)
        let installed = try MascotLibrary.install(packAt: shared)
        XCTAssertEqual(installed.manifest.introFrames, 4)       // 6 frames, 2 must stay for the loop
        XCTAssertEqual(installed.manifest.outroFrames, 0)
    }

    func testFolderWithoutManifestIsNotAPack() throws {
        let dir = home.appendingPathComponent("junk.\(MascotLibrary.packExtension)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertThrowsError(try MascotLibrary.install(packAt: dir)) { XCTAssertEqual($0 as? MascotError, .invalidPack) }
    }

    func testRemoveRefusesFoldersOutsideTheLibrary() throws {
        let outside = home.appendingPathComponent("precious")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let fake = MascotInfo(id: "precious", manifest: MascotManifest(name: "x"), directory: outside)
        try MascotLibrary.remove(fake)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testBundledPacksAreListedAndMarked() throws {
        let root = home.appendingPathComponent("Mascots")
        let src = try MascotLibrary.importGIF(at: try makeGIF(count: 6), name: "Shipped", segmentation: .introAndOutro)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: src.directory, to: root.appendingPathComponent("Shipped.\(MascotLibrary.packExtension)"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("not-a-pack"), withIntermediateDirectories: true)

        let found = MascotLibrary.bundled(in: root)
        XCTAssertEqual(found.map(\.id), ["Shipped"])
        XCTAssertTrue(found[0].isBundled)
        XCTAssertEqual(found[0].name, "Shipped")
        XCTAssertTrue(MascotLibrary.bundled(in: home.appendingPathComponent("nothing")).isEmpty)
    }
}
