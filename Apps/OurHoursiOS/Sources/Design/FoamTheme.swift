import SwiftUI

enum FoamTheme {
    static let ink = Color(red: 0.14, green: 0.16, blue: 0.28)
    static let cream = Color(red: 1, green: 0.93, blue: 0.75)
    static func sky(together: Bool) -> LinearGradient {
        let colors = together
            ? [Color(red: 1, green: 0.894, blue: 0.812), Color(red: 0.988, green: 0.91, blue: 0.847), Color(red: 0.973, green: 0.91, blue: 0.949)]
            : [Color(red: 0.729, green: 0.796, blue: 1), Color(red: 0.808, green: 0.843, blue: 0.98), Color(red: 0.875, green: 0.847, blue: 0.98)]
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

extension View {
    func foamPill() -> some View {
        padding(.horizontal, 18).padding(.vertical, 10)
            .background(.white.opacity(0.55), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.7)) }
    }
}
