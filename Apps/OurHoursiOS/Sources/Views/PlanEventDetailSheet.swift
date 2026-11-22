import OurHoursCore
import PhotosUI
import SwiftUI

struct PlanDetailRoute: Identifiable, Equatable {
    let id: UUID
}

private struct PlanViewerRoute: Identifiable {
    let id = UUID()
    let initialPhotoID: UUID
    let albumPhotoIDs: [UUID]
}

private struct PlanChecklistComposerRoute: Identifiable {
    let id = UUID()
    let kind: PairPlanChecklistKind
}

struct PlanEventDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let planID: UUID
    var onFocusMapCoordinate: ((GeoCoordinate) -> Void)? = nil
    var onOpenDayDate: ((Date) -> Void)? = nil

    @State private var showEditSheet = false
    @State private var composerRoute: PlanChecklistComposerRoute?
    @State private var selectedMediaDayFilter: String? = nil
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var viewerRoute: PlanViewerRoute?
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
                let media = model.mediaAttachments(for: plan)
                let places = model.placeTags(for: plan)
                let recordedSeconds = model.recordedSeconds(for: plan)

                VStack(spacing: 0) {
                    topBar(plan: plan)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 8)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            heroCard(plan: plan, mediaCount: media.count, placeCount: places.count, recordedSeconds: recordedSeconds)

                            checklistCard(plan: plan, kind: .todo)

                            checklistCard(plan: plan, kind: .packing)

                            if !places.isEmpty {
                                placesSection(places: places)
                            }

                            mediaSection(plan: plan, allMedia: media)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 40)
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
        .sheet(isPresented: $showEditSheet) {
            if let plan {
                PlanEventEditorSheet(
                    existingPlan: plan,
                    onDeleted: { dismiss() }
                )
            }
        }
        .sheet(item: $composerRoute) { route in
            if let plan {
                PlanChecklistComposerSheet(
                    planTitle: plan.title,
                    target: .persisted(planID: plan.id),
                    initialKind: route.kind
                )
            }
        }
        .onChange(of: pickerItems) { _, picked in
            guard !picked.isEmpty, let plan else { return }
            let itemsToImport = picked
            pickerItems = []
            Task {
                isImporting = true
                defer { isImporting = false }
                await importPickedMediaItems(
                    itemsToImport,
                    dayKey: selectedMediaDayFilter,
                    model: model,
                    planID: plan.id,
                    fallbackDayKey: selectedMediaDayFilter ?? plan.startDayKey
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
        HStack {
            FoamRoundIconButton(accessibilityLabel: "戻る") {
                dismiss()
            } icon: {
                FoamChevronIcon(direction: -1)
            }

            Spacer(minLength: 8)

            Text(plan.title)
                .font(FoamFont.bold(16, relativeTo: .headline))
                .foregroundStyle(FoamTheme.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                showEditSheet = true
            } label: {
                Text("編集")
                    .font(FoamFont.bold(13, relativeTo: .caption))
                    .foregroundStyle(FoamTheme.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Color.white.opacity(0.84), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.white, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func heroCard(
        plan: PairPlanEvent,
        mediaCount: Int,
        placeCount: Int,
        recordedSeconds: TimeInterval
    ) -> some View {
        let todayKey = EncounterCalendarAggregator.dayKey(for: .now)
        let status = plan.lifecycleStatus(asOfDayKey: todayKey)
        let statusBadge: (text: String, tint: Color) = switch status {
        case .upcoming:
            if let days = plan.daysUntilStart(asOfDayKey: todayKey) {
                (days <= 1 ? "予定 · 明日" : "予定 · あと\(days)日", plan.icon.accentColor)
            } else {
                ("予定", plan.icon.accentColor)
            }
        case .ongoing:
            ("いま開催中", FoamTheme.warmAccent)
        case .past:
            ("おもいで", FoamTheme.ink.opacity(0.68))
        }

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: plan.icon.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    Image(systemName: plan.icon.symbolName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(plan.formattedDateRange)
                            .font(FoamFont.bold(13, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.ink.opacity(0.74))
                        if plan.spanDayCount > 1 {
                            Text("(\(plan.spanDayCount)日間)")
                                .font(FoamFont.bold(11.5, relativeTo: .caption2))
                                .foregroundStyle(FoamTheme.ink.opacity(0.55))
                        }
                    }

                    Text(plan.title)
                        .font(FoamFont.bold(20, relativeTo: .title3))
                        .foregroundStyle(FoamTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Text(statusBadge.text)
                    .font(FoamFont.bold(11.5, relativeTo: .caption2))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusBadge.tint, in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if recordedSeconds > 0 {
                        statPill(icon: "clock.fill", text: "いっしょに \(FoamTheme.duration(recordedSeconds))", tint: FoamTheme.warmAccent)
                    }
                    statPill(icon: "photo.on.rectangle", text: "写真・動画 \(mediaCount)件", tint: plan.icon.accentColor)
                    if placeCount > 0 {
                        statPill(icon: "mappin.and.ellipse", text: "場所 \(placeCount)件", tint: FoamTheme.warmAccent)
                    }
                }
            }

            if let memo = plan.memo, !memo.isEmpty {
                Text(memo)
                    .font(FoamFont.regular(14, relativeTo: .subheadline))
                    .foregroundStyle(FoamTheme.ink.opacity(0.84))
                    .lineSpacing(3)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            SoapBubbleSurface(
                cornerStyle: .roundedRect(24),
                prominence: .standard,
                isTogether: model.isTogetherNow,
                seed: 4.1,
                wobbleScale: 0.25,
                animated: false,
                milkyFillOpacity: 0.84
            )
        }
        .shadow(color: FoamTheme.ink.opacity(0.08), radius: 8, y: 3)
    }

    @ViewBuilder
    private func checklistCard(plan: PairPlanEvent, kind: PairPlanChecklistKind) -> some View {
        let items = kind == .todo ? plan.todoItems : plan.packingItems
        let doneCount = items.count { $0.isDone }
        let tint: Color = kind == .todo ? FoamTheme.warmAccent : Color(red: 0.24, green: 0.56, blue: 0.92)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(kind == .todo ? "やりたいこと" : "持ち物リスト", systemImage: kind.symbolName)
                    .font(FoamFont.bold(14.5, relativeTo: .subheadline))
                    .foregroundStyle(FoamTheme.ink)

                if !items.isEmpty {
                    Text("\(doneCount) / \(items.count)")
                        .font(FoamFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(doneCount == items.count ? tint : FoamTheme.ink.opacity(0.58))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.72), in: Capsule())
                }

                Spacer()

                Button {
                    composerRoute = PlanChecklistComposerRoute(kind: kind)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10.5, weight: .bold))
                        Text("追加")
                            .font(FoamFont.bold(11.5, relativeTo: .caption2))
                    }
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.86), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.white, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }

            if items.isEmpty {
                Button {
                    composerRoute = PlanChecklistComposerRoute(kind: kind)
                } label: {
                    Text(kind == .todo ? "「+ 追加」からやりたいことを追加できます" : "「+ 追加」から持ち物を追加できます")
                        .font(FoamFont.regular(12.5, relativeTo: .caption))
                        .foregroundStyle(FoamTheme.ink.opacity(0.54))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            model.togglePlanChecklistItem(planID: plan.id, itemID: item.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(item.isDone ? tint : FoamTheme.ink.opacity(0.32))
                                Text(item.title)
                                    .font(FoamFont.medium(14.5, relativeTo: .subheadline))
                                    .foregroundStyle(item.isDone ? FoamTheme.ink.opacity(0.46) : FoamTheme.ink)
                                    .strikethrough(item.isDone)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            SoapBubbleSurface(
                cornerStyle: .roundedRect(22),
                prominence: .standard,
                isTogether: model.isTogetherNow,
                seed: kind == .todo ? 5.5 : 6.7,
                wobbleScale: 0.25,
                animated: false,
                milkyFillOpacity: 0.80
            )
        }
    }

    @ViewBuilder
    private func placesSection(places: [DayPlaceTag]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("訪れた場所")
                .font(FoamFont.bold(15, relativeTo: .subheadline))
                .foregroundStyle(FoamTheme.ink)
                .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(places) { tag in
                        Button {
                            if let coord = tag.coordinate, coord.isValid {
                                dismiss()
                                onFocusMapCoordinate?(coord)
                            } else {
                                let date = PairPlanEvent.dayKeyDate(tag.dayKey) ?? .now
                                dismiss()
                                onOpenDayDate?(date)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tag.coordinate?.isValid == true ? "mappin.circle.fill" : "mappin")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(FoamTheme.warmAccent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tag.name)
                                        .font(FoamFont.bold(12.5, relativeTo: .caption))
                                        .foregroundStyle(FoamTheme.ink)
                                    Text(shortMonthDayTitle(tag.dayKey))
                                        .font(FoamFont.regular(10, relativeTo: .caption2))
                                        .foregroundStyle(FoamTheme.ink.opacity(0.55))
                                }
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.84), in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(Color.white, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mediaSection(plan: PairPlanEvent, allMedia: [DayPhotoAttachment]) -> some View {
        let importing = isImporting
        let todayKey = EncounterCalendarAggregator.dayKey(for: .now)
        let status = plan.lifecycleStatus(asOfDayKey: todayKey)
        let dayKeys = availableDayKeys(for: plan, media: allMedia)
        let filtered = selectedMediaDayFilter.map { dayKey in allMedia.filter { $0.dayKey == dayKey } } ?? allMedia

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("写真・動画")
                    .font(FoamFont.bold(15.5, relativeTo: .headline))
                    .foregroundStyle(FoamTheme.ink)
                Text("\(filtered.count)件")
                    .font(FoamFont.bold(12, relativeTo: .caption))
                    .foregroundStyle(FoamTheme.ink.opacity(0.58))

                Spacer()

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
                    .padding(.vertical, 6)
                    .background(FoamTheme.ink, in: Capsule())
                }
                .disabled(importing)
            }

            if dayKeys.count > 1 || selectedMediaDayFilter != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        dayFilterChip(title: "すべて (\(allMedia.count))", isSelected: selectedMediaDayFilter == nil) {
                            selectedMediaDayFilter = nil
                        }
                        ForEach(dayKeys, id: \.self) { dayKey in
                            let count = allMedia.count { $0.dayKey == dayKey }
                            dayFilterChip(
                                title: count > 0 ? "\(shortMonthDayTitle(dayKey)) (\(count))" : shortMonthDayTitle(dayKey),
                                isSelected: selectedMediaDayFilter == dayKey
                            ) {
                                selectedMediaDayFilter = (selectedMediaDayFilter == dayKey) ? nil : dayKey
                            }
                        }
                    }
                }
            }

            MediaTransferProgressBanner()

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: status == .upcoming ? "sparkles" : "photo.on.rectangle.angled")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(plan.icon.accentColor)
                    Text(
                        selectedMediaDayFilter != nil
                            ? "この日の写真・動画はありません"
                            : (status == .upcoming ? "予定日が近づいたら写真が増えていきます" : "この期間の写真・動画がまだありません")
                    )
                        .font(FoamFont.bold(14, relativeTo: .subheadline))
                        .foregroundStyle(FoamTheme.ink)
                    if selectedMediaDayFilter != nil {
                        Button("すべて表示") {
                            selectedMediaDayFilter = nil
                        }
                        .buttonStyle(FoamCardActionStyle(fullWidth: false))
                    } else {
                        Text("「+ 追加」からこのアルバムに直接写真や動画を追加したり、\(plan.formattedDateRange)に撮影・追加すると自動でまとまります。")
                            .font(FoamFont.regular(12.5, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.ink.opacity(0.68))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background {
                    SoapBubbleSurface(
                        cornerStyle: .roundedRect(22),
                        prominence: .standard,
                        isTogether: model.isTogetherNow,
                        seed: 7.2,
                        wobbleScale: 0.25,
                        animated: false,
                        milkyFillOpacity: 0.78
                    )
                }
            } else {
                LazyVGrid(columns: gridColumns, spacing: 3) {
                    ForEach(filtered) { item in
                        mediaTile(item: item, plan: plan, orderedIDs: filtered.map(\.id))
                    }
                }
            }
        }
    }

    private func dayFilterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FoamFont.bold(11.5, relativeTo: .caption2))
                .foregroundStyle(isSelected ? .white : FoamTheme.ink.opacity(0.80))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
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
            viewerRoute = PlanViewerRoute(initialPhotoID: item.id, albumPhotoIDs: orderedIDs)
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

    private func statPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(FoamFont.bold(12, relativeTo: .caption))
                .foregroundStyle(FoamTheme.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.82), in: Capsule())
    }

    private func availableDayKeys(for plan: PairPlanEvent, media: [DayPhotoAttachment]) -> [String] {
        var set = Set(media.map(\.dayKey))
        if plan.spanDayCount <= 14 {
            set.formUnion(plan.dayKeys())
        }
        return set.sorted()
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
