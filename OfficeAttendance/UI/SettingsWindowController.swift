import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    private let credentialStore: CredentialStore
    private let mondayService: MondayService
    var onSave: (() -> Void)?

    init(credentialStore: CredentialStore, mondayService: MondayService) {
        self.credentialStore = credentialStore
        self.mondayService = mondayService
        let settingsView = SettingsView(credentialStore: credentialStore,
                                        mondayService: mondayService)
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Office Attendance Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
