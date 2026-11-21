import SwiftUI
import UIKit

enum SoapBubbleCornerStyle: Equatable {
    case capsule
    case roundedRect(CGFloat)
}

enum SoapBubbleProminence: Equatable {
    case standard
    case vivid
}

/// Smooth organic contour with subtle surface-tension waves that fits circles, capsules, and rounded cards.
struct OrganicBubbleShape: Shape {
    var cornerStyle: SoapBubbleCornerStyle
    let seed: Double
    var phase: Double = 0
    var ampScale: Double = 1.0

    func path(in rect: CGRect) -> Path {
        let minDim = min(rect.width, rect.height)
        guard minDim > 4 else { return Path() }

        let inset = min(3.4, minDim * 0.14)
        let rRect = rect.insetBy(dx: inset, dy: inset)
        guard rRect.width > 2, rRect.height > 2 else { return Path() }

        let r: CGFloat = switch cornerStyle {
        case .capsule: min(rRect.width, rRect.height) * 0.5
        case let .roundedRect(radius): min(radius, min(rRect.width, rRect.height) * 0.5)
        }

        let topBottomStraight = max(0, rRect.width - 2.0 * r)
        let leftRightStraight = max(0, rRect.height - 2.0 * r)
        let quarterArc = 0.5 * .pi * r

        let s1 = topBottomStraight
        let s2 = s1 + quarterArc
        let s3 = s2 + leftRightStraight
        let s4 = s3 + quarterArc
        let s5 = s4 + topBottomStraight
        let s6 = s5 + quarterArc
        let s7 = s6 + leftRightStraight
        let totalLen = max(1.0, s7 + quarterArc)

        let steps = 36
        var points: [CGPoint] = []
        points.reserveCapacity(steps)

        for i in 0..<steps {
            let s = (Double(i) / Double(steps)) * totalLen
            let base: CGPoint
            let normal: CGVector

            if s < s1 {
                let t = s / max(1e-6, topBottomStraight)
                base = CGPoint(x: rRect.minX + r + CGFloat(t) * topBottomStraight, y: rRect.minY)
                normal = CGVector(dx: 0, dy: -1)
            } else if s < s2 {
                let t = (s - s1) / max(1e-6, quarterArc)
                let angle = -Double.pi * 0.5 + t * (Double.pi * 0.5)
                base = CGPoint(
                    x: rRect.maxX - r + CGFloat(cos(angle)) * r,
                    y: rRect.minY + r + CGFloat(sin(angle)) * r
                )
                normal = CGVector(dx: cos(angle), dy: sin(angle))
            } else if s < s3 {
                let t = (s - s2) / max(1e-6, leftRightStraight)
                base = CGPoint(x: rRect.maxX, y: rRect.minY + r + CGFloat(t) * leftRightStraight)
                normal = CGVector(dx: 1, dy: 0)
            } else if s < s4 {
                let t = (s - s3) / max(1e-6, quarterArc)
                let angle = t * (Double.pi * 0.5)
                base = CGPoint(
                    x: rRect.maxX - r + CGFloat(cos(angle)) * r,
                    y: rRect.maxY - r + CGFloat(sin(angle)) * r
                )
                normal = CGVector(dx: cos(angle), dy: sin(angle))
            } else if s < s5 {
                let t = (s - s4) / max(1e-6, topBottomStraight)
                base = CGPoint(x: rRect.maxX - r - CGFloat(t) * topBottomStraight, y: rRect.maxY)
                normal = CGVector(dx: 0, dy: 1)
            } else if s < s6 {
                let t = (s - s5) / max(1e-6, quarterArc)
                let angle = Double.pi * 0.5 + t * (Double.pi * 0.5)
                base = CGPoint(
                    x: rRect.minX + r + CGFloat(cos(angle)) * r,
                    y: rRect.maxY - r + CGFloat(sin(angle)) * r
                )
                normal = CGVector(dx: cos(angle), dy: sin(angle))
            } else if s < s7 {
                let t = (s - s6) / max(1e-6, leftRightStraight)
                base = CGPoint(x: rRect.minX, y: rRect.maxY - r - CGFloat(t) * leftRightStraight)
                normal = CGVector(dx: -1, dy: 0)
            } else {
                let t = (s - s7) / max(1e-6, quarterArc)
                let angle = Double.pi + t * (Double.pi * 0.5)
                base = CGPoint(
                    x: rRect.minX + r + CGFloat(cos(angle)) * r,
                    y: rRect.minY + r + CGFloat(sin(angle)) * r
                )
                normal = CGVector(dx: cos(angle), dy: sin(angle))
            }

            let theta = (Double(i) / Double(steps)) * 2.0 * .pi
            let wave = 1.15 * sin(3.0 * theta + seed + phase * 1.10)
                + 0.78 * cos(5.0 * theta - seed * 1.3 - phase * 1.65)
                + 0.45 * sin(7.0 * theta + seed * 0.7 + phase * 2.20)
            let maxAmp = min(3.2 * ampScale, Double(minDim) * 0.11)
            let amp = maxAmp * (wave / 2.38)

            points.append(CGPoint(
                x: base.x + normal.dx * CGFloat(amp),
                y: base.y + normal.dy * CGFloat(amp)
            ))
        }

        var path = Path()
        guard let last = points.last, let first = points.first else { return path }
        path.move(to: CGPoint(x: (last.x + first.x) * 0.5, y: (last.y + first.y) * 0.5))
        for i in points.indices {
            let cur = points[i]
            let next = points[(i + 1) % points.count]
            let mid = CGPoint(x: (cur.x + next.x) * 0.5, y: (cur.y + next.y) * 0.5)
            path.addQuadCurve(to: mid, control: cur)
        }
        path.closeSubpath()
        return path
    }
}

