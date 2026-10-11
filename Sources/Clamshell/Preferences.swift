import Foundation

/// User-facing settings, stored in UserDefaults.
enum Preferences {
    private static let d = UserDefaults.standard

    private static func bool(_ key: String, default value: Bool) -> Bool {
        d.object(forKey: key) == nil ? value : d.bool(forKey: key)
    }

    static var showClock: Bool {
        get { bool("showClock", default: true) }
        set { d.set(newValue, forKey: "showClock") }
    }

    static var showLabel: Bool {
        get { bool("showLabel", default: true) }
        set { d.set(newValue, forKey: "showLabel") }
    }

    /// true = black/white silhouette that follows the menu bar; false = the mascot's own colours.
    static var monochrome: Bool {
        get { bool("monochrome", default: false) }
        set { d.set(newValue, forKey: "monochrome") }
    }

    /// Turns shorter than this many seconds do not chime. Negative = chime off.
    static var chimeMinimumSeconds: Double {
        get { d.object(forKey: "chimeMinimumSeconds") == nil ? -1 : d.double(forKey: "chimeMinimumSeconds") }
        set { d.set(newValue, forKey: "chimeMinimumSeconds") }
    }

    /// Keep the mascot in the menu bar (resting) even when Claude is idle.
    static var alwaysShow: Bool {
        get { bool("alwaysShow", default: false) }
        set { d.set(newValue, forKey: "alwaysShow") }
    }

    /// Which artwork is active: "builtin", "legacy" or "pack:<id>". Anyone who used the older single-slot custom
    /// folder keeps seeing it until they pick something else.
    static var mascotSource: String {
        get { d.string(forKey: "mascotSource") ?? (SpriteSet.hasLegacy ? "legacy" : "builtin") }
        set { d.set(newValue, forKey: "mascotSource") }
    }

    /// One-time: carry settings over from the placeholder identifier used before the first release.
    static func migrateFromOldIdentifier() {
        guard !d.bool(forKey: "migratedFromDevIdentifier") else { return }
        d.set(true, forKey: "migratedFromDevIdentifier")
        guard let old = UserDefaults(suiteName: "dev.clamshell.app") else { return }
        for key in ["showClock", "showLabel", "monochrome", "chimeMinimumSeconds", "alwaysShow", "mascotSource", "askedAboutHooks", "language"]
        where d.object(forKey: key) == nil {
            if let v = old.object(forKey: key) { d.set(v, forKey: key) }
        }
    }

    static var askedAboutHooks: Bool {
        get { bool("askedAboutHooks", default: false) }
        set { d.set(newValue, forKey: "askedAboutHooks") }
    }
}
