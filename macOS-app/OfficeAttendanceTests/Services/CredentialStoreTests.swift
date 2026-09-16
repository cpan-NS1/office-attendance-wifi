import XCTest
@testable import OfficeAttendance

final class CredentialStoreTests: XCTestCase {
    var store: CredentialStore!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = CredentialStore(appDir: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - load / save credentials

    func test_load_returnsNil_whenNothingSaved() {
        XCTAssertNil(store.load())
    }

    func test_saveAndLoad_roundTrips() throws {
        try store.save(token: "tok", boardId: "123", employeeId: "emp",
                       ipPrefix: "9.", dnsDomain: "ibm.com")
        let creds = store.load()
        XCTAssertEqual(creds?.token, "tok")
        XCTAssertEqual(creds?.boardId, "123")
        XCTAssertEqual(creds?.employeeId, "emp")
        XCTAssertEqual(creds?.ipPrefix, "9.")
        XCTAssertEqual(creds?.dnsDomain, "ibm.com")
    }

    func test_load_returnsNil_whenTokenIsEmpty() throws {
        try store.save(token: "", boardId: "123", employeeId: "emp",
                       ipPrefix: "9.", dnsDomain: "ibm.com")
        XCTAssertNil(store.load())
    }

    func test_save_preservesExistingColumnMap() throws {
        let map = ColumnMap(employeeColumnId: "e", weekStartColumnId: "ws",
                            mondayColumnId: "m", tuesdayColumnId: "t",
                            wednesdayColumnId: "w", thursdayColumnId: "th",
                            fridayColumnId: "f")
        store.saveColumnMap(map)
        // Save credentials without touching the column map
        try store.save(token: "tok2", boardId: "999", employeeId: "emp2",
                       ipPrefix: "10.", dnsDomain: "example.com")
        XCTAssertEqual(store.loadColumnMap()?.mondayColumnId, "m")
    }

    func test_clearAll_removesCredentialsAndHistory() throws {
        try store.save(token: "tok", boardId: "123", employeeId: "emp",
                       ipPrefix: "9.", dnsDomain: "ibm.com")
        store.saveAttendance(date: "2025-01-01", status: .office)
        store.clearAll()
        XCTAssertNil(store.load())
        XCTAssertTrue(store.loadHistory().isEmpty)
    }

    // MARK: - Column map

    func test_columnMap_roundTrips() {
        let map = ColumnMap(employeeColumnId: "e", weekStartColumnId: "ws",
                            mondayColumnId: "m", tuesdayColumnId: "t",
                            wednesdayColumnId: "w", thursdayColumnId: "th",
                            fridayColumnId: "f")
        store.saveColumnMap(map)
        let loaded = store.loadColumnMap()
        XCTAssertEqual(loaded?.mondayColumnId, "m")
        XCTAssertEqual(loaded?.fridayColumnId, "f")
    }

    func test_loadColumnMap_returnsNil_whenNothingSaved() {
        XCTAssertNil(store.loadColumnMap())
    }

    // MARK: - Attendance history

    func test_loadHistory_returnsEmpty_whenNoEntriesSaved() {
        XCTAssertTrue(store.loadHistory().isEmpty)
    }

    func test_saveAttendance_andLoadHistory_roundTrips() {
        store.saveAttendance(date: "2025-06-02", status: .office)
        let entry = store.loadHistory().first { $0.date == "2025-06-02" }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.status, .office)
    }

