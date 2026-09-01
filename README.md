# Office attendance check-in

A [SwiftBar](https://swiftbar.app) plugin that prompts you to log your attendance on Monday.com once per day. It detects whether you are on the IBM office network and pre-selects **Office** or **WFH** accordingly — you confirm with one click or choose a different status.

> **Why not SSID?** macOS 12+ redacts the SSID from all shell-accessible APIs. IP prefix and DNS domain are available without any special entitlement and are equally reliable for identifying the office network.

## How it works

SwiftBar runs the plugin every hour. When attendance hasn't been logged yet today:

1. A dialog appears pre-filled with the smart default:
   - **Office network detected** → default is `Office`
   - **Remote / other network** → default is `WFH`
2. Click the primary button to confirm, **Change** to pick a different status, or **Not Now** to skip (it will prompt again next hour).
3. The menu bar icon updates to show today's logged status (e.g. `🏢 Office`).

Weekends are skipped automatically. A marker file prevents the same day being submitted twice.

| Weekday | Monday column ID |
| --- | --- |
| Monday | `1` |
| Tuesday | `129` |
| Wednesday | `209` |
| Thursday | `205` |
| Friday | `201` |

## Requirements

- [SwiftBar](https://swiftbar.app) — `brew install --cask swiftbar`
- [jq](https://stedolan.github.io/jq/) — `brew install jq`

## Setup

1. Install SwiftBar and jq if you haven't already:

   ```zsh
   brew install --cask swiftbar
   brew install jq
   ```

2. Clone or download this repo somewhere permanent (e.g. `~/Projects/office-attendance-wifi`).

3. Run the installer — it writes `.env` and symlinks the plugin into your SwiftBar plugins folder:

   ```zsh
   cd ~/Projects/office-attendance-wifi
   ./install.zsh
   ```

4. Open SwiftBar (if it isn't running). It will pick up the plugin automatically.

## Manual test

To trigger the dialog without waiting for the next hourly run:

```zsh
FORCE_RUN=1 zsh check-office-attendance.1h.zsh
```

To do a dry run (no Monday.com changes):

```zsh
FORCE_RUN=1 DRY_RUN=1 zsh check-office-attendance.1h.zsh
```

## Sharing with a colleague

Send them the repo (or a zip). They run `./install.zsh` with their own credentials. That's it.

## Uninstall

```zsh
rm ~/Library/Application\ Support/SwiftBar/Plugins/check-office-attendance.1h.zsh
```

Then remove this repo folder if you no longer need it.
