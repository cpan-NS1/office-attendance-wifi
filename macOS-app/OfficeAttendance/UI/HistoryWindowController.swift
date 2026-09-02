import AppKit
import SwiftUI

final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    private let credentialStore: CredentialStore
    private let mondayService: MondayService

    init(credentialStore: CredentialStore, mondayService: MondayService) {
        self.credentialStore = credentialStore
        self.mondayService = mondayService
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Attendance History"
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        let creds = credentialStore.load()
        let boardId = creds?.boardId ?? ""
        let view = HistoryView(
            credentialStore: credentialStore,
            mondayService: mondayService,
            credentials: creds,
            boardId: boardId
        )
        window?.contentViewController = NSHostingController(rootView: view)
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
