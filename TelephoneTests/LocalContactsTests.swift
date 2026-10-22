import AppKit
import XCTest
import UseCases

@MainActor
final class LocalContactsTests: XCTestCase {
    private func withStore(_ body: (LocalContacts, UserDefaults) throws -> Void) rethrows {
        let suite = "SwiftDial-Contacts-Test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(LocalContacts(defaults: defaults), defaults)
    }

    func testPersistsOriginalNumberAndSupportsEditDelete() throws {
        try withStore { store, defaults in
            try store.save(name: "Maria", number: "(41) 3333-4444")
            let saved = LocalContacts(defaults: defaults).all[0]
            XCTAssertEqual(saved.number, "(41) 3333-4444")
            XCTAssertEqual(saved.name, "Maria")
            try store.save(id: saved.id, name: "Maria Silva", number: "118")
            XCTAssertEqual(store.all.count, 1)
            XCTAssertEqual(store.all[0].id, saved.id)
            XCTAssertEqual(store.match(number: "118", accountID: "a")?.name, "Maria Silva")
            store.remove(id: saved.id)
            XCTAssertTrue(LocalContacts(defaults: defaults).all.isEmpty)
        }
    }

    func testRecognizesRawAndRoutedNumberWithoutChangingSavedNumber() throws {
        try withStore { store, defaults in
            defaults.set([["UUID": "a", "DialPlan": "xxx|xxxxxxxx|xxxxxxxxx|0800x.|0300x.|<0:043>x."]], forKey: "Accounts")
            try store.save(name: "Office", number: "04133334444")
            XCTAssertEqual(store.match(number: "04133334444", accountID: "a")?.name, "Office")
            XCTAssertEqual(store.match(number: "0434133334444", accountID: "a")?.name, "Office")
            XCTAssertNil(store.match(number: "0434133334444", accountID: "other"))
            XCTAssertEqual(store.all[0].number, "04133334444")
        }
    }

    func testBrazilianCountryCodeFormattingAndDuplicateValidation() throws {
        try withStore { store, _ in
            try store.save(name: "Maria", number: "(11) 99999-8888")
            XCTAssertEqual(store.match(number: "+5511999998888", accountID: "a")?.name, "Maria")
            XCTAssertThrowsError(try store.save(name: "Duplicate", number: "5511999998888"))
            XCTAssertNil(store.match(number: "999998888", accountID: "a"))
            XCTAssertNil(store.match(number: "sip:11999998888@example.com", accountID: "a"))
        }
    }

    func testAmbiguousAliasesDoNotChooseWrongContactAndExactMatchWins() throws {
        try withStore { store, defaults in
            defaults.set([["UUID": "a", "DialPlan": "<1:9>xx|<2:9>xx"]], forKey: "Accounts")
            try store.save(name: "One", number: "118")
            try store.save(name: "Two", number: "218")
            XCTAssertNil(store.match(number: "918", accountID: "a"))
            try store.save(name: "Exact", number: "918")
            XCTAssertEqual(store.match(number: "918", accountID: "a")?.name, "Exact")
        }
    }

    func testInvalidInputDoesNotOverwriteExistingContact() throws {
        try withStore { store, _ in
            try store.save(name: "Office", number: "118")
            let original = store.all[0]
            for number in ["", "---", "*#", "abc118", "sip:118@example.com", "11+8", "118\n123"] {
                XCTAssertThrowsError(try store.save(id: original.id, name: "Changed", number: number))
            }
            XCTAssertThrowsError(try store.save(id: original.id, name: " ", number: "118"))
            XCTAssertEqual(store.all, [original])
        }
    }

    func testHistoryMatchingPrefersLocalNameAndRetainsOriginalNumber() async throws {
        let suite = "SwiftDial-Contacts-History-Test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([["UUID": "a", "DialPlan": "<0:043>x."]], forKey: "Accounts")
        let store = LocalContacts(defaults: defaults)
        try store.save(name: "Office", number: "04133334444")
        let matcher = LocalContactMatching(fallback: ContactFallback(), accountID: "a", contacts: store)
        let result = await matcher.match(for: URI(user: "0434133334444", host: "", displayName: "Old name"))
        XCTAssertEqual(result?.name, "Office")
        if case let .phone(number, _) = result?.address { XCTAssertEqual(number, "04133334444") }
        else { XCTFail("Expected original local phone number") }
        let unknown = await matcher.match(for: URI(user: "119", host: "", displayName: ""))
        XCTAssertEqual(unknown?.name, "System contact")
        try store.save(id: store.all[0].id, name: "Updated Office", number: "04133334444")
        let updated = await matcher.match(for: URI(user: "0434133334444", host: "", displayName: ""))
        XCTAssertEqual(updated?.name, "Updated Office")
    }

