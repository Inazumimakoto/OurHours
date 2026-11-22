import OurHoursCore
import PhotosUI
import SwiftUI

private enum GalleryFilter: CaseIterable, Identifiable {
    case all
    case photos
    case videos
    case noLocation

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "すべて"
        case .photos: "写真"
        case .videos: "動画"
        case .noLocation: "場所なし"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .photos: "photo.fill"
        case .videos: "video.fill"
        case .noLocation: "mappin.slash"
        }
    }
}

private struct GalleryMonthSection: Identifiable {
    let id: String
    let title: String
    let items: [DayPhotoAttachment]
}

private struct GalleryViewerRoute: Identifiable {
    let id = UUID()
    let initialPhotoID: UUID
    let albumPhotoIDs: [UUID]
}

struct MemoriesGalleryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var isTabBarCollapsed: Bool
    let onFocusMapCoordinate: (GeoCoordinate) -> Void
    let onOpenDayDate: (Date) -> Void

    @State private var filter: GalleryFilter = .all
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var viewerRoute: GalleryViewerRoute?
    @State private var editingLocationPhoto: DayPhotoAttachment?
    @State private var selectedPlanRoute: PlanDetailRoute?
    @State private var selectedDayKeyFilter: String? = nil
    @State private var pendingMapCoordinateAfterPlan: GeoCoordinate?
    @State private var scrollAnchorY: CGFloat = 0
    @State private var lastScrollDirectionDown: Bool? = nil

    private struct GalleryScrollMetrics: Equatable {
        let offsetY: CGFloat
        let contentHeight: CGFloat
        let visibleHeight: CGFloat
    }

    private var allItems: [DayPhotoAttachment] {
        model.allMediaAttachments
    }

    private var dayScopedItems: [DayPhotoAttachment] {
        guard let selectedDayKeyFilter else { return allItems }
        return allItems.filter { $0.dayKey == selectedDayKeyFilter }
    }

    private var filteredItems: [DayPhotoAttachment] {
        switch filter {
        case .all: dayScopedItems
        case .photos: dayScopedItems.filter { $0.mediaKind == .photo }
        case .videos: dayScopedItems.filter { $0.mediaKind == .video }
        case .noLocation: dayScopedItems.filter { $0.coordinate == nil }
        }
    }

    private var monthSections: [GalleryMonthSection] {
        var order: [String] = []
        var grouped: [String: [DayPhotoAttachment]] = [:]
        for item in filteredItems {
            let monthKey = String(item.dayKey.prefix(7))
            if grouped[monthKey] == nil {
                order.append(monthKey)
                grouped[monthKey] = []
            }
            grouped[monthKey]?.append(item)
        }
        return order.compactMap { key in
            guard let items = grouped[key], !items.isEmpty else { return nil }
            return GalleryMonthSection(id: key, title: formattedMonthTitle(key), items: items)
        }
    }

    private func count(for filter: GalleryFilter) -> Int {
        switch filter {
        case .all: dayScopedItems.count
        case .photos: dayScopedItems.count { $0.mediaKind == .photo }
        case .videos: dayScopedItems.count { $0.mediaKind == .video }
        case .noLocation: dayScopedItems.count { $0.coordinate == nil }
        }
    }

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        let items = filteredItems
        let plans = model.allPlanEvents
        let importing = isImporting

        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("アルバム")
                        .font(FoamFont.bold(22, relativeTo: .title2))
                        .foregroundStyle(FoamTheme.ink)
                    Text("\(items.count)件")
                        .font(FoamFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(FoamTheme.warmAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.84), in: Capsule())

                    Spacer(minLength: 4)

                    PhotosPicker(
                        selection: $pickerItems,
                        matching: .any(of: [.images, .videos])
                    ) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("追加")
                                .font(FoamFont.bold(12, relativeTo: .caption))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(FoamTheme.ink, in: Capsule())
                    }
                    .disabled(importing)
                }
                .padding(.trailing, 58)

                if !allItems.isEmpty {
                    filterChipsRow
                }

                if let selectedDayKeyFilter {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(FoamTheme.warmAccent)
                        Text("\(MemoryMapPinBuilder.formattedDayTitle(selectedDayKeyFilter))の写真・動画のみ")
                            .font(FoamFont.bold(12, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.ink)
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78)) {
                                self.selectedDayKeyFilter = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(FoamTheme.ink.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("日付の絞り込みを解除")
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.88), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.white, lineWidth: 1)
                    }
                }

                MediaTransferProgressBanner()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if allItems.isEmpty {
                if !plans.isEmpty {
                    tripAlbumsShelf(plans: plans)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
                emptyStateCard(
                    title: "まだ写真や動画がありません",
                    message: "アルバムから選ぶか、カレンダーの日別の思い出から写真・動画を追加できます。",
                    showsPicker: true
                )
                .padding(.horizontal, 18)
                Spacer(minLength: 0)
            } else if items.isEmpty {
                if !plans.isEmpty {
                    tripAlbumsShelf(plans: plans)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
                emptyStateCard(
                    title: "この条件の写真・動画はありません",
                    message: "フィルタを「すべて」に戻すと、保存済みの思い出を見られます。",
                    showsPicker: false
                )
                .padding(.horizontal, 18)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if !plans.isEmpty {
                            tripAlbumsShelf(plans: plans)
                        }

                        ForEach(monthSections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(section.title)
                                        .font(FoamFont.bold(16, relativeTo: .headline))
                                        .foregroundStyle(FoamTheme.ink)
                                    Text("\(section.items.count)件")
                                        .font(FoamFont.bold(11.5, relativeTo: .caption))
                                        .foregroundStyle(FoamTheme.ink.opacity(0.55))
                                }
                                .padding(.horizontal, 16)

                                LazyVGrid(columns: gridColumns, spacing: 3) {
                                    ForEach(section.items) { item in
                                        galleryTile(item: item, orderedIDs: items.map(\.id))
                                    }
                                }
                                .padding(.horizontal, 10)
                            }
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 108)
                }
                .onScrollGeometryChange(for: GalleryScrollMetrics.self) { geo in
                    GalleryScrollMetrics(
                        offsetY: geo.contentOffset.y + geo.contentInsets.top,
                        contentHeight: geo.contentSize.height,
                        visibleHeight: geo.containerSize.height
                    )
                } action: { oldValue, newValue in
                    handleScrollMetricsChange(oldValue, newValue)
                }
            }
        }
        .onChange(of: filter) { _, _ in
            expandTabBar()
        }
        .onChange(of: selectedDayKeyFilter) { _, _ in
            expandTabBar()
        }
        .onChange(of: items.isEmpty) { _, isEmpty in
            if isEmpty {
                expandTabBar()
            }
        }
        .onChange(of: pickerItems) { _, picked in
            guard !picked.isEmpty else { return }
            let itemsToImport = picked
            pickerItems = []
            Task {
                isImporting = true
                defer { isImporting = false }
                await importPickedMediaItems(itemsToImport, dayKey: selectedDayKeyFilter, model: model)
            }
        }
        .fullScreenCover(item: $viewerRoute) { route in
            DayPhotoViewerSheet(
                dayKey: nil,
                initialPhotoID: route.initialPhotoID,
                albumPhotoIDs: route.albumPhotoIDs,
                onFocusMapCoordinate: onFocusMapCoordinate,
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
        .fullScreenCover(item: $selectedPlanRoute, onDismiss: {
            if let coord = pendingMapCoordinateAfterPlan {
                pendingMapCoordinateAfterPlan = nil
                onFocusMapCoordinate(coord)
            }
        }) { route in
            TripAlbumGallerySheet(
                planID: route.id,
                onFocusMapCoordinate: { coord in
                    pendingMapCoordinateAfterPlan = coord
                }
            )
        }
    }

    @ViewBuilder
    private func tripAlbumsShelf(plans: [PairPlanEvent]) -> some View {
        let todayKey = EncounterCalendarAggregator.dayKey(for: .now)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("旅行・イベント")
                    .font(FoamFont.bold(16, relativeTo: .headline))
                    .foregroundStyle(FoamTheme.ink)
                Text("\(plans.count)件")
                    .font(FoamFont.bold(11.5, relativeTo: .caption))
                    .foregroundStyle(FoamTheme.ink.opacity(0.55))
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(plans) { plan in
                        tripCoverCard(plan: plan, todayKey: todayKey)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func tripCoverCard(plan: PairPlanEvent, todayKey: String) -> some View {
        let media = model.mediaAttachments(for: plan)
        let coverImage = media.first.flatMap { model.dayMediaThumbnail(for: $0) }
        let status = plan.lifecycleStatus(asOfDayKey: todayKey)
        let badgeLabel: String = switch status {
        case .upcoming:
            if let days = plan.daysUntilStart(asOfDayKey: todayKey) {
                days <= 1 ? "明日" : "あと\(days)日"
            } else {
                "予定"
            }
        case .ongoing: "開催中"
        case .past: "\(media.count)枚"
        }

        Button {
            selectedPlanRoute = PlanDetailRoute(id: plan.id)
        } label: {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: plan.icon.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .overlay {
                            Image(systemName: plan.icon.symbolName)
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.white.opacity(0.38))
                                .offset(x: 34, y: -16)
                        }
                    }
                }
                .frame(width: 158, height: 116)
                .clipped()

                LinearGradient(
                    colors: [Color.black.opacity(0.02), Color.black.opacity(0.68)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: plan.icon.symbolName)
                            .font(.system(size: 10, weight: .bold))
                        Text(badgeLabel)
                            .font(FoamFont.bold(10.5, relativeTo: .caption2))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        status == .upcoming || status == .ongoing
                            ? plan.icon.accentColor.opacity(0.92)
                            : Color.black.opacity(0.42),
                        in: Capsule()
                    )

                    Spacer(minLength: 4)

                    Text(plan.title)
                        .font(FoamFont.bold(13.5, relativeTo: .subheadline))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(plan.formattedDateRange)
                        .font(FoamFont.medium(10.5, relativeTo: .caption2))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                }
                .padding(10)
            }
            .frame(width: 158, height: 116)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.92), lineWidth: 1.5)
            }
            .shadow(color: FoamTheme.ink.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(GalleryFilter.allCases) { item in
                    let selected = filter == item
                    let itemCount = count(for: item)
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78)) {
                            filter = item
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: item.symbolName)
                                .font(.system(size: 11, weight: .bold))
                            Text("\(item.title) (\(itemCount))")
                                .font(FoamFont.bold(12, relativeTo: .caption))
                        }
                        .foregroundStyle(selected ? .white : FoamTheme.ink.opacity(0.80))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(selected ? FoamTheme.ink : Color.white.opacity(0.86))
                                .overlay {
                                    if !selected {
                                        Capsule().strokeBorder(Color.white, lineWidth: 1)
                                    }
                                }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func galleryTile(item: DayPhotoAttachment, orderedIDs: [UUID]) -> some View {
        Button {
            viewerRoute = GalleryViewerRoute(initialPhotoID: item.id, albumPhotoIDs: orderedIDs)
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
                .overlay(alignment: .topTrailing) {
                    if model.isMediaUploading(id: item.id) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.56), in: Circle())
                            .padding(5)
                    }
                }
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
        .accessibilityLabel(item.locationName ?? (item.mediaKind == .video ? "動画" : "写真"))
        .contextMenu {
            Button {
                editingLocationPhoto = item
            } label: {
                Label(item.coordinate == nil ? "場所を検索してつける" : "店舗・位置を調整", systemImage: "mappin.and.ellipse")
            }
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78)) {
                    selectedDayKeyFilter = item.dayKey
                }
            } label: {
                Label("\(MemoryMapPinBuilder.formattedDayTitle(item.dayKey))の写真だけ見る", systemImage: "calendar")
            }
            if let coord = item.coordinate {
                Button {
                    onFocusMapCoordinate(coord)
                } label: {
                    Label("地図で見る", systemImage: "map.fill")
                }
            }
            if !model.allPlanEvents.isEmpty {
                let matchedPlan = model.effectivePlan(for: item)
                Menu {
                    ForEach(model.allPlanEvents) { plan in
                        Button {
                            model.assignMedia(id: item.id, toPlanID: plan.id)
                        } label: {
                            if matchedPlan?.id == plan.id {
                                Label(plan.title, systemImage: "checkmark")
                            } else {
                                Text(plan.title)
                            }
                        }
                    }
                    if let matchedPlan {
                        Divider()
                        Button {
                            model.excludeMedia(id: item.id, fromPlanID: matchedPlan.id)
                        } label: {
                            Label("アルバムから外す", systemImage: "folder.badge.minus")
                        }
                    }
                } label: {
                    Label("旅行・イベントアルバム", systemImage: "folder")
                }
            }
            Button(role: .destructive) {
                model.deleteDayPhoto(id: item.id)
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func emptyStateCard(title: String, message: String, showsPicker: Bool) -> some View {
        let importing = isImporting
        VStack(spacing: 12) {
            Image(systemName: showsPicker ? "photo.on.rectangle.angled" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(FoamTheme.ink.opacity(0.70))
            Text(title)
                .font(FoamFont.bold(17, relativeTo: .headline))
                .foregroundStyle(FoamTheme.ink)
            Text(message)
                .font(FoamFont.regular(13, relativeTo: .footnote))
                .foregroundStyle(FoamTheme.ink.opacity(0.68))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            if showsPicker {
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
            } else {
                Button("すべて表示") {
                    filter = .all
                    selectedDayKeyFilter = nil
                }
                .buttonStyle(FoamCardActionStyle(fullWidth: false))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            SoapBubbleSurface(
                cornerStyle: .roundedRect(24),
                prominence: .standard,
                isTogether: model.isTogetherNow,
                seed: 4.8,
                wobbleScale: 0.35,
                animated: false
            )
        }
        .shadow(color: FoamTheme.ink.opacity(0.10), radius: 10, y: 3)
        .padding(.bottom, 96)
    }

    private func handleScrollMetricsChange(_ old: GalleryScrollMetrics, _ new: GalleryScrollMetrics) {
        if new.contentHeight <= new.visibleHeight + 60 || new.offsetY <= 16 {
            scrollAnchorY = new.offsetY
            lastScrollDirectionDown = nil
            expandTabBar()
            return
        }
        // Ignore bottom overscroll bounce so dragging back up at the bottom edge does not jitter.
        if new.offsetY + new.visibleHeight >= new.contentHeight - 8 {
            return
        }
        let delta = new.offsetY - old.offsetY
        guard abs(delta) >= 0.5 else { return }
        let movingDown = delta > 0
        if lastScrollDirectionDown != movingDown {
            lastScrollDirectionDown = movingDown
            scrollAnchorY = old.offsetY
        }
        if movingDown {
            if new.offsetY > 40 && (new.offsetY - scrollAnchorY) > 28 && !isTabBarCollapsed {
                setTabBarCollapsed(true)
            }
        } else if (scrollAnchorY - new.offsetY) > 18 && isTabBarCollapsed {
            setTabBarCollapsed(false)
        }
    }

    private func expandTabBar() {
        if isTabBarCollapsed {
            setTabBarCollapsed(false)
        }
    }

    private func setTabBarCollapsed(_ collapsed: Bool) {
        if reduceMotion {
            isTabBarCollapsed = collapsed
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                isTabBarCollapsed = collapsed
            }
        }
    }

    private func formattedMonthTitle(_ monthKey: String) -> String {
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else {
            return monthKey
        }
        return "\(year)年\(month)月"
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func parsedDate(fromDayKey dayKey: String) -> Date {
        let parts = dayKey.split(separator: "-")
        if parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) {
            return CalendarDateValue(year: y, month: m, day: d).toDate()
        }
        return .now
    }
}
