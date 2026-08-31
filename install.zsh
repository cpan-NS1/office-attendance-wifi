#!/bin/zsh
# Installs the check as a per-user LaunchAgent.
set -euo pipefail

PACKAGE_DIR=${0:A:h}
AGENT_PATH="$HOME/Library/LaunchAgents/com.user.office-attendance-wifi.plist"

if ! command -v jq >/dev/null; then
  print -u2 "jq is required. Install it first (for example: brew install jq)."
  exit 1
fi

print -n "Office IP prefix (the start of your IP when in the office) [9.]: "
read -r office_ip_prefix
office_ip_prefix=${office_ip_prefix:-9.}

print -n "Office DNS search domain [ibm.com]: "
read -r office_dns_domain
office_dns_domain=${office_dns_domain:-ibm.com}

print -n "Monday board ID [18428037357]: "
read -r board_id
board_id=${board_id:-18428037357}

print -n "Your employee ID [1058851]: "
read -r employee_id
employee_id=${employee_id:-1058851}

print -s -n "Monday API token (input hidden): "
read -r monday_token
print
if [[ -z "$monday_token" ]]; then
  print -u2 "A token is required. Nothing was installed."
  exit 1
fi

cat > "$PACKAGE_DIR/.env" <<ENV
OFFICE_IP_PREFIX=$(printf '%q' "$office_ip_prefix")
OFFICE_DNS_DOMAIN=$(printf '%q' "$office_dns_domain")
BOARD_ID=$(printf '%q' "$board_id")
EMPLOYEE_ID=$(printf '%q' "$employee_id")
MONDAY_TOKEN=$(printf '%q' "$monday_token")
STATE_DIR="$PACKAGE_DIR"
LOG_FILE="$PACKAGE_DIR/check-office-attendance.log"
ENV
chmod 600 "$PACKAGE_DIR/.env"

mkdir -p "$HOME/Library/LaunchAgents"
chmod 700 "$PACKAGE_DIR/check-office-attendance.zsh"
/usr/bin/sed "s|__INSTALL_DIR__|$PACKAGE_DIR|g" "$PACKAGE_DIR/com.user.office-attendance-wifi.plist.template" > "$AGENT_PATH"
/bin/launchctl bootout "gui/$(id -u)" "$AGENT_PATH" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$(id -u)" "$AGENT_PATH"

print "Installed. The script will run on network changes and at login."
print "It changes only the current weekday's cell and logs to: $PACKAGE_DIR/check-office-attendance.log"
