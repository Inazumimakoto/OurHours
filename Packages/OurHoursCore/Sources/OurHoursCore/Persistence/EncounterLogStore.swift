import Foundation
import Synchronization

public final class EncounterLogStore: Sendable {
    public struct ExportFiles: Sendable, Equatable {
        public let json: URL
        public let sessionsCSV: URL
        public let eventsCSV: URL
    }

    private struct Export: Encodable {
        struct Pair: Encodable {
            let pairID: UUID
            let localRole: PeerRole
            let keyEpoch: UInt32
            let createdAt: Date
            let displayLabel: String?

            init(_ config: PairConfiguration) {
                pairID = config.pairID
                localRole = config.localRole
                keyEpoch = config.keyEpoch
                createdAt = config.createdAt
                displayLabel = config.displayLabel
            }
        }
        let pairConfiguration: Pair?
        let sessions: [EncounterSession]
        let events: [DiagnosticEvent]
    }

    public let directory: URL
    private let lock = Mutex(())
    private var sessionsURL: URL { directory.appendingPathComponent("sessions.json") }
    private var eventsURL: URL { directory.appendingPathComponent("events.jsonl") }

    public init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("OurHours")) {
        self.directory = directory
    }

    public func loadSessions() throws -> [EncounterSession] {
        try lock.withLock { _ in try readSessions() }
    }

    public func saveSessions(_ sessions: [EncounterSession]) throws {
        try lock.withLock { _ in
            let data = try JSONEncoder().encode(sessions)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: sessionsURL, options: .atomic)
        }
    }

    public func appendEvent(_ event: DiagnosticEvent) throws {
        try lock.withLock { _ in
            var line = try JSONEncoder().encode(event)
            line.append(10)
            guard FileManager.default.fileExists(atPath: eventsURL.path) else {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try line.write(to: eventsURL, options: .atomic)
                return
            }
            let handle = try FileHandle(forUpdating: eventsURL)
            defer { try? handle.close() }
            let end = try handle.seekToEnd()
            if end > 0 {
                try handle.seek(toOffset: end - 1)
                if try handle.read(upToCount: 1)?.first != 10 {
                    try handle.seek(toOffset: end)
                    line.insert(10, at: line.startIndex)
                }
            }
            try handle.write(contentsOf: line)
        }
    }

    /// Returns up to the most recent valid events, in append order.
    public func recentEvents(limit: Int = 200) throws -> [DiagnosticEvent] {
        try lock.withLock { _ in try readEvents(limit: limit) }
    }

    public func clearLogs() throws {
        try lock.withLock { _ in
            var firstError: (any Error)?
            for url in [sessionsURL, eventsURL] {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch let error as CocoaError where error.code == .fileNoSuchFile {
                    continue
                } catch {
                    if firstError == nil { firstError = error }
                }
            }
            if let firstError { throw firstError }
        }
    }

    public func exportJSONData(pairConfiguration: PairConfiguration?) -> Data {
        lock.withLock { _ in (try? jsonData(pairConfiguration)) ?? Data() }
    }

    public func exportSessionsCSVData() -> Data {
        lock.withLock { _ in sessionsCSV((try? readSessions()) ?? []) }
    }

    public func exportEventsCSVData() -> Data {
        lock.withLock { _ in eventsCSV((try? readEvents()) ?? []) }
    }

    public func writeExportFiles(
        pairConfiguration: PairConfiguration?, to temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> ExportFiles {
        try lock.withLock { _ in
            let exportDirectory = temporaryDirectory.appendingPathComponent("OurHours-\(UUID().uuidString)")
            let files = ExportFiles(
                json: exportDirectory.appendingPathComponent("ourhours.json"),
                sessionsCSV: exportDirectory.appendingPathComponent("sessions.csv"),
                eventsCSV: exportDirectory.appendingPathComponent("events.csv")
            )
            let sessions = try readSessions()
            let events = try readEvents()
            let json = try Self.encodeExport(pairConfiguration, sessions: sessions, events: events)
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            do {
                try json.write(to: files.json, options: .atomic)
                try sessionsCSV(sessions).write(to: files.sessionsCSV, options: .atomic)
                try eventsCSV(events).write(to: files.eventsCSV, options: .atomic)
            } catch {
                try? FileManager.default.removeItem(at: exportDirectory)
                throw error
            }
            return files
        }
    }

    private func readSessions() throws -> [EncounterSession] {
        let data: Data
        do {
            data = try Data(contentsOf: sessionsURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        }
        do {
            return try JSONDecoder().decode([EncounterSession].self, from: data)
        } catch {
            let backupURL = directory.appendingPathComponent("sessions-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: sessionsURL, to: backupURL)
            throw error
        }
    }

    private func readEvents(limit: Int = .max) throws -> [DiagnosticEvent] {
        guard limit > 0 else { return [] }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: eventsURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return []
        }
        defer { try? handle.close() }
        let decoder = JSONDecoder()
        var offset = try handle.seekToEnd()
        var suffix = Data()
        var newestFirst: [DiagnosticEvent] = []

        // Read backward in blocks so a small limit only touches the end of the file.
        while offset > 0 {
            let count = min(offset, 64 * 1024)
            offset -= count
            try handle.seek(toOffset: offset)
            let chunk = (try handle.read(upToCount: Int(count)) ?? Data()) + suffix
            var lineEnd = chunk.endIndex
            for index in chunk.indices.reversed() where chunk[index] == 10 {
                if let event = try? decoder.decode(DiagnosticEvent.self, from: chunk[(index + 1)..<lineEnd]) {
                    newestFirst.append(event)
                    if newestFirst.count == limit { return newestFirst.reversed() }
                }
                lineEnd = index
            }
            suffix = Data(chunk[..<lineEnd])
        }
        if let event = try? decoder.decode(DiagnosticEvent.self, from: suffix) { newestFirst.append(event) }
        return newestFirst.reversed()
    }

    private func jsonData(_ config: PairConfiguration?) throws -> Data {
        try Self.encodeExport(config, sessions: readSessions(), events: readEvents())
    }

    private static func encodeExport(
        _ config: PairConfiguration?, sessions: [EncounterSession], events: [DiagnosticEvent]
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Export(pairConfiguration: config.map(Export.Pair.init), sessions: sessions, events: events))
    }

    private func sessionsCSV(_ sessions: [EncounterSession]) -> Data {
        let header = [
            "id", "pairID", "startedAt", "endedAt", "status", "durationSeconds", "connectionPath", "startRole",
            "endReason", "disconnectErrorDescription", "isAutoReconnectPending", "gapFromPreviousSessionSeconds",
            "batteryLevelAtStart", "batteryLevelAtEnd"
        ]
        let date = ISO8601DateFormatter()
        date.formatOptions.insert(.withFractionalSeconds)
        return csv(header: header, rows: sessions.map { session in
            [
                session.id.uuidString, session.pairID.uuidString, date.string(from: session.startedAt),
                session.endedAt.map(date.string(from:)) ?? "", session.status.rawValue, field(session.durationSeconds),
                session.connectionPath.rawValue, session.startRole.rawValue, session.endReason?.rawValue ?? "",
                session.disconnectErrorDescription ?? "", field(session.isAutoReconnectPending),
                field(session.gapFromPreviousSessionSeconds), field(session.batteryLevelAtStart),
                field(session.batteryLevelAtEnd)
            ]
        })
    }

    private func eventsCSV(_ events: [DiagnosticEvent]) -> Data {
        let date = ISO8601DateFormatter()
        date.formatOptions.insert(.withFractionalSeconds)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return csv(
            header: ["id", "timestamp", "category", "kind", "message", "metadata", "batteryLevel", "appState"],
            rows: events.map { event in
                let metadata = (try? encoder.encode(event.metadata)).map { String(decoding: $0, as: UTF8.self) }
                return [
                    event.id.uuidString, date.string(from: event.timestamp), event.category.rawValue, event.kind,
                    event.message, metadata ?? "{}", field(event.batteryLevel), event.appState ?? ""
                ]
            }
        )
    }

    private func field<T: CustomStringConvertible>(_ value: T?) -> String {
        value?.description ?? ""
    }

    private func csv(header: [String], rows: [[String]]) -> Data {
        var data = Data()
        for row in [header] + rows {
            let line = row.map { field in
                if field.utf8.contains(where: { [10, 13, 34, 44].contains($0) }) {
                    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return field
            }.joined(separator: ",")
            data.append(contentsOf: (line + "\r\n").utf8)
        }
        return data
    }
}