    func testHistoryDraftRecoversPrefixWithoutSavingAndKeepsIncomingNumber() throws {
        try withStore { store, defaults in
            defaults.set([["UUID": "a", "DialPlan": "xxx|xxxxxxxx|xxxxxxxxx|0800x.|0300x.|<0:043>x."]], forKey: "Accounts")
            let draft = try XCTUnwrap(store.draftFromHistory(number: "0434133334444", accountID: "a", isIncoming: false))
            XCTAssertEqual(draft.number, "04133334444")
            XCTAssertTrue(draft.needsReview)
            XCTAssertTrue(store.all.isEmpty)
            XCTAssertEqual(store.draftFromHistory(number: "0434133334444", accountID: "a", isIncoming: true)?.number, "0434133334444")
            for number in ["118", "08001234567", "03003376786", "04133334444"] {
                XCTAssertEqual(store.draftFromHistory(number: number, accountID: "a", isIncoming: false)?.number, number)
            }
            XCTAssertNil(store.draftFromHistory(number: "alice@example.com", accountID: "a", isIncoming: false))
        }
    }

    func testHistoryDraftReusesSavedContactAndHandlesPlusSubstitution() throws {
        try withStore { store, defaults in
            defaults.set([["UUID": "a", "DialPlan": "<0:043>x."]], forKey: "Accounts")
            try store.save(name: "Office", number: "04133334444")
            let draft = try XCTUnwrap(store.draftFromHistory(number: "0434133334444", accountID: "a", isIncoming: false))
            XCTAssertEqual(draft.contact?.id, store.all[0].id)
            XCTAssertEqual(draft.contact?.name, "Office")
            XCTAssertEqual(draft.number, "04133334444")
            XCTAssertFalse(draft.needsReview)
            defaults.set([["UUID": "b", "DialPlan": "x.", "SubstitutePlusCharacter": true,
                           "PlusCharacterSubstitutionString": "00"]], forKey: "Accounts")
            XCTAssertEqual(store.draftFromHistory(number: "00442079460123", accountID: "b", isIncoming: false)?.number, "+442079460123")
        }
    }

    func testAmbiguousHistoryPrefixIsNotRemoved() throws {
        try withStore { store, defaults in
            defaults.set([["UUID": "a", "DialPlan": "<0:9>xx|<1:9>xx"]], forKey: "Accounts")
            let draft = try XCTUnwrap(store.draftFromHistory(number: "918", accountID: "a", isIncoming: false))
            XCTAssertEqual(draft.number, "918")
            XCTAssertTrue(draft.needsReview)
        }
    }

    func testDoubleClickPassesSavedNumberToNormalDialingWithoutChangingContact() throws {
        try withStore { store, _ in
            try store.save(name: "Office", number: "04133334444")
            let original = store.all
            let controller = LocalContactsWindowController(contacts: store)
            defer { controller.close() }
            var requested: [String] = []
            var routed: String?
            controller.placeCall = { number in
                requested.append(number)
                routed = try? DialPlan("<0:043>x.").apply(to: number)
                return true
            }
            let table = ClickedContactTable()
            table.row = 0
            controller.callContactFromTable(table)
            XCTAssertEqual(requested, ["04133334444"])
            XCTAssertEqual(routed, "0434133334444")
            XCTAssertEqual(store.all, original)
            table.row = -1
            controller.callContactFromTable(table)
            table.row = 1
            controller.callContactFromTable(table)
            XCTAssertEqual(requested.count, 1)
        }
    }

    func testUnavailableCallingKeepsContactAndShowsMessage() throws {
        try withStore { store, _ in
            try store.save(name: "Office", number: "118")
            let controller = LocalContactsWindowController(contacts: store)
            defer { controller.close() }
            controller.placeCall = { _ in false }
            let table = ClickedContactTable()
            table.row = 0
            controller.callContactFromTable(table)
            func fields(in view: NSView) -> [NSTextField] {
                (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
            }
            XCTAssertTrue(fields(in: controller.window!.contentView!).contains {
                $0.stringValue == NSLocalizedString("No account is available to place this call.", comment: "")
            })
            XCTAssertEqual(store.all[0].number, "118")
        }
    }

    func testPlusSubstitutionAlias() throws {
        try withStore { store, defaults in
            defaults.set([["UUID": "a", "DialPlan": "x.", "SubstitutePlusCharacter": true,
                           "PlusCharacterSubstitutionString": "00"]], forKey: "Accounts")
            try store.save(name: "International", number: "+442079460123")
            XCTAssertEqual(store.match(number: "00442079460123", accountID: "a")?.name, "International")
        }
    }
}

@ContactsActor
private final class ContactFallback: ContactMatching {
    nonisolated init() {}
    func match(for uri: URI) async -> MatchedContact? {
        MatchedContact(name: "System contact", address: .phone(number: uri.user, label: ""))
    }
}

@MainActor
private final class ClickedContactTable: NSTableView {
    var row = -1
    override var clickedRow: Int { row }
}

@MainActor
final class UserDirectoryTests: XCTestCase {
    func testMicroSIPJSONAndValidation() throws {
        let response = try JSONDecoder().decode(DirectoryResponse.self, from: Data("""
        {"refresh":300,"silent":0,"items":[{"name":"Ana","number":"002","presence":0},{"name":"Fernando","number":"201"}]}
        """.utf8))
        XCTAssertEqual(response.refresh, 300)
        XCTAssertEqual(try response.contacts().map(\.number), ["002", "201"])
        for json in [
            "{\"items\":[{\"name\":\"A\",\"number\":201}]}",
            "{\"items\":[{\"name\":\"A\",\"number\":\"abc\"}]}",
            "{\"items\":[{\"name\":\"A\",\"number\":\"201\"},{\"name\":\"B\",\"number\":\"201\"}]}",
            "{\"presence\":[]}",
            "{\"items\":[{\"name\":\" \",\"number\":\"201\"}]}"
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(DirectoryResponse.self, from: Data(json.utf8)).contacts())
        }
    }

