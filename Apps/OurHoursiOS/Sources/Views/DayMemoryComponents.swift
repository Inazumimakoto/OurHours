import AVKit
import MapKit
import OurHoursCore
import PhotosUI
import SwiftUI
import UIKit

struct MediaTransferProgressBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let progress = model.activeMediaProgress {
            let percent = Int((progress.overallFraction * 100).rounded())
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: symbolName(for: progress.phase))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(FoamTheme.warmAccent)
                    Text(progress.detailText)
                        .font(FoamFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(FoamTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(percent)%")
                        .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(FoamTheme.ink.opacity(0.68))
                }

                ProgressView(value: progress.overallFraction, total: 1.0)
                    .tint(FoamTheme.warmAccent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.84))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white, lineWidth: 1)
                    }
            )
            .shadow(color: FoamTheme.ink.opacity(0.06), radius: 5, y: 2)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func symbolName(for phase: MediaTransferProgress.Phase) -> String {
        switch phase {
        case .importing: "arrow.triangle.2.circlepath"
        case .uploading: "icloud.and.arrow.up"
        case .downloading: "icloud.and.arrow.down"
        }
    }
}

struct DayPlaceTagsSection: View {
    @Environment(AppModel.self) private var model
    let dayKey: String
    let onFocusMapCoordinate: ((GeoCoordinate) -> Void)?

    @State private var showPlacePicker = false
    @State private var editingTag: DayPlaceTag?
    @State private var isAddingPlaceMedia = false

    var body: some View {
        let tags = model.placeTags(forDayKey: dayKey)
        let photos = model.photos(forDayKey: dayKey)

        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags) { tag in
                        let linkedCount = photos.count(where: { $0.placeTagID == tag.id })
                        HStack(spacing: 4) {
                            Button {
                                editingTag = tag
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: tag.coordinate != nil ? "mappin.circle.fill" : "tag.fill")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundStyle(tag.coordinate != nil ? FoamTheme.warmAccent : FoamTheme.ink.opacity(0.62))
                                    Text(tag.name)
                                        .font(FoamFont.bold(12.5, relativeTo: .caption))
                                        .foregroundStyle(FoamTheme.ink)
                                        .lineLimit(1)
                                    if linkedCount > 0 {
                                        HStack(spacing: 2) {
                                            Image(systemName: "photo.fill")
                                                .font(.system(size: 9.5, weight: .bold))
                                            Text("\(linkedCount)")
                                                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                                        }
                                        .foregroundStyle(FoamTheme.ink.opacity(0.64))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(FoamTheme.ink.opacity(0.08), in: Capsule())
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            if let coord = tag.coordinate, let onFocusMapCoordinate {
                                Button {
                                    onFocusMapCoordinate(coord)
                                } label: {
                                    Image(systemName: "map.fill")
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundStyle(FoamTheme.ink.opacity(0.56))
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(tag.name)を地図で見る")
                            }
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, tag.coordinate != nil && onFocusMapCoordinate != nil ? 6 : 10)
                        .padding(.vertical, 6)
                        .background {
                            SoapBubbleSurface(
                                cornerStyle: .capsule,
                                prominence: .standard,
                                isTogether: model.isTogetherNow,
                                seed: 2.4,
                                wobbleScale: 0.25,
                                animated: false
                            )
                        }
                        .contextMenu {
                            Button {
                                editingTag = tag
                            } label: {
                                Label("編集・写真紐づけ", systemImage: "pencil")
                            }
                            if let coord = tag.coordinate, let onFocusMapCoordinate {
                                Button {
                                    onFocusMapCoordinate(coord)
                                } label: {
                                    Label("地図で見る", systemImage: "map.fill")
                                }
                            }
                            Button(role: .destructive) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                model.deleteDayPlaceTag(id: tag.id)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        showPlacePicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("場所を追加")
                                .font(FoamFont.bold(12.5, relativeTo: .caption))
                        }
                        .foregroundStyle(FoamTheme.ink.opacity(0.74))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.54))
                                .overlay {
                                    Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                                }
                        )
                    }
                    .buttonStyle(.plain)

                    if isAddingPlaceMedia {
                        ProgressView()
                            .controlSize(.small)
                            .tint(FoamTheme.ink)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .sheet(isPresented: $showPlacePicker) {
            PlaceTagPickerSheet(
                title: "場所を追加",
                photosOnDay: photos,
                requiresCoordinate: false,
                allowsMediaAttachment: true
            ) { result in
                guard let tag = model.addDayPlaceTag(
                    dayKey: dayKey,
                    name: result.name,
                    address: result.address,
                    coordinate: result.coordinate
                ) else { return }

                for existingID in result.linkedExistingMediaIDs {
                    model.linkMedia(id: existingID, to: tag)
                }

                guard !result.newlyPickedMedia.isEmpty else { return }
                let pickedItems = result.newlyPickedMedia
                Task {
                    isAddingPlaceMedia = true
                    defer { isAddingPlaceMedia = false }
                    await importPickedMediaItems(
                        pickedItems,
                        dayKey: dayKey,
                        model: model,
                        overrideCoordinate: tag.coordinate,
                        overrideLocationName: tag.name,
                        placeTagID: tag.id
                    )
                }
            }
        }
        .sheet(item: $editingTag) { tag in
            let initialLinked = Set(photos.filter { $0.placeTagID == tag.id }.map(\.id))
            PlaceTagPickerSheet(
                title: "場所を編集",
                photosOnDay: photos,
                requiresCoordinate: false,
                allowsMediaAttachment: true,
                initialCoordinate: tag.coordinate,
                initialName: tag.name,
                initialAddress: tag.address,
                initialLinkedMediaIDs: initialLinked,
                submitButtonTitle: "保存",
                onOpenOnMap: onFocusMapCoordinate,
                onDelete: {
                    model.deleteDayPlaceTag(id: tag.id)
                }
            ) { result in
                guard let updatedTag = model.updateDayPlaceTag(
                    tag,
                    name: result.name,
                    address: result.address,
                    coordinate: result.coordinate
                ) else { return }

                model.setLinkedMedia(result.linkedExistingMediaIDs, for: updatedTag)

                guard !result.newlyPickedMedia.isEmpty else { return }
                let pickedItems = result.newlyPickedMedia
                Task {
                    isAddingPlaceMedia = true
                    defer { isAddingPlaceMedia = false }
                    await importPickedMediaItems(
                        pickedItems,
                        dayKey: dayKey,
                        model: model,
                        overrideCoordinate: updatedTag.coordinate,
                        overrideLocationName: updatedTag.name,
                        placeTagID: updatedTag.id
                    )
                }
            }
        }
    }
}

