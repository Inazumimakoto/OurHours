import Foundation
import Testing
@testable import OurHoursCore

struct SessionCoordinatorTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)
    private let pairID = UUID()
    private let central = ActiveLinkKey.central(UUID())
    private let peripheral = ActiveLinkKey.peripheral(UUID())

    @Test func firstLinkStartsSession() throws {
        var coordinator = SessionCoordinator()
        let started = coordinator.linkAuthenticated(
            central, pairID: pairID, at: start, connectionPath: .scanDiscovery, batteryLevel: 0.5
        )
        let session = try #require(started)
        #expect(coordinator.activeSession == session)
        #expect(coordinator.activeLinks == [central])
        #expect(session.status == .active)
        #expect(session.endedAt == nil)
        #expect(session.durationSeconds == nil)
        #expect(session.batteryLevelAtStart == 0.5)
        #expect(session.startRole == .central)
    }

    @Test func twoLinksKeepOneSessionUntilFinalDisconnect() throws {
        var coordinator = SessionCoordinator()
        let started = coordinator.linkAuthenticated(
            central, pairID: pairID, at: start, connectionPath: .scanDiscovery
        )
        let session = try #require(started)
        #expect(coordinator.linkAuthenticated(
            peripheral, pairID: pairID, at: start.addingTimeInterval(1), connectionPath: .incomingPeripheral
        ) == nil)
        #expect(coordinator.activeLinks == [central, peripheral])
        #expect(coordinator.linkDisconnected(peripheral, at: start.addingTimeInterval(2), endReason: .peerUnsubscribed) == nil)
        #expect(coordinator.activeSession == session)
        #expect(coordinator.activeLinks == [central])
        let end = start.addingTimeInterval(90)
        let completed = coordinator.linkDisconnected(
            central, at: end, endReason: .disconnected, disconnectErrorDescription: "link lost",
            isAutoReconnectPending: true, batteryLevel: 0.25
        )
        let result = try #require(completed)
        #expect(result.id == session.id)
        #expect(result.endedAt == end)
        #expect(result.durationSeconds == 90)
        #expect(result.disconnectErrorDescription == "link lost")
        #expect(result.isAutoReconnectPending == true)
        #expect(result.batteryLevelAtEnd == 0.25)
        #expect(coordinator.activeSession == nil)
        #expect(coordinator.linkDisconnected(central, at: end, endReason: .disconnected) == nil)
        let second = coordinator.linkAuthenticated(
            central, pairID: pairID, at: end.addingTimeInterval(30), connectionPath: .autoReconnect
        )
        #expect(second?.gapFromPreviousSessionSeconds == 30)
    }

    @Test func previousCompletedSessionMustBelongToPair() {
        let other = EncounterSession(
            pairID: UUID(), startedAt: start, endedAt: start.addingTimeInterval(12),
            status: .completed, connectionPath: .incomingPeripheral, startRole: .peripheral
        )
        var coordinator = SessionCoordinator(sessions: [other])
        let next = coordinator.linkAuthenticated(
            central, pairID: pairID, at: start.addingTimeInterval(60), connectionPath: .scanDiscovery
        )
        #expect(next?.gapFromPreviousSessionSeconds == nil)
    }

    @Test func launchWithoutLinksLeavesEndUnknown() throws {
        let persisted = EncounterSession(pairID: pairID, startedAt: start, connectionPath: .scanDiscovery, startRole: .central)
        var coordinator = SessionCoordinator(sessions: [persisted])
        coordinator.reconcileActiveSessionsOnLaunch(now: start.addingTimeInterval(50_000), restoredActiveLinks: [])
        let reconciled = try #require(coordinator.sessions.first)
        #expect(reconciled.id == persisted.id)
        #expect(reconciled.status == .unknownEnd)
        #expect(reconciled.endedAt == nil)
        #expect(reconciled.endReason == .terminatedWhileActive)
        #expect(reconciled.durationSeconds == nil)
        #expect(coordinator.activeSession == nil)
    }

    @Test func launchWithRestoredLinkKeepsOriginalSession() {
        let persisted = EncounterSession(pairID: pairID, startedAt: start, connectionPath: .scanDiscovery, startRole: .central)
        var coordinator = SessionCoordinator(sessions: [persisted])
        coordinator.reconcileActiveSessionsOnLaunch(now: start.addingTimeInterval(100), restoredActiveLinks: [central])
        #expect(coordinator.activeSession == persisted)
        #expect(coordinator.activeLinks == [central])
    }

    @Test(arguments: [SessionEndReason.unpaired, .autoRecordingDisabled])
    func controlChangeEndsImmediately(reason: SessionEndReason) throws {
        var coordinator = SessionCoordinator()
        coordinator.linkAuthenticated(central, pairID: pairID, at: start, connectionPath: .scanDiscovery)
        coordinator.linkAuthenticated(peripheral, pairID: pairID, at: start, connectionPath: .incomingPeripheral)
        let end = start.addingTimeInterval(10)
        let completed = coordinator.endActiveSessionForControlChange(at: end, endReason: reason, batteryLevel: 0.75)
        let session = try #require(completed)
        #expect(session.status == .completed)
        #expect(session.endedAt == end)
        #expect(session.endReason == reason)
        #expect(session.batteryLevelAtEnd == 0.75)
        #expect(coordinator.activeLinks.isEmpty)
        #expect(coordinator.activeSession == nil)
    }

    @Test func durationRequiresCompletedStatusAndEnd() {
        var session = EncounterSession(
            pairID: pairID, startedAt: start, endedAt: start.addingTimeInterval(10),
            status: .unknownEnd, connectionPath: .scanDiscovery, startRole: .central
        )
        #expect(session.durationSeconds == nil)
        session.status = .active
        #expect(session.durationSeconds == nil)
        session.status = .completed
        #expect(session.durationSeconds == 10)
        session.endedAt = nil
        #expect(session.durationSeconds == nil)
    }

    @Test func mergeThresholdOverlapAndPairIsolation() {
        func session(_ from: TimeInterval, _ to: TimeInterval, pair: UUID, status: SessionStatus = .completed) -> EncounterSession {
            EncounterSession(
                pairID: pair, startedAt: start.addingTimeInterval(from), endedAt: start.addingTimeInterval(to),
                status: status, connectionPath: .scanDiscovery, startRole: .central
            )
        }
        let a = session(0, 100, pair: pairID)
        let overlap = session(20, 60, pair: pairID)
        let b = session(400, 500, pair: pairID)
        let c = session(801, 900, pair: pairID)
        let unknown = session(600, 800, pair: pairID, status: .unknownEnd)
        let other = session(50, 500, pair: UUID())
        let raw = [c, b, unknown, other, a, overlap]
        let merged = EncounterSession.mergedReferenceIntervals(from: raw)
        #expect(merged.map(\.sessionIDs) == [[a.id, overlap.id, b.id], [other.id], [c.id]])
        #expect(merged.first?.durationSeconds == 500)
        #expect(EncounterSession.mergedReferenceIntervals(from: raw, maxGapSeconds: 299).count == 4)
        #expect(raw[4] == a)
    }

    @Test func heartbeatUpdatesLastSeenAtAndPreservesAcrossTerminatedReconcile() {
        var coordinator = SessionCoordinator()
        #expect(coordinator.recordActiveHeartbeat(at: start.addingTimeInterval(300)) == nil)

        let started = coordinator.linkAuthenticated(central, pairID: pairID, at: start, connectionPath: .scanDiscovery)
        #expect(started?.lastSeenAt == nil)
        #expect(coordinator.activeSession?.effectiveLastSeenAt == start)
        #expect(coordinator.recordActiveHeartbeat(at: start.addingTimeInterval(179)) == nil)

        let t1 = start.addingTimeInterval(180)
        let pulsed = coordinator.recordActiveHeartbeat(at: t1)
        #expect(pulsed?.lastSeenAt == t1)
        #expect(coordinator.activeSession?.effectiveLastSeenAt == t1)
        #expect(coordinator.recordActiveHeartbeat(at: t1) == nil)

        coordinator.reconcileActiveSessionsOnLaunch(now: start.addingTimeInterval(500), restoredActiveLinks: [])
        #expect(coordinator.sessions.count == 1)
        #expect(coordinator.sessions[0].status == .unknownEnd)
        #expect(coordinator.sessions[0].endReason == .terminatedWhileActive)
        #expect(coordinator.sessions[0].lastSeenAt == t1)
        #expect(coordinator.sessions[0].effectiveLastSeenAt == t1)
    }

    @Test func terminatedWhileActiveResumesWithinWindowUsingHeartbeat() {
        let heartbeat = start.addingTimeInterval(1200)
        let persisted = EncounterSession(
            pairID: pairID,
            startedAt: start,
            lastSeenAt: heartbeat,
            status: .active,
            connectionPath: .scanDiscovery,
            startRole: .central
        )
        var coordinator = SessionCoordinator(sessions: [persisted])
        coordinator.reconcileActiveSessionsOnLaunch(now: heartbeat.addingTimeInterval(30), restoredActiveLinks: [])
        #expect(coordinator.sessions[0].status == .unknownEnd)

        let reconnectAt = heartbeat.addingTimeInterval(500)
        let resumed = coordinator.linkAuthenticated(
            peripheral,
            pairID: pairID,
            at: reconnectAt,
            connectionPath: .incomingPeripheral
        )
        #expect(resumed?.id == persisted.id)
        #expect(resumed?.status == .active)
        #expect(resumed?.startedAt == start)
        #expect(resumed?.endedAt == nil)
        #expect(resumed?.endReason == nil)
        #expect(resumed?.lastSeenAt == reconnectAt)
        #expect(coordinator.sessions.count == 1)

        let end = start.addingTimeInterval(3600)
        let completed = coordinator.linkDisconnected(peripheral, at: end, endReason: .disconnected)
        #expect(completed?.id == persisted.id)
        #expect(completed?.durationSeconds == 3600)
    }

    @Test func terminatedWhileActiveDoesNotResumePastWindowOrMismatch() {
        let heartbeat = start.addingTimeInterval(600)
        let terminated = EncounterSession(
            pairID: pairID,
            startedAt: start,
            lastSeenAt: heartbeat,
            status: .unknownEnd,
            connectionPath: .scanDiscovery,
            startRole: .central,
            endReason: .terminatedWhileActive
        )
        var expiredCoordinator = SessionCoordinator(sessions: [terminated])
        let lateSession = expiredCoordinator.linkAuthenticated(
            central,
            pairID: pairID,
            at: heartbeat.addingTimeInterval(BLEConstants.terminatedSessionResumeWindowSeconds + 1),
            connectionPath: .scanDiscovery
        )
        #expect(lateSession?.id != terminated.id)
        #expect(expiredCoordinator.sessions.count == 2)
        #expect(expiredCoordinator.sessions[0].status == .unknownEnd)

        var wrongReasonSession = terminated
        wrongReasonSession.endReason = .disconnected
        var reasonCoordinator = SessionCoordinator(sessions: [wrongReasonSession])
        let reasonNew = reasonCoordinator.linkAuthenticated(
            central,
            pairID: pairID,
            at: heartbeat.addingTimeInterval(60),
            connectionPath: .scanDiscovery
        )
        #expect(reasonNew?.id != terminated.id)
        #expect(reasonCoordinator.sessions.count == 2)

        var pairCoordinator = SessionCoordinator(sessions: [terminated])
        let otherPairSession = pairCoordinator.linkAuthenticated(
            central,
            pairID: UUID(),
            at: heartbeat.addingTimeInterval(60),
            connectionPath: .scanDiscovery
        )
        #expect(otherPairSession?.id != terminated.id)
        #expect(pairCoordinator.sessions.count == 2)
    }

    @Test func legacySessionJSONWithoutLastSeenAtDecodes() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "pairID": "22222222-2222-2222-2222-222222222222",
          "startedAt": 1700000000,
          "status": "active",
          "connectionPath": "scanDiscovery",
          "startRole": "central"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(EncounterSession.self, from: Data(json.utf8))
        #expect(decoded.lastSeenAt == nil)
        #expect(decoded.effectiveLastSeenAt == Date(timeIntervalSince1970: 1_700_000_000))
    }
}
