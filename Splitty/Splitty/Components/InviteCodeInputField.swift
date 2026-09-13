import SwiftUI
import UIKit

struct InviteCodeInputField: UIViewRepresentable {
    let text: String
    @Binding var isFocused: Bool
    let isEnabled: Bool
    let onEdit: (String, InviteCodeEditSource) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PasteAwareTextField {
        let field = PasteAwareTextField()
        field.delegate = context.coordinator
        field.autocapitalizationType = .allCharacters
        field.autocorrectionType = .no
        field.keyboardType = .asciiCapable
        field.textContentType = .oneTimeCode
        field.textColor = .clear
        field.tintColor = .clear
        field.backgroundColor = .clear
        field.accessibilityLabel = L10n.Invite.code
        field.accessibilityHint = L10n.Invite.codeHint
        return field
    }

    func updateUIView(_ field: PasteAwareTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.isEnabled = isEnabled
        field.accessibilityValue = InviteCodeEntry.accessibilityValue(for: text)

        if isFocused, !field.isFirstResponder {
            field.becomeFirstResponder()
        } else if !isFocused, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: InviteCodeInputField

        init(parent: InviteCodeInputField) {
            self.parent = parent
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            guard let current = textField.text,
                  let swiftRange = Range(range, in: current) else { return false }
            let proposed = current.replacingCharacters(in: swiftRange, with: string)
            let source: InviteCodeEditSource = (textField as? PasteAwareTextField)?.isPasting == true
                ? .paste
                : .typing
            parent.onEdit(proposed, source)
            return false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused = false
        }
    }
}

final class PasteAwareTextField: UITextField {
    private(set) var isPasting = false

    override func closestPosition(to point: CGPoint) -> UITextPosition? {
        endOfDocument
    }

    override func paste(_ sender: Any?) {
        isPasting = true
        super.paste(sender)
        isPasting = false
    }
}
