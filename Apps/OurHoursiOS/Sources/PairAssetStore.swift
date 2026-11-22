import Foundation
import OurHoursCore
import Synchronization

final class PairAssetStore: Sendable {
    private static let lock = Mutex(())
    let directory: URL

    private var assetsDirectory: URL {
        directory.appendingPathComponent("Assets", isDirectory: true)
    }

    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("OurHours")) {
        self.directory = directory
    }

    func exists(kind: PairAssetKind, id: UUID) -> Bool {
        Self.lock.withLock { _ in
            FileManager.default.fileExists(atPath: fileURL(kind: kind, id: id).path)
        }
    }

    func loadData(kind: PairAssetKind, id: UUID) -> Data? {
        Self.lock.withLock { _ in
            try? Data(contentsOf: fileURL(kind: kind, id: id))
        }
    }

    func saveData(_ data: Data, kind: PairAssetKind, id: UUID) throws {
        try Self.lock.withLock { _ in
            try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
            try data.write(to: fileURL(kind: kind, id: id), options: .atomic)
        }
    }

    func deleteData(kind: PairAssetKind, id: UUID) {
        Self.lock.withLock { _ in
            try? FileManager.default.removeItem(at: fileURL(kind: kind, id: id))
        }
    }

    func clearAll() {
        Self.lock.withLock { _ in
            try? FileManager.default.removeItem(at: assetsDirectory)
        }
    }

    func fileURL(kind: PairAssetKind, id: UUID) -> URL {
        let ext = kind == .dayVideo ? "mp4" : "jpg"
        return assetsDirectory.appendingPathComponent("\(kind.rawValue)_\(id.uuidString).\(ext)")
    }
}
