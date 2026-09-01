import AppKit
import SwiftUI
import Combine
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var credentialStore = CredentialStore()
    private var mondayService = MondayService()
    private var coordinator: AttendanceCoordinator?
    private var cancellables = Set<AnyCancellable>()
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settingsWindowController = SettingsWindowController(
            credentialStore: credentialStore,
            mondayService: mondayService
        )
        settingsWindowController?.onSave = { [weak self] in
            self?.restartCoordinator()
        }

        let networkMonitor = NetworkMonitor()
        coordinator = AttendanceCoordinator(
            credentialStore: credentialStore,
            networkMonitor: networkMonitor,
            mondayService: mondayService
        )
        Task { @MainActor [weak self] in self?.coordinator?.start() }

        coordinator?.$checkInState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.statusItem?.menu = self?.buildMenu()
            }
            .store(in: &cancellables)

        NotificationService.shared.requestPermission()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "🏢?"
        statusItem?.menu = buildMenu()

        // Show settings on first launch if not configured
        if credentialStore.load() == nil {
            settingsWindowController?.show()
        }

        // Listen for notification-triggered actions
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
                                               name: .openSettings, object: nil)
        
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    @MainActor private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Weekend: show static icon, no check-in options
        let weekday = Calendar.current.component(.weekday, from: Date())
        if weekday == 1 || weekday == 7 {
            self.statusItem?.button?.title = "🏢"
            let item = NSMenuItem(title: "Weekend — no attendance needed", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            switch coordinator?.checkInState {
            case .checkedIn(let status):
                self.statusItem?.button?.title = "\(status.icon) \(status.menuLabel)"
                let statusItem = NSMenuItem(title: "\(status.icon) \(status.menuLabel)", action: nil, keyEquivalent: "")
                statusItem.isEnabled = false
                menu.addItem(statusItem)
                menu.addItem(NSMenuItem(title: today(), action: nil, keyEquivalent: ""))
                menu.addItem(.separator())
                let changeHeader = NSMenuItem(title: "Change to:", action: nil, keyEquivalent: "")
                changeHeader.isEnabled = false
                menu.addItem(changeHeader)
                for s in AttendanceStatus.allCases where s != status {
                    let item = NSMenuItem(title: s.menuLabel, action: #selector(changeStatus(_:)), keyEquivalent: "")
                    item.representedObject = s
                    menu.addItem(item)
                }
            case .error(let msg):
                self.statusItem?.button?.title = "🏢⚠️"
                let errItem = NSMenuItem(title: "Error: \(msg)", action: nil, keyEquivalent: "")
                errItem.isEnabled = false
                menu.addItem(errItem)
            default:
                self.statusItem?.button?.title = "🏢?"
                let checkInHeader = NSMenuItem(title: "Not checked in yet", action: nil, keyEquivalent: "")
                checkInHeader.isEnabled = false
                menu.addItem(checkInHeader)
                menu.addItem(.separator())
                for s in AttendanceStatus.allCases {
                    let item = NSMenuItem(title: "Set: \(s.menuLabel)", action: #selector(changeStatus(_:)), keyEquivalent: "")
                    item.representedObject = s
                    menu.addItem(item)
                }
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func changeStatus(_ sender: NSMenuItem) {
        guard let status = sender.representedObject as? AttendanceStatus else { return }
        Task { await coordinator?.manualCheckIn(status: status) }
    }

    private func today() -> String {
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .none
        return f.string(from: Date())
    }

    @objc private func openSettings() {
        settingsWindowController?.show()
    }

    private func restartCoordinator() {
        Task { @MainActor [weak self] in self?.coordinator?.start() }
    }
}
