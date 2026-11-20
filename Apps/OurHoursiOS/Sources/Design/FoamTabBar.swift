import SwiftUI

enum FoamTab: CaseIterable { case home, calendar }

struct FoamTabBar: View {
    @Binding var selected: FoamTab
    let onBurst: (CGFloat) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FoamTab.allCases, id: \.self) { tab in
                let home = tab == .home
                let active = selected == tab
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(duration: 0.4)) { selected = tab }
                    onBurst(home ? 0.28 : 0.72)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: home ? "house" : "calendar").font(.title2.weight(.semibold))
                            .foregroundStyle(active ? Color(red: 0.58, green: 0.35, blue: 0.1) : FoamTheme.ink)
                        Text(home ? "ホーム" : "カレンダー").font(.caption.bold())
                    }
                    .background { Circle().fill(FoamTheme.cream).blur(radius: 9).scaleEffect(1.45).opacity(active ? 1 : 0) }
                    .scaleEffect(active ? 1.06 : 1)
                    .frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
                }
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .buttonStyle(.plain).padding(.horizontal, 18)
        .background(alignment: .bottom) {
            GeometryReader { geometry in
                Image("FoamTabBarBase").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height + 36, alignment: .bottom)
                    .offset(y: -36).allowsHitTesting(false)
            }.ignoresSafeArea(edges: .bottom)
        }
    }
}
