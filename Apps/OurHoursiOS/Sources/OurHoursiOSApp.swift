import CoreBluetooth
import OurHoursCore
import SwiftUI

@main
struct OurHoursiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            if let model = delegate.appModel {
                RootTabView(appModel: model)
            } else {
                ProgressView()
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    @Published private(set) var appModel: AppModel?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let engine = OurHoursBLEEngine(enableStateRestoration: true)
        // A fresh install has no managers to restore. Allow its first prompt to follow the notice.
        if CBManager.authorization != .notDetermined || engine.currentSnapshot().isPaired {
            engine.start()
        }
        appModel = AppModel(engine: engine)
        return true
    }
}
