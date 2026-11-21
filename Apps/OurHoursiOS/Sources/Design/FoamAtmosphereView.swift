import SwiftUI

enum FoamBurstStyle: Equatable {
    case tabSplash
    case screenPuff
}

struct FoamBurstParticle: Equatable {
    let offsetX: Double
    let offsetY: Double
    let velocityX: Double
    let velocityY: Double
    let gravity: Double
    let drag: Double
    let diameter: Double
    let delay: Double
    let lifetime: Double
    let wobbleFrequency: Double
    let wobbleAmplitude: Double
    let wobblePhase: Double
    let initialRotation: Double
    let spinSpeed: Double
    let peakOpacity: Double
    let usesMascotSprite: Bool
}

struct FoamBurstEvent: Equatable {
    let id = UUID()
    let originNormalized: CGPoint
    let style: FoamBurstStyle
    let particles: [FoamBurstParticle]

    static func tabSplash(originNormalizedX: CGFloat) -> FoamBurstEvent {
        let count = Int.random(in: 9...12)
        let particles = (0..<count).map { _ in
            FoamBurstParticle(
                offsetX: Double.random(in: -34...34),
                offsetY: Double.random(in: -8...6),
                velocityX: Double.random(in: -118...118),
                velocityY: -Double.random(in: 175...335),
                gravity: Double.random(in: 135...215),
                drag: Double.random(in: 1.5...2.8),
                diameter: Double.random(in: 9...24),
                delay: Double.random(in: 0...0.16),
                lifetime: Double.random(in: 0.72...1.24),
                wobbleFrequency: Double.random(in: 4.5...8.5),
                wobbleAmplitude: Double.random(in: 4...12),
                wobblePhase: Double.random(in: 0...(Double.pi * 2)),
                initialRotation: Double.random(in: -0.6...0.6),
                spinSpeed: Double.random(in: -1.6...1.6),
                peakOpacity: Double.random(in: 0.78...0.96),
                usesMascotSprite: Bool.random() && Double.random(in: 0...1) < 0.25
            )
        }
        return FoamBurstEvent(
            originNormalized: CGPoint(x: originNormalizedX, y: 0.89),
            style: .tabSplash,
            particles: particles
        )
    }

    static func screenPuff(originNormalized: CGPoint) -> FoamBurstEvent {
        let count = Int.random(in: 6...10)
        let baseAngle = Double.random(in: 0...(Double.pi * 2))
        let particles = (0..<count).map { index in
            let sector = Double(index) / Double(count) * Double.pi * 2
            let angle = baseAngle + sector + Double.random(in: -0.45...0.45)
            let speed = Double.random(in: 34...94)
            return FoamBurstParticle(
                offsetX: Double.random(in: -10...10),
                offsetY: Double.random(in: -10...10),
                velocityX: cos(angle) * speed,
                velocityY: sin(angle) * speed - Double.random(in: 24...58),
                gravity: -Double.random(in: 18...42),
                drag: Double.random(in: 2.2...3.6),
                diameter: Double.random(in: 11...26),
                delay: Double.random(in: 0...0.11),
                lifetime: Double.random(in: 0.85...1.42),
                wobbleFrequency: Double.random(in: 2.8...5.6),
                wobbleAmplitude: Double.random(in: 5...13),
                wobblePhase: Double.random(in: 0...(Double.pi * 2)),
                initialRotation: Double.random(in: -0.8...0.8),
                spinSpeed: Double.random(in: -1.2...1.2),
                peakOpacity: Double.random(in: 0.70...0.92),
                usesMascotSprite: Double.random(in: 0...1) < 0.35
            )
        }
        return FoamBurstEvent(
            originNormalized: originNormalized,
            style: .screenPuff,
            particles: particles
        )
    }
}

private struct AmbientFloatBubble {
    let anchorX: Double
    let anchorY: Double
    let diameter: Double
    let driftX: Double
    let driftY: Double
    let freqX: Double
    let freqY: Double
    let phaseX: Double
    let phaseY: Double
    let baseOpacity: Double
    let usesMascotSprite: Bool
    let togetherOnly: Bool
}

