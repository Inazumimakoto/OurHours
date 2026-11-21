import SwiftUI
import UIKit

/// Emits normalized tap coordinates on window taps outside the bottom tab bar and modal sheets.
struct FoamTapObserverView: UIViewRepresentable {
    let excludedBottomHeight: CGFloat
    let onTap: @MainActor @Sendable (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(excludedBottomHeight: excludedBottomHeight, onTap: onTap)
    }

    func makeUIView(context: Context) -> ObserverHostView {
        let view = ObserverHostView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onWindowAttach = { window in
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: ObserverHostView, context: Context) {
        context.coordinator.excludedBottomHeight = excludedBottomHeight
        context.coordinator.onTap = onTap
    }

    static func dismantleUIView(_ uiView: ObserverHostView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class ObserverHostView: UIView {
        var onWindowAttach: ((UIWindow) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { return }
            onWindowAttach?(window)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var excludedBottomHeight: CGFloat
        var onTap: @MainActor @Sendable (CGPoint) -> Void
        private weak var attachedWindow: UIWindow?
        private var recognizer: UITapGestureRecognizer?

        init(excludedBottomHeight: CGFloat, onTap: @escaping @MainActor @Sendable (CGPoint) -> Void) {
            self.excludedBottomHeight = excludedBottomHeight
            self.onTap = onTap
        }

        func attach(to window: UIWindow) {
            guard attachedWindow !== window else { return }
            detach()
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            attachedWindow = window
            recognizer = tap
        }

        func detach() {
            if let recognizer, let attachedWindow {
                attachedWindow.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            attachedWindow = nil
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let window = gesture.view as? UIWindow else { return }
            guard window.rootViewController?.presentedViewController == nil else { return }
            let width = window.bounds.width
            let height = window.bounds.height
            guard width > 0, height > 0 else { return }
            let location = gesture.location(in: window)
            guard location.y < height - excludedBottomHeight else { return }
            let normalized = CGPoint(
                x: min(max(location.x / width, 0.02), 0.98),
                y: min(max(location.y / height, 0.02), 0.96)
            )
            onTap(normalized)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let window = gestureRecognizer.view as? UIWindow else { return false }
            guard window.rootViewController?.presentedViewController == nil else { return false }
            let location = touch.location(in: window)
            return location.y < window.bounds.height - excludedBottomHeight
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
