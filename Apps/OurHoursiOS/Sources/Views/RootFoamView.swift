import SwiftUI
import UIKit

struct RootFoamView: View {
    let appModel: AppModel
    @State private var tab = FoamTab.home
    @State private var burst: FoamBurstEvent?
    @State private var lastBurstTimestamp = Date.distantPast
    @State private var showSettings = false
    @State private var showPairing = false
    @State private var month = Date.now
    @State private var pendingDayRoute: SelectedDayRoute?

    var body: some View {
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
        .font(FoamFont.medium(16))
        .foregroundStyle(FoamTheme.ink)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
            .font(FoamFont.medium(16))
        }
        .sheet(isPresented: $showPairing) { PairingView() }
        .environment(appModel)
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
