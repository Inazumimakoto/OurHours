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
        let count = Int.random(in: 10...14)
        let particles = (0..<count).map { _ in
            FoamBurstParticle(
                offsetX: Double.random(in: -36...36),
                offsetY: Double.random(in: -10...4),
                velocityX: Double.random(in: -85...85),
                velocityY: -Double.random(in: 135...260),
                gravity: -Double.random(in: 20...52),
                drag: Double.random(in: 1.8...3.0),
                diameter: Double.random(in: 13...30),
                delay: Double.random(in: 0...0.16),
                lifetime: Double.random(in: 0.95...1.55),
                wobbleFrequency: Double.random(in: 3.2...6.2),
                wobbleAmplitude: Double.random(in: 6...16),
                wobblePhase: Double.random(in: 0...(Double.pi * 2)),
                initialRotation: Double.random(in: -0.6...0.6),
                spinSpeed: Double.random(in: -1.6...1.6),
                peakOpacity: Double.random(in: 0.88...1.0),
                usesMascotSprite: Double.random(in: 0...1) < 0.30
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
                diameter: Double.random(in: 14...32),
                delay: Double.random(in: 0...0.11),
                lifetime: Double.random(in: 0.95...1.55),
                wobbleFrequency: Double.random(in: 2.8...5.6),
                wobbleAmplitude: Double.random(in: 5...13),
                wobblePhase: Double.random(in: 0...(Double.pi * 2)),
                initialRotation: Double.random(in: -0.8...0.8),
                spinSpeed: Double.random(in: -1.2...1.2),
                peakOpacity: Double.random(in: 0.86...1.0),
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
    var softened: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let ambientBubbles: [AmbientFloatBubble] = [
        AmbientFloatBubble(anchorX: 0.16, anchorY: 0.22, diameter: 96, driftX: 22, driftY: 28, freqX: 0.17, freqY: 0.13, phaseX: 0.4, phaseY: 1.2, baseOpacity: 0.58, usesMascotSprite: true, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.84, anchorY: 0.18, diameter: 74, driftX: 18, driftY: 22, freqX: 0.14, freqY: 0.19, phaseX: 2.1, phaseY: 0.6, baseOpacity: 0.66, usesMascotSprite: true, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.72, anchorY: 0.40, diameter: 112, driftX: 26, driftY: 24, freqX: 0.11, freqY: 0.15, phaseX: 3.7, phaseY: 2.5, baseOpacity: 0.54, usesMascotSprite: true, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.12, anchorY: 0.56, diameter: 64, driftX: 20, driftY: 26, freqX: 0.21, freqY: 0.14, phaseX: 1.1, phaseY: 4.1, baseOpacity: 0.68, usesMascotSprite: false, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.88, anchorY: 0.64, diameter: 86, driftX: 22, driftY: 24, freqX: 0.15, freqY: 0.12, phaseX: 5.0, phaseY: 1.9, baseOpacity: 0.58, usesMascotSprite: true, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.28, anchorY: 0.76, diameter: 52, driftX: 18, driftY: 18, freqX: 0.23, freqY: 0.18, phaseX: 2.8, phaseY: 3.3, baseOpacity: 0.74, usesMascotSprite: false, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.62, anchorY: 0.78, diameter: 68, driftX: 20, driftY: 20, freqX: 0.16, freqY: 0.20, phaseX: 4.4, phaseY: 0.9, baseOpacity: 0.62, usesMascotSprite: true, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.46, anchorY: 0.15, diameter: 44, driftX: 16, driftY: 15, freqX: 0.24, freqY: 0.17, phaseX: 0.9, phaseY: 5.2, baseOpacity: 0.72, usesMascotSprite: false, togetherOnly: false),
        AmbientFloatBubble(anchorX: 0.34, anchorY: 0.34, diameter: 84, driftX: 20, driftY: 22, freqX: 0.14, freqY: 0.16, phaseX: 1.6, phaseY: 2.9, baseOpacity: 0.64, usesMascotSprite: true, togetherOnly: true),
        AmbientFloatBubble(anchorX: 0.68, anchorY: 0.56, diameter: 58, driftX: 18, driftY: 20, freqX: 0.19, freqY: 0.15, phaseX: 3.2, phaseY: 4.7, baseOpacity: 0.78, usesMascotSprite: false, togetherOnly: true)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: softened ? (1.0 / 15.0) : (1.0 / 30.0), paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let particleSprite = context.resolve(Image("BubbleParticle"))
                let mascotSprite = context.resolve(Image("BubbleMascot"))
                let time = timeline.date.timeIntervalSinceReferenceDate

                for bubble in Self.ambientBubbles {
                    if bubble.togetherOnly && !isTogether { continue }
                    if softened && bubble.diameter < 66 { continue }
                    let sprite = bubble.usesMascotSprite ? mascotSprite : particleSprite
                    let x = bubble.anchorX * size.width
                        + sin(time * bubble.freqX + bubble.phaseX) * bubble.driftX
                        + cos(time * 0.08 + bubble.phaseY) * 12
                    let y = bubble.anchorY * size.height
                        + cos(time * bubble.freqY + bubble.phaseY) * bubble.driftY
                        + sin(time * 0.07 + bubble.phaseX) * 10
                    let breathe = 1.0 + 0.045 * sin(time * 0.42 + bubble.phaseX)
                    let diameter = bubble.diameter * breathe
                    let angle = Angle.radians(sin(time * 0.22 + bubble.phaseY) * 0.16)
                    let opacityBoost = isTogether ? 1.18 : 1.0
                    let softenMultiplier = softened ? 0.36 : 1.0
                    let opacity = min(0.92, bubble.baseOpacity * opacityBoost) * softenMultiplier

                    var layer = context
                    layer.opacity = opacity
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: angle)
                    layer.draw(sprite, in: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter))
                }
            }
        }
        .blur(radius: softened ? 5.0 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: softened)
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
                let particleSprite = context.resolve(Image("BubbleParticle"))
                let mascotSprite = context.resolve(Image("BubbleMascot"))
                let now = timeline.date

                for burst in activeBursts {
                    let elapsed = now.timeIntervalSince(burst.startDate)
                    guard elapsed >= 0, elapsed < 2.2 else { continue }
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

                        let fade: Double
                        if progress < 0.18 {
                            fade = progress / 0.18
                        } else if progress < 0.82 {
                            fade = 1.0 - ((progress - 0.18) / 0.64) * 0.18
                        } else if progress < 0.94 {
                            fade = 0.82 * (1.0 - (progress - 0.82) / 0.12)
                        } else {
                            fade = 0
                        }

                        let diameter = p.diameter * popScale
                        let sprite = p.usesMascotSprite ? mascotSprite : particleSprite

                        if fade > 0.001 {
                            var layer = context
                            layer.opacity = p.peakOpacity * fade
                            layer.translateBy(x: x, y: y)
                            layer.rotate(by: Angle.radians(p.initialRotation + p.spinSpeed * age))
                            layer.draw(sprite, in: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter))
                        }

                        if progress > 0.82 {
                            let popProgress = min(1.0, (progress - 0.82) / 0.18)
                            let ringRadius = diameter * (0.48 + popProgress * 0.24)
                            let ringRect = CGRect(
                                x: x - ringRadius,
                                y: y - ringRadius,
                                width: ringRadius * 2,
                                height: ringRadius * 2
                            )
                            context.stroke(
                                Path(ellipseIn: ringRect),
                                with: .color(Color.white.opacity((1.0 - popProgress) * 0.65)),
                                lineWidth: 1.2
                            )
                        }
                    }
                }
            }
        }
        .onChange(of: burstEvent) {
            guard let burstEvent, !reduceMotion else { return }
            let now = Date.now
            activeBursts.removeAll { now.timeIntervalSince($0.startDate) >= 2.2 }
            activeBursts.append((burstEvent, now))
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
