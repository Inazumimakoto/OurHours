import Foundation
import Testing
@testable import OurHoursCore

struct EncounterLogStoreTests {
    private func temporaryStore() -> EncounterLogStore {
        EncounterLogStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @Test func atomicSessionReplacement() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(try store.loadSessions().isEmpty)
        let active = EncounterSession(pairID: UUID(), startedAt: Date(), connectionPath: .scanDiscovery, startRole: .central)
        try store.saveSessions([active])
        #expect(try store.loadSessions() == [active])
        var completed = active
        completed.status = .completed
        completed.endedAt = active.startedAt.addingTimeInterval(60)
        try store.saveSessions([completed])
        #expect(try EncounterLogStore(directory: store.directory).loadSessions() == [completed])
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path) == ["sessions.json"])
    }

    @Test func appendsAfterMalformedTailAndLoadsOnlyRecentValidEvents() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(try store.recentEvents().isEmpty)
        let first = DiagnosticEvent(category: .storage, kind: "first", message: String(repeating: "a", count: 70_000))
        let second = DiagnosticEvent(category: .settings, kind: "second", message: "A message\nwith a newline.")
        let third = DiagnosticEvent(category: .session, kind: "third", message: "")
        try store.appendEvent(first)
        try store.appendEvent(second)
        let url = store.directory.appendingPathComponent("events.jsonl")
        let writer = try FileHandle(forWritingTo: url)
        try writer.seekToEnd()
        try writer.write(contentsOf: Data("{\"corrupt\": true}\n{\"timestamp\":".utf8))
        try writer.close()
        #expect(try store.recentEvents(limit: 0).isEmpty)
        #expect(try store.recentEvents(limit: 1) == [second])
        #expect(try store.recentEvents(limit: 2) == [first, second])
        try store.appendEvent(third)
        #expect(try store.recentEvents(limit: 2) == [second, third])
        #expect(try store.recentEvents() == [first, second, third])
    }

    @Test func clearLogsIsIdempotent() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.clearLogs()
        try store.saveSessions([])
        try store.appendEvent(DiagnosticEvent(category: .storage, kind: "created", message: ""))
        try store.clearLogs()
        try store.clearLogs()
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).isEmpty)
        #expect(try store.recentEvents().isEmpty)
        #expect(try store.loadSessions().isEmpty)
    }

    @Test func exportExcludesSharedSecretAndWritesShareFiles() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let secret = Data(0..<32)
        let config = PairConfiguration(
            pairID: UUID(), sharedSecret: secret, localRole: .partnerB, keyEpoch: 2, displayLabel: "Peer"
        )
        try store.appendEvent(DiagnosticEvent(category: .storage, kind: "export", message: ""))
        let data = store.exportJSONData(pairConfiguration: config)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exported = try #require(root["pairConfiguration"] as? [String: Any])
        #expect(exported["pairID"] as? String == config.pairID.uuidString)
        #expect(exported["displayLabel"] as? String == "Peer")
        #expect(exported["sharedSecret"] == nil)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains(secret.base64EncodedString()))
        let files = try store.writeExportFiles(pairConfiguration: config, to: store.directory)
        #expect(try Data(contentsOf: files.json) == data)
        #expect(try Data(contentsOf: files.sessionsCSV) == store.exportSessionsCSVData())
        #expect(try Data(contentsOf: files.eventsCSV) == store.exportEventsCSVData())
    }

    @Test func csvEscapesCommasQuotesAndNewlines() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let tricky = "lost, \"peer\"\r\nretry\nnow"
        let escaped = "\"lost, \"\"peer\"\"\r\nretry\nnow\""
        let now = Date()
        let session = EncounterSession(
            pairID: UUID(), startedAt: now, endedAt: now, status: .completed, connectionPath: .scanDiscovery,
            startRole: .central, disconnectErrorDescription: tricky
        )
        try store.saveSessions([session])
        try store.appendEvent(DiagnosticEvent(
            category: .central, kind: "disconnect", message: tricky, metadata: ["result": "lost"]
        ))
        let sessions = String(decoding: store.exportSessionsCSVData(), as: UTF8.self)
        let events = String(decoding: store.exportEventsCSVData(), as: UTF8.self)
        #expect(sessions.contains(",\(escaped),"))
        #expect(events.contains(",\(escaped),\"{\"\"result\"\":\"\"lost\"\"}\","))
        #expect(sessions.hasSuffix("\r\n"))
        #expect(events.hasSuffix("\r\n"))
    }

    @Test func corruptSessionsFileIsBackedUpAndThrows() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let sessionsURL = store.directory.appendingPathComponent("sessions.json")
        let corruptPayload = Data("{not-valid-json".utf8)
        try corruptPayload.write(to: sessionsURL, options: .atomic)

        #expect(throws: (any Error).self) {
            try store.loadSessions()
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        let backups = files.filter { $0.hasPrefix("sessions-corrupt-") && $0.hasSuffix(".json") }
        #expect(backups.count == 1)
        if let backup = backups.first {
            #expect(try Data(contentsOf: store.directory.appendingPathComponent(backup)) == corruptPayload)
        }
    }
}
