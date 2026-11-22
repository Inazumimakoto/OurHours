import SwiftUI

struct FoamChromeOverlay: View {
    var isTogether: Bool = false
    var showsCustomizerButton: Bool = false
    var hasUnseenUnlocks: Bool = false
    var onOpenCustomizer: (() -> Void)? = nil
    let onOpenSettings: () -> Void

    var body: some View {
        VStack {
            HStack {
                if showsCustomizerButton, let onOpenCustomizer {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        onOpenCustomizer()
                    }) {
                        SoapBubbleSurface(
                            cornerStyle: .capsule,
                            prominence: .standard,
                            isTogether: isTogether,
                            seed: 1.9,
                            wobbleScale: 0.90
                        )
                        .frame(width: 50, height: 50)
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(FoamTheme.ink.opacity(0.84))
                        }
                        .overlay(alignment: .topTrailing) {
                            if hasUnseenUnlocks {
                                Circle()
                                    .fill(FoamTheme.warmAccent)
                                    .frame(width: 11, height: 11)
                                    .overlay {
                                        Circle().strokeBorder(.white, lineWidth: 1.5)
                                    }
                                    .offset(x: -3, y: 3)
                            }
                        }
                    }
                    .buttonStyle(FoamSettingsButtonStyle())
                    .accessibilityLabel("シャボン玉をきせかえ")
                }

                Spacer()

                Button(action: {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    onOpenSettings()
                }) {
                    SoapBubbleSurface(
                        cornerStyle: .capsule,
                        prominence: .standard,
                        isTogether: isTogether,
                        seed: 3.1,
                        wobbleScale: 0.90
                    )
                    .frame(width: 50, height: 50)
                    .overlay { FoamSettingsIcon() }
                }
                .buttonStyle(FoamSettingsButtonStyle())
                .accessibilityLabel("設定")
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct FoamSettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                x: configuration.isPressed ? 1.06 : 1.0,
                y: configuration.isPressed ? 0.89 : 1.0
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.64), value: configuration.isPressed)
    }
}
