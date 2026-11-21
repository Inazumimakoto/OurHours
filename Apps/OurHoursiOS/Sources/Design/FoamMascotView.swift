import SwiftUI

struct FoamMascotView: View {
    let isTogether: Bool
    var isPaired: Bool = true
    let onTapBurst: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(FoamTheme.cream).blur(radius: 24)
                .frame(width: 175, height: 175).opacity((isPaired && isTogether) ? 0.85 : 0)
            if isPaired {
                ForEach(0..<2) { index in
                    let side: CGFloat = index == 0 ? -1 : 1
                    FoamCharacter(index: index, reduceMotion: reduceMotion, onTap: onTapBurst)
                        .rotationEffect(.degrees(side * (isTogether ? 9 : -7)))
                        .offset(x: side * (isTogether ? 32 : 56), y: side * (isTogether ? 9 : 40))
                }
            } else {
                FoamCharacter(index: 0, reduceMotion: reduceMotion, onTap: onTapBurst)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.85, dampingFraction: 0.72), value: isTogether)
        .animation(reduceMotion ? nil : .spring(response: 0.85, dampingFraction: 0.72), value: isPaired)
    }
}

private struct FoamCharacter: View {
    let index: Int
    let reduceMotion: Bool
    let onTap: () -> Void
    @State private var bounce = 0

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            bounce += 1
            onTap()
        } label: {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let wave = sin(t * (index == 0 ? 1.15 : 0.98) + Double(index))
                let blink = (t + Double(index)).truncatingRemainder(dividingBy: 4.7) < 0.13
                ZStack {
                    Image("BubbleMascot").resizable().scaledToFit()
                    Canvas { context, _ in
                        for x in [37.0, 91.0] {
                            let blush = Path(ellipseIn: CGRect(x: x - 12, y: 64, width: 24, height: 15))
                            context.fill(blush, with: .radialGradient(Gradient(colors: [.pink.opacity(0.28), .clear]),
                                center: CGPoint(x: x, y: 71), startRadius: 0, endRadius: 12))
                        }
                        for (x, y, depth) in [(46.0, 59.0, blink ? 2.0 : 8.0), (81, 59, blink ? 2 : 8), (63, 69, 7)] {
                            var arc = Path()
                            arc.move(to: CGPoint(x: x - 6, y: y))
                            arc.addQuadCurve(to: CGPoint(x: x + 6, y: y), control: CGPoint(x: x, y: y + depth))
                            context.stroke(arc, with: .color(FoamTheme.ink), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                        }
                    }
                }
                .frame(width: 128, height: 128)
                .scaleEffect(x: 1 - wave * 0.014, y: 1 + wave * 0.018)
                .offset(y: wave * (index == 0 ? 8 : 11))
            }
        }
        .buttonStyle(.plain)
        .keyframeAnimator(initialValue: CGFloat(1), trigger: bounce) { content, scale in
            content.scaleEffect(x: reduceMotion ? 1 : 2 - scale, y: reduceMotion ? 1 : scale)
        } keyframes: { _ in
            SpringKeyframe(0.86, duration: 0.12)
            SpringKeyframe(1, duration: 0.45, spring: .bouncy)
        }
        .accessibilityLabel("シャボン玉のキャラクター").accessibilityHint("タップするとシャボン玉がはじけます")
    }
}
