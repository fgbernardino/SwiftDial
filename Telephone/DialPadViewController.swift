import AppKit

@MainActor
final class DialPadViewController: NSViewController {
    private let destination: String
    private let dial: (String) -> Void
    private let numberField = NSTextField()

    @objc init(destination: String, dial: @escaping (String) -> Void) {
        self.destination = destination
        self.dial = dial
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        numberField.stringValue = destination
        numberField.placeholderString = NSLocalizedString("Phone number", comment: "Dial pad input.")
        numberField.setAccessibilityLabel(numberField.placeholderString)
        numberField.target = self
        numberField.action = #selector(makeCall)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        stack.addArrangedSubview(numberField)
        numberField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        for symbols in [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"], ["+", "⌫"]] {
            let row = NSStackView()
            row.distribution = .fillEqually
            row.spacing = 8
            for symbol in symbols {
                let button = NSButton(title: symbol, target: self, action: #selector(pressKey(_:)))
                button.bezelStyle = .rounded
                button.refusesFirstResponder = true
                button.setAccessibilityLabel(symbol == "⌫" ? NSLocalizedString("Delete digit", comment: "Dial pad backspace.") : symbol)
                row.addArrangedSubview(button)
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let call = NSButton(title: NSLocalizedString("Dial", comment: "Dial pad call action."), target: self, action: #selector(makeCall))
        call.bezelStyle = .rounded
        stack.addArrangedSubview(call)
        call.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalToConstant: 220)
        ])
        preferredContentSize = view.fittingSize
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(numberField)
        if let editor = numberField.currentEditor() {
            editor.selectedRange = NSRange(location: editor.string.utf16.count, length: 0)
        }
    }

    @objc private func pressKey(_ sender: NSButton) {
        if let editor = numberField.currentEditor() as? NSTextView {
            if sender.title == "⌫" {
                editor.deleteBackward(nil)
            } else {
                editor.insertText(sender.title, replacementRange: editor.selectedRange())
            }
        } else if sender.title == "⌫" {
            numberField.stringValue = String(numberField.stringValue.dropLast())
        } else {
            numberField.stringValue += sender.title
        }
    }

    @objc private func makeCall() {
        let number = (numberField.currentEditor()?.string ?? numberField.stringValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !number.isEmpty else { return }
        dial(number)
    }
}
