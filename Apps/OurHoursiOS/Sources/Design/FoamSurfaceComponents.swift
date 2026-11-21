import SwiftUI

struct FoamRoundIconButton<Icon: View>: View {
    var size: CGFloat = 44
    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            SoapBubbleSurface(
                cornerStyle: .capsule,
                prominence: .standard,
                seed: 2.7,
                wobbleScale: 0.85
            )
            .frame(width: size, height: size)
            .overlay { icon() }
        }
        .buttonStyle(FoamRoundBounceButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct FoamRoundBounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.91 : 1.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.64), value: configuration.isPressed)
    }
}

struct FoamSoftCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var padding: EdgeInsets = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                SoapBubbleSurface(
                    cornerStyle: .roundedRect(cornerRadius),
                    prominence: .standard,
                    seed: 4.2,
                    wobbleScale: 0.35,
                    animated: false
                )
            }
    }
}

enum FoamDurationFormatter {
    struct HeroParts {
        let hours: Int
        let minutes: Int
        let seconds: Int
    }

    static func heroParts(for interval: TimeInterval) -> HeroParts {
        let total = max(0, Int(interval.rounded(.towardZero)))
        return HeroParts(
            hours: total / 3600,
            minutes: (total / 60) % 60,
            seconds: total % 60
        )
    }

    static func compactDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total / 60) % 60
        let remSeconds = total % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)時間\(minutes)分" : "\(hours)時間"
        }
        if minutes > 0 {
            return remSeconds > 0 && minutes < 5 ? "\(minutes)分\(remSeconds)秒" : "\(minutes)分"
        }
        return total > 0 ? "\(total)秒" : "0分"
    }
}
