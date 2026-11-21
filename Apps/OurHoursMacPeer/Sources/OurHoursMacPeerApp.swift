import AppKit
import SwiftUI

@main
struct OurHoursMacPeerApp: App {
    @State private var model = MacPeerModel()

    var body: some Scene {
        WindowGroup("OurHours Mac Peer") {
            MacPeerDashboardView(model: model)
                .frame(minWidth: 960, minHeight: 680)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.handleForegroundActivation()
                }
        }
        .defaultSize(width: 1120, height: 820)
        .windowResizability(.contentMinSize)
    }
}
