import SwiftUI

struct FoamChromeOverlay: View {
    let onOpenSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("FoamCornerCluster")
                .resizable()
                .scaledToFit()
                .frame(width: 152)
                .scaleEffect(breathe ? 1.035 : 1, anchor: .topLeading)
                .animation(reduceMotion ? nil : .easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathe)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .ignoresSafeArea(edges: [.top, .leading])

            HStack {
                Spacer()
                Button(action: {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    onOpenSettings()
                }) {
                    Image("FoamSettingsLather")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .shadow(color: FoamTheme.ink.opacity(0.09), radius: 6, y: 3)
                        .overlay { FoamSettingsIcon() }
                }
                .buttonStyle(FoamSettingsButtonStyle())
                .accessibilityLabel("設定")
            }
            .padding(.trailing, 14)
            .padding(.top, 2)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { breathe = true }
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
