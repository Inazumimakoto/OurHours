import SwiftUI
import UIKit

/// Keeps the underlying UITextField alive so pressing Return or tapping "+" never dismisses the keyboard.
struct PlanRapidEntryField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var isEnabled: Bool = true
    var autoFocusOnAppear: Bool = true
    let focusRequest: Int
    let onSubmit: () -> Void
    var onFocusConfirmed: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self, initialFocusRequest: autoFocusOnAppear ? nil : focusRequest)
    }

    func makeUIView(context: Context) -> PlanRapidEntryTextField {
        let field = PlanRapidEntryTextField()
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        field.borderStyle = .none
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UIColor(FoamTheme.ink)
        field.placeholder = placeholder
        field.accessibilityLabel = placeholder
        field.returnKeyType = .default
        field.enablesReturnKeyAutomatically = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: PlanRapidEntryTextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = isEnabled
        if field.placeholder != placeholder {
            field.placeholder = placeholder
            field.accessibilityLabel = placeholder
        }
        // Preserve active Japanese/CJK marked-text composition while allowing explicit draft clears.
        if field.text != text, field.markedTextRange == nil || text.isEmpty {
            if text.isEmpty { field.unmarkText() }
            field.text = text
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            field.requestFocus { [weak coordinator = context.coordinator] in
                coordinator?.parent.onFocusConfirmed()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PlanRapidEntryTextField, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return CGSize(width: width, height: max(24, uiView.intrinsicContentSize.height))
    }

    static func dismantleUIView(_ field: PlanRapidEntryTextField, coordinator: Coordinator) {
        field.stopRequestingFocus()
        field.delegate = nil
        if field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PlanRapidEntryField
        var lastFocusRequest: Int?

        init(_ parent: PlanRapidEntryField, initialFocusRequest: Int?) {
            self.parent = parent
            self.lastFocusRequest = initialFocusRequest
        }

        nonisolated deinit {}

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            guard field.markedTextRange == nil else { return false }
            parent.text = field.text ?? ""
            parent.onSubmit()
            field.text = parent.text
            return false
        }
    }
}

final class PlanRapidEntryTextField: UITextField {
    private var wantsFocus = false
    private var isFocusScheduled = false
    private var focusCompletion: (() -> Void)?

    nonisolated deinit {}

    func requestFocus(onConfirmed: @escaping () -> Void) {
        wantsFocus = true
        focusCompletion = onConfirmed
        scheduleFocusIfNeeded()
    }

    func stopRequestingFocus() {
        wantsFocus = false
        focusCompletion = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleFocusIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleFocusIfNeeded()
    }

    private func scheduleFocusIfNeeded() {
        guard wantsFocus, window != nil, isEnabled, !isFocusScheduled else { return }
        isFocusScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isFocusScheduled = false
            guard self.wantsFocus, self.window != nil, self.isEnabled else { return }
            if self.isFirstResponder || self.becomeFirstResponder() {
                self.wantsFocus = false
                let completion = self.focusCompletion
                self.focusCompletion = nil
                completion?()
            }
        }
    }
}
