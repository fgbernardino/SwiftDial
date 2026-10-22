import AppKit

@MainActor
@objcMembers
final class DialPlanEditor: NSObject {
    private let plan = NSTextField(string: "")
    private let number = NSTextField(string: "")
    private let result = NSTextField(wrappingLabelWithString: "")

    @objc(editAccountID:)
    static func edit(accountID: String) {
        let editor = DialPlanEditor()
        editor.edit(accountID)
    }

    private func edit(_ accountID: String) {
        let defaults = UserDefaults.standard
        let accounts = defaults.array(forKey: UserDefaultsKeys.accounts) as? [[String: Any]] ?? []
        guard let account = accounts.first(where: { $0[AKSIPAccountKeys.uuid] as? String == accountID }) else { return }
        plan.stringValue = account[DialPlan.settingsKey] as? String ?? ""
        plan.placeholderString = "xxx|xxxxxxxx|xxxxxxxxx|0800x.|0300x.|<0:043>x."
        plan.setAccessibilityLabel(NSLocalizedString("Dial plan", comment: "Dial plan editor"))
        number.placeholderString = "04133334444"
        number.setAccessibilityLabel(NSLocalizedString("Test number", comment: "Dial plan editor"))
        let test = NSButton(title: NSLocalizedString("Test without calling", comment: "Dial plan editor"), target: self, action: #selector(testNumber))
        let stack = NSStackView(views: [plan, NSTextField(labelWithString: NSLocalizedString("Test number", comment: "Dial plan editor")), number, test, result])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        for field in [plan, number, result] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 460).isActive = true
        }
        result.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        stack.frame.size = stack.fittingSize
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Dial plan", comment: "Dial plan editor")
        alert.informativeText = NSLocalizedString("MicroSIP syntax. First matching rule wins; other numbers are blocked. Leave empty to disable. Applies before replacing +. History numbers use the plan without repeating recognized replacements. Explicit SIP addresses and call-window redial are used as stored.", comment: "Dial plan help")
        alert.accessoryView = stack
        alert.addButton(withTitle: NSLocalizedString("Save", comment: "Save dial plan"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel dial plan"))
        alert.window.initialFirstResponder = plan
        while alert.runModal() == .alertFirstButtonReturn {
            do {
                _ = try DialPlan(plan.stringValue)
                var current = defaults.array(forKey: UserDefaultsKeys.accounts) as? [[String: Any]] ?? []
                guard let index = current.firstIndex(where: { $0[AKSIPAccountKeys.uuid] as? String == accountID }) else { return }
                current[index][DialPlan.settingsKey] = plan.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                defaults.set(current, forKey: UserDefaultsKeys.accounts)
                NotificationCenter.default.post(name: DialPlan.changed, object: accountID)
                return
            } catch { result.stringValue = error.localizedDescription }
        }
    }

    @objc private func testNumber() {
        do {
            let formatter = AKTelephoneNumberFormatter()
            let raw = number.stringValue
            let normalized = raw.rangeOfCharacter(from: .letters) == nil ? (formatter.telephoneNumber(from: raw) ?? raw) : raw
            result.stringValue = try DialPlan(plan.stringValue).apply(to: normalized)
        } catch { result.stringValue = error.localizedDescription }
    }
}
