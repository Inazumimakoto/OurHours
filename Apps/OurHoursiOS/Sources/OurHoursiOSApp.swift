import CoreBluetooth
import OurHoursCore
import SwiftUI
import UIKit

@main
struct OurHoursiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let model = delegate.appModel {
                    RootFoamView(appModel: model)
                } else {
                    ProgressView()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    delegate.appModel?.handleForegroundActivation()
                }
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
        configureAppearance()
        let engine = OurHoursBLEEngine(enableStateRestoration: true)
        // A fresh install has no managers to restore. Allow its first prompt to follow the notice.
        if CBManager.authorization != .notDetermined || engine.currentSnapshot().isPaired {
            engine.start()
        }
        let model = AppModel(engine: engine)
        model.locationMonitor.startIfAuthorized()
        if options?[.location] != nil {
            model.handleBackgroundLocationLaunch()
        }
        appModel = model
        return true
    }

    private func configureAppearance() {
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        navAppearance.titleTextAttributes = [
            .font: FoamFont.uiBold(18),
            .foregroundColor: UIColor(FoamTheme.ink)
        ]
        navAppearance.largeTitleTextAttributes = [
            .font: FoamFont.uiBold(30),
            .foregroundColor: UIColor(FoamTheme.ink)
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        let barAttributes: [NSAttributedString.Key: Any] = [
            .font: FoamFont.uiBold(16)
        ]
        UIBarButtonItem.appearance().setTitleTextAttributes(barAttributes, for: .normal)
        UIBarButtonItem.appearance().setTitleTextAttributes(barAttributes, for: .highlighted)
    }
}
