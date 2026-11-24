@preconcurrency import CoreLocation
import Foundation
import Observation
import OurHoursCore
import UIKit

/// Background + foreground precise location collector with visits, SLC, and dynamic 100m exit geofencing.
@MainActor
@Observable
final class LocationPresenceMonitor: NSObject, CLLocationManagerDelegate {
    private static let enabledKey = "ourhours.locationPresenceEnabled"
    private static let legacyWakeKey = "ourhours.locationWakeEnabled"
    private static let anchorRegionID = "ourhours.anchor"
    private static let anchorRadiusMeters: CLLocationDistance = 100

    private let manager: CLLocationManager
    private let defaults: UserDefaults
    private let onVisit: @MainActor (LocationVisitRecord, Bool) -> Void
    private let onPoint: @MainActor (LocationPointSample) -> Void
    private let onWake: @MainActor (String) -> Void

    private var pendingAlwaysUpgrade = false
    private var pendingFixSource: LocationSampleSource = .foregroundFix
    private var lastAnchorCoordinate: CLLocationCoordinate2D?
    private var fixBackgroundTaskID = UIBackgroundTaskIdentifier.invalid
    private var pendingFixContinuations: [(id: UUID, continuation: CheckedContinuation<Void, Never>)] = []
    private var lastCoarseRetryAt = Date.distantPast
    private var lastWakeAtBySource: [String: Date] = [:]

    private(set) var isEnabled: Bool
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var accuracyAuthorization: CLAccuracyAuthorization
    private(set) var isMonitoring = false
    private(set) var lastCaptureDate: Date?

    init(
        defaults: UserDefaults = .standard,
        onVisit: @escaping @MainActor (LocationVisitRecord, Bool) -> Void,
        onPoint: @escaping @MainActor (LocationPointSample) -> Void,
        onWake: @escaping @MainActor (String) -> Void
    ) {
        self.defaults = defaults
        self.onVisit = onVisit
        self.onPoint = onPoint
        self.onWake = onWake
        self.manager = CLLocationManager()

        if defaults.object(forKey: Self.enabledKey) != nil {
            self.isEnabled = defaults.bool(forKey: Self.enabledKey)
        } else if defaults.object(forKey: Self.legacyWakeKey) != nil {
            self.isEnabled = defaults.bool(forKey: Self.legacyWakeKey)
        } else {
            self.isEnabled = false
        }

        self.authorizationStatus = manager.authorizationStatus
        self.accuracyAuthorization = manager.accuracyAuthorization
        super.init()

        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.pausesLocationUpdatesAutomatically = true
        manager.delegate = self
    }

    var isReducedAccuracyWarning: Bool {
        isEnabled
            && (authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse)
            && accuracyAuthorization == .reducedAccuracy
    }

    var needsSettingsGuidance: Bool {
        isEnabled && (
            authorizationStatus == .authorizedWhenInUse
                || authorizationStatus == .denied
                || authorizationStatus == .restricted
                || accuracyAuthorization == .reducedAccuracy
        )
    }

    var statusDescription: String {
        guard isEnabled else { return "オフ" }
        switch authorizationStatus {
        case .authorizedAlways:
            if accuracyAuthorization == .reducedAccuracy {
                return "稼働中（「正確な位置情報」オフのため精度不足）"
            }
            return isMonitoring ? "稼働中（正確な位置・常に許可）" : "許可済み（開始待機中）"
        case .authorizedWhenInUse:
            return "「使用中のみ」許可（バックグラウンド補完には「常に許可」が必要）"
        case .notDetermined:
            return "許可待ち"
        case .denied, .restricted:
            return "未許可（設定から許可してください）"
        @unknown default:
            return "確認中"
        }
    }

    func startIfAuthorized() {
        refreshStatus()
        guard isEnabled, authorizationStatus == .authorizedAlways else {
            stopMonitoring()
            return
        }
        startMonitoring()
    }

    func enableAndRequestAuthorization() {
        isEnabled = true
        defaults.set(true, forKey: Self.enabledKey)
        refreshStatus()

        switch authorizationStatus {
        case .notDetermined:
            pendingAlwaysUpgrade = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            pendingAlwaysUpgrade = true
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            pendingAlwaysUpgrade = false
            startMonitoring()
            requestFreshFix(source: .foregroundFix)
        case .denied, .restricted:
            pendingAlwaysUpgrade = false
            stopMonitoring()
        @unknown default:
            break
        }
    }

