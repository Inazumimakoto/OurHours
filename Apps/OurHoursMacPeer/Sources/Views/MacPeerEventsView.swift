import OurHoursCore
import SwiftUI

struct MacPeerEventsView: View {
    let model: MacPeerModel

    @State private var searchText = ""
    @State private var category: EventCategory?
    @State private var alert: EventAlert?

    private enum EventAlert: Identifiable {
        case clearLogs
        case exportFailed(String)

        var id: String {
            switch self {
            case .clearLogs: "clearLogs"
            case .exportFailed: "exportFailed"
            }
        }
    }

    var body: some View {
        let events = filteredEvents
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if events.isEmpty {
                ContentUnavailableView(
                    model.snapshot.recentEvents.isEmpty ? "No diagnostic events" : "No matching events",
                    systemImage: "list.bullet.rectangle"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(events) { event in
                            MacPeerEventRow(event: event)
                                .padding(.vertical, 8)
                            Divider()
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(item: $alert) { alert in
            switch alert {
            case .clearLogs:
                Alert(
                    title: Text("Clear diagnostic logs?"),
                    message: Text("This deletes saved events and encounter sessions and resets active links."),
                    primaryButton: .destructive(Text("Clear Logs"), action: model.clearLogs),
                    secondaryButton: .cancel()
                )
            case .exportFailed(let message):
                Alert(title: Text("Export Failed"), message: Text(message))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Diagnostic Events")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Clear Logs") { alert = .clearLogs }
                Menu("Export") {
                    Button("JSON") { export(.json) }
                    Button("Sessions CSV") { export(.sessionsCSV) }
                    Button("Events CSV") { export(.eventsCSV) }
                }
                .fixedSize()
                .disabled(model.isExporting)
            }

            HStack(spacing: 12) {
                TextField("Search events", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("Category", selection: $category) {
                    Text("All Categories").tag(nil as EventCategory?)
                    ForEach(EventCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(Optional(category))
                    }
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var filteredEvents: [DiagnosticEvent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.snapshot.recentEvents.reversed().filter { event in
            guard category == nil || event.category == category else { return false }
            return query.isEmpty
                || event.category.rawValue.localizedStandardContains(query)
                || event.kind.localizedStandardContains(query)
                || event.message.localizedStandardContains(query)
                || event.metadata.contains {
                    $0.key.localizedStandardContains(query) || $0.value.localizedStandardContains(query)
                }
        }
    }

    private func export(_ format: MacPeerModel.ExportFormat) {
        Task {
            do {
                try await model.export(format)
            } catch {
                alert = .exportFailed(error.localizedDescription)
            }
        }
    }
}

private struct MacPeerEventRow: View {
    let event: DiagnosticEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                MacPeerBadge(title: event.category.rawValue, color: .secondary)
                Text(event.kind)
                    .font(.caption.monospaced().weight(.medium))
            }
            Text(event.message)
                .font(.callout)

            if !event.metadata.isEmpty {
                Text(event.metadata.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " · "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}
