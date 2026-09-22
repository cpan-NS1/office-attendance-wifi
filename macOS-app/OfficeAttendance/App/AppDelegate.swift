import AppKit
import SwiftUI
import Combine
import Sparkle
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var historyWindowController: HistoryWindowController?
    private var credentialStore = CredentialStore()
    private var mondayService = MondayService()
    private var coordinator: AttendanceCoordinator?
    private var cancellables = Set<AnyCancellable>()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var globalHotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.shared.log("App launched (v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"))")

        let networkMonitor = NetworkMonitor()
        AppLogger.shared.log("Setting up windows")
        settingsWindowController = SettingsWindowController(
            credentialStore: credentialStore,
            mondayService: mondayService,
            networkMonitor: networkMonitor
        )
        settingsWindowController?.onSave = { [weak self] in
            self?.restartCoordinator()
        }
        historyWindowController = HistoryWindowController(credentialStore: credentialStore, mondayService: mondayService)
        coordinator = AttendanceCoordinator(
            credentialStore: credentialStore,
            networkMonitor: networkMonitor,
            mondayService: mondayService
        )
        AppLogger.shared.log("Starting coordinator")
        Task { @MainActor [weak self] in self?.coordinator?.start() }

        coordinator?.$checkInState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.statusItem?.menu = self?.buildMenu()
            }
            .store(in: &cancellables)

        NotificationService.shared.requestPermission()

        AppLogger.shared.log("Creating status bar item")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "🏢?"
        statusItem?.menu = buildMenu()
        AppLogger.shared.log("Status bar item created")

        // Apply saved Dock visibility preference
        if UserDefaults.standard.bool(forKey: UserDefaults.Keys.showInDock) {
            NSApp.setActivationPolicy(.regular)
        }

        // Register ⌥⌘A global hotkey as a fallback when the menu bar icon is hidden
        registerGlobalHotKey()

        // Show settings on first launch if not configured
        if credentialStore.load() == nil {
            AppLogger.shared.log("No credentials found — showing settings")
            settingsWindowController?.show()
        } else {
            AppLogger.shared.log("Credentials loaded OK")
        }

        // Listen for notification-triggered actions
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
                                               name: .openSettings, object: nil)

        // Re-evaluate network on wake from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    /// Groups for the status submenu structure.
    /// Each entry is (parentLabel, members). A group with one remaining
    /// member after exclusion is flattened to a plain item.
    private let statusGroups: [(label: String, members: [AttendanceStatus])] = [
        ("Office",   [.office]),
        ("WFH",      [.wfh, .wfhSickness, .wfhUnplannedIssues, .wfhWeatherWarning]),
        ("Vacation", [.vacation, .loa, .bankHoliday, .travel]),
        ("Sick",     [.sick]),
    ]

    /// Appends status items to `menu`. Single-member groups appear as plain
    /// items; multi-member groups use a submenu. The currently active status
    /// is excluded; if that empties a group its parent is hidden too.
    @MainActor private func addStatusItems(to menu: NSMenu,
                                           prefix: String = "",
                                           excluding current: AttendanceStatus? = nil) {
        for group in statusGroups {
            let candidates = group.members.filter { $0 != current }
            guard !candidates.isEmpty else { continue }

            if group.members.count == 1 {
                // Single-member group — plain item
                let item = NSMenuItem(title: "\(prefix)\(candidates[0].menuLabel)",
                                     action: #selector(changeStatus(_:)),
                                     keyEquivalent: "")
                item.representedObject = candidates[0]
                menu.addItem(item)
            } else {
                // Multi-member group — submenu
                let subMenu = NSMenu()
                for s in candidates {
                    let item = NSMenuItem(title: "\(prefix)\(s.menuLabel)",
                                         action: #selector(changeStatus(_:)),
                                         keyEquivalent: "")
                    item.representedObject = s
                    subMenu.addItem(item)
                }
                let parent = NSMenuItem(title: "\(prefix)\(group.label)…", action: nil, keyEquivalent: "")
                parent.submenu = subMenu
                menu.addItem(parent)
            }
        }
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
                addStatusItems(to: menu, excluding: status)
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
                addStatusItems(to: menu, prefix: "Set: ")
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "History…", action: #selector(openHistory), keyEquivalent: "h"))
        if let boardId = credentialStore.load()?.boardId,
           let url = URL(string: "https://ibm.monday.com/boards/\(boardId)") {
            let boardItem = NSMenuItem(title: "Open Board ↗", action: #selector(openBoard), keyEquivalent: "")
            boardItem.representedObject = url
            menu.addItem(boardItem)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""))
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

    @objc private func openHistory() {
        historyWindowController?.show()
    }

    @objc private func openBoard(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    @objc private func openSettings() {
        settingsWindowController?.show()
    }

    @objc private func handleWake() {
        // Delay to allow WiFi to fully associate and obtain a DHCP lease after wake.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self?.coordinator?.checkNetworkNow()
        }
    }

    private func restartCoordinator() {
        Task { @MainActor [weak self] in self?.coordinator?.start() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        statusItem?.button?.performClick(nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let ref = globalHotKeyRef { UnregisterEventHotKey(ref) }
        if let handler = hotKeyHandler { RemoveEventHandler(handler) }
    }

    // MARK: - Global hotkey (⌥⌘A)

    private static let hotKeyVirtualKeyCode: UInt32 = 0x00  // kVK_ANSI_A
    private static let hotKeySignature: OSType = 0x4F414141  // "OAAa"

    private func registerGlobalHotKey() {
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: 1)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(Self.hotKeyVirtualKeyCode, UInt32(cmdKey | optionKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &ref)
        globalHotKeyRef = ref

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { delegate.statusItem?.button?.performClick(nil) }
            return noErr
        }, 1, &eventSpec, selfPtr, &hotKeyHandler)
    }
}
