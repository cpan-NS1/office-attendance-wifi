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
        // Activate the app first, then order the window front.
        // setActivationPolicy must come before activate; activate must come
        // before makeKeyAndOrderFront so that when the window is ordered
        // front the app is already active and the window actually receives
        // focus instead of sitting behind the previous frontmost app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Only hide from Dock if the user hasn't opted to keep it visible.
        if !UserDefaults.standard.bool(forKey: UserDefaults.Keys.showInDock) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