struct DayPhotosSection: View {
    @Environment(AppModel.self) private var model
    let dayKey: String
    let onFocusMapCoordinate: ((GeoCoordinate) -> Void)?

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isProcessingPhotos = false
    @State private var viewerSelection: PhotoViewerSelection?
    @State private var editingLocationPhoto: DayPhotoAttachment?

    private struct PhotoViewerSelection: Identifiable {
        let id: UUID
    }

    var body: some View {
        let photos = model.photos(forDayKey: dayKey)
        let processing = isProcessingPhotos

        VStack(alignment: .leading, spacing: 8) {
            MediaTransferProgressBanner()

            if photos.isEmpty {
                HStack(spacing: 8) {
                    PhotosPicker(
                        selection: $pickerItems,
                        matching: .any(of: [.images, .videos])
                    ) {
                        HStack(spacing: 5) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 12, weight: .bold))
                            Text("写真・動画を追加")
                                .font(FoamFont.bold(12.5, relativeTo: .caption))
                        }
                        .foregroundStyle(FoamTheme.ink.opacity(0.76))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.54))
                                .overlay {
                                    Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                                }
                        )
                    }
                    .disabled(processing)

                    if processing && model.activeMediaProgress == nil {
                        ProgressView()
                            .controlSize(.small)
                            .tint(FoamTheme.ink)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(photos) { photo in
                            Button {
                                viewerSelection = PhotoViewerSelection(id: photo.id)
                            } label: {
                                ZStack {
                                    Group {
                                        if let image = model.dayMediaThumbnail(for: photo) {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                        } else {
                                            ZStack {
                                                Color.white.opacity(0.65)
                                                ProgressView()
                                                    .controlSize(.small)
                                                    .tint(FoamTheme.ink.opacity(0.65))
                                            }
                                        }
                                    }
                                    .frame(width: 86, height: 86)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.92), lineWidth: 2)
                                    }
                                    .shadow(color: FoamTheme.ink.opacity(0.10), radius: 5, y: 2)

                                    if model.isMediaUploading(id: photo.id) {
                                        VStack {
                                            HStack {
                                                Spacer()
                                                ProgressView()
                                                    .controlSize(.mini)
                                                    .tint(.white)
                                                    .padding(4)
                                                    .background(Color.black.opacity(0.56), in: Circle())
                                            }
                                            Spacer()
                                        }
                                        .padding(5)
                                    }

                                    if photo.mediaKind == .video {
                                        VStack {
                                            Spacer()
                                            HStack(spacing: 3) {
                                                Image(systemName: "play.fill")
                                                    .font(.system(size: 8.5, weight: .bold))
                                                if let sec = photo.durationSeconds {
                                                    Text(formattedVideoDuration(sec))
                                                        .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                                                }
                                            }
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2.5)
                                            .background(Color.black.opacity(0.62), in: Capsule())
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(5)
                                    }

                                    if photo.coordinate != nil {
                                        VStack {
                                            Spacer()
                                            HStack {
                                                Spacer()
                                                Image(systemName: "mappin.circle.fill")
                                                    .font(.system(size: 15, weight: .bold))
                                                    .foregroundStyle(FoamTheme.warmAccent, Color.white)
                                                    .shadow(color: FoamTheme.ink.opacity(0.18), radius: 2, y: 1)
                                            }
                                        }
                                        .padding(5)
                                    }
                                }
                                .frame(width: 86, height: 86)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(photo.locationName ?? (photo.mediaKind == .video ? "この日の動画" : "この日の写真"))
                            .contextMenu {
                                Button {
                                    editingLocationPhoto = photo
                                } label: {
                                    Label(photo.coordinate == nil ? "場所を検索してつける" : "店舗・位置を調整", systemImage: "mappin.and.ellipse")
                                }
                                if let coord = photo.coordinate, let onFocusMapCoordinate {
                                    Button {
                                        onFocusMapCoordinate(coord)
                                    } label: {
                                        Label("地図で見る", systemImage: "map.fill")
                                    }
                                }
                                Button(role: .destructive) {
                                    model.deleteDayPhoto(id: photo.id)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }

                        PhotosPicker(
                            selection: $pickerItems,
                            matching: .any(of: [.images, .videos])
                        ) {
                            VStack(spacing: 4) {
                                if processing {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(FoamTheme.ink)
                                } else {
                                    Image(systemName: "plus")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(FoamTheme.ink.opacity(0.68))
                                    Text("写真・動画")
                                        .font(FoamFont.bold(10.5, relativeTo: .caption2))
                                        .foregroundStyle(FoamTheme.ink.opacity(0.62))
                                }
                            }
                            .frame(width: 86, height: 86)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.50))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.86), lineWidth: 1.5)
                                    }
                            )
                        }
                        .disabled(processing)
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            let picked = items
            pickerItems = []
            Task {
                isProcessingPhotos = true
                defer { isProcessingPhotos = false }
                await importPickedMediaItems(picked, dayKey: dayKey, model: model)
            }
        }
        .fullScreenCover(item: $viewerSelection) { selection in
            DayPhotoViewerSheet(
                dayKey: dayKey,
                initialPhotoID: selection.id,
                onFocusMapCoordinate: onFocusMapCoordinate
            )
        }
        .sheet(item: $editingLocationPhoto) { photo in
            PlaceTagPickerSheet(
                title: photo.coordinate == nil ? "場所を検索してつける" : "店舗・位置を調整",
                photosOnDay: model.photos(forDayKey: photo.dayKey),
                existingPlaceTagsOnDay: model.placeTags(forDayKey: photo.dayKey),
                requiresCoordinate: true,
                allowsMediaAttachment: false,
                initialCoordinate: photo.coordinate,
                initialName: photo.locationName,
                submitButtonTitle: "保存"
            ) { result in
                model.updateDayPhotoLocation(
                    id: photo.id,
                    coordinate: result.coordinate,
                    locationName: result.name,
                    placeTagID: result.selectedExistingPlaceTagID
                )
            }
        }
    }

    private func formattedVideoDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

