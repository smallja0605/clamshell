import Foundation

/// "Is the app running?" answered with an advisory file lock instead of matching process names.
/// The app keeps the lock for its whole life; the kernel releases it if the app crashes.
public enum AppLock {
    /// Called by the app at launch. Returns the descriptor to keep open, or nil if another instance holds the lock.
    public static func acquire() -> Int32? {
        Paths.ensureDirectories()
        let fd = open(Paths.appLock.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return nil }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { return fd }
        close(fd)
        return nil
    }

    /// Called by the hook helper. True if some process currently holds the lock.
    public static func isAppRunning() -> Bool {
        let fd = open(Paths.appLock.path, O_RDONLY)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        if flock(fd, LOCK_SH | LOCK_NB) == 0 { flock(fd, LOCK_UN); return false }
        return true
    }
}
