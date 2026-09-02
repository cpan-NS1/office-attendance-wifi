# History: Fetch from Monday.com (Option A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the History window opens, fetch the current month's attendance data directly from the Monday.com board and merge it with locally stored values so the calendar reflects statuses set on the website too.

**Architecture:** Add a `fetchMonthStatus` method to `MondayService` that queries all week-rows covering a given month, reads the Mon–Fri column values, and returns a `[String: AttendanceStatus]` keyed by ISO date. `HistoryView` receives `MondayService` + `CredentialStore.Credentials`, calls the fetch on `.onAppear` and on month navigation, then merges remote results over local `UserDefaults` data. `HistoryWindowController` and `HistoryView` signatures are updated to accept the new dependencies.

**Tech Stack:** Swift, SwiftUI, existing `MondayService` / `CredentialStore` / `ColumnMap` types

**Spec:** n/a (feature discussed in conversation)

## Global Constraints

- Remote data wins over local `UserDefaults` data for the same date key.
- Fetch is read-only — never writes to `UserDefaults` or the Monday.com board.
- Fetch is fire-and-forget with a visible loading state; errors show a non-blocking inline message, they do not block the calendar.
- Only weekdays (Mon–Fri) are fetched; weekends have no column on the board.
- The existing `findItemId` and `checkIn` methods must not be modified.
- No new dependencies — use only Foundation, SwiftUI, and existing project types.

---

### Task 1: Add `fetchMonthStatus` to `MondayService`

**Files:**
- Modify: `macOS-app/OfficeAttendance/Services/MondayService.swift`

**Interfaces:**
- Produces: `func fetchMonthStatus(boardId: String, employeeId: String, columnMap: ColumnMap, token: String, month: Date) async throws -> [String: AttendanceStatus]`
  - Returns a dictionary keyed by `"yyyy-MM-dd"` ISO date strings.
  - Covers every Monday-start week that overlaps the given `month`.

**Background — how the board is structured:**
Each row on the board represents one person's one week. The row has:
- An employee column (`columnMap.employeeColumnId`) containing the employee's ID as text.
- A week-start column (`columnMap.weekStartColumnId`) whose JSON `value` is `{"date":"yyyy-MM-dd"}`.
- Five day columns (`columnMap.mondayColumnId` … `columnMap.fridayColumnId`) whose `text` values are one of `"Office"`, `"WFH"`, `"Sick"`, `"Vacation"`, `"Holiday"` (or empty/absent).

**What this task does:**
1. Compute all Monday dates for weeks that overlap the given `month`.
2. For each week start date, attempt to find the matching row via `findItemId` and then read its day columns.
3. Map each non-empty day column text to an `AttendanceStatus` using `AttendanceStatus.allCases.first { $0.mondayValue == text }`.
4. Build the output dict: key = the ISO date for that weekday (Mon=weekStart+0, Tue=+1, …, Fri=+4).

**Implementation note — fetching column values:**
After you have the `itemId`, use this query to read the five day columns in one API call:

```graphql
query($boardId: ID!, $itemId: ID!) {
  boards(ids: [$boardId]) {
    items_page(limit: 1, ids: [$itemId]) {
      items {
        column_values(ids: ["<mon>","<tue>","<wed>","<thu>","<fri>"]) {
          id text
        }
      }
    }
  }
}
```

However, the Monday.com v2 API does not support filtering `items_page` by `ids`. Use the simpler item query instead:

```graphql
query($itemId: ID!) {
  items(ids: [$itemId]) {
    column_values(ids: ["<mon>","<tue>","<wed>","<thu>","<fri>"]) {
      id text
    }
  }
}
```

- [ ] **Step 1: Add a private `fetchWeekDayValues` helper to `MondayService`**

Add this private method inside the `MondayService` class (before the existing `buildPayload` helper):

