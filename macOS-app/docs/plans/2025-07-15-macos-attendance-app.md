# macOS Office Attendance App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS Menu Bar app that auto-logs daily attendance on Monday.com when the user connects to the office Wi-Fi, with a system notification and a dropdown to correct the status.

**Architecture:** SwiftUI Menu Bar app (no main window), `NWPathMonitor` for real-time network detection, `AttendanceCoordinator` as the single orchestrator, `MondayService` for API calls, credentials in Keychain.

**Tech Stack:** Swift 5.9+, SwiftUI + AppKit, Network.framework, UserNotifications.framework, Security.framework (Keychain), URLSession, Sparkle 2.x (auto-update)

**Spec:** `docs/superpowers/specs/2025-07-15-macos-attendance-app-design.md`

## Global Constraints

- Minimum deployment target: macOS 13.0 (Ventura)
- Language: Swift 5.9+; no Objective-C new files
- Bundle ID: `com.ibm.office-attendance`
- Keychain service name: `com.ibm.office-attendance`
- `UserDefaults` suite: standard (no app group needed — single process)
- Attendance key format: `attendance-YYYY-MM-DD`
- Monday.com API endpoint: `https://api.monday.com/v2` (HTTPS only, no certificate bypass)
- All network calls: `URLSession` with 30-second timeout, no `0.0.0.0` binding
- No hardcoded secrets; all credentials via Keychain
- Sparkle 2.x for auto-update (do not use Sparkle 1.x)
- Sign with Developer ID Application; notarize before release
- Status values (exact strings): `Office`, `WFH`, `Sick`, `Vacation`, `Holiday`

---

## File Map

```
OfficeAttendance/
├── App/
│   ├── OfficeAttendanceApp.swift          # @main, NSApplicationDelegate, Login Item setup
│   └── AppDelegate.swift                  # NSStatusItem, menu construction
├── Coordinator/
│   └── AttendanceCoordinator.swift        # Orchestration — network → check-in decision tree
├── Services/
│   ├── NetworkMonitor.swift               # NWPathMonitor wrapper, isOnOfficeNetwork publisher
│   ├── MondayService.swift                # Board introspection + query + mutation
│   ├── NotificationService.swift          # UNUserNotificationCenter wrapper
│   └── CredentialStore.swift             # Keychain read/write + UserDefaults column map
├── UI/
│   ├── MenuBarView.swift                  # SwiftUI menu content (status + dropdown items)
│   └── SettingsWindowController.swift     # NSWindowController hosting SettingsView
│   └── SettingsView.swift                 # SwiftUI form: credentials, network, board verify
├── Models/
│   ├── AttendanceStatus.swift             # enum AttendanceStatus + icon/label helpers
│   ├── ColumnMap.swift                    # struct ColumnMap (7 columnId fields)
│   └── CheckInState.swift                 # enum CheckInState (notCheckedIn/checkedIn/error)
└── Utilities/
    └── Logger.swift                       # Rotating log file (1 MB × 3)
```

Tests live under `OfficeAttendanceTests/` mirroring the above structure.

---

## Task 1: Xcode Project Scaffold

**Files:**
- Create: `OfficeAttendance.xcodeproj` (Xcode project)
- Create: `OfficeAttendance/App/OfficeAttendanceApp.swift`
- Create: `OfficeAttendance/App/AppDelegate.swift`
- Create: `OfficeAttendanceTests/` test target

**Interfaces:**
- Produces: compilable app target, test target, `NSStatusItem` stub in AppDelegate

- [ ] **Step 1: Create Xcode project**

