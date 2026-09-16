import Foundation

final class CredentialStore: ObservableObject {

    // MARK: - Init

    /// Production init uses ~/.officeattendance.
    convenience init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.init(appDir: home.appendingPathComponent(".officeattendance", isDirectory: true))
    }

    /// Designated init — allows tests to inject a temporary directory.
    init(appDir: URL) {
        self.appDir = appDir
        self.configURL  = appDir.appendingPathComponent("config.json")
        self.historyURL = appDir.appendingPathComponent("history.json")
    }


    // MARK: - Types

    struct Credentials {
        let token: String
        let boardId: String
        let employeeId: String
        let ipPrefix: String
        let dnsDomain: String
    }

    struct HistoryEntry: Identifiable {
        let date: String          // "yyyy-MM-dd"
        let status: AttendanceStatus
        var id: String { date }
    }

    // MARK: - Codable backing structs

    private struct StoredConfig: Codable {
        var token: String
        var boardId: String
        var employeeId: String
        var ipPrefix: String
        var dnsDomain: String
        var columnMap: ColumnMap?
    }

    private struct StoredHistoryEntry: Codable {
        let date: String
        let status: String        // mondayValue
    }

    // MARK: - Paths

    private let appDir: URL
    private let configURL: URL
    private let historyURL: URL

    // MARK: - Public API

    func save(token: String, boardId: String, employeeId: String,
              ipPrefix: String, dnsDomain: String) throws {
        // Load existing config so we preserve any saved columnMap.
        var config = (try? loadStoredConfig()) ?? StoredConfig(token: "", boardId: "",
                                                               employeeId: "", ipPrefix: "",
                                                               dnsDomain: "", columnMap: nil)
        config.token      = token
        config.boardId    = boardId
        config.employeeId = employeeId
        config.ipPrefix   = ipPrefix
        config.dnsDomain  = dnsDomain
        try writeConfig(config)
    }

    func load() -> Credentials? {
        guard let config = try? loadStoredConfig(),
              !config.token.isEmpty
        else { return nil }
        return Credentials(token: config.token,
                           boardId: config.boardId,
                           employeeId: config.employeeId,
                           ipPrefix: config.ipPrefix,
                           dnsDomain: config.dnsDomain)
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: configURL)
        try? FileManager.default.removeItem(at: historyURL)
    }

    // MARK: - Column map

    func saveColumnMap(_ map: ColumnMap) {
        var config = (try? loadStoredConfig()) ?? StoredConfig(token: "", boardId: "",
                                                               employeeId: "", ipPrefix: "",
                                                               dnsDomain: "", columnMap: nil)
        config.columnMap = map
        try? writeConfig(config)
    }

    func loadColumnMap() -> ColumnMap? {
        (try? loadStoredConfig())?.columnMap
    }

    // MARK: - Attendance history

    /// Saves (or overwrites) a single day's attendance entry.
    func saveAttendance(date: String, status: AttendanceStatus) {
        var entries = loadStoredHistory()
        entries.removeAll { $0.date == date }
        entries.append(StoredHistoryEntry(date: date, status: status.mondayValue))
        try? writeHistory(entries)
    }

    /// Returns all persisted attendance entries, newest-first.
    func loadHistory() -> [HistoryEntry] {
        loadStoredHistory()
            .compactMap { entry -> HistoryEntry? in
                guard let status = AttendanceStatus.allCases
                    .first(where: { $0.mondayValue == entry.status })
                else { return nil }
                return HistoryEntry(date: entry.date, status: status)
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Migration from UserDefaults

    /// Call once on launch. Moves any existing UserDefaults-based config and
    /// history into the new file-based storage, then clears the old keys.
    func migrateFromUserDefaultsIfNeeded() {
        let ud = UserDefaults.standard
        let servicePrefix = "com.chenmo.office-attendance."
        let legacyConfigKeys = ["board-id", "employee-id", "office-ip-prefix", "office-dns-domain"]

        // Check if any legacy config key exists.
        let legacyTokenKey = servicePrefix + "monday-token"
        let hasLegacyConfig = legacyConfigKeys
            .contains { ud.string(forKey: servicePrefix + $0) != nil }
            || ud.string(forKey: legacyTokenKey) != nil
        guard hasLegacyConfig else { return }

        let token      = ud.string(forKey: legacyTokenKey) ?? ""
        let boardId    = ud.string(forKey: servicePrefix + "board-id") ?? ""
        let employeeId = ud.string(forKey: servicePrefix + "employee-id") ?? ""
        let ipPrefix   = ud.string(forKey: servicePrefix + "office-ip-prefix") ?? ""
        let dnsDomain  = ud.string(forKey: servicePrefix + "office-dns-domain") ?? ""

        // Migrate column map.
        var columnMap: ColumnMap? = nil
        if let data = ud.data(forKey: "columnMap") {
            columnMap = try? JSONDecoder().decode(ColumnMap.self, from: data)
        }

        let config = StoredConfig(token: token, boardId: boardId, employeeId: employeeId,
                                  ipPrefix: ipPrefix, dnsDomain: dnsDomain,
                                  columnMap: columnMap)
        try? writeConfig(config)

        // Migrate attendance history.
        let allKeys = ud.dictionaryRepresentation().keys
        var historyEntries: [StoredHistoryEntry] = []
        for key in allKeys where key.hasPrefix("attendance-") && !key.hasPrefix("attendance-office-") {
            let date = String(key.dropFirst("attendance-".count))
            if let raw = ud.string(forKey: key) {
                historyEntries.append(StoredHistoryEntry(date: date, status: raw))
            }
        }
        if !historyEntries.isEmpty {
            try? writeHistory(historyEntries)
        }

        // Clear legacy keys.
        ud.removeObject(forKey: legacyTokenKey)
        for key in legacyConfigKeys { ud.removeObject(forKey: servicePrefix + key) }
        ud.removeObject(forKey: "columnMap")
        for key in allKeys where key.hasPrefix("attendance-") {
            ud.removeObject(forKey: key)
        }
    }

    // MARK: - Private helpers

    private func ensureAppDir() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: appDir.path) {
            try fm.createDirectory(at: appDir,
                                   withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        }
    }

    private func loadStoredConfig() throws -> StoredConfig {
        let data = try Data(contentsOf: configURL)
        return try JSONDecoder().decode(StoredConfig.self, from: data)
    }

    private func writeConfig(_ config: StoredConfig) throws {
        try ensureAppDir()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: configURL.path)
    }

    private func loadStoredHistory() -> [StoredHistoryEntry] {
        guard let data = try? Data(contentsOf: historyURL),
              let entries = try? JSONDecoder().decode([StoredHistoryEntry].self, from: data)
        else { return [] }
        return entries
    }

    private func writeHistory(_ entries: [StoredHistoryEntry]) throws {
        try ensureAppDir()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: historyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: historyURL.path)
    }
}
