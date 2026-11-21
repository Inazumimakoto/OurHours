import SwiftUI

struct TaskKillAnimationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TaskKillDiagram(reduceMotion: reduceMotion)
            .accessibilityHidden(true)
    }
}

private struct TaskKillDiagram: View {
    let reduceMotion: Bool
    @State private var startedAt = Date.now

    private let coral = Color(red: 0.77, green: 0.29, blue: 0.31)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
            let time = elapsed.truncatingRemainder(dividingBy: 4.4)
            let switcher = reduceMotion ? 1 : ease(time, from: 0.72, to: 1.44) * (1 - ease(time, from: 3.73, to: 4.28))
            let swipe = ease(time, from: 1.68, to: 2.42)
            let remaining = 1 - ease(time, from: 2.42, to: 3.16)
            // The card briefly overshoots its resting position on the way back.
            let lift = reduceMotion ? 7 : swipe * 57 * remaining * remaining * (2.7 * remaining - 1.7)
            let finger = reduceMotion ? 1 : ease(time, from: 1.43, to: 1.72) * (1 - ease(time, from: 2.22, to: 2.52))
            let mark = ease(time, from: 2.27, to: 2.74)
            let markOpacity = reduceMotion ? 1 : mark * (1 - ease(time, from: 3.49, to: 3.93))

            ZStack {
                phone(switcher: switcher, lift: lift, time: reduceMotion ? 0 : time)
                swipeIndicator
                    .offset(x: 23, y: reduceMotion ? 48 : 86 - swipe * 82)
                    .opacity(finger)
                prohibitionMark
                    .scaleEffect(reduceMotion ? 1 : 0.62 + mark * 0.38 + sin(mark * .pi) * 0.39)
                    .offset(x: 32, y: -30)
                    .opacity(markOpacity)
            }
            .frame(width: 176, height: 242)
        }
    }

    private func phone(switcher: Double, lift: Double, time: Double) -> some View {
        let bezel = RoundedRectangle(cornerRadius: 27)
        let screen = RoundedRectangle(cornerRadius: 22)
        return ZStack {
            bezel.fill(FoamTheme.ink.opacity(0.87))
            bezel.strokeBorder(.white.opacity(0.72), lineWidth: 1)

            ZStack {
                LinearGradient(colors: [.init(red: 0.77, green: 0.78, blue: 0.92), .init(red: 0.92, green: 0.84, blue: 0.90)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)

                RoundedRectangle(cornerRadius: 13)
                    .fill(.white.opacity(0.38))
                    .frame(width: 74, height: 146)
                    .offset(x: -83)
                    .opacity(switcher)

                appCard(switcher: switcher, time: time)
                    .scaleEffect(1 - switcher * 0.35)
                    .offset(x: switcher * 5, y: 6 * switcher - lift)
            }
            .clipShape(screen)
            .padding(5)

            Capsule()
                .fill(FoamTheme.ink)
                .frame(width: 35, height: 10)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 11)
            Capsule()
                .fill(FoamTheme.ink.opacity(0.54))
                .frame(width: 37, height: 3)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 11)
        }
        .frame(width: 132, height: 242)
    }

    private func appCard(switcher: Double, time: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22 - switcher * 7)
        let drift = sin(time * 2 * .pi / 4.4) * 4

        return ZStack {
            shape.fill(FoamTheme.sky(together: true))
            shape.strokeBorder(.white.opacity(0.78), lineWidth: switcher)
            Image("BubbleMascot").resizable().scaledToFit()
                .frame(width: 37, height: 37)
                .offset(x: -16, y: drift - 10)
            Image("BubbleMascot").resizable().scaledToFit()
                .frame(width: 32, height: 32)
                .offset(x: 16, y: 8 - drift)
        }
        .frame(width: 122, height: 232)
    }

    private var swipeIndicator: some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.up")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(FoamTheme.ink.opacity(0.85))
            Circle()
                .fill(.white.opacity(0.58))
                .overlay { Circle().strokeBorder(.white.opacity(0.88), lineWidth: 1.4) }
                .frame(width: 28, height: 28)
        }
    }

    private var prohibitionMark: some View {
        Image(systemName: "nosign")
            .font(.system(size: 51, weight: .semibold))
            .foregroundStyle(coral)
            .frame(width: 56, height: 56)
            .background(.white.opacity(0.78), in: Circle())
    }

    private func ease(_ time: Double, from start: Double, to end: Double) -> Double {
        let progress = min(max((time - start) / (end - start), 0), 1)
        return progress * progress * (3 - 2 * progress)
    }
}

#Preview {
    TaskKillAnimationView()
        .padding(24)
        .background(FoamTheme.sky(together: false))
}

#Preview("Reduce Motion") {
    TaskKillDiagram(reduceMotion: true)
        .padding(24)
        .background(FoamTheme.sky(together: false))
}