In Xcode: File → New → Project → macOS → App.
- Product Name: `OfficeAttendance`
- Bundle Identifier: `com.ibm.office-attendance`
- Interface: SwiftUI
- Language: Swift
- Uncheck "Include Tests" (we'll add the test target manually for control)
- Deployment Target: macOS 13.0

- [ ] **Step 2: Remove default ContentView, add AppDelegate**

Delete `ContentView.swift`. Replace `OfficeAttendanceApp.swift` with:

```swift
import SwiftUI

@main
struct OfficeAttendanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — Menu Bar only
        Settings { EmptyView() }
    }
}
```

Create `OfficeAttendance/App/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "🏢?"
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func openSettings() {
        // Placeholder — wired up in Task 6
    }
}
```

- [ ] **Step 3: Add unit test target**

In Xcode: File → New → Target → macOS → Unit Testing Bundle.
- Name: `OfficeAttendanceTests`
- Host Application: `OfficeAttendance`

- [ ] **Step 4: Build and run — verify menu bar icon appears**

Product → Run (⌘R). Confirm `🏢?` appears in the menu bar and the app does not appear in the Dock.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat: scaffold menu bar app — status item, no dock icon"
```

---

## Task 2: Models

**Files:**
- Create: `OfficeAttendance/Models/AttendanceStatus.swift`
- Create: `OfficeAttendance/Models/ColumnMap.swift`
- Create: `OfficeAttendance/Models/CheckInState.swift`
- Test: `OfficeAttendanceTests/Models/AttendanceStatusTests.swift`

**Interfaces:**
- Produces:
  - `enum AttendanceStatus: String, CaseIterable` — cases: `office`, `wfh`, `sick`, `vacation`, `holiday`; computed `mondayValue: String`, `menuLabel: String`, `icon: String`
  - `struct ColumnMap: Codable` — fields: `employeeColumnId`, `weekStartColumnId`, `mondayColumnId`, `tuesdayColumnId`, `wednesdayColumnId`, `thursdayColumnId`, `fridayColumnId` (all `String`)
  - `enum CheckInState` — cases: `notCheckedIn`, `checkedIn(AttendanceStatus)`, `error(String)`

- [ ] **Step 1: Write failing tests**

Create `OfficeAttendanceTests/Models/AttendanceStatusTests.swift`:

```swift
import XCTest
@testable import OfficeAttendance

final class AttendanceStatusTests: XCTestCase {
    func test_mondayValue_matchesExpectedStrings() {
        XCTAssertEqual(AttendanceStatus.office.mondayValue, "Office")
        XCTAssertEqual(AttendanceStatus.wfh.mondayValue, "WFH")
        XCTAssertEqual(AttendanceStatus.sick.mondayValue, "Sick")
        XCTAssertEqual(AttendanceStatus.vacation.mondayValue, "Vacation")
        XCTAssertEqual(AttendanceStatus.holiday.mondayValue, "Holiday")
    }

    func test_allCases_haveNonEmptyIcon() {
        for status in AttendanceStatus.allCases {
            XCTAssertFalse(status.icon.isEmpty, "\(status) has empty icon")
        }
    }
}
```

- [ ] **Step 2: Run — verify it fails**

Product → Test (⌘U). Expected: compile error "cannot find type AttendanceStatus".

- [ ] **Step 3: Implement models**

Create `OfficeAttendance/Models/AttendanceStatus.swift`:

```swift
enum AttendanceStatus: String, CaseIterable, Codable {
    case office, wfh, sick, vacation, holiday

    /// The string value written to Monday.com
    var mondayValue: String {
        switch self {
        case .office:   return "Office"
        case .wfh:      return "WFH"
        case .sick:     return "Sick"
        case .vacation: return "Vacation"
        case .holiday:  return "Holiday"
        }
    }

    var menuLabel: String {
        switch self {
        case .office:   return "Office"
        case .wfh:      return "WFH"
        case .sick:     return "Sick"
        case .vacation: return "Vacation"
        case .holiday:  return "Holiday"
        }
    }

    var icon: String {
        switch self {
        case .office:   return "🏢"
        case .wfh:      return "🏠"
        case .sick:     return "🤒"
        case .vacation: return "🌴"
        case .holiday:  return "🎌"
        }
    }
}
```

Create `OfficeAttendance/Models/ColumnMap.swift`:

```swift
struct ColumnMap: Codable {
    var employeeColumnId: String
    var weekStartColumnId: String
    var mondayColumnId: String
    var tuesdayColumnId: String
    var wednesdayColumnId: String
    var thursdayColumnId: String
    var fridayColumnId: String

    /// Returns the column ID for the given weekday (1 = Mon … 5 = Fri).
    /// Returns nil for weekends.
    func columnId(forWeekday weekday: Int) -> String? {
        switch weekday {
        case 2: return mondayColumnId
        case 3: return tuesdayColumnId
        case 4: return wednesdayColumnId
        case 5: return thursdayColumnId
        case 6: return fridayColumnId
        default: return nil
        }
    }
}
```

> Note: `Calendar.component(.weekday)` returns 1=Sun, 2=Mon … 7=Sat on the Gregorian calendar. `columnId(forWeekday:)` uses that convention.

Create `OfficeAttendance/Models/CheckInState.swift`:

```swift
enum CheckInState {
    case notCheckedIn
    case checkedIn(AttendanceStatus)
    case error(String)
}
```

- [ ] **Step 4: Run tests — verify they pass**

Product → Test (⌘U). Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat: add AttendanceStatus, ColumnMap, CheckInState models"
```

---

## Task 3: CredentialStore

**Files:**
- Create: `OfficeAttendance/Services/CredentialStore.swift`
- Test: `OfficeAttendanceTests/Services/CredentialStoreTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `final class CredentialStore: ObservableObject`
  - `func save(token: String, boardId: String, employeeId: String, ipPrefix: String, dnsDomain: String) throws`
  - `func load() -> Credentials?` — returns `nil` if any required field is missing
  - `func saveColumnMap(_ map: ColumnMap)`
  - `func loadColumnMap() -> ColumnMap?`
  - `func clearAll()`
  - `struct Credentials` — fields: `token`, `boardId`, `employeeId`, `ipPrefix`, `dnsDomain` (all `String`)

- [ ] **Step 1: Write failing tests**

Create `OfficeAttendanceTests/Services/CredentialStoreTests.swift`:

```swift
import XCTest
@testable import OfficeAttendance

final class CredentialStoreTests: XCTestCase {
    var store: CredentialStore!

    override func setUp() {
        super.setUp()
        store = CredentialStore()
        store.clearAll()
    }

    func test_load_returnsNil_whenNothingSaved() {
        XCTAssertNil(store.load())
    }

    func test_saveAndLoad_roundTrips() throws {
        try store.save(token: "tok", boardId: "123", employeeId: "emp",
                       ipPrefix: "9.", dnsDomain: "ibm.com")
        let creds = store.load()
        XCTAssertEqual(creds?.token, "tok")
        XCTAssertEqual(creds?.boardId, "123")
        XCTAssertEqual(creds?.employeeId, "emp")
        XCTAssertEqual(creds?.ipPrefix, "9.")
        XCTAssertEqual(creds?.dnsDomain, "ibm.com")
    }

    func test_columnMap_roundTrips() {
        let map = ColumnMap(employeeColumnId: "e", weekStartColumnId: "ws",
                            mondayColumnId: "m", tuesdayColumnId: "t",
                            wednesdayColumnId: "w", thursdayColumnId: "th",
                            fridayColumnId: "f")
        store.saveColumnMap(map)
        let loaded = store.loadColumnMap()
        XCTAssertEqual(loaded?.mondayColumnId, "m")
        XCTAssertEqual(loaded?.fridayColumnId, "f")
    }
}
```

- [ ] **Step 2: Run — verify it fails**

Expected: compile error "cannot find type CredentialStore".

- [ ] **Step 3: Implement CredentialStore**

Create `OfficeAttendance/Services/CredentialStore.swift`:

```swift
import Foundation
import Security

final class CredentialStore: ObservableObject {
    private let serviceName = "com.ibm.office-attendance"
    private let columnMapKey = "columnMap"

    struct Credentials {
        let token: String
        let boardId: String
        let employeeId: String
        let ipPrefix: String
        let dnsDomain: String
    }

    // MARK: - Keychain

    func save(token: String, boardId: String, employeeId: String,
              ipPrefix: String, dnsDomain: String) throws {
        try setKeychainItem(key: "monday-token", value: token)
        try setKeychainItem(key: "board-id", value: boardId)
        try setKeychainItem(key: "employee-id", value: employeeId)
        try setKeychainItem(key: "office-ip-prefix", value: ipPrefix)
        try setKeychainItem(key: "office-dns-domain", value: dnsDomain)
    }

    func load() -> Credentials? {
        guard
            let token  = getKeychainItem(key: "monday-token"),
            let boardId = getKeychainItem(key: "board-id"),
            let empId  = getKeychainItem(key: "employee-id"),
            let ip     = getKeychainItem(key: "office-ip-prefix"),
            let dns    = getKeychainItem(key: "office-dns-domain")
        else { return nil }
        return Credentials(token: token, boardId: boardId, employeeId: empId,
                           ipPrefix: ip, dnsDomain: dns)
    }

    func clearAll() {
        for key in ["monday-token", "board-id", "employee-id",
                    "office-ip-prefix", "office-dns-domain"] {
            deleteKeychainItem(key: key)
        }
        UserDefaults.standard.removeObject(forKey: columnMapKey)
    }

    // MARK: - UserDefaults (column map)

    func saveColumnMap(_ map: ColumnMap) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: columnMapKey)
        }
    }

    func loadColumnMap() -> ColumnMap? {
        guard let data = UserDefaults.standard.data(forKey: columnMapKey) else { return nil }
        return try? JSONDecoder().decode(ColumnMap.self, from: data)
    }

    // MARK: - Private Keychain helpers

    private func setKeychainItem(key: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
        let attributes = query.merging([kSecValueData: data]) { $1 }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func getKeychainItem(key: String) -> String? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychainItem(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

⌘U. Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat: add CredentialStore — Keychain + UserDefaults column map"
```

---

## Task 4: NetworkMonitor

**Files:**
- Create: `OfficeAttendance/Services/NetworkMonitor.swift`
- Test: `OfficeAttendanceTests/Services/NetworkMonitorTests.swift`

**Interfaces:**
- Consumes: `CredentialStore.Credentials` (for `ipPrefix`, `dnsDomain`)
- Produces:
  - `final class NetworkMonitor: ObservableObject`
  - `@Published var isOnOfficeNetwork: Bool`
  - `func start(credentials: CredentialStore.Credentials)`
  - `func stop()`
  - Internal: `func evaluate(path: NWPath, credentials: CredentialStore.Credentials) -> Bool` (testable)

- [ ] **Step 1: Write failing tests**

Create `OfficeAttendanceTests/Services/NetworkMonitorTests.swift`:

```swift
import XCTest
import Network
@testable import OfficeAttendance

final class NetworkMonitorTests: XCTestCase {
    func test_evaluate_returnsTrue_whenIPMatches() {
        let monitor = NetworkMonitor()
        // evaluate is tested via the helper that checks IP prefix
        let result = monitor.ipMatches(ip: "9.123.45.67", prefix: "9.")
        XCTAssertTrue(result)
    }

    func test_evaluate_returnsFalse_whenIPDoesNotMatch() {
        let monitor = NetworkMonitor()
        let result = monitor.ipMatches(ip: "192.168.1.1", prefix: "9.")
        XCTAssertFalse(result)
    }

    func test_evaluate_returnsTrue_whenDNSMatches() {
        let monitor = NetworkMonitor()
        let result = monitor.dnsMatches(domain: "subdomain.ibm.com", suffix: "ibm.com")
        XCTAssertTrue(result)
    }

    func test_evaluate_returnsFalse_whenBothEmpty() {
        let monitor = NetworkMonitor()
        let resultIP  = monitor.ipMatches(ip: "", prefix: "9.")
        let resultDNS = monitor.dnsMatches(domain: "", suffix: "ibm.com")
        XCTAssertFalse(resultIP)
        XCTAssertFalse(resultDNS)
    }
}
```

- [ ] **Step 2: Run — verify it fails**

Expected: compile error "cannot find type NetworkMonitor".

- [ ] **Step 3: Implement NetworkMonitor**

Create `OfficeAttendance/Services/NetworkMonitor.swift`:

```swift
import Foundation
import Network
import Combine

final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOnOfficeNetwork: Bool = false

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.ibm.office-attendance.network")
    private var credentials: CredentialStore.Credentials?

    func start(credentials: CredentialStore.Credentials) {
        self.credentials = credentials
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            guard let self, let creds = self.credentials else { return }
            let result = self.evaluate(path: path, credentials: creds)
            DispatchQueue.main.async { self.isOnOfficeNetwork = result }
        }
        m.start(queue: queue)
        monitor = m
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    // MARK: - Testable helpers

    func evaluate(path: NWPath, credentials: CredentialStore.Credentials) -> Bool {
        let ip = currentIPAddress() ?? ""
        let dns = currentDNSDomain() ?? ""
        return ipMatches(ip: ip, prefix: credentials.ipPrefix)
            || dnsMatches(domain: dns, suffix: credentials.dnsDomain)
    }

    func ipMatches(ip: String, prefix: String) -> Bool {
        !ip.isEmpty && !prefix.isEmpty && ip.hasPrefix(prefix)
    }

    func dnsMatches(domain: String, suffix: String) -> Bool {
        !domain.isEmpty && !suffix.isEmpty && domain.contains(suffix)
    }

    private func currentIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var addr = ifaddr
        while let current = addr {
            let ifa = current.pointee
            if ifa.ifa_addr.pointee.sa_family == UInt8(AF_INET),
               String(cString: ifa.ifa_name) == "en0" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(ifa.ifa_addr, socklen_t(ifa.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                return String(cString: hostname)
            }
            addr = current.pointee.ifa_next
        }
        return nil
    }

    private func currentDNSDomain() -> String? {
        // Read the first DNS search domain via SystemConfiguration
        guard let store = SCDynamicStoreCreate(nil, "OfficeAttendance" as CFString, nil, nil) else {
            return nil
        }
        let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(
            nil, kSCDynamicStoreDomainState, kSCEntNetDNS)
        guard let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any],
              let domains = dict["SearchDomains"] as? [String] else { return nil }
        return domains.first
    }
}
```

Add `import SystemConfiguration` at the top of the file.

- [ ] **Step 4: Run tests — verify they pass**

⌘U. Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat: add NetworkMonitor — NWPathMonitor wrapper with office detection"
```

