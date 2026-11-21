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
                    .offset(x: home ? -8 : 2, y: 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FoamTabSquishButtonStyle())
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(.horizontal, 18)
        .background(alignment: .bottom) {
            GeometryReader { geometry in
                Image("FoamTabBarBase")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height + 58, alignment: .bottom)
                    .offset(y: -58)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Smooth organic pill contour with live continuous/elastic perimeter waves that automatically fit any content width.
private struct OrganicFoamHollowShape: Shape {
    let seed: Double
    var phase: Double = 0
    var ampScale: Double = 1.0

    func path(in rect: CGRect) -> Path {
        guard rect.width > 4, rect.height > 4 else { return Path() }

        let inset: CGFloat = 2.6
        let rRect = rect.insetBy(dx: inset, dy: inset)
        let rx = rRect.height * 0.5
        let halfStraight = max(0, (rRect.width - rRect.height) * 0.5)
        let cy = rRect.midY
        let leftCx = rRect.midX - halfStraight
        let rightCx = rRect.midX + halfStraight

        let steps = 48
        var points: [CGPoint] = []
        points.reserveCapacity(steps)

        // Parameterize uniformly around the stadium (top straight -> right arc -> bottom straight -> left arc)
        let arcLen = .pi * rx
        let straightLen = 2.0 * halfStraight
        let totalLen = max(1.0, 2.0 * arcLen + 2.0 * straightLen)

        for i in 0..<steps {
            let s = (Double(i) / Double(steps)) * totalLen
            let base: CGPoint
            let normal: CGVector

            if s < straightLen {
                // Top edge left -> right
                let t = s / max(1e-6, straightLen)
                base = CGPoint(x: leftCx + CGFloat(t) * 2.0 * halfStraight, y: rRect.minY)
                normal = CGVector(dx: 0, dy: -1)
            } else if s < straightLen + arcLen {
                // Right semicircle -pi/2 -> +pi/2
                let t = (s - straightLen) / max(1e-6, arcLen)
                let angle = -Double.pi * 0.5 + t * Double.pi
                base = CGPoint(x: rightCx + CGFloat(cos(angle)) * rx, y: cy + CGFloat(sin(angle)) * rx)
                normal = CGVector(dx: cos(angle), dy: sin(angle))
            } else if s < 2.0 * straightLen + arcLen {
                // Bottom edge right -> left
                let t = (s - straightLen - arcLen) / max(1e-6, straightLen)
                base = CGPoint(x: rightCx - CGFloat(t) * 2.0 * halfStraight, y: rRect.maxY)
                normal = CGVector(dx: 0, dy: 1)
            } else {
                // Left semicircle +pi/2 -> 3*pi/2
                let t = (s - 2.0 * straightLen - arcLen) / max(1e-6, arcLen)
                let angle = Double.pi * 0.5 + t * Double.pi
                base = CGPoint(x: leftCx + CGFloat(cos(angle)) * rx, y: cy + CGFloat(sin(angle)) * rx)
                normal = CGVector(dx: cos(angle), dy: sin(angle))
            }

            let theta = (Double(i) / Double(steps)) * 2.0 * .pi
            let wave = 1.15 * sin(3.0 * theta + seed + phase * 0.95)
                + 0.78 * cos(5.0 * theta - seed * 1.3 - phase * 1.45)
                + 0.45 * sin(7.0 * theta + seed * 0.7 + phase * 1.95)
            let maxAmp = min(2.1 * ampScale, Double(min(rect.width, rect.height)) * 0.085)
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

/// Concept D pressed-foam hollow with initial tap squish wobble settling into continuous organic drift.
private struct OrganicFoamPressedHollow: View {
    let active: Bool
    let isTogether: Bool
    let seed: Double
    let pressDate: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var topTint: Color {
        isTogether
            ? Color(red: 0.945, green: 0.916, blue: 0.896)
            : Color(red: 0.896, green: 0.912, blue: 0.958)
    }

    private var bottomTint: Color {
        isTogether
            ? Color(red: 0.976, green: 0.958, blue: 0.948)
            : Color(red: 0.954, green: 0.964, blue: 0.988)
    }

    private var undercutColor: Color {
        isTogether
            ? Color(red: 0.62, green: 0.56, blue: 0.52)
            : Color(red: 0.54, green: 0.58, blue: 0.68)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !active)) { timeline in
            let metrics = animationMetrics(at: timeline.date)
            let hollow = OrganicFoamHollowShape(
                seed: seed,
                phase: metrics.phase,
                ampScale: metrics.ampScale
            )

            ZStack {
                // Outer displaced white foam ridge around the pressed dent
                hollow
                    .stroke(Color.white.opacity(0.95), lineWidth: 5.0)
                    .blur(radius: 1.8)
                    .shadow(color: Color.black.opacity(0.06), radius: 2.5, y: 1.5)
                    .padding(-2.5)

                // Flattened thinned-foam concave well reflecting the subtle sky tint underneath
                hollow
                    .fill(
                        LinearGradient(
                            colors: [topTint, bottomTint],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .shadow(.inner(color: undercutColor.opacity(0.55), radius: 5.5, x: 0, y: 5.0))
                        .shadow(.inner(color: Color.black.opacity(0.14), radius: 10.0, x: 0, y: 2.5))
                        .shadow(.inner(color: Color.white.opacity(0.98), radius: 3.0, x: 0, y: -3.0))
                    )
            }
            .scaleEffect(x: 1.0 + metrics.squish, y: 1.0 - metrics.squish)
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
        let phase = t * 1.35 + (1.0 - impulse) * 1.6
        let ampScale = 1.0 + impulse * 1.15
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