/// Large dreamy bubbles drifting gently behind the main UI.
struct FoamAmbientBackgroundView: View {
    let isTogether: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let ambientBubbles: [AmbientFloatBubble] = [
        AmbientFloatBubble(anchorX: 0.16, anchorY: 0.22, diameter: 96, driftX: 22, driftY: 28, freqX: 0.17, freqY: 0.13, phaseX: 0.4, phaseY: 1.2, baseOpacity: 0.26, usesMascotSprite: true, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.84, anchorY: 0.18, diameter: 74, driftX: 18, driftY: 22, freqX: 0.14, freqY: 0.19, phaseX: 2.1, phaseY: 0.6, baseOpacity: 0.32, usesMascotSprite: true, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.72, anchorY: 0.40, diameter: 112, driftX: 26, driftY: 24, freqX: 0.11, freqY: 0.15, phaseX: 3.7, phaseY: 2.5, baseOpacity: 0.20, usesMascotSprite: true, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.12, anchorY: 0.56, diameter: 64, driftX: 20, driftY: 26, freqX: 0.21, freqY: 0.14, phaseX: 1.1, phaseY: 4.1, baseOpacity: 0.30, usesMascotSprite: false, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.88, anchorY: 0.64, diameter: 86, driftX: 22, driftY: 24, freqX: 0.15, freqY: 0.12, phaseX: 5.0, phaseY: 1.9, baseOpacity: 0.26, usesMascotSprite: true, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.28, anchorY: 0.76, diameter: 52, driftX: 18, driftY: 18, freqX: 0.23, freqY: 0.18, phaseX: 2.8, phaseY: 3.3, baseOpacity: 0.36, usesMascotSprite: false, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.62, anchorY: 0.78, diameter: 68, driftX: 20, driftY: 20, freqX: 0.16, freqY: 0.20, phaseX: 4.4, phaseY: 0.9, baseOpacity: 0.28, usesMascotSprite: true, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.46, anchorY: 0.15, diameter: 44, driftX: 16, driftY: 15, freqX: 0.24, freqY: 0.17, phaseX: 0.9, phaseY: 5.2, baseOpacity: 0.34, usesMascotSprite: false, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.34, anchorY: 0.34, diameter: 84, driftX: 20, driftY: 22, freqX: 0.14, freqY: 0.16, phaseX: 1.6, phaseY: 2.9, baseOpacity: 0.34, usesMascotSprite: true, togetherOnly: true),
        AmbientFloatBubble(anchorX: 0.68, anchorY: 0.56, diameter: 58, driftX: 18, driftY: 20, freqX: 0.19, freqY: 0.15, phaseX: 3.2, phaseY: 4.7, baseOpacity: 0.40, usesMascotSprite: false, togetherOnly: true)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let sudSprite = context.resolve(Image("FoamSudDrop"))
                let ballSprite = context.resolve(Image("FoamMascotBall"))
                let time = timeline.date.timeIntervalSinceReferenceDate

                for bubble in Self.ambientBubbles {
                    if bubble.togetherOnly && !isTogether { continue }
                    let sprite = bubble.usesMascotSprite ? ballSprite : sudSprite
                    let x = bubble.anchorX * size.width
                        + sin(time * bubble.freqX + bubble.phaseX) * bubble.driftX
                        + cos(time * 0.08 + bubble.phaseY) * 12
                    let y = bubble.anchorY * size.height
                        + cos(time * bubble.freqY + bubble.phaseY) * bubble.driftY
                        + sin(time * 0.07 + bubble.phaseX) * 10
                    let breathe = 1.0 + 0.045 * sin(time * 0.42 + bubble.phaseX)
                    let diameter = bubble.diameter * breathe
                    let angle = Angle.radians(sin(time * 0.22 + bubble.phaseY) * 0.16)
                    let opacityBoost = isTogether ? 1.24 : 1.0
                    let opacity = min(0.68, bubble.baseOpacity * opacityBoost)

                    var layer = context
                    layer.opacity = opacity
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: angle)
                    layer.draw(sprite, in: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter))
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// Interactive tap-bubble bursts rendered above UI chrome so taps anywhere visibly emit bubbles.
struct FoamTapBurstsOverlayView: View {
    let burstEvent: FoamBurstEvent?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeBursts: [(event: FoamBurstEvent, startDate: Date)] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion || activeBursts.isEmpty)) { timeline in
            Canvas { context, size in
                let sudSprite = context.resolve(Image("FoamSudDrop"))
                let ballSprite = context.resolve(Image("FoamMascotBall"))
                let now = timeline.date

                for burst in activeBursts {
                    let elapsed = now.timeIntervalSince(burst.startDate)
                    guard elapsed >= 0, elapsed < 2.0 else { continue }
                    let baseX = burst.event.originNormalized.x * size.width
                    let baseY = burst.event.originNormalized.y * size.height

                    for p in burst.event.particles {
                        let age = elapsed - p.delay
                        guard age >= 0, age < p.lifetime else { continue }
                        let progress = age / p.lifetime
                        let damped = (1.0 - exp(-p.drag * age)) / max(p.drag, 0.01)
                        let wobble = sin(age * p.wobbleFrequency + p.wobblePhase) * p.wobbleAmplitude * progress

                        let x = baseX + p.offsetX + p.velocityX * damped + wobble
                        let y = baseY + p.offsetY + p.velocityY * damped + 0.5 * p.gravity * age * age

                        let popScale: Double = if burst.event.style == .screenPuff {
                            age < 0.16 ? 0.25 + (age / 0.16) * 0.85 : 1.10 - progress * 0.18
                        } else {
                            age < 0.08 ? 0.45 + (age / 0.08) * 0.60 : 1.05 - progress * 0.12
                        }

                        let fade = progress < 0.18 ? (progress / 0.18) : pow(max(0, 1.0 - (progress - 0.18) / 0.82), 1.35)
                        let diameter = p.diameter * popScale
                        let sprite = p.usesMascotSprite ? ballSprite : sudSprite

                        var layer = context
                        layer.opacity = p.peakOpacity * fade
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: Angle.radians(p.initialRotation + p.spinSpeed * age))
                        layer.draw(sprite, in: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter))
                    }
                }
            }
        }
        .onChange(of: burstEvent) {
            guard let burstEvent, !reduceMotion else { return }
            let now = Date.now
            activeBursts.removeAll { now.timeIntervalSince($0.startDate) >= 2.0 }
            activeBursts.append((burstEvent, now))
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
