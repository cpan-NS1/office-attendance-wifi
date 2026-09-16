import XCTest
@testable import OfficeAttendance

final class AttendanceStatusTests: XCTestCase {
    func test_mondayValue_matchesExpectedStrings() {
        XCTAssertEqual(AttendanceStatus.office.mondayValue, "Office")
        XCTAssertEqual(AttendanceStatus.wfh.mondayValue, "WFH")
        XCTAssertEqual(AttendanceStatus.wfhSickness.mondayValue, "WFH: Sickness")
        XCTAssertEqual(AttendanceStatus.wfhUnplannedIssues.mondayValue, "WFH: Unplanned Issues")
        XCTAssertEqual(AttendanceStatus.wfhWeatherWarning.mondayValue, "WFH: Weather Warning")
        XCTAssertEqual(AttendanceStatus.sick.mondayValue, "Sick")
        XCTAssertEqual(AttendanceStatus.vacation.mondayValue, "Vacation")
        XCTAssertEqual(AttendanceStatus.loa.mondayValue, "LOA")
        XCTAssertEqual(AttendanceStatus.bankHoliday.mondayValue, "Bank Holiday")
        XCTAssertEqual(AttendanceStatus.travel.mondayValue, "Travel")
    }

    func test_allCases_haveNonEmptyIcon() {
        for status in AttendanceStatus.allCases {
            XCTAssertFalse(status.icon.isEmpty, "\(status) has empty icon")
        }
    }
}
