import Foundation
import Security

final class CredentialStore: ObservableObject {
    private let serviceName = "com.ibm.office-attendance"
    private let columnMapKey = "columnMap"

    struct Credentials {
        let token: String
        let boardId: String
        let employeeId: String
        let ipPrefix: String
        let dnsDomain: String
    }

    // MARK: - Keychain

    func save(token: String, boardId: String, employeeId: String,
              ipPrefix: String, dnsDomain: String) throws {
        try setKeychainItem(key: "monday-token", value: token)
        try setKeychainItem(key: "board-id", value: boardId)
        try setKeychainItem(key: "employee-id", value: employeeId)
        try setKeychainItem(key: "office-ip-prefix", value: ipPrefix)
        try setKeychainItem(key: "office-dns-domain", value: dnsDomain)
    }

    func load() -> Credentials? {
        guard
            let token  = getKeychainItem(key: "monday-token"),
            let boardId = getKeychainItem(key: "board-id"),
            let empId  = getKeychainItem(key: "employee-id"),
            let ip     = getKeychainItem(key: "office-ip-prefix"),
            let dns    = getKeychainItem(key: "office-dns-domain")
        else { return nil }
        return Credentials(token: token, boardId: boardId, employeeId: empId,
                           ipPrefix: ip, dnsDomain: dns)
    }

    func clearAll() {
        for key in ["monday-token", "board-id", "employee-id",
                    "office-ip-prefix", "office-dns-domain"] {
            deleteKeychainItem(key: key)
        }
        UserDefaults.standard.removeObject(forKey: columnMapKey)
    }

    // MARK: - UserDefaults (column map)

    func saveColumnMap(_ map: ColumnMap) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: columnMapKey)
        }
    }

    func loadColumnMap() -> ColumnMap? {
        guard let data = UserDefaults.standard.data(forKey: columnMapKey) else { return nil }
        return try? JSONDecoder().decode(ColumnMap.self, from: data)
    }

    // MARK: - Private Keychain helpers

    private func setKeychainItem(key: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
        let attributes = query.merging([kSecValueData: data]) { $1 }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func getKeychainItem(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychainItem(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