```swift
/// Fetches the five day-column text values for a known itemId.
/// Returns a dict of columnId -> text (only non-empty values are included).
private func fetchWeekDayValues(itemId: String,
                                 columnMap: ColumnMap,
                                 token: String) async throws -> [String: String] {
    let colIds = [columnMap.mondayColumnId, columnMap.tuesdayColumnId,
                  columnMap.wednesdayColumnId, columnMap.thursdayColumnId,
                  columnMap.fridayColumnId]
    let idsLiteral = colIds.map { "\"\($0)\"" }.joined(separator: ",")
    let query = """
    query($itemId: ID!) {
      items(ids: [$itemId]) {
        column_values(ids: [\(idsLiteral)]) {
          id text
        }
      }
    }
    """
    let payload = try buildPayload(query: query, variables: ["itemId": itemId])
    let data = try await post(payload: payload, token: token)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let errors = (json?["errors"] as? [[String: Any]]) ?? []
    if !errors.isEmpty {
        throw MondayError.apiError(errors.first?["message"] as? String ?? "unknown")
    }
    guard let items = (json?["data"] as? [String: Any])?["items"] as? [[String: Any]],
          let colVals = items.first?["column_values"] as? [[String: Any]]
    else { throw MondayError.apiError("Unexpected response shape from items query") }

    var result: [String: String] = [:]
    for cv in colVals {
        guard let id = cv["id"] as? String,
              let text = cv["text"] as? String,
              !text.isEmpty else { continue }
        result[id] = text
    }
    return result
}
```

- [ ] **Step 2: Add the public `fetchMonthStatus` method to `MondayService`**

Add this public method inside the `MondayService` class (after `checkIn`, before `// MARK: - Internal helpers`):

```swift
// MARK: - History fetch

/// Fetches all attendance statuses for the employee for the given month.
/// Returns a dictionary keyed by "yyyy-MM-dd" ISO date strings.
/// Weeks with no board row are silently skipped.
func fetchMonthStatus(boardId: String,
                      employeeId: String,
                      columnMap: ColumnMap,
                      token: String,
                      month: Date) async throws -> [String: AttendanceStatus] {
    let weekStarts = weekStartDates(overlapping: month)
    var result: [String: AttendanceStatus] = [:]

    for weekStart in weekStarts {
        let weekStartStr = weekStartDateString(for: weekStart)

        // Find the row for this week; skip if not found
        guard let itemId = try? await findItemId(
            boardId: boardId,
            employeeId: employeeId,
            weekStartDate: weekStartStr,
            columnMap: columnMap,
            token: token
        ) else { continue }

        let dayValues = try await fetchWeekDayValues(
            itemId: itemId,
            columnMap: columnMap,
            token: token
        )

        let colIds = [
            (columnMap.mondayColumnId,    0),
            (columnMap.tuesdayColumnId,   1),
            (columnMap.wednesdayColumnId, 2),
            (columnMap.thursdayColumnId,  3),
            (columnMap.fridayColumnId,    4)
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")

        for (colId, dayOffset) in colIds {
            guard let text = dayValues[colId],
                  let status = AttendanceStatus.allCases.first(where: { $0.mondayValue == text }),
                  let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
            else { continue }
            result[isoFormatter.string(from: dayDate)] = status
        }
    }

    return result
}

/// Returns every Monday date for weeks that overlap the given month.
private func weekStartDates(overlapping month: Date) -> [Date] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2 // Monday
    let comps = calendar.dateComponents([.year, .month], from: month)
    guard let monthStart = calendar.date(from: comps),
          let monthRange = calendar.range(of: .day, in: .month, for: monthStart)
    else { return [] }
    let monthEnd = calendar.date(byAdding: .day, value: monthRange.count - 1, to: monthStart)!

    var starts: [Date] = []
    var current = weekStartDate(for: monthStart)
    while current <= monthEnd {
        starts.append(current)
        current = calendar.date(byAdding: .weekOfYear, value: 1, to: current)!
    }
    return starts
}
```

- [ ] **Step 3: Build the project to confirm no compile errors**

