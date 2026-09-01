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
}
