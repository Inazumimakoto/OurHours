import OurHoursCore
import SwiftUI
import UIKit

struct RootFoamView: View {
    let appModel: AppModel
    var onReplayLaunchAnimation: (() -> Void)? = nil
    #if DEBUG
    let activeDebugPreset: DebugPreviewPreset?
    let onSelectDebugPreset: ((DebugPreviewPreset?) -> Void)?
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = FoamTab.home
    @State private var burst: FoamBurstEvent?
    @State private var lastBurstTimestamp = Date.distantPast
    @State private var showSettings = false
    @State private var showPairing = false
    @State private var showBubbleCustomizer = false
    @State private var customizerInitialCategory: BubbleCustomizationCategory = .color
    @State private var showOnboardingReplay = false
    @State private var pendingOnboardingReplay = false
    @State private var month = Date.now
    @State private var pendingDayRoute: SelectedDayRoute?
    @State private var homeUnknownEndRoute: SelectedDayRoute?
    @State private var pendingMapFocusCoordinate: GeoCoordinate?
    @State private var isMapFullScreen = false
    @State private var isGalleryTabBarCollapsed = false

    #if DEBUG
    init(
        appModel: AppModel,
        activeDebugPreset: DebugPreviewPreset? = nil,
        onSelectDebugPreset: ((DebugPreviewPreset?) -> Void)? = nil,
        onReplayLaunchAnimation: (() -> Void)? = nil
    ) {
        self.appModel = appModel
        self.activeDebugPreset = activeDebugPreset
        self.onSelectDebugPreset = onSelectDebugPreset
        self.onReplayLaunchAnimation = onReplayLaunchAnimation
        switch ScreenshotScene.current {
        case .calendar, .dayDetail:
            _tab = State(initialValue: .calendar)
            _month = State(initialValue: ScreenshotDemo.demoMonthDate)
            if ScreenshotScene.current == .dayDetail {
                _pendingDayRoute = State(initialValue: SelectedDayRoute(
                    date: ScreenshotDemo.demoDayDate, startAdding: false, focusEncounterID: nil
                ))
            }
        case .gallery:
            _tab = State(initialValue: .gallery)
        case .map:
            _tab = State(initialValue: .map)
        case .customizer:
            _tab = State(initialValue: .home)
            _showBubbleCustomizer = State(initialValue: true)
            _customizerInitialCategory = State(initialValue: .makeup)
        case .settings: _showSettings = State(initialValue: true)
        case .pairing: _showPairing = State(initialValue: true)
        case .home, nil: break
        }
    }
    #endif

