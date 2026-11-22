import OurHoursCore
import SwiftUI
import UIKit

struct FoamMascotView: View {
    let isTogether: Bool
    var isPaired: Bool = true
    var localColor: BubbleColorTheme = .skyBlue
    var localExpression: BubbleExpression = .classic
    var localExpressionRotation: [BubbleExpression] = []
    var localDecorations: BubbleDecorationLoadout = .none
    var partnerColor: BubbleColorTheme? = nil
    var partnerExpression: BubbleExpression = .classic
    var partnerExpressionRotation: [BubbleExpression] = []
    var partnerDecorations: BubbleDecorationLoadout = .none
    var activeSessionStartDate: Date? = nil
    let onTapBurst: () -> Void
    var onSecretPop: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !isTogether || activeSessionStartDate == nil)) { tick in
            mascotStack(growth: Self.growthScale(isTogether: isTogether, startDate: activeSessionStartDate, now: tick.date))
        }
    }

    private static func growthScale(isTogether: Bool, startDate: Date?, now: Date) -> CGFloat {
        guard isTogether, let startDate else { return 1.0 }
        let elapsed = max(0, now.timeIntervalSince(startDate))
        // Unbounded continuous growth at +0.78x per 10 hours spent together (1.78x at 10h, growing infinitely).
        let progress = elapsed / 36_000.0
        return 1.0 + 0.78 * CGFloat(progress)
    }

    @ViewBuilder
    private func mascotStack(growth: CGFloat) -> some View {
        let progress = max(0, (growth - 1.0) / 0.78)
        let effectiveScale = isTogether ? growth : 1.0

        ZStack {
            Circle()
                .fill(RadialGradient(colors: [FoamTheme.cream, .clear], center: .center, startRadius: 18, endRadius: 122))
                .frame(width: 244, height: 244)
                .scaleEffect(effectiveScale)
                .opacity((isPaired && isTogether) ? 0.85 : 0)
                .frame(width: 175, height: 175)
                .accessibilityHidden(true)
            if isPaired {
                ForEach(0..<2) { index in
                    let side: CGFloat = index == 0 ? -1 : 1
                    FoamCharacter(
                        index: index,
                        color: index == 0 ? localColor : partnerColor,
                        expression: index == 0 ? localExpression : partnerExpression,
                        expressionRotationPool: index == 0 ? localExpressionRotation : partnerExpressionRotation,
                        decorations: index == 0 ? localDecorations : partnerDecorations,
                        size: 128,
                        isTogether: isTogether,
                        onTap: onTapBurst,
                        onSecretPop: onSecretPop
                    )
                    .scaleEffect(effectiveScale)
                    .rotationEffect(.degrees(side * (isTogether ? 9 : -7)))
                    .offset(
                        x: side * (isTogether ? (32 + 24 * progress) : 56),
                        y: side * (isTogether ? (9 + 6 * progress) : 40)
                    )
                }
            } else {
                FoamCharacter(
                    index: 0,
                    color: localColor,
                    expression: localExpression,
                    expressionRotationPool: localExpressionRotation,
                    decorations: localDecorations,
                    size: 128,
                    isTogether: isTogether,
                    onTap: onTapBurst,
                    onSecretPop: onSecretPop
                )
                .scaleEffect(effectiveScale)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.95, dampingFraction: 0.78), value: isTogether)
        .animation(reduceMotion ? nil : .spring(response: 0.85, dampingFraction: 0.72), value: isPaired)
        .animation(reduceMotion ? nil : .spring(response: 1.1, dampingFraction: 0.82), value: growth)
    }
}

private struct FoamCharacter: View {
    let index: Int
    let color: BubbleColorTheme?
    let expression: BubbleExpression
    let expressionRotationPool: [BubbleExpression]
    let decorations: BubbleDecorationLoadout
    let size: CGFloat
    let isTogether: Bool
    let onTap: () -> Void
    var onSecretPop: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = 0
    @State private var tapHighlightUntil = Date.distantPast
    @State private var recentTapDates: [Date] = []
    @State private var popStartDate: Date? = nil
    @State private var popCleanupTask: Task<Void, Never>? = nil

    private var accessibilityLabel: String {
        let base = index == 0 ? "あなたのシャボン玉" : "相手のシャボン玉"
        guard let color else { return base }
        return "\(base)、\(color.displayName)"
    }

