import Foundation
#if os(iOS)
import Synchronization
import UIKit
#endif

public final class DeviceMetricsProvider: Sendable {
    #if os(iOS)
    private struct Metrics: Sendable {
        var battery: Float?
        var appState = "unknown"
    }

    private let metrics = Mutex(Metrics())
    @MainActor private var observer: Observer?

    public init() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            observer = Observer(provider: self)
        }
    }

    public func batteryLevel() -> Float? { metrics.withLock { $0.battery } }
    public func appStateDescription() -> String { metrics.withLock { $0.appState } }

    @MainActor
    private final class Observer: NSObject {
        private weak var provider: DeviceMetricsProvider?

        init(provider: DeviceMetricsProvider) {
            self.provider = provider
            super.init()
            UIDevice.current.isBatteryMonitoringEnabled = true
            let notifications = [
                UIDevice.batteryLevelDidChangeNotification,
                UIApplication.didBecomeActiveNotification,
                UIApplication.willResignActiveNotification,
                UIApplication.willEnterForegroundNotification,
                UIApplication.didEnterBackgroundNotification
            ]
            for name in notifications {
                NotificationCenter.default.addObserver(self, selector: #selector(notified(_:)), name: name, object: nil)
            }
            refresh(nil)
        }

        @objc private nonisolated func notified(_ notification: Notification) {
            let name = notification.name
            DispatchQueue.main.async { [weak self] in self?.refresh(name) }
        }

        private func refresh(_ name: Notification.Name?) {
            let level = UIDevice.current.batteryLevel
            let appState: String
            switch name {
            case UIApplication.didBecomeActiveNotification: appState = "active"
            case UIApplication.willResignActiveNotification, UIApplication.willEnterForegroundNotification:
                appState = "inactive"
            case UIApplication.didEnterBackgroundNotification: appState = "background"
            default:
                switch UIApplication.shared.applicationState {
                case .active: appState = "active"
                case .inactive: appState = "inactive"
                case .background: appState = "background"
                @unknown default: appState = "unknown"
                }
            }
            provider?.metrics.withLock { $0 = Metrics(battery: level >= 0 ? level : nil, appState: appState) }
        }
    }
    #else
    public init() {}
    public func batteryLevel() -> Float? { nil }
    public func appStateDescription() -> String { "active" }
    #endif
}
