import Foundation

final class CredentialStore: ObservableObject {
    private let serviceName = "com.chenmo.office-attendance"
    private let columnMapKey = "columnMap"

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

    // MARK: - Private

    private func udKey(_ key: String) -> String { "\(serviceName).\(key)" }
}