    func testRefreshCacheFailureEmptySnapshotAndLocalSeparation() async throws {
        let suite = "SwiftDial-Directory-Test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("https://directory.example/contacts", forKey: "SwiftDialDirectoryURL")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DirectoryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let directory = UserDirectory(defaults: defaults, session: session)
        let local = LocalContacts(defaults: defaults)
        try local.save(name: "Personal", number: "201")
        DirectoryURLProtocol.body = Data("""
        {"refresh":300,"items":[{"name":"Company","number":"201"}]}
        """.utf8)
        let delay = await directory.refresh()
        XCTAssertEqual(delay, 300)
        XCTAssertEqual(directory.all.first?.name, "Company")
        XCTAssertEqual(local.all.first?.name, "Personal")
        XCTAssertEqual(UserDirectory(defaults: defaults).all, directory.all)
        let previous = directory.all
        DirectoryURLProtocol.statusCode = 503
        let serverRetry = await directory.refresh()
        XCTAssertEqual(serverRetry, 300)
        XCTAssertEqual(directory.all, previous)
        DirectoryURLProtocol.statusCode = 200
        DirectoryURLProtocol.body = Data("not json".utf8)
        let retry = await directory.refresh()
        XCTAssertEqual(retry, 300)
        XCTAssertEqual(directory.all, previous)
        XCTAssertEqual(UserDirectory(defaults: defaults).all, previous)
        DirectoryURLProtocol.body = Data("{\"items\":[]}".utf8)
        let stopped = await directory.refresh()
        XCTAssertEqual(stopped, 0)
        XCTAssertTrue(directory.all.isEmpty)
        XCTAssertEqual(local.all.count, 1)
        XCTAssertThrowsError(try directory.configure("file:///tmp/contacts.json"))
        XCTAssertThrowsError(try directory.configure("https://user:password@example.com/contacts"))
        XCTAssertEqual(directory.urlString, "https://directory.example/contacts")
        try directory.configure("https://other.example/contacts")
        XCTAssertTrue(directory.all.isEmpty)
        XCTAssertNil(defaults.data(forKey: "SwiftDialDirectoryCache"))
        try directory.configure("")
        XCTAssertTrue(directory.all.isEmpty)
        XCTAssertNil(defaults.data(forKey: "SwiftDialDirectoryCache"))
        XCTAssertEqual(local.all.count, 1)
    }

    func testDirectoryCallsOriginalNumberAndUsesExistingMatching() throws {
        let suite = "SwiftDial-Directory-Calling-Test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("https://directory.example/contacts", forKey: "SwiftDialDirectoryURL")
        defaults.set(Data("{\"items\":[{\"name\":\"Office\",\"number\":\"04133334444\"}]}".utf8), forKey: "SwiftDialDirectoryCache")
        defaults.set([["UUID": "a", "DialPlan": "<0:043>x."]], forKey: "Accounts")
        let directory = UserDirectory(defaults: defaults)
        let local = LocalContacts(defaults: defaults)
        XCTAssertEqual(local.match(number: "0434133334444", accountID: "a", contacts: directory.all)?.name, "Office")
        let controller = UserDirectoryWindowController(directory: directory)
        defer { controller.close() }
        var called: [String] = []
        controller.placeCall = { called.append($0); return true }
        let table = ClickedContactTable()
        table.row = 0
        controller.callContact(table)
        table.row = -1
        controller.callContact(table)
        XCTAssertEqual(called, ["04133334444"])
        XCTAssertTrue(local.all.isEmpty)
    }
}

private final class DirectoryURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var statusCode = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
