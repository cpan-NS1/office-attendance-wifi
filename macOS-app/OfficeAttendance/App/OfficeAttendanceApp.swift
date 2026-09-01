import SwiftUI

@main
struct OfficeAttendanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — Menu Bar only
        Settings { EmptyView() }
    }
}
