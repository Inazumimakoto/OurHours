import OurHoursCore
import SwiftUI

struct MacPeerSessionsView: View {
    let sessions: [EncounterSession]
    let mergedIntervals: [MergedReferenceInterval]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Encounter Sessions")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(sessions.count) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if sessions.isEmpty {
                ContentUnavailableView("No encounter sessions", systemImage: "clock")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !mergedIntervals.isEmpty {
                            mergedSummary
                                .padding(.bottom, 8)
                        }

                        ForEach(sessions.reversed()) { session in
                            Divider()
                            MacPeerSessionRow(session: session)
                                .padding(.vertical, 9)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mergedSummary: some View {
        DisclosureGroup {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(mergedIntervals.reversed()) { interval in
                    HStack {
                        Text(interval.startedAt.formatted(date: .abbreviated, time: .standard))
                        Text("–")
                            .accessibilityHidden(true)
                        Text(interval.endedAt.formatted(date: .abbreviated, time: .standard))
                        Spacer()
                        Text("\(interval.sessionIDs.count) sessions")
                        Text(sessionDuration(interval.durationSeconds))
                    }
                    .font(.caption.monospacedDigit())
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text("Merged Reference Intervals")
                    .fontWeight(.medium)
                Spacer()
                Text("\(mergedIntervals.count) intervals")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct MacPeerSessionRow: View {
    let session: EncounterSession

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start: \(session.startedAt.formatted(date: .abbreviated, time: .standard))")
                    if session.status == .completed, let end = session.endedAt {
                        Text("End: \(end.formatted(date: .abbreviated, time: .standard))")
                    }
                }
                .font(.callout.monospacedDigit())
                Spacer(minLength: 8)

                switch session.status {
                case .active:
                    MacPeerBadge(title: "Active", color: .green, icon: "circle.fill")
                case .unknownEnd:
                    MacPeerBadge(title: "終了不明", color: .orange, icon: "exclamationmark.triangle.fill")
                case .completed:
                    if let duration = session.durationSeconds {
                        MacPeerBadge(title: sessionDuration(duration), color: .secondary, icon: "clock")
                    }
                }
            }

            HStack(spacing: 8) {
                Text(session.connectionPath.rawValue)
                Text(session.startRole.rawValue)
                if let reason = session.endReason {
                    Text(reason.rawValue)
                }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)

            if let gap = session.gapFromPreviousSessionSeconds {
                Text("Previous gap: \(sessionDuration(gap))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let pending = session.isAutoReconnectPending {
                Text(pending ? "Auto-reconnect pending" : "Auto-reconnect not pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = session.disconnectErrorDescription {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .textSelection(.enabled)
    }
}

private func sessionDuration(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
}

#Preview("Unresolved Encounter") {
    MacPeerSessionsView(
        sessions: [
            EncounterSession(
                pairID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
                startedAt: Date(timeIntervalSince1970: 1_763_640_000),
                status: .unknownEnd,
                connectionPath: .autoReconnect,
                startRole: .central,
                endReason: .terminatedWhileActive
            )
        ],
        mergedIntervals: []
    )
    .frame(width: 600, height: 200)
}