---

## Task 5: MondayService

**Files:**
- Create: `OfficeAttendance/Services/MondayService.swift`
- Test: `OfficeAttendanceTests/Services/MondayServiceTests.swift`

**Interfaces:**
- Consumes: `CredentialStore.Credentials`, `ColumnMap`, `AttendanceStatus`
- Produces:
  - `final class MondayService`
  - `func discoverColumns(boardId: String, token: String) async throws -> ColumnMap`
  - `func checkIn(status: AttendanceStatus, credentials: CredentialStore.Credentials, columnMap: ColumnMap) async throws`
  - `struct MondayError: Error` — cases: `noRowFound`, `apiError(String)`, `columnNotFound`

- [ ] **Step 1: Write failing tests**

Create `OfficeAttendanceTests/Services/MondayServiceTests.swift`:

```swift
import XCTest
@testable import OfficeAttendance

final class MondayServiceTests: XCTestCase {
    func test_weekStartDate_isAlwaysMonday() {
        let service = MondayService()
        let calendar = Calendar(identifier: .gregorian)
        // Use a known Wednesday: 2025-07-16
        var components = DateComponents()
        components.year = 2025; components.month = 7; components.day = 16
        let wednesday = calendar.date(from: components)!
        let weekStart = service.weekStartDate(for: wednesday)
        let weekday = calendar.component(.weekday, from: weekStart)
        XCTAssertEqual(weekday, 2, "Week start should be Monday (weekday=2)")
    }

    func test_weekStartDate_formatsAsISO() {
        let service = MondayService()
        var components = DateComponents()
        components.year = 2025; components.month = 7; components.day = 16
        let calendar = Calendar(identifier: .gregorian)
        let wednesday = calendar.date(from: components)!
        let result = service.weekStartDateString(for: wednesday)
        XCTAssertEqual(result, "2025-07-14")
    }
}
```

