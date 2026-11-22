import OurHoursCore
import SwiftUI

extension BubbleColorTheme {
    var tintColor: Color {
        switch self {
        case .clear: Color.white.opacity(0.45)
        case .skyBlue: Color(red: 0.28, green: 0.68, blue: 0.99)
        case .sakuraPink: Color(red: 1.00, green: 0.56, blue: 0.76)
        case .lavender: Color(red: 0.66, green: 0.50, blue: 0.98)
        case .mint: Color(red: 0.24, green: 0.84, blue: 0.68)
        case .honeyYellow: Color(red: 1.00, green: 0.79, blue: 0.22)
        case .coral: Color(red: 1.00, green: 0.48, blue: 0.38)
        case .peachCream: Color(red: 1.00, green: 0.68, blue: 0.52)
        case .matcha: Color(red: 0.44, green: 0.72, blue: 0.30)
        case .sodaPop: Color(red: 0.14, green: 0.84, blue: 0.95)
        case .berryRose: Color(red: 0.88, green: 0.24, blue: 0.54)
        case .sunsetGlow: Color(red: 1.00, green: 0.46, blue: 0.42)
        case .oceanDeep: Color(red: 0.12, green: 0.52, blue: 0.88)
        case .moonlight: Color(red: 0.36, green: 0.42, blue: 0.88)
        case .champagneGold: Color(red: 0.96, green: 0.76, blue: 0.24)
        case .auroraPrism: Color(red: 0.46, green: 0.86, blue: 1.00)
        case .snowCrystal: Color(red: 0.92, green: 0.96, blue: 1.00)
        case .santaRuby: Color(red: 0.90, green: 0.18, blue: 0.28)
        case .chocoMocha: Color(red: 0.64, green: 0.41, blue: 0.28)
        case .crimsonDawn: Color(red: 0.95, green: 0.28, blue: 0.34)
        case .easterPastel: Color(red: 0.98, green: 0.72, blue: 0.88)
        case .milkyWay: Color(red: 0.24, green: 0.34, blue: 0.78)
        }
    }

    var deepTintColor: Color {
        switch self {
        case .clear: Color(red: 0.74, green: 0.84, blue: 0.98)
        case .skyBlue: Color(red: 0.10, green: 0.45, blue: 0.85)
        case .sakuraPink: Color(red: 0.85, green: 0.26, blue: 0.56)
        case .lavender: Color(red: 0.46, green: 0.28, blue: 0.82)
        case .mint: Color(red: 0.09, green: 0.60, blue: 0.46)
        case .honeyYellow: Color(red: 0.88, green: 0.55, blue: 0.08)
        case .coral: Color(red: 0.88, green: 0.24, blue: 0.20)
        case .peachCream: Color(red: 0.92, green: 0.46, blue: 0.30)
        case .matcha: Color(red: 0.22, green: 0.48, blue: 0.16)
        case .sodaPop: Color(red: 0.04, green: 0.56, blue: 0.82)
        case .berryRose: Color(red: 0.60, green: 0.10, blue: 0.36)
        case .sunsetGlow: Color(red: 0.74, green: 0.24, blue: 0.64)
        case .oceanDeep: Color(red: 0.05, green: 0.26, blue: 0.62)
        case .moonlight: Color(red: 0.17, green: 0.20, blue: 0.58)
        case .champagneGold: Color(red: 0.76, green: 0.50, blue: 0.08)
        case .auroraPrism: Color(red: 0.54, green: 0.38, blue: 0.94)
        case .snowCrystal: Color(red: 0.68, green: 0.82, blue: 0.96)
        case .santaRuby: Color(red: 0.62, green: 0.07, blue: 0.16)
        case .chocoMocha: Color(red: 0.40, green: 0.22, blue: 0.13)
        case .crimsonDawn: Color(red: 0.74, green: 0.10, blue: 0.20)
        case .easterPastel: Color(red: 0.56, green: 0.84, blue: 0.76)
        case .milkyWay: Color(red: 0.12, green: 0.16, blue: 0.52)
        }
    }

