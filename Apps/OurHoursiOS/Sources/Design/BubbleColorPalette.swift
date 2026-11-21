import OurHoursCore
import SwiftUI

extension BubbleColorTheme {
    var tintColor: Color {
        switch self {
        case .skyBlue: Color(red: 0.59, green: 0.82, blue: 0.99)
        case .sakuraPink: Color(red: 1.00, green: 0.72, blue: 0.83)
        case .lavender: Color(red: 0.78, green: 0.71, blue: 0.98)
        case .mint: Color(red: 0.59, green: 0.88, blue: 0.77)
        case .honeyYellow: Color(red: 1.00, green: 0.87, blue: 0.56)
        case .coral: Color(red: 1.00, green: 0.68, blue: 0.59)
        }
    }

    var deepTintColor: Color {
        switch self {
        case .skyBlue: Color(red: 0.33, green: 0.61, blue: 0.87)
        case .sakuraPink: Color(red: 0.86, green: 0.45, blue: 0.64)
        case .lavender: Color(red: 0.62, green: 0.48, blue: 0.84)
        case .mint: Color(red: 0.29, green: 0.69, blue: 0.56)
        case .honeyYellow: Color(red: 0.88, green: 0.62, blue: 0.29)
        case .coral: Color(red: 0.89, green: 0.42, blue: 0.36)
        }
    }

    var glowColor: Color {
        switch self {
        case .skyBlue: Color(red: 0.87, green: 0.98, blue: 1.00)
        case .sakuraPink: Color(red: 1.00, green: 0.91, blue: 0.96)
        case .lavender: Color(red: 0.94, green: 0.90, blue: 1.00)
        case .mint: Color(red: 0.85, green: 0.99, blue: 0.93)
        case .honeyYellow: Color(red: 1.00, green: 0.97, blue: 0.83)
        case .coral: Color(red: 1.00, green: 0.92, blue: 0.86)
        }
    }

    var swatchGradient: LinearGradient {
        LinearGradient(
            colors: [glowColor, tintColor, deepTintColor.opacity(0.84)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct BubbleColorSwatches: View {
    let selection: BubbleColorTheme
    let onSelect: (BubbleColorTheme) -> Void

    var body: some View {
        let colors = BubbleColorTheme.allCases
        ViewThatFits(in: .horizontal) {
            swatchRow(colors)
            VStack(spacing: 2) {
                swatchRow(Array(colors.prefix(3)))
                swatchRow(Array(colors.suffix(3)))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func swatchRow(_ colors: [BubbleColorTheme]) -> some View {
        HStack(spacing: 2) {
            ForEach(colors) { color in
                Button {
                    onSelect(color)
                } label: {
                    Circle()
                        .fill(color.swatchGradient)
                        .overlay { Circle().strokeBorder(.white.opacity(0.88), lineWidth: 1.5) }
                        .overlay {
                            if selection == color {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(FoamTheme.ink)
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
