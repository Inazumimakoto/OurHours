import OurHoursCore
import SwiftUI

enum MascotPopFaceMode: Equatable {
    case shocked
    case straining(blowing: Bool)
}

enum MascotResolvedEyeMode: Equatable {
    case open
    case happy
    case closed
}

enum BubbleDecorationRenderer {
    static let canvasExtentMultiplier: CGFloat = 1.44
    private static let designDimension: CGFloat = 128.0
    private static let ink = FoamTheme.ink

    static func transformToBubbleSpace(context: inout GraphicsContext, canvasSize: CGSize) {
        let baseSize = min(canvasSize.width, canvasSize.height) / canvasExtentMultiplier
        let offsetX = (canvasSize.width - baseSize) * 0.5
        let offsetY = (canvasSize.height - baseSize) * 0.5
        context.translateBy(x: offsetX, y: offsetY)
        let scale = baseSize / designDimension
        context.scaleBy(x: scale, y: scale)
    }

    static func hasThemeAccents(_ theme: BubbleColorTheme) -> Bool {
        switch theme {
        case .moonlight, .snowCrystal, .champagneGold, .auroraPrism, .easterPastel, .milkyWay:
            return true
        default:
            return false
        }
    }

    static func drawThemeAccents(in context: inout GraphicsContext, size: CGSize, theme: BubbleColorTheme) {
        let w = size.width
        let h = size.height
        switch theme {
        case .moonlight:
            let points: [(Double, Double, Double)] = [
                (0.24, 0.28, 0.052), (0.76, 0.30, 0.044), (0.68, 0.76, 0.040), (0.28, 0.72, 0.032)
            ]
            for (px, py, pr) in points {
                drawFourPointSparkle(
                    in: &context,
                    center: CGPoint(x: w * px, y: h * py),
                    radius: min(w, h) * pr,
                    color: Color(red: 1.0, green: 0.96, blue: 0.72).opacity(0.88)
                )
            }
        case .snowCrystal:
            let flakes: [(Double, Double, Double)] = [
                (0.26, 0.32, 0.045), (0.74, 0.28, 0.038), (0.72, 0.74, 0.042), (0.28, 0.72, 0.032)
            ]
            for (px, py, pr) in flakes {
                let r = min(w, h) * pr
                let dot = Path(ellipseIn: CGRect(x: w * px - r, y: h * py - r, width: r * 2, height: r * 2))
                context.fill(dot, with: .color(.white.opacity(0.92)))
            }
        case .champagneGold:
            let glints: [(Double, Double, Double)] = [
                (0.24, 0.34, 0.048), (0.74, 0.36, 0.040), (0.65, 0.74, 0.046)
            ]
            for (px, py, pr) in glints {
                drawFourPointSparkle(
                    in: &context,
                    center: CGPoint(x: w * px, y: h * py),
                    radius: min(w, h) * pr,
                    color: Color.white.opacity(0.92)
                )
            }
        case .auroraPrism:
            drawFourPointSparkle(
                in: &context,
                center: CGPoint(x: w * 0.74, y: h * 0.30),
                radius: min(w, h) * 0.05,
                color: Color.white.opacity(0.92)
            )
        case .easterPastel:
            let dots: [(Double, Double, Double, Color)] = [
                (0.24, 0.34, 0.045, Color(red: 1.0, green: 0.96, blue: 0.56)),
                (0.76, 0.32, 0.040, Color(red: 0.62, green: 0.96, blue: 0.84)),
                (0.70, 0.74, 0.044, Color(red: 1.0, green: 0.70, blue: 0.86)),
                (0.28, 0.70, 0.036, Color.white)
            ]
            for (px, py, pr, col) in dots {
                let r = min(w, h) * pr
                let dot = Path(ellipseIn: CGRect(x: w * px - r, y: h * py - r, width: r * 2, height: r * 2))
                context.fill(dot, with: .color(col.opacity(0.88)))
            }
        case .milkyWay:
            let minDim = min(w, h)
            var river = Path()
            river.move(to: CGPoint(x: w * 0.04, y: h * 0.84))
            river.addCurve(
                to: CGPoint(x: w * 0.96, y: h * 0.16),
                control1: CGPoint(x: w * 0.36, y: h * 0.72),
                control2: CGPoint(x: w * 0.64, y: h * 0.28)
            )
            let nebulaShading: GraphicsContext.Shading = .linearGradient(
                Gradient(colors: [
                    Color(red: 0.44, green: 0.86, blue: 1.0).opacity(0.32),
                    Color(red: 0.82, green: 0.68, blue: 1.0).opacity(0.36),
                    Color(red: 1.0, green: 0.76, blue: 0.92).opacity(0.30),
                    Color(red: 0.68, green: 0.94, blue: 1.0).opacity(0.34)
                ]),
                startPoint: CGPoint(x: 0, y: h),
                endPoint: CGPoint(x: w, y: 0)
            )
            context.stroke(river, with: nebulaShading, style: StrokeStyle(lineWidth: minDim * 0.32, lineCap: .round))
            context.stroke(river, with: .color(Color.white.opacity(0.22)), style: StrokeStyle(lineWidth: minDim * 0.16, lineCap: .round))
            context.stroke(river, with: .color(Color(red: 0.88, green: 0.98, blue: 1.0).opacity(0.28)), style: StrokeStyle(lineWidth: minDim * 0.06, lineCap: .round))

            let microDots: [(Double, Double, Double, Color)] = [
                (0.14, 0.78, 0.018, .white),
                (0.20, 0.71, 0.024, Color(red: 0.74, green: 0.96, blue: 1.0)),
                (0.24, 0.81, 0.015, Color(red: 1.0, green: 0.94, blue: 0.70)),
                (0.28, 0.68, 0.020, .white),
                (0.32, 0.61, 0.014, Color(red: 1.0, green: 0.80, blue: 0.94)),
                (0.37, 0.65, 0.022, .white),
                (0.42, 0.56, 0.016, Color(red: 0.76, green: 0.95, blue: 1.0)),
                (0.47, 0.49, 0.021, Color(red: 1.0, green: 0.95, blue: 0.72)),
                (0.51, 0.55, 0.015, .white),
                (0.56, 0.45, 0.023, Color(red: 0.86, green: 0.92, blue: 1.0)),
                (0.61, 0.39, 0.014, Color(red: 1.0, green: 0.82, blue: 0.94)),
                (0.66, 0.43, 0.019, .white),
                (0.71, 0.33, 0.025, Color(red: 0.74, green: 0.96, blue: 1.0)),
                (0.76, 0.27, 0.016, .white),
                (0.81, 0.31, 0.020, Color(red: 1.0, green: 0.94, blue: 0.72)),
                (0.87, 0.21, 0.017, .white),
                (0.22, 0.30, 0.018, Color(red: 0.84, green: 0.94, blue: 1.0)),
                (0.36, 0.24, 0.015, .white),
                (0.74, 0.74, 0.020, Color(red: 1.0, green: 0.94, blue: 0.74)),
                (0.60, 0.78, 0.015, .white)
            ]
            for (px, py, pr, col) in microDots {
                let r = minDim * pr
                let dot = Path(ellipseIn: CGRect(x: w * px - r, y: h * py - r, width: r * 2, height: r * 2))
                context.fill(dot, with: .color(col.opacity(0.92)))
            }

            let sparkles: [(Double, Double, Double, Color)] = [
                (0.18, 0.75, 0.052, .white),
                (0.35, 0.58, 0.044, Color(red: 1.0, green: 0.96, blue: 0.72)),
                (0.50, 0.46, 0.060, .white),
                (0.64, 0.36, 0.042, Color(red: 0.76, green: 0.96, blue: 1.0)),
                (0.80, 0.25, 0.056, .white),
                (0.26, 0.32, 0.044, Color(red: 0.90, green: 0.97, blue: 1.0)),
                (0.73, 0.72, 0.046, Color(red: 1.0, green: 0.95, blue: 0.74))
            ]
            for (px, py, pr, col) in sparkles {
                drawFourPointSparkle(
                    in: &context,
                    center: CGPoint(x: w * px, y: h * py),
                    radius: minDim * pr,
                    color: col.opacity(0.95)
                )
            }
        default:
            break
        }
    }

