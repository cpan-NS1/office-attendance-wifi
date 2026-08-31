# Office attendance check-in

This macOS LaunchAgent checks the current network connection at login and whenever network configuration changes. When the device is on the IBM office network (detected by IP address prefix and DNS domain), it changes **only today's weekday cell** on the current week's row to **Office**.

> **Why not SSID?** macOS 12+ redacts the SSID from all shell-accessible APIs. IP prefix and DNS domain are available without any special entitlement and are equally reliable for identifying the office network.

It is configured for the supplied Monday board and your employee ID. The weekday status-column IDs are already mapped:

| Weekday | Column ID |
| --- | --- |
| Monday | `1` |
| Tuesday | `129` |
| Wednesday | `209` |
| Thursday | `205` |
| Friday | `201` |

## Setup

1. Copy `.env.example` to `.env` and fill in your values:

   ```zsh
   cp .env.example .env
   ```

   Edit `.env`:
   - **`OFFICE_IP_PREFIX`** — the start of your IP on the office network. For IBM this is `9.` (default). If unsure, connect to office Wi-Fi and run `ipconfig getifaddr en0`.
   - **`OFFICE_DNS_DOMAIN`** — the DNS search domain pushed by the office DHCP server. For IBM this is `ibm.com` (default). If unsure, run `scutil --dns | grep "search domain"`.
   - **`BOARD_ID`** — the Monday board ID (pre-filled).
   - **`EMPLOYEE_ID`** — your employee ID (pre-filled).
   - **`MONDAY_TOKEN`** — your Monday developer API token. Find it at: profile avatar → **Developers** → **My Access Tokens**.

2. Test it without changing Monday:

   ```zsh
   DRY_RUN=1 "/Users/chandler/Project/office-attendance-wifi/check-office-attendance.zsh"
   ```

3. Once it works, install the LaunchAgent so it runs automatically on network changes:

   ```zsh
   cd "/Users/chandler/Project/office-attendance-wifi"
   ./install.zsh
   ```

The job skips weekends and records a local completion marker after a successful update, so it will not submit the same weekday twice. Logs are written to `check-office-attendance.log` inside the repo folder.

## Uninstall

```zsh
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.user.office-attendance-wifi.plist"
rm "$HOME/Library/LaunchAgents/com.user.office-attendance-wifi.plist"
```
