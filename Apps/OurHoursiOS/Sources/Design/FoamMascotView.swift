import OurHoursCore
import SwiftUI
import UIKit

struct FoamMascotView: View {
    let isTogether: Bool
    var isPaired: Bool = true
    var localColor: BubbleColorTheme = .skyBlue
    var partnerColor: BubbleColorTheme? = nil
    let onTapBurst: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [FoamTheme.cream, .clear], center: .center, startRadius: 18, endRadius: 122))
                .frame(width: 244, height: 244)
                .opacity((isPaired && isTogether) ? 0.85 : 0)
                .frame(width: 175, height: 175)
                .accessibilityHidden(true)
            if isPaired {
                ForEach(0..<2) { index in
                    let side: CGFloat = index == 0 ? -1 : 1
                    FoamCharacter(index: index, color: index == 0 ? localColor : partnerColor, onTap: onTapBurst)
                        .rotationEffect(.degrees(side * (isTogether ? 9 : -7)))
                        .offset(x: side * (isTogether ? 32 : 56), y: side * (isTogether ? 9 : 40))
                }
            } else {
                FoamCharacter(index: 0, color: localColor, onTap: onTapBurst)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.85, dampingFraction: 0.72), value: isTogether)
        .animation(reduceMotion ? nil : .spring(response: 0.85, dampingFraction: 0.72), value: isPaired)
    }
}

private struct FoamCharacter: View {
    let index: Int
    let color: BubbleColorTheme?
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = 0

    private var accessibilityLabel: String {
        let base = index == 0 ? "あなたのシャボン玉" : "相手のシャボン玉"
        guard let color else { return base }
        return "\(base)、\(color.displayName)"
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if !reduceMotion { bounce += 1 }
            onTap()
        } label: {
            MascotBubbleAvatar(color: color, index: index)
        }
        .buttonStyle(.plain)
        .keyframeAnimator(initialValue: CGFloat(1), trigger: bounce) { content, scale in
            content.scaleEffect(x: 2 - scale, y: scale)
        } keyframes: { _ in
            SpringKeyframe(0.86, duration: 0.12)
            SpringKeyframe(1, duration: 0.45, spring: .bouncy)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("タップするとシャボン玉がはじけます")
    }
}

struct MascotBubbleAvatar: View {
    var color: BubbleColorTheme? = .skyBlue
    var size: CGFloat = 128
    var animated = true
    var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let floats = animated && !reduceMotion
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !floats)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let wave = floats ? sin(time * (index == 0 ? 1.15 : 0.98) + Double(index)) : 0
            let blink = floats && (time + Double(index)).truncatingRemainder(dividingBy: 4.7) < 0.13

            ZStack {
                if let color {
                    Circle()
                        .fill(RadialGradient(
                            colors: [color.glowColor.opacity(0.16), color.tintColor.opacity(0.50), color.deepTintColor.opacity(0.34)],
                            center: .topLeading, startRadius: 0, endRadius: size * 0.84
                        ))
                        .overlay {
                            Circle().strokeBorder(
                                LinearGradient(
                                    colors: [color.glowColor.opacity(0.74), .clear, color.deepTintColor.opacity(0.46)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ), lineWidth: size * 0.027
                            )
                        }
                        .padding(size * 0.09)
                }
                Image("BubbleMascot").resizable().scaledToFit()
                face(blink: blink)
            }
            .frame(width: size, height: size)
            .scaleEffect(x: 1 - wave * 0.014, y: 1 + wave * 0.018)
            .offset(y: wave * (index == 0 ? 8 : 11))
        }
        .accessibilityHidden(true)
    }

    private func face(blink: Bool) -> some View {
        Canvas { context, canvasSize in
            var face = context
            face.scaleBy(x: canvasSize.width / 128, y: canvasSize.height / 128)
            for x in [37.0, 91.0] {
                let blush = Path(ellipseIn: CGRect(x: x - 12, y: 64, width: 24, height: 15))
                face.fill(
                    blush,
                    with: .radialGradient(
                        Gradient(colors: [.pink.opacity(0.28), .clear]),
                        center: CGPoint(x: x, y: 71), startRadius: 0, endRadius: 12
                    )
                )
            }
            let eyeDepth = blink ? 2.0 : 8.0
            for (x, y, depth) in [(46.0, 59.0, eyeDepth), (81, 59, eyeDepth), (63, 69, 7)] {
                var arc = Path()
                arc.move(to: CGPoint(x: x - 6, y: y))
                arc.addQuadCurve(to: CGPoint(x: x + 6, y: y), control: CGPoint(x: x, y: y + depth))
                face.stroke(arc, with: .color(FoamTheme.ink), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
            }
        }
    }
}
