import CloudKit
import CoreBluetooth
import OurHoursCore
import SwiftUI
import UIKit

@main
struct OurHoursiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLaunchSplash = {
        #if DEBUG
        return ScreenshotScene.current == nil
        #else
        return true
        #endif
    }()
    @State private var launchSplashID = UUID()

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if let model = delegate.appModel {
                        #if DEBUG
                        RootFoamView(
                            appModel: model,
                            activeDebugPreset: delegate.activeDebugPreset,
                            onSelectDebugPreset: { delegate.selectDebugPreset($0) },
                            onReplayLaunchAnimation: {
                                launchSplashID = UUID()
                                showLaunchSplash = true
                            }
                        )
                        .id(delegate.modelSessionID)
                        #else
                        RootFoamView(appModel: model)
                        #endif
                    } else {
                        Color("LaunchBackground")
                            .ignoresSafeArea()
                    }
                }

                if showLaunchSplash, delegate.appModel != nil {
                    LaunchSplashOverlayView {
                        showLaunchSplash = false
                    }
                    .id(launchSplashID)
                    .zIndex(10)
                }
            }
            .preferredColorScheme(.light)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    delegate.handleForegroundActivation()
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    @Published private(set) var appModel: AppModel?
    private var liveAppModel: AppModel?
    #if DEBUG
    private var activePreviewHandle: DebugPreviewHandle?
    @Published private(set) var activeDebugPreset: DebugPreviewPreset?
    @Published private(set) var modelSessionID = UUID()
    #endif

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureAppearance()
        #if DEBUG
        if let scene = ScreenshotScene.current {
            appModel = ScreenshotDemo.makeAppModel(for: scene)
            return true
        }
        #endif
        let engine = OurHoursBLEEngine(enableStateRestoration: true)
        // A fresh install has no managers to restore. Allow its first prompt to follow the notice.
        if CBManager.authorization != .notDetermined {
            engine.start()
        }
        let model = AppModel(engine: engine)
        model.locationMonitor.startIfAuthorized()
        if options?[.location] != nil {
            model.handleBackgroundLocationLaunch()
        }
        appModel = model
        liveAppModel = model
        ShareSceneDelegate.appModel = model
        application.registerForRemoteNotifications()
        return true
    }

    func handleForegroundActivation() {
        liveAppModel?.handleForegroundActivation()
    }

    #if DEBUG
    func selectDebugPreset(_ preset: DebugPreviewPreset?) {
        guard ScreenshotScene.current == nil else { return }
        activePreviewHandle?.cleanup()
        activePreviewHandle = nil
        if let preset {
            let handle = DebugPreviewFactory.makeHandle(for: preset)
            activePreviewHandle = handle
            activeDebugPreset = preset
            appModel = handle.model
        } else {
            activeDebugPreset = nil
            appModel = liveAppModel
        }
        modelSessionID = UUID()
    }
    #endif

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              notification.subscriptionID == nil
                || notification.subscriptionID?.hasPrefix("ourhours.pairspace.") == true else {
            completionHandler(.noData)
            return
        }
        var finished = false
        let finish: @MainActor (UIBackgroundFetchResult) -> Void = { result in
            guard !finished else { return }
            finished = true
            completionHandler(result)
        }
        let timeout = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(25))
            } catch {
                return
            }
            finish(.failed)
        }
        Task { @MainActor in
            let result = await liveAppModel?.handleRemoteCloudKitPush() ?? .noData
            timeout.cancel()
            finish(result)
        }
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        liveAppModel?.handleAcceptedExternalShare(metadata)
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        if session.role == .windowApplication {
            configuration.delegateClass = ShareSceneDelegate.self
        }
        return configuration
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

@MainActor
private final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    static weak var appModel: AppModel?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let metadata = options.cloudKitShareMetadata {
            Self.appModel?.handleAcceptedExternalShare(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Self.appModel?.handleAcceptedExternalShare(metadata)
    }
}
