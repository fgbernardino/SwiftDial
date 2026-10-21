import AppKit

@MainActor
final class UserDirectoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    @objc static let shared = UserDirectoryWindowController()
    @objc var placeCall: ((String) -> Bool)?
    private let directory: UserDirectory
    private let urlField = NSTextField(string: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let table = NSTableView()
    private var contacts: [LocalContact] = []

    init(directory: UserDirectory = .shared) {
        self.directory = directory
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = NSLocalizedString("User Directory", comment: "Directory window")
        window.minSize = NSSize(width: 480, height: 320)
        window.center()
        window.setFrameAutosaveName("UserDirectory")
        urlField.stringValue = directory.urlString
        urlField.placeholderString = "https://example.com/api/phone-directory"
        urlField.setAccessibilityLabel(NSLocalizedString("Directory URL", comment: "Directory setting"))
        for (id, title, width) in [("name", "Name", 290.0), ("number", "Phone number", 180.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = NSLocalizedString(title, comment: "Contact field")
            column.width = width
            table.addTableColumn(column)
        }
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(callContact(_:))
        table.allowsMultipleSelection = false
        table.setAccessibilityLabel(window.title)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        let buttons = NSStackView(views: [
            NSButton(title: NSLocalizedString("Save URL", comment: "Directory action"), target: self, action: #selector(saveURL)),
            NSButton(title: NSLocalizedString("Refresh", comment: "Directory action"), target: self, action: #selector(refreshDirectory)),
            NSButton(title: NSLocalizedString("Call", comment: "Directory action"), target: self, action: #selector(callSelected))
        ])
        buttons.spacing = 8
        let help = NSTextField(wrappingLabelWithString: NSLocalizedString("Read-only shared contacts. Local contacts stay separate. Leave the URL empty to disable.", comment: "Directory help"))
        let stack = NSStackView(views: [NSTextField(labelWithString: NSLocalizedString("Directory URL", comment: "Directory setting")), urlField, buttons, help, scroll, message])
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
            urlField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
            message.widthAnchor.constraint(equalTo: stack.widthAnchor),
            message.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: UserDirectory.changed, object: directory)
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc func open(_ sender: Any?) {
        showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    @objc private func saveURL() {
        do {
            try directory.configure(urlField.stringValue)
            urlField.stringValue = directory.urlString
        } catch { message.stringValue = error.localizedDescription }
    }

    @objc private func refreshDirectory() { directory.start() }

    @objc private func reload() {
        let selected = contacts.indices.contains(table.selectedRow) ? contacts[table.selectedRow].id : nil
        contacts = directory.all
        table.reloadData()
        if let row = contacts.firstIndex(where: { $0.id == selected }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        message.stringValue = directory.status
    }

    @objc func callContact(_ sender: NSTableView) { call(row: sender.clickedRow) }
    @objc private func callSelected() { call(row: table.selectedRow) }

    private func call(row: Int) {
        guard contacts.indices.contains(row) else { return }
        if placeCall?(contacts[row].number) != true {
            message.stringValue = NSLocalizedString("No account is available to place this call.", comment: "Local contacts dialing")
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { contacts.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        NSTextField(labelWithString: tableColumn?.identifier.rawValue == "name" ? contacts[row].name : contacts[row].number)
    }
}
