import Foundation

struct DirectoryResponse: Decodable {
    struct Item: Decodable {
        let name: String
        let number: String
    }
    let refresh: Int?
    let items: [Item]

    @MainActor func contacts() throws -> [LocalContact] {
        var numbers = Set<String>()
        return try items.map {
            let name = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let number = $0.number.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 200,
                  let canonical = LocalContacts.canonical(number), numbers.insert(canonical).inserted else {
                throw LocalContacts.Failure.invalid
            }
            return LocalContact(id: number, name: name, number: number)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

@MainActor
final class UserDirectory: NSObject {
    @objc static let shared = UserDirectory()
    static let changed = Notification.Name("SwiftDialDirectoryChanged")
    private let defaults: UserDefaults
    private let session: URLSession
    private var task: Task<Void, Never>?
    private(set) var all: [LocalContact] = []
    private(set) var status = NSLocalizedString("Directory is disabled.", comment: "Directory status")
    var urlString: String { defaults.string(forKey: "SwiftDialDirectoryURL") ?? "" }

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        super.init()
        if !urlString.isEmpty, let data = defaults.data(forKey: "SwiftDialDirectoryCache"),
           let response = try? JSONDecoder().decode(DirectoryResponse.self, from: data),
           let contacts = try? response.contacts() {
            all = contacts
            status = NSLocalizedString("Showing saved directory.", comment: "Directory status")
        }
    }

    func configure(_ value: String) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            guard let url = URL(string: value), url.scheme?.lowercased() == "https",
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.fragment == nil else {
                throw NSError(domain: "UserDirectory", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    NSLocalizedString("Enter a valid HTTPS directory URL, or leave it empty to disable.", comment: "Directory validation")])
            }
        }
        if value != urlString {
            defaults.set(value, forKey: "SwiftDialDirectoryURL")
            defaults.removeObject(forKey: "SwiftDialDirectoryCache")
            all = []
        }
        start()
    }

    @objc func start() {
        task?.cancel()
        task = nil
        guard !urlString.isEmpty else {
            status = NSLocalizedString("Directory is disabled.", comment: "Directory status")
            notify()
            return
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.refresh(), delay > 0, !Task.isCancelled else { return }
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    // A failed request never replaces the last successfully validated snapshot.
    func refresh() async -> Int {
        let source = urlString
        guard let url = URL(string: source), !source.isEmpty else { return 0 }
        status = NSLocalizedString("Updating directory…", comment: "Directory status")
        notify()
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled, source == urlString else { return 0 }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  http.url?.scheme == "https", data.count <= 5_000_000 else { throw URLError(.badServerResponse) }
            let directory = try JSONDecoder().decode(DirectoryResponse.self, from: data)
            let contacts = try directory.contacts()
            all = contacts
            defaults.set(data, forKey: "SwiftDialDirectoryCache")
            status = String(format: NSLocalizedString("Directory updated: %ld contacts.", comment: "Directory status"), all.count)
            notify()
            // Clamp positive intervals to avoid an accidental tight polling loop.
            return (directory.refresh ?? 0) > 0 ? min(max(directory.refresh!, 30), 86400) : 0
        } catch {
            guard !Task.isCancelled, source == urlString else { return 0 }
            status = NSLocalizedString("Could not update directory. Saved contacts are retained. Retrying in 5 minutes.", comment: "Directory status")
            notify()
            return 300
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.changed, object: self)
        NotificationCenter.default.post(name: LocalContacts.changed, object: self)
    }
}
