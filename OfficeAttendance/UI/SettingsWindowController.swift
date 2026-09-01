import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    private let credentialStore: CredentialStore
    private let mondayService: MondayService
    var onSave: (() -> Void)?

    init(credentialStore: CredentialStore, mondayService: MondayService) {
        self.credentialStore = credentialStore
        self.mondayService = mondayService
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Office Attendance Settings"
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        // Rebuild the view each time so onSave is always current
        let settingsView = SettingsView(
            credentialStore: credentialStore,
            mondayService: mondayService,
            onSave: onSave
        )
        let hostingController = NSHostingController(rootView: settingsView)
        window?.contentViewController = hostingController
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
