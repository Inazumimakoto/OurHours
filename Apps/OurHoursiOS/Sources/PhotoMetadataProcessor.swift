import AVFoundation
@preconcurrency import CoreLocation
import CoreTransferable
import Foundation
import ImageIO
import MapKit
import OurHoursCore
import UIKit
import UniformTypeIdentifiers

struct PickedVideoFile: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copyURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("oh-picked-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copyURL)
            return Self(url: copyURL)
        }
    }
}

struct ProcessedDayPhoto: Sendable {
    let jpegData: Data
    let coordinate: GeoCoordinate?
    let capturedAt: Date?
}

struct ProcessedDayVideo: Sendable {
    let videoData: Data
    let thumbnailJPEGData: Data
    let durationSeconds: Double
    let coordinate: GeoCoordinate?
    let capturedAt: Date?
}

struct ReverseGeocodeDetails: Sendable {
    let name: String
    let address: String?
}

enum PhotoMetadataProcessor {
    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()

    static func loadNormalizedImage(from rawData: Data, maxPixelDimension: CGFloat = 1400) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(rawData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    static func processDayPhoto(
        from rawData: Data,
        maxPixelDimension: CGFloat = 1600,
        jpegQuality: CGFloat = 0.80
    ) -> ProcessedDayPhoto? {
        guard let source = CGImageSourceCreateWithData(rawData as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let coordinate = extractCoordinate(from: properties)
        let capturedAt = extractCaptureDate(from: properties)

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        // Re-encoding UIImage as JPEG strips all original EXIF/GPS metadata from stored & uploaded bytes.
        let image = UIImage(cgImage: cgImage)
        guard let jpegData = image.jpegData(compressionQuality: jpegQuality) else { return nil }
        return ProcessedDayPhoto(jpegData: jpegData, coordinate: coordinate, capturedAt: capturedAt)
    }

    static func processAvatar(
        from rawData: Data,
        sidePixels: CGFloat = 320,
        jpegQuality: CGFloat = 0.84
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(rawData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(sidePixels * 2, 640)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return nil }

        let cropSide = min(width, height)
        let cropRect = CGRect(
            x: (width - cropSide) * 0.5,
            y: (height - cropSide) * 0.5,
            width: cropSide,
            height: cropSide
        )
        let cropped = cgImage.cropping(to: cropRect) ?? cgImage
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let targetSize = CGSize(width: sidePixels, height: sidePixels)
        let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: jpegQuality)
    }

    static func processDayVideo(
        from sourceURL: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async -> ProcessedDayVideo? {
        let asset = AVURLAsset(url: sourceURL)
        guard let durationTime = try? await asset.load(.duration) else { return nil }
        let duration = CMTimeGetSeconds(durationTime)
        guard duration.isFinite, duration > 0 else { return nil }

        let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
        var coordinate: GeoCoordinate?
        if let locationItem = AVMetadataItem.metadataItems(
            from: commonMetadata,
            filteredByIdentifier: .commonIdentifierLocation
        ).first,
            let isoString = try? await locationItem.load(.stringValue) {
            coordinate = parseISO6709(isoString)
        }

        let creationItem = try? await asset.load(.creationDate)
        let capturedAt = try? await creationItem?.load(.dateValue)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        guard let thumbnailCG = try? await generator.image(at: .zero).image,
              let thumbnailData = UIImage(cgImage: thumbnailCG).jpegData(compressionQuality: 0.80) else {
            return nil
        }

        let softLimitBytes = 40 * 1024 * 1024
        let hardLimitBytes = 45 * 1024 * 1024

        var exportedData = await exportMP4(asset: asset, preset: AVAssetExportPreset1280x720, onProgress: onProgress)
        if exportedData == nil || (exportedData?.count ?? 0) > softLimitBytes {
            onProgress?(0)
            exportedData = await exportMP4(asset: asset, preset: AVAssetExportPresetMediumQuality, onProgress: onProgress)
        }
        guard let videoData = exportedData, videoData.count <= hardLimitBytes else {
            return nil
        }

        return ProcessedDayVideo(
            videoData: videoData,
            thumbnailJPEGData: thumbnailData,
            durationSeconds: duration,
            coordinate: coordinate,
            capturedAt: capturedAt
        )
    }

    private static func exportMP4(
        asset: AVAsset,
        preset: String,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async -> Data? {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { return nil }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("oh-video-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outURL) }
        session.shouldOptimizeForNetworkUse = true
        let stateStream = session.states(updateInterval: 0.15)
        let progressTask = Task {
            for await state in stateStream {
                if Task.isCancelled { break }
                if case let .exporting(progress) = state {
                    onProgress?(min(1.0, max(0.0, progress.fractionCompleted)))
                }
            }
        }
        defer { progressTask.cancel() }
        do {
            try await session.export(to: outURL, as: .mp4)
            onProgress?(1.0)
            return try Data(contentsOf: outURL)
        } catch {
            return nil
        }
    }

    private static func parseISO6709(_ raw: String) -> GeoCoordinate? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "+" || first == "-" else { return nil }
        var signIndices: [String.Index] = [trimmed.startIndex]
        var index = trimmed.index(after: trimmed.startIndex)
        while index < trimmed.endIndex {
            let ch = trimmed[index]
            if ch == "+" || ch == "-" {
                signIndices.append(index)
            } else if ch == "/" {
                break
            }
            index = trimmed.index(after: index)
        }
        guard signIndices.count >= 2 else { return nil }
        let latStr = String(trimmed[signIndices[0]..<signIndices[1]])
        let lonEnd = signIndices.count >= 3
            ? signIndices[2]
            : (trimmed.firstIndex(of: "/") ?? trimmed.endIndex)
        let lonStr = String(trimmed[signIndices[1]..<lonEnd])
        guard let lat = Double(latStr), let lon = Double(lonStr) else { return nil }
        let coord = GeoCoordinate(latitude: lat, longitude: lon)
        return coord.isValid ? coord : nil
    }

    static func reverseGeocodeDetails(for coordinate: GeoCoordinate) async -> ReverseGeocodeDetails? {
        guard coordinate.isValid else { return nil }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        request.preferredLocale = Locale(identifier: "ja_JP")
        guard let items = try? await request.mapItems, let item = items.first else { return nil }

        let city = item.addressRepresentations?.cityName
        let cityContext = item.addressRepresentations?.cityWithContext
        let fullAddress = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
        let itemName = item.name

        let primaryName = [itemName, city, cityContext].compactMap { value -> String? in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }.first
        guard let primaryName else { return nil }

        let subtitle = [cityContext, fullAddress].compactMap { value -> String? in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  trimmed != primaryName else {
                return nil
            }
            return trimmed
        }.first
        return ReverseGeocodeDetails(name: primaryName, address: subtitle)
    }

    static func reverseGeocodeName(for coordinate: GeoCoordinate) async -> String? {
        await reverseGeocodeDetails(for: coordinate)?.name
    }

    private static func extractCoordinate(from properties: [CFString: Any]?) -> GeoCoordinate? {
        guard let gps = properties?[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let rawLat = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
              let rawLon = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue else {
            return nil
        }
        let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased()
        let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased()
        let lat = latRef == "S" ? -abs(rawLat) : rawLat
        let lon = lonRef == "W" ? -abs(rawLon) : rawLon
        let coord = GeoCoordinate(latitude: lat, longitude: lon)
        return coord.isValid ? coord : nil
    }

    private static func extractCaptureDate(from properties: [CFString: Any]?) -> Date? {
        guard let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String else {
            return nil
        }
        return exifDateFormatter.date(from: raw)
    }
}

@MainActor
final class OneShotLocationFetcher: NSObject, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var continuation: CheckedContinuation<GeoCoordinate?, Never>?
    private var waitingForAuth = false
    private var timeoutTask: Task<Void, Never>?

    func fetchCurrentCoordinate(requestAuthorizationIfNeeded: Bool) async -> GeoCoordinate? {
        #if DEBUG
        if ScreenshotScene.current != nil { return nil }
        #endif
        if continuation != nil { return nil }

        let mgr = CLLocationManager()
        manager = mgr
        mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
        mgr.delegate = self

        switch mgr.authorizationStatus {
        case .denied, .restricted:
            cleanup()
            return nil
        case .notDetermined:
            guard requestAuthorizationIfNeeded else {
                cleanup()
                return nil
            }
            return await waitForFix {
                self.waitingForAuth = true
                mgr.requestWhenInUseAuthorization()
            }
        case .authorizedWhenInUse, .authorizedAlways:
            if let cached = mgr.location,
               Date.now.timeIntervalSince(cached.timestamp) < 120 {
                let coord = GeoCoordinate(
                    latitude: cached.coordinate.latitude,
                    longitude: cached.coordinate.longitude
                )
                if coord.isValid {
                    cleanup()
                    return coord
                }
            }
            return await waitForFix {
                mgr.requestLocation()
            }
        @unknown default:
            cleanup()
            return nil
        }
    }

    private func waitForFix(_ trigger: @MainActor () -> Void) async -> GeoCoordinate? {
        await withCheckedContinuation { cont in
            continuation = cont
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(6))
                self?.finish(with: nil)
            }
            trigger()
        }
    }

    private func finish(with coordinate: GeoCoordinate?) {
        let cont = continuation
        continuation = nil
        cleanup()
        cont?.resume(returning: coordinate)
    }

    private func cleanup() {
        timeoutTask?.cancel()
        timeoutTask = nil
        waitingForAuth = false
        manager?.delegate = nil
        manager = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self, self.waitingForAuth else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.waitingForAuth = false
                self.manager?.requestLocation()
            case .denied, .restricted:
                self.finish(with: nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last?.coordinate
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let latest else {
                self.finish(with: nil)
                return
            }
            let geo = GeoCoordinate(latitude: latest.latitude, longitude: latest.longitude)
            self.finish(with: geo.isValid ? geo : nil)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in
            self?.finish(with: nil)
        }
    }
}
