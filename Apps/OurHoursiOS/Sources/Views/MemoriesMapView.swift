import MapKit
import OurHoursCore
import SwiftUI

private enum MemoryMapFilter: CaseIterable, Identifiable {
    case all
    case photos
    case places

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "すべて"
        case .photos: "写真・動画"
        case .places: "場所タグ"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "sparkles"
        case .photos: "photo.fill"
        case .places: "mappin.circle.fill"
        }
    }
}

private struct MapDayRoute: Identifiable {
    let id = UUID()
    let date: Date
}

private struct MapMediaViewerRoute: Identifiable {
    let id = UUID()
    let dayKey: String
    let initialPhotoID: UUID
    let scopedPhotoIDs: [UUID]
    let headerTitle: String
}

struct MemoriesMapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var focusCoordinate: GeoCoordinate?
    @Binding var isFullScreen: Bool
    let onOpenCalendar: () -> Void

    @State private var filter: MemoryMapFilter = .all
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var locationFetcher = OneShotLocationFetcher()
    @State private var selectedPinID: String?
    @State private var detailRoute: MapDayRoute?
    @State private var viewerRoute: MapMediaViewerRoute?
    @State private var pendingDetailDateAfterViewer: Date?

    private var allPins: [MemoryMapPin] {
        model.memoryMapPins
    }

    private var filteredPins: [MemoryMapPin] {
        switch filter {
        case .all: allPins
        case .photos: allPins.filter(\.hasPhotos)
        case .places: allPins.filter(\.hasPlaceTags)
        }
    }

    private var selectedPin: MemoryMapPin? {
        guard let selectedPinID else { return nil }
        return filteredPins.first(where: { $0.id == selectedPinID })
    }

    private func count(for filter: MemoryMapFilter) -> Int {
        switch filter {
        case .all: allPins.count
        case .photos: allPins.count(where: \.hasPhotos)
        case .places: allPins.count(where: \.hasPlaceTags)
        }
    }

    var body: some View {
        ZStack {
            if isFullScreen {
                fullScreenLayout
            } else {
                cardLayout
            }
        }
        .onAppear {
            #if DEBUG
            if ScreenshotScene.current == .map {
                let featured = filteredPins.first(where: { $0.title.contains("横浜") }) ?? filteredPins.first
                selectedPinID = featured?.id
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 35.48, longitude: 139.66),
                        span: MKCoordinateSpan(latitudeDelta: 0.68, longitudeDelta: 0.62)
                    )
                )
                return
            }
            #endif
            if let focusCoordinate {
                applyFocus(focusCoordinate)
            } else {
                fitAllPins(animated: false)
            }
        }
        .task {
            if allPins.isEmpty && focusCoordinate == nil {
                if let currentCoord = await locationFetcher.fetchCurrentCoordinate(requestAuthorizationIfNeeded: false) {
                    if allPins.isEmpty && focusCoordinate == nil {
                        centerCamera(on: currentCoord, spanDelta: 0.08)
                    }
                }
            }
        }
        .onChange(of: focusCoordinate) { _, newValue in
            if let newValue {
                applyFocus(newValue)
            }
        }
        .onChange(of: filter) { _, _ in
            if let selectedPinID, !filteredPins.contains(where: { $0.id == selectedPinID }) {
                self.selectedPinID = nil
            }
        }
        .fullScreenCover(item: $viewerRoute, onDismiss: {
            if let pendingDate = pendingDetailDateAfterViewer {
                pendingDetailDateAfterViewer = nil
                detailRoute = MapDayRoute(date: pendingDate)
            }
        }) { route in
            DayPhotoViewerSheet(
                dayKey: route.dayKey,
                initialPhotoID: route.initialPhotoID,
                scopedPhotoIDs: route.scopedPhotoIDs,
                headerTitle: route.headerTitle,
                onOpenDayDetail: { dayKey in
                    pendingDetailDateAfterViewer = parsedDate(fromDayKey: dayKey)
                }
            )
        }
        .fullScreenCover(item: $detailRoute) { route in
            DayDetailSheet(date: route.date) { coord in
                focusCoordinate = coord
            }
        }
    }

    private var cardLayout: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("思い出マップ")
                        .font(FoamFont.bold(22, relativeTo: .title2))
                        .foregroundStyle(FoamTheme.ink)
                    Text("\(filteredPins.count)か所")
                        .font(FoamFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(FoamTheme.warmAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.84), in: Capsule())
                    Spacer(minLength: 0)
                }
                .padding(.trailing, 58)

                if !allPins.isEmpty {
                    filterChipsRow
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ZStack(alignment: .bottom) {
                mapSurface
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.92), lineWidth: 2)
                    }
                    .shadow(color: FoamTheme.ink.opacity(0.12), radius: 12, y: 4)

                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 8) {
                            if !filteredPins.isEmpty {
                                fitAllButton
                            }
                            fullScreenToggleButton
                        }
                    }
                    .padding(12)
                    Spacer()
                }

                if filteredPins.isEmpty {
                    emptyStateCard
                        .padding(14)
                } else if let pin = selectedPin {
                    selectedPinCard(pin: pin)
                        .padding(12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 104)
        }
    }

    private var fullScreenLayout: some View {
        ZStack(alignment: .bottom) {
            mapSurface
                .ignoresSafeArea()

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                            isFullScreen = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 12, weight: .bold))
                            Text("戻す")
                                .font(FoamFont.bold(13, relativeTo: .subheadline))
                        }
                        .foregroundStyle(FoamTheme.ink)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(Color.white.opacity(0.88), lineWidth: 1)
                        }
                        .shadow(color: FoamTheme.ink.opacity(0.12), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if !filteredPins.isEmpty {
                        fitAllButton
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                if !allPins.isEmpty {
                    filterChipsRow
                        .padding(.horizontal, 14)
                }

                Spacer()

                if filteredPins.isEmpty {
                    emptyStateCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                } else if let pin = selectedPin {
                    selectedPinCard(pin: pin)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var mapSurface: some View {
        Map(position: $cameraPosition) {
            ForEach(filteredPins) { pin in
                let coord = CLLocationCoordinate2D(
                    latitude: pin.coordinate.latitude,
                    longitude: pin.coordinate.longitude
                )
                let isSelected = pin.id == selectedPinID
                Annotation("", coordinate: coord, anchor: .bottom) {
                    Button {
                        handlePinTap(pin)
                    } label: {
                        pinView(pin: pin, isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pin.title)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onTapGesture {
            if selectedPinID != nil {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    selectedPinID = nil
                }
            }
        }
    }

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MemoryMapFilter.allCases) { item in
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

    private var fitAllButton: some View {
        Button {
            fitAllPins(animated: true)
        } label: {
            Image(systemName: "scope")
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(FoamTheme.ink)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.88), lineWidth: 1)
                }
                .shadow(color: FoamTheme.ink.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("すべての思い出を表示")
    }

    private var fullScreenToggleButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                isFullScreen = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11.5, weight: .bold))
                Text("全画面")
                    .font(FoamFont.bold(12, relativeTo: .caption))
            }
            .foregroundStyle(FoamTheme.ink)
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(0.88), lineWidth: 1)
            }
            .shadow(color: FoamTheme.ink.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func handlePinTap(_ pin: MemoryMapPin) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.72)) {
            selectedPinID = pin.id
            centerCamera(on: pin.coordinate, spanDelta: 0.025)
        }
    }

    private func openViewer(for pin: MemoryMapPin, initialPhotoID: UUID) {
        viewerRoute = MapMediaViewerRoute(
            dayKey: pin.dayKey,
            initialPhotoID: initialPhotoID,
            scopedPhotoIDs: pin.photoIDs,
            headerTitle: pin.title
        )
    }

    @ViewBuilder
    private func pinView(pin: MemoryMapPin, isSelected: Bool) -> some View {
        if let primaryPhotoID = pin.photoIDs.first {
            let mediaItem = model.mediaAttachment(id: primaryPhotoID)
            let hasVideo = pin.photoIDs.contains { model.mediaAttachment(id: $0)?.mediaKind == .video }
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image = mediaItem.flatMap({ model.dayMediaThumbnail(for: $0) }) ?? model.dayPhotoImage(id: primaryPhotoID) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            ZStack {
                                FoamTheme.cream
                                Image(systemName: hasVideo ? "video.fill" : "photo")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(FoamTheme.ink.opacity(0.7))
                            }
                        }
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(isSelected ? FoamTheme.warmAccent : Color.white, lineWidth: isSelected ? 3 : 2.5)
                    }
                    .shadow(color: FoamTheme.ink.opacity(0.24), radius: 5, y: 2)

                    if pin.photoIDs.count > 1 {
                        Text("\(pin.photoIDs.count)")
                            .font(FoamFont.bold(10.5, relativeTo: .caption2))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(FoamTheme.ink, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(Color.white, lineWidth: 1)
                            }
                            .offset(x: 4, y: -4)
                    } else if hasVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white, FoamTheme.ink)
                            .offset(x: 3, y: -3)
                    }
                }

                if pin.hasPlaceTags || pin.title != MemoryMapPinBuilder.formattedDayTitle(pin.dayKey) {
                    Text(pin.title)
                        .font(FoamFont.bold(10.5, relativeTo: .caption2))
                        .foregroundStyle(FoamTheme.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.92), in: Capsule())
                        .shadow(color: FoamTheme.ink.opacity(0.12), radius: 2, y: 1)
                }
            }
            .scaleEffect(isSelected ? 1.12 : 1.0)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FoamTheme.warmAccent)
                Text(pin.title)
                    .font(FoamFont.bold(12, relativeTo: .caption))
                    .foregroundStyle(FoamTheme.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(Color.white.opacity(0.95))
                    .overlay {
                        Capsule().strokeBorder(
                            isSelected ? FoamTheme.warmAccent : FoamTheme.ink.opacity(0.18),
                            lineWidth: isSelected ? 2 : 1
                        )
                    }
                    .shadow(color: FoamTheme.ink.opacity(0.18), radius: 5, y: 2)
            }
            .scaleEffect(isSelected ? 1.12 : 1.0)
        }
    }

    private func selectedPinCard(pin: MemoryMapPin) -> some View {
        let dayDate = parsedDate(fromDayKey: pin.dayKey)
        let localMemo = model.localMemoText(forDayKey: pin.dayKey).trimmingCharacters(in: .whitespacesAndNewlines)
        let partnerMemo = model.partnerMemoText(forDayKey: pin.dayKey)?.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                pinCardHeaderBadge(pin: pin)

                VStack(alignment: .leading, spacing: 3) {
                    Text(dayDate.formatted(.dateTime.year().month().day().locale(Locale(identifier: "ja_JP"))))
                        .font(FoamFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(FoamTheme.warmAccent)

                    Text(pin.title)
                        .font(FoamFont.bold(16, relativeTo: .headline))
                        .foregroundStyle(FoamTheme.ink)
                        .lineLimit(1)

                    if let subtitle = pin.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(FoamFont.regular(12, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.ink.opacity(0.65))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        selectedPinID = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FoamTheme.ink.opacity(0.55))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.7), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("閉じる")
            }

            if pin.hasPhotos {
                pinCardMediaStrip(pin: pin)
            }

            if !localMemo.isEmpty {
                HStack(spacing: 6) {
                    UserAvatarView(image: model.localAvatarImage, bubbleColor: model.localBubbleColor, size: 22)
                    Text(localMemo)
                        .font(FoamFont.regular(13, relativeTo: .footnote))
                        .foregroundStyle(FoamTheme.ink.opacity(0.84))
                        .lineLimit(2)
                }
            }
            if let partnerMemo, !partnerMemo.isEmpty {
                HStack(spacing: 6) {
                    UserAvatarView(
                        image: model.partnerAvatarImage,
                        bubbleColor: model.effectivePartnerBubbleColor ?? .sakuraPink,
                        size: 22
                    )
                    Text(partnerMemo)
                        .font(FoamFont.regular(13, relativeTo: .footnote))
                        .foregroundStyle(FoamTheme.ink.opacity(0.84))
                        .lineLimit(2)
                }
            }

            if pin.hasPhotos, let firstID = pin.photoIDs.first {
                HStack(spacing: 8) {
                    Button {
                        openViewer(for: pin, initialPhotoID: firstID)
                    } label: {
                        Label("写真を見る（\(pin.photoIDs.count)件）", systemImage: "photo.on.rectangle")
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FoamCardActionStyle(fullWidth: true))

                    Button {
                        detailRoute = MapDayRoute(date: dayDate)
                    } label: {
                        Text("この日の詳細")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FoamCardActionStyle(fullWidth: true))
                }
            } else {
                Button {
                    detailRoute = MapDayRoute(date: dayDate)
                } label: {
                    Text("この日の詳細を見る")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FoamCardActionStyle(fullWidth: true))
            }
        }
        .padding(14)
        .background {
            SoapBubbleSurface(
                cornerStyle: .roundedRect(24),
                prominence: .standard,
                isTogether: model.isTogetherNow,
                seed: 5.1,
                wobbleScale: 0.3,
                animated: false,
                milkyFillOpacity: 0.88
            )
        }
        .shadow(color: FoamTheme.ink.opacity(0.14), radius: 12, y: 4)
    }

    @ViewBuilder
    private func pinCardHeaderBadge(pin: MemoryMapPin) -> some View {
        if pin.hasPhotos, let firstID = pin.photoIDs.first {
            let mediaItem = model.mediaAttachment(id: firstID)
            let isVideo = mediaItem?.mediaKind == .video
            Button {
                openViewer(for: pin, initialPhotoID: firstID)
            } label: {
                ZStack {
                    if let image = mediaItem.flatMap({ model.dayMediaThumbnail(for: $0) }) ?? model.dayPhotoImage(id: firstID) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        FoamTheme.cream.opacity(0.85)
                        Image(systemName: isVideo ? "video.fill" : "photo")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(FoamTheme.warmAccent)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                }
                .overlay {
                    if isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.55), in: Circle())
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(pin.title)の写真を開く")
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FoamTheme.cream.opacity(0.85))
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(FoamTheme.warmAccent)
            }
            .frame(width: 56, height: 56)
        }
    }

    private func pinCardMediaStrip(pin: MemoryMapPin) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pin.photoIDs, id: \.self) { photoID in
                    let mediaItem = model.mediaAttachment(id: photoID)
                    let isVideo = mediaItem?.mediaKind == .video
                    Button {
                        openViewer(for: pin, initialPhotoID: photoID)
                    } label: {
                        ZStack {
                            if let image = mediaItem.flatMap({ model.dayMediaThumbnail(for: $0) }) ?? model.dayPhotoImage(id: photoID) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                ZStack {
                                    Color.white.opacity(0.7)
                                    Image(systemName: isVideo ? "video.fill" : "photo")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(FoamTheme.ink.opacity(0.6))
                                }
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.2)
                        }
                        .overlay(alignment: .bottomLeading) {
                            if isVideo {
                                HStack(spacing: 2) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 8, weight: .bold))
                                    if let sec = mediaItem?.durationSeconds {
                                        Text(formattedDuration(sec))
                                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.62), in: Capsule())
                                .padding(4)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isVideo ? "動画を開く" : "写真を開く")
                }
            }
        }
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var emptyStateCard: some View {
        VStack(spacing: 10) {
            if allPins.isEmpty {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(FoamTheme.warmAccent)
                Text("ふたりの思い出マップ")
                    .font(FoamFont.bold(17, relativeTo: .headline))
                    .foregroundStyle(FoamTheme.ink)
                Text("カレンダーの日別ページから写真・動画や場所タグを追加すると、思い出の場所がここに並びます。")
                    .font(FoamFont.regular(13.5, relativeTo: .footnote))
                    .foregroundStyle(FoamTheme.ink.opacity(0.74))
                    .multilineTextAlignment(.center)
                Button("カレンダーを開く", action: onOpenCalendar)
                    .buttonStyle(FoamCardActionStyle(fullWidth: false))
                    .padding(.top, 2)
            } else {
                Text("この条件に一致するスポットがありません")
                    .font(FoamFont.bold(15, relativeTo: .subheadline))
                    .foregroundStyle(FoamTheme.ink)
                Button("すべて表示") {
                    filter = .all
                }
                .buttonStyle(FoamCardActionStyle(fullWidth: false))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background {
            SoapBubbleSurface(
                cornerStyle: .roundedRect(24),
                prominence: .standard,
                isTogether: model.isTogetherNow,
                seed: 6.2,
                wobbleScale: 0.35,
                animated: false,
                milkyFillOpacity: 0.88
            )
        }
        .shadow(color: FoamTheme.ink.opacity(0.10), radius: 10, y: 3)
    }

    private func applyFocus(_ target: GeoCoordinate) {
        if let matched = allPins.min(by: {
            $0.coordinate.distanceMeters(to: target) < $1.coordinate.distanceMeters(to: target)
        }), matched.coordinate.distanceMeters(to: target) < 250 {
            if filter == .photos && !matched.hasPhotos || filter == .places && !matched.hasPlaceTags {
                filter = .all
            }
            selectedPinID = matched.id
            centerCamera(on: matched.coordinate, spanDelta: 0.015)
        } else {
            centerCamera(on: target, spanDelta: 0.015)
        }
        focusCoordinate = nil
    }

    private func centerCamera(on coordinate: GeoCoordinate, spanDelta: Double) {
        cameraPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
            )
        )
    }

    private func fitAllPins(animated: Bool) {
        let pins = filteredPins
        guard !pins.isEmpty else {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 36.2048, longitude: 138.2529),
                    span: MKCoordinateSpan(latitudeDelta: 12.0, longitudeDelta: 12.0)
                )
            )
            return
        }
        let lats = pins.map(\.coordinate.latitude)
        let lons = pins.map(\.coordinate.longitude)
        let minLat = lats.min()!
        let maxLat = lats.max()!
        let minLon = lons.min()!
        let maxLon = lons.max()!
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) * 0.5,
            longitude: (minLon + maxLon) * 0.5
        )
        let latDelta = max(0.03, (maxLat - minLat) * 1.45)
        let lonDelta = max(0.03, (maxLon - minLon) * 1.45)
        let target = MapCameraPosition.region(
            MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
            )
        )
        if animated && !reduceMotion {
            withAnimation(.easeInOut(duration: 0.35)) {
                cameraPosition = target
            }
        } else {
            cameraPosition = target
        }
    }

    private func parsedDate(fromDayKey dayKey: String) -> Date {
        let parts = dayKey.split(separator: "-")
        if parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) {
            return CalendarDateValue(year: y, month: m, day: d).toDate()
        }
        return .now
    }
}