- [ ] **Step 2: Run — verify it fails**

Expected: compile error "cannot find type MondayService".

- [ ] **Step 3: Implement MondayService**

Create `OfficeAttendance/Services/MondayService.swift`:

```swift
import Foundation

enum MondayError: Error, LocalizedError {
    case noRowFound
    case columnNotFound
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noRowFound:        return "No attendance row found for this week."
        case .columnNotFound:    return "Day column not found in column map."
        case .apiError(let msg): return "Monday.com API error: \(msg)"
        }
    }
}

final class MondayService {
    private let endpoint = URL(string: "https://api.monday.com/v2")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    // MARK: - Column Discovery

    func discoverColumns(boardId: String, token: String) async throws -> ColumnMap {
        let query = """
        query($boardId: ID!) {
          boards(ids: [$boardId]) {
            columns { id title type }
          }
        }
        """
        let payload = try buildPayload(query: query, variables: ["boardId": boardId])
        let data = try await post(payload: payload, token: token)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errors = (json?["errors"] as? [[String: Any]]) ?? []
        if !errors.isEmpty {
            throw MondayError.apiError(errors.first?["message"] as? String ?? "unknown")
        }
        guard let columns = (((json?["data"] as? [String: Any])?["boards"] as? [[String: Any]])?.first)?["columns"] as? [[String: Any]]
        else { throw MondayError.apiError("Unexpected response shape") }

        func id(forTitle title: String) throws -> String {
            guard let col = columns.first(where: { ($0["title"] as? String) == title }),
                  let id = col["id"] as? String else {
                throw MondayError.columnNotFound
            }
            return id
        }

        return ColumnMap(
            employeeColumnId:   try id(forTitle: "Employee name"),
            weekStartColumnId:  try id(forTitle: "Week Start"),
            mondayColumnId:     try id(forTitle: "Monday"),
            tuesdayColumnId:    try id(forTitle: "Tuesday"),
            wednesdayColumnId:  try id(forTitle: "Wednesday"),
            thursdayColumnId:   try id(forTitle: "Thursday"),
            fridayColumnId:     try id(forTitle: "Friday")
        )
    }

    // MARK: - Check-in

    func checkIn(status: AttendanceStatus,
                 credentials: CredentialStore.Credentials,
                 columnMap: ColumnMap) async throws {
        let today = Date()
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: today)

        guard let dayColumnId = columnMap.columnId(forWeekday: weekday) else {
            throw MondayError.columnNotFound
        }

        // Step 1: find the item_id for this person's row this week
        let itemId = try await findItemId(
            boardId: credentials.boardId,
            employeeId: credentials.employeeId,
            weekStartDate: weekStartDateString(for: today),
            columnMap: columnMap,
            token: credentials.token
        )

        // Step 2: write the status to today's column
        let mutation = """
        mutation($boardId: ID!, $itemId: ID!, $columnId: String!, $value: String!) {
          change_simple_column_value(
            board_id: $boardId, item_id: $itemId,
            column_id: $columnId, value: $value
          ) { id }
        }
        """
        let vars: [String: Any] = [
            "boardId":  credentials.boardId,
            "itemId":   itemId,
            "columnId": dayColumnId,
            "value":    status.mondayValue
        ]
        let payload = try buildPayload(query: mutation, variables: vars)
        let data = try await post(payload: payload, token: credentials.token)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errors = (json?["errors"] as? [[String: Any]]) ?? []
        if !errors.isEmpty {
            throw MondayError.apiError(errors.first?["message"] as? String ?? "unknown")
        }
    }

    // MARK: - Internal helpers

    private func findItemId(boardId: String, employeeId: String,
                            weekStartDate: String, columnMap: ColumnMap,
                            token: String) async throws -> String {
        let query = """
        query($boardId: ID!) {
          boards(ids: [$boardId]) {
            items_page(limit: 500) {
              items {
                id
                column_values(ids: ["\(columnMap.employeeColumnId)", "\(columnMap.weekStartColumnId)"]) {
                  id text value
                }
              }
            }
          }
        }
        """
        let payload = try buildPayload(query: query, variables: ["boardId": boardId])
        let data = try await post(payload: payload, token: token)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errors = (json?["errors"] as? [[String: Any]]) ?? []
        if !errors.isEmpty {
            throw MondayError.apiError(errors.first?["message"] as? String ?? "unknown")
        }
        guard let items = ((((json?["data"] as? [String: Any])?["boards"] as? [[String: Any]])?.first)?["items_page"] as? [String: Any])?["items"] as? [[String: Any]]
        else { throw MondayError.apiError("Unexpected response shape") }

        for item in items {
            guard let id = item["id"] as? String,
                  let colVals = item["column_values"] as? [[String: Any]] else { continue }

            let empMatch = colVals.contains {
                $0["id"] as? String == columnMap.employeeColumnId &&
                $0["text"] as? String == employeeId
            }
            let weekMatch = colVals.contains {
                $0["id"] as? String == columnMap.weekStartColumnId &&
                (try? (JSONDecoder().decode([String: String].self,
                    from: Data(($0["value"] as? String ?? "").utf8)))["date"]) == weekStartDate
            }
            if empMatch && weekMatch { return id }
        }
        throw MondayError.noRowFound
    }

    func weekStartDate(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components)!
    }

    func weekStartDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: weekStartDate(for: date))
    }

    private func buildPayload(query: String, variables: [String: Any]) throws -> Data {
        let body: [String: Any] = ["query": query, "variables": variables]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func post(payload: Data, token: String) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.httpBody = payload
        let (data, _) = try await session.data(for: request)
        return data
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

⌘U. Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat: add MondayService — column discovery, check-in query+mutation"
```

