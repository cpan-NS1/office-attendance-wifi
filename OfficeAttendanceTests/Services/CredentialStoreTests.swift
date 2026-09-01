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
}
