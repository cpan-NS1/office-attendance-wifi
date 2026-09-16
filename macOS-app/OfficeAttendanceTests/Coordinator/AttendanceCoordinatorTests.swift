import XCTest
@testable import OfficeAttendance

@MainActor
final class AttendanceCoordinatorTests: XCTestCase {
    var store: CredentialStore!
    var coordinator: AttendanceCoordinator!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = CredentialStore(appDir: tempDir)
        coordinator = AttendanceCoordinator(
            credentialStore: store,
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        // Clear the transient office-seen flag before each test
        UserDefaults.standard.removeObject(forKey: coordinator.officeSeenTodayKey())
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: coordinator.officeSeenTodayKey())
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - isWeekend

    func test_isWeekend_returnsTrue_forSaturday() {
        var components = DateComponents()
        components.year = 2025; components.month = 7; components.day = 19 // Saturday
        let saturday = Calendar.current.date(from: components)!
        XCTAssertTrue(coordinator.isWeekend(date: saturday))
    }

    func test_isWeekend_returnsFalse_forMonday() {
        var components = DateComponents()
        components.year = 2025; components.month = 7; components.day = 14 // Monday
        let monday = Calendar.current.date(from: components)!
        XCTAssertFalse(coordinator.isWeekend(date: monday))
    }

    // MARK: - todayDateString / todayKey

    func test_todayDateString_isValidISODate() {
        let dateStr = coordinator.todayDateString()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        XCTAssertNotNil(formatter.date(from: dateStr),
                        "'\(dateStr)' is not a valid yyyy-MM-dd date")
    }

    func test_todayDateString_isStableWithinSameDay() {
        XCTAssertEqual(coordinator.todayDateString(), coordinator.todayDateString())
    }

    func test_todayKey_hasAttendancePrefix() {
        XCTAssertTrue(coordinator.todayKey().hasPrefix("attendance-"))
    }

    // MARK: - officeSeenTodayKey

    func test_officeSeenTodayKey_hasOfficePrefixAndISODate() {
        let key = coordinator.officeSeenTodayKey()
        XCTAssertTrue(key.hasPrefix("attendance-office-"),
                      "key should start with 'attendance-office-', got: \(key)")
        let datePart = String(key.dropFirst("attendance-office-".count))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        XCTAssertNotNil(formatter.date(from: datePart),
                        "date portion '\(datePart)' is not a valid yyyy-MM-dd date")
    }

    // MARK: - alreadyCheckedIn

    func test_alreadyCheckedIn_returnsFalse_whenNoEntryInStore() {
        XCTAssertFalse(coordinator.alreadyCheckedIn(for: "2025-07-14"))
    }

    func test_alreadyCheckedIn_returnsTrue_afterSavingAttendance() {
        store.saveAttendance(date: "2025-07-14", status: .office)
        XCTAssertTrue(coordinator.alreadyCheckedIn(for: "2025-07-14"))
    }

    // MARK: - officeWasSeenToday / markOfficeSeen

    func test_officeWasSeenToday_returnsFalse_whenNotSet() {
        XCTAssertFalse(coordinator.officeWasSeenToday())
    }

    func test_markOfficeSeen_causesOfficeWasSeenTodayToReturnTrue() {
        coordinator.markOfficeSeen()
        XCTAssertTrue(coordinator.officeWasSeenToday())
    }

    // MARK: - shouldUpdate

    func test_shouldUpdateToWFH_returnsFalse_whenOfficePreviouslySeen() {
        coordinator.markOfficeSeen()
        store.saveAttendance(date: coordinator.todayDateString(), status: .office)
        XCTAssertFalse(coordinator.shouldUpdate(isOnOfficeNetwork: false),
                       "WFH update should be suppressed when office was seen today")
    }

    func test_shouldUpdateToWFH_returnsTrue_whenOfficeNotSeenAndNotCheckedIn() {
        XCTAssertTrue(coordinator.shouldUpdate(isOnOfficeNetwork: false),
                      "WFH update should proceed when office not seen and not checked in")
    }

    func test_shouldUpdateToWFH_returnsFalse_whenAlreadyCheckedInAsWFH() {
        store.saveAttendance(date: coordinator.todayDateString(), status: .wfh)
        XCTAssertFalse(coordinator.shouldUpdate(isOnOfficeNetwork: false),
                       "WFH update should be suppressed when already checked in as WFH")
    }

    func test_shouldUpdateToOffice_returnsTrue_whenAlreadyCheckedInAsWFH() {
        store.saveAttendance(date: coordinator.todayDateString(), status: .wfh)
        XCTAssertTrue(coordinator.shouldUpdate(isOnOfficeNetwork: true),
                      "Office update should override an existing WFH check-in")
    }

    func test_shouldUpdateToOffice_returnsFalse_whenAlreadyCheckedInAsOffice() {
        coordinator.markOfficeSeen()
        store.saveAttendance(date: coordinator.todayDateString(), status: .office)
        XCTAssertFalse(coordinator.shouldUpdate(isOnOfficeNetwork: true),
                       "Office update should be a no-op when already checked in as office")
    }

    // MARK: - Manual check-in office stickiness invariant

    func test_shouldUpdateToWFH_returnsFalse_afterManualOfficeCheckIn() {
        // Simulates: user manually selects Office from the menu, then later wakes
        // up at home — the sticky flag must suppress the WFH update.
        coordinator.markOfficeSeen()
        store.saveAttendance(date: coordinator.todayDateString(), status: .office)
        XCTAssertFalse(coordinator.shouldUpdate(isOnOfficeNetwork: false),
                       "WFH should be suppressed after a manual office check-in")
    }
}