---

## Task 6: AttendanceCoordinator

**Files:**
- Create: `OfficeAttendance/Coordinator/AttendanceCoordinator.swift`
- Test: `OfficeAttendanceTests/Coordinator/AttendanceCoordinatorTests.swift`

**Interfaces:**
- Consumes: `NetworkMonitor`, `MondayService`, `NotificationService` (stub for now), `CredentialStore`
- Produces:
  - `final class AttendanceCoordinator: ObservableObject`
  - `@Published var checkInState: CheckInState`
  - `func start()`
  - `func manualCheckIn(status: AttendanceStatus) async`

- [ ] **Step 1: Write failing test**

Create `OfficeAttendanceTests/Coordinator/AttendanceCoordinatorTests.swift`:

```swift
import XCTest
@testable import OfficeAttendance

final class AttendanceCoordinatorTests: XCTestCase {
    func test_isWeekend_returnsTrue_forSaturday() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        var components = DateComponents()
        components.year = 2025; components.month = 7; components.day = 19 // Saturday
        let saturday = Calendar.current.date(from: components)!
        XCTAssertTrue(coordinator.isWeekend(date: saturday))
    }

    func test_isWeekend_returnsFalse_forMonday() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        var components = DateComponents()
        components.year = 2025; components.month = 7; components.day = 14 // Monday
        let monday = Calendar.current.date(from: components)!
        XCTAssertFalse(coordinator.isWeekend(date: monday))
    }

    func test_alreadyCheckedIn_usesUserDefaults() {
        let coordinator = AttendanceCoordinator(
            credentialStore: CredentialStore(),
            networkMonitor: NetworkMonitor(),
            mondayService: MondayService()
        )
        let key = "attendance-2025-07-14"
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(coordinator.alreadyCheckedIn(for: key))
        UserDefaults.standard.set("Office", forKey: key)
        XCTAssertTrue(coordinator.alreadyCheckedIn(for: key))
        UserDefaults.standard.removeObject(forKey: key)
    }
}
```

- [ ] **Step 2: Run — verify it fails**

Expected: compile error "cannot find type AttendanceCoordinator".

- [ ] **Step 3: Implement AttendanceCoordinator**

Create `OfficeAttendance/Coordinator/AttendanceCoordinator.swift`:

```swift
import Foundation
import Combine

@MainActor
final class AttendanceCoordinator: ObservableObject {
    @Published private(set) var checkInState: CheckInState = .notCheckedIn

    private let credentialStore: CredentialStore
    private let networkMonitor: NetworkMonitor
    private let mondayService: MondayService
    private var cancellables = Set<AnyCancellable>()
    private var midnightTimer: Timer?

    init(credentialStore: CredentialStore,
         networkMonitor: NetworkMonitor,
         mondayService: MondayService) {
        self.credentialStore = credentialStore
        self.networkMonitor = networkMonitor
        self.mondayService = mondayService
    }

    func start() {
        guard let credentials = credentialStore.load() else {
            // No credentials — stay idle; SettingsWindow will be shown by AppDelegate
            return
        }
        networkMonitor.start(credentials: credentials)
        networkMonitor.$isOnOfficeNetwork
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOffice in
                self?.handleNetworkChange(isOnOfficeNetwork: isOffice, credentials: credentials)
            }
            .store(in: &cancellables)
        scheduleMidnightReset()
    }

    func manualCheckIn(status: AttendanceStatus) async {
        guard let credentials = credentialStore.load(),
              let columnMap = credentialStore.loadColumnMap() else { return }
        do {
            try await mondayService.checkIn(status: status, credentials: credentials,
                                            columnMap: columnMap)
            let key = todayKey()
            UserDefaults.standard.set(status.mondayValue, forKey: key)
            checkInState = .checkedIn(status)
        } catch {
            checkInState = .error(error.localizedDescription)
        }
    }

    // MARK: - Testable helpers

    func isWeekend(date: Date = Date()) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 || weekday == 7 // Sun or Sat
    }

    func alreadyCheckedIn(for key: String) -> Bool {
        UserDefaults.standard.string(forKey: key) != nil
    }

    func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "attendance-\(formatter.string(from: Date()))"
    }

    // MARK: - Private

    private func handleNetworkChange(isOnOfficeNetwork: Bool,
                                     credentials: CredentialStore.Credentials) {
        guard !isWeekend() else { return }
        let key = todayKey()
        guard !alreadyCheckedIn(for: key) else { return }
        guard let columnMap = credentialStore.loadColumnMap() else { return }

        let status: AttendanceStatus = isOnOfficeNetwork ? .office : .wfh
        Task {
            do {
                try await mondayService.checkIn(status: status, credentials: credentials,
                                                columnMap: columnMap)
                UserDefaults.standard.set(status.mondayValue, forKey: key)
                checkInState = .checkedIn(status)
                // Notification posted in Task 7
            } catch {
                checkInState = .error(error.localizedDescription)
            }
        }
    }

    private func scheduleMidnightReset() {
        midnightTimer?.invalidate()
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
              let midnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: tomorrow)
        else { return }
        midnightTimer = Timer(fire: midnight, interval: 86400, repeats: true) { [weak self] _ in
            self?.checkInState = .notCheckedIn
        }
        RunLoop.main.add(midnightTimer!, forMode: .common)
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

⌘U. Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat: add AttendanceCoordinator — orchestration, idempotency, midnight reset"
```