Open the Xcode project at `macOS-app/OfficeAttendance.xcodeproj` and build (⌘B). Expected: build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
cd macOS-app
git add OfficeAttendance/Services/MondayService.swift
git commit -m "feat: add fetchMonthStatus to MondayService"
```

---

### Task 2: Wire `MondayService` and credentials into `HistoryView`

**Files:**
- Modify: `macOS-app/OfficeAttendance/UI/HistoryView.swift`
- Modify: `macOS-app/OfficeAttendance/UI/HistoryWindowController.swift`

**Interfaces:**
- Consumes: `MondayService.fetchMonthStatus(boardId:employeeId:columnMap:token:month:) async throws -> [String: AttendanceStatus]` (from Task 1)
- `CredentialStore.Credentials` struct (fields: `token`, `boardId`, `employeeId`)
- `CredentialStore.loadColumnMap() -> ColumnMap?`

**What this task does:**

`HistoryView` currently takes `credentialStore: CredentialStore` and `boardId: String`. Extend it to:
1. Accept `mondayService: MondayService` and `credentials: CredentialStore.Credentials?` as new init parameters.
2. Add `@State private var remoteEntries: [String: AttendanceStatus] = [:]` and `@State private var fetchError: String? = nil` and `@State private var isFetching = false`.
3. Compute `entryMap` by merging local + remote (remote wins):
   ```swift
   private var entryMap: [String: AttendanceStatus] {
       var map = Dictionary(uniqueKeysWithValues: entries.map { ($0.date, $0.status) })
       for (k, v) in remoteEntries { map[k] = v }
       return map
   }
   ```
4. Call `fetchRemote()` on `.onAppear` and whenever `displayedMonth` changes (use `.onChange(of: displayedMonth)`).
5. Show a `ProgressView` spinner in the header area while `isFetching` is true, and an inline error text below the header when `fetchError` is set.

**`fetchRemote()` method to add:**

```swift
private func fetchRemote() {
    guard let credentials,
          let columnMap = credentialStore.loadColumnMap() else { return }
    isFetching = true
    fetchError = nil
    Task {
        do {
            let remote = try await mondayService.fetchMonthStatus(
                boardId: credentials.boardId,
                employeeId: credentials.employeeId,
                columnMap: columnMap,
                token: credentials.token,
                month: displayedMonth
            )
            await MainActor.run {
                remoteEntries = remote
                isFetching = false
            }
        } catch {
            await MainActor.run {
                fetchError = error.localizedDescription
                isFetching = false
            }
        }
    }
}
```

**Header changes — add spinner and error below the existing HStack:**

Replace the header section (`// ── Header ───`) so it looks like this:

```swift
// ── Header ────────────────────────────────────────────────────
HStack(spacing: 8) {
    Button { changeMonth(by: -1) } label: {
        Image(systemName: "chevron.left")
    }
    .buttonStyle(.plain)

    Text(monthFormatter.string(from: displayedMonth))
        .font(.headline)
        .frame(minWidth: 140)

    Button { changeMonth(by: 1) } label: {
        Image(systemName: "chevron.right")
    }
    .buttonStyle(.plain)

    if isFetching {
        ProgressView()
            .scaleEffect(0.6)
            .frame(width: 16, height: 16)
    }

    Spacer()

    if let url = boardURL {
        Link("Open Board ↗", destination: url)
            .font(.subheadline)
    }
}
.padding(.horizontal, 20)
.padding(.top, 16)
.padding(.bottom, fetchError != nil ? 4 : 12)

if let fetchError {
    Text("⚠️ \(fetchError)")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
}
```

**`.onAppear` and `.onChange` — replace the existing `.onAppear` at the bottom of `body`:**

```swift
.onAppear {
    entries = credentialStore.loadHistory()
    fetchRemote()
}
.onChange(of: displayedMonth) { _ in
    fetchRemote()
}
```

**Updated `HistoryView` init signature:**

```swift
struct HistoryView: View {
    let credentialStore: CredentialStore
    let mondayService: MondayService
    let credentials: CredentialStore.Credentials?
    let boardId: String
    // ... (all existing @State vars remain unchanged)
```

