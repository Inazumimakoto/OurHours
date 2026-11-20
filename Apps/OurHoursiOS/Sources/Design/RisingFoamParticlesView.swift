import SwiftUI

struct FoamBurstEvent: Equatable {
    let id = UUID()
    let originNormalizedX: CGFloat
    let count: Int
}

struct RisingFoamParticlesView: View {
    let isTogether: Bool
    let burstEvent: FoamBurstEvent?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bursts: [(event: FoamBurstEvent, date: Date)] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 120, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let sprite = context.resolve(Image("FoamSudDrop"))
                func draw(_ x: Double, _ y: Double, _ diameter: Double, _ opacity: Double) {
                    var layer = context
                    layer.opacity = opacity
                    layer.draw(sprite, in: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter))
                }
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<(isTogether ? 32 : 10) {
                    let seed = Double(index)
                    let cycle = isTogether ? 7.0 : 17.0
                    let phase = (time / (cycle + seed.truncatingRemainder(dividingBy: 4)) + seed * 0.618).truncatingRemainder(dividingBy: 1)
                    let x = (seed * 0.382 + 0.08).truncatingRemainder(dividingBy: 1) * size.width
                    draw(x + sin(phase * 7 + seed) * 14, size.height * (0.90 - phase * 0.84),
                         5 + Double(index % 6) * 2.6, sin(phase * .pi) * (isTogether ? 0.86 : 0.52))
                }
                for burst in bursts {
                    let age = timeline.date.timeIntervalSince(burst.date)
                    guard age >= 0, age < 1 else { continue }
                    for index in 0..<burst.event.count {
                        let spread = Double(index) / Double(burst.event.count - 1) * 2 - 1
                        let x = size.width * burst.event.originNormalizedX + spread * (1 - exp(-age * 2)) * 87
                        let y = size.height - 64 - age * (280 - abs(spread) * 85) + 158 * age * age
                        draw(x, y, 11 + Double(index % 3) * 4, 1 - age * age)
                    }
                }
            }
        }
        .onChange(of: burstEvent) {
            guard let burstEvent, !reduceMotion else { return }
            bursts.removeAll { Date.now.timeIntervalSince($0.date) >= 1 }
            bursts.append((burstEvent, .now))
        }
        .accessibilityHidden(true).allowsHitTesting(false)
    }
}
