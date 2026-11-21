import SwiftUI

struct FoamChromeOverlay: View {
    var isTogether: Bool = false
    let onOpenSettings: () -> Void

    var body: some View {
        VStack {
            HStack {
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
            .padding(.trailing, 14)
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
