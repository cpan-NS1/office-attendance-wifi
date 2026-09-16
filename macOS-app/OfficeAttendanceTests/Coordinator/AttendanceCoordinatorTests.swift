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

    // MARK: - officeSeenTodayKey

    func test_officeSeenTodayKey_hasOfficePrefixAndISODate() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        let key = coordinator.officeSeenTodayKey()
        XCTAssertTrue(key.hasPrefix("attendance-office-"), "key should start with 'attendance-office-', got: \(key)")
        let datePart = String(key.dropFirst("attendance-office-".count))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        XCTAssertNotNil(formatter.date(from: datePart), "date portion '\(datePart)' is not a valid yyyy-MM-dd date")
    }

    func test_officeSeenTodayKey_isStableWithinSameDay() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        XCTAssertEqual(coordinator.officeSeenTodayKey(), coordinator.officeSeenTodayKey())
    }

    // MARK: - officeWasSeenToday / markOfficeSeen

    func test_officeWasSeenToday_returnsFalse_whenNotSet() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        let key = coordinator.officeSeenTodayKey()
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(coordinator.officeWasSeenToday())
    }

    func test_markOfficeSeen_causesOfficeWasSeenTodayToReturnTrue() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        let key = coordinator.officeSeenTodayKey()
        UserDefaults.standard.removeObject(forKey: key)
        coordinator.markOfficeSeen()
        XCTAssertTrue(coordinator.officeWasSeenToday())
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - shouldUpdate logic

    func test_shouldUpdateToWFH_returnsFalse_whenOfficePreviouslySeen() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        let officeKey = coordinator.officeSeenTodayKey()
        let attendanceKey = coordinator.todayKey()
        // Simulate: office was seen earlier today (e.g. morning), now on home WiFi
        UserDefaults.standard.set(true, forKey: officeKey)
        UserDefaults.standard.set(AttendanceStatus.office.mondayValue, forKey: attendanceKey)

        XCTAssertFalse(coordinator.shouldUpdate(isOnOfficeNetwork: false),
                       "WFH update should be suppressed when office was seen today")

        UserDefaults.standard.removeObject(forKey: officeKey)
        UserDefaults.standard.removeObject(forKey: attendanceKey)
    }

    func test_shouldUpdateToWFH_returnsTrue_whenOfficeNotSeenAndNotCheckedIn() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        let officeKey = coordinator.officeSeenTodayKey()
        let attendanceKey = coordinator.todayKey()
        UserDefaults.standard.removeObject(forKey: officeKey)
        UserDefaults.standard.removeObject(forKey: attendanceKey)

        XCTAssertTrue(coordinator.shouldUpdate(isOnOfficeNetwork: false),
                      "WFH update should proceed when office not seen and not checked in")

        UserDefaults.standard.removeObject(forKey: officeKey)
        UserDefaults.standard.removeObject(forKey: attendanceKey)
    }

    func test_shouldUpdateToWFH_returnsFalse_whenAlreadyCheckedInAsWFH() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        let officeKey = coordinator.officeSeenTodayKey()
        let attendanceKey = coordinator.todayKey()
        UserDefaults.standard.removeObject(forKey: officeKey)
        UserDefaults.standard.set(AttendanceStatus.wfh.mondayValue, forKey: attendanceKey)

        XCTAssertFalse(coordinator.shouldUpdate(isOnOfficeNetwork: false),
                       "WFH update should be suppressed when already checked in as WFH")

        UserDefaults.standard.removeObject(forKey: officeKey)
        UserDefaults.standard.removeObject(forKey: attendanceKey)
    }

    func test_shouldUpdateToOffice_returnsTrue_evenWhenAlreadyCheckedInAsWFH() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        let officeKey = coordinator.officeSeenTodayKey()
        let attendanceKey = coordinator.todayKey()
        // Simulate: woke up at home → set WFH, then drove to office
        UserDefaults.standard.removeObject(forKey: officeKey)
        UserDefaults.standard.set(AttendanceStatus.wfh.mondayValue, forKey: attendanceKey)

        XCTAssertTrue(coordinator.shouldUpdate(isOnOfficeNetwork: true),
                      "Office update should override an existing WFH check-in")

        UserDefaults.standard.removeObject(forKey: officeKey)
        UserDefaults.standard.removeObject(forKey: attendanceKey)
    }

    func test_shouldUpdateToOffice_returnsFalse_whenAlreadyCheckedInAsOffice() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        let officeKey = coordinator.officeSeenTodayKey()
        let attendanceKey = coordinator.todayKey()
        UserDefaults.standard.set(true, forKey: officeKey)
        UserDefaults.standard.set(AttendanceStatus.office.mondayValue, forKey: attendanceKey)

        XCTAssertFalse(coordinator.shouldUpdate(isOnOfficeNetwork: true),
                       "Office update should be a no-op when already checked in as office")

        UserDefaults.standard.removeObject(forKey: officeKey)
        UserDefaults.standard.removeObject(forKey: attendanceKey)
    }

    // MARK: - Manual check-in office stickiness invariant

    func test_shouldUpdateToWFH_returnsFalse_afterManualOfficeCheckIn() {
        // Simulates: user manually selects Office from the menu, then later wakes
        // up at home — the sticky flag must have been set by the manual check-in
        // so WFH is suppressed.
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        let officeKey = coordinator.officeSeenTodayKey()
        let attendanceKey = coordinator.todayKey()
        UserDefaults.standard.removeObject(forKey: officeKey)
        UserDefaults.standard.removeObject(forKey: attendanceKey)

        // Replicate what manualCheckIn does on success for .office
        coordinator.markOfficeSeen()
        UserDefaults.standard.set(AttendanceStatus.office.mondayValue, forKey: attendanceKey)

        XCTAssertFalse(coordinator.shouldUpdate(isOnOfficeNetwork: false),
                       "WFH should be suppressed after a manual office check-in")

        UserDefaults.standard.removeObject(forKey: officeKey)
        UserDefaults.standard.removeObject(forKey: attendanceKey)
    }
}