**`HistoryWindowController.show()` — pass the new dependencies:**

```swift
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
```

`HistoryWindowController` currently only holds `credentialStore`. Add `mondayService: MondayService` to its stored properties and `init`:

```swift
final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    private let credentialStore: CredentialStore
    private let mondayService: MondayService

    init(credentialStore: CredentialStore, mondayService: MondayService) {
        self.credentialStore = credentialStore
        self.mondayService = mondayService
        // ... rest of init unchanged
    }
```

Check `AppDelegate.swift` — it creates `HistoryWindowController`. Update that call site to also pass `mondayService`.

- [ ] **Step 1: Update `HistoryView` — add new stored properties and state**

In [`HistoryView.swift`](macOS-app/OfficeAttendance/UI/HistoryView.swift), add `mondayService` and `credentials` to the struct's stored properties (after `let boardId: String`), and add the three new `@State` vars (`remoteEntries`, `fetchError`, `isFetching`) after the existing `@State private var displayedMonth`.

- [ ] **Step 2: Update `entryMap` in `HistoryView`**

Replace the existing `entryMap` computed property:

```swift
private var entryMap: [String: AttendanceStatus] {
    var map = Dictionary(uniqueKeysWithValues: entries.map { ($0.date, $0.status) })
    for (k, v) in remoteEntries { map[k] = v }
    return map
}
```

- [ ] **Step 3: Add `fetchRemote()` to `HistoryView`**

Add the `fetchRemote()` method (shown above) inside the `HistoryView` struct, after `changeMonth(by:)`.

- [ ] **Step 4: Update the header in `HistoryView.body`**

Replace the `// ── Header ───` section with the updated version shown above (adds spinner next to month title, and the conditional error text below the HStack).

- [ ] **Step 5: Update `.onAppear` and add `.onChange` in `HistoryView`**

Replace the existing `.onAppear { entries = credentialStore.loadHistory() }` with the two-modifier version shown above.

- [ ] **Step 6: Update `HistoryWindowController`**

Add `mondayService: MondayService` to stored properties and `init`, update `show()` to pass all four args to `HistoryView`.

- [ ] **Step 7: Update `AppDelegate.swift` call site**

Find where `HistoryWindowController(credentialStore:)` is called and add `mondayService:` argument. The `MondayService` instance is already available in `AppDelegate` (it's used by `AttendanceCoordinator`). Pass the same instance.

- [ ] **Step 8: Build the project (⌘B)**

Expected: build succeeds with no errors or warnings.

- [ ] **Step 9: Commit**

```bash
cd macOS-app
git add OfficeAttendance/UI/HistoryView.swift \
        OfficeAttendance/UI/HistoryWindowController.swift \
        OfficeAttendance/App/AppDelegate.swift
git commit -m "feat: fetch month attendance from Monday.com in history view"
```

---

### Task 3: Manual smoke test

No automated tests exist for SwiftUI views in this project. Verify manually:

- [ ] **Step 1: Launch the app**

Build & run in Xcode with a valid set of credentials already configured.

- [ ] **Step 2: Open History**

Click the menu bar icon → History. The calendar should open. A small spinner appears next to the month title while fetching, then disappears.

- [ ] **Step 3: Verify remote data appears**

On ibm.monday.com, confirm there is at least one day this month set to a status. That day should now show the correct icon in the calendar even if it was never checked in via the app.

- [ ] **Step 4: Navigate to a previous month**

Click the `<` chevron. A new fetch should trigger (spinner reappears). Statuses for that month should populate.

- [ ] **Step 5: Verify local-only days still appear**

Any day that was checked in only via the app (i.e. exists in `UserDefaults` but not on the board — e.g. if the board row was deleted) should still show up. This confirms the merge logic is additive.

- [ ] **Step 6: Verify error path**

Temporarily break the token in Settings (add a character). Open History. The spinner should appear, then disappear, and a small `⚠️` error caption should appear below the header. The calendar grid should still render with local data.
