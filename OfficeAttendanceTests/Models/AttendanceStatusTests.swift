import XCTest
@testable import OfficeAttendance

final class AttendanceStatusTests: XCTestCase {
    func test_mondayValue_matchesExpectedStrings() {
        XCTAssertEqual(AttendanceStatus.office.mondayValue, "Office")
        XCTAssertEqual(AttendanceStatus.wfh.mondayValue, "WFH")
        XCTAssertEqual(AttendanceStatus.sick.mondayValue, "Sick")
        XCTAssertEqual(AttendanceStatus.vacation.mondayValue, "Vacation")
        XCTAssertEqual(AttendanceStatus.holiday.mondayValue, "Holiday")
    }

    func test_allCases_haveNonEmptyIcon() {
        for status in AttendanceStatus.allCases {
            XCTAssertFalse(status.icon.isEmpty, "\(status) has empty icon")
        }
    }
}
