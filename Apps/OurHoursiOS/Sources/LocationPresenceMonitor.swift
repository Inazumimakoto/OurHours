@preconcurrency import CoreLocation
import Foundation
import Observation
import OurHoursCore

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
        refreshStatus()
        guard isEnabled else { return }
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else { return }
        pendingFixSource = source
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.requestLocation()
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
        manager.allowsBackgroundLocationUpdates = false
        guard isMonitoring else { return }
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        isMonitoring = false
    }

    private func updateAnchorRegionIfNeeded(latitude: Double, longitude: Double, accuracy: Double) {
        guard isEnabled, authorizationStatus == .authorizedAlways else { return }
        guard accuracy >= 0, accuracy <= 65 else { return }
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
        Task { @MainActor [weak self] in
            self?.handleAuthChange()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let best = locations
            .filter { $0.horizontalAccuracy >= 0 }
            .min { $0.horizontalAccuracy < $1.horizontalAccuracy } ?? locations.last
        guard let best else { return }
        let lat = best.coordinate.latitude
        let lon = best.coordinate.longitude
        let acc = best.horizontalAccuracy
        let timestamp = best.timestamp

        Task { @MainActor [weak self] in
            guard let self, self.isEnabled else { return }
            let now = Date.now
            self.lastCaptureDate = now

            if acc >= 0 && acc <= LocationProximityMatcher.maxAcceptedAccuracyMeters {
                let source = self.pendingFixSource
                self.pendingFixSource = .significantChange
                let point = LocationPointSample(
                    timestamp: timestamp,
                    latitude: lat,
                    longitude: lon,
                    horizontalAccuracy: acc,
                    source: source
                )
                self.onPoint(point)
                self.updateAnchorRegionIfNeeded(latitude: lat, longitude: lon, accuracy: acc)
            } else {
                self.requestFreshFix(source: .significantChange)
            }
            self.onWake("significantLocation")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let lat = visit.coordinate.latitude
        let lon = visit.coordinate.longitude
        let acc = visit.horizontalAccuracy
        let rawArrival = visit.arrivalDate
        let rawDeparture = visit.departureDate

        Task { @MainActor [weak self] in
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
            self.onWake(departedAt == nil ? "locationVisitArrival" : "locationVisitDeparture")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let regionID = region.identifier
        Task { @MainActor [weak self] in
            guard let self, self.isEnabled, regionID == Self.anchorRegionID else { return }
            self.clearAnchorRegion()
            self.requestFreshFix(source: .geofenceExit)
            self.onWake("geofenceExit")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Transient CoreLocation errors are non-fatal; subsequent visit/SLC wakes will retry.
    }
}