    var body: some View {
        Group {
            if appModel.hasCompletedOnboarding {
                mainContent
            } else {
                OnboardingView()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: appModel.hasCompletedOnboarding)
        .font(FoamFont.medium(16))
        .foregroundStyle(FoamTheme.ink)
        .fullScreenCover(isPresented: $showOnboardingReplay) { OnboardingView() }
        .environment(appModel)
    }

    private var mainContent: some View {
        let isTabBarHidden = (tab == .gallery && isGalleryTabBarCollapsed)

        return ZStack {
            FoamTheme.sky(together: false).ignoresSafeArea()
            FoamTheme.sky(together: true).ignoresSafeArea().opacity(appModel.isTogetherNow ? 1 : 0)
                .animation(.easeInOut(duration: 1), value: appModel.isTogetherNow)
            FoamAmbientBackgroundView(
                isTogether: appModel.isTogetherNow,
                softened: tab == .calendar || tab == .gallery
            ).ignoresSafeArea()
            FoamTapObserverView(excludedBottomHeight: isTabBarHidden ? 24 : 112) { normalizedPoint in
                emitScreenPuff(at: normalizedPoint)
            }
            .ignoresSafeArea()
            Group {
                switch tab {
                case .home:
                    HomeView(
                        onPair: { showPairing = true },
                        onBurst: {
                            // Finger taps are handled at exact coordinates by FoamTapObserverView.
                            if UIAccessibility.isVoiceOverRunning {
                                emitScreenPuff(at: CGPoint(x: 0.5, y: 0.48))
                            }
                        },
                        onOpenUnknownEnd: { encounter in
                            homeUnknownEndRoute = SelectedDayRoute(
                                date: encounter.startedAt,
                                startAdding: false,
                                focusEncounterID: encounter.id
                            )
                        }
                    )
                    .padding(.bottom, 96)
                case .calendar:
                    CalendarView(
                        displayedMonth: $month,
                        pendingRoute: $pendingDayRoute,
                        onFocusMapCoordinate: { coord in
                            pendingMapFocusCoordinate = coord
                            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.76)) {
                                tab = .map
                            }
                        }
                    )
                    .padding(.bottom, 96)
                case .gallery:
                    MemoriesGalleryView(
                        isTabBarCollapsed: $isGalleryTabBarCollapsed,
                        onFocusMapCoordinate: { coord in
                            pendingMapFocusCoordinate = coord
                            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.76)) {
                                tab = .map
                            }
                        },
                        onOpenDayDate: { date in
                            month = date
                            pendingDayRoute = SelectedDayRoute(
                                date: date,
                                startAdding: false,
                                focusEncounterID: nil
                            )
                            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.76)) {
                                tab = .calendar
                            }
                        }
                    )
                case .map:
                    MemoriesMapView(
                        focusCoordinate: $pendingMapFocusCoordinate,
                        isFullScreen: $isMapFullScreen,
                        onOpenCalendar: {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.76)) {
                                tab = .calendar
                            }
                        }
                    )
                }
            }
            if !(tab == .map && isMapFullScreen) {
                FoamChromeOverlay(
                    isTogether: appModel.isTogetherNow,
                    showsCustomizerButton: tab == .home,
                    hasUnseenUnlocks: !appModel.unseenUnlockedItemIDs.isEmpty,
                    onOpenCustomizer: {
                        customizerInitialCategory = .color
                        showBubbleCustomizer = true
                    },
                    onOpenSettings: { showSettings = true }
                )
                    .transition(.move(edge: .top).combined(with: .opacity))
                VStack {
                    Spacer()
                    FoamTabBar(selected: $tab, isTogether: appModel.isTogetherNow, onBurst: emitTabSplash)
                        .background {
                            if tab == .gallery {
                                galleryTabBarFadeBackdrop
                                    .padding(.top, -46)
                                    .ignoresSafeArea(edges: .bottom)
                            }
                        }
                }
                .offset(y: isTabBarHidden ? 172 : 0)
                .opacity(isTabBarHidden ? 0 : 1)
                .allowsHitTesting(!isTabBarHidden)
                .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84), value: isTabBarHidden)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            VStack {
                if let banner = appModel.activeUnlockBanner {
                    BubbleUnlockToastBanner(
                        banner: banner,
                        isTogether: appModel.isTogetherNow,
                        onOpenCustomizer: { category in
                            customizerInitialCategory = category
                            showBubbleCustomizer = true
                        },
                        onDismiss: {
                            appModel.dismissUnlockBanner()
                        }
                    )
                    .padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82), value: appModel.activeUnlockBanner?.id)
            FoamTapBurstsOverlayView(burstEvent: burst).ignoresSafeArea()
            #if DEBUG
            if ScreenshotScene.current == nil, let activeDebugPreset {
                VStack {
                    HStack(spacing: 8) {
                        Text("DEV: \(activeDebugPreset.shortBadgeTitle)")
                            .font(FoamFont.bold(12, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.ink)
                        Button("戻す") {
                            onSelectDebugPreset?(nil)
                        }
                        .font(FoamFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(FoamTheme.ink.opacity(0.85), in: Capsule())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
                    }
                    .shadow(color: FoamTheme.ink.opacity(0.12), radius: 6, y: 2)
                    .padding(.top, 6)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            #endif
        }
        .sheet(isPresented: $showSettings, onDismiss: replayOnboardingIfPending) {
            NavigationStack {
                #if DEBUG
                SettingsView(
                    onReplayOnboarding: {
                        pendingOnboardingReplay = true
                        showSettings = false
                    },
                    activeDebugPreset: activeDebugPreset,
                    onSelectDebugPreset: onSelectDebugPreset,
                    onReplayLaunchAnimation: onReplayLaunchAnimation
                )
                #else
                SettingsView(onReplayOnboarding: {
                    pendingOnboardingReplay = true
                    showSettings = false
                })
                #endif
            }
            .font(FoamFont.medium(16))
        }
        .sheet(isPresented: $showPairing) { PairingView() }
        .sheet(isPresented: $showBubbleCustomizer) {
            BubbleCustomizerView(initialCategory: customizerInitialCategory)
                .environment(appModel)
        }
        .fullScreenCover(item: $homeUnknownEndRoute) { route in
            DayDetailSheet(
                date: route.date,
                startAdding: route.startAdding,
                focusEncounterID: route.focusEncounterID,
                backAccessibilityLabel: "ホームに戻る",
                onFocusMapCoordinate: { coord in
                    pendingMapFocusCoordinate = coord
                    withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.76)) {
                        tab = .map
                    }
                }
            )
        }
        .onChange(of: tab) { _, newTab in
            if newTab != .map && isMapFullScreen {
                isMapFullScreen = false
            }
            if newTab != .gallery && isGalleryTabBarCollapsed {
                isGalleryTabBarCollapsed = false
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isMapFullScreen)
    }

    private var galleryTabBarFadeBackdrop: some View {
        let fadeColors = appModel.isTogetherNow
            ? [
                Color(red: 0.996, green: 0.902, blue: 0.847).opacity(0),
                Color(red: 0.988, green: 0.910, blue: 0.847).opacity(0.62),
                Color(red: 0.980, green: 0.910, blue: 0.898).opacity(0.92),
                Color(red: 0.973, green: 0.910, blue: 0.949).opacity(0.98)
            ]
            : [
                Color(red: 0.768, green: 0.820, blue: 0.990).opacity(0),
                Color(red: 0.808, green: 0.843, blue: 0.980).opacity(0.62),
                Color(red: 0.842, green: 0.845, blue: 0.980).opacity(0.92),
                Color(red: 0.875, green: 0.847, blue: 0.980).opacity(0.98)
            ]

        return ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black.opacity(0.68), location: 0.32),
                            .init(color: .black, location: 0.56),
                            .init(color: .black, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            LinearGradient(
                stops: [
                    .init(color: fadeColors[0], location: 0.0),
                    .init(color: fadeColors[1].opacity(0.78), location: 0.34),
                    .init(color: fadeColors[2].opacity(0.96), location: 0.58),
                    .init(color: fadeColors[3].opacity(1.0), location: 0.74),
                    .init(color: fadeColors[3].opacity(1.0), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func replayOnboardingIfPending() {
        guard pendingOnboardingReplay else { return }
        pendingOnboardingReplay = false
        showOnboardingReplay = true
    }

    private func emitTabSplash(_ originX: CGFloat) {
        lastBurstTimestamp = .now
        burst = FoamBurstEvent.tabSplash(originNormalizedX: originX)
    }

    private func emitScreenPuff(at normalizedPoint: CGPoint) {
        let now = Date.now
        guard now.timeIntervalSince(lastBurstTimestamp) > 0.08 else { return }
        lastBurstTimestamp = now
        burst = FoamBurstEvent.screenPuff(originNormalized: normalizedPoint)
    }
}
