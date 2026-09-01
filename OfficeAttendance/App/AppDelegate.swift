import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var credentialStore = CredentialStore()
    private var mondayService = MondayService()
    private var coordinator: AttendanceCoordinator?
    private var cancellables = Set<AnyCancellable>()

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
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func openSettings() {
        settingsWindowController?.show()
    }

    private func restartCoordinator() {
        Task { @MainActor [weak self] in self?.coordinator?.start() }
    }
}