    var body: some View {
        Button {
            handleTap()
        } label: {
            MascotBubbleAvatar(
                color: color,
                expression: expression,
                expressionRotationPool: expressionRotationPool,
                decorations: decorations,
                size: size,
                index: index,
                isTogether: isTogether,
                tapHighlightUntil: tapHighlightUntil,
                popStartDate: popStartDate
            )
            .keyframeAnimator(initialValue: CGFloat(1), trigger: bounce) { content, scale in
                content.scaleEffect(x: 2 - scale, y: scale)
            } keyframes: { _ in
                SpringKeyframe(0.86, duration: 0.12)
                SpringKeyframe(1, duration: 0.45, spring: .bouncy)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("タップするとシャボン玉がはじけます")
        .onDisappear {
            popCleanupTask?.cancel()
            popCleanupTask = nil
        }
    }

    private func handleTap() {
        let now = Date.now
        onTap()

        if popStartDate != nil {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            return
        }

        recentTapDates = recentTapDates.filter { now.timeIntervalSince($0) <= 1.0 }
        recentTapDates.append(now)

        if recentTapDates.count >= 5 {
            recentTapDates.removeAll()
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            popStartDate = now
            onSecretPop?()

            let duration: Duration = reduceMotion ? .milliseconds(1050) : .milliseconds(2980)
            popCleanupTask?.cancel()
            popCleanupTask = Task { @MainActor in
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                popStartDate = nil
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
            return
        }

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        if !reduceMotion {
            bounce += 1
            tapHighlightUntil = now.addingTimeInterval(0.95)
        }
    }
}

private struct PopAnimationFrame {
    let shellOpacity: Double
    let shellScale: Double
    let shellOffsetY: Double
    let decorationOpacity: Double
    let burstProgress: Double?
    let faceMode: MascotPopFaceMode?
    let faceScale: Double
    let faceOffsetX: Double
    let faceOffsetY: Double
    let miniBubbleCenterYNorm: Double?
    let miniBubbleRadiusNorm: Double?
}

struct MascotBubbleAvatar: View {
    var color: BubbleColorTheme? = .skyBlue
    var expression: BubbleExpression = .classic
    var expressionRotationPool: [BubbleExpression] = []
    var isFastPreviewRotation: Bool = false
    var decorations: BubbleDecorationLoadout = .none
    var size: CGFloat = 128
    var animated = true
    var index = 0
    var isTogether = true
    var tapHighlightUntil: Date = .distantPast
    var popStartDate: Date? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let totalPopDuration: TimeInterval = 2.95
    private static let homeRotationIntervals: [TimeInterval] = [5.2, 8.4, 4.6, 9.6, 6.8, 7.5, 5.0, 10.1]
    private static let previewRotationIntervals: [TimeInterval] = [1.8, 2.5, 2.1, 2.9]

    var body: some View {
        let isPopping = popStartDate != nil
        let floats = (animated && !reduceMotion) || isPopping
        let extendedSize = size * BubbleDecorationRenderer.canvasExtentMultiplier

        TimelineView(.animation(minimumInterval: 1 / 60, paused: !floats)) { timeline in
            let now = timeline.date
            let time = now.timeIntervalSinceReferenceDate
            let popFrame = popFrame(at: now)
            let isInActivePop = popFrame != nil
            let wave = (animated && !reduceMotion && !isInActivePop)
                ? sin(time * (index == 0 ? 1.15 : 0.98) + Double(index))
                : 0
            let activeExpression = resolvedExpression(at: time, floats: animated && !reduceMotion)
            let classicMode = classicEyeMode(at: time, timelineDate: now, floats: animated && !reduceMotion)
            let blinkClosed = (animated && !reduceMotion && !isInActivePop) ? isBlinking(at: time) : false
            let resolvedColor = color ?? .skyBlue

            ZStack {
                if !decorations.isEmpty {
                    Canvas { context, canvasSize in
                        BubbleDecorationRenderer.transformToBubbleSpace(context: &context, canvasSize: canvasSize)
                        BubbleDecorationRenderer.drawBackDecorations(
                            in: &context,
                            loadout: decorations,
                            tintColor: resolvedColor.tintColor,
                            deepTintColor: resolvedColor.deepTintColor
                        )
                    }
                    .frame(width: extendedSize, height: extendedSize)
                    .opacity(popFrame?.decorationOpacity ?? 1.0)
                    .allowsHitTesting(false)
                }

                ZStack {
                    if let color, color != .clear {
                        Circle()
                            .fill(color.bubbleSphereFill(size: size))
                            .overlay {
                                Circle().strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            color.glowColor.opacity(0.92),
                                            color.tintColor.opacity(0.32),
                                            color.deepTintColor.opacity(0.72)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: size * 0.032
                                )
                            }
                            .overlay {
                                if BubbleDecorationRenderer.hasThemeAccents(color) {
                                    Canvas { ctx, cSize in
                                        BubbleDecorationRenderer.drawThemeAccents(in: &ctx, size: cSize, theme: color)
                                    }
                                    .clipShape(Circle())
                                }
                            }
                            .padding(size * 0.09)
                    }
                    Image("BubbleMascot")
                        .resizable()
                        .scaledToFit()
                        .opacity(color == nil || color == .clear ? 1.0 : 0.56)
                    if let color, color != .clear {
                        Circle()
                            .trim(from: 0.57, to: 0.72)
                            .stroke(
                                Color.white.opacity(0.72),
                                style: StrokeStyle(lineWidth: max(1.6, size * 0.030), lineCap: .round)
                            )
                            .padding(size * 0.145)
                    }
                }
                .frame(width: size, height: size)
                .scaleEffect(popFrame?.shellScale ?? 1.0)
                .offset(y: (popFrame?.shellOffsetY ?? 0) * (size / 128.0))
                .opacity(popFrame?.shellOpacity ?? 1.0)

                if let popFrame, let centerYNorm = popFrame.miniBubbleCenterYNorm, let radiusNorm = popFrame.miniBubbleRadiusNorm {
                    Canvas { context, canvasSize in
                        BubbleDecorationRenderer.transformToBubbleSpace(context: &context, canvasSize: canvasSize)
                        drawReinflatingBubble(
                            in: &context,
                            centerY: centerYNorm,
                            radius: radiusNorm,
                            color: resolvedColor
                        )
                    }
                    .frame(width: extendedSize, height: extendedSize)
                    .allowsHitTesting(false)
                }

                if let burstProgress = popFrame?.burstProgress {
                    Canvas { context, canvasSize in
                        BubbleDecorationRenderer.transformToBubbleSpace(context: &context, canvasSize: canvasSize)
                        BubbleDecorationRenderer.drawPopBurstEffects(in: &context, progress: burstProgress)
                    }
                    .frame(width: extendedSize, height: extendedSize)
                    .allowsHitTesting(false)
                }

                Canvas { context, canvasSize in
                    BubbleDecorationRenderer.transformToBubbleSpace(context: &context, canvasSize: canvasSize)
                    BubbleDecorationRenderer.drawFace(
                        in: &context,
                        expression: activeExpression,
                        classicEyeMode: classicMode,
                        blinkClosed: blinkClosed,
                        loadout: decorations,
                        popFaceMode: popFrame?.faceMode
                    )
                }
                .frame(width: extendedSize, height: extendedSize)
                .scaleEffect(popFrame?.faceScale ?? 1.0)
                .offset(
                    x: (popFrame?.faceOffsetX ?? 0) * (size / 128.0),
                    y: (popFrame?.faceOffsetY ?? 0) * (size / 128.0)
                )
                .allowsHitTesting(false)

                if !decorations.isEmpty {
                    Canvas { context, canvasSize in
                        BubbleDecorationRenderer.transformToBubbleSpace(context: &context, canvasSize: canvasSize)
                        BubbleDecorationRenderer.drawFrontDecorations(in: &context, loadout: decorations)
                    }
                    .frame(width: extendedSize, height: extendedSize)
                    .opacity(popFrame?.decorationOpacity ?? 1.0)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(x: 1 - wave * 0.014, y: 1 + wave * 0.018)
            .offset(y: wave * (index == 0 ? 8 : 11))
        }
        .accessibilityHidden(true)
    }

    private func resolvedExpression(at time: TimeInterval, floats: Bool) -> BubbleExpression {
        guard !expressionRotationPool.isEmpty else { return expression }
        guard floats, expressionRotationPool.count >= 2 else {
            return expressionRotationPool.first ?? expression
        }
        let intervals = isFastPreviewRotation ? Self.previewRotationIntervals : Self.homeRotationIntervals
        let totalCycle = intervals.reduce(0, +)
        let offsetTime = time + Double(index) * (isFastPreviewRotation ? 0.9 : 17.3)
        let cycleIndex = max(0, Int(floor(offsetTime / totalCycle)))
        var remainder = offsetTime - Double(cycleIndex) * totalCycle

        var slotIndex = 0
        for (idx, dur) in intervals.enumerated() {
            if remainder < dur || idx == intervals.count - 1 {
                slotIndex = idx
                break
            }
            remainder -= dur
        }

        let count = expressionRotationPool.count
        let chosenIndex = rotationPickIndex(cycle: cycleIndex, slot: slotIndex, count: count)
        return expressionRotationPool[chosenIndex]
    }

    private func rotationPickIndex(cycle: Int, slot: Int, count: Int) -> Int {
        func rawPick(_ c: Int, _ s: Int) -> Int {
            let h = abs(c &* 131 + s &* 37 + index &* 19 + 7)
            return h % count
        }
        let current = rawPick(cycle, slot)
        let prevSlot = slot > 0 ? slot - 1 : (isFastPreviewRotation ? Self.previewRotationIntervals.count - 1 : Self.homeRotationIntervals.count - 1)
        let prevCycle = slot > 0 ? cycle : max(0, cycle - 1)
        let previous = rawPick(prevCycle, prevSlot)
        if current == previous {
            return (current + 1) % count
        }
        return current
    }

    private func popFrame(at date: Date) -> PopAnimationFrame? {
        guard let popStartDate else { return nil }
        let elapsed = date.timeIntervalSince(popStartDate)
        guard elapsed >= 0 else { return nil }

        if reduceMotion {
            guard elapsed < 1.0 else { return nil }
            return PopAnimationFrame(
                shellOpacity: 1.0,
                shellScale: 1.0,
                shellOffsetY: 0,
                decorationOpacity: 1.0,
                burstProgress: nil,
                faceMode: .shocked,
                faceScale: 1.0,
                faceOffsetX: 0,
                faceOffsetY: 0,
                miniBubbleCenterYNorm: nil,
                miniBubbleRadiusNorm: nil
            )
        }

        guard elapsed < Self.totalPopDuration else { return nil }

        if elapsed < 0.58 {
            let burstProg = elapsed < 0.38 ? (elapsed / 0.38) : nil
            let decoOpacity = max(0.0, 1.0 - elapsed / 0.08)
            let bouncePhase = min(1.0, elapsed / 0.24)
            let bounceScale = 1.0 + sin(bouncePhase * .pi) * 0.14
            return PopAnimationFrame(
                shellOpacity: 0,
                shellScale: 1.15,
                shellOffsetY: 0,
                decorationOpacity: decoOpacity,
                burstProgress: burstProg,
                faceMode: .shocked,
                faceScale: bounceScale,
                faceOffsetX: 0,
                faceOffsetY: -sin(bouncePhase * .pi) * 4.0,
                miniBubbleCenterYNorm: nil,
                miniBubbleRadiusNorm: nil
            )
        } else if elapsed < 0.92 {
            let shakeX = sin(elapsed * 54.0) * 1.4
            let shakeY = cos(elapsed * 46.0) * 0.8
            return PopAnimationFrame(
                shellOpacity: 0,
                shellScale: 0,
                shellOffsetY: 0,
                decorationOpacity: 0,
                burstProgress: nil,
                faceMode: .straining(blowing: false),
                faceScale: 0.96,
                faceOffsetX: shakeX,
                faceOffsetY: shakeY,
                miniBubbleCenterYNorm: nil,
                miniBubbleRadiusNorm: nil
            )
        } else if elapsed < 1.28 {
            let t = (elapsed - 0.92) / 0.36
            let eased = t * t * (3.0 - 2.0 * t)
            return PopAnimationFrame(
                shellOpacity: 0,
                shellScale: 0,
                shellOffsetY: 0,
                decorationOpacity: 0,
                burstProgress: nil,
                faceMode: .straining(blowing: true),
                faceScale: 0.97,
                faceOffsetX: sin(elapsed * 42.0) * 0.7,
                faceOffsetY: 0,
                miniBubbleCenterYNorm: 73.0,
                miniBubbleRadiusNorm: 7.0 + eased * 8.5
            )
        } else if elapsed < 1.74 {
            let t = (elapsed - 1.28) / 0.46
            let eased = t * t * (3.0 - 2.0 * t)
            return PopAnimationFrame(
                shellOpacity: 0,
                shellScale: 0,
                shellOffsetY: 0,
                decorationOpacity: 0,
                burstProgress: nil,
                faceMode: .straining(blowing: false),
                faceScale: 0.98,
                faceOffsetX: sin(elapsed * 46.0) * 0.9,
                faceOffsetY: cos(elapsed * 42.0) * 0.6,
                miniBubbleCenterYNorm: 73.0 - eased * 4.5,
                miniBubbleRadiusNorm: 15.5 + eased * 14.5
            )
        } else if elapsed < 2.22 {
            let t = (elapsed - 1.74) / 0.48
            let eased = t * t * (3.0 - 2.0 * t)
            return PopAnimationFrame(
                shellOpacity: 0,
                shellScale: 0,
                shellOffsetY: 0,
                decorationOpacity: 0,
                burstProgress: nil,
                faceMode: .straining(blowing: false),
                faceScale: 1.0,
                faceOffsetX: sin(elapsed * 40.0) * 0.6,
                faceOffsetY: 0,
                miniBubbleCenterYNorm: 68.5 - eased * 3.0,
                miniBubbleRadiusNorm: 30.0 + eased * 14.0
            )
        } else if elapsed < 2.62 {
            let t = (elapsed - 2.22) / 0.40
            let eased = t * t * (3.0 - 2.0 * t)
            let radius = 44.0 + eased * 10.5
            return PopAnimationFrame(
                shellOpacity: eased * 0.55,
                shellScale: 0.88 + eased * 0.16,
                shellOffsetY: (1.0 - eased) * 2.0,
                decorationOpacity: max(0, (eased - 0.55) / 0.45) * 0.4,
                burstProgress: nil,
                faceMode: .straining(blowing: false),
                faceScale: 1.0 + eased * 0.03,
                faceOffsetX: 0,
                faceOffsetY: 0,
                miniBubbleCenterYNorm: 65.5 - eased * 1.5,
                miniBubbleRadiusNorm: radius
            )
        } else {
            let t = min(1.0, (elapsed - 2.62) / (Self.totalPopDuration - 2.62))
            let eased = 1.0 - pow(1.0 - t, 3.0)
            let elasticScale = 1.04 - eased * 0.04
            return PopAnimationFrame(
                shellOpacity: 0.55 + eased * 0.45,
                shellScale: elasticScale,
                shellOffsetY: 0,
                decorationOpacity: 0.4 + eased * 0.6,
                burstProgress: nil,
                faceMode: t < 0.25 ? .straining(blowing: false) : nil,
                faceScale: 1.0 + (1.0 - eased) * 0.04,
                faceOffsetX: 0,
                faceOffsetY: 0,
                miniBubbleCenterYNorm: 64.0,
                miniBubbleRadiusNorm: t < 0.55 ? (54.5 - eased * 2.0) : nil
            )
        }
    }

    private func drawReinflatingBubble(
        in context: inout GraphicsContext,
        centerY: Double,
        radius: Double,
        color: BubbleColorTheme
    ) {
        let rect = CGRect(x: 64.0 - radius, y: centerY - radius, width: radius * 2.0, height: radius * 2.0)
        let circle = Path(ellipseIn: rect)
        let topColor = color == .clear ? Color.white.opacity(0.60) : color.glowColor.opacity(0.62)
        let midColor = color == .clear ? Color(red: 0.82, green: 0.93, blue: 1.0).opacity(0.32) : color.tintColor.opacity(0.70)
        let rimColor = color == .clear ? Color(red: 0.72, green: 0.86, blue: 1.0).opacity(0.85) : color.deepTintColor.opacity(0.75)

        context.fill(
            circle,
            with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.24), topColor, midColor]),
                center: CGPoint(x: 64.0 - radius * 0.3, y: centerY - radius * 0.3),
                startRadius: 0,
                endRadius: radius * 1.15
            )
        )
        context.stroke(
            circle,
            with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.95), rimColor, Color(red: 1.0, green: 0.78, blue: 0.92).opacity(0.75)]),
                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            ),
            style: StrokeStyle(lineWidth: max(1.6, min(3.2, radius * 0.065)))
        )

        if radius >= 10 {
            let dotR = max(1.6, radius * 0.14)
            let dot = Path(ellipseIn: CGRect(x: 64.0 - radius * 0.48 - dotR, y: centerY - radius * 0.48 - dotR, width: dotR * 2, height: dotR * 2))
            context.fill(dot, with: .color(Color.white.opacity(0.90)))
        }
    }

    private func isBlinking(at time: TimeInterval) -> Bool {
        let blinkCycle = (time + Double(index) * 1.3).truncatingRemainder(dividingBy: 4.3)
        return blinkCycle < 0.14
    }

    private func classicEyeMode(at time: TimeInterval, timelineDate: Date, floats: Bool) -> MascotResolvedEyeMode {
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
}
