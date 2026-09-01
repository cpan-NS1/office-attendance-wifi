# macOS Office Attendance App — Design Spec

**Date:** 2025-07-15  
**Status:** Approved for implementation  
**Replaces:** SwiftBar shell plugin (`check-office-attendance.1h.zsh`)

---

## 1. Overview

A native macOS Menu Bar application that automatically logs daily office attendance on Monday.com. When the user connects to the office Wi-Fi, the app detects the network change, submits attendance as **Office**, and posts a system notification. If the user is on any other network, attendance is submitted as **WFH**. The user can correct the status at any time via the notification action button or the Menu Bar dropdown.

The app is distributed as a signed, notarized `.dmg` on GitHub Releases. Each user configures their own credentials on first launch.

---

## 2. Architecture

The app has no main window. It runs as a Login Item and lives entirely in the Menu Bar.

```
┌─────────────────────────────────────────────────┐
│  UI Layer                                        │
│  MenuBarView · StatusDropdown · SettingsWindow  │
├─────────────────────────────────────────────────┤
│  App Logic Layer                                 │
│  AttendanceCoordinator                          │
├─────────────────────────────────────────────────┤
│  Service Layer                                   │
│  NetworkMonitor · MondayService                 │
│  NotificationService · CredentialStore          │
├─────────────────────────────────────────────────┤
│  Persistence                                     │
│  Keychain (credentials) · UserDefaults (state)  │
└─────────────────────────────────────────────────┘
```

**Data flow:** `NetworkMonitor` emits path-change events → `AttendanceCoordinator` evaluates whether to act → calls `MondayService` → calls `NotificationService` → publishes updated state to UI layer via `@Published` properties. The UI layer reads state only; it never calls services directly.

---

## 3. Network Detection

`NetworkMonitor` wraps `NWPathMonitor` and runs on a dedicated background queue. On every path update it evaluates two conditions (matching the existing shell plugin logic):

- Current IPv4 address on `en0` starts with `OFFICE_IP_PREFIX` (e.g. `9.`)
- DNS search domain contains `OFFICE_DNS_DOMAIN` (e.g. `ibm.com`)

Either condition matching sets `isOnOfficeNetwork = true`.

IP is read via `getifaddrs` (no entitlement required). DNS search domain is read via `SCDynamicStoreCopyDHCPInfo` or `res_ninit`. Both are available without special entitlements on macOS.

---

## 4. Attendance Coordinator

`AttendanceCoordinator` is the single orchestration point. It subscribes to `NetworkMonitor` and applies the following decision tree on every network change event:

```
Network change received
  ├─ Weekend (Saturday / Sunday)? → skip
  ├─ Credentials not configured?  → send setup-reminder notification; skip
  ├─ Already checked in today?    → skip (idempotent)
  └─ Weekday, credentials present, not yet checked in
       ├─ isOnOfficeNetwork = true  → submit "Office"
       └─ isOnOfficeNetwork = false → submit "WFH"
            (no network / unknown network also → WFH)
```

After a successful submission the result is written to `UserDefaults` under the key `attendance-YYYY-MM-DD`. A midnight `Timer` clears the current-day entry so the next day starts fresh.

---

## 5. Monday.com Integration

### 5.1 Column Discovery (Board Introspection)

Because different boards have different column IDs, the app does not hard-code column IDs. On first save of credentials (and whenever the user clicks **Verify Board**), `MondayService` queries the board's column list and matches by title:

| Expected title | Maps to |
|----------------|---------|
| `Monday`       | `mondayColumnId` |
| `Tuesday`      | `tuesdayColumnId` |
| `Wednesday`    | `wednesdayColumnId` |
| `Thursday`     | `thursdayColumnId` |
| `Friday`       | `fridayColumnId` |
| `Employee name` (text column) | `employeeColumnId` |
| `Week Start` (date column) | `weekStartColumnId` |

The resolved mapping is stored in `UserDefaults` (not Keychain — not sensitive). If automatic title matching fails for any day column, the Settings window exposes an **Advanced** section where the user can enter column IDs manually.

### 5.2 Check-in Flow

Two sequential API calls, matching the existing shell plugin logic:

1. **Query** — fetch all items on the board, filter by `employeeColumnId == EMPLOYEE_ID` and `weekStartColumnId == thisWeekMonday`, return `item_id`.
2. **Mutation** — call `change_simple_column_value` with `item_id`, the weekday's `columnId`, and the status string (`Office`, `WFH`, `Sick`, `Vacation`, `Holiday`).