---

## Task 7: NotificationService + wire coordinator

**Files:**
- Create: `OfficeAttendance/Services/NotificationService.swift`
- Modify: `OfficeAttendance/Coordinator/AttendanceCoordinator.swift` — add notification calls

**Interfaces:**
- Produces:
  - `final class NotificationService`
  - `func requestPermission()`
  - `func sendCheckInNotification(status: AttendanceStatus)`
  - `func sendChangeConfirmation(status: AttendanceStatus)`
  - `func sendSetupReminder()`
  - Notification category IDs: `"CHECKIN"` (actions: `"CHANGE"`, `"OK"`), `"SETUP"` (action: `"OPEN_SETTINGS"`)

- [ ] **Step 1: Implement NotificationService**

Create `OfficeAttendance/Services/NotificationService.swift`:

```swift
import UserNotifications
import AppKit

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendCheckInNotification(status: AttendanceStatus) {
        let content = UNMutableNotificationContent()
        content.title = "\(status.icon) Attendance logged: \(status.menuLabel)"
        content.body = formattedToday()
        content.categoryIdentifier = "CHECKIN"
        content.sound = .default
        schedule(content: content, id: "checkin-\(formattedToday())")
    }

    func sendChangeConfirmation(status: AttendanceStatus) {
        let content = UNMutableNotificationContent()
        content.title = "✅ Changed to: \(status.menuLabel)"
        content.body = formattedToday()
        content.sound = .default
        schedule(content: content, id: "change-\(UUID().uuidString)")
    }

    func sendSetupReminder() {
        let content = UNMutableNotificationContent()
        content.title = "⚙️ Office Attendance — Setup required"
        content.body = "Tap to open Settings"
        content.categoryIdentifier = "SETUP"
        schedule(content: content, id: "setup-reminder")
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 didReceive response: UNNotificationResponse,
                                 withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "CHANGE", UNNotificationDefaultActionIdentifier:
            if response.notification.request.content.categoryIdentifier == "CHECKIN" {
                NotificationCenter.default.post(name: .openMenuBarDropdown, object: nil)
            } else if response.notification.request.content.categoryIdentifier == "SETUP" {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
        default: break
        }
        completionHandler()
    }

    // MARK: - Private

    private func registerCategories() {
        let changeAction = UNNotificationAction(identifier: "CHANGE",
                                               title: "Change", options: [.foreground])
        let okAction = UNNotificationAction(identifier: "OK", title: "OK", options: [])
        let checkinCategory = UNNotificationCategory(identifier: "CHECKIN",
                                                     actions: [changeAction, okAction],
                                                     intentIdentifiers: [])
        let openAction = UNNotificationAction(identifier: "OPEN_SETTINGS",
                                              title: "Open Settings", options: [.foreground])
        let setupCategory = UNNotificationCategory(identifier: "SETUP",
                                                   actions: [openAction],
                                                   intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([checkinCategory, setupCategory])
    }

    private func schedule(content: UNMutableNotificationContent, id: String) {
        let request = UNNotificationRequest(identifier: id,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func formattedToday() -> String {
        let f = DateFormatter()
        f.dateStyle = .full; f.timeStyle = .none
        return f.string(from: Date())
    }
}

extension Notification.Name {
    static let openMenuBarDropdown = Notification.Name("openMenuBarDropdown")
    static let openSettings        = Notification.Name("openSettings")
}
```

- [ ] **Step 2: Wire notifications into AttendanceCoordinator**

In `AttendanceCoordinator.swift`, in `handleNetworkChange` after `checkInState = .checkedIn(status)`:

```swift
NotificationService.shared.sendCheckInNotification(status: status)
```

In `manualCheckIn` after `checkInState = .checkedIn(status)`:

```swift
NotificationService.shared.sendChangeConfirmation(status: status)
```

In `start()` when credentials are nil:

```swift
NotificationService.shared.sendSetupReminder()
```

- [ ] **Step 3: Build — verify no compile errors**

⌘B. Expected: Build Succeeded.

- [ ] **Step 4: Commit**

```bash
git add .
git commit -m "feat: add NotificationService, wire check-in and setup notifications"
```

---

## Task 8: Settings UI

**Files:**
- Create: `OfficeAttendance/UI/SettingsView.swift`
- Create: `OfficeAttendance/UI/SettingsWindowController.swift`
- Modify: `OfficeAttendance/App/AppDelegate.swift` — wire `openSettings`

**Interfaces:**
- Consumes: `CredentialStore`, `MondayService`
- Produces: `SettingsWindowController` with `func show()`

- [ ] **Step 1: Implement SettingsView**

