import XCTest
@testable import OfficeAttendance

@MainActor
final class AttendanceCoordinatorTests: XCTestCase {
    func test_isWeekend_returnsTrue_forSaturday() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        var components = DateComponents()
        components.year = 2025; components.month = 7; components.day = 19 // Saturday
        let saturday = Calendar.current.date(from: components)!
        XCTAssertTrue(coordinator.isWeekend(date: saturday))
    }

    func test_isWeekend_returnsFalse_forMonday() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        var components = DateComponents()
        components.year = 2025; components.month = 7; components.day = 14 // Monday
        let monday = Calendar.current.date(from: components)!
        XCTAssertFalse(coordinator.isWeekend(date: monday))
    }

    func test_alreadyCheckedIn_usesUserDefaults() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        let key = "attendance-2025-07-14"
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(coordinator.alreadyCheckedIn(for: key))
        UserDefaults.standard.set("Office", forKey: key)
        XCTAssertTrue(coordinator.alreadyCheckedIn(for: key))
        UserDefaults.standard.removeObject(forKey: key)
    }

    func test_todayKey_hasAttendancePrefixAndISODate() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        let key = coordinator.todayKey()
        // Must start with "attendance-"
        XCTAssertTrue(key.hasPrefix("attendance-"), "key should start with 'attendance-', got: \(key)")
        // The date portion must be parseable as yyyy-MM-dd
        let datePart = String(key.dropFirst("attendance-".count))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        XCTAssertNotNil(formatter.date(from: datePart), "date portion '\(datePart)' is not a valid yyyy-MM-dd date")
    }

    func test_todayKey_isStableWithinSameDay() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        XCTAssertEqual(coordinator.todayKey(), coordinator.todayKey())
    }
}
