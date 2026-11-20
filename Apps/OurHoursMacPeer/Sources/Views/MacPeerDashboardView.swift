import OurHoursCore
import SwiftUI

struct MacPeerDashboardView: View {
    let model: MacPeerModel

    var body: some View {
        HSplitView {
            MacPeerControlsView(model: model)
                .frame(minWidth: 348, idealWidth: 364, maxWidth: 420)

            VStack(spacing: 0) {
                MacPeerTelemetryHeader(snapshot: model.snapshot)
                Divider()
                VSplitView {
                    MacPeerSessionsView(
                        sessions: model.snapshot.sessions,
                        mergedIntervals: model.mergedIntervals
                    )
                    .frame(minHeight: 155, idealHeight: 255)

                    MacPeerEventsView(model: model)
                        .frame(minHeight: 200)
                }
            }
            .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MacPeerTelemetryHeader: View {
    let snapshot: EngineSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live BLE Status")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let path = snapshot.activeSession?.connectionPath ?? snapshot.lastConnectionPath {
                    MacPeerBadge(title: path.rawValue, color: .blue, icon: "point.topleft.down.to.point.bottomright.curvepath")
                        .accessibilityLabel("Connection path: \(path.rawValue)")
                }
            }

            HStack(alignment: .top, spacing: 20) {
                radioState("Central", state: snapshot.centralState)
                radioState("Peripheral", state: snapshot.peripheralState)
                radioState("Active Links", state: String(snapshot.activeLinkCount))
                Spacer(minLength: 0)
                radioState("Last Authentication", state: snapshot.lastAuthDate.map {
                    $0.formatted(date: .abbreviated, time: .standard)
                } ?? "—")
            }

            HStack(spacing: 8) {
                MacPeerBadge(
                    title: snapshot.isScanning ? "Scanning on" : "Scanning off",
                    color: snapshot.isScanning ? .green : .secondary,
                    icon: "magnifyingglass"
                )
                MacPeerBadge(
                    title: snapshot.isAdvertising ? "Advertising on" : "Advertising off",
                    color: snapshot.isAdvertising ? .green : .secondary,
                    icon: "antenna.radiowaves.left.and.right"
                )
            }

            if !snapshot.activeLinksSummary.isEmpty {
                let summary = snapshot.activeLinksSummary.joined(separator: "\n")
                Text(summary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(summary)
                    .textSelection(.enabled)
            }

            if let error = snapshot.lastErrorMessage {
                Label {
                    Text("Last BLE error: \(error)")
                        .lineLimit(3)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.callout)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                .help(error)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35))
    }

    private func radioState(_ label: String, state: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(state)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MacPeerBadge: View {
    let title: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .accessibilityHidden(true)
            }
            Text(title)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .fixedSize()
    }
}

#Preview("Live BLE Status") {
    MacPeerTelemetryHeader(snapshot: EngineSnapshot(
        centralState: "poweredOn",
        peripheralState: "poweredOn",
        isAdvertising: true,
        activeLinkCount: 1,
        activeLinksSummary: ["peripheral: 00000000-0000-0000-0000-000000000001"],
        lastConnectionPath: .incomingPeripheral,
        lastAuthDate: Date(timeIntervalSince1970: 1_763_640_000)
    ))
    .frame(width: 600)
}
