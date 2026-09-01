#!/bin/zsh
# Installs the SwiftBar plugin by symlinking it into the SwiftBar plugins folder.
set -euo pipefail

PACKAGE_DIR=${0:A:h}
PLUGIN_NAME="check-office-attendance.1h.zsh"

if ! command -v jq >/dev/null; then
  print -u2 "jq is required. Install it first: brew install jq"
  exit 1
fi

if ! command -v swiftbar >/dev/null && [[ ! -d "/Applications/SwiftBar.app" ]]; then
  print -u2 "SwiftBar is not installed. Install it first: brew install --cask swiftbar"
  exit 1
fi

if [[ -f "$PACKAGE_DIR/.env" ]]; then
  print ".env already exists — skipping configuration prompts."
else
  print -n "Office IP prefix (start of your IP when in the office) [9.]: "
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
ENV
  chmod 600 "$PACKAGE_DIR/.env"
fi

# Find the SwiftBar plugins folder from its preferences, fall back to default.
plugins_dir=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)
plugins_dir=${plugins_dir:-"$HOME/Library/Application Support/SwiftBar/Plugins"}
mkdir -p "$plugins_dir"

chmod +x "$PACKAGE_DIR/$PLUGIN_NAME"
ln -sf "$PACKAGE_DIR/$PLUGIN_NAME" "$plugins_dir/$PLUGIN_NAME"

print "Installed. SwiftBar will pick up the plugin automatically."
print "The plugin runs every hour and logs to: $PACKAGE_DIR/check-office-attendance.log"
print "Open SwiftBar and make sure it is running to see the menu bar icon."
