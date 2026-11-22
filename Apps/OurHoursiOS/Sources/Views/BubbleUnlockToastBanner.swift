import OurHoursCore
import SwiftUI

struct BubbleUnlockToastBanner: View {
    let banner: BubbleUnlockBanner
    let isTogether: Bool
    let onOpenCustomizer: (BubbleCustomizationCategory) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onOpenCustomizer(banner.primaryCategory)
                onDismiss()
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [BubbleColorTheme.honeyYellow.glowColor, BubbleColorTheme.sakuraPink.tintColor],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 38, height: 38)
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(FoamTheme.ink)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(banner.title)
                            .font(FoamFont.bold(13.5, relativeTo: .subheadline))
                            .foregroundStyle(FoamTheme.ink)
                            .lineLimit(1)
                        Text(banner.subtitle)
                            .font(FoamFont.regular(11.5, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.ink.opacity(0.74))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 3) {
                        Text("きせかえ")
                            .font(FoamFont.bold(11.5, relativeTo: .caption))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(FoamTheme.ink, in: Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(FoamTheme.ink.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.65), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            SoapBubbleSurface(
                cornerStyle: .roundedRect(24),
                prominence: .vivid,
                isTogether: isTogether,
                seed: 7.4,
                wobbleScale: 0.35,
                animated: !reduceMotion
            )
        }
        .shadow(color: FoamTheme.ink.opacity(0.14), radius: 12, y: 4)
        .padding(.horizontal, 14)
        .task(id: banner.id) {
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}
