import SwiftUI

enum FoamTab: CaseIterable { case home, calendar, gallery, map }

struct FoamTabBar: View {
    @Binding var selected: FoamTab
    let isTogether: Bool
    let onBurst: (CGFloat) -> Void

    @State private var pressDateByTab: [FoamTab: Date] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FoamTab.allCases, id: \.self) { tab in
                let active = selected == tab
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    pressDateByTab[tab] = .now
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) { selected = tab }
                    onBurst(burstOrigin(for: tab))
                } label: {
                    VStack(spacing: 1) {
                        tabIcon(for: tab, active: active)
                            .scaleEffect(0.84)
                        Text(tabTitle(for: tab))
                            .font(FoamFont.bold(10.5, relativeTo: .caption2))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(active ? FoamTheme.ink.opacity(0.90) : FoamTheme.ink.opacity(0.54))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .frame(minWidth: 64, minHeight: 48)
                    .scaleEffect(active ? 0.95 : 1.0)
                    .offset(y: active ? 1.5 : 0)
                    .background {
                        OrganicFoamPressedHollow(
                            active: active,
                            isTogether: isTogether,
                            seed: tabSeed(for: tab),
                            pressDate: pressDateByTab[tab] ?? .distantPast
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .offset(x: 0, y: 0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FoamTabSquishButtonStyle())
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func tabIcon(for tab: FoamTab, active: Bool) -> some View {
        switch tab {
        case .home: FoamHomeIcon(active: active)
        case .calendar: FoamCalendarIcon(active: active)
        case .gallery: FoamGalleryIcon(active: active)
        case .map: FoamMapIcon(active: active)
        }
    }

    private func tabTitle(for tab: FoamTab) -> String {
        switch tab {
        case .home: "ホーム"
        case .calendar: "カレンダー"
        case .gallery: "アルバム"
        case .map: "マップ"
        }
    }

    private func burstOrigin(for tab: FoamTab) -> CGFloat {
        switch tab {
        case .home: 0.14
        case .calendar: 0.38
        case .gallery: 0.62
        case .map: 0.86
        }
    }

    private func tabSeed(for tab: FoamTab) -> Double {
        switch tab {
        case .home: 0.0
        case .calendar: 1.7
        case .gallery: 2.6
        case .map: 3.4
        }
    }
}

/// Wobbling translucent Style A soap-bubble capsule well backed by the unified bubble renderer.
private struct OrganicFoamPressedHollow: View {
    let active: Bool
    let isTogether: Bool
    let seed: Double
    let pressDate: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !active)) { timeline in
            let metrics = animationMetrics(at: timeline.date)
            SoapBubbleSurface(
                cornerStyle: .capsule,
                prominence: .vivid,
                isTogether: isTogether,
                seed: seed,
                wobbleScale: metrics.ampScale,
                externalPhase: metrics.phase,
                squish: metrics.squish
            )
        }
        .animation(.easeInOut(duration: 0.8), value: isTogether)
        .opacity(active ? 1 : 0)
        .scaleEffect(active ? 1 : 0.86)
        .animation(.spring(response: 0.34, dampingFraction: 0.76), value: active)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func animationMetrics(at date: Date) -> (phase: Double, ampScale: Double, squish: Double) {
        guard !reduceMotion else { return (0, 1.0, 0) }
        let t = date.timeIntervalSinceReferenceDate
        let elapsed = max(0, date.timeIntervalSince(pressDate))
        let impulse = exp(-elapsed * 2.1)
        let phase = t * 1.55 + (1.0 - impulse) * 1.6
        let ampScale = 1.25 + impulse * 1.15
        let squish = sin(elapsed * 13.0) * impulse * 0.032
        return (phase, ampScale, squish)
    }
}

private struct FoamTabSquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .offset(y: configuration.isPressed ? 1.5 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
