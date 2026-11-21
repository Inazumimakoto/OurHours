import SwiftUI

/// Custom plump, softly rounded icons embedded into creamy white soap lather.
struct FoamHomeIcon: View {
    let active: Bool

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let accent = active ? FoamTheme.ink.opacity(0.88) : FoamTheme.ink.opacity(0.50)
            let stroke = StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)

            var house = Path()
            house.move(to: CGPoint(x: w * 0.50, y: h * 0.16))
            house.addQuadCurve(
                to: CGPoint(x: w * 0.84, y: h * 0.45),
                control: CGPoint(x: w * 0.71, y: h * 0.25)
            )
            house.addQuadCurve(
                to: CGPoint(x: w * 0.75, y: h * 0.84),
                control: CGPoint(x: w * 0.83, y: h * 0.77)
            )
            house.addQuadCurve(
                to: CGPoint(x: w * 0.25, y: h * 0.84),
                control: CGPoint(x: w * 0.50, y: h * 0.88)
            )
            house.addQuadCurve(
                to: CGPoint(x: w * 0.16, y: h * 0.45),
                control: CGPoint(x: w * 0.17, y: h * 0.77)
            )
            house.addQuadCurve(
                to: CGPoint(x: w * 0.50, y: h * 0.16),
                control: CGPoint(x: w * 0.29, y: h * 0.25)
            )
            house.closeSubpath()

            if active {
                context.fill(house, with: .color(FoamTheme.ink.opacity(0.08)))
            }
            context.stroke(house, with: .color(accent), style: stroke)

            let bubbleLeft = Path(ellipseIn: CGRect(x: w * 0.37, y: h * 0.50, width: w * 0.12, height: h * 0.12))
            let bubbleRight = Path(ellipseIn: CGRect(x: w * 0.51, y: h * 0.53, width: w * 0.11, height: h * 0.11))
            context.fill(bubbleLeft, with: .color(accent.opacity(active ? 0.88 : 0.68)))
            context.fill(bubbleRight, with: .color(accent.opacity(active ? 0.62 : 0.44)))
        }
        .frame(width: 26, height: 26)
        .shadow(color: .white.opacity(active ? 0.65 : 0.92), radius: 0.4, y: 0.8)
        .accessibilityHidden(true)
    }
}

struct FoamCalendarIcon: View {
    let active: Bool

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let accent = active ? FoamTheme.ink.opacity(0.88) : FoamTheme.ink.opacity(0.50)
            let stroke = StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)

            let bodyRect = CGRect(x: w * 0.16, y: h * 0.25, width: w * 0.68, height: h * 0.60)
            let bodyPath = Path(roundedRect: bodyRect, cornerRadius: w * 0.20)

            if active {
                context.fill(bodyPath, with: .color(FoamTheme.ink.opacity(0.08)))
            }
            context.stroke(bodyPath, with: .color(accent), style: stroke)

            var header = Path()
            header.move(to: CGPoint(x: w * 0.18, y: h * 0.43))
            header.addQuadCurve(
                to: CGPoint(x: w * 0.82, y: h * 0.43),
                control: CGPoint(x: w * 0.50, y: h * 0.45)
            )
            context.stroke(header, with: .color(accent.opacity(0.82)), style: StrokeStyle(lineWidth: 1.75, lineCap: .round))

            for xRatio in [0.35, 0.65] {
                let ringRect = CGRect(x: w * xRatio - 2.0, y: h * 0.14, width: 4.0, height: h * 0.16)
                let ring = Path(roundedRect: ringRect, cornerRadius: 2.0)
                context.fill(ring, with: .color(.white))
                context.stroke(ring, with: .color(accent), style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
            }

            let dots: [(Double, Double, Double)] = [
                (0.35, 0.57, 3.3), (0.52, 0.56, 4.0), (0.67, 0.58, 3.0),
                (0.38, 0.71, 3.8), (0.57, 0.72, 3.2)
            ]
            for (x, y, d) in dots {
                let dotRect = CGRect(x: w * x - d / 2, y: h * y - d / 2, width: d, height: d)
                context.fill(Path(ellipseIn: dotRect), with: .color(accent.opacity(active ? 0.88 : 0.66)))
            }
        }
        .frame(width: 26, height: 26)
        .shadow(color: .white.opacity(active ? 0.65 : 0.92), radius: 0.4, y: 0.8)
        .accessibilityHidden(true)
    }
}

struct FoamSettingsIcon: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.36
            let stroke = StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
            let accent = FoamTheme.ink.opacity(0.62)

            var gear = Path()
            let teeth = 6
            let steps = 72
            for step in 0...steps {
                let angle = Double(step) / Double(steps) * .pi * 2
                let wave = pow((cos(angle * Double(teeth)) + 1) * 0.5, 1.4)
                let r = radius * (0.76 + 0.30 * wave)
                let pt = CGPoint(x: center.x + CGFloat(cos(angle)) * r, y: center.y + CGFloat(sin(angle)) * r)
                if step == 0 { gear.move(to: pt) } else { gear.addLine(to: pt) }
            }
            gear.closeSubpath()
            context.stroke(gear, with: .color(accent), style: stroke)

            let innerR = radius * 0.36
            let centerDot = Path(ellipseIn: CGRect(x: center.x - innerR, y: center.y - innerR, width: innerR * 2, height: innerR * 2))
            context.stroke(centerDot, with: .color(accent), style: stroke)
        }
        .frame(width: 22, height: 22)
        .shadow(color: .white.opacity(0.9), radius: 0.4, y: 0.8)
        .accessibilityHidden(true)
    }
}

struct FoamPlusIcon: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let stroke = StrokeStyle(lineWidth: 2.2, lineCap: .round)
            var p = Path()
            p.move(to: CGPoint(x: w * 0.5, y: h * 0.24))
            p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.76))
            p.move(to: CGPoint(x: w * 0.24, y: h * 0.5))
            p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.5))
            context.stroke(p, with: .color(FoamTheme.ink.opacity(0.68)), style: stroke)
        }
        .frame(width: 20, height: 20)
        .shadow(color: .white.opacity(0.9), radius: 0.4, y: 0.8)
        .accessibilityHidden(true)
    }
}

struct FoamChevronIcon: View {
    let direction: Int

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let left = direction < 0
            let tipX = left ? w * 0.32 : w * 0.68
            let tailX = left ? w * 0.64 : w * 0.36
            var p = Path()
            p.move(to: CGPoint(x: tailX, y: h * 0.24))
            p.addQuadCurve(to: CGPoint(x: tipX, y: h * 0.50), control: CGPoint(x: (tipX + tailX) * 0.5, y: h * 0.39))
            p.addQuadCurve(to: CGPoint(x: tailX, y: h * 0.76), control: CGPoint(x: (tipX + tailX) * 0.5, y: h * 0.61))
            context.stroke(p, with: .color(FoamTheme.ink.opacity(0.68)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 20, height: 20)
        .shadow(color: .white.opacity(0.9), radius: 0.4, y: 0.8)
        .accessibilityHidden(true)
    }
}