@MainActor
private final class ImportBatchGuard {
    var isFinished = false
}

@MainActor
func importPickedMediaItems(
    _ items: [PhotosPickerItem],
    dayKey: String?,
    model: AppModel,
    overrideCoordinate: GeoCoordinate? = nil,
    overrideLocationName: String? = nil,
    placeTagID: UUID? = nil,
    planID: UUID? = nil,
    fallbackDayKey: String? = nil
) async {
    guard !items.isEmpty else { return }
    let total = items.count
    let batchGuard = ImportBatchGuard()
    defer {
        batchGuard.isFinished = true
        model.setMediaImportProgress(nil)
    }

    for (index, item) in items.enumerated() {
        let isMovie = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        if isMovie {
            model.setMediaImportProgress(MediaTransferProgress(
                phase: .importing,
                completedCount: index,
                totalCount: total,
                currentItemFraction: 0.05,
                detailText: "動画を読み込み中 (\(index + 1)/\(total))"
            ))
            if let pickedVideo = try? await item.loadTransferable(type: PickedVideoFile.self) {
                defer { try? FileManager.default.removeItem(at: pickedVideo.url) }
                let progressHandler: @Sendable (Double) -> Void = { fraction in
                    Task { @MainActor in
                        guard !batchGuard.isFinished else { return }
                        model.setMediaImportProgress(MediaTransferProgress(
                            phase: .importing,
                            completedCount: index,
                            totalCount: total,
                            currentItemFraction: fraction,
                            detailText: "動画を変換中 (\(index + 1)/\(total))"
                        ))
                    }
                }
                if let dayKey {
                    _ = await model.addDayVideo(
                        dayKey: dayKey,
                        fileURL: pickedVideo.url,
                        overrideCoordinate: overrideCoordinate,
                        overrideLocationName: overrideLocationName,
                        placeTagID: placeTagID,
                        planID: planID,
                        onExportProgress: progressHandler
                    )
                } else {
                    _ = await model.addAlbumVideo(
                        fileURL: pickedVideo.url,
                        planID: planID,
                        fallbackDayKey: fallbackDayKey,
                        onExportProgress: progressHandler
                    )
                }
            }
        } else {
            model.setMediaImportProgress(MediaTransferProgress(
                phase: .importing,
                completedCount: index,
                totalCount: total,
                currentItemFraction: 0.3,
                detailText: "写真を読み込み中 (\(index + 1)/\(total))"
            ))
            if let data = try? await item.loadTransferable(type: Data.self) {
                if let dayKey {
                    _ = await model.addDayPhoto(
                        dayKey: dayKey,
                        rawImageData: data,
                        overrideCoordinate: overrideCoordinate,
                        overrideLocationName: overrideLocationName,
                        placeTagID: placeTagID,
                        planID: planID
                    )
                } else {
                    _ = await model.addAlbumPhoto(
                        rawImageData: data,
                        planID: planID,
                        fallbackDayKey: fallbackDayKey
                    )
                }
            }
        }
    }
}

