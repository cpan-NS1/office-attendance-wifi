# Office Attendance

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-chenmo-yellow?logo=buy-me-a-coffee)](https://buymeacoffee.com/chenmo)

Two independent implementations of the same idea — automatically log your daily attendance on Monday.com based on whether you are on the IBM office network.

| Folder | Approach | What you need |
|---|---|---|
| [`macOS-app/`](macOS-app/) | Native macOS menu-bar app (SwiftUI + Xcode) | Xcode 15+, macOS 13+ |
| [`swiftbar-plugin/`](swiftbar-plugin/) | SwiftBar shell-script plugin | SwiftBar, jq |

---

## macOS App

A native, self-contained menu-bar application built with Swift and SwiftUI. Runs as a background accessory, detects the office network using IP prefix / DNS domain, and checks you in automatically. Provides a Settings window for configuration — no terminal required after the first launch.

### Storage

All configuration and history is stored in `~/.officeattendance/` in your home folder:

```
~/.officeattendance/
  config.json    ← API token, board ID, employee ID, network settings, column map
  history.json   ← daily attendance entries [{date, status}, ...]
```

Both files are created with permissions `0600` (owner read/write only) and the directory with `0700`. This means your settings persist across app updates and reinstalls — you will never need to re-enter your credentials after updating.

Existing installations are migrated automatically on first launch after update.

### Build & install

```zsh
cd macOS-app
./build.sh            # Release DMG
./build.sh --debug    # Debug build
```

Or open `macOS-app/OfficeAttendance.xcodeproj` in Xcode and run directly.

---

## SwiftBar Plugin

A [SwiftBar](https://swiftbar.app) plugin written in zsh. SwiftBar runs the script every hour. When attendance hasn't been logged yet today:

1. A dropdown appears pre-filled with the smart default:
   - **Office network detected** → default is `Office`
   - **Remote / other network** → default is `WFH`
2. Click the primary button to confirm, or choose a different status.
3. The menu bar icon updates to show today's logged status (e.g. `🏢 Office`).

Weekends are skipped automatically. A marker file prevents the same day being submitted twice.

> **Why not SSID?** macOS 12+ redacts the SSID from all shell-accessible APIs. IP prefix and DNS domain are available without any special entitlement and are equally reliable for identifying the office network.

### Requirements

- [SwiftBar](https://swiftbar.app) — `brew install --cask swiftbar`
- [jq](https://stedolan.github.io/jq/) — `brew install jq`

### Setup

1. Install SwiftBar and jq:

   ```zsh
   brew install --cask swiftbar
   brew install jq
   ```

2. Clone or download this repo somewhere permanent (e.g. `~/Projects/office-attendance-wifi`).

3. Run the installer:

   ```zsh
   cd ~/Projects/office-attendance-wifi/swiftbar-plugin
   ./install.zsh
   ```

4. Open SwiftBar (if it isn't running). It will pick up the plugin automatically.

### Manual test

```zsh
cd swiftbar-plugin
FORCE_RUN=1 zsh check-office-attendance.1h.zsh
```

### Uninstall

```zsh
rm ~/Library/Application\ Support/SwiftBar/Plugins/check-office-attendance.1h.zsh
```

Then remove this repo folder if you no longer need it.

---

## Support

If this project saves you a few minutes every day, consider buying me a coffee! ☕

[https://buymeacoffee.com/chenmo](https://buymeacoffee.com/chenmo)