    func disable() {
        isEnabled = false
        pendingAlwaysUpgrade = false
        defaults.set(false, forKey: Self.enabledKey)
        stopMonitoring()
    }

    func requestFreshFix(source: LocationSampleSource) {
        requestFreshFix(source: source, preserveSource: false)
    }

    func requestFreshFixAndWait(source: LocationSampleSource, timeoutSeconds: TimeInterval = 4.0) async {
        refreshStatus()
        guard isEnabled else { return }
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else { return }
        let waiterID = UUID()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pendingFixContinuations.append((id: waiterID, continuation: continuation))
            requestFreshFix(source: source, preserveSource: false)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(max(0.5, timeoutSeconds)))
                self?.resumeFixWaiter(id: waiterID)
            }
        }
    }

    private func requestFreshFix(source: LocationSampleSource, preserveSource: Bool) {
        refreshStatus()
        guard isEnabled else {
            finishPendingFixRequest()
            return
        }
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            finishPendingFixRequest()
            return
        }
        if !preserveSource {
            pendingFixSource = source
        }
        beginFixBackgroundTaskIfNeeded()
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.requestLocation()
    }

    private func beginFixBackgroundTaskIfNeeded() {
        guard fixBackgroundTaskID == .invalid else { return }
        fixBackgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "OurHoursLocationFix") { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishPendingFixRequest()
            }
        }
    }

    private func endFixBackgroundTaskIfNeeded() {
        if fixBackgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(fixBackgroundTaskID)
            fixBackgroundTaskID = .invalid
        }
    }

    private func finishPendingFixRequest() {
        endFixBackgroundTaskIfNeeded()
        let waiters = pendingFixContinuations
        pendingFixContinuations.removeAll()
        for waiter in waiters {
            waiter.continuation.resume()
        }
    }

    private func resumeFixWaiter(id: UUID) {
        guard let index = pendingFixContinuations.firstIndex(where: { $0.id == id }) else { return }
        let waiter = pendingFixContinuations.remove(at: index)
        waiter.continuation.resume()
        if pendingFixContinuations.isEmpty {
            endFixBackgroundTaskIfNeeded()
        }
    }

    private func emitWake(_ source: String) {
        let now = Date.now
        if let last = lastWakeAtBySource[source], now.timeIntervalSince(last) < 5 {
            return
        }
        lastWakeAtBySource[source] = now
        onWake(source)
    }

    private nonisolated func runOnMainActor(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            Task { @MainActor in work() }
        }
    }

    private func startMonitoring() {
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.allowsBackgroundLocationUpdates = (authorizationStatus == .authorizedAlways)
        guard !isMonitoring else { return }
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
        manager.startMonitoringVisits()
        isMonitoring = true
    }

    private func stopMonitoring() {
        clearAnchorRegion()
        finishPendingFixRequest()
        manager.allowsBackgroundLocationUpdates = false
        guard isMonitoring else { return }
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        isMonitoring = false
    }

    private func updateAnchorRegionIfNeeded(latitude: Double, longitude: Double, accuracy: Double) {
        guard isEnabled, authorizationStatus == .authorizedAlways else { return }
        guard accuracy >= 0, accuracy <= 100 else { return }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        if let prev = lastAnchorCoordinate {
            let moved = LocationProximityMatcher.haversineMeters(
                lat1: prev.latitude, lon1: prev.longitude,
                lat2: latitude, lon2: longitude
            )
            if moved < 25 { return }
        }

        clearAnchorRegion()
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = CLCircularRegion(
            center: center,
            radius: Self.anchorRadiusMeters,
            identifier: Self.anchorRegionID
        )
        region.notifyOnExit = true
        region.notifyOnEntry = false
        manager.startMonitoring(for: region)
        lastAnchorCoordinate = center
    }

    private func clearAnchorRegion() {
        for region in manager.monitoredRegions where region.identifier == Self.anchorRegionID {
            manager.stopMonitoring(for: region)
        }
        lastAnchorCoordinate = nil
    }

    private func refreshStatus() {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
    }

    private func handleAuthChange() {
        refreshStatus()
        switch authorizationStatus {
        case .authorizedAlways:
            pendingAlwaysUpgrade = false
            if isEnabled {
                startMonitoring()
                requestFreshFix(source: .foregroundFix)
            }
        case .authorizedWhenInUse:
            if isEnabled && pendingAlwaysUpgrade {
                manager.requestAlwaysAuthorization()
            } else {
                stopMonitoring()
            }
        case .denied, .restricted, .notDetermined:
            pendingAlwaysUpgrade = false
            stopMonitoring()
        @unknown default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        runOnMainActor { [weak self] in
            self?.handleAuthChange()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.map { (
            timestamp: $0.timestamp,
            latitude: $0.coordinate.latitude,
            longitude: $0.coordinate.longitude,
            accuracy: $0.horizontalAccuracy
        ) }

        runOnMainActor { [weak self] in
            guard let self else { return }
            guard self.isEnabled else {
                self.finishPendingFixRequest()
                return
            }
            let now = Date.now
            self.lastCaptureDate = now

            let valid = samples.filter { $0.accuracy >= 0 }
            let recent = valid.filter { now.timeIntervalSince($0.timestamp) <= 180 }
            let chosen: (timestamp: Date, latitude: Double, longitude: Double, accuracy: Double)?
            if let freshBest = recent.min(by: { $0.accuracy < $1.accuracy }) {
                chosen = freshBest
            } else {
                let acceptable = valid.filter { now.timeIntervalSince($0.timestamp) <= 900 }
                chosen = acceptable.max(by: { $0.timestamp < $1.timestamp })
            }
            self.finishPendingFixRequest()

            guard let best = chosen else { return }

            if best.accuracy <= LocationProximityMatcher.maxAcceptedAccuracyMeters {
                let source = self.pendingFixSource
                self.pendingFixSource = .significantChange
                let point = LocationPointSample(
                    timestamp: best.timestamp,
                    latitude: best.latitude,
                    longitude: best.longitude,
                    horizontalAccuracy: best.accuracy,
                    source: source
                )
                self.onPoint(point)
                self.updateAnchorRegionIfNeeded(latitude: best.latitude, longitude: best.longitude, accuracy: best.accuracy)
            } else if self.accuracyAuthorization == .fullAccuracy,
                      now.timeIntervalSince(self.lastCoarseRetryAt) >= 60 {
                self.lastCoarseRetryAt = now
                self.requestFreshFix(source: self.pendingFixSource, preserveSource: true)
            }
            self.emitWake("significantLocation")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let lat = visit.coordinate.latitude
        let lon = visit.coordinate.longitude
        let acc = visit.horizontalAccuracy
        let rawArrival = visit.arrivalDate
        let rawDeparture = visit.departureDate

        runOnMainActor { [weak self] in
            guard let self, self.isEnabled else { return }
            let now = Date.now
            self.lastCaptureDate = now

            let arrivalUnknown = (rawArrival == .distantPast)
            let departedAt: Date? = (rawDeparture == .distantFuture) ? nil : rawDeparture
            let arrivedAt = arrivalUnknown ? (departedAt ?? now) : rawArrival
            let record = LocationVisitRecord(
                latitude: lat,
                longitude: lon,
                horizontalAccuracy: acc,
                arrivedAt: arrivedAt,
                departedAt: departedAt,
                recordedAt: now
            )
            self.onVisit(record, arrivalUnknown)
            self.updateAnchorRegionIfNeeded(latitude: lat, longitude: lon, accuracy: acc)
            self.emitWake(departedAt == nil ? "locationVisitArrival" : "locationVisitDeparture")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let regionID = region.identifier
        runOnMainActor { [weak self] in
            guard let self, self.isEnabled, regionID == Self.anchorRegionID else { return }
            self.clearAnchorRegion()
            self.requestFreshFix(source: .geofenceExit)
            self.emitWake("geofenceExit")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Transient CoreLocation errors are non-fatal; subsequent visit/SLC wakes will retry.
        runOnMainActor { [weak self] in
            self?.finishPendingFixRequest()
        }
    }
}
