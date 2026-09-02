import Foundation

final class CredentialStore: ObservableObject {
    private let serviceName = "com.chenmo.office-attendance"
    private let columnMapKey = "columnMap"

    struct HistoryEntry: Identifiable {
        let date: String          // "yyyy-MM-dd"
        let status: AttendanceStatus
        var id: String { date }
    }

    private let credentialKeys = ["monday-token", "board-id", "employee-id",
                                  "office-ip-prefix", "office-dns-domain"]

    struct Credentials {
        let token: String
        let boardId: String
        let employeeId: String
        let ipPrefix: String
        let dnsDomain: String
    }

    // MARK: - Public API

    func save(token: String, boardId: String, employeeId: String,
              ipPrefix: String, dnsDomain: String) throws {
        let values = [token, boardId, employeeId, ipPrefix, dnsDomain]
        for (key, value) in zip(credentialKeys, values) {
            UserDefaults.standard.set(value, forKey: udKey(key))
        }
    }

    func load() -> Credentials? {
        guard
            let token   = UserDefaults.standard.string(forKey: udKey("monday-token")),
            let boardId = UserDefaults.standard.string(forKey: udKey("board-id")),
            let empId   = UserDefaults.standard.string(forKey: udKey("employee-id")),
            let ip      = UserDefaults.standard.string(forKey: udKey("office-ip-prefix")),
            let dns     = UserDefaults.standard.string(forKey: udKey("office-dns-domain"))
        else { return nil }
        return Credentials(token: token, boardId: boardId, employeeId: empId,
                           ipPrefix: ip, dnsDomain: dns)
    }

    func clearAll() {
        credentialKeys.forEach { UserDefaults.standard.removeObject(forKey: udKey($0)) }
        UserDefaults.standard.removeObject(forKey: columnMapKey)
    }

    // MARK: - Column map

    func saveColumnMap(_ map: ColumnMap) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: columnMapKey)
        }
    }

    func loadColumnMap() -> ColumnMap? {
        guard let data = UserDefaults.standard.data(forKey: columnMapKey) else { return nil }
        return try? JSONDecoder().decode(ColumnMap.self, from: data)
    }

    /// Returns all persisted attendance entries, newest-first.
    func loadHistory() -> [HistoryEntry] {
        UserDefaults.standard.dictionaryRepresentation()
            .compactMap { key, value -> HistoryEntry? in
                guard key.hasPrefix("attendance-"),
                      let raw = value as? String,
                      let status = AttendanceStatus.allCases.first(where: { $0.mondayValue == raw })
                else { return nil }
                let date = String(key.dropFirst("attendance-".count))
                return HistoryEntry(date: date, status: status)
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Private

    private func udKey(_ key: String) -> String { "\(serviceName).\(key)" }
}
