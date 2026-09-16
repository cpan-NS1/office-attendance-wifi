import XCTest
@testable import OfficeAttendance

final class ColumnMapTests: XCTestCase {
    private let map = ColumnMap(
        employeeColumnId: "emp",
        weekStartColumnId: "ws",
        mondayColumnId: "mon",
        tuesdayColumnId: "tue",
        wednesdayColumnId: "wed",
        thursdayColumnId: "thu",
        fridayColumnId: "fri"
    )

    func test_columnId_returnsMonday_forWeekday2() {
        XCTAssertEqual(map.columnId(forWeekday: 2), "mon")
    }

    func test_columnId_returnsTuesday_forWeekday3() {
        XCTAssertEqual(map.columnId(forWeekday: 3), "tue")
    }

    func test_columnId_returnsWednesday_forWeekday4() {
        XCTAssertEqual(map.columnId(forWeekday: 4), "wed")
    }

    func test_columnId_returnsThursday_forWeekday5() {
        XCTAssertEqual(map.columnId(forWeekday: 5), "thu")
    }

    func test_columnId_returnsFriday_forWeekday6() {
        XCTAssertEqual(map.columnId(forWeekday: 6), "fri")
    }

    func test_columnId_returnsNil_forSunday() {
        XCTAssertNil(map.columnId(forWeekday: 1))
    }

    func test_columnId_returnsNil_forSaturday() {
        XCTAssertNil(map.columnId(forWeekday: 7))
    }
}
