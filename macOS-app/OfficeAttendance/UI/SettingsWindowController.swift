import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let credentialStore: CredentialStore
    private let mondayService: MondayService
    private let networkMonitor: NetworkMonitor
    var onSave: (() -> Void)?

    init(credentialStore: CredentialStore, mondayService: MondayService, networkMonitor: NetworkMonitor) {
        self.credentialStore = credentialStore
        self.mondayService = mondayService
        self.networkMonitor = networkMonitor
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Office Attendance Settings"
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        // Rebuild the view each time so onSave is always current
        let settingsView = SettingsView(
            credentialStore: credentialStore,
            mondayService: mondayService,
            networkMonitor: networkMonitor,
            onSave: onSave
        )
        let hostingController = NSHostingController(rootView: settingsView)
        window?.contentViewController = hostingController
        // When triggered from an NSMenu action, macOS closes the menu and
        // briefly returns focus to the previously-active app after the action
        // fires. A one-tick async dispatch is not enough — the menu dismissal
        // animation completes after that tick and the other app steals focus
        // back. orderFrontRegardless() makes the window appear on screen
        // immediately, and we wait 150 ms (well past menu dismissal) before
        // calling activate + makeKeyAndOrderFront so we reliably win the
        // focus race.
        window?.orderFrontRegardless()
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Only hide from Dock if the user hasn't opted to keep it visible.
        if !UserDefaults.standard.bool(forKey: UserDefaults.Keys.showInDock) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
