import SwiftUI

@main
struct OurHoursMacPeerApp: App {
    @State private var model = MacPeerModel()

    var body: some Scene {
        WindowGroup("OurHours Mac Peer") {
            MacPeerDashboardView(model: model)
                .frame(minWidth: 960, minHeight: 680)
        }
        .defaultSize(width: 1120, height: 820)
        .windowResizability(.contentMinSize)
    }
}