struct DayPhotoViewerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let dayKey: String?
    let initialPhotoID: UUID
    var scopedPhotoIDs: [UUID]? = nil
    var albumPhotoIDs: [UUID]? = nil
    var headerTitle: String? = nil
    var onFocusMapCoordinate: ((GeoCoordinate) -> Void)? = nil
    var onOpenDayDetail: ((String) -> Void)? = nil

    @State private var selectedPhotoID: UUID
    @State private var showsChrome = true
    @State private var showLocationPicker = false
    @State private var confirmDelete = false

    init(
        dayKey: String?,
        initialPhotoID: UUID,
        scopedPhotoIDs: [UUID]? = nil,
        albumPhotoIDs: [UUID]? = nil,
        headerTitle: String? = nil,
        onFocusMapCoordinate: ((GeoCoordinate) -> Void)? = nil,
        onOpenDayDetail: ((String) -> Void)? = nil
    ) {
        self.dayKey = dayKey
        self.initialPhotoID = initialPhotoID
        self.scopedPhotoIDs = scopedPhotoIDs
        self.albumPhotoIDs = albumPhotoIDs
        self.headerTitle = headerTitle
        self.onFocusMapCoordinate = onFocusMapCoordinate
        self.onOpenDayDetail = onOpenDayDetail
        _selectedPhotoID = State(initialValue: initialPhotoID)
    }

    private var visiblePhotos: [DayPhotoAttachment] {
        if let albumPhotoIDs {
            let byID = Dictionary(uniqueKeysWithValues: model.allMediaAttachments.map { ($0.id, $0) })
            return albumPhotoIDs.compactMap { byID[$0] }
        }
        guard let dayKey else { return model.allMediaAttachments }
        let allOnDay = model.photos(forDayKey: dayKey)
        guard let scopedPhotoIDs else { return allOnDay }
        let idSet = Set(scopedPhotoIDs)
        let filtered = allOnDay.filter { idSet.contains($0.id) }
        return filtered.isEmpty ? allOnDay : filtered
    }

    var body: some View {
        let photos = visiblePhotos
        let currentPhoto = photos.first(where: { $0.id == selectedPhotoID }) ?? photos.first

        ZStack {
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleChrome()
                }

            if photos.isEmpty {
                Color.clear.onAppear { dismiss() }
            } else {
                TabView(selection: $selectedPhotoID) {
                    ForEach(photos) { photo in
                        Group {
                            if photo.mediaKind == .video {
                                DayVideoPlayerView(item: photo)
                            } else if let image = model.dayPhotoImage(id: photo.id) {
                                ZoomablePhotoView(image: image) {
                                    toggleChrome()
                                }
                            } else {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        toggleChrome()
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(photo.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: (showsChrome && photos.count > 1) ? .automatic : .never))

                if showsChrome {
                    chromeOverlay(photos: photos, currentPhoto: currentPhoto)
                        .transition(.opacity)
                }
            }
        }
        .statusBarHidden(!showsChrome)
        .onChange(of: currentPhoto?.id) { _, _ in
            if currentPhoto?.mediaKind == .video && !showsChrome {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsChrome = true
                }
            }
        }
        .confirmationDialog(
            currentPhoto?.mediaKind == .video ? "この動画を削除しますか？" : "この写真を削除しますか？",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            if let currentPhoto {
                Button("削除する", role: .destructive) {
                    let remaining = visiblePhotos.filter { $0.id != currentPhoto.id }
                    model.deleteDayPhoto(id: currentPhoto.id)
                    if let next = remaining.first {
                        selectedPhotoID = next.id
                    } else {
                        dismiss()
                    }
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(isPresented: $showLocationPicker) {
            if let currentPhoto {
                PlaceTagPickerSheet(
                    title: currentPhoto.coordinate == nil ? "場所を検索してつける" : "店舗・位置を調整",
                    photosOnDay: model.photos(forDayKey: currentPhoto.dayKey),
                    existingPlaceTagsOnDay: model.placeTags(forDayKey: currentPhoto.dayKey),
                    requiresCoordinate: true,
                    allowsMediaAttachment: false,
                    initialCoordinate: currentPhoto.coordinate,
                    initialName: currentPhoto.locationName,
                    submitButtonTitle: "保存"
                ) { result in
                    model.updateDayPhotoLocation(
                        id: currentPhoto.id,
                        coordinate: result.coordinate,
                        locationName: result.name,
                        placeTagID: result.selectedExistingPlaceTagID
                    )
                }
            }
        }
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showsChrome.toggle()
        }
    }

    @ViewBuilder
    private func chromeOverlay(photos: [DayPhotoAttachment], currentPhoto: DayPhotoAttachment?) -> some View {
        VStack {
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.18), in: Circle())
                }

                Spacer()

                VStack(spacing: 1) {
                    if let headerTitle, !headerTitle.isEmpty {
                        Text(headerTitle)
                            .font(FoamFont.bold(14, relativeTo: .subheadline))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    } else if albumPhotoIDs != nil || dayKey == nil, let currentPhoto {
                        Text(MemoryMapPinBuilder.formattedDayTitle(currentPhoto.dayKey))
                            .font(FoamFont.bold(14, relativeTo: .subheadline))
                            .foregroundStyle(.white)
                    }
                    if let currentPhoto, let index = photos.firstIndex(where: { $0.id == currentPhoto.id }) {
                        Text("\(index + 1) / \(photos.count)")
                            .font(FoamFont.bold(headerTitle == nil && albumPhotoIDs == nil ? 14 : 12, relativeTo: .caption))
                            .foregroundStyle(.white.opacity(0.86))
                    }
                }

                Spacer()

                if let onOpenDayDetail, let currentPhoto {
                    Button {
                        dismiss()
                        onOpenDayDetail(currentPhoto.dayKey)
                    } label: {
                        Text("この日の詳細")
                            .font(FoamFont.bold(12, relativeTo: .caption))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.92), in: Capsule())
                    }
                }

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.18), in: Circle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.62), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Spacer()

            if let currentPhoto {
                VStack(alignment: .leading, spacing: 10) {
                    if let capturedAt = currentPhoto.capturedAt {
                        Text(capturedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(FoamFont.medium(12.5, relativeTo: .caption))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    if let place = currentPhoto.locationName, !place.isEmpty {
                        Label(place, systemImage: "mappin.circle.fill")
                            .font(FoamFont.bold(14.5, relativeTo: .subheadline))
                            .foregroundStyle(.white)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if currentPhoto.coordinate == nil {
                                Button {
                                    showLocationPicker = true
                                } label: {
                                    Label("場所を検索してつける", systemImage: "magnifyingglass")
                                        .font(FoamFont.bold(13, relativeTo: .caption))
                                        .foregroundStyle(FoamTheme.ink)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color.white, in: Capsule())
                                }
                            } else {
                                if let coord = currentPhoto.coordinate, let onFocusMapCoordinate {
                                    Button {
                                        dismiss()
                                        onFocusMapCoordinate(coord)
                                    } label: {
                                        Label("地図で見る", systemImage: "map.fill")
                                            .font(FoamFont.bold(13, relativeTo: .caption))
                                            .foregroundStyle(FoamTheme.ink)
                                            .padding(.horizontal, 13)
                                            .padding(.vertical, 8)
                                            .background(Color.white, in: Capsule())
                                    }
                                }

                                Button {
                                    showLocationPicker = true
                                } label: {
                                    Label("店舗・位置を調整", systemImage: "mappin.and.ellipse")
                                        .font(FoamFont.bold(13, relativeTo: .caption))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.24), in: Capsule())
                                }

                                Button {
                                    model.updateDayPhotoLocation(
                                        id: currentPhoto.id,
                                        coordinate: nil,
                                        locationName: nil,
                                        placeTagID: nil
                                    )
                                } label: {
                                    Text("外す")
                                        .font(FoamFont.bold(12.5, relativeTo: .caption))
                                        .foregroundStyle(.white.opacity(0.84))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }
}

private struct DayVideoPlayerView: View {
    @Environment(AppModel.self) private var model
    let item: DayPhotoAttachment

    @State private var player: AVPlayer?

    var body: some View {
        let videoURL = model.dayVideoURL(id: item.id)
        ZStack {
            if let player, videoURL != nil {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if let thumb = model.dayMediaThumbnail(for: item) {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .opacity(0.6)
                }
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text("動画を読み込み中…")
                        .font(FoamFont.medium(13, relativeTo: .caption))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .onChange(of: videoURL, initial: true) { _, newURL in
            if let newURL {
                if (player?.currentItem?.asset as? AVURLAsset)?.url != newURL {
                    player?.pause()
                    player = AVPlayer(url: newURL)
                }
            } else {
                player?.pause()
                player = nil
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

private struct ZoomablePhotoView: UIViewRepresentable {
    let image: UIImage
    let onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = ZoomContainerScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        scrollView.imageView = imageView
        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        context.coordinator.lastImage = image
        context.coordinator.onSingleTap = onSingleTap

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        if context.coordinator.lastImage !== image {
            context.coordinator.lastImage = image
            context.coordinator.imageView?.image = image
            scrollView.setZoomScale(1.0, animated: false)
            scrollView.setNeedsLayout()
        }
    }

    final class ZoomContainerScrollView: UIScrollView {
        weak var imageView: UIImageView?

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let imageView else { return }
            if zoomScale <= 1.001 {
                imageView.frame = bounds
                contentSize = bounds.size
            } else {
                let offsetX = max((bounds.width - contentSize.width) * 0.5, 0)
                let offsetY = max((bounds.height - contentSize.height) * 0.5, 0)
                imageView.center = CGPoint(
                    x: contentSize.width * 0.5 + offsetX,
                    y: contentSize.height * 0.5 + offsetY
                )
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        var lastImage: UIImage?
        var onSingleTap: (() -> Void)?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.setNeedsLayout()
        }

        @objc func handleSingleTap() {
            onSingleTap?()
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView, let imageView else { return }
            if scrollView.zoomScale > 1.05 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let zoomScale: CGFloat = 2.5
                let width = scrollView.bounds.width / zoomScale
                let height = scrollView.bounds.height / zoomScale
                let rect = CGRect(
                    x: point.x - width * 0.5,
                    y: point.y - height * 0.5,
                    width: width,
                    height: height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}

struct PlaceTagSelectionResult {
    let name: String
    let address: String?
    let coordinate: GeoCoordinate?
    let selectedExistingPlaceTagID: UUID?
    let linkedExistingMediaIDs: Set<UUID>
    let newlyPickedMedia: [PhotosPickerItem]
}

private struct ResolvedPlaceCandidate: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let address: String?
    let coordinate: GeoCoordinate
}

struct PlaceTagPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let title: String
    let photosOnDay: [DayPhotoAttachment]
    var existingPlaceTagsOnDay: [DayPlaceTag] = []
    var requiresCoordinate = false
    var allowsMediaAttachment = true
    var initialCoordinate: GeoCoordinate? = nil
    var initialName: String? = nil
    var initialAddress: String? = nil
    var initialLinkedMediaIDs: Set<UUID> = []
    var submitButtonTitle: String? = nil
    var onOpenOnMap: ((GeoCoordinate) -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    let onSelect: (PlaceTagSelectionResult) -> Void

    @State private var searchHelper = PlaceSearchHelper()
    @State private var locationFetcher = OneShotLocationFetcher()
    @State private var placeName: String
    @State private var selectedAddress: String?
    @State private var selectedCoordinate: GeoCoordinate?
    @State private var selectedExistingPlaceTagID: UUID?
    @State private var cameraPosition: MapCameraPosition
    @State private var currentMapRegion: MKCoordinateRegion?
    @State private var selectedMapFeature: MapFeature?
    @State private var directSearchResults: [ResolvedPlaceCandidate] = []
    @State private var didManuallyEditName = false
    @State private var didLockChosenStoreName = false
    @State private var didInteractWithMap = false
    @State private var isResolving = false
    @State private var linkedExistingMediaIDs: Set<UUID>
    @State private var stagedPickerItems: [PhotosPickerItem] = []
    @State private var lastFeatureSelectTime = Date.distantPast
    @State private var pendingRawTapTask: Task<Void, Never>?
    @State private var confirmDelete = false
    @FocusState private var isSearchFocused: Bool

    init(
        title: String,
        photosOnDay: [DayPhotoAttachment],
        existingPlaceTagsOnDay: [DayPlaceTag] = [],
        requiresCoordinate: Bool = false,
        allowsMediaAttachment: Bool = true,
        initialCoordinate: GeoCoordinate? = nil,
        initialName: String? = nil,
        initialAddress: String? = nil,
        initialLinkedMediaIDs: Set<UUID> = [],
        submitButtonTitle: String? = nil,
        onOpenOnMap: ((GeoCoordinate) -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onSelect: @escaping (PlaceTagSelectionResult) -> Void
    ) {
        self.title = title
        self.photosOnDay = photosOnDay
        self.existingPlaceTagsOnDay = existingPlaceTagsOnDay
        self.requiresCoordinate = requiresCoordinate
        self.allowsMediaAttachment = allowsMediaAttachment
        self.initialCoordinate = initialCoordinate
        self.initialName = initialName
        self.initialAddress = initialAddress
        self.initialLinkedMediaIDs = initialLinkedMediaIDs
        self.submitButtonTitle = submitButtonTitle
        self.onOpenOnMap = onOpenOnMap
        self.onDelete = onDelete
        self.onSelect = onSelect

        let trimmedInitName = initialName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        _selectedCoordinate = State(initialValue: initialCoordinate)
        _placeName = State(initialValue: initialName ?? "")
        _selectedAddress = State(initialValue: initialAddress)
        _linkedExistingMediaIDs = State(initialValue: initialLinkedMediaIDs)
        _didLockChosenStoreName = State(initialValue: !trimmedInitName.isEmpty)

        if let coord = initialCoordinate, coord.isValid {
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
            )))
        } else if let photoCoord = photosOnDay.compactMap(\.coordinate).first(where: \.isValid) {
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: photoCoord.latitude, longitude: photoCoord.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )))
        } else {
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
                span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
            )))
        }
    }

    private var trimmedPlaceName: String {
        placeName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        let hasName = !trimmedPlaceName.isEmpty || !searchHelper.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if requiresCoordinate {
            return hasName && selectedCoordinate?.isValid == true
        }
        return hasName
    }

    var body: some View {
        NavigationStack {
            List {
                Section("スポット検索・表示名") {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextField("店名・駅・スポット名を検索", text: $searchHelper.query)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .focused($isSearchFocused)
                                .onChange(of: searchHelper.query) { _, _ in
                                    if !directSearchResults.isEmpty {
                                        directSearchResults = []
                                    }
                                }
                                .onSubmit {
                                    performExplicitSearch()
                                }
                            if !searchHelper.query.isEmpty {
                                Button {
                                    searchHelper.query = ""
                                    directSearchResults = []
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("検索文字をクリア")
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                        Button {
                            performExplicitSearch()
                        } label: {
                            Text("検索")
                                .font(FoamFont.bold(13.5, relativeTo: .subheadline))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(FoamTheme.ink, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(searchHelper.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResolving)
                    }

                    if !directSearchResults.isEmpty {
                        ForEach(directSearchResults) { candidate in
                            Button {
                                applyResolvedStore(
                                    name: candidate.name,
                                    address: candidate.address,
                                    coordinate: candidate.coordinate,
                                    spanDelta: 0.008
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.name)
                                        .font(FoamFont.bold(14.5, relativeTo: .subheadline))
                                        .foregroundStyle(FoamTheme.ink)
                                    if let address = candidate.address, !address.isEmpty {
                                        Text(address)
                                            .font(FoamFont.regular(12, relativeTo: .caption))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else if !searchHelper.suggestions.isEmpty {
                        ForEach(searchHelper.suggestions.prefix(5)) { suggestion in
                            Button {
                                resolveAndSelect(suggestion)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .font(FoamFont.bold(14.5, relativeTo: .subheadline))
                                        .foregroundStyle(FoamTheme.ink)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(FoamFont.regular(12, relativeTo: .caption))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(isResolving)
                        }
                    }

                    HStack(spacing: 6) {
                        TextField("表示する店名・場所名", text: Binding(
                            get: { placeName },
                            set: { newValue in
                                placeName = newValue
                                let nonEmpty = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                didManuallyEditName = nonEmpty
                                if !nonEmpty {
                                    didLockChosenStoreName = false
                                }
                            }
                        ))
                        if !placeName.isEmpty {
                            Button {
                                placeName = ""
                                didManuallyEditName = false
                                didLockChosenStoreName = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("表示名をクリア")
                        }
                    }
                }

                if !allowsMediaAttachment && !existingPlaceTagsOnDay.isEmpty {
                    Section("この日に登録した場所から選ぶ") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(existingPlaceTagsOnDay) { tag in
                                    Button {
                                        selectedExistingPlaceTagID = tag.id
                                        placeName = tag.name
                                        selectedAddress = tag.address
                                        didLockChosenStoreName = true
                                        didManuallyEditName = false
                                        didInteractWithMap = true
                                        if let coord = tag.coordinate, coord.isValid {
                                            selectedCoordinate = coord
                                            moveCamera(to: coord, spanDelta: 0.01)
                                        }
                                    } label: {
                                        Label(tag.name, systemImage: tag.coordinate != nil ? "mappin.circle.fill" : "tag.fill")
                                            .font(FoamFont.bold(12.5, relativeTo: .caption))
                                            .foregroundStyle(selectedExistingPlaceTagID == tag.id ? .white : FoamTheme.ink)
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 6)
                                            .background(
                                                selectedExistingPlaceTagID == tag.id
                                                    ? FoamTheme.ink
                                                    : Color.secondary.opacity(0.12),
                                                in: Capsule()
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack(alignment: .bottomTrailing) {
                            MapReader { proxy in
                                Map(position: $cameraPosition, selection: $selectedMapFeature) {
                                    UserAnnotation()

                                    if let coord = selectedCoordinate, coord.isValid {
                                        Marker(
                                            trimmedPlaceName.isEmpty ? "選択した場所" : trimmedPlaceName,
                                            coordinate: CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
                                        )
                                        .tint(FoamTheme.warmAccent)
                                    }
                                }
                                .frame(height: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .onMapCameraChange(frequency: .onEnd) { context in
                                    currentMapRegion = context.region
                                    searchHelper.updateRegion(context.region)
                                }
                                .onChange(of: selectedMapFeature) { _, feature in
                                    guard let feature else { return }
                                    lastFeatureSelectTime = .now
                                    pendingRawTapTask?.cancel()
                                    pendingRawTapTask = nil
                                    didInteractWithMap = true
                                    selectedExistingPlaceTagID = nil
                                    let coord = GeoCoordinate(
                                        latitude: feature.coordinate.latitude,
                                        longitude: feature.coordinate.longitude
                                    )
                                    let featureTitle = feature.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                    if coord.isValid {
                                        selectedCoordinate = coord
                                        moveCamera(to: coord, spanDelta: 0.008)
                                    }
                                    if !featureTitle.isEmpty {
                                        placeName = featureTitle
                                        didLockChosenStoreName = true
                                        didManuallyEditName = false
                                    }
                                    resolveMapFeature(feature)
                                }
                                .simultaneousGesture(
                                    SpatialTapGesture().onEnded { value in
                                        let tapPoint = value.location
                                        pendingRawTapTask?.cancel()
                                        pendingRawTapTask = Task {
                                            try? await Task.sleep(for: .milliseconds(120))
                                            guard !Task.isCancelled else { return }
                                            guard Date.now.timeIntervalSince(lastFeatureSelectTime) > 0.25 else { return }
                                            if let clCoord = proxy.convert(tapPoint, from: .local) {
                                                let geo = GeoCoordinate(latitude: clCoord.latitude, longitude: clCoord.longitude)
                                                if geo.isValid {
                                                    dropPin(at: geo)
                                                }
                                            }
                                        }
                                    }
                                )
                            }

                            Button {
                                recenterToCurrentLocation()
                            } label: {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 13.5, weight: .bold))
                                    .foregroundStyle(FoamTheme.ink)
                                    .frame(width: 36, height: 36)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .overlay {
                                        Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                                    }
                                    .shadow(color: Color.black.opacity(0.16), radius: 4, y: 2)
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .accessibilityLabel("現在地を表示")
                        }

                        HStack {
                            Text("店名アイコンまたは地図をタップして位置を合わせられます")
                                .font(FoamFont.regular(11.5, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if selectedCoordinate != nil && !requiresCoordinate {
                                Button("ピンを外す") {
                                    selectedCoordinate = nil
                                    selectedAddress = nil
                                    selectedMapFeature = nil
                                }
                                .font(FoamFont.bold(12, relativeTo: .caption))
                                .foregroundStyle(.red)
                            }
                        }

                        let geoPhotos = photosOnDay.filter { $0.coordinate?.isValid == true }
                        if !geoPhotos.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(geoPhotos) { photo in
                                        if let coord = photo.coordinate {
                                            Button {
                                                didInteractWithMap = true
                                                selectedExistingPlaceTagID = nil
                                                moveCamera(to: coord, spanDelta: 0.012)
                                                selectedCoordinate = coord
                                                if let locName = photo.locationName,
                                                   !didManuallyEditName,
                                                   !didLockChosenStoreName || trimmedPlaceName.isEmpty {
                                                    placeName = locName
                                                    didLockChosenStoreName = true
                                                }
                                            } label: {
                                                Label(
                                                    photo.locationName ?? "写真の位置を使う",
                                                    systemImage: "photo.circle.fill"
                                                )
                                                .font(FoamFont.bold(12, relativeTo: .caption))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color.secondary.opacity(0.12), in: Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                } header: {
                    Text("地図でピンを合わせる\(requiresCoordinate ? "" : "（任意）")")
                }

                if allowsMediaAttachment {
                    Section("この場所に写真・動画を紐づける（任意）") {
                        if !photosOnDay.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(photosOnDay) { item in
                                        let isLinked = linkedExistingMediaIDs.contains(item.id)
                                        Button {
                                            if isLinked {
                                                linkedExistingMediaIDs.remove(item.id)
                                            } else {
                                                linkedExistingMediaIDs.insert(item.id)
                                            }
                                        } label: {
                                            ZStack(alignment: .topTrailing) {
                                                Group {
                                                    if let image = model.dayMediaThumbnail(for: item) {
                                                        Image(uiImage: image)
                                                            .resizable()
                                                            .scaledToFill()
                                                    } else {
                                                        Color.secondary.opacity(0.15)
                                                    }
                                                }
                                                .frame(width: 64, height: 64)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .strokeBorder(isLinked ? FoamTheme.warmAccent : Color.clear, lineWidth: 2.5)
                                                }

                                                Image(systemName: isLinked ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundStyle(isLinked ? FoamTheme.warmAccent : .white, Color.white)
                                                    .shadow(radius: 2)
                                                    .padding(4)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        let stagedCount = stagedPickerItems.count
                        PhotosPicker(
                            selection: $stagedPickerItems,
                            matching: .any(of: [.images, .videos])
                        ) {
                            HStack {
                                Label("新しく写真・動画を選んで追加", systemImage: "photo.on.rectangle.angled")
                                Spacer()
                                if stagedCount > 0 {
                                    Text("\(stagedCount)件")
                                        .font(FoamFont.bold(13, relativeTo: .caption))
                                        .foregroundStyle(FoamTheme.warmAccent)
                                }
                            }
                        }
                    }
                }

                if (selectedCoordinate?.isValid == true && onOpenOnMap != nil) || onDelete != nil {
                    Section {
                        if let coord = selectedCoordinate, coord.isValid, let onOpenOnMap {
                            Button {
                                dismiss()
                                onOpenOnMap(coord)
                            } label: {
                                Label("地図で見る", systemImage: "map.fill")
                            }
                        }
                        if onDelete != nil {
                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Label("この場所を削除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .font(FoamFont.medium(15))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(submitButtonTitle ?? (requiresCoordinate ? "設定" : "追加")) {
                        submit()
                    }
                    .font(FoamFont.bold(15, relativeTo: .body))
                    .disabled(!canSubmit || isResolving)
                }
            }
            .confirmationDialog("この場所タグを削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除する", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("キャンセル", role: .cancel) {}
            }
            .task {
                if initialCoordinate == nil {
                    if let currentCoord = await locationFetcher.fetchCurrentCoordinate(requestAuthorizationIfNeeded: true),
                       !didInteractWithMap,
                       selectedCoordinate == nil,
                       directSearchResults.isEmpty {
                        moveCamera(to: currentCoord, spanDelta: 0.025)
                    }
                }
            }
            .onDisappear {
                pendingRawTapTask?.cancel()
            }
        }
        .preferredColorScheme(.light)
    }

    private func submit() {
        let finalName = trimmedPlaceName.isEmpty
            ? searchHelper.query.trimmingCharacters(in: .whitespacesAndNewlines)
            : trimmedPlaceName
        guard !finalName.isEmpty else { return }
        onSelect(PlaceTagSelectionResult(
            name: finalName,
            address: selectedAddress,
            coordinate: selectedCoordinate,
            selectedExistingPlaceTagID: selectedExistingPlaceTagID,
            linkedExistingMediaIDs: linkedExistingMediaIDs,
            newlyPickedMedia: stagedPickerItems
        ))
        dismiss()
    }

    private func recenterToCurrentLocation() {
        didInteractWithMap = true
        Task {
            if let coord = await locationFetcher.fetchCurrentCoordinate(requestAuthorizationIfNeeded: true) {
                moveCamera(to: coord, spanDelta: 0.018)
            }
        }
    }

    private func applyResolvedStore(
        name: String,
        address: String?,
        coordinate: GeoCoordinate?,
        spanDelta: Double
    ) {
        isSearchFocused = false
        didInteractWithMap = true
        selectedExistingPlaceTagID = nil
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanName.isEmpty {
            placeName = cleanName
            didLockChosenStoreName = true
            didManuallyEditName = false
        }
        selectedAddress = address
        searchHelper.query = ""
        directSearchResults = []
        if let coordinate, coordinate.isValid {
            selectedCoordinate = coordinate
            moveCamera(to: coordinate, spanDelta: spanDelta)
        }
    }

    private func dropPin(at coordinate: GeoCoordinate) {
        didInteractWithMap = true
        selectedExistingPlaceTagID = nil
        selectedCoordinate = coordinate
        moveCamera(to: coordinate, spanDelta: 0.015)
        Task {
            if let details = await PhotoMetadataProcessor.reverseGeocodeDetails(for: coordinate) {
                selectedAddress = details.address
                if trimmedPlaceName.isEmpty || (!didManuallyEditName && !didLockChosenStoreName) {
                    placeName = details.name
                }
            }
        }
    }

    private func moveCamera(to coordinate: GeoCoordinate, spanDelta: Double) {
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
            span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
        ))
    }

    private func performExplicitSearch() {
        let query = searchHelper.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearchFocused = false
        didInteractWithMap = true
        Task {
            isResolving = true
            defer { isResolving = false }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.pointOfInterest, .address]
            if let currentMapRegion {
                request.region = currentMapRegion
            }
            if let response = try? await MKLocalSearch(request: request).start() {
                let candidates: [ResolvedPlaceCandidate] = response.mapItems.prefix(6).compactMap { item in
                    let coord = GeoCoordinate(
                        latitude: item.location.coordinate.latitude,
                        longitude: item.location.coordinate.longitude
                    )
                    guard coord.isValid else { return nil }
                    let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let displayName = (name?.isEmpty == false ? name! : query)
                    let address = item.addressRepresentations?.cityWithContext
                        ?? item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
                    return ResolvedPlaceCandidate(name: displayName, address: address, coordinate: coord)
                }
                directSearchResults = candidates
                if let first = candidates.first {
                    moveCamera(to: first.coordinate, spanDelta: 0.012)
                }
            }
        }
    }

    private func resolveAndSelect(_ suggestion: PlaceSuggestion) {
        isSearchFocused = false
        didInteractWithMap = true
        Task {
            isResolving = true
            defer { isResolving = false }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = suggestion.searchQuery
            request.resultTypes = [.pointOfInterest, .address]
            if let currentMapRegion {
                request.region = currentMapRegion
            }
            if let response = try? await MKLocalSearch(request: request).start(),
               let item = response.mapItems.first {
                let coord = GeoCoordinate(
                    latitude: item.location.coordinate.latitude,
                    longitude: item.location.coordinate.longitude
                )
                let itemName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let chosenName = (item.pointOfInterestCategory != nil && itemName?.isEmpty == false)
                    ? itemName!
                    : suggestion.title
                let address = item.addressRepresentations?.cityWithContext
                    ?? item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
                    ?? (suggestion.subtitle.isEmpty ? nil : suggestion.subtitle)
                applyResolvedStore(
                    name: chosenName,
                    address: address,
                    coordinate: coord.isValid ? coord : selectedCoordinate,
                    spanDelta: 0.008
                )
            } else {
                applyResolvedStore(
                    name: suggestion.title,
                    address: suggestion.subtitle.isEmpty ? nil : suggestion.subtitle,
                    coordinate: selectedCoordinate,
                    spanDelta: 0.015
                )
            }
        }
    }

    private func resolveMapFeature(_ feature: MapFeature) {
        let request = MKMapItemRequest(feature: feature)
        request.getMapItem { item, _ in
            guard let item else { return }
            let itemCoord = GeoCoordinate(
                latitude: item.location.coordinate.latitude,
                longitude: item.location.coordinate.longitude
            )
            if itemCoord.isValid {
                selectedCoordinate = itemCoord
            }
            let address = item.addressRepresentations?.cityWithContext
                ?? item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
            if let address, !address.isEmpty {
                selectedAddress = address
            }
            if let itemName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !itemName.isEmpty {
                placeName = itemName
                didLockChosenStoreName = true
                didManuallyEditName = false
            }
        }
    }
}

private struct PlaceSuggestion: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let searchQuery: String
}

@MainActor
@Observable
private final class PlaceSearchHelper: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                suggestions = []
            } else {
                completer.queryFragment = trimmed
            }
        }
    }
    var suggestions: [PlaceSuggestion] = []

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = [.pointOfInterest, .address]
        completer.delegate = self
    }

    func updateRegion(_ region: MKCoordinateRegion) {
        completer.region = region
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let mapped = completer.results.prefix(8).enumerated().map { index, item in
            let combined = item.subtitle.isEmpty ? item.title : "\(item.title) \(item.subtitle)"
            return PlaceSuggestion(
                id: "\(index)-\(item.title)-\(item.subtitle)",
                title: item.title,
                subtitle: item.subtitle,
                searchQuery: combined
            )
        }
        Task { @MainActor [weak self] in
            self?.suggestions = mapped
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in
            self?.suggestions = []
        }
    }
}
