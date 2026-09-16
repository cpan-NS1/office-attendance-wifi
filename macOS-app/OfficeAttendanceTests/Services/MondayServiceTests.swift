import XCTest
@testable import OfficeAttendance

final class MondayServiceTests: XCTestCase {
    func test_weekStartDate_isAlwaysMonday() {
        let service = MondayService()
        let calendar = Calendar(identifier: .gregorian)
        // Use a known Wednesday: 2025-07-16
        var components = DateComponents()
        components.year = 2025; components.month = 7; components.day = 16
        let wednesday = calendar.date(from: components)!
        let weekStart = service.weekStartDate(for: wednesday)
        let weekday = calendar.component(.weekday, from: weekStart)
        XCTAssertEqual(weekday, 2, "Week start should be Monday (weekday=2)")
    }

    func test_weekStartDate_formatsAsISO() {
        let service = MondayService()
        var components = DateComponents()
        components.year = 2025; components.month = 7; components.day = 16
        let calendar = Calendar(identifier: .gregorian)
        let wednesday = calendar.date(from: components)!
        let result = service.weekStartDateString(for: wednesday)
        XCTAssertEqual(result, "2025-07-14")
    }

    // A Friday in the last week of a month whose last day is mid-week; the
    // returned Monday must still be <= the last day, so it's included.
    func test_weekStartDate_returnsCorrectMonday_forFridayInLastWeekOfMonth() {
        let service = MondayService()
        var components = DateComponents()
        components.year = 2025; components.month = 1; components.day = 31 // Friday
        let calendar = Calendar(identifier: .gregorian)
        let friday = calendar.date(from: components)!
        let weekStart = service.weekStartDate(for: friday)
        let startComps = calendar.dateComponents([.year, .month, .day], from: weekStart)
        XCTAssertEqual(startComps.year, 2025)
        XCTAssertEqual(startComps.month, 1)
        XCTAssertEqual(startComps.day, 27) // Monday 27 Jan 2025
    }

    func test_weekStartDateString_formatsMonday_forFriday() {
        let service = MondayService()
        var components = DateComponents()
        components.year = 2025; components.month = 1; components.day = 31
        let calendar = Calendar(identifier: .gregorian)
        let friday = calendar.date(from: components)!
        XCTAssertEqual(service.weekStartDateString(for: friday), "2025-01-27")
    }
}

final class MondayErrorTests: XCTestCase {
    func test_noRowFound_hasNonEmptyDescription() {
        XCTAssertFalse((MondayError.noRowFound.errorDescription ?? "").isEmpty)
    }

    func test_columnNotFound_includesColumnName() {
        let desc = MondayError.columnNotFound("Monday").errorDescription ?? ""
        XCTAssertTrue(desc.contains("Monday"), "Expected column name in: \(desc)")
    }

    func test_apiError_includesMessage() {
        let desc = MondayError.apiError("token expired").errorDescription ?? ""
        XCTAssertTrue(desc.contains("token expired"), "Expected message in: \(desc)")
    }
}