Create `OfficeAttendance/UI/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var credentialStore: CredentialStore
    let mondayService: MondayService
    var onSave: (() -> Void)?

    @State private var token = ""
    @State private var boardId = ""
    @State private var employeeId = ""
    @State private var ipPrefix = "9."
    @State private var dnsDomain = "ibm.com"
    @State private var verifyStatus: VerifyStatus = .idle
    @State private var showAdvanced = false
    @State private var columnMap: ColumnMap? = nil

    // Advanced manual overrides
    @State private var manualEmployeeCol = ""
    @State private var manualWeekStartCol = ""
    @State private var manualMon = ""
    @State private var manualTue = ""
    @State private var manualWed = ""
    @State private var manualThu = ""
    @State private var manualFri = ""

    enum VerifyStatus {
        case idle, loading, success(ColumnMap), failure(String)
    }

    var canSave: Bool {
        switch verifyStatus {
        case .success: return true
        default: return false
        }
    }

    var body: some View {
        Form {
            Section("Monday.com") {
                SecureField("API Token", text: $token)
                TextField("Board ID", text: $boardId)
                TextField("Employee ID (name as shown on board)", text: $employeeId)
            }

            Section("Network Detection") {
                TextField("Office IP Prefix (e.g. 9.)", text: $ipPrefix)
                TextField("Office DNS Domain (e.g. ibm.com)", text: $dnsDomain)
            }

            Section("Board Verification") {
                Button("Verify Board") { Task { await verifyBoard() } }
                    .disabled(token.isEmpty || boardId.isEmpty)
                switch verifyStatus {
                case .idle: EmptyView()
                case .loading: ProgressView("Checking…")
                case .success(let map):
                    Text("✅ Monday(\(map.mondayColumnId)) Tue(\(map.tuesdayColumnId)) Wed(\(map.wednesdayColumnId)) Thu(\(map.thursdayColumnId)) Fri(\(map.fridayColumnId))")
                        .font(.caption).foregroundColor(.secondary)
                case .failure(let msg):
                    Text("❌ \(msg)").font(.caption).foregroundColor(.red)
                }

                DisclosureGroup("Advanced (manual column IDs)", isExpanded: $showAdvanced) {
                    TextField("Employee name column ID", text: $manualEmployeeCol)
                    TextField("Week Start column ID", text: $manualWeekStartCol)
                    TextField("Monday column ID", text: $manualMon)
                    TextField("Tuesday column ID", text: $manualTue)
                    TextField("Wednesday column ID", text: $manualWed)
                    TextField("Thursday column ID", text: $manualThu)
                    TextField("Friday column ID", text: $manualFri)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { NSApp.keyWindow?.close() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveCredentials() }
                    .disabled(!canSave)
            }
        }
        .onAppear { loadExisting() }
    }

    private func verifyBoard() async {
        verifyStatus = .loading
        do {
            let map = try await mondayService.discoverColumns(boardId: boardId, token: token)
            columnMap = map
            // Pre-fill advanced fields
            manualEmployeeCol = map.employeeColumnId
            manualWeekStartCol = map.weekStartColumnId
            manualMon = map.mondayColumnId
            manualTue = map.tuesdayColumnId
            manualWed = map.wednesdayColumnId
            manualThu = map.thursdayColumnId
            manualFri = map.fridayColumnId
            verifyStatus = .success(map)
        } catch {
            verifyStatus = .failure(error.localizedDescription)
        }
    }

    private func saveCredentials() {
        guard case .success(var map) = verifyStatus else { return }
        // Apply manual overrides if advanced fields were edited
        if showAdvanced {
            map = ColumnMap(employeeColumnId: manualEmployeeCol.isEmpty ? map.employeeColumnId : manualEmployeeCol,
                            weekStartColumnId: manualWeekStartCol.isEmpty ? map.weekStartColumnId : manualWeekStartCol,
                            mondayColumnId: manualMon.isEmpty ? map.mondayColumnId : manualMon,
                            tuesdayColumnId: manualTue.isEmpty ? map.tuesdayColumnId : manualTue,
                            wednesdayColumnId: manualWed.isEmpty ? map.wednesdayColumnId : manualWed,
                            thursdayColumnId: manualThu.isEmpty ? map.thursdayColumnId : manualThu,
                            fridayColumnId: manualFri.isEmpty ? map.fridayColumnId : manualFri)
        }
        try? credentialStore.save(token: token, boardId: boardId, employeeId: employeeId,
                                  ipPrefix: ipPrefix, dnsDomain: dnsDomain)
        credentialStore.saveColumnMap(map)
        NSApp.keyWindow?.close()
        onSave?()
    }

    private func loadExisting() {
        guard let creds = credentialStore.load() else { return }
        token = creds.token
        boardId = creds.boardId
        employeeId = creds.employeeId
        ipPrefix = creds.ipPrefix
        dnsDomain = creds.dnsDomain
    }
}
```

- [ ] **Step 2: Implement SettingsWindowController**

Create `OfficeAttendance/UI/SettingsWindowController.swift`:

```swift
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
```

- [ ] **Step 3: Wire into AppDelegate**

In `AppDelegate.swift`, add properties and update `applicationDidFinishLaunching`:

```swift
private var settingsWindowController: SettingsWindowController?
private var credentialStore = CredentialStore()
private var mondayService = MondayService()
private var coordinator: AttendanceCoordinator?

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
    coordinator?.start()

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

@objc private func openSettings() {
    settingsWindowController?.show()
}

private func restartCoordinator() {
    coordinator?.start()
}
```

- [ ] **Step 4: Build and manually test settings window**

⌘R. Click Menu Bar → Settings… — confirm the settings window opens, Verify Board button works with real credentials, Save saves to Keychain.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat: add SettingsView and SettingsWindowController, wire AppDelegate"
```

---

## Task 9: Menu Bar Dropdown UI

**Files:**
- Create: `OfficeAttendance/UI/MenuBarView.swift`
- Modify: `OfficeAttendance/App/AppDelegate.swift` — replace stub menu with live menu

**Interfaces:**
- Consumes: `AttendanceCoordinator.checkInState`, `AttendanceStatus`

- [ ] **Step 1: Implement live menu construction**

In `AppDelegate.swift`, replace `buildMenu()` with one that reads coordinator state:

```swift
private func buildMenu() -> NSMenu {
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
```

Rebuild the menu whenever `coordinator.$checkInState` changes. Add to `applicationDidFinishLaunching`:

```swift
coordinator?.$checkInState
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in
        self?.statusItem?.menu = self?.buildMenu()
    }
    .store(in: &cancellables)
