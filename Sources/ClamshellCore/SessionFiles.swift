import Foundation

/// Reading and writing session records. Writes are atomic (temp file + rename) so the app never sees half a file.
public enum SessionFiles {
    public static func url(for id: String, in dir: URL = Paths.sessions) -> URL {
        dir.appendingPathComponent(sanitizedSessionID(id) + ".json")
    }

    public static func read(id: String, in dir: URL = Paths.sessions) -> SessionRecord? {
        guard let data = try? Data(contentsOf: url(for: id, in: dir)) else { return nil }
        return try? JSONDecoder().decode(SessionRecord.self, from: data)
    }

    public static func write(_ record: SessionRecord, in dir: URL = Paths.sessions) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = url(for: record.id, in: dir)
        let tmp = dir.appendingPathComponent(".\(record.id).\(getpid()).tmp")
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        try enc.encode(record).write(to: tmp)
        _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
    }

    public static func remove(id: String, in dir: URL = Paths.sessions) {
        try? FileManager.default.removeItem(at: url(for: id, in: dir))
    }
}
