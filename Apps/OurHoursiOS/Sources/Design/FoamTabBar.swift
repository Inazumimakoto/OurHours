import SwiftUI

enum FoamTab: CaseIterable { case home, calendar }

struct FoamTabBar: View {
    @Binding var selected: FoamTab
    let isTogether: Bool
    let onBurst: (CGFloat) -> Void

    @State private var pressDateByTab: [FoamTab: Date] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FoamTab.allCases, id: \.self) { tab in
                let home = tab == .home
                let active = selected == tab
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    pressDateByTab[tab] = .now
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) { selected = tab }
                    onBurst(home ? 0.28 : 0.72)
                } label: {
                    VStack(spacing: 1) {
                        Group {
                            if home {
                                FoamHomeIcon(active: active)
                            } else {
                                FoamCalendarIcon(active: active)
                            }
                        }
                        .scaleEffect(0.84)
                        Text(home ? "ホーム" : "カレンダー")
                            .font(FoamFont.bold(10.5, relativeTo: .caption2))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(active ? FoamTheme.ink.opacity(0.90) : FoamTheme.ink.opacity(0.54))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .frame(minWidth: 92, minHeight: 48)
                    .scaleEffect(active ? 0.95 : 1.0)
                    .offset(y: active ? 1.5 : 0)
                    .background {
                        OrganicFoamPressedHollow(
                            active: active,
                            isTogether: isTogether,
                            seed: home ? 0.0 : 1.7,
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
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
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
