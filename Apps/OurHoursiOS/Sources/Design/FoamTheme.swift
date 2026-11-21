import SwiftUI
import UIKit

enum FoamFont {
    static let regularName = "ZenMaruGothic-Regular"
    static let mediumName = "ZenMaruGothic-Medium"
    static let boldName = "ZenMaruGothic-Bold"

    static func regular(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(regularName, size: size, relativeTo: style)
    }

    static func medium(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(mediumName, size: size, relativeTo: style)
    }

    static func bold(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(boldName, size: size, relativeTo: style)
    }

    static func uiRegular(_ size: CGFloat) -> UIFont {
        UIFont(name: regularName, size: size) ?? .systemFont(ofSize: size, weight: .regular)
    }

    static func uiMedium(_ size: CGFloat) -> UIFont {
        UIFont(name: mediumName, size: size) ?? .systemFont(ofSize: size, weight: .medium)
    }

    static func uiBold(_ size: CGFloat) -> UIFont {
        UIFont(name: boldName, size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }
}

enum FoamTheme {
    static let ink = Color(red: 0.14, green: 0.16, blue: 0.28)
    static let cream = Color(red: 1.0, green: 0.93, blue: 0.75)
    static let warmAccent = Color(red: 0.58, green: 0.35, blue: 0.10)

    static func sky(together: Bool) -> LinearGradient {
        let colors = together
            ? [Color(red: 1.0, green: 0.894, blue: 0.812), Color(red: 0.988, green: 0.91, blue: 0.847), Color(red: 0.973, green: 0.91, blue: 0.949)]
            : [Color(red: 0.729, green: 0.796, blue: 1.0), Color(red: 0.808, green: 0.843, blue: 0.98), Color(red: 0.875, green: 0.847, blue: 0.98)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        let remSeconds = seconds % 60
        if hours > 0 { return "\(hours)時間\(minutes)分" }
        if minutes > 0 { return remSeconds > 0 ? "\(minutes)分\(remSeconds)秒" : "\(minutes)分" }
        return seconds > 0 ? "\(seconds)秒" : "0分"
    }
}

/// Continuous pastel soap-bubble surface framing content cleanly without rectangular distortion.
struct FoamCloudSurface: View {
    var isTogether: Bool = false
    var compact: Bool = false
    var wobble: Bool = true

    var body: some View {
        SoapBubbleSurface(
            cornerStyle: compact ? .capsule : .roundedRect(24),
            prominence: .standard,
            isTogether: isTogether,
            seed: compact ? 1.1 : 2.3,
            wobbleScale: wobble ? (compact ? 0.90 : 0.55) : 0,
            animated: wobble
        )
    }
}

private struct FoamPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

extension View {
    func foamCloudSurface(isTogether: Bool = false, compact: Bool = false) -> some View {
        padding(.horizontal, compact ? 22 : 26)
            .padding(.vertical, compact ? 12 : 16)
            .background { FoamCloudSurface(isTogether: isTogether, compact: compact) }
    }

    func foamButtonSurface(wobble: Bool = true) -> some View {
        padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background { FoamCloudSurface(isTogether: false, compact: true, wobble: wobble) }
            .buttonStyle(FoamPressButtonStyle())
    }
}