    func test_saveAttendance_overwrites_existingEntryForSameDate() {
        store.saveAttendance(date: "2025-06-02", status: .wfh)
        store.saveAttendance(date: "2025-06-02", status: .office)
        let entries = store.loadHistory().filter { $0.date == "2025-06-02" }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.status, .office)
    }

    func test_loadHistory_isSortedNewestFirst() {
        store.saveAttendance(date: "2025-05-01", status: .wfh)
        store.saveAttendance(date: "2025-05-05", status: .wfh)
        store.saveAttendance(date: "2025-05-03", status: .wfh)
        let dates = store.loadHistory().map { $0.date }
        XCTAssertEqual(dates, ["2025-05-05", "2025-05-03", "2025-05-01"])
    }

    // MARK: - Migration

    func test_migration_movesUserDefaultsConfigToFile() throws {
        let ud = UserDefaults.standard
        let prefix = "com.chenmo.office-attendance."
        ud.set("migrated-token", forKey: prefix + "monday-token")
        ud.set("board99",        forKey: prefix + "board-id")
        ud.set("emp42",          forKey: prefix + "employee-id")
        ud.set("10.",            forKey: prefix + "office-ip-prefix")
        ud.set("example.com",   forKey: prefix + "office-dns-domain")
        defer {
            ud.removeObject(forKey: prefix + "monday-token")
            ud.removeObject(forKey: prefix + "board-id")
            ud.removeObject(forKey: prefix + "employee-id")
            ud.removeObject(forKey: prefix + "office-ip-prefix")
            ud.removeObject(forKey: prefix + "office-dns-domain")
        }

        store.migrateFromUserDefaultsIfNeeded()

        let creds = store.load()
        XCTAssertEqual(creds?.token,      "migrated-token")
        XCTAssertEqual(creds?.boardId,    "board99")
        XCTAssertEqual(creds?.employeeId, "emp42")
        XCTAssertEqual(creds?.ipPrefix,   "10.")
        XCTAssertEqual(creds?.dnsDomain,  "example.com")
    }

    func test_migration_movesUserDefaultsHistoryToFile() {
        let ud = UserDefaults.standard
        let prefix = "com.chenmo.office-attendance."
        // Plant a legacy config key so migration triggers
        ud.set("tok", forKey: prefix + "monday-token")
        ud.set("attendance-2025-03-10", forKey: prefix + "board-id")  // dummy to trigger
        ud.set("Office", forKey: "attendance-2025-03-10")
        defer {
            ud.removeObject(forKey: prefix + "monday-token")
            ud.removeObject(forKey: prefix + "board-id")
            ud.removeObject(forKey: "attendance-2025-03-10")
        }

        store.migrateFromUserDefaultsIfNeeded()

        let entry = store.loadHistory().first { $0.date == "2025-03-10" }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.status, .office)
    }

    func test_migration_clearsLegacyUserDefaultsKeys() throws {
        let ud = UserDefaults.standard
        let prefix = "com.chenmo.office-attendance."
        ud.set("tok",       forKey: prefix + "monday-token")
        ud.set("board1",    forKey: prefix + "board-id")
        ud.set("emp1",      forKey: prefix + "employee-id")
        ud.set("9.",        forKey: prefix + "office-ip-prefix")
        ud.set("ibm.com",   forKey: prefix + "office-dns-domain")

        store.migrateFromUserDefaultsIfNeeded()

        XCTAssertNil(ud.string(forKey: prefix + "monday-token"))
        XCTAssertNil(ud.string(forKey: prefix + "board-id"))
        XCTAssertNil(ud.string(forKey: prefix + "employee-id"))
        XCTAssertNil(ud.string(forKey: prefix + "office-ip-prefix"))
        XCTAssertNil(ud.string(forKey: prefix + "office-dns-domain"))
    }

    func test_migration_isIdempotent() throws {
        let ud = UserDefaults.standard
        let prefix = "com.chenmo.office-attendance."
        ud.set("tok",     forKey: prefix + "monday-token")
        ud.set("board1",  forKey: prefix + "board-id")
        ud.set("emp1",    forKey: prefix + "employee-id")
        ud.set("9.",      forKey: prefix + "office-ip-prefix")
        ud.set("ibm.com", forKey: prefix + "office-dns-domain")

        store.migrateFromUserDefaultsIfNeeded()
        store.migrateFromUserDefaultsIfNeeded() // second call must be a no-op

        XCTAssertEqual(store.load()?.token, "tok")
    }
}