```

Add `private var cancellables = Set<AnyCancellable>()` to `AppDelegate` and `import Combine`.

- [ ] **Step 2: Build and manually test dropdown**

⌘R. Confirm:
- Before check-in: `🏢?`, dropdown shows "Set: Office / WFH / Sick…"
- After manual check-in: icon updates to `🏢 Office`, dropdown shows "Change to: WFH / Sick…"

- [ ] **Step 3: Commit**

```bash
git add .
git commit -m "feat: live menu bar dropdown reflecting check-in state"
```

---

## Task 10: Logger

**Files:**
- Create: `OfficeAttendance/Utilities/Logger.swift`
- Modify: `MondayService.swift`, `AttendanceCoordinator.swift` — replace `print` with `AppLogger`

- [ ] **Step 1: Implement rotating logger**

Create `OfficeAttendance/Utilities/Logger.swift`:

```swift
import Foundation

final class AppLogger {
    static let shared = AppLogger()
    private let maxSize: Int = 1_048_576 // 1 MB
    private let maxFiles = 3
    private let logURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("com.ibm.office-attendance", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("attendance.log")
    }()

    private init() {}

    func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        rotate()
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try? FileHandle(forWritingTo: logURL)
                handle?.seekToEndOfFile()
                handle?.write(data)
                handle?.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    private func rotate() {
        guard let size = try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > maxSize else { return }
        let dir = logURL.deletingLastPathComponent()
        // Shift old logs
        for i in stride(from: maxFiles - 1, through: 1, by: -1) {
            let old = dir.appendingPathComponent("attendance.\(i).log")
            let new = dir.appendingPathComponent("attendance.\(i + 1).log")
            try? FileManager.default.removeItem(at: new)
            try? FileManager.default.moveItem(at: old, to: new)
        }
        let first = dir.appendingPathComponent("attendance.1.log")
        try? FileManager.default.moveItem(at: logURL, to: first)
    }
}
```

- [ ] **Step 2: Add error logging in catch blocks**

In `AttendanceCoordinator.swift`, in `handleNetworkChange`, update the catch block:

```swift
} catch {
    AppLogger.shared.log("Check-in failed: \(error.localizedDescription)")
    checkInState = .error(error.localizedDescription)
}
```

In `AttendanceCoordinator.swift`, in `manualCheckIn`, update the catch block:

```swift
} catch {
    AppLogger.shared.log("Manual check-in failed: \(error.localizedDescription)")
    checkInState = .error(error.localizedDescription)
}
```

- [ ] **Step 3: Build — verify no compile errors**

⌘B.

- [ ] **Step 4: Commit**

```bash
git add .
git commit -m "feat: add rotating AppLogger (1 MB × 3 files)"
```

---

## Task 11: Sparkle Auto-Update

**Files:**
- Modify: `OfficeAttendance.xcodeproj` — add Sparkle via Swift Package Manager
- Create: `appcast.xml` in repo root

- [ ] **Step 1: Add Sparkle via SPM**

In Xcode: File → Add Package Dependencies.
URL: `https://github.com/sparkle-project/Sparkle`
Version: `2.x.x` (latest stable 2.x)
Add `Sparkle` library to the `OfficeAttendance` target.

- [ ] **Step 2: Configure Sparkle in AppDelegate**

Add to `AppDelegate.swift`:

```swift
import Sparkle

private var updaterController: SPUStandardUpdaterController?

// In applicationDidFinishLaunching, after other setup:
updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
)
```

Add to `Info.plist`:
```xml
<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/YOUR_ORG/office-attendance-wifi/main/appcast.xml</string>
<key>SUEnableAutomaticChecks</key>
<true/>
```

Replace `YOUR_ORG` with your actual GitHub org/user.

- [ ] **Step 3: Create placeholder appcast.xml**

Create `appcast.xml` in the repo root:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Office Attendance Updates</title>
    <item>
      <title>Version 1.0.0</title>
      <sparkle:version>1</sparkle:version>
      <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
      <pubDate>Tue, 15 Jul 2025 00:00:00 +0000</pubDate>
      <enclosure url="https://github.com/YOUR_ORG/office-attendance-wifi/releases/download/v1.0.0/OfficeAttendance.dmg"
                 sparkle:edSignature="PLACEHOLDER"
                 length="0"
                 type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

- [ ] **Step 4: Build — verify Sparkle links correctly**

⌘B. Expected: Build Succeeded with no linker errors.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat: integrate Sparkle 2.x for auto-update, add appcast.xml placeholder"
```

---

## Task 12: Signing, Notarization & DMG

This task is performed manually at release time. Document the steps here for repeatability.

- [ ] **Step 1: Configure signing in Xcode**

Target → Signing & Capabilities:
- Team: your Apple Developer account
- Signing Certificate: Developer ID Application
- Bundle Identifier: `com.ibm.office-attendance`

- [ ] **Step 2: Add entitlements**

Create `OfficeAttendance.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.ibm.office-attendance</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 3: Archive and export**

Product → Archive → Distribute App → Developer ID → Export.

- [ ] **Step 4: Notarize**

```bash
xcrun notarytool submit OfficeAttendance.dmg \
  --apple-id YOUR_APPLE_ID \
  --team-id YOUR_TEAM_ID \
  --password APP_SPECIFIC_PASSWORD \
  --wait
xcrun stapler staple OfficeAttendance.dmg
```

- [ ] **Step 5: Update appcast.xml with real signature**

```bash
# Generate EdDSA signature (Sparkle provides sign_update tool)
./Sparkle/bin/sign_update OfficeAttendance.dmg
# Copy the output signature into appcast.xml enclosure sparkle:edSignature
```

- [ ] **Step 6: Create GitHub Release**

Tag `v1.0.0`, upload `OfficeAttendance.dmg`, commit updated `appcast.xml`.

```bash
git add appcast.xml
git commit -m "release: v1.0.0 appcast"
git tag v1.0.0
git push origin main --tags
```
