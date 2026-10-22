import Foundation

// MicroSIP digit-map syntax, not unrestricted regular expressions.
@objcMembers
final class DialPlan: NSObject {
    static let settingsKey = "DialPlan"
    @nonobjc static let changed = Notification.Name("SwiftDialDialPlanChanged")
    private let rules: [[Atom]]
    private static let dialCharacters = Set("0123456789+*#")

    enum Failure: LocalizedError {
        case invalid, blocked
        var errorDescription: String? {
            NSLocalizedString(self == .invalid ? "Invalid dial plan." : "Number blocked by dial plan.", comment: "Dial plan error")
        }
    }

    private struct Atom {
        var characters: Set<Character>?
        var literal: String?
        var replacement: String?
        var repeated = false
    }

    @nonobjc init(_ text: String) throws {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 2048 else { throw Failure.invalid }
        if text.hasPrefix("("), text.hasSuffix(")") { text = String(text.dropFirst().dropLast()) }
        if text.isEmpty { rules = []; super.init(); return }
        let patterns = text.components(separatedBy: "|")
        guard patterns.count <= 64 else { throw Failure.invalid }
        rules = try patterns.map { pattern in
            let chars = Array(pattern)
            var atoms: [Atom] = []
            var i = 0
            while i < chars.count {
                let char = chars[i]
                if char == "." {
                    guard !atoms.isEmpty, !atoms[atoms.count - 1].repeated,
                          atoms[atoms.count - 1].replacement == nil else { throw Failure.invalid }
                    atoms[atoms.count - 1].repeated = true
                } else if char == "<" {
                    guard let end = chars[(i + 1)...].firstIndex(of: ">") else { throw Failure.invalid }
                    let parts = String(chars[(i + 1)..<end]).components(separatedBy: ":")
                    guard parts.count == 2, !(parts[0].isEmpty && parts[1].isEmpty),
                          parts.allSatisfy({ Set($0).isSubset(of: Self.dialCharacters) }) else { throw Failure.invalid }
                    atoms.append(Atom(literal: parts[0], replacement: parts[1]))
                    i = end
                } else if char == "[" {
                    guard let end = chars[(i + 1)...].firstIndex(of: "]"), end > i + 1 else { throw Failure.invalid }
                    var accepted: Set<Character> = []
                    var j = i + 1
                    while j < end {
                        guard Self.dialCharacters.contains(chars[j]) else { throw Failure.invalid }
                        if j + 2 < end, chars[j + 1] == "-" {
                            guard let low = chars[j].wholeNumberValue, let high = chars[j + 2].wholeNumberValue,
                                  low <= high else { throw Failure.invalid }
                            for value in low...high { accepted.insert(Character(String(value))) }
                            j += 3
                        } else { accepted.insert(chars[j]); j += 1 }
                    }
                    atoms.append(Atom(characters: accepted))
                    i = end
                } else if char == "x" {
                    atoms.append(Atom())
                } else {
                    guard Self.dialCharacters.contains(char) else { throw Failure.invalid }
                    atoms.append(Atom(literal: String(char)))
                }
                i += 1
            }
            guard !atoms.isEmpty, atoms.count <= 128 else { throw Failure.invalid }
            return atoms
        }
        super.init()
    }

    @nonobjc func apply(to number: String, fromHistory: Bool = false, plusSubstitution: String? = nil) throws -> String {
        guard !rules.isEmpty else { return number }
        guard !number.isEmpty, number.count <= 128,
              Set(number).isSubset(of: Self.dialCharacters) else { throw Failure.blocked }
        if fromHistory {
            // History contains the final routed value, including the account's plus substitution.
            if let prefix = plusSubstitution, number.hasPrefix(prefix) {
                let beforeSubstitution = "+" + number.dropFirst(prefix.count)
                if (try? apply(to: beforeSubstitution, fromHistory: true)) == beforeSubstitution {
                    return number
                }
            }
            // History stores routed numbers, not the original input. Validate an inverse
            // against the ordered plan so an already-produced result is not rewritten.
            for rule in rules where rule.contains(where: { $0.replacement != nil }) {
                let inverse = rule.map { atom -> Atom in
                    guard let replacement = atom.replacement else { return atom }
                    return Atom(literal: replacement, replacement: atom.literal)
                }
                if let original = Self.match(inverse, number),
                   (try? apply(to: original)) == number { return number }
            }
        }
        for rule in rules {
            if let result = Self.match(rule, number) {
                guard !result.isEmpty, result.count <= 128 else { throw Failure.blocked }
                return result
            }
        }
        throw Failure.blocked
    }

    // Recover only a unique, verified prefix replacement; never guess discarded digits.
    @nonobjc func originalNumber(for number: String) -> String? {
        guard !number.isEmpty, number.count <= 128,
              Set(number).isSubset(of: Self.dialCharacters) else { return nil }
        var candidates: Set<String> = []
        if (try? apply(to: number)) == number { candidates.insert(number) }
        for rule in rules {
            guard let first = rule.first, let prefix = first.replacement,
                  !prefix.isEmpty, let originalPrefix = first.literal,
                  rule.dropFirst().allSatisfy({ $0.replacement == nil }),
                  number.hasPrefix(prefix) else { continue }
            let original = originalPrefix + number.dropFirst(prefix.count)
            if (try? apply(to: original)) == number { candidates.insert(original) }
        }
        if candidates.count > 1 { return nil }
        return candidates.first ?? number
    }

    private static func match(_ rule: [Atom], _ number: String) -> String? {
        let input = Array(number)
        // Dynamic programming bounds work even for many overlapping repetitions.
        var suffixes: [Int: String] = [input.count: ""]
        for atom in rule.reversed() {
            var next: [Int: String] = [:]
            for start in stride(from: input.count, through: 0, by: -1) {
                if atom.repeated {
                    if let suffix = suffixes[start] { next[start] = suffix }
                    if start < input.count, Self.matches(atom, input[start]), let tail = next[start + 1] {
                        next[start] = String(input[start]) + tail
                    }
                } else if let literal = atom.literal {
                    let end = start + literal.count
                    if end <= input.count, String(input[start..<end]) == literal, let tail = suffixes[end] {
                        next[start] = (atom.replacement ?? literal) + tail
                    }
                } else if start < input.count, Self.matches(atom, input[start]), let tail = suffixes[start + 1] {
                    next[start] = String(input[start]) + tail
                }
            }
            suffixes = next
        }
        return suffixes[0]
    }

    private static func matches(_ atom: Atom, _ char: Character) -> Bool {
        if let literal = atom.literal { return literal == String(char) }
        return atom.characters?.contains(char) ?? true
    }

    @objc(transformNumber:accountID:fromHistory:plusSubstitution:error:)
    static func transform(number: String, accountID: String, fromHistory: Bool, plusSubstitution: String?) throws -> String {
        let accounts = UserDefaults.standard.array(forKey: UserDefaultsKeys.accounts) as? [[String: Any]] ?? []
        let plan = accounts.first { $0[AKSIPAccountKeys.uuid] as? String == accountID }?[settingsKey] as? String ?? ""
        return try DialPlan(plan).apply(to: number, fromHistory: fromHistory, plusSubstitution: plusSubstitution)
    }
}
