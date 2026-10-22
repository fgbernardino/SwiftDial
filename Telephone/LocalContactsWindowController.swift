import AppKit

@MainActor
final class LocalContactsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    @objc static let shared = LocalContactsWindowController()
    @objc var placeCall: ((String) -> Bool)?
    private let store: LocalContacts
    private let table = NSTableView()
    private let nameField = NSTextField(string: "")
    private let numberField = NSTextField(string: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private var contacts: [LocalContact] = []
    private var selectedID: String?

    init(contacts: LocalContacts = .shared) {
        self.store = contacts
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 480),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = NSLocalizedString("Local Contacts", comment: "Internal address book")
        window.center()
        for (id, title, width) in [("name", "Name", 230.0), ("number", "Phone number", 220.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = NSLocalizedString(title, comment: "Contact field")
            column.width = width
            table.addTableColumn(column)
        }
        table.target = self
        table.doubleAction = #selector(callContactFromTable(_:))
        table.delegate = self
        table.dataSource = self
        table.allowsMultipleSelection = false
        table.setAccessibilityLabel(window.title)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        let buttons = NSStackView(views: [button("New", #selector(newContact)), button("Save", #selector(saveContact)), button("Delete", #selector(deleteContact))])
        buttons.spacing = 8
        nameField.setAccessibilityLabel(NSLocalizedString("Name", comment: "Contact field"))
        numberField.setAccessibilityLabel(NSLocalizedString("Phone number", comment: "Contact field"))
        let stack = NSStackView(views: [scroll, NSTextField(labelWithString: NSLocalizedString("Name", comment: "Contact field")), nameField,
                                      NSTextField(labelWithString: NSLocalizedString("Phone number", comment: "Contact field")), numberField,
                                      NSTextField(wrappingLabelWithString: NSLocalizedString("Saved only in SwiftDial. Enter the original number, without the dial-plan prefix.", comment: "Contacts help")), buttons, message])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            nameField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            numberField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            message.widthAnchor.constraint(equalTo: stack.widthAnchor),
            message.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: NSLocalizedString(title, comment: "Contacts action"), target: self, action: action)
    }

    @objc func open(_ sender: Any?) {
        showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func openDraft(contact: LocalContact?, number: String, needsReview: Bool) {
        if !nameField.stringValue.isEmpty || !numberField.stringValue.isEmpty {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Replace the current contact form?", comment: "Opening a history contact")
            alert.informativeText = NSLocalizedString("Unsaved changes in the form will be discarded.", comment: "Opening a history contact")
            alert.addButton(withTitle: NSLocalizedString("Continue", comment: "Opening a history contact"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        reload()
        newContact()
        selectedID = contact?.id
        nameField.stringValue = contact?.name ?? ""
        numberField.stringValue = number
        message.stringValue = needsReview ? NSLocalizedString("Check the original number before saving; recovery uses the current dial plan.", comment: "History contact prefill") : ""
        open(nil)
        window?.makeFirstResponder(nameField)
    }

    @objc func callContactFromTable(_ sender: NSTableView) {
        guard contacts.indices.contains(sender.clickedRow) else { return }
        // Dial the saved number, never an unsaved edit or a rewritten history number.
        let number = contacts[sender.clickedRow].number
        if placeCall?(number) == true {
            message.stringValue = ""
        } else {
            message.stringValue = NSLocalizedString("No account is available to place this call.", comment: "Local contacts dialing")
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { contacts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        NSTextField(labelWithString: tableColumn?.identifier.rawValue == "name" ? contacts[row].name : contacts[row].number)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard contacts.indices.contains(table.selectedRow) else { return }
        let contact = contacts[table.selectedRow]
        selectedID = contact.id
        nameField.stringValue = contact.name
        numberField.stringValue = contact.number
        message.stringValue = ""
    }

    @objc private func newContact() {
        selectedID = nil
        table.deselectAll(nil)
        nameField.stringValue = ""
        numberField.stringValue = ""
        message.stringValue = ""
        window?.makeFirstResponder(nameField)
    }

    @objc private func saveContact() {
        window?.makeFirstResponder(nil)
        do {
            try store.save(id: selectedID, name: nameField.stringValue, number: numberField.stringValue)
            reload()
            newContact()
        } catch { message.stringValue = error.localizedDescription }
    }

    @objc private func deleteContact() {
        guard let id = selectedID else { return }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Delete this contact?", comment: "Contact deletion")
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: "Contact deletion"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Contact deletion"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.remove(id: id)
        reload()
        newContact()
    }

    private func reload() {
        contacts = store.all
        table.reloadData()
    }
}
