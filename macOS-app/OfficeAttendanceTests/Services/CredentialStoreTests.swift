import XCTest
@testable import OfficeAttendance

final class CredentialStoreTests: XCTestCase {
    var store: CredentialStore!

    override func setUp() {
        super.setUp()
        store = CredentialStore()
        store.clearAll()
    }

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

    func test_loadHistory_returnsEmpty_whenNoAttendanceKeys() {
        // Clear any stray attendance keys from prior test runs
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("attendance-") }
        keys.forEach { defaults.removeObject(forKey: $0) }

        XCTAssertTrue(store.loadHistory().isEmpty)
    }

    func test_loadHistory_returnsEntry_withCorrectStatusAndDate() {
        let key = "attendance-2025-06-02"
        UserDefaults.standard.set("Office", forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let history = store.loadHistory()
        let entry = history.first { $0.date == "2025-06-02" }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.status, .office)
    }

    func test_loadHistory_ignoresUnknownStatusValues() {
        let key = "attendance-2025-06-03"
        UserDefaults.standard.set("NotAStatus", forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let history = store.loadHistory()
        XCTAssertNil(history.first { $0.date == "2025-06-03" })
    }

    func test_loadHistory_isSortedNewestFirst() {
        let keys = ["attendance-2025-05-01", "attendance-2025-05-05", "attendance-2025-05-03"]
        keys.forEach { UserDefaults.standard.set("WFH", forKey: $0) }
        defer { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

        let dates = store.loadHistory()
            .filter { ["2025-05-01", "2025-05-05", "2025-05-03"].contains($0.date) }
            .map { $0.date }
        XCTAssertEqual(dates, ["2025-05-05", "2025-05-03", "2025-05-01"])
    }
}
