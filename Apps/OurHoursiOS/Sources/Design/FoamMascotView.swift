import OurHoursCore
import SwiftUI
import UIKit

struct FoamMascotView: View {
    let isTogether: Bool
    var isPaired: Bool = true
    var localColor: BubbleColorTheme = .skyBlue
    var partnerColor: BubbleColorTheme? = nil
    var activeSessionStartDate: Date? = nil
    let onTapBurst: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isTogether, let startDate = activeSessionStartDate {
            TimelineView(.periodic(from: .now, by: 5)) { tick in
                mascotStack(growth: Self.growthScale(isTogether: true, startDate: startDate, now: tick.date))
            }
        } else {
            mascotStack(growth: 1.0)
        }
    }

    private static func growthScale(isTogether: Bool, startDate: Date?, now: Date) -> CGFloat {
        guard isTogether, let startDate else { return 1.0 }
        let elapsed = max(0, now.timeIntervalSince(startDate))
        // Smoothly expands up to ~1.24x over hours spent together.
        return 1.0 + 0.24 * CGFloat(1.0 - exp(-elapsed / 5_400.0))
    }

    @ViewBuilder
    private func mascotStack(growth: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [FoamTheme.cream, .clear], center: .center, startRadius: 18, endRadius: 122))
                .frame(width: 244 * growth, height: 244 * growth)
                .opacity((isPaired && isTogether) ? 0.85 : 0)
                .frame(width: 175 * growth, height: 175 * growth)
                .accessibilityHidden(true)
            if isPaired {
                ForEach(0..<2) { index in
                    let side: CGFloat = index == 0 ? -1 : 1
                    FoamCharacter(
                        index: index,
                        color: index == 0 ? localColor : partnerColor,
                        size: 128 * growth,
                        isTogether: isTogether,
                        onTap: onTapBurst
                    )
                    .rotationEffect(.degrees(side * (isTogether ? 9 : -7)))
                    .offset(
                        x: side * (isTogether ? 32 * growth : 56),
                        y: side * (isTogether ? 9 * growth : 40)
                    )
                }
            } else {
                FoamCharacter(
                    index: 0,
                    color: localColor,
                    size: 128 * growth,
                    isTogether: isTogether,
                    onTap: onTapBurst
                )
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.85, dampingFraction: 0.72), value: isTogether)
        .animation(reduceMotion ? nil : .spring(response: 0.85, dampingFraction: 0.72), value: isPaired)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: growth)
    }
}

private struct FoamCharacter: View {
    let index: Int
    let color: BubbleColorTheme?
    let size: CGFloat
    let isTogether: Bool
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = 0
    @State private var tapHighlightUntil = Date.distantPast

    private var accessibilityLabel: String {
        let base = index == 0 ? "あなたのシャボン玉" : "相手のシャボン玉"
        guard let color else { return base }
        return "\(base)、\(color.displayName)"
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if !reduceMotion {
                bounce += 1
                tapHighlightUntil = Date.now.addingTimeInterval(0.95)
            }
            onTap()
        } label: {
            MascotBubbleAvatar(
                color: color,
                size: size,
                index: index,
                isTogether: isTogether,
                tapHighlightUntil: tapHighlightUntil
            )
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

private enum MascotEyeExpression {
    case open
    case happy
    case closed
}

struct MascotBubbleAvatar: View {
    var color: BubbleColorTheme? = .skyBlue
    var size: CGFloat = 128
    var animated = true
    var index = 0
    var isTogether = true
    var tapHighlightUntil: Date = .distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let floats = animated && !reduceMotion
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !floats)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let wave = floats ? sin(time * (index == 0 ? 1.15 : 0.98) + Double(index)) : 0
            let expression = eyeExpression(at: time, timelineDate: timeline.date, floats: floats)

            ZStack {
                if let color, color != .clear {
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
                face(expression: expression)
            }
            .frame(width: size, height: size)
            .scaleEffect(x: 1 - wave * 0.014, y: 1 + wave * 0.018)
            .offset(y: wave * (index == 0 ? 8 : 11))
        }
        .accessibilityHidden(true)
    }

    private func eyeExpression(at time: TimeInterval, timelineDate: Date, floats: Bool) -> MascotEyeExpression {
        if !floats {
            if timelineDate < tapHighlightUntil { return isTogether ? .happy : .open }
            return isTogether ? .open : .closed
        }
        if timelineDate < tapHighlightUntil {
            return isTogether ? .happy : .open
        }
        if isTogether {
            let happyCycle = (time + Double(index) * 1.7).truncatingRemainder(dividingBy: 9.5)
            if happyCycle < 1.35 { return .happy }
            let blinkCycle = (time + Double(index) * 1.3).truncatingRemainder(dividingBy: 4.3)
            if blinkCycle < 0.14 { return .closed }
            return .open
        } else {
            let peekCycle = (time + Double(index) * 2.1).truncatingRemainder(dividingBy: 9.2)
            if peekCycle < 2.6 {
                if peekCycle >= 1.25 && peekCycle < 1.39 { return .closed }
                return .open
            }
            return .closed
        }
    }

    private func face(expression: MascotEyeExpression) -> some View {
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
            for x in [46.0, 81.0] {
                switch expression {
                case .open:
                    let eye = Path(roundedRect: CGRect(x: x - 4.4, y: 53.5, width: 8.8, height: 11.2), cornerSize: CGSize(width: 4.4, height: 4.4))
                    face.fill(eye, with: .color(FoamTheme.ink))
                    let primaryCatchlight = Path(ellipseIn: CGRect(x: x - 2.3, y: 55.3, width: 3.2, height: 3.2))
                    face.fill(primaryCatchlight, with: .color(.white.opacity(0.95)))
                    let secondaryCatchlight = Path(ellipseIn: CGRect(x: x + 0.6, y: 60.0, width: 1.7, height: 1.7))
                    face.fill(secondaryCatchlight, with: .color(.white.opacity(0.85)))
                case .happy:
                    var arc = Path()
                    arc.move(to: CGPoint(x: x - 6, y: 61))
                    arc.addQuadCurve(to: CGPoint(x: x + 6, y: 61), control: CGPoint(x: x, y: 53))
                    face.stroke(arc, with: .color(FoamTheme.ink), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                case .closed:
                    var arc = Path()
                    arc.move(to: CGPoint(x: x - 6, y: 59))
                    arc.addQuadCurve(to: CGPoint(x: x + 6, y: 59), control: CGPoint(x: x, y: 66))
                    face.stroke(arc, with: .color(FoamTheme.ink), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                }
            }
            var mouth = Path()
            mouth.move(to: CGPoint(x: 57, y: 69))
            mouth.addQuadCurve(to: CGPoint(x: 69, y: 69), control: CGPoint(x: 63, y: 76))
            face.stroke(mouth, with: .color(FoamTheme.ink), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
        }
    }
}
