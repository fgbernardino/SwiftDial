import Foundation
import UseCases

struct LocalContact: Equatable, Sendable {
    let id: String
    let name: String
    let number: String
}

@MainActor
final class LocalContacts: NSObject {
    @objc static let shared = LocalContacts(defaults: .standard)
    static let changed = Notification.Name("SwiftDialLocalContactsChanged")
    private static let key = "SwiftDialLocalContacts"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    var all: [LocalContact] {
        (defaults.array(forKey: Self.key) as? [[String: String]] ?? []).compactMap {
            guard let id = $0["id"], let name = $0["name"], let number = $0["number"] else { return nil }
            return LocalContact(id: id, name: name, number: number)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    enum Failure: LocalizedError {
        case invalid, duplicate
        var errorDescription: String? {
            NSLocalizedString(self == .invalid ? "Enter a name and a valid phone number." : "This number is already saved.", comment: "Local contacts validation")
        }
    }

    func save(id: String? = nil, name: String, number: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 200, Self.normalized(number) != nil else { throw Failure.invalid }
        var contacts = all
        guard !contacts.contains(where: { $0.id != id && Self.canonical($0.number) == Self.canonical(number) }) else { throw Failure.duplicate }
        let contact = LocalContact(id: id ?? UUID().uuidString, name: name, number: number)
        if let index = contacts.firstIndex(where: { $0.id == id }) { contacts[index] = contact }
        else { contacts.append(contact) }
        persist(contacts)
    }

    func remove(id: String) { persist(all.filter { $0.id != id }) }

    private func persist(_ contacts: [LocalContact]) {
        // Store the entered number only; dial-plan aliases are computed at lookup time.
        defaults.set(contacts.map { ["id": $0.id, "name": $0.name, "number": $0.number] }, forKey: Self.key)
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    func match(number: String, accountID: String) -> LocalContact? {
        match(number: number, accountID: accountID, contacts: all)
    }

    func match(number: String, accountID: String, contacts: [LocalContact]) -> LocalContact? {
        guard let wanted = Self.canonical(number) else { return nil }
        let exact = contacts.filter { Self.canonical($0.number) == wanted }
        if !exact.isEmpty { return exact.count == 1 ? exact[0] : nil }
        let accounts = defaults.array(forKey: UserDefaultsKeys.accounts) as? [[String: Any]] ?? []
        let account = accounts.first { $0[AKSIPAccountKeys.uuid] as? String == accountID } ?? [:]
        guard let plan = try? DialPlan(account[DialPlan.settingsKey] as? String ?? "") else { return nil }
        let aliases = contacts.filter { contact in
            guard let raw = Self.normalized(contact.number), var routed = try? plan.apply(to: raw) else { return false }
            if account[UserDefaultsKeys.substitutePlusCharacter] as? Bool == true, routed.hasPrefix("+") {
                routed = (account[UserDefaultsKeys.plusCharacterSubstitutionString] as? String ?? "") + routed.dropFirst()
            }
            return Self.canonical(routed) == wanted
        }
        return aliases.count == 1 ? aliases[0] : nil
    }

    func draftFromHistory(number: String, accountID: String, isIncoming: Bool)
        -> (contact: LocalContact?, number: String, needsReview: Bool)? {
        guard let normalized = Self.normalized(number) else { return nil }
        if let contact = match(number: number, accountID: accountID) {
            return (contact, contact.number, false)
        }
        // Incoming caller IDs were not routed through our outgoing dial plan.
        if isIncoming { return (nil, normalized, false) }
        let accounts = defaults.array(forKey: UserDefaultsKeys.accounts) as? [[String: Any]] ?? []
        let account = accounts.first { $0[AKSIPAccountKeys.uuid] as? String == accountID } ?? [:]
        guard let plan = try? DialPlan(account[DialPlan.settingsKey] as? String ?? "") else {
            return (nil, normalized, true)
        }
        var routed = normalized
        if account[UserDefaultsKeys.substitutePlusCharacter] as? Bool == true,
           let prefix = account[UserDefaultsKeys.plusCharacterSubstitutionString] as? String,
           !prefix.isEmpty, routed.hasPrefix(prefix) {
            routed = "+" + routed.dropFirst(prefix.count)
        }
        guard let original = plan.originalNumber(for: routed) else { return (nil, normalized, true) }
        // History has no saved plan version. Keep the prefill editable for older records.
        return (nil, original, true)
    }

    @objc(nameForNumber:accountID:)
    func name(number: String, accountID: String) -> String? {
        match(number: number, accountID: accountID)?.name
            ?? match(number: number, accountID: accountID, contacts: UserDirectory.shared.all)?.name
    }

    static func normalized(_ value: String) -> String? {
        guard !value.isEmpty, value.count <= 128,
              value.allSatisfy({ "0123456789+*# ()-.".contains($0) }) else { return nil }
        let number = value.filter { "0123456789+*#".contains($0) }
        guard !number.isEmpty, number.contains(where: { $0.isNumber }),
              !number.dropFirst().contains("+") else { return nil }
        return number
    }

    static func canonical(_ value: String) -> String? {
        guard let number = normalized(value) else { return nil }
        let digits = number.hasPrefix("+") ? String(number.dropFirst()) : number
        if digits.hasPrefix("55"), [12, 13].contains(digits.count) { return String(digits.dropFirst(2)) }
        return number
    }
}

@ContactsActor
final class LocalContactMatching: ContactMatching {
    private let fallback: ContactMatching
    private let accountID: String
    private let contacts: LocalContacts

    nonisolated init(fallback: ContactMatching, accountID: String, contacts: LocalContacts) {
        self.fallback = fallback
        self.accountID = accountID
        self.contacts = contacts
    }

    func match(for uri: URI) async -> MatchedContact? {
        if let contact = await contacts.match(number: uri.user, accountID: accountID) {
            return MatchedContact(name: contact.name, address: .phone(number: contact.number, label: ""))
        }
        if let contact = await contacts.match(number: uri.user, accountID: accountID, contacts: UserDirectory.shared.all) {
            return MatchedContact(name: contact.name, address: .phone(number: contact.number, label: ""))
        }
        return await fallback.match(for: uri)
    }
}