/// Single-pass zero-blur Style A pastel translucent soap-bubble renderer with crisp optical light reflections.
struct SoapBubbleSurface: View {
    var cornerStyle: SoapBubbleCornerStyle = .capsule
    var prominence: SoapBubbleProminence = .standard
    var isTogether: Bool = false
    var seed: Double = 0
    var wobbleScale: Double = 0.55
    var animated: Bool = true
    var externalPhase: Double? = nil
    var squish: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let externalPhase {
            bubbleCanvas(phase: reduceMotion ? 0 : externalPhase)
        } else if animated && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                bubbleCanvas(phase: timeline.date.timeIntervalSinceReferenceDate * 1.10)
            }
        } else {
            bubbleCanvas(phase: 0)
        }
    }

    private func bubbleCanvas(phase: Double) -> some View {
        Canvas { context, size in
            let minDim = min(size.width, size.height)
            guard minDim > 4 else { return }

            let isVivid = prominence == .vivid
            let shapePath = OrganicBubbleShape(
                cornerStyle: cornerStyle,
                seed: seed,
                phase: phase,
                ampScale: reduceMotion ? 0 : wobbleScale
            )
            .path(in: CGRect(origin: .zero, size: size))

            // 1. Cheap subtle bottom rim shadow without blurring or tinting the clear bubble interior
            var shadowCtx = context
            shadowCtx.translateBy(x: 0, y: 2)
            shadowCtx.stroke(
                shapePath,
                with: .color(FoamTheme.ink.opacity(isVivid ? 0.06 : 0.04)),
                style: StrokeStyle(lineWidth: 2.8, lineJoin: .round)
            )

            // 2. Luminous pastel translucent interior veil
            let pastelTint = isTogether
                ? Color(red: 1.0, green: 0.86, blue: 0.94)
                : Color(red: 0.80, green: 0.90, blue: 1.0)
            let fillShading: GraphicsContext.Shading = .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(isVivid ? 0.54 : 0.44),
                    Color.white.opacity(isVivid ? 0.22 : 0.16),
                    pastelTint.opacity(isVivid ? 0.36 : 0.26)
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            )
            context.fill(shapePath, with: fillShading)

            // 3. Drifting Style A pastel iridescent gradient for inner Fresnel cushion & outer rim
            let drift = sin(phase * 0.65) * 0.08
            let iridescentShading: GraphicsContext.Shading = .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(0.95),
                    Color(red: 0.56, green: 0.90, blue: 1.0, opacity: 0.88),
                    Color(red: 1.0, green: 0.72, blue: 0.90, opacity: 0.88),
                    Color(red: 0.76, green: 0.82, blue: 1.0, opacity: 0.88),
                    Color(red: 1.0, green: 0.92, blue: 0.74, opacity: 0.85),
                    Color.white.opacity(0.94)
                ]),
                startPoint: CGPoint(x: size.width * (0.05 + drift), y: size.height * 0.05),
                endPoint: CGPoint(x: size.width * (0.95 - drift), y: size.height * 0.95)
            )

            // 4. Clipped interior Fresnel rim cushion + optical specular light reflections
            var inner = context
            inner.clip(to: shapePath)

            inner.opacity = isVivid ? 0.16 : 0.12
            inner.stroke(shapePath, with: iridescentShading, style: StrokeStyle(lineWidth: 5.5, lineJoin: .round))
            inner.opacity = isVivid ? 0.26 : 0.18
            inner.stroke(shapePath, with: iridescentShading, style: StrokeStyle(lineWidth: 3.0, lineJoin: .round))
            inner.opacity = 1.0

            drawOpticalSpeculars(in: &inner, size: size, isVivid: isVivid)

            // 5. Layered outer iridescent bloom + crisp thin-film rim + upper-left white rim kiss
            var rimHalo = context
            rimHalo.opacity = isVivid ? 0.18 : 0.13
            rimHalo.stroke(
                shapePath,
                with: iridescentShading,
                style: StrokeStyle(lineWidth: isVivid ? 6.4 : 4.8, lineJoin: .round)
            )
            rimHalo.opacity = isVivid ? 0.34 : 0.25
            rimHalo.stroke(
                shapePath,
                with: iridescentShading,
                style: StrokeStyle(lineWidth: isVivid ? 3.8 : 2.9, lineJoin: .round)
            )

            context.stroke(
                shapePath,
                with: iridescentShading,
                style: StrokeStyle(lineWidth: isVivid ? 2.0 : 1.55, lineJoin: .round)
            )

            let whiteKissShading: GraphicsContext.Shading = .linearGradient(
                Gradient(colors: [Color.white.opacity(isVivid ? 0.92 : 0.78), .clear]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width * 0.55, y: size.height * 0.55)
            )
            context.stroke(
                shapePath,
                with: whiteKissShading,
                style: StrokeStyle(lineWidth: 1.1, lineJoin: .round)
            )
        }
        .scaleEffect(x: 1.0 + squish, y: 1.0 - squish)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawOpticalSpeculars(in context: inout GraphicsContext, size: CGSize, isVivid: Bool) {
        let minDim = min(size.width, size.height)
        guard minDim > 6 else { return }

        let inset = min(3.4, minDim * 0.14)
        let innerW = max(2, size.width - inset * 2)
        let innerH = max(2, size.height - inset * 2)
        let r: CGFloat = switch cornerStyle {
        case .capsule: min(innerW, innerH) * 0.5
        case let .roundedRect(radius): min(radius, min(innerW, innerH) * 0.5)
        }
        let trackInset = min(5.5, minDim * 0.18)
        let hr = max(1.8, r - trackInset)

        if size.width <= size.height * 1.25 {
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let primaryArc = arcPath(center: center, radius: hr, startDeg: 206, endDeg: 262)
            let coreWidth = max(1.0, min(2.8, r * 0.105))

            strokeMultiLayerGlow(
                primaryArc,
                in: &context,
                coreWidth: coreWidth,
                coreOpacity: isVivid ? 0.94 : 0.88
            )

            if minDim >= 18 {
                let dotRad = 184.0 * .pi / 180.0
                let dotD = max(2.2, min(4.2, r * 0.13))
                let dotPos = CGPoint(
                    x: center.x + CGFloat(cos(dotRad)) * hr,
                    y: center.y + CGFloat(sin(dotRad)) * hr
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: dotPos.x - dotD * 0.5, y: dotPos.y - dotD * 0.5, width: dotD, height: dotD)),
                    with: .color(.white.opacity(0.90))
                )
            }

            let bounceArc = arcPath(center: center, radius: hr, startDeg: 24, endDeg: 68)
            let bounceWidth = max(1.1, min(2.8, r * 0.10))
            context.stroke(
                bounceArc,
                with: .color(.white.opacity(0.18)),
                style: StrokeStyle(lineWidth: bounceWidth * 1.8, lineCap: .round)
            )
            context.stroke(
                bounceArc,
                with: .color(.white.opacity(0.36)),
                style: StrokeStyle(lineWidth: bounceWidth, lineCap: .round)
            )
        } else {
            let tlCenter = CGPoint(x: inset + r, y: inset + r)
            let straightTail = min(size.width * 0.28, max(16, r * 1.15))
            var topPath = arcPath(center: tlCenter, radius: hr, startDeg: 196, endDeg: 270)
            topPath.addLine(to: CGPoint(x: tlCenter.x + straightTail, y: tlCenter.y - hr))

            strokeMultiLayerGlow(
                topPath,
                in: &context,
                coreWidth: 2.1,
                coreOpacity: isVivid ? 0.94 : 0.86
            )

            let dotRad = 176.0 * .pi / 180.0
            let dotPos = CGPoint(
                x: tlCenter.x + CGFloat(cos(dotRad)) * hr,
                y: tlCenter.y + CGFloat(sin(dotRad)) * hr
            )
            context.fill(
                Path(ellipseIn: CGRect(x: dotPos.x - 1.6, y: dotPos.y - 1.6, width: 3.2, height: 3.2)),
                with: .color(.white.opacity(0.88))
            )

            let brCenter = CGPoint(x: size.width - inset - r, y: size.height - inset - r)
            let brArc = arcPath(center: brCenter, radius: hr, startDeg: 14, endDeg: 82)
            context.stroke(
                brArc,
                with: .color(.white.opacity(0.16)),
                style: StrokeStyle(lineWidth: 3.8, lineCap: .round)
            )
            context.stroke(
                brArc,
                with: .color(.white.opacity(0.34)),
                style: StrokeStyle(lineWidth: 2.1, lineCap: .round)
            )
        }
    }

    private func strokeMultiLayerGlow(
        _ path: Path,
        in context: inout GraphicsContext,
        coreWidth: CGFloat,
        coreOpacity: Double
    ) {
        context.stroke(
            path,
            with: .color(.white.opacity(0.18)),
            style: StrokeStyle(lineWidth: coreWidth * 2.1, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            path,
            with: .color(.white.opacity(0.38)),
            style: StrokeStyle(lineWidth: coreWidth * 1.4, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            path,
            with: .color(.white.opacity(coreOpacity)),
            style: StrokeStyle(lineWidth: coreWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func arcPath(center: CGPoint, radius: CGFloat, startDeg: Double, endDeg: Double, steps: Int = 18) -> Path {
        var path = Path()
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let rad = (startDeg + (endDeg - startDeg) * t) * .pi / 180.0
            let pt = CGPoint(
                x: center.x + CGFloat(cos(rad)) * radius,
                y: center.y + CGFloat(sin(rad)) * radius
            )
            if step == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        return path
    }
}

/// Interactive translucent soap-bubble toggle switch with wobbling bubble knob and mini burst sparkles.
struct SoapBubbleToggleStyle: ToggleStyle {
    var isTogether: Bool = false
    var seed: Double = 1.2

    func makeBody(configuration: Configuration) -> some View {
        SoapBubbleToggleControl(
            configuration: configuration,
            isTogether: isTogether,
            seed: seed
        )
    }
}

private struct SoapBubbleToggleControl: View {
    let configuration: ToggleStyle.Configuration
    let isTogether: Bool
    let seed: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSquishing = false
    @State private var showBurst = false
    @State private var burstProgress: CGFloat = 0

    private var onColors: [Color] {
        isTogether
            ? [Color(red: 1.0, green: 0.70, blue: 0.80), Color(red: 1.0, green: 0.86, blue: 0.68)]
            : [Color(red: 0.54, green: 0.84, blue: 1.0), Color(red: 0.76, green: 0.74, blue: 1.0)]
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            let nextValue = !configuration.isOn
            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.64)) {
                configuration.isOn = nextValue
            }
            guard !reduceMotion else { return }
            isSquishing = true
            if nextValue {
                showBurst = true
                burstProgress = 0
                withAnimation(.easeOut(duration: 0.62)) {
                    burstProgress = 1.0
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(640))
                    showBurst = false
                    burstProgress = 0
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) {
                    isSquishing = false
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                configuration.label
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 10)

                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    if configuration.isOn {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: onColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .opacity(0.78)
                            )
                            .overlay {
                                Capsule().strokeBorder(Color.white.opacity(0.88), lineWidth: 1.5)
                            }
                            .shadow(color: onColors[0].opacity(0.35), radius: 6, y: 2)
                    } else {
                        Capsule()
                            .fill(Color.white.opacity(0.32))
                            .overlay {
                                Capsule().strokeBorder(FoamTheme.ink.opacity(0.16), lineWidth: 1.2)
                            }
                    }

                    SoapBubbleSurface(
                        cornerStyle: .capsule,
                        prominence: configuration.isOn ? .vivid : .standard,
                        isTogether: isTogether,
                        seed: seed,
                        wobbleScale: 0,
                        animated: false
                    )
                    .frame(width: 28, height: 28)
                    .scaleEffect(x: isSquishing ? 1.14 : 1.0, y: isSquishing ? 0.88 : 1.0)
                    .overlay {
                        if showBurst {
                            let burstOpacity = burstProgress < 0.2
                                ? Double(burstProgress / 0.2)
                                : max(0, 1.0 - Double(burstProgress - 0.2) / 0.8)
                            ZStack {
                                miniSparkleBubble(diameter: 5)
                                    .offset(x: -6 * burstProgress, y: -6 - 14 * burstProgress)
                                miniSparkleBubble(diameter: 7)
                                    .offset(x: 4 * burstProgress, y: -8 - 20 * burstProgress)
                                miniSparkleBubble(diameter: 4)
                                    .offset(x: 11 * burstProgress, y: -4 - 12 * burstProgress)
                            }
                            .opacity(burstOpacity)
                            .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(width: 54, height: 32)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
        .accessibilityValue(configuration.isOn ? "オン" : "オフ")
    }

    private func miniSparkleBubble(diameter: CGFloat) -> some View {
        Circle()
            .fill(Color.white.opacity(0.55))
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.95), lineWidth: 0.8)
            }
            .frame(width: diameter, height: diameter)
    }
}
