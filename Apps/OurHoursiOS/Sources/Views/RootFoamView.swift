import SwiftUI
import UIKit

struct RootFoamView: View {
    let appModel: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = FoamTab.home
    @State private var burst: FoamBurstEvent?
    @State private var lastBurstTimestamp = Date.distantPast
    @State private var showSettings = false
    @State private var showPairing = false
    @State private var showOnboardingReplay = false
    @State private var pendingOnboardingReplay = false
    @State private var month = Date.now
    @State private var pendingDayRoute: SelectedDayRoute?

    #if DEBUG
    init(appModel: AppModel) {
        self.appModel = appModel
        switch ScreenshotScene.current {
        case .calendar, .dayDetail:
            _tab = State(initialValue: .calendar)
            _month = State(initialValue: ScreenshotDemo.demoMonthDate)
            if ScreenshotScene.current == .dayDetail {
                _pendingDayRoute = State(initialValue: SelectedDayRoute(
                    date: ScreenshotDemo.demoDayDate, startAdding: false, focusEncounterID: nil
                ))
            }
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
        ZStack {
            FoamTheme.sky(together: false).ignoresSafeArea()
            FoamTheme.sky(together: true).ignoresSafeArea().opacity(appModel.isTogetherNow ? 1 : 0)
                .animation(.easeInOut(duration: 1), value: appModel.isTogetherNow)
            FoamAmbientBackgroundView(
                isTogether: appModel.isTogetherNow,
                softened: tab == .calendar
            ).ignoresSafeArea()
            FoamTapObserverView(excludedBottomHeight: 112) { normalizedPoint in
                emitScreenPuff(at: normalizedPoint)
            }
            .ignoresSafeArea()
            Group {
                if tab == .home {
                    HomeView(
                        onPair: { showPairing = true },
                        onBurst: {
                            // Finger taps are handled at exact coordinates by FoamTapObserverView.
                            if UIAccessibility.isVoiceOverRunning {
                                emitScreenPuff(at: CGPoint(x: 0.5, y: 0.48))
                            }
                        },
                        onOpenUnknownEnd: { encounter in
                            month = encounter.startedAt
                            pendingDayRoute = SelectedDayRoute(
                                date: encounter.startedAt,
                                startAdding: false,
                                focusEncounterID: encounter.id
                            )
                            tab = .calendar
                        }
                    )
                } else {
                    CalendarView(displayedMonth: $month, pendingRoute: $pendingDayRoute)
                }
            }.padding(.bottom, 96)
            FoamChromeOverlay(isTogether: appModel.isTogetherNow) { showSettings = true }
            VStack {
                Spacer()
                FoamTabBar(selected: $tab, isTogether: appModel.isTogetherNow, onBurst: emitTabSplash)
            }
            FoamTapBurstsOverlayView(burstEvent: burst).ignoresSafeArea()
        }
        .sheet(isPresented: $showSettings, onDismiss: replayOnboardingIfPending) {
            NavigationStack {
                SettingsView(onReplayOnboarding: {
                    pendingOnboardingReplay = true
                    showSettings = false
                })
            }
            .font(FoamFont.medium(16))
        }
        .sheet(isPresented: $showPairing) { PairingView() }
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
