import AppKit
import SwiftUI

final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    private let credentialStore: CredentialStore

    init(credentialStore: CredentialStore) {
        self.credentialStore = credentialStore
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
        let boardId = credentialStore.load()?.boardId ?? ""
        let view = HistoryView(credentialStore: credentialStore, boardId: boardId)
        window?.contentViewController = NSHostingController(rootView: view)
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
