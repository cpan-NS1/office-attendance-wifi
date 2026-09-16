import Foundation
import Combine

@MainActor
final class AttendanceCoordinator: ObservableObject {
    @Published private(set) var checkInState: CheckInState = .notCheckedIn

    private let credentialStore: CredentialStore
    private let networkMonitor: NetworkMonitor
    private let mondayService: MondayService
    private var cancellables = Set<AnyCancellable>()
    private var midnightTimer: Timer?

    init(credentialStore: CredentialStore,
         networkMonitor: NetworkMonitor,
         mondayService: MondayService) {
        self.credentialStore = credentialStore
        self.networkMonitor = networkMonitor
        self.mondayService = mondayService
    }

    /// Triggers an immediate network re-evaluation — called on wake from sleep.
    func checkNetworkNow() {
        guard let credentials = credentialStore.load() else { return }
        networkMonitor.checkCurrentNetwork(credentials: credentials)
    }

    func start() {
        print("[Coordinator] start() called")
        credentialStore.migrateFromUserDefaultsIfNeeded()
        guard let credentials = credentialStore.load() else {
            print("[Coordinator] start() — no credentials, returning early")
            // No credentials — stay idle; SettingsWindow will be shown by AppDelegate
            NotificationService.shared.sendSetupReminder()
            return
        }
        print("[Coordinator] start() — credentials loaded, ipPrefix='\(credentials.ipPrefix)' dnsDomain='\(credentials.dnsDomain)'")

        // Restore today's status from UserDefaults so the menu is correct immediately,
        // even before any network check or API call.
        restoreStateFromDefaults()

        networkMonitor.start(credentials: credentials)
        networkMonitor.$isOnOfficeNetwork
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOffice in
                self?.handleNetworkChange(isOnOfficeNetwork: isOffice, credentials: credentials)
            }
            .store(in: &cancellables)
        scheduleMidnightReset()
    }

    /// Seeds `checkInState` from today's persisted value so the menu reflects
    /// the correct status immediately on launch, and sends a notification so
    /// the user knows what was already logged.
    private func restoreStateFromDefaults() {
        let today = todayDateString()
        guard let entry = credentialStore.loadHistory().first(where: { $0.date == today })
        else { return }
        checkInState = .checkedIn(entry.status)
        NotificationService.shared.sendCheckInNotification(status: entry.status)
    }

    func manualCheckIn(status: AttendanceStatus) async {
        guard let credentials = credentialStore.load(),
              let columnMap = credentialStore.loadColumnMap() else { return }
        do {
            try await mondayService.checkIn(status: status, credentials: credentials,
                                            columnMap: columnMap)
            if status == .office { markOfficeSeen() }
            credentialStore.saveAttendance(date: todayDateString(), status: status)
            checkInState = .checkedIn(status)
            NotificationService.shared.sendChangeConfirmation(status: status)
        } catch {
            AppLogger.shared.log("Manual check-in failed: \(error.localizedDescription)")
            checkInState = .error(error.localizedDescription)
        }
    }

    // MARK: - Testable helpers

    func isWeekend(date: Date = Date()) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 || weekday == 7 // Sun or Sat
    }

    func alreadyCheckedIn(for date: String) -> Bool {
        credentialStore.loadHistory().contains { $0.date == date }
    }

    func todayDateString(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    /// Legacy shim kept for any call sites that still use the old key-based API.
    func todayKey() -> String { "attendance-\(todayDateString())" }

    /// Key used to persist whether office WiFi was detected at any point today.
    func officeSeenTodayKey() -> String {
        "attendance-office-\(todayDateString())"
    }

    func officeWasSeenToday() -> Bool {
        UserDefaults.standard.bool(forKey: officeSeenTodayKey())
    }

    func markOfficeSeen() {
        UserDefaults.standard.set(true, forKey: officeSeenTodayKey())
    }

    /// Returns whether a network-triggered check-in should proceed.
    ///
    /// Rules:
    /// - Office WiFi: proceed only if not already checked in as office today.
    /// - Non-office WiFi: proceed only if office was never seen today AND not yet checked in at all.
    func shouldUpdate(isOnOfficeNetwork: Bool) -> Bool {
        let today = todayDateString()
        if isOnOfficeNetwork {
            // Office always wins, but skip if already recorded as office.
            let existing = credentialStore.loadHistory().first(where: { $0.date == today })
            return existing?.status != .office
        } else {
            // WFH only if office hasn't been seen today and not yet checked in.
            return !officeWasSeenToday() && !alreadyCheckedIn(for: today)
        }
    }

    // MARK: - Private

    private func handleNetworkChange(isOnOfficeNetwork: Bool,
                                     credentials: CredentialStore.Credentials) {
        print("[Coordinator] handleNetworkChange isOnOfficeNetwork=\(isOnOfficeNetwork)")
        guard !isWeekend() else { print("[Coordinator] blocked — weekend"); return }
        guard shouldUpdate(isOnOfficeNetwork: isOnOfficeNetwork) else { print("[Coordinator] blocked — shouldUpdate=false"); return }
        guard let columnMap = credentialStore.loadColumnMap() else {
            print("[Coordinator] blocked — no columnMap")
            checkInState = .error("Setup incomplete — please open Settings and verify your board")
            NotificationService.shared.sendSetupReminder()
            return
        }
        print("[Coordinator] proceeding to check in as \(isOnOfficeNetwork ? "office" : "wfh")")

        let status: AttendanceStatus = isOnOfficeNetwork ? .office : .wfh
        Task {
            do {
                try await mondayService.checkIn(status: status, credentials: credentials,
                                                columnMap: columnMap)
                if isOnOfficeNetwork { markOfficeSeen() }
                credentialStore.saveAttendance(date: todayDateString(), status: status)
                checkInState = .checkedIn(status)
                NotificationService.shared.sendCheckInNotification(status: status)
            } catch {
                AppLogger.shared.log("Check-in failed: \(error.localizedDescription)")
                checkInState = .error(error.localizedDescription)
            }
        }
    }

    private func scheduleMidnightReset() {
        midnightTimer?.invalidate()
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
              let midnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: tomorrow)
        else { return }
        midnightTimer = Timer(fire: midnight, interval: 86400, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkInState = .notCheckedIn
            }
        }
        RunLoop.main.add(midnightTimer!, forMode: .common)
    }
}
