//
//  CallHistoryViewController.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

import Cocoa

final class CallHistoryViewController: NSViewController {
    @objc var correctNumber: ((String) -> Void)?

    @objc var keyView: NSView {
        return tableView
    }
    @objc weak var target: CallHistoryViewEventTarget? {
        didSet {
            target?.shouldReloadData()
        }
    }
    var recordCount: Int {
        return records.count
    }
    private var records: [PresentationCallHistoryRecord] = []
    private let pasteboard = NSPasteboard.general
    private var formatsPhoneNumbers = UserDefaults.standard.bool(forKey: UserDefaultsKeys.formatTelephoneNumbers)
    private var splitsLastFourDigits = UserDefaults.standard.bool(forKey: UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits)
    @IBOutlet private weak var tableView: NSTableView!

    init() {
        super.init(nibName: "CallHistoryViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(formattingSettingsDidChange),
                                               name: UserDefaults.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(localContactsDidChange),
                                               name: LocalContacts.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(localContactsDidChange),
                                               name: DialPlan.changed, object: nil)
        tableView.enclosingScrollView?.hasHorizontalScroller = false
        tableView.enclosingScrollView?.horizontalScrollElasticity = .none
        tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
        // The icon column is fixed; only the name column absorbs available width.
        tableView.tableColumns[0].resizingMask = []
        tableView.tableColumns[1].minWidth = 80
        tableView.tableColumns[1].maxWidth = 10_000
        tableView.tableColumns[1].resizingMask = .autoresizingMask
        tableView.tableColumns[2].resizingMask = []
        tableView.tableColumns[2].width = 140
        let saveContact = NSMenuItem(title: NSLocalizedString("Save Contact…", comment: "Save contact from call history"),
                                     action: #selector(saveContactFromHistory(_:)), keyEquivalent: "")
        saveContact.target = self
        tableView.menu?.insertItem(saveContact, at: 2)
        let correct = NSMenuItem(title: NSLocalizedString("Correct Number", comment: "Edit a history number without calling"),
                                 action: #selector(correctNumberFromHistory(_:)), keyEquivalent: "")
        correct.target = self
        tableView.menu?.insertItem(correct, at: 1)
        target?.shouldReloadData()
    }

    @objc func correctNumberFromHistory(_ sender: Any) {
        let row = clickedOrSelectedRow()
        guard records.indices.contains(row), let address = records[row].sourceAddress, !address.isEmpty else { return }
        correctNumber?(address)
    }

    @objc nonisolated private func formattingSettingsDidChange() {
        Task { @MainActor in
            let enabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.formatTelephoneNumbers)
            let splitsDigits = UserDefaults.standard.bool(forKey: UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits)
            guard enabled != formatsPhoneNumbers || splitsDigits != splitsLastFourDigits else { return }
            formatsPhoneNumbers = enabled
            splitsLastFourDigits = splitsDigits
            target?.shouldReloadData()
        }
    }

    @objc nonisolated private func localContactsDidChange() {
        Task { @MainActor in target?.shouldReloadData() }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        tableView.sizeToFit()
    }

    override func keyDown(with event: NSEvent) {
        if isReturnKey(event) {
            pickRecord(at: tableView.selectedRow)
        } else if isDeleteKey(event) {
            removeRecord(at: tableView.selectedRow)
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func updateNextKeyView(_ view: NSView) {
        keyView.nextKeyView = view
    }

    @IBAction func didDoubleClick(_ sender: NSTableView) {
        guard sender.clickedRow != -1 else { return }
        pickRecord(at: sender.clickedRow)
    }

    @IBAction func makeCall(_ sender: Any) {
        guard clickedOrSelectedRow() != -1 else { return }
        pickRecord(at: clickedOrSelectedRow())
    }

    @IBAction func copy(_ sender: Any) {
        guard clickedOrSelectedRow() != -1 else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects([records[clickedOrSelectedRow()]])
    }

    @objc func saveContactFromHistory(_ sender: Any) {
        let row = clickedOrSelectedRow()
        guard records.indices.contains(row), let accountID = target?.accountID,
              let number = records[row].sourceNumber,
              let draft = LocalContacts.shared.draftFromHistory(number: number, accountID: accountID,
                                                                isIncoming: records[row].isIncoming) else { return }
        LocalContactsWindowController.shared.openDraft(contact: draft.contact, number: draft.number, needsReview: draft.needsReview)
    }

    @IBAction func delete(_ sender: Any) {
        guard clickedOrSelectedRow() != -1 else { return }
        removeRecord(at: clickedOrSelectedRow())
    }

    @IBAction func deleteAll(_ sender: Any) {
        Task {
            if await makeDeleteAllAlert().beginSheetModal(for: view.window!) == .alertFirstButtonReturn {
                target?.shouldRemoveAllRecords()
            }
        }
    }
}

private extension CallHistoryViewController {
    func pickRecord(at index: Int) {
        guard !records.isEmpty else { return }
        target?.didPickRecord(withIdentifier: records[index].identifier)
    }

    func removeRecord(at index: Int) {
        guard !records.isEmpty else { return }
        let record = records[index]
        Task {
            if await makeDeleteRecordAlert(recordName: record.name).beginSheetModal(for: view.window!) == .alertFirstButtonReturn {
                removeTableViewRow(index, andRecordWithIdentifier: record.identifier)
            }
        }
    }

    func isReturnKey(_ event: NSEvent) -> Bool {
        return event.keyCode == 0x24
    }

    func isDeleteKey(_ event: NSEvent) -> Bool {
        return event.keyCode == 0x33 || event.keyCode == 0x75
    }

    func removeTableViewRow(_ row: Int, andRecordWithIdentifier identifier: String) {
        tableView.removeRows(at: IndexSet(integer: row), withAnimation: .slideUp)
        records.remove(at: row)
        target?.shouldRemoveRecord(withIdentifier: identifier)
    }

    func clickedOrSelectedRow() -> Int {
        return tableView.clickedRow != -1 ? tableView.clickedRow : tableView.selectedRow
    }
}

extension CallHistoryViewController: CallHistoryView {
    func show(_ records: [PresentationCallHistoryRecord]) {
        let oldRecords = self.records
        let oldIndex = tableView.selectedRow
        self.records = records
        reloadTableView(old: oldRecords, new: records)
        restoreSelection(oldIndex: oldIndex, old: oldRecords, new: records)
    }

    private func reloadTableView(old: [PresentationCallHistoryRecord], new: [PresentationCallHistoryRecord]) {
        let diff = ArrayDifference(before: old, after: new)
        if case .prepended(count: let count) = diff, count <= 2 {
            tableView.insertRows(at: IndexSet(integersIn: 0..<count), withAnimation: .slideDown)
        } else if case .shiftedByOne = diff {
            tableView.beginUpdates()
            tableView.insertRows(at: IndexSet(integer: 0), withAnimation: .slideDown)
            tableView.removeRows(at: IndexSet(integer: old.count), withAnimation: .slideDown)
            tableView.endUpdates()
        } else {
            tableView.reloadData()
        }
    }

    private func restoreSelection(oldIndex: Int, old: [PresentationCallHistoryRecord], new: [PresentationCallHistoryRecord]) {
        guard !records.isEmpty else { return }
        tableView.selectRowIndexes(
            IndexSet(integer: RestoredSelectionIndex(indexBefore: oldIndex, before: old, after: new).value),
            byExtendingSelection: false
        )
    }
}

extension CallHistoryViewController: NSTableViewDataSource {
    func numberOfRows(in view: NSTableView) -> Int {
        return records.count
    }

    func tableView(_ view: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
        return records[row]
    }
}

extension CallHistoryViewController: NSTableViewDelegate {
    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSeparators()
    }

    func tableViewSelectionIsChanging(_ notification: Notification) {
        updateSeparators()
    }

    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        switch edge {
        case .trailing:
            return [makeDeleteAction()]
        case .leading:
            return []
        @unknown default:
            return []
        }
    }

    private func updateSeparators() {
        tableView.enumerateAvailableRowViews { (view, _) in
            view.needsDisplay = true
        }
    }

    private func makeDeleteAction() -> NSTableViewRowAction {
        let a = NSTableViewRowAction(
            style: .destructive,
            title: NSLocalizedString("Delete", comment: "Delete button."),
            handler: removeRowAndRecord
        )
        a.image = NSImage(named: NSImage.touchBarDeleteTemplateName)
        return a
    }

    private func removeRowAndRecord(action: NSTableViewRowAction, row: Int) {
        removeTableViewRow(row, andRecordWithIdentifier: records[row].identifier)
    }
}

extension CallHistoryViewController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(correctNumberFromHistory(_:)):
            let row = clickedOrSelectedRow()
            return records.indices.contains(row) && !(records[row].sourceAddress ?? "").isEmpty && correctNumber != nil
        case #selector(saveContactFromHistory(_:)):
            let row = clickedOrSelectedRow()
            guard records.indices.contains(row), let accountID = target?.accountID,
                  let number = records[row].sourceNumber else { return false }
            return LocalContacts.shared.draftFromHistory(number: number, accountID: accountID,
                                                         isIncoming: records[row].isIncoming) != nil
        case #selector(copy(_:)), #selector(makeCall), #selector(delete), #selector(deleteAll):
            return !records.isEmpty
        default:
            return false
        }
    }
}

@MainActor
private func makeDeleteRecordAlert(recordName name: String) -> NSAlert {
    return makeDeletionAlert(
        messageText: String(
            format: NSLocalizedString(
                "Are you sure you want to delete the record “%@”?", comment: "Call history record removal alert."
            ),
            name
        )
    )
}

@MainActor
private func makeDeleteAllAlert() -> NSAlert {
    return makeDeletionAlert(
        messageText: NSLocalizedString(
            "Are you sure you want to delete all records?", comment: "Call history all records removal alert."
        )
    )
}

@MainActor
private func makeDeletionAlert(messageText text: String) -> NSAlert {
    let a = NSAlert()
    a.messageText = text
    a.informativeText = NSLocalizedString(
        "This action cannot be undone.", comment: "Call history record removal alert informative text."
    )
    let delete = a.addButton(withTitle: NSLocalizedString("Delete", comment: "Delete button."))
    delete.hasDestructiveAction = true
    a.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button.")).keyEquivalent = "\u{1b}"
    return a
}