    static func drawPopBurstEffects(in context: inout GraphicsContext, progress: Double) {
        let clamped = min(max(progress, 0), 1)
        guard clamped < 1 else { return }
        let alpha = (1.0 - clamped) * (1.0 - clamped * 0.35)
        let center = CGPoint(x: 64, y: 64)

        let spikeCount = 12
        for i in 0..<spikeCount {
            let angle = (Double(i) / Double(spikeCount)) * .pi * 2.0 + 0.14
            let innerR = 30.0 + clamped * 26.0
            let outerR = 44.0 + clamped * 40.0
            var ray = Path()
            ray.move(to: CGPoint(x: center.x + cos(angle) * innerR, y: center.y + sin(angle) * innerR))
            ray.addLine(to: CGPoint(x: center.x + cos(angle) * outerR, y: center.y + sin(angle) * outerR))
            context.stroke(
                ray,
                with: .color(Color.white.opacity(alpha * 0.92)),
                style: StrokeStyle(lineWidth: 2.3 * (1.0 - clamped * 0.45), lineCap: .round)
            )

            if i.isMultiple(of: 2) {
                let dropletAngle = angle + 0.19
                let dropletR = 36.0 + clamped * 44.0
                let dSize = (6.0 - clamped * 3.2)
                let dPos = CGPoint(
                    x: center.x + cos(dropletAngle) * dropletR,
                    y: center.y + sin(dropletAngle) * dropletR
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: dPos.x - dSize * 0.5, y: dPos.y - dSize * 0.5, width: dSize, height: dSize)),
                    with: .color(Color.white.opacity(alpha * 0.85))
                )
            }
        }
    }

    static func drawBackDecorations(
        in context: inout GraphicsContext,
        loadout: BubbleDecorationLoadout,
        tintColor: Color,
        deepTintColor: Color
    ) {
        switch loadout.ears {
        case .none:
            break
        case .catEars:
            drawCatEars(in: &context, tintColor: tintColor, deepTintColor: deepTintColor)
        case .dogEars:
            drawDogEars(in: &context)
        case .koalaEars:
            drawKoalaEars(in: &context)
        case .bunnyEars:
            drawBunnyEars(in: &context, tintColor: tintColor, deepTintColor: deepTintColor)
        case .bearEars:
            drawBearEars(in: &context)
        }

        if loadout.outfit == .halloweenCape {
            var cloak = Path()
            cloak.move(to: CGPoint(x: 24, y: 92))
            cloak.addQuadCurve(to: CGPoint(x: 16, y: 123), control: CGPoint(x: 14, y: 110))
            cloak.addQuadCurve(to: CGPoint(x: 64, y: 132), control: CGPoint(x: 38, y: 134))
            cloak.addQuadCurve(to: CGPoint(x: 112, y: 123), control: CGPoint(x: 90, y: 134))
            cloak.addQuadCurve(to: CGPoint(x: 104, y: 92), control: CGPoint(x: 114, y: 110))
            cloak.closeSubpath()
            context.fill(cloak, with: .color(Color(red: 0.28, green: 0.16, blue: 0.44)))
            context.stroke(cloak, with: .color(Color(red: 0.18, green: 0.09, blue: 0.30)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        }
    }

    static func drawFace(
        in context: inout GraphicsContext,
        expression: BubbleExpression,
        classicEyeMode: MascotResolvedEyeMode,
        blinkClosed: Bool,
        loadout: BubbleDecorationLoadout,
        popFaceMode: MascotPopFaceMode?
    ) {
        if let popFaceMode {
            switch popFaceMode {
            case .shocked:
                drawShockedPopFace(in: &context)
            case let .straining(blowing):
                drawStrainingPopFace(in: &context, blowing: blowing)
            }
            return
        }

        let blushAlpha: Double = switch expression {
        case .shy: 0.45
        case .heartEyes, .dreamy, .laughing: 0.36
        default: 0.28
        }
        drawBlush(in: &context, opacity: blushAlpha, showShyLines: expression == .shy)
        drawMakeup(in: &context, makeup: loadout.makeup)

        if blinkClosed && shouldBlink(for: expression) {
            for x in [46.0, 81.0] {
                drawClosedEyeArc(in: &context, centerX: x, y: 59, downward: true)
            }
            drawMouth(in: &context, expression: expression)
            drawFaceAccessories(in: &context, loadout: loadout)
            return
        }

        switch expression {
        case .classic:
            for x in [46.0, 81.0] {
                switch classicEyeMode {
                case .open: drawOpenEye(in: &context, centerX: x, centerY: 59)
                case .happy: drawClosedEyeArc(in: &context, centerX: x, y: 61, downward: false)
                case .closed: drawClosedEyeArc(in: &context, centerX: x, y: 59, downward: true)
                }
            }
        case .smile:
            for x in [46.0, 81.0] {
                drawOpenEye(in: &context, centerX: x, centerY: 58.5)
            }
        case .sleepy:
            for x in [46.0, 81.0] {
                drawClosedEyeArc(in: &context, centerX: x, y: 59.5, downward: true)
            }
        case .winkLeft:
            drawWinkRightFacingEye(in: &context, centerX: 46.0, centerY: 59.0)
            drawOpenEye(in: &context, centerX: 81.0, centerY: 59.0)
        case .squeezed:
            drawSqueezedEye(in: &context, centerX: 46.0, centerY: 58.5, pointingRight: true)
            drawSqueezedEye(in: &context, centerX: 81.0, centerY: 58.5, pointingRight: false)
        case .catMouth:
            for x in [46.0, 81.0] {
                drawOpenEye(in: &context, centerX: x, centerY: 58.5)
            }
        case .starry:
            for x in [46.0, 81.0] {
                drawStarryEye(in: &context, centerX: x, centerY: 58.5)
            }
        case .pout:
            for x in [46.0, 81.0] {
                drawSmallDotEye(in: &context, centerX: x, centerY: 59.0)
            }
        case .heartEyes:
            for x in [46.0, 81.0] {
                drawHeartEye(in: &context, centerX: x, centerY: 58.5)
            }
        case .shy:
            for x in [46.0, 81.0] {
                drawClosedEyeArc(in: &context, centerX: x, y: 60.5, downward: false)
            }
        case .relaxed:
            for x in [46.0, 81.0] {
                drawClosedEyeArc(in: &context, centerX: x, y: 60.0, downward: false)
            }
        case .cool:
            for x in [46.0, 81.0] {
                drawCoolEye(in: &context, centerX: x, centerY: 59.0)
            }
        case .dreamy:
            for x in [46.0, 81.0] {
                drawDreamyEye(in: &context, centerX: x, centerY: 59.5)
            }
        case .laughing:
            for x in [46.0, 81.0] {
                drawClosedEyeArc(in: &context, centerX: x, y: 60.5, downward: false)
            }
        case .royalSparkle:
            for x in [46.0, 81.0] {
                drawStarryEye(in: &context, centerX: x, centerY: 58.5)
            }
            drawFourPointSparkle(in: &context, center: CGPoint(x: 27, y: 42), radius: 4.5, color: .white.opacity(0.95))
            drawFourPointSparkle(in: &context, center: CGPoint(x: 100, y: 40), radius: 3.8, color: .white.opacity(0.92))
        case .poppedSurprise:
            for x in [46.0, 81.0] {
                drawSurprisedRoundEye(in: &context, centerX: x, centerY: 58.0)
            }
        case .mischievous:
            for x in [46.0, 81.0] {
                drawMischievousEye(in: &context, centerX: x, centerY: 59.0)
            }
        case .partyPop:
            for x in [46.0, 81.0] {
                drawClosedEyeArc(in: &context, centerX: x, y: 60.0, downward: false)
            }
            let confetti: [(CGPoint, Color)] = [
                (CGPoint(x: 28, y: 42), Color(red: 1.0, green: 0.45, blue: 0.62)),
                (CGPoint(x: 100, y: 41), Color(red: 0.34, green: 0.78, blue: 1.0)),
                (CGPoint(x: 94, y: 80), Color(red: 1.0, green: 0.80, blue: 0.24)),
                (CGPoint(x: 33, y: 80), Color(red: 0.56, green: 0.88, blue: 0.44))
            ]
            for (pt, col) in confetti {
                let dot = Path(ellipseIn: CGRect(x: pt.x - 2.3, y: pt.y - 2.3, width: 4.6, height: 4.6))
                context.fill(dot, with: .color(col.opacity(0.92)))
            }
        }

        drawMouth(in: &context, expression: expression)
        drawFaceAccessories(in: &context, loadout: loadout)
    }

    static func drawFrontDecorations(in context: inout GraphicsContext, loadout: BubbleDecorationLoadout) {
        drawEyewear(in: &context, eyewear: loadout.eyewear)
        drawOutfit(in: &context, outfit: loadout.outfit)
        drawHeadwear(in: &context, headwear: loadout.headwear)
    }

    // MARK: - Pop Faces (IMG_7093.JPG)

    private static func drawShockedPopFace(in context: inout GraphicsContext) {
        for x in [47.0, 81.0] {
            let rect = CGRect(x: x - 7.0, y: 49.0, width: 14.0, height: 15.0)
            let path = Path(ellipseIn: rect)
            context.fill(path, with: .color(.white.opacity(0.96)))
            context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
            let pupil = Path(ellipseIn: CGRect(x: x - 2.3, y: 54.5, width: 4.6, height: 4.6))
            context.fill(pupil, with: .color(ink))
        }
        let mouthRect = CGRect(x: 52.0, y: 66.5, width: 24.0, height: 21.0)
        let mouthPath = Path(ellipseIn: mouthRect)
        context.fill(mouthPath, with: .color(Color(red: 1.0, green: 0.72, blue: 0.78).opacity(0.75)))
        context.stroke(mouthPath, with: .color(ink), style: StrokeStyle(lineWidth: 3.0, lineCap: .round))
    }

    private static func drawStrainingPopFace(in context: inout GraphicsContext, blowing: Bool) {
        drawSqueezedEye(in: &context, centerX: 46.5, centerY: 57.5, pointingRight: true)
        drawSqueezedEye(in: &context, centerX: 81.5, centerY: 57.5, pointingRight: false)

        if blowing {
            let pucker = Path(ellipseIn: CGRect(x: 59.5, y: 69.0, width: 9.0, height: 7.5))
            context.fill(pucker, with: .color(Color(red: 1.0, green: 0.68, blue: 0.76).opacity(0.75)))
            context.stroke(pucker, with: .color(ink), style: StrokeStyle(lineWidth: 2.6))
        } else {
            var squiggle = Path()
            let points: [CGPoint] = [
                CGPoint(x: 52.0, y: 72.5),
                CGPoint(x: 56.5, y: 69.5),
                CGPoint(x: 61.0, y: 74.5),
                CGPoint(x: 64.5, y: 69.5),
                CGPoint(x: 68.5, y: 74.5),
                CGPoint(x: 73.0, y: 69.5),
                CGPoint(x: 76.5, y: 72.5)
            ]
            squiggle.move(to: points[0])
            for pt in points.dropFirst() {
                squiggle.addLine(to: pt)
            }
            context.stroke(squiggle, with: .color(ink), style: StrokeStyle(lineWidth: 2.7, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: - Eyes & Mouth

    private static func shouldBlink(for expression: BubbleExpression) -> Bool {
        switch expression {
        case .smile, .catMouth, .starry, .pout, .heartEyes, .cool, .royalSparkle, .poppedSurprise, .mischievous:
            return true
        case .classic, .sleepy, .winkLeft, .squeezed, .shy, .relaxed, .dreamy, .laughing, .partyPop:
            return false
        }
    }

    private static func drawBlush(in context: inout GraphicsContext, opacity: Double, showShyLines: Bool) {
        for x in [37.0, 91.0] {
            let blush = Path(ellipseIn: CGRect(x: x - 12, y: 64, width: 24, height: 15))
            context.fill(
                blush,
                with: .radialGradient(
                    Gradient(colors: [.pink.opacity(opacity), .clear]),
                    center: CGPoint(x: x, y: 71),
                    startRadius: 0,
                    endRadius: 12
                )
            )
            if showShyLines {
                for dx in [-4.5, 0.0, 4.5] {
                    var line = Path()
                    line.move(to: CGPoint(x: x + dx - 1.5, y: 72.5))
                    line.addLine(to: CGPoint(x: x + dx + 1.5, y: 67.5))
                    context.stroke(line, with: .color(.pink.opacity(0.62)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                }
            }
        }
    }

    private static func drawMakeup(in context: inout GraphicsContext, makeup: BubbleMakeup) {
        switch makeup {
        case .none:
            return

        case .rosyCheeks:
            for x in [35.0, 93.0] {
                let cheek = Path(ellipseIn: CGRect(x: x - 11.5, y: 63.5, width: 23, height: 14))
                context.fill(
                    cheek,
                    with: .radialGradient(
                        Gradient(colors: [Color(red: 1.0, green: 0.36, blue: 0.56).opacity(0.42), .clear]),
                        center: CGPoint(x: x, y: 70.5),
                        startRadius: 0,
                        endRadius: 11.5
                    )
                )
            }
            for x in [31.0, 97.0] {
                let shine = Path(ellipseIn: CGRect(x: x - 2.0, y: 68.2, width: 4.0, height: 2.3))
                context.fill(shine, with: .color(.white.opacity(0.86)))
            }
            for x in [36.5, 91.5] {
                let dot = Path(ellipseIn: CGRect(x: x - 1.1, y: 70.5, width: 2.2, height: 2.2))
                context.fill(dot, with: .color(.white.opacity(0.82)))
            }

        case .freckles:
            let freckleCol = Color(red: 0.62, green: 0.38, blue: 0.24).opacity(0.72)
            let dots: [(Double, Double, Double)] = [
                (34, 67.5, 1.3), (38.5, 69.5, 1.4), (42.5, 67.0, 1.2), (36, 72.0, 1.2), (40.5, 72.2, 1.3),
                (85.5, 67.0, 1.2), (89.5, 69.5, 1.4), (94, 67.5, 1.3), (87.5, 72.2, 1.3), (92, 72.0, 1.2),
                (60.5, 65.0, 1.1), (67.5, 65.0, 1.1)
            ]
            for (x, y, r) in dots {
                context.fill(
                    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                    with: .color(freckleCol)
                )
            }

        case .glitterTears:
            let aqua = Color(red: 0.56, green: 0.90, blue: 1.0)
            let rose = Color(red: 1.0, green: 0.72, blue: 0.88)
            for cx in [46.0, 81.0] {
                drawFourPointSparkle(in: &context, center: CGPoint(x: cx, y: 67.8), radius: 3.4, color: .white.opacity(0.95))
                let dropA = Path(ellipseIn: CGRect(x: cx - 5.2, y: 68.5, width: 2.8, height: 3.6))
                context.fill(dropA, with: .color(aqua.opacity(0.88)))
                let dropB = Path(ellipseIn: CGRect(x: cx + 2.8, y: 69.5, width: 2.4, height: 3.0))
                context.fill(dropB, with: .color(rose.opacity(0.88)))
            }

        case .starStamps:
            let gold = Color(red: 1.0, green: 0.80, blue: 0.22)
            let sky = Color(red: 0.42, green: 0.82, blue: 1.0)
            let leftStar = fivePointStarPath(center: CGPoint(x: 34.5, y: 70.5), outerRadius: 4.5, innerRadius: 2.1)
            context.fill(leftStar, with: .color(gold.opacity(0.94)))
            context.stroke(leftStar, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 0.8, lineJoin: .round))
            let rightStar = fivePointStarPath(center: CGPoint(x: 93.5, y: 70.5), outerRadius: 4.5, innerRadius: 2.1)
            context.fill(rightStar, with: .color(sky.opacity(0.94)))
            context.stroke(rightStar, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 0.8, lineJoin: .round))
            for pt in [CGPoint(x: 40.5, y: 68.0), CGPoint(x: 87.5, y: 68.0)] {
                context.fill(Path(ellipseIn: CGRect(x: pt.x - 1.3, y: pt.y - 1.3, width: 2.6, height: 2.6)), with: .color(.white.opacity(0.92)))
            }

        case .goldHighlighter:
            let glowPoints: [(Double, Double, Double)] = [
                (64.0, 62.5, 9.0), (35.0, 66.0, 10.0), (93.0, 66.0, 10.0)
            ]
            for (x, y, rad) in glowPoints {
                let oval = Path(ellipseIn: CGRect(x: x - rad, y: y - rad * 0.55, width: rad * 2, height: rad * 1.1))
                context.fill(
                    oval,
                    with: .radialGradient(
                        Gradient(colors: [Color(red: 1.0, green: 0.94, blue: 0.64).opacity(0.62), .clear]),
                        center: CGPoint(x: x, y: y),
                        startRadius: 0,
                        endRadius: rad
                    )
                )
            }
            for (pt, rad) in [(CGPoint(x: 31, y: 64.5), 3.3), (CGPoint(x: 97, y: 64.5), 3.3), (CGPoint(x: 64, y: 60.0), 2.8)] {
                drawFourPointSparkle(in: &context, center: pt, radius: rad, color: .white.opacity(0.96))
            }

        case .milkyWayGlow:
            var veil = Path()
            veil.move(to: CGPoint(x: 24, y: 73.5))
            veil.addQuadCurve(to: CGPoint(x: 104, y: 61.5), control: CGPoint(x: 64, y: 69.5))
            let galaxyShading: GraphicsContext.Shading = .linearGradient(
                Gradient(colors: [
                    Color(red: 0.44, green: 0.86, blue: 1.0).opacity(0.45),
                    Color(red: 0.80, green: 0.64, blue: 1.0).opacity(0.48),
                    Color(red: 1.0, green: 0.70, blue: 0.90).opacity(0.42)
                ]),
                startPoint: CGPoint(x: 24, y: 74),
                endPoint: CGPoint(x: 104, y: 61)
            )
            context.stroke(veil, with: galaxyShading, style: StrokeStyle(lineWidth: 9.5, lineCap: .round))

            let dust: [(Double, Double, Double, Color)] = [
                (28, 72.5, 1.3, .white),
                (36, 70.0, 1.1, Color(red: 0.72, green: 0.96, blue: 1.0)),
                (44, 71.2, 1.4, Color(red: 1.0, green: 0.93, blue: 0.68)),
                (53, 68.5, 1.0, .white),
                (60, 67.2, 1.2, Color(red: 1.0, green: 0.78, blue: 0.92)),
                (68, 66.8, 1.3, .white),
                (76, 65.4, 1.1, Color(red: 0.72, green: 0.96, blue: 1.0)),
                (85, 64.2, 1.4, Color(red: 1.0, green: 0.94, blue: 0.70)),
                (94, 62.0, 1.2, .white),
                (100, 62.6, 1.0, Color(red: 0.86, green: 0.92, blue: 1.0))
            ]
            for (x, y, r, col) in dust {
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(col.opacity(0.95)))
            }
            drawFourPointSparkle(in: &context, center: CGPoint(x: 33, y: 71.5), radius: 3.6, color: .white.opacity(0.96))
            drawFourPointSparkle(in: &context, center: CGPoint(x: 64, y: 67.2), radius: 3.1, color: Color(red: 1.0, green: 0.94, blue: 0.66))
            drawFourPointSparkle(in: &context, center: CGPoint(x: 94, y: 63.0), radius: 3.8, color: .white.opacity(0.96))

        case .heartStamps:
            for x in [34.5, 93.5] {
                let h = heartPath(center: CGPoint(x: x, y: 70.8), size: 7.4)
                context.fill(h, with: .color(Color(red: 0.98, green: 0.34, blue: 0.56).opacity(0.92)))
                context.stroke(h, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 0.9, lineJoin: .round))
            }

        case .sakuraPetals:
            for (x, deg) in [(34.0, -24.0), (94.0, 24.0)] {
                var ctx = context
                ctx.translateBy(x: x, y: 70.5)
                ctx.rotate(by: .degrees(deg))
                for angle in [0.0, 72.0, 144.0, 216.0, 288.0] {
                    var pCtx = ctx
                    pCtx.rotate(by: .degrees(angle))
                    let petal = Path(ellipseIn: CGRect(x: -1.5, y: -5.2, width: 3.0, height: 4.2))
                    pCtx.fill(petal, with: .color(Color(red: 1.0, green: 0.72, blue: 0.85).opacity(0.92)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: -1.4, y: -1.4, width: 2.8, height: 2.8)), with: .color(Color(red: 1.0, green: 0.86, blue: 0.36)))
            }

        case .snowCrystals:
            for x in [34.5, 93.5] {
                let glow = Path(ellipseIn: CGRect(x: x - 8, y: 65, width: 16, height: 11))
                context.fill(glow, with: .color(Color(red: 0.72, green: 0.90, blue: 1.0).opacity(0.28)))
            }
            let cx = 93.5
            let cy = 70.0
            for i in 0..<3 {
                let rad = Double(i) * (.pi / 3.0)
                var ray = Path()
                ray.move(to: CGPoint(x: cx - cos(rad) * 4.5, y: cy - sin(rad) * 4.5))
                ray.addLine(to: CGPoint(x: cx + cos(rad) * 4.5, y: cy + sin(rad) * 4.5))
                context.stroke(ray, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }
            for pt in [CGPoint(x: 34.5, y: 70.5), CGPoint(x: 38.5, y: 68.5)] {
                context.fill(Path(ellipseIn: CGRect(x: pt.x - 1.5, y: pt.y - 1.5, width: 3.0, height: 3.0)), with: .color(.white.opacity(0.92)))
            }

        case .pastelConfetti:
            let bits: [(Double, Double, Double, Color)] = [
                (31, 69, 1.8, Color(red: 1.0, green: 0.68, blue: 0.84)),
                (36, 72, 1.6, Color(red: 1.0, green: 0.92, blue: 0.48)),
                (40, 68, 1.7, Color(red: 0.56, green: 0.92, blue: 0.80)),
                (88, 68, 1.7, Color(red: 0.74, green: 0.70, blue: 1.0)),
                (92, 72, 1.6, Color(red: 1.0, green: 0.68, blue: 0.84)),
                (97, 69, 1.8, Color(red: 1.0, green: 0.92, blue: 0.48))
            ]
            for (x, y, r, col) in bits {
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(col.opacity(0.94)))
            }

        case .spookyMoon:
            var moon = Path()
            moon.addArc(center: CGPoint(x: 34.5, y: 70.5), radius: 4.2, startAngle: .degrees(40), endAngle: .degrees(320), clockwise: false)
            moon.addQuadCurve(to: CGPoint(x: 37.7, y: 73.2), control: CGPoint(x: 33.2, y: 70.5))
            moon.closeSubpath()
            context.fill(moon, with: .color(Color(red: 1.0, green: 0.82, blue: 0.28).opacity(0.94)))
            drawFourPointSparkle(
                in: &context,
                center: CGPoint(x: 93.5, y: 70.5),
                radius: 4.0,
                color: Color(red: 0.62, green: 0.36, blue: 0.90).opacity(0.90)
            )
        }
    }

    private static func drawOpenEye(in context: inout GraphicsContext, centerX: Double, centerY: Double) {
        let eye = Path(
            roundedRect: CGRect(x: centerX - 4.4, y: centerY - 5.5, width: 8.8, height: 11.2),
            cornerSize: CGSize(width: 4.4, height: 4.4)
        )
        context.fill(eye, with: .color(ink))
        let primary = Path(ellipseIn: CGRect(x: centerX - 2.3, y: centerY - 3.7, width: 3.2, height: 3.2))
        context.fill(primary, with: .color(.white.opacity(0.95)))
        let secondary = Path(ellipseIn: CGRect(x: centerX + 0.6, y: centerY + 1.0, width: 1.7, height: 1.7))
        context.fill(secondary, with: .color(.white.opacity(0.85)))
    }

    private static func drawSmallDotEye(in context: inout GraphicsContext, centerX: Double, centerY: Double) {
        let eye = Path(ellipseIn: CGRect(x: centerX - 3.5, y: centerY - 3.6, width: 7.0, height: 7.4))
        context.fill(eye, with: .color(ink))
        let glint = Path(ellipseIn: CGRect(x: centerX - 1.6, y: centerY - 2.1, width: 2.2, height: 2.2))
        context.fill(glint, with: .color(.white.opacity(0.9)))
    }

    private static func drawSurprisedRoundEye(in context: inout GraphicsContext, centerX: Double, centerY: Double) {
        let outer = Path(ellipseIn: CGRect(x: centerX - 5.8, y: centerY - 6.2, width: 11.6, height: 12.4))
        context.fill(outer, with: .color(.white.opacity(0.95)))
        context.stroke(outer, with: .color(ink), style: StrokeStyle(lineWidth: 2.4))
        let pupil = Path(ellipseIn: CGRect(x: centerX - 2.2, y: centerY - 2.2, width: 4.4, height: 4.4))
        context.fill(pupil, with: .color(ink))
    }

    private static func drawClosedEyeArc(in context: inout GraphicsContext, centerX: Double, y: Double, downward: Bool) {
        var arc = Path()
        arc.move(to: CGPoint(x: centerX - 6, y: y))
        arc.addQuadCurve(
            to: CGPoint(x: centerX + 6, y: y),
            control: CGPoint(x: centerX, y: downward ? y + 7 : y - 8)
        )
        context.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
    }

    private static func drawWinkRightFacingEye(in context: inout GraphicsContext, centerX: Double, centerY: Double) {
        var path = Path()
        path.move(to: CGPoint(x: centerX - 5.2, y: centerY - 4.0))
        path.addLine(to: CGPoint(x: centerX + 4.8, y: centerY))
        path.addLine(to: CGPoint(x: centerX - 5.2, y: centerY + 4.0))
        context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
    }

    private static func drawSqueezedEye(in context: inout GraphicsContext, centerX: Double, centerY: Double, pointingRight: Bool) {
        let tipX = pointingRight ? centerX + 4.8 : centerX - 4.8
        let outerX = pointingRight ? centerX - 5.2 : centerX + 5.2
        var path = Path()
        path.move(to: CGPoint(x: outerX, y: centerY - 4.4))
        path.addLine(to: CGPoint(x: tipX, y: centerY))
        path.addLine(to: CGPoint(x: outerX, y: centerY + 4.4))
        context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 2.9, lineCap: .round, lineJoin: .round))
    }

    private static func drawStarryEye(in context: inout GraphicsContext, centerX: Double, centerY: Double) {
        let eye = Path(ellipseIn: CGRect(x: centerX - 5.6, y: centerY - 5.8, width: 11.2, height: 11.6))
        context.fill(eye, with: .color(ink))
        drawFourPointSparkle(in: &context, center: CGPoint(x: centerX + 1.2, y: centerY - 1.4), radius: 3.4, color: .white)
        let dot = Path(ellipseIn: CGRect(x: centerX - 2.8, y: centerY + 1.3, width: 2.2, height: 2.2))
        context.fill(dot, with: .color(.white.opacity(0.88)))
    }

    private static func drawHeartEye(in context: inout GraphicsContext, centerX: Double, centerY: Double) {
        let heart = heartPath(center: CGPoint(x: centerX, y: centerY + 0.8), size: 12.2)
        context.fill(heart, with: .color(Color(red: 0.94, green: 0.34, blue: 0.54)))
        context.stroke(heart, with: .color(ink.opacity(0.72)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        let shine = Path(ellipseIn: CGRect(x: centerX - 3.3, y: centerY - 2.7, width: 2.5, height: 2.2))
        context.fill(shine, with: .color(.white.opacity(0.85)))
    }

    private static func drawCoolEye(in context: inout GraphicsContext, centerX: Double, centerY: Double) {
        let eye = Path(roundedRect: CGRect(x: centerX - 4.6, y: centerY - 2.6, width: 9.2, height: 6.4), cornerRadius: 3.2)
        context.fill(eye, with: .color(ink))
        var lid = Path()
        lid.move(to: CGPoint(x: centerX - 6.0, y: centerY - 3.0))
        lid.addLine(to: CGPoint(x: centerX + 6.0, y: centerY - 3.0))
        context.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        let glint = Path(ellipseIn: CGRect(x: centerX - 2.0, y: centerY - 1.5, width: 2.4, height: 2.0))
        context.fill(glint, with: .color(.white.opacity(0.92)))
    }

    private static func drawDreamyEye(in context: inout GraphicsContext, centerX: Double, centerY: Double) {
        var arc = Path()
        arc.move(to: CGPoint(x: centerX - 6.0, y: centerY - 0.5))
        arc.addQuadCurve(to: CGPoint(x: centerX + 6.0, y: centerY - 0.5), control: CGPoint(x: centerX, y: centerY + 6.0))
        context.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        let lashOffsets: [(Double, Double)] = [(-5.4, -3.5), (5.4, 3.5)]
        for (startDX, endDX) in lashOffsets {
            var lash = Path()
            lash.move(to: CGPoint(x: centerX + startDX, y: centerY + 1.0))
            lash.addLine(to: CGPoint(x: centerX + endDX * 1.35, y: centerY + 3.2))
            context.stroke(lash, with: .color(ink), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
        }
    }

    private static func drawMischievousEye(in context: inout GraphicsContext, centerX: Double, centerY: Double) {
        let sclera = Path(roundedRect: CGRect(x: centerX - 5.2, y: centerY - 3.0, width: 10.4, height: 7.4), cornerRadius: 3.7)
        context.fill(sclera, with: .color(.white.opacity(0.92)))
        context.stroke(sclera, with: .color(ink), style: StrokeStyle(lineWidth: 2.1))
        let pupil = Path(ellipseIn: CGRect(x: centerX - 0.5, y: centerY - 2.0, width: 4.8, height: 5.2))
        context.fill(pupil, with: .color(ink))
        let glint = Path(ellipseIn: CGRect(x: centerX + 0.5, y: centerY - 1.2, width: 1.7, height: 1.7))
        context.fill(glint, with: .color(.white.opacity(0.95)))
        var brow = Path()
        brow.move(to: CGPoint(x: centerX - 6.0, y: centerY - 4.4))
        brow.addLine(to: CGPoint(x: centerX + 6.0, y: centerY - 3.6))
        context.stroke(brow, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }

    private static func drawMouth(in context: inout GraphicsContext, expression: BubbleExpression) {
        switch expression {
        case .catMouth:
            var left = Path()
            left.move(to: CGPoint(x: 56.5, y: 69.0))
            left.addQuadCurve(to: CGPoint(x: 63.5, y: 69.5), control: CGPoint(x: 60.0, y: 74.5))
            var right = Path()
            right.move(to: CGPoint(x: 63.5, y: 69.5))
            right.addQuadCurve(to: CGPoint(x: 70.5, y: 69.0), control: CGPoint(x: 67.0, y: 74.5))
            let style = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            context.stroke(left, with: .color(ink), style: style)
            context.stroke(right, with: .color(ink), style: style)
        case .pout:
            var mouth = Path()
            mouth.move(to: CGPoint(x: 59.0, y: 72.5))
            mouth.addQuadCurve(to: CGPoint(x: 68.0, y: 72.5), control: CGPoint(x: 63.5, y: 68.5))
            context.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        case .laughing, .heartEyes, .partyPop:
            var openMouth = Path()
            openMouth.move(to: CGPoint(x: 56.0, y: 68.5))
            openMouth.addLine(to: CGPoint(x: 71.0, y: 68.5))
            openMouth.addQuadCurve(to: CGPoint(x: 56.0, y: 68.5), control: CGPoint(x: 63.5, y: 80.5))
            openMouth.closeSubpath()
            context.fill(openMouth, with: .color(Color(red: 0.96, green: 0.48, blue: 0.60)))
            context.stroke(openMouth, with: .color(ink), style: StrokeStyle(lineWidth: 2.3, lineJoin: .round))
        case .mischievous:
            var smirk = Path()
            smirk.move(to: CGPoint(x: 55.5, y: 70.0))
            smirk.addQuadCurve(to: CGPoint(x: 71.5, y: 68.2), control: CGPoint(x: 64.0, y: 75.5))
            context.stroke(smirk, with: .color(ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            var tongue = Path()
            tongue.move(to: CGPoint(x: 64.5, y: 71.5))
            tongue.addCurve(
                to: CGPoint(x: 69.8, y: 70.0),
                control1: CGPoint(x: 65.0, y: 78.8),
                control2: CGPoint(x: 70.6, y: 77.5)
            )
            tongue.closeSubpath()
            context.fill(tongue, with: .color(Color(red: 1.0, green: 0.56, blue: 0.70)))
            context.stroke(tongue, with: .color(ink), style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))
        case .poppedSurprise:
            let circle = Path(ellipseIn: CGRect(x: 59.5, y: 68.0, width: 9.0, height: 10.0))
            context.fill(circle, with: .color(Color(red: 1.0, green: 0.66, blue: 0.74).opacity(0.85)))
            context.stroke(circle, with: .color(ink), style: StrokeStyle(lineWidth: 2.4))
        case .cool:
            var smirk = Path()
            smirk.move(to: CGPoint(x: 58.5, y: 71.5))
            smirk.addQuadCurve(to: CGPoint(x: 69.5, y: 68.8), control: CGPoint(x: 65.0, y: 72.5))
            context.stroke(smirk, with: .color(ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        case .smile:
            var mouth = Path()
            mouth.move(to: CGPoint(x: 55.5, y: 68.5))
            mouth.addQuadCurve(to: CGPoint(x: 71.5, y: 68.5), control: CGPoint(x: 63.5, y: 77.5))
            context.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
        default:
            var mouth = Path()
            mouth.move(to: CGPoint(x: 57, y: 69))
            mouth.addQuadCurve(to: CGPoint(x: 69, y: 69), control: CGPoint(x: 63, y: 76))
            context.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
        }
    }

    // MARK: - Face Accessories (Eyebrows, Facial Hair, Moles)

    private static func drawFaceAccessories(in context: inout GraphicsContext, loadout: BubbleDecorationLoadout) {
        drawEyebrows(in: &context, eyebrows: loadout.eyebrows)
        drawFacialHair(in: &context, hair: loadout.facialHair)
        drawMoles(in: &context, moles: loadout.moles)
    }

    private static func drawEyebrows(in context: inout GraphicsContext, eyebrows: BubbleEyebrows) {
        switch eyebrows {
        case .none:
            return
        case .soft:
            for (index, x) in [46.0, 81.0].enumerated() {
                var path = Path()
                let tilt = index == 0 ? -0.6 : 0.6
                path.move(to: CGPoint(x: x - 6.0, y: 48.0 - tilt))
                path.addQuadCurve(to: CGPoint(x: x + 6.0, y: 48.0 + tilt), control: CGPoint(x: x, y: 44.5))
                context.stroke(path, with: .color(ink.opacity(0.84)), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
            }
        case .thick:
            for (index, x) in [46.0, 81.0].enumerated() {
                var brow = context
                brow.translateBy(x: x, y: 47.0)
                brow.rotate(by: .degrees(index == 0 ? -5 : 5))
                let pill = Path(roundedRect: CGRect(x: -7.0, y: -2.2, width: 14.0, height: 4.4), cornerRadius: 2.2)
                brow.fill(pill, with: .color(ink.opacity(0.9)))
            }
        case .arched:
            for (index, x) in [46.0, 81.0].enumerated() {
                var path = Path()
                let innerLift = index == 0 ? 1.5 : -1.5
                path.move(to: CGPoint(x: x - 6.5, y: 48.5 - innerLift))
                path.addLine(to: CGPoint(x: x + 6.5, y: 48.5 + innerLift))
                context.stroke(path, with: .color(ink.opacity(0.9)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
        case .worried:
            for (index, x) in [46.0, 81.0].enumerated() {
                var path = Path()
                let outerDrop = index == 0 ? -2.2 : 2.2
                path.move(to: CGPoint(x: x - 6.2, y: 47.5 - outerDrop))
                path.addQuadCurve(to: CGPoint(x: x + 6.2, y: 47.5 + outerDrop), control: CGPoint(x: x, y: 44.8))
                context.stroke(path, with: .color(ink.opacity(0.86)), style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
            }
        }
    }

    private static func drawFacialHair(in context: inout GraphicsContext, hair: BubbleFacialHair) {
        switch hair {
        case .none:
            return
        case .catWhiskers:
            let style = StrokeStyle(lineWidth: 1.7, lineCap: .round)
            for side in [-1.0, 1.0] {
                let startX = 64.0 + side * 26.0
                let endX = 64.0 + side * 43.0
                for (index, yOff) in [-4.5, 0.5, 5.5].enumerated() {
                    var line = Path()
                    line.move(to: CGPoint(x: startX, y: 66.5 + yOff))
                    line.addLine(to: CGPoint(x: endX, y: 66.5 + yOff + Double(index - 1) * 2.4))
                    context.stroke(line, with: .color(ink.opacity(0.75)), style: style)
                }
            }
        case .gentlemanMustache:
            for side in [-1.0, 1.0] {
                var curl = Path()
                curl.move(to: CGPoint(x: 63.5, y: 66.5))
                curl.addCurve(
                    to: CGPoint(x: 63.5 + side * 14.5, y: 64.5),
                    control1: CGPoint(x: 63.5 + side * 5.0, y: 63.0),
                    control2: CGPoint(x: 63.5 + side * 11.0, y: 68.8)
                )
                context.stroke(curl, with: .color(ink), style: StrokeStyle(lineWidth: 3.0, lineCap: .round))
            }
        case .fullBeard:
            drawBeardBase(in: &context, fill: Color.white.opacity(0.88), stroke: ink.opacity(0.65), fluffy: false)
        case .santaBeard:
            drawBeardBase(in: &context, fill: Color.white.opacity(0.96), stroke: Color(red: 0.78, green: 0.84, blue: 0.92), fluffy: true)
        }
    }

    private static func drawBeardBase(in context: inout GraphicsContext, fill: Color, stroke: Color, fluffy: Bool) {
        var beard = Path()
        beard.move(to: CGPoint(x: 34.0, y: 68.0))
        beard.addQuadCurve(to: CGPoint(x: 42.0, y: fluffy ? 96.0 : 92.0), control: CGPoint(x: 31.0, y: 85.0))
        beard.addQuadCurve(to: CGPoint(x: 64.0, y: fluffy ? 109.0 : 103.5), control: CGPoint(x: 50.0, y: fluffy ? 108.0 : 103.0))
        beard.addQuadCurve(to: CGPoint(x: 86.0, y: fluffy ? 96.0 : 92.0), control: CGPoint(x: 78.0, y: fluffy ? 108.0 : 103.0))
        beard.addQuadCurve(to: CGPoint(x: 94.0, y: 68.0), control: CGPoint(x: 97.0, y: 85.0))
        beard.addQuadCurve(to: CGPoint(x: 76.0, y: 78.5), control: CGPoint(x: 86.0, y: 78.0))
        beard.addQuadCurve(to: CGPoint(x: 64.0, y: 76.0), control: CGPoint(x: 70.0, y: 74.0))
        beard.addQuadCurve(to: CGPoint(x: 52.0, y: 78.5), control: CGPoint(x: 58.0, y: 74.0))
        beard.addQuadCurve(to: CGPoint(x: 34.0, y: 68.0), control: CGPoint(x: 42.0, y: 78.0))
        beard.closeSubpath()
        context.fill(beard, with: .color(fill))
        context.stroke(beard, with: .color(stroke), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        if fluffy {
            for side in [-1.0, 1.0] {
                let puff = Path(ellipseIn: CGRect(x: 64.0 + side * 7.5 - 6.0, y: 65.5, width: 12.0, height: 6.8))
                context.fill(puff, with: .color(.white.opacity(0.98)))
                context.stroke(puff, with: .color(stroke), style: StrokeStyle(lineWidth: 1.4))
            }
        }
    }

    private static func drawMoles(in context: inout GraphicsContext, moles: Set<BubbleMole>) {
        for mole in BubbleMole.allCases where moles.contains(mole) {
            let point: CGPoint? = switch mole {
            case .none: nil
            case .underLeftEye: CGPoint(x: 41.5, y: 66.0)
            case .underRightEye: CGPoint(x: 86.0, y: 66.0)
            case .nearMouth: CGPoint(x: 73.0, y: 73.5)
            case .cheek: CGPoint(x: 90.0, y: 71.0)
            }
            guard let point else { continue }
            let dot = Path(ellipseIn: CGRect(x: point.x - 1.7, y: point.y - 1.7, width: 3.4, height: 3.4))
            context.fill(dot, with: .color(ink.opacity(0.9)))
        }
    }

    // MARK: - Eyewear

    private static func drawEyewear(in context: inout GraphicsContext, eyewear: BubbleEyewear) {
        switch eyewear {
        case .none:
            return
        case .roundGlasses:
            let frameColor = Color(red: 0.36, green: 0.25, blue: 0.20)
            for x in [46.0, 81.0] {
                let lens = Path(ellipseIn: CGRect(x: x - 11.5, y: 47.5, width: 23.0, height: 22.0))
                context.fill(lens, with: .color(Color.white.opacity(0.18)))
                context.stroke(lens, with: .color(frameColor), style: StrokeStyle(lineWidth: 2.2))
                drawLensGlint(in: &context, centerX: x, centerY: 58.0)
            }
            var bridge = Path()
            bridge.move(to: CGPoint(x: 57.5, y: 57.5))
            bridge.addQuadCurve(to: CGPoint(x: 69.5, y: 57.5), control: CGPoint(x: 63.5, y: 54.5))
            context.stroke(bridge, with: .color(frameColor), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        case .squareGlasses:
            for x in [46.0, 81.0] {
                let lens = Path(roundedRect: CGRect(x: x - 12.2, y: 48.5, width: 24.4, height: 19.5), cornerRadius: 5.5)
                context.fill(lens, with: .color(Color.white.opacity(0.16)))
                context.stroke(lens, with: .color(ink), style: StrokeStyle(lineWidth: 2.4))
                drawLensGlint(in: &context, centerX: x, centerY: 58.0)
            }
            var bridge = Path()
            bridge.move(to: CGPoint(x: 58.2, y: 56.0))
            bridge.addLine(to: CGPoint(x: 68.8, y: 56.0))
            context.stroke(bridge, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        case .heartGlasses:
            let framePink = Color(red: 0.94, green: 0.42, blue: 0.62)
            for x in [46.0, 81.0] {
                let heart = heartPath(center: CGPoint(x: x, y: 59.0), size: 22.0)
                context.fill(heart, with: .color(Color(red: 1.0, green: 0.78, blue: 0.88).opacity(0.32)))
                context.stroke(heart, with: .color(framePink), style: StrokeStyle(lineWidth: 2.3, lineJoin: .round))
            }
            var bridge = Path()
            bridge.move(to: CGPoint(x: 57.0, y: 56.5))
            bridge.addLine(to: CGPoint(x: 70.0, y: 56.5))
            context.stroke(bridge, with: .color(framePink), style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
        case .sunglasses:
            for x in [46.0, 81.0] {
                let lens = Path(roundedRect: CGRect(x: x - 13.0, y: 48.5, width: 26.0, height: 20.0), cornerRadius: 7.5)
                context.fill(
                    lens,
                    with: .linearGradient(
                        Gradient(colors: [Color(red: 0.16, green: 0.19, blue: 0.34).opacity(0.90), Color(red: 0.28, green: 0.32, blue: 0.50).opacity(0.84)]),
                        startPoint: CGPoint(x: x - 12, y: 48),
                        endPoint: CGPoint(x: x + 12, y: 68)
                    )
                )
                context.stroke(lens, with: .color(.white.opacity(0.92)), style: StrokeStyle(lineWidth: 2.1))
                drawLensGlint(in: &context, centerX: x, centerY: 58.0)
            }
            var bridge = Path()
            bridge.move(to: CGPoint(x: 59.0, y: 54.5))
            bridge.addLine(to: CGPoint(x: 68.0, y: 54.5))
            context.stroke(bridge, with: .color(.white.opacity(0.92)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        case .starGlasses:
            let goldFrame = Color(red: 0.94, green: 0.72, blue: 0.18)
            let goldStroke = Color(red: 0.68, green: 0.44, blue: 0.08)
            for x in [46.0, 81.0] {
                let star = fivePointStarPath(center: CGPoint(x: x, y: 58.0), outerRadius: 12.6, innerRadius: 6.0)
                context.fill(star, with: .color(Color(red: 1.0, green: 0.94, blue: 0.68).opacity(0.38)))
                context.stroke(star, with: .color(goldStroke), style: StrokeStyle(lineWidth: 2.1, lineJoin: .round))
                context.stroke(star, with: .color(goldFrame), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            }
            var bridge = Path()
            bridge.move(to: CGPoint(x: 57.0, y: 57.0))
            bridge.addLine(to: CGPoint(x: 70.0, y: 57.0))
            context.stroke(bridge, with: .color(goldStroke), style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
        case .grouchoGlasses:
            let frameDark = Color(red: 0.16, green: 0.17, blue: 0.24)
            for x in [46.0, 81.0] {
                let lens = Path(ellipseIn: CGRect(x: x - 11.5, y: 48.0, width: 23.0, height: 20.5))
                context.fill(lens, with: .color(Color.white.opacity(0.16)))
                context.stroke(lens, with: .color(frameDark), style: StrokeStyle(lineWidth: 2.8))
                let brow = Path(roundedRect: CGRect(x: x - 10.5, y: 43.0, width: 21.0, height: 4.5), cornerRadius: 2.2)
                context.fill(brow, with: .color(frameDark))
            }
            var bridge = Path()
            bridge.move(to: CGPoint(x: 57.5, y: 56.5))
            bridge.addLine(to: CGPoint(x: 69.5, y: 56.5))
            context.stroke(bridge, with: .color(frameDark), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            let nose = Path(ellipseIn: CGRect(x: 57.0, y: 56.5, width: 14.0, height: 12.5))
            context.fill(nose, with: .color(Color(red: 0.98, green: 0.42, blue: 0.46)))
            context.stroke(nose, with: .color(Color(red: 0.68, green: 0.20, blue: 0.26)), style: StrokeStyle(lineWidth: 1.5))
            var stache = Path()
            stache.move(to: CGPoint(x: 49.0, y: 71.5))
            stache.addQuadCurve(to: CGPoint(x: 64.0, y: 67.5), control: CGPoint(x: 55.0, y: 64.5))
            stache.addQuadCurve(to: CGPoint(x: 79.0, y: 71.5), control: CGPoint(x: 73.0, y: 64.5))
            stache.addQuadCurve(to: CGPoint(x: 64.0, y: 72.0), control: CGPoint(x: 71.5, y: 75.5))
            stache.addQuadCurve(to: CGPoint(x: 49.0, y: 71.5), control: CGPoint(x: 56.5, y: 75.5))
            stache.closeSubpath()
            context.fill(stache, with: .color(frameDark))
        }
    }

    private static func drawLensGlint(in context: inout GraphicsContext, centerX: Double, centerY: Double) {
        var glint = Path()
        glint.move(to: CGPoint(x: centerX - 6.0, y: centerY - 2.5))
        glint.addLine(to: CGPoint(x: centerX - 1.5, y: centerY - 6.8))
        context.stroke(glint, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
    }

    // MARK: - Ears

    private static func drawCatEars(in context: inout GraphicsContext, tintColor: Color, deepTintColor: Color) {
        let earConfigs: [(baseA: CGPoint, tip: CGPoint, baseB: CGPoint, innerCenter: CGPoint)] = [
            (CGPoint(x: 24, y: 31), CGPoint(x: 22, y: 3), CGPoint(x: 45, y: 17), CGPoint(x: 29, y: 18)),
            (CGPoint(x: 104, y: 31), CGPoint(x: 106, y: 3), CGPoint(x: 83, y: 17), CGPoint(x: 99, y: 18))
        ]
        for ear in earConfigs {
            var path = Path()
            path.move(to: ear.baseA)
            path.addQuadCurve(to: ear.tip, control: CGPoint(x: (ear.baseA.x + ear.tip.x) * 0.5 - 2, y: (ear.baseA.y + ear.tip.y) * 0.5))
            path.addQuadCurve(to: ear.baseB, control: CGPoint(x: (ear.tip.x + ear.baseB.x) * 0.5 + 1, y: (ear.tip.y + ear.baseB.y) * 0.5))
            path.closeSubpath()
            context.fill(path, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.9), tintColor.opacity(0.85)]), startPoint: ear.tip, endPoint: ear.baseA))
            context.stroke(path, with: .color(deepTintColor.opacity(0.65)), style: StrokeStyle(lineWidth: 2.0, lineJoin: .round))

            var inner = Path()
            inner.move(to: CGPoint(x: (ear.baseA.x + ear.innerCenter.x) * 0.5, y: (ear.baseA.y + ear.innerCenter.y) * 0.5))
            inner.addLine(to: CGPoint(x: (ear.tip.x + ear.innerCenter.x) * 0.5, y: (ear.tip.y + ear.innerCenter.y) * 0.5))
            inner.addLine(to: CGPoint(x: (ear.baseB.x + ear.innerCenter.x) * 0.5, y: (ear.baseB.y + ear.innerCenter.y) * 0.5))
            inner.closeSubpath()
            context.fill(inner, with: .color(Color(red: 1.0, green: 0.72, blue: 0.82).opacity(0.82)))
        }
    }

    private static func drawDogEars(in context: inout GraphicsContext) {
        let earColor = Color(red: 0.90, green: 0.74, blue: 0.58)
        let earStroke = Color(red: 0.64, green: 0.45, blue: 0.30)
        for side in [-1.0, 1.0] {
            var ear = context
            ear.translateBy(x: 64 + side * 47, y: 50)
            ear.rotate(by: .degrees(side * 16))
            let shape = Path(roundedRect: CGRect(x: -10.5, y: -16, width: 21, height: 38), cornerRadius: 10.5)
            ear.fill(
                shape,
                with: .linearGradient(
                    Gradient(colors: [earColor, earColor.opacity(0.75)]),
                    startPoint: CGPoint(x: 0, y: -16),
                    endPoint: CGPoint(x: 0, y: 22)
                )
            )
            ear.stroke(shape, with: .color(earStroke.opacity(0.75)), style: StrokeStyle(lineWidth: 2.0))
        }
    }

    private static func drawKoalaEars(in context: inout GraphicsContext) {
        let outerColor = Color(red: 0.76, green: 0.80, blue: 0.88)
        let strokeColor = Color(red: 0.46, green: 0.50, blue: 0.62)
        for side in [-1.0, 1.0] {
            let cx = 64 + side * 44
            let cy = 27.0
            let outer = Path(ellipseIn: CGRect(x: cx - 16, y: cy - 16, width: 32, height: 32))
            context.fill(outer, with: .color(outerColor.opacity(0.95)))
            context.stroke(outer, with: .color(strokeColor.opacity(0.7)), style: StrokeStyle(lineWidth: 2.0))
            let inner = Path(ellipseIn: CGRect(x: cx - 9, y: cy - 9, width: 18, height: 18))
            context.fill(inner, with: .color(Color.white.opacity(0.88)))
        }
    }

    private static func drawBunnyEars(in context: inout GraphicsContext, tintColor: Color, deepTintColor: Color) {
        for side in [-1.0, 1.0] {
            var ear = context
            ear.translateBy(x: 64 + side * 20, y: 12)
            ear.rotate(by: .degrees(side * 12))
            let outer = Path(ellipseIn: CGRect(x: -9.5, y: -26, width: 19, height: 36))
            ear.fill(
                outer,
                with: .linearGradient(
                    Gradient(colors: [Color.white, tintColor.opacity(0.85)]),
                    startPoint: CGPoint(x: 0, y: -26),
                    endPoint: CGPoint(x: 0, y: 10)
                )
            )
            ear.stroke(outer, with: .color(deepTintColor.opacity(0.65)), style: StrokeStyle(lineWidth: 2.0))
            let inner = Path(ellipseIn: CGRect(x: -5.0, y: -20, width: 10, height: 24))
            ear.fill(inner, with: .color(Color(red: 1.0, green: 0.74, blue: 0.84).opacity(0.82)))
        }
    }

    private static func drawBearEars(in context: inout GraphicsContext) {
        let outerColor = Color(red: 0.94, green: 0.78, blue: 0.60)
        let strokeColor = Color(red: 0.68, green: 0.49, blue: 0.30)
        for side in [-1.0, 1.0] {
            let cx = 64 + side * 35
            let cy = 20.0
            let outer = Path(ellipseIn: CGRect(x: cx - 13, y: cy - 13, width: 26, height: 26))
            context.fill(outer, with: .color(outerColor))
            context.stroke(outer, with: .color(strokeColor.opacity(0.72)), style: StrokeStyle(lineWidth: 2.0))
            let inner = Path(ellipseIn: CGRect(x: cx - 7, y: cy - 7, width: 14, height: 14))
            context.fill(inner, with: .color(Color(red: 1.0, green: 0.90, blue: 0.80)))
        }
    }

    // MARK: - Headwear

    private static func drawHeadwear(in context: inout GraphicsContext, headwear: BubbleHeadwear) {
        switch headwear {
        case .none:
            return
        case .ribbon:
            drawTopRibbon(in: &context)
        case .crown:
            drawCrown(in: &context)
        case .tiara:
            drawTiara(in: &context)
        case .santaHat:
            drawSantaHat(in: &context)
        case .snowmanHat:
            drawSnowmanHat(in: &context)
        case .flowerCrown:
            drawFlowerCrown(in: &context)
        case .strawHat:
            drawStrawHat(in: &context)
        case .beret:
            drawBeret(in: &context)
        case .heartHeadband:
            drawHeartHeadband(in: &context)
        case .partyHat:
            drawPartyHat(in: &context)
        case .witchHat:
            drawWitchHat(in: &context)
        case .newYearMikan:
            drawNewYearMikan(in: &context)
        case .oniHorns:
            drawOniHorns(in: &context)
        case .risingSunHeadband:
            drawRisingSunHeadband(in: &context)
        case .peachBlossom:
            drawPeachBlossom(in: &context)
        case .jesterHat:
            drawJesterHat(in: &context)
        case .easterEggHat:
            drawEasterEggHat(in: &context)
        case .samuraiKabuto:
            drawSamuraiKabuto(in: &context)
        case .frogRainHat:
            drawFrogRainHat(in: &context)
        case .tanabataStar:
            drawTanabataStar(in: &context)
        case .festivalMask:
            drawFestivalMask(in: &context)
        case .moonDango:
            drawMoonDango(in: &context)
        case .countdownSpark:
            drawCountdownSpark(in: &context)
        }
    }

    private static func drawTopRibbon(in context: inout GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: 37, y: 20)
        ctx.rotate(by: .degrees(-24))

        let ribbonMain = Color(red: 1.0, green: 0.48, blue: 0.66)
        let ribbonDark = Color(red: 0.80, green: 0.24, blue: 0.44)

        for side in [-1.0, 1.0] {
            var wing = Path()
            wing.move(to: .zero)
            wing.addCurve(
                to: CGPoint(x: side * 14, y: -6),
                control1: CGPoint(x: side * 6, y: -9),
                control2: CGPoint(x: side * 12, y: -9)
            )
            wing.addCurve(
                to: .zero,
                control1: CGPoint(x: side * 15, y: 5),
                control2: CGPoint(x: side * 6, y: 7)
            )
            wing.closeSubpath()
            ctx.fill(wing, with: .color(ribbonMain))
            ctx.stroke(wing, with: .color(ribbonDark.opacity(0.8)), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        }

        let knot = Path(ellipseIn: CGRect(x: -4, y: -4, width: 8, height: 8))
        ctx.fill(knot, with: .color(Color(red: 1.0, green: 0.72, blue: 0.82)))
        ctx.stroke(knot, with: .color(ribbonDark.opacity(0.85)), style: StrokeStyle(lineWidth: 1.6))
    }

    private static func drawCrown(in context: inout GraphicsContext) {
        var crown = Path()
        crown.move(to: CGPoint(x: 47, y: 15))
        crown.addLine(to: CGPoint(x: 44, y: 1))
        crown.addLine(to: CGPoint(x: 55, y: 8))
        crown.addLine(to: CGPoint(x: 64, y: -4))
        crown.addLine(to: CGPoint(x: 73, y: 8))
        crown.addLine(to: CGPoint(x: 84, y: 1))
        crown.addLine(to: CGPoint(x: 81, y: 15))
        crown.closeSubpath()

        context.fill(
            crown,
            with: .linearGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.94, blue: 0.62), Color(red: 0.96, green: 0.74, blue: 0.24)]),
                startPoint: CGPoint(x: 64, y: -4),
                endPoint: CGPoint(x: 64, y: 15)
            )
        )
        context.stroke(crown, with: .color(Color(red: 0.74, green: 0.49, blue: 0.12)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))

        let jewels: [(CGPoint, Color)] = [
            (CGPoint(x: 64, y: 9.5), Color(red: 0.96, green: 0.34, blue: 0.54)),
            (CGPoint(x: 52, y: 11.0), Color(red: 0.42, green: 0.78, blue: 1.0)),
            (CGPoint(x: 76, y: 11.0), Color(red: 0.42, green: 0.78, blue: 1.0))
        ]
        for (pt, color) in jewels {
            let gem = Path(ellipseIn: CGRect(x: pt.x - 2.1, y: pt.y - 2.1, width: 4.2, height: 4.2))
            context.fill(gem, with: .color(color))
        }
    }

    private static func drawTiara(in context: inout GraphicsContext) {
        var arch = Path()
        arch.move(to: CGPoint(x: 43, y: 17))
        arch.addQuadCurve(to: CGPoint(x: 85, y: 17), control: CGPoint(x: 64, y: 11))
        context.stroke(arch, with: .color(Color(red: 0.80, green: 0.85, blue: 0.94)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

        var crest = Path()
        crest.move(to: CGPoint(x: 47, y: 15))
        crest.addQuadCurve(to: CGPoint(x: 54, y: 4), control: CGPoint(x: 48, y: 8))
        crest.addQuadCurve(to: CGPoint(x: 59, y: 12), control: CGPoint(x: 57, y: 7))
        crest.addQuadCurve(to: CGPoint(x: 64, y: -3), control: CGPoint(x: 61, y: 2))
        crest.addQuadCurve(to: CGPoint(x: 69, y: 12), control: CGPoint(x: 67, y: 2))
        crest.addQuadCurve(to: CGPoint(x: 74, y: 4), control: CGPoint(x: 71, y: 7))
        crest.addQuadCurve(to: CGPoint(x: 81, y: 15), control: CGPoint(x: 80, y: 8))
        context.stroke(crest, with: .color(.white), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
        context.stroke(crest, with: .color(Color(red: 0.62, green: 0.69, blue: 0.84)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))

        let centerGem = Path(ellipseIn: CGRect(x: 61.5, y: 2.5, width: 5.0, height: 6.0))
        context.fill(centerGem, with: .color(Color(red: 1.0, green: 0.54, blue: 0.78)))
        for sx in [54.0, 74.0] {
            let pearl = Path(ellipseIn: CGRect(x: sx - 2.0, y: 4.5, width: 4.0, height: 4.0))
            context.fill(pearl, with: .color(Color(red: 0.68, green: 0.90, blue: 1.0)))
        }
    }

    private static func drawSantaHat(in context: inout GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: 64, y: 16)
        ctx.rotate(by: .degrees(8))

        var cone = Path()
        cone.move(to: CGPoint(x: -24, y: 2))
        cone.addQuadCurve(to: CGPoint(x: 16, y: -26), control: CGPoint(x: -10, y: -24))
        cone.addQuadCurve(to: CGPoint(x: 28, y: -8), control: CGPoint(x: 28, y: -22))
        cone.addQuadCurve(to: CGPoint(x: 24, y: 2), control: CGPoint(x: 22, y: -6))
        cone.closeSubpath()
        ctx.fill(cone, with: .color(Color(red: 0.88, green: 0.16, blue: 0.24)))
        ctx.stroke(cone, with: .color(Color(red: 0.58, green: 0.08, blue: 0.14)), style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))

        let brim = Path(roundedRect: CGRect(x: -26, y: -3, width: 52, height: 11), cornerRadius: 5.5)
        ctx.fill(brim, with: .color(.white))
        ctx.stroke(brim, with: .color(Color(red: 0.80, green: 0.85, blue: 0.92)), style: StrokeStyle(lineWidth: 1.5))

        let pom = Path(ellipseIn: CGRect(x: 22, y: -14, width: 11, height: 11))
        ctx.fill(pom, with: .color(.white))
        ctx.stroke(pom, with: .color(Color(red: 0.80, green: 0.85, blue: 0.92)), style: StrokeStyle(lineWidth: 1.4))
    }

    private static func drawSnowmanHat(in context: inout GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: 64, y: 14)
        ctx.rotate(by: .degrees(-10))

        var bucket = Path()
        bucket.move(to: CGPoint(x: -15, y: 2))
        bucket.addLine(to: CGPoint(x: -11, y: -18))
        bucket.addLine(to: CGPoint(x: 11, y: -18))
        bucket.addLine(to: CGPoint(x: 15, y: 2))
        bucket.closeSubpath()
        ctx.fill(bucket, with: .color(Color(red: 0.28, green: 0.48, blue: 0.78)))
        ctx.stroke(bucket, with: .color(Color(red: 0.16, green: 0.30, blue: 0.54)), style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))

        let band = Path(roundedRect: CGRect(x: -17, y: -1, width: 34, height: 6), cornerRadius: 3)
        ctx.fill(band, with: .color(.white))
        ctx.stroke(band, with: .color(Color(red: 0.76, green: 0.84, blue: 0.94)), style: StrokeStyle(lineWidth: 1.4))
    }

    private static func drawFlowerCrown(in context: inout GraphicsContext) {
        let flowers: [(x: Double, y: Double, color: Color)] = [
            (40, 17, Color(red: 1.0, green: 0.72, blue: 0.84)),
            (52, 13, Color(red: 1.0, green: 0.92, blue: 0.62)),
            (64, 12, Color(red: 1.0, green: 0.66, blue: 0.80)),
            (76, 13, Color(red: 0.76, green: 0.94, blue: 0.84)),
            (88, 17, Color(red: 1.0, green: 0.78, blue: 0.88))
        ]
        var vine = Path()
        vine.move(to: CGPoint(x: 36, y: 18))
        vine.addQuadCurve(to: CGPoint(x: 92, y: 18), control: CGPoint(x: 64, y: 9))
        context.stroke(vine, with: .color(Color(red: 0.34, green: 0.68, blue: 0.38)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        for f in flowers {
            let blossom = Path(ellipseIn: CGRect(x: f.x - 5.5, y: f.y - 5.5, width: 11, height: 11))
            context.fill(blossom, with: .color(f.color))
            context.stroke(blossom, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.2))
            let center = Path(ellipseIn: CGRect(x: f.x - 2, y: f.y - 2, width: 4, height: 4))
            context.fill(center, with: .color(Color(red: 1.0, green: 0.82, blue: 0.28)))
        }
    }

    private static func drawStrawHat(in context: inout GraphicsContext) {
        let straw = Color(red: 0.96, green: 0.84, blue: 0.56)
        let strawDark = Color(red: 0.74, green: 0.56, blue: 0.24)

        var crown = Path()
        crown.move(to: CGPoint(x: 44, y: 14))
        crown.addQuadCurve(to: CGPoint(x: 49, y: -3), control: CGPoint(x: 45, y: 2))
        crown.addLine(to: CGPoint(x: 79, y: -3))
        crown.addQuadCurve(to: CGPoint(x: 84, y: 14), control: CGPoint(x: 83, y: 2))
        crown.closeSubpath()
        context.fill(crown, with: .color(straw))
        context.stroke(crown, with: .color(strawDark), style: StrokeStyle(lineWidth: 1.7))

        var band = Path()
        band.move(to: CGPoint(x: 45, y: 9))
        band.addLine(to: CGPoint(x: 83, y: 9))
        context.stroke(band, with: .color(Color(red: 0.92, green: 0.34, blue: 0.42)), style: StrokeStyle(lineWidth: 4.2))

        let brim = Path(ellipseIn: CGRect(x: 24, y: 10, width: 80, height: 12))
        context.fill(brim, with: .color(straw))
        context.stroke(brim, with: .color(strawDark), style: StrokeStyle(lineWidth: 1.7))
    }

    private static func drawBeret(in context: inout GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: 62, y: 13)
        ctx.rotate(by: .degrees(-12))

        let cap = Path(ellipseIn: CGRect(x: -25, y: -11, width: 50, height: 22))
        ctx.fill(cap, with: .color(Color(red: 0.76, green: 0.45, blue: 0.30)))
        ctx.stroke(cap, with: .color(Color(red: 0.50, green: 0.26, blue: 0.16)), style: StrokeStyle(lineWidth: 1.8))

        var stem = Path()
        stem.move(to: CGPoint(x: 0, y: -11))
        stem.addQuadCurve(to: CGPoint(x: 3, y: -17), control: CGPoint(x: 0, y: -15))
        ctx.stroke(stem, with: .color(Color(red: 0.50, green: 0.26, blue: 0.16)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }

    private static func drawHeartHeadband(in context: inout GraphicsContext) {
        var band = Path()
        band.move(to: CGPoint(x: 31, y: 25))
        band.addQuadCurve(to: CGPoint(x: 97, y: 25), control: CGPoint(x: 64, y: 6))
        context.stroke(band, with: .color(Color(red: 0.94, green: 0.36, blue: 0.58)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))

        for (x, y) in [(48.0, 7.0), (80.0, 7.0)] {
            var stem = Path()
            stem.move(to: CGPoint(x: x, y: 14))
            stem.addLine(to: CGPoint(x: x, y: y + 4))
            context.stroke(stem, with: .color(Color(red: 0.80, green: 0.24, blue: 0.44)), style: StrokeStyle(lineWidth: 1.6))
            let heart = heartPath(center: CGPoint(x: x, y: y), size: 11.0)
            context.fill(heart, with: .color(Color(red: 1.0, green: 0.44, blue: 0.66)))
            context.stroke(heart, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.1))
        }
    }

    private static func drawPartyHat(in context: inout GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: 64, y: 14)
        ctx.rotate(by: .degrees(8))

        var cone = Path()
        cone.move(to: CGPoint(x: -14, y: 3))
        cone.addLine(to: CGPoint(x: 0, y: -24))
        cone.addLine(to: CGPoint(x: 14, y: 3))
        cone.closeSubpath()
        ctx.fill(cone, with: .color(Color(red: 0.42, green: 0.78, blue: 0.98)))
        ctx.stroke(cone, with: .color(Color(red: 0.22, green: 0.50, blue: 0.76)), style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))

        for (dx, dy, c) in [(-4.0, -7.0, Color.yellow), (4.0, -10.0, Color.pink), (0.0, -3.0, Color.white)] {
            let dot = Path(ellipseIn: CGRect(x: dx - 2.2, y: dy - 2.2, width: 4.4, height: 4.4))
            ctx.fill(dot, with: .color(c))
        }
        let pom = Path(ellipseIn: CGRect(x: -4.5, y: -29, width: 9, height: 9))
        ctx.fill(pom, with: .color(Color(red: 1.0, green: 0.86, blue: 0.34)))
    }

    private static func drawWitchHat(in context: inout GraphicsContext) {
        let hatPurple = Color(red: 0.34, green: 0.20, blue: 0.52)
        let hatStroke = Color(red: 0.18, green: 0.10, blue: 0.32)

        var cone = Path()
        cone.move(to: CGPoint(x: 42, y: 13))
        cone.addQuadCurve(to: CGPoint(x: 72, y: -15), control: CGPoint(x: 52, y: -10))
        cone.addQuadCurve(to: CGPoint(x: 84, y: 13), control: CGPoint(x: 76, y: -2))
        cone.closeSubpath()
        context.fill(cone, with: .color(hatPurple))
        context.stroke(cone, with: .color(hatStroke), style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))

        var band = Path()
        band.move(to: CGPoint(x: 44, y: 10))
        band.addLine(to: CGPoint(x: 83, y: 10))
        context.stroke(band, with: .color(Color(red: 0.98, green: 0.68, blue: 0.24)), style: StrokeStyle(lineWidth: 4.0))

        let brim = Path(ellipseIn: CGRect(x: 28, y: 10, width: 72, height: 11))
        context.fill(brim, with: .color(hatPurple))
        context.stroke(brim, with: .color(hatStroke), style: StrokeStyle(lineWidth: 1.7))
    }

    private static func drawNewYearMikan(in context: inout GraphicsContext) {
        let lowerMochi = Path(ellipseIn: CGRect(x: 49, y: 4, width: 30, height: 14))
        context.fill(lowerMochi, with: .color(.white))
        context.stroke(lowerMochi, with: .color(Color(red: 0.80, green: 0.84, blue: 0.90)), style: StrokeStyle(lineWidth: 1.5))

        let upperMochi = Path(ellipseIn: CGRect(x: 53, y: -4, width: 22, height: 11))
        context.fill(upperMochi, with: .color(.white))
        context.stroke(upperMochi, with: .color(Color(red: 0.80, green: 0.84, blue: 0.90)), style: StrokeStyle(lineWidth: 1.5))

        let mikan = Path(ellipseIn: CGRect(x: 58, y: -12, width: 12, height: 10))
        context.fill(mikan, with: .color(Color(red: 1.0, green: 0.56, blue: 0.16)))
        context.stroke(mikan, with: .color(Color(red: 0.78, green: 0.36, blue: 0.08)), style: StrokeStyle(lineWidth: 1.2))

        var leaf = Path()
        leaf.move(to: CGPoint(x: 64, y: -12))
        leaf.addQuadCurve(to: CGPoint(x: 70, y: -16), control: CGPoint(x: 68, y: -16))
        leaf.addQuadCurve(to: CGPoint(x: 64, y: -12), control: CGPoint(x: 66, y: -11))
        context.fill(leaf, with: .color(Color(red: 0.24, green: 0.66, blue: 0.30)))
    }

    private static func drawOniHorns(in context: inout GraphicsContext) {
        let hornYellow = Color(red: 1.0, green: 0.84, blue: 0.28)
        let hornStroke = Color(red: 0.72, green: 0.44, blue: 0.08)
        for side in [-1.0, 1.0] {
            var ctx = context
            ctx.translateBy(x: 64 + side * 16, y: 12)
            ctx.rotate(by: .degrees(side * 16))
            var horn = Path()
            horn.move(to: CGPoint(x: -6, y: 5))
            horn.addQuadCurve(to: CGPoint(x: 0, y: -16), control: CGPoint(x: -5, y: -6))
            horn.addQuadCurve(to: CGPoint(x: 6, y: 5), control: CGPoint(x: 5, y: -6))
            horn.closeSubpath()
            ctx.fill(horn, with: .color(hornYellow))
            ctx.stroke(horn, with: .color(hornStroke), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            for stripeY in [-1.0, -7.0] {
                var stripe = Path()
                stripe.move(to: CGPoint(x: -3.2, y: stripeY))
                stripe.addLine(to: CGPoint(x: 3.2, y: stripeY))
                ctx.stroke(stripe, with: .color(hornStroke), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
    }

    private static func drawRisingSunHeadband(in context: inout GraphicsContext) {
        var band = Path()
        band.move(to: CGPoint(x: 24, y: 27))
        band.addQuadCurve(to: CGPoint(x: 104, y: 27), control: CGPoint(x: 64, y: 12))
        band.addQuadCurve(to: CGPoint(x: 101, y: 34), control: CGPoint(x: 104, y: 31))
        band.addQuadCurve(to: CGPoint(x: 27, y: 34), control: CGPoint(x: 64, y: 20))
        band.closeSubpath()
        context.fill(band, with: .color(.white))
        context.stroke(band, with: .color(Color(red: 0.78, green: 0.84, blue: 0.92)), style: StrokeStyle(lineWidth: 1.3))

        let sun = Path(ellipseIn: CGRect(x: 57, y: 17.5, width: 14, height: 14))
        context.fill(sun, with: .color(Color(red: 0.92, green: 0.20, blue: 0.28)))
        context.stroke(sun, with: .color(Color(red: 0.68, green: 0.08, blue: 0.16)), style: StrokeStyle(lineWidth: 1.2))
    }

    private static func drawPeachBlossom(in context: inout GraphicsContext) {
        let centers: [(CGPoint, Color)] = [
            (CGPoint(x: 42, y: 17), Color(red: 1.0, green: 0.68, blue: 0.82)),
            (CGPoint(x: 31, y: 24), Color(red: 1.0, green: 0.82, blue: 0.90))
        ]
        var stem = Path()
        stem.move(to: CGPoint(x: 25, y: 29))
        stem.addQuadCurve(to: CGPoint(x: 50, y: 13), control: CGPoint(x: 37, y: 19))
        context.stroke(stem, with: .color(Color(red: 0.42, green: 0.66, blue: 0.36)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

        for (center, petalColor) in centers {
            for i in 0..<5 {
                let rad = (Double(i) / 5.0) * .pi * 2.0 - .pi * 0.5
                let px = center.x + cos(rad) * 4.5
                let py = center.y + sin(rad) * 4.5
                let petal = Path(ellipseIn: CGRect(x: px - 3.3, y: py - 3.3, width: 6.6, height: 6.6))
                context.fill(petal, with: .color(petalColor))
            }
            let dot = Path(ellipseIn: CGRect(x: center.x - 2.2, y: center.y - 2.2, width: 4.4, height: 4.4))
            context.fill(dot, with: .color(Color(red: 1.0, green: 0.84, blue: 0.30)))
        }
    }

    private static func drawJesterHat(in context: inout GraphicsContext) {
        let red = Color(red: 0.94, green: 0.28, blue: 0.40)
        let blue = Color(red: 0.28, green: 0.60, blue: 0.96)
        let gold = Color(red: 1.0, green: 0.84, blue: 0.28)
        let strokeCol = ink.opacity(0.65)

        var leftHorn = Path()
        leftHorn.move(to: CGPoint(x: 42, y: 16))
        leftHorn.addQuadCurve(to: CGPoint(x: 30, y: -8), control: CGPoint(x: 28, y: 4))
        leftHorn.addQuadCurve(to: CGPoint(x: 58, y: 12), control: CGPoint(x: 44, y: -4))
        leftHorn.closeSubpath()
        context.fill(leftHorn, with: .color(red))
        context.stroke(leftHorn, with: .color(strokeCol), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

        var rightHorn = Path()
        rightHorn.move(to: CGPoint(x: 86, y: 16))
        rightHorn.addQuadCurve(to: CGPoint(x: 98, y: -8), control: CGPoint(x: 100, y: 4))
        rightHorn.addQuadCurve(to: CGPoint(x: 70, y: 12), control: CGPoint(x: 84, y: -4))
        rightHorn.closeSubpath()
        context.fill(rightHorn, with: .color(blue))
        context.stroke(rightHorn, with: .color(strokeCol), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

        for pt in [CGPoint(x: 30, y: -8), CGPoint(x: 98, y: -8)] {
            let bell = Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8))
            context.fill(bell, with: .color(gold))
            context.stroke(bell, with: .color(strokeCol), style: StrokeStyle(lineWidth: 1.2))
        }
    }

    private static func drawEasterEggHat(in context: inout GraphicsContext) {
        let eggRect = CGRect(x: 50, y: -12, width: 28, height: 30)
        let egg = Path(ellipseIn: eggRect)
        context.fill(
            egg,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.94, blue: 0.62),
                    Color(red: 1.0, green: 0.72, blue: 0.86),
                    Color(red: 0.66, green: 0.94, blue: 0.84)
                ]),
                startPoint: CGPoint(x: 64, y: -12),
                endPoint: CGPoint(x: 64, y: 18)
            )
        )
        context.stroke(egg, with: .color(Color(red: 0.72, green: 0.56, blue: 0.78)), style: StrokeStyle(lineWidth: 1.6))

        var zig = Path()
        zig.move(to: CGPoint(x: 51, y: 4))
        zig.addLine(to: CGPoint(x: 57, y: 0))
        zig.addLine(to: CGPoint(x: 64, y: 5))
        zig.addLine(to: CGPoint(x: 71, y: 0))
        zig.addLine(to: CGPoint(x: 77, y: 4))
        context.stroke(zig, with: .color(.white.opacity(0.92)), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
    }

    private static func drawSamuraiKabuto(in context: inout GraphicsContext) {
        let navy = Color(red: 0.24, green: 0.34, blue: 0.58)
        let navyStroke = Color(red: 0.14, green: 0.20, blue: 0.38)
        var helmet = Path()
        helmet.move(to: CGPoint(x: 34, y: 17))
        helmet.addLine(to: CGPoint(x: 64, y: -10))
        helmet.addLine(to: CGPoint(x: 94, y: 17))
        helmet.addLine(to: CGPoint(x: 82, y: 17))
        helmet.addLine(to: CGPoint(x: 64, y: 8))
        helmet.addLine(to: CGPoint(x: 46, y: 17))
        helmet.closeSubpath()
        context.fill(helmet, with: .color(navy))
        context.stroke(helmet, with: .color(navyStroke), style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))

        for side in [-1.0, 1.0] {
            var horn = Path()
            horn.move(to: CGPoint(x: 64, y: 4))
            horn.addLine(to: CGPoint(x: 64 + side * 20, y: -14))
            horn.addLine(to: CGPoint(x: 64 + side * 12, y: 4))
            horn.closeSubpath()
            context.fill(horn, with: .color(Color(red: 1.0, green: 0.82, blue: 0.28)))
            context.stroke(horn, with: .color(Color(red: 0.72, green: 0.50, blue: 0.10)), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
        }
    }

    private static func drawFrogRainHat(in context: inout GraphicsContext) {
        let green = Color(red: 0.44, green: 0.80, blue: 0.42)
        let greenStroke = Color(red: 0.22, green: 0.52, blue: 0.22)

        var hood = Path()
        hood.addArc(center: CGPoint(x: 64, y: 16), radius: 26, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        hood.closeSubpath()
        context.fill(hood, with: .color(green))
        context.stroke(hood, with: .color(greenStroke), style: StrokeStyle(lineWidth: 1.7))

        for side in [-1.0, 1.0] {
            let ex = 64 + side * 14
            let bump = Path(ellipseIn: CGRect(x: ex - 7.5, y: -10, width: 15, height: 15))
            context.fill(bump, with: .color(green))
            context.stroke(bump, with: .color(greenStroke), style: StrokeStyle(lineWidth: 1.6))
            let eyeWhite = Path(ellipseIn: CGRect(x: ex - 4.5, y: -7, width: 9, height: 9))
            context.fill(eyeWhite, with: .color(.white))
            let pupil = Path(ellipseIn: CGRect(x: ex - 2, y: -4.5, width: 4, height: 4))
            context.fill(pupil, with: .color(ink))
        }
    }

    private static func drawTanabataStar(in context: inout GraphicsContext) {
        var band = Path()
        band.move(to: CGPoint(x: 34, y: 22))
        band.addQuadCurve(to: CGPoint(x: 94, y: 22), control: CGPoint(x: 64, y: 8))
        context.stroke(band, with: .color(Color(red: 0.36, green: 0.62, blue: 0.96)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

        let mainStar = fivePointStarPath(center: CGPoint(x: 64, y: 3), outerRadius: 11.5, innerRadius: 5.4)
        context.fill(mainStar, with: .color(Color(red: 1.0, green: 0.88, blue: 0.34)))
        context.stroke(mainStar, with: .color(Color(red: 0.78, green: 0.54, blue: 0.10)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

        for (sx, col) in [(46.0, Color(red: 0.98, green: 0.58, blue: 0.78)), (82.0, Color(red: 0.56, green: 0.88, blue: 1.0))] {
            let sideStar = fivePointStarPath(center: CGPoint(x: sx, y: 11), outerRadius: 6.5, innerRadius: 3.1)
            context.fill(sideStar, with: .color(col))
            context.stroke(sideStar, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.0))
        }
    }

    private static func drawFestivalMask(in context: inout GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: 38, y: 13)
        ctx.rotate(by: .degrees(-18))

        var leftEar = Path()
        leftEar.move(to: CGPoint(x: -11, y: -2))
        leftEar.addLine(to: CGPoint(x: -9, y: -16))
        leftEar.addLine(to: CGPoint(x: -2, y: -6))
        leftEar.closeSubpath()
        ctx.fill(leftEar, with: .color(.white))
        ctx.stroke(leftEar, with: .color(ink.opacity(0.75)), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))

        var rightEar = Path()
        rightEar.move(to: CGPoint(x: 11, y: -2))
        rightEar.addLine(to: CGPoint(x: 9, y: -16))
        rightEar.addLine(to: CGPoint(x: 2, y: -6))
        rightEar.closeSubpath()
        ctx.fill(rightEar, with: .color(.white))
        ctx.stroke(rightEar, with: .color(ink.opacity(0.75)), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))

        var face = Path()
        face.move(to: CGPoint(x: -13, y: -3))
        face.addQuadCurve(to: CGPoint(x: 0, y: 11), control: CGPoint(x: -9, y: 9))
        face.addQuadCurve(to: CGPoint(x: 13, y: -3), control: CGPoint(x: 9, y: 9))
        face.addQuadCurve(to: CGPoint(x: -13, y: -3), control: CGPoint(x: 0, y: -10))
        face.closeSubpath()
        ctx.fill(face, with: .color(.white))
        ctx.stroke(face, with: .color(ink.opacity(0.75)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

        for sx in [-5.5, 5.5] {
            var mark = Path()
            mark.move(to: CGPoint(x: sx - 2.5, y: 0))
            mark.addLine(to: CGPoint(x: sx + 2.5, y: -1))
            ctx.stroke(mark, with: .color(Color(red: 0.90, green: 0.22, blue: 0.28)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
    }

    private static func drawMoonDango(in context: inout GraphicsContext) {
        var tray = Path()
        tray.move(to: CGPoint(x: 47, y: 12))
        tray.addLine(to: CGPoint(x: 81, y: 12))
        tray.addLine(to: CGPoint(x: 77, y: 17))
        tray.addLine(to: CGPoint(x: 51, y: 17))
        tray.closeSubpath()
        context.fill(tray, with: .color(Color(red: 0.86, green: 0.68, blue: 0.44)))
        context.stroke(tray, with: .color(Color(red: 0.58, green: 0.40, blue: 0.18)), style: StrokeStyle(lineWidth: 1.4))

        let positions = [
            CGPoint(x: 55, y: 9), CGPoint(x: 64, y: 9), CGPoint(x: 73, y: 9),
            CGPoint(x: 59.5, y: 2), CGPoint(x: 68.5, y: 2),
            CGPoint(x: 64, y: -5)
        ]
        for (index, pt) in positions.enumerated() {
            let ball = Path(ellipseIn: CGRect(x: pt.x - 4.8, y: pt.y - 4.4, width: 9.6, height: 8.8))
            let col = index == positions.count - 1 ? Color(red: 1.0, green: 0.90, blue: 0.46) : Color.white
            context.fill(ball, with: .color(col))
            context.stroke(ball, with: .color(Color(red: 0.78, green: 0.82, blue: 0.88)), style: StrokeStyle(lineWidth: 1.2))
        }
    }

    private static func drawCountdownSpark(in context: inout GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: 64, y: 10)
        ctx.rotate(by: .degrees(12))

        let band = Path(roundedRect: CGRect(x: -17, y: -4, width: 34, height: 8), cornerRadius: 4)
        ctx.fill(band, with: .color(Color(red: 1.0, green: 0.80, blue: 0.26)))
        ctx.stroke(band, with: .color(Color(red: 0.74, green: 0.48, blue: 0.08)), style: StrokeStyle(lineWidth: 1.4))

        let rays: [(CGPoint, Color)] = [
            (CGPoint(x: -14, y: -18), Color(red: 1.0, green: 0.44, blue: 0.62)),
            (CGPoint(x: 0, y: -23), Color(red: 0.34, green: 0.82, blue: 1.0)),
            (CGPoint(x: 15, y: -17), Color(red: 0.54, green: 0.90, blue: 0.44))
        ]
        for (tip, col) in rays {
            var line = Path()
            line.move(to: CGPoint(x: tip.x * 0.25, y: -4))
            line.addLine(to: tip)
            ctx.stroke(line, with: .color(col), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            let star = fivePointStarPath(center: tip, outerRadius: 4.5, innerRadius: 2.1)
            ctx.fill(star, with: .color(col))
        }
    }

    // MARK: - Outfits

    private static func drawOutfit(in context: inout GraphicsContext, outfit: BubbleOutfit) {
        switch outfit {
        case .none:
            return
        case .bowTie:
            let fill = Color(red: 0.98, green: 0.44, blue: 0.52)
            let stroke = Color(red: 0.74, green: 0.22, blue: 0.32)
            drawBowTie(in: &context, centerY: 111, fill: fill, stroke: stroke)

        case .sailorCollar:
            var collar = Path()
            collar.move(to: CGPoint(x: 34, y: 102))
            collar.addQuadCurve(to: CGPoint(x: 64, y: 116), control: CGPoint(x: 46, y: 116))
            collar.addQuadCurve(to: CGPoint(x: 94, y: 102), control: CGPoint(x: 82, y: 116))
            collar.addLine(to: CGPoint(x: 88, y: 124))
            collar.addQuadCurve(to: CGPoint(x: 40, y: 124), control: CGPoint(x: 64, y: 129))
            collar.closeSubpath()
            context.fill(collar, with: .color(Color(red: 0.19, green: 0.28, blue: 0.49)))
            context.stroke(collar, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))

            var stripe = Path()
            stripe.move(to: CGPoint(x: 38, y: 108))
            stripe.addQuadCurve(to: CGPoint(x: 64, y: 121), control: CGPoint(x: 48, y: 120))
            stripe.addQuadCurve(to: CGPoint(x: 90, y: 108), control: CGPoint(x: 80, y: 120))
            context.stroke(stripe, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

            var ribbon = Path()
            ribbon.move(to: CGPoint(x: 64, y: 113))
            ribbon.addLine(to: CGPoint(x: 56, y: 124))
            ribbon.addLine(to: CGPoint(x: 64, y: 120))
            ribbon.addLine(to: CGPoint(x: 72, y: 124))
            ribbon.closeSubpath()
            context.fill(ribbon, with: .color(Color(red: 0.98, green: 0.44, blue: 0.56)))

        case .scarf:
            let tail = Path(roundedRect: CGRect(x: 74, y: 106, width: 13, height: 22), cornerRadius: 5.5)
            context.fill(tail, with: .color(Color(red: 0.96, green: 0.52, blue: 0.58)))
            context.stroke(tail, with: .color(Color(red: 0.76, green: 0.30, blue: 0.38)), style: StrokeStyle(lineWidth: 1.7))

            var wrap = Path()
            wrap.move(to: CGPoint(x: 28, y: 100))
            wrap.addQuadCurve(to: CGPoint(x: 100, y: 100), control: CGPoint(x: 64, y: 114))
            wrap.addQuadCurve(to: CGPoint(x: 96, y: 114), control: CGPoint(x: 102, y: 108))
            wrap.addQuadCurve(to: CGPoint(x: 32, y: 114), control: CGPoint(x: 64, y: 126))
            wrap.closeSubpath()
            context.fill(wrap, with: .color(Color(red: 1.0, green: 0.62, blue: 0.68)))
            context.stroke(wrap, with: .color(Color(red: 0.78, green: 0.32, blue: 0.40)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))

        case .hoodie:
            var hood = Path()
            hood.move(to: CGPoint(x: 28, y: 102))
            hood.addQuadCurve(to: CGPoint(x: 64, y: 114), control: CGPoint(x: 44, y: 114))
            hood.addQuadCurve(to: CGPoint(x: 100, y: 102), control: CGPoint(x: 84, y: 114))
            hood.addQuadCurve(to: CGPoint(x: 94, y: 125), control: CGPoint(x: 100, y: 118))
            hood.addQuadCurve(to: CGPoint(x: 34, y: 125), control: CGPoint(x: 64, y: 131))
            hood.closeSubpath()
            context.fill(hood, with: .color(Color(red: 0.72, green: 0.87, blue: 0.98)))
            context.stroke(hood, with: .color(Color(red: 0.36, green: 0.56, blue: 0.78)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))

            for x in [56.0, 72.0] {
                var cord = Path()
                cord.move(to: CGPoint(x: x, y: 113))
                cord.addLine(to: CGPoint(x: x, y: 125))
                context.stroke(cord, with: .color(.white), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
            }

        case .overalls:
            var bib = Path()
            bib.move(to: CGPoint(x: 38, y: 105))
            bib.addLine(to: CGPoint(x: 48, y: 105))
            bib.addLine(to: CGPoint(x: 48, y: 112))
            bib.addLine(to: CGPoint(x: 80, y: 112))
            bib.addLine(to: CGPoint(x: 80, y: 105))
            bib.addLine(to: CGPoint(x: 90, y: 105))
            bib.addLine(to: CGPoint(x: 92, y: 126))
            bib.addQuadCurve(to: CGPoint(x: 36, y: 126), control: CGPoint(x: 64, y: 130))
            bib.closeSubpath()
            context.fill(bib, with: .color(Color(red: 0.38, green: 0.56, blue: 0.84)))
            context.stroke(bib, with: .color(Color(red: 0.22, green: 0.36, blue: 0.62)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
            for x in [45.0, 83.0] {
                let button = Path(ellipseIn: CGRect(x: x - 2.3, y: 111.5, width: 4.6, height: 4.6))
                context.fill(button, with: .color(Color(red: 1.0, green: 0.85, blue: 0.42)))
            }

        case .ribbonDress:
            var dress = Path()
            dress.move(to: CGPoint(x: 32, y: 104))
            dress.addQuadCurve(to: CGPoint(x: 64, y: 112), control: CGPoint(x: 48, y: 113))
            dress.addQuadCurve(to: CGPoint(x: 96, y: 104), control: CGPoint(x: 80, y: 113))
            dress.addLine(to: CGPoint(x: 102, y: 125))
            dress.addQuadCurve(to: CGPoint(x: 26, y: 125), control: CGPoint(x: 64, y: 130))
            dress.closeSubpath()
            context.fill(dress, with: .color(Color(red: 1.0, green: 0.78, blue: 0.88)))
            context.stroke(dress, with: .color(Color(red: 0.84, green: 0.42, blue: 0.62)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
            let collarDot = Path(ellipseIn: CGRect(x: 60, y: 109, width: 8, height: 6))
            context.fill(collarDot, with: .color(Color(red: 0.98, green: 0.48, blue: 0.68)))

        case .santaSuit:
            var coat = Path()
            coat.move(to: CGPoint(x: 30, y: 103))
            coat.addQuadCurve(to: CGPoint(x: 98, y: 103), control: CGPoint(x: 64, y: 114))
            coat.addLine(to: CGPoint(x: 98, y: 124))
            coat.addQuadCurve(to: CGPoint(x: 30, y: 124), control: CGPoint(x: 64, y: 130))
            coat.closeSubpath()
            context.fill(coat, with: .color(Color(red: 0.88, green: 0.16, blue: 0.24)))
            context.stroke(coat, with: .color(Color(red: 0.58, green: 0.08, blue: 0.14)), style: StrokeStyle(lineWidth: 1.7))

            let trim = Path(roundedRect: CGRect(x: 30, y: 100, width: 68, height: 9), cornerRadius: 4.5)
            context.fill(trim, with: .color(.white))
            let belt = Path(roundedRect: CGRect(x: 32, y: 116, width: 64, height: 6), cornerRadius: 2)
            context.fill(belt, with: .color(ink))
            let buckle = Path(roundedRect: CGRect(x: 58, y: 115, width: 12, height: 8), cornerRadius: 2)
            context.stroke(buckle, with: .color(Color(red: 1.0, green: 0.84, blue: 0.28)), style: StrokeStyle(lineWidth: 2.0))

        case .snowmanBody:
            let tail = Path(roundedRect: CGRect(x: 72, y: 106, width: 12, height: 22), cornerRadius: 5)
            context.fill(tail, with: .color(Color(red: 0.94, green: 0.28, blue: 0.34)))
            var wrap = Path()
            wrap.move(to: CGPoint(x: 28, y: 101))
            wrap.addQuadCurve(to: CGPoint(x: 100, y: 101), control: CGPoint(x: 64, y: 113))
            wrap.addQuadCurve(to: CGPoint(x: 95, y: 114), control: CGPoint(x: 100, y: 108))
            wrap.addQuadCurve(to: CGPoint(x: 33, y: 114), control: CGPoint(x: 64, y: 123))
            wrap.closeSubpath()
            context.fill(wrap, with: .color(Color(red: 0.96, green: 0.34, blue: 0.40)))
            context.stroke(wrap, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.6))
            for y in [118.5, 125.0] {
                let coal = Path(ellipseIn: CGRect(x: 61.5, y: y, width: 5, height: 5))
                context.fill(coal, with: .color(ink))
            }

        case .kimonoCollar:
            var base = Path()
            base.move(to: CGPoint(x: 30, y: 103))
            base.addQuadCurve(to: CGPoint(x: 98, y: 103), control: CGPoint(x: 64, y: 116))
            base.addLine(to: CGPoint(x: 94, y: 125))
            base.addQuadCurve(to: CGPoint(x: 34, y: 125), control: CGPoint(x: 64, y: 130))
            base.closeSubpath()
            context.fill(base, with: .color(Color(red: 0.96, green: 0.48, blue: 0.62)))
            context.stroke(base, with: .color(Color(red: 0.72, green: 0.22, blue: 0.38)), style: StrokeStyle(lineWidth: 1.6))

            var vCollar = Path()
            vCollar.move(to: CGPoint(x: 42, y: 106))
            vCollar.addLine(to: CGPoint(x: 64, y: 124))
            vCollar.addLine(to: CGPoint(x: 86, y: 106))
            context.stroke(vCollar, with: .color(.white), style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round))
            let obi = Path(roundedRect: CGRect(x: 44, y: 120, width: 40, height: 6), cornerRadius: 3)
            context.fill(obi, with: .color(Color(red: 0.98, green: 0.80, blue: 0.30)))

        case .halloweenCape:
            var collar = Path()
            collar.move(to: CGPoint(x: 28, y: 102))
            collar.addQuadCurve(to: CGPoint(x: 64, y: 113), control: CGPoint(x: 46, y: 113))
            collar.addQuadCurve(to: CGPoint(x: 100, y: 102), control: CGPoint(x: 82, y: 113))
            collar.addLine(to: CGPoint(x: 94, y: 120))
            collar.addQuadCurve(to: CGPoint(x: 34, y: 120), control: CGPoint(x: 64, y: 125))
            collar.closeSubpath()
            context.fill(collar, with: .color(Color(red: 0.36, green: 0.20, blue: 0.56)))
            context.stroke(collar, with: .color(Color(red: 0.98, green: 0.62, blue: 0.24)), style: StrokeStyle(lineWidth: 1.8))
            let clasp = Path(ellipseIn: CGRect(x: 60, y: 109, width: 8, height: 8))
            context.fill(clasp, with: .color(Color(red: 1.0, green: 0.72, blue: 0.24)))

        case .chocolateApron:
            var apron = Path()
            apron.move(to: CGPoint(x: 36, y: 105))
            apron.addQuadCurve(to: CGPoint(x: 92, y: 105), control: CGPoint(x: 64, y: 113))
            apron.addLine(to: CGPoint(x: 96, y: 126))
            apron.addQuadCurve(to: CGPoint(x: 32, y: 126), control: CGPoint(x: 64, y: 130))
            apron.closeSubpath()
            context.fill(apron, with: .color(Color(red: 0.52, green: 0.32, blue: 0.22)))
            context.stroke(apron, with: .color(Color(red: 1.0, green: 0.86, blue: 0.90)), style: StrokeStyle(lineWidth: 2.0, lineJoin: .round))
            let heart = heartPath(center: CGPoint(x: 64, y: 117), size: 11.0)
            context.fill(heart, with: .color(Color(red: 1.0, green: 0.68, blue: 0.80)))

        case .whiteDayTuxedo:
            var vest = Path()
            vest.move(to: CGPoint(x: 34, y: 103))
            vest.addQuadCurve(to: CGPoint(x: 94, y: 103), control: CGPoint(x: 64, y: 114))
            vest.addLine(to: CGPoint(x: 90, y: 126))
            vest.addQuadCurve(to: CGPoint(x: 38, y: 126), control: CGPoint(x: 64, y: 130))
            vest.closeSubpath()
            context.fill(vest, with: .color(Color(red: 0.95, green: 0.97, blue: 1.0)))
            context.stroke(vest, with: .color(ink.opacity(0.65)), style: StrokeStyle(lineWidth: 1.7))
            drawBowTie(
                in: &context,
                centerY: 112,
                fill: Color(red: 0.34, green: 0.68, blue: 0.96),
                stroke: Color(red: 0.16, green: 0.44, blue: 0.72)
            )

        case .raincoat:
            var coat = Path()
            coat.move(to: CGPoint(x: 30, y: 103))
            coat.addQuadCurve(to: CGPoint(x: 98, y: 103), control: CGPoint(x: 64, y: 114))
            coat.addLine(to: CGPoint(x: 96, y: 126))
            coat.addQuadCurve(to: CGPoint(x: 32, y: 126), control: CGPoint(x: 64, y: 130))
            coat.closeSubpath()
            context.fill(coat, with: .color(Color(red: 1.0, green: 0.82, blue: 0.24)))
            context.stroke(coat, with: .color(Color(red: 0.78, green: 0.56, blue: 0.08)), style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))
            for y in [114.0, 121.5] {
                let button = Path(ellipseIn: CGRect(x: 61.5, y: y, width: 5, height: 5))
                context.fill(button, with: .color(.white))
                context.stroke(button, with: .color(Color(red: 0.78, green: 0.56, blue: 0.08)), style: StrokeStyle(lineWidth: 1.2))
            }

        case .yukataCollar:
            var base = Path()
            base.move(to: CGPoint(x: 30, y: 103))
            base.addQuadCurve(to: CGPoint(x: 98, y: 103), control: CGPoint(x: 64, y: 116))
            base.addLine(to: CGPoint(x: 94, y: 125))
            base.addQuadCurve(to: CGPoint(x: 34, y: 125), control: CGPoint(x: 64, y: 130))
            base.closeSubpath()
            context.fill(base, with: .color(Color(red: 0.24, green: 0.42, blue: 0.76)))
            context.stroke(base, with: .color(.white.opacity(0.90)), style: StrokeStyle(lineWidth: 1.6))

            var vCollar = Path()
            vCollar.move(to: CGPoint(x: 42, y: 106))
            vCollar.addLine(to: CGPoint(x: 64, y: 123))
            vCollar.addLine(to: CGPoint(x: 86, y: 106))
            context.stroke(vCollar, with: .color(.white), style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))

            for pt in [CGPoint(x: 44, y: 118), CGPoint(x: 84, y: 118)] {
                let dot = Path(ellipseIn: CGRect(x: pt.x - 2.6, y: pt.y - 2.6, width: 5.2, height: 5.2))
                context.fill(dot, with: .color(Color(red: 0.70, green: 0.92, blue: 1.0)))
            }
            let obi = Path(roundedRect: CGRect(x: 44, y: 120, width: 40, height: 6), cornerRadius: 3)
            context.fill(obi, with: .color(Color(red: 0.96, green: 0.42, blue: 0.56)))
        }
    }

    private static func drawBowTie(in context: inout GraphicsContext, centerY: Double, fill: Color, stroke: Color) {
        for side in [-1.0, 1.0] {
            var wing = Path()
            wing.move(to: CGPoint(x: 64, y: centerY))
            wing.addLine(to: CGPoint(x: 64 + side * 14, y: centerY - 7))
            wing.addLine(to: CGPoint(x: 64 + side * 14, y: centerY + 7))
            wing.closeSubpath()
            context.fill(wing, with: .color(fill))
            context.stroke(wing, with: .color(stroke), style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))
        }
        let knot = Path(ellipseIn: CGRect(x: 60, y: centerY - 4, width: 8, height: 8))
        context.fill(knot, with: .color(.white.opacity(0.85)))
        context.stroke(knot, with: .color(stroke), style: StrokeStyle(lineWidth: 1.7))
    }

    // MARK: - Helpers

    private static func drawFourPointSparkle(in context: inout GraphicsContext, center: CGPoint, radius: Double, color: Color) {
        var star = Path()
        star.move(to: CGPoint(x: center.x, y: center.y - radius))
        star.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + radius * 0.25, y: center.y - radius * 0.25))
        star.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x + radius * 0.25, y: center.y + radius * 0.25))
        star.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - radius * 0.25, y: center.y + radius * 0.25))
        star.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x - radius * 0.25, y: center.y - radius * 0.25))
        star.closeSubpath()
        context.fill(star, with: .color(color))
    }

    private static func fivePointStarPath(center: CGPoint, outerRadius: Double, innerRadius: Double) -> Path {
        var path = Path()
        for i in 0..<10 {
            let r = i.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = -Double.pi * 0.5 + (Double(i) * Double.pi / 5.0)
            let pt = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        path.closeSubpath()
        return path
    }

    private static func heartPath(center: CGPoint, size: Double) -> Path {
        let w = size
        let h = size * 0.92
        let topY = center.y - h * 0.22
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y + h * 0.44))
        path.addCurve(
            to: CGPoint(x: center.x - w * 0.5, y: topY),
            control1: CGPoint(x: center.x - w * 0.22, y: center.y + h * 0.26),
            control2: CGPoint(x: center.x - w * 0.5, y: center.y + h * 0.04)
        )
        path.addCurve(
            to: CGPoint(x: center.x, y: center.y - h * 0.14),
            control1: CGPoint(x: center.x - w * 0.5, y: center.y - h * 0.44),
            control2: CGPoint(x: center.x - w * 0.08, y: center.y - h * 0.46)
        )
        path.addCurve(
            to: CGPoint(x: center.x + w * 0.5, y: topY),
            control1: CGPoint(x: center.x + w * 0.08, y: center.y - h * 0.46),
            control2: CGPoint(x: center.x + w * 0.5, y: center.y - h * 0.44)
        )
        path.addCurve(
            to: CGPoint(x: center.x, y: center.y + h * 0.44),
            control1: CGPoint(x: center.x + w * 0.5, y: center.y + h * 0.04),
            control2: CGPoint(x: center.x + w * 0.22, y: center.y + h * 0.26)
        )
        path.closeSubpath()
        return path
    }
}
