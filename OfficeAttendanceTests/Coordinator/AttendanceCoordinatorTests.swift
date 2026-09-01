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
}
