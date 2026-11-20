import SwiftUI

struct RootFoamView: View {
    let appModel: AppModel
    @State private var tab = FoamTab.home
    @State private var burst: FoamBurstEvent?
    @State private var showSettings = false
    @State private var showPairing = false
    @State private var month = Date.now

    var body: some View {
        ZStack {
            FoamTheme.sky(together: false).ignoresSafeArea()
            FoamTheme.sky(together: true).ignoresSafeArea().opacity(appModel.isTogetherNow ? 1 : 0)
                .animation(.easeInOut(duration: 1), value: appModel.isTogetherNow)
            RisingFoamParticlesView(isTogether: appModel.isTogetherNow, burstEvent: burst).ignoresSafeArea()
            Group {
                if tab == .home {
                    HomeView(onPair: { showPairing = true }, onBurst: { emit(0.5) }, onCalendar: { date in
                        month = date
                        tab = .calendar
                    })
                } else {
                    CalendarView(displayedMonth: $month)
                }
            }.padding(.bottom, 88)
            FoamChromeOverlay { showSettings = true }
            VStack {
                Spacer()
                FoamTabBar(selected: $tab, onBurst: emit)
            }
        }
        .fontDesign(.rounded).foregroundStyle(FoamTheme.ink)
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView().toolbar { Button("閉じる") { showSettings = false } } }
        }
        .sheet(isPresented: $showPairing) { PairingView() }
        .environment(appModel)
    }

    private func emit(_ origin: CGFloat) {
        burst = FoamBurstEvent(originNormalizedX: origin, count: Int.random(in: 6...9))
    }
}
