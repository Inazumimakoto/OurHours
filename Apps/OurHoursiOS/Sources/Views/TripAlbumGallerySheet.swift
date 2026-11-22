import OurHoursCore
import PhotosUI
import SwiftUI

private struct TripAlbumViewerRoute: Identifiable {
    let id = UUID()
    let initialPhotoID: UUID
    let albumPhotoIDs: [UUID]
}

/// Photo-and-video-focused trip/event album opened from the Album tab without checklists or planning forms.
struct TripAlbumGallerySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let planID: UUID
    var onFocusMapCoordinate: ((GeoCoordinate) -> Void)? = nil

    @State private var selectedDayKey: String? = nil
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var viewerRoute: TripAlbumViewerRoute?
    @State private var editingLocationPhoto: DayPhotoAttachment?
    @State private var pendingMapCoordinateAfterViewer: GeoCoordinate?

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        let plan = model.planEvent(id: planID)

        ZStack {
            FoamTheme.sky(together: model.isTogetherNow)
                .ignoresSafeArea()
            FoamAmbientBackgroundView(isTogether: model.isTogetherNow, softened: true)
                .ignoresSafeArea()

            if let plan {
                let allMedia = model.mediaAttachments(for: plan)
                let dayKeys = availableDayKeys(for: plan, media: allMedia)
                let media = filteredMedia(in: allMedia)

                VStack(spacing: 0) {
                    topBar(plan: plan)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 8)

                    if dayKeys.count > 1 || selectedDayKey != nil {
                        dayFilterRow(dayKeys: dayKeys, allMedia: allMedia)
                            .padding(.bottom, 8)
                    }

                    MediaTransferProgressBanner()
                        .padding(.horizontal, 16)

                    if media.isEmpty {
                        Spacer(minLength: 0)
                        emptyStateCard(plan: plan, hasAnyMedia: !allMedia.isEmpty)
                            .padding(.horizontal, 18)
                        Spacer(minLength: 0)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: gridColumns, spacing: 3) {
                                ForEach(media) { item in
                                    mediaTile(item: item, plan: plan, orderedIDs: media.map(\.id))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 4)
                            .padding(.bottom, 36)
                        }
                    }
                }
            } else {
                Color.clear.onAppear {
                    dismiss()
                }
            }
        }
        .font(FoamFont.medium(16))
        .foregroundStyle(FoamTheme.ink)
        .preferredColorScheme(.light)
        .onChange(of: pickerItems) { _, picked in
            guard !picked.isEmpty, let plan else { return }
            let itemsToImport = picked
            pickerItems = []
            Task {
                isImporting = true
                defer { isImporting = false }
                await importPickedMediaItems(
                    itemsToImport,
                    dayKey: selectedDayKey,
                    model: model,
                    planID: plan.id,
                    fallbackDayKey: selectedDayKey ?? plan.startDayKey
                )
            }
        }
        .fullScreenCover(item: $viewerRoute, onDismiss: {
            if let coord = pendingMapCoordinateAfterViewer {
                pendingMapCoordinateAfterViewer = nil
                dismiss()
                onFocusMapCoordinate?(coord)
            }
        }) { route in
            DayPhotoViewerSheet(
                dayKey: nil,
                initialPhotoID: route.initialPhotoID,
                albumPhotoIDs: route.albumPhotoIDs,
                headerTitle: plan?.title,
                onFocusMapCoordinate: { coord in
                    pendingMapCoordinateAfterViewer = coord
                },
                onOpenDayDetail: nil
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

    @ViewBuilder
    private func topBar(plan: PairPlanEvent) -> some View {
        let importing = isImporting
        HStack(spacing: 10) {
            FoamRoundIconButton(accessibilityLabel: "戻る") {
                dismiss()
            } icon: {
                FoamChevronIcon(direction: -1)
            }

            Spacer(minLength: 4)

            VStack(spacing: 1) {
                Text(plan.title)
                    .font(FoamFont.bold(16, relativeTo: .headline))
                    .foregroundStyle(FoamTheme.ink)
                    .lineLimit(1)
                Text(plan.formattedDateRange)
                    .font(FoamFont.medium(11.5, relativeTo: .caption))
                    .foregroundStyle(FoamTheme.ink.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            PhotosPicker(
                selection: $pickerItems,
                matching: .any(of: [.images, .videos])
            ) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("追加")
                        .font(FoamFont.bold(12, relativeTo: .caption))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(FoamTheme.ink, in: Capsule())
            }
            .disabled(importing)
        }
    }

    private func dayFilterRow(dayKeys: [String], allMedia: [DayPhotoAttachment]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                dayChip(title: "すべて (\(allMedia.count))", isSelected: selectedDayKey == nil) {
                    selectedDayKey = nil
                }

                ForEach(dayKeys, id: \.self) { dayKey in
                    let count = allMedia.count { $0.dayKey == dayKey }
                    dayChip(
                        title: count > 0 ? "\(shortMonthDayTitle(dayKey)) (\(count))" : shortMonthDayTitle(dayKey),
                        isSelected: selectedDayKey == dayKey
                    ) {
                        selectedDayKey = (selectedDayKey == dayKey) ? nil : dayKey
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func dayChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FoamFont.bold(12, relativeTo: .caption))
                .foregroundStyle(isSelected ? .white : FoamTheme.ink.opacity(0.80))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? FoamTheme.ink : Color.white.opacity(0.86))
                        .overlay {
                            if !isSelected {
                                Capsule().strokeBorder(Color.white, lineWidth: 1)
                            }
                        }
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func mediaTile(item: DayPhotoAttachment, plan: PairPlanEvent, orderedIDs: [UUID]) -> some View {
        Button {
            viewerRoute = TripAlbumViewerRoute(initialPhotoID: item.id, albumPhotoIDs: orderedIDs)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image = model.dayMediaThumbnail(for: item) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color.white.opacity(0.68)
                            ProgressView()
                                .controlSize(.small)
                                .tint(FoamTheme.ink.opacity(0.62))
                        }
                    }
                }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if item.mediaKind == .video {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8.5, weight: .bold))
                            if let sec = item.durationSeconds {
                                Text(formattedDuration(sec))
                                    .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(Color.black.opacity(0.62), in: Capsule())
                        .padding(5)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if item.coordinate != nil {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(FoamTheme.warmAccent, Color.white)
                            .shadow(color: FoamTheme.ink.opacity(0.24), radius: 2, y: 1)
                            .padding(5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingLocationPhoto = item
            } label: {
                Label(item.coordinate == nil ? "場所を検索してつける" : "店舗・位置を調整", systemImage: "mappin.and.ellipse")
            }
            if let coord = item.coordinate, let onFocusMapCoordinate {
                Button {
                    dismiss()
                    onFocusMapCoordinate(coord)
                } label: {
                    Label("地図で見る", systemImage: "map.fill")
                }
            }
            Button {
                model.excludeMedia(id: item.id, fromPlanID: plan.id)
            } label: {
                Label("このアルバムから外す", systemImage: "folder.badge.minus")
            }
            Button(role: .destructive) {
                model.deleteDayPhoto(id: item.id)
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func emptyStateCard(plan: PairPlanEvent, hasAnyMedia: Bool) -> some View {
        let importing = isImporting
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(plan.icon.accentColor)
            Text(hasAnyMedia ? "この日に登録された写真・動画はありません" : "まだ写真・動画がありません")
                .font(FoamFont.bold(15, relativeTo: .subheadline))
                .foregroundStyle(FoamTheme.ink)
            Text("「+ 追加」から写真や動画を追加すると、\(plan.title)のアルバムに並びます。")
                .font(FoamFont.regular(12.5, relativeTo: .caption))
                .foregroundStyle(FoamTheme.ink.opacity(0.68))
                .multilineTextAlignment(.center)
            if hasAnyMedia {
                Button("すべて表示") {
                    selectedDayKey = nil
                }
                .buttonStyle(FoamCardActionStyle(fullWidth: false))
            } else {
                PhotosPicker(
                    selection: $pickerItems,
                    matching: .any(of: [.images, .videos])
                ) {
                    Label("写真・動画を追加", systemImage: "plus")
                        .font(FoamFont.bold(14, relativeTo: .subheadline))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(FoamTheme.ink, in: Capsule())
                }
                .disabled(importing)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            SoapBubbleSurface(
                cornerStyle: .roundedRect(24),
                prominence: .standard,
                isTogether: model.isTogetherNow,
                seed: 5.8,
                wobbleScale: 0.25,
                animated: false,
                milkyFillOpacity: 0.84
            )
        }
        .shadow(color: FoamTheme.ink.opacity(0.08), radius: 8, y: 3)
    }

    private func availableDayKeys(for plan: PairPlanEvent, media: [DayPhotoAttachment]) -> [String] {
        var set = Set(media.map(\.dayKey))
        if plan.spanDayCount <= 14 {
            set.formUnion(plan.dayKeys())
        }
        return set.sorted()
    }

    private func filteredMedia(in media: [DayPhotoAttachment]) -> [DayPhotoAttachment] {
        guard let selectedDayKey else { return media }
        return media.filter { $0.dayKey == selectedDayKey }
    }

    private func shortMonthDayTitle(_ dayKey: String) -> String {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return dayKey }
        return "\(m)/\(d)"
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
