import SwiftUI

struct FoamChromeOverlay: View {
    let onOpenSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("FoamCornerCluster").resizable().scaledToFit().frame(width: 160)
                .scaleEffect(breathe ? 1.035 : 1, anchor: .topLeading)
                .animation(reduceMotion ? nil : .easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathe)
                .onAppear { breathe = true }
                .allowsHitTesting(false).accessibilityHidden(true).ignoresSafeArea(edges: [.top, .leading])
            HStack {
                Spacer()
                Button(action: onOpenSettings) {
                    Image("FoamCalendarStamp").resizable().scaledToFit().frame(width: 50, height: 50)
                        .overlay { Image(systemName: "gearshape.fill").font(.title3) }
                }
                .buttonStyle(FoamSettingsButtonStyle()).accessibilityLabel("設定")
            }.padding(.horizontal, 16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct FoamSettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