    var glowColor: Color {
        switch self {
        case .clear: Color.white.opacity(0.95)
        case .skyBlue: Color(red: 0.72, green: 0.92, blue: 1.00)
        case .sakuraPink: Color(red: 1.00, green: 0.84, blue: 0.93)
        case .lavender: Color(red: 0.88, green: 0.82, blue: 1.00)
        case .mint: Color(red: 0.72, green: 0.98, blue: 0.90)
        case .honeyYellow: Color(red: 1.00, green: 0.94, blue: 0.62)
        case .coral: Color(red: 1.00, green: 0.80, blue: 0.74)
        case .peachCream: Color(red: 1.00, green: 0.89, blue: 0.80)
        case .matcha: Color(red: 0.78, green: 0.93, blue: 0.68)
        case .sodaPop: Color(red: 0.64, green: 0.97, blue: 1.00)
        case .berryRose: Color(red: 0.98, green: 0.68, blue: 0.84)
        case .sunsetGlow: Color(red: 1.00, green: 0.82, blue: 0.46)
        case .oceanDeep: Color(red: 0.52, green: 0.84, blue: 1.00)
        case .moonlight: Color(red: 0.76, green: 0.80, blue: 1.00)
        case .champagneGold: Color(red: 1.00, green: 0.95, blue: 0.72)
        case .auroraPrism: Color(red: 0.86, green: 0.98, blue: 1.00)
        case .snowCrystal: Color.white
        case .santaRuby: Color(red: 1.00, green: 0.66, blue: 0.72)
        case .chocoMocha: Color(red: 0.86, green: 0.68, blue: 0.55)
        case .crimsonDawn: Color(red: 1.00, green: 0.86, blue: 0.56)
        case .easterPastel: Color(red: 1.00, green: 0.95, blue: 0.68)
        case .milkyWay: Color(red: 0.56, green: 0.88, blue: 1.00)
        }
    }

