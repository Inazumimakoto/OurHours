import Foundation
import Synchronization

public final class PartnerSyncStore: Sendable {
    private static let lock = Mutex(())
    public let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("peer_sync.json") }

    public init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("OurHours")) {
        self.directory = directory
    }

    public func load() throws -> PeerSessionCache? {
        try Self.lock.withLock { _ in try read() }
    }

    @discardableResult
    public func savePeerSessions(
        pairID: UUID,
        peerRole: PeerRole,
        sessions: [SyncedPeerSession],
        now: Date = Date()
    ) throws -> PeerSessionCache {
        try Self.lock.withLock { _ in
            let cache = PeerSessionCache(
                pairID: pairID,
                peerRole: peerRole,
                updatedAt: now,
                sessions: sessions.filter { $0.pairID == pairID }
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(cache)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return cache
        }
    }

    public func clearAll() throws {
        try Self.lock.withLock { _ in
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                return
            }
        }
    }

    private func read() throws -> PeerSessionCache? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(PeerSessionCache.self, from: data)
    }
}
