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

    func start() {
        guard let credentials = credentialStore.load() else {
            // No credentials — stay idle; SettingsWindow will be shown by AppDelegate
            NotificationService.shared.sendSetupReminder()
            return
        }

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

    /// Seeds `checkInState` from today's persisted UserDefaults value so the
    /// menu reflects the correct status immediately on launch, and sends a
    /// notification so the user knows what was already logged.
    private func restoreStateFromDefaults() {
        let key = todayKey()
        guard let saved = UserDefaults.standard.string(forKey: key),
              let status = AttendanceStatus.allCases.first(where: { $0.mondayValue == saved })
        else { return }
        checkInState = .checkedIn(status)
        NotificationService.shared.sendCheckInNotification(status: status)
    }

    func manualCheckIn(status: AttendanceStatus) async {
        guard let credentials = credentialStore.load(),
              let columnMap = credentialStore.loadColumnMap() else { return }
        do {
            try await mondayService.checkIn(status: status, credentials: credentials,
                                            columnMap: columnMap)
            let key = todayKey()
            UserDefaults.standard.set(status.mondayValue, forKey: key)
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

    func alreadyCheckedIn(for key: String) -> Bool {
        UserDefaults.standard.string(forKey: key) != nil
    }

    func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "attendance-\(formatter.string(from: Date()))"
    }

    // MARK: - Private

    private func handleNetworkChange(isOnOfficeNetwork: Bool,
                                     credentials: CredentialStore.Credentials) {
        guard !isWeekend() else { return }
        let key = todayKey()
        guard !alreadyCheckedIn(for: key) else { return }
        guard let columnMap = credentialStore.loadColumnMap() else { return }

        let status: AttendanceStatus = isOnOfficeNetwork ? .office : .wfh
        Task {
            do {
                try await mondayService.checkIn(status: status, credentials: credentials,
                                                columnMap: columnMap)
                UserDefaults.standard.set(status.mondayValue, forKey: key)
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