    var swatchGradient: LinearGradient {
        switch self {
        case .clear:
            return LinearGradient(
                colors: [Color.white.opacity(0.76), Color.white.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sunsetGlow:
            return LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.84, blue: 0.42),
                    Color(red: 1.00, green: 0.44, blue: 0.40),
                    Color(red: 0.74, green: 0.24, blue: 0.64)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .moonlight:
            return LinearGradient(
                colors: [
                    Color(red: 0.78, green: 0.82, blue: 1.00),
                    Color(red: 0.36, green: 0.42, blue: 0.88),
                    Color(red: 0.16, green: 0.19, blue: 0.54)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .champagneGold:
            return LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.96, blue: 0.76),
                    Color(red: 0.96, green: 0.76, blue: 0.24),
                    Color(red: 0.76, green: 0.50, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .auroraPrism:
            return LinearGradient(
                colors: [
                    Color(red: 0.28, green: 0.90, blue: 1.00),
                    Color(red: 1.00, green: 0.54, blue: 0.82),
                    Color(red: 0.44, green: 0.94, blue: 0.70),
                    Color(red: 0.56, green: 0.42, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .crimsonDawn:
            return LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.88, blue: 0.56),
                    Color(red: 0.96, green: 0.30, blue: 0.36),
                    Color(red: 0.74, green: 0.10, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .easterPastel:
            return LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.94, blue: 0.66),
                    Color(red: 1.00, green: 0.74, blue: 0.88),
                    Color(red: 0.62, green: 0.94, blue: 0.84),
                    Color(red: 0.78, green: 0.74, blue: 1.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .milkyWay:
            return LinearGradient(
                colors: [
                    Color(red: 0.56, green: 0.90, blue: 1.00),
                    Color(red: 0.26, green: 0.36, blue: 0.82),
                    Color(red: 0.14, green: 0.15, blue: 0.48)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [glowColor, tintColor, deepTintColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var bubbleGradientColors: [Color] {
        switch self {
        case .clear:
            return [Color.white.opacity(0.35), Color.white.opacity(0.14), Color(red: 0.82, green: 0.92, blue: 1.0).opacity(0.24)]
        case .sunsetGlow:
            return [
                Color(red: 1.00, green: 0.86, blue: 0.48).opacity(0.84),
                Color(red: 1.00, green: 0.48, blue: 0.42).opacity(0.86),
                Color(red: 0.76, green: 0.26, blue: 0.66).opacity(0.82)
            ]
        case .auroraPrism:
            return [
                Color(red: 0.34, green: 0.90, blue: 1.00).opacity(0.82),
                Color(red: 1.00, green: 0.56, blue: 0.84).opacity(0.82),
                Color(red: 0.48, green: 0.44, blue: 0.96).opacity(0.84)
            ]
        case .snowCrystal:
            return [
                Color.white.opacity(0.94),
                Color(red: 0.90, green: 0.95, blue: 1.00).opacity(0.88),
                Color(red: 0.70, green: 0.84, blue: 0.98).opacity(0.82)
            ]
        case .easterPastel:
            return [
                Color(red: 1.00, green: 0.95, blue: 0.70).opacity(0.84),
                Color(red: 1.00, green: 0.76, blue: 0.89).opacity(0.82),
                Color(red: 0.64, green: 0.92, blue: 0.84).opacity(0.84)
            ]
        case .milkyWay:
            return [
                Color(red: 0.54, green: 0.88, blue: 1.00).opacity(0.76),
                Color(red: 0.24, green: 0.34, blue: 0.78).opacity(0.86),
                Color(red: 0.12, green: 0.16, blue: 0.52).opacity(0.86)
            ]
        default:
            return [
                glowColor.opacity(0.76),
                tintColor.opacity(0.82),
                deepTintColor.opacity(0.80)
            ]
        }
    }

    func bubbleSphereFill(size: CGFloat) -> RadialGradient {
        RadialGradient(
            colors: bubbleGradientColors,
            center: UnitPoint(x: 0.30, y: 0.28),
            startRadius: 0,
            endRadius: size * 0.82
        )
    }

    func bubbleSurfaceColors(size: CGFloat) -> RadialGradient {
        bubbleSphereFill(size: size)
    }
}

struct BubbleColorSwatches: View {
    let selection: BubbleColorTheme
    var colors: [BubbleColorTheme] = BubbleColorTheme.starterColors
    let onSelect: (BubbleColorTheme) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if colors.count <= 7 {
                swatchRow(colors)
            } else {
                chunkedRows
            }
            chunkedRows
        }
        .frame(maxWidth: .infinity)
    }

    private var chunkedRows: some View {
        let chunkSize = colors.count <= 8 ? 4 : 6
        let chunks = stride(from: 0, to: colors.count, by: chunkSize).map {
            Array(colors[$0..<min($0 + chunkSize, colors.count)])
        }
        return VStack(spacing: 2) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, row in
                swatchRow(row)
            }
        }
    }

    private func swatchRow(_ rowColors: [BubbleColorTheme]) -> some View {
        HStack(spacing: 2) {
            ForEach(rowColors) { color in
                Button {
                    onSelect(color)
                } label: {
                    Circle()
                        .fill(color.swatchGradient)
                        .overlay {
                            if color == .clear || color == .auroraPrism {
                                Circle().strokeBorder(
                                    AngularGradient(
                                        colors: [
                                            Color(red: 0.45, green: 0.85, blue: 1.0),
                                            Color(red: 1.0, green: 0.60, blue: 0.84),
                                            Color(red: 0.52, green: 0.95, blue: 0.74),
                                            Color.white,
                                            Color(red: 0.45, green: 0.85, blue: 1.0)
                                        ],
                                        center: .center
                                    ),
                                    lineWidth: 2
                                )
                            } else {
                                Circle().strokeBorder(.white.opacity(0.90), lineWidth: 1.5)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if color == .clear {
                                Circle()
                                    .fill(.white.opacity(0.95))
                                    .frame(width: 6, height: 6)
                                    .offset(x: 7, y: 7)
                            }
                        }
                        .overlay {
                            if selection == color {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(color.prefersLightForeground ? Color.white : FoamTheme.ink)
                            }
                        }
                        .frame(width: 35, height: 35)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.displayName)
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
    }
}

private extension BubbleColorTheme {
    var prefersLightForeground: Bool {
        switch self {
        case .oceanDeep, .moonlight, .santaRuby, .chocoMocha, .berryRose, .crimsonDawn, .milkyWay:
            return true
        default:
            return false
        }
    }
}
