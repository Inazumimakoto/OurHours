import SwiftUI

struct LaunchSplashOverlayView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity: Double = 1.0
    @State private var iconScale: CGFloat = 0.94
    @State private var didFinish = false

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            Image("LaunchAppIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.65), lineWidth: 1)
                }
                .shadow(color: FoamTheme.ink.opacity(0.14), radius: 16, y: 6)
                .scaleEffect(iconScale)
        }
        .opacity(opacity)
        .contentShape(Rectangle())
        .onTapGesture {
            finishOnce()
        }
        .task {
            if reduceMotion {
                try? await Task.sleep(for: .milliseconds(320))
                finishOnce()
                return
            }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                iconScale = 1.0
            }
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled, !didFinish else { return }
            withAnimation(.easeOut(duration: 0.26)) {
                opacity = 0.0
                iconScale = 1.04
            }
            try? await Task.sleep(for: .milliseconds(270))
            finishOnce()
        }
        .accessibilityHidden(true)
    }

    private func finishOnce() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }
}