All requests use `URLSession` with a 30-second timeout. On failure: log to a rotating log file (max 1 MB, 3 rotations), show an error note in the Menu Bar dropdown. No error notification is posted to avoid interrupting the user.

### 5.3 Status Values

`Office` · `WFH` · `Sick` · `Vacation` · `Holiday`

These are the values written directly to Monday.com as status strings, matching the board's label configuration.

---

## 6. Credential Storage

All credentials are stored in the macOS Keychain under service name `com.ibm.office-attendance`.

| Field | Key | Default |
|-------|-----|---------|
| Monday API Token | `monday-token` | — (required) |
| Board ID | `board-id` | — (required) |
| Employee ID | `employee-id` | — (required) |
| Office IP Prefix | `office-ip-prefix` | `9.` |
| Office DNS Domain | `office-dns-domain` | `ibm.com` |

Column ID mappings (non-sensitive) are stored in `UserDefaults`.

---

## 7. Settings Window

A standard macOS window (`NSPanel`) opened from Menu Bar → **Settings…** or automatically on first launch (sheet cannot be dismissed until credentials are saved).

**Layout:**

```
┌─ Monday.com ──────────────────────────────────┐
│  API Token      [••••••••••••••] [Show]        │
│  Board ID       [                ]             │
│  Employee ID    [                ]             │
├─ Network Detection ───────────────────────────┤
│  Office IP Prefix    [9.         ]             │
│  Office DNS Domain   [ibm.com    ]             │
├─ Board Verification ──────────────────────────┤
│  [Verify Board]                                │
│  ✅ Found: Monday(1) Tuesday(129) Wed(209)...  │
│     Employee col: text_mm54pmq7                │
│     Week Start col: date_mm58nve7              │
│                                                │
│  ▶ Advanced (manual column IDs)               │
├───────────────────────────────────────────────┤
│                          [Cancel]  [Save]      │
└───────────────────────────────────────────────┘
```

**Save** is disabled until **Verify Board** has run successfully. After saving, the app immediately performs one network check and submits attendance if appropriate.

---

## 8. Notifications

Uses `UNUserNotificationCenter`. The app requests notification permission on first launch.

### Notification: Attendance logged

Triggered after a successful automatic check-in.

```
Title:   🏢 Attendance logged: Office
Body:    Wednesday, 16 July 2025
Actions: [Change]  [OK]
```

- **OK** — dismisses
- **Change** — activates the app and opens the Menu Bar dropdown

### Notification: Attendance logged (change confirmed)

Triggered after the user manually changes status from the dropdown.

```
Title:   ✅ Changed to: WFH
Body:    Wednesday, 16 July 2025
```
No action buttons.

### Notification: Setup required

Triggered on network connect when credentials are not configured.

```
Title:   ⚙️ Office Attendance — Setup required
Body:    Tap to open Settings
Actions: [Open Settings]
```

---

## 9. Menu Bar UI

### Icon states

| State | Icon text |
|-------|-----------|
| Checked in — Office | `🏢 Office` |
| Checked in — WFH | `🏠 WFH` |
| Checked in — Sick | `🤒 Sick` |
| Checked in — Vacation | `🌴 Vacation` |
| Checked in — Holiday | `🎌 Holiday` |
| Not yet checked in | `🏢?` |
| Weekend | `🏢` |
| Not configured | `⚙️` |

### Dropdown

```
🏢 Office                     ← today's status, bold, non-interactive
Wednesday, 16 July 2025
──────────────────────────────
Change to:
  WFH
  Sick
  Vacation
  Holiday
──────────────────────────────
Settings…
Quit
```

Clicking a "Change to" item calls `MondayService` directly and posts a confirmation notification on success.

---

## 10. Distribution

- Language: **Swift 5.9+**, UI: **SwiftUI** (Menu Bar extras) + **AppKit** for the settings panel
- Minimum macOS: **13.0 (Ventura)** — required for `NWPathMonitor` reliability and modern `UNUserNotificationCenter` action handling
- Signed with **Developer ID Application** certificate
- Notarized via `notarytool` before each release
- Packaged as a `.dmg` with an `Applications` symlink
- Distributed via **GitHub Releases** — one `.dmg` asset per version tag
- Auto-update: **Sparkle 2.x** framework, update feed hosted as a `appcast.xml` in the GitHub repo

---

## 11. Out of Scope

The following are explicitly excluded from this version:

- Multiple board configurations per user
- Automatic creation of missing week rows on Monday.com
- iOS / iPadOS companion app
- Admin dashboard or aggregate reporting
- Any UI beyond the Menu Bar icon, dropdown, and settings window
