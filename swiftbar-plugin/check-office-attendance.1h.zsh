#!/bin/zsh
# SwiftBar plugin — marks the current workday attendance on Monday.com.
# Refresh interval encoded in filename: .1h = run every hour.
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>false</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>false</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>false</swiftbar.hideSwiftBar>
set -euo pipefail

SCRIPT_DIR=${0:A:h}
if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  echo "🏢?"
  echo "---"
  echo "⚠️ Missing .env file"
  echo "Copy .env.example to .env and fill in your values."
  exit 1
fi
source "$SCRIPT_DIR/.env"
JQ=$(command -v jq)

STATE_DIR="$SCRIPT_DIR/.state"
LOG_FILE="$SCRIPT_DIR/check-office-attendance.log"
mkdir -p "$STATE_DIR"

log() {
  local msg="$(/bin/date '+%Y-%m-%d %H:%M:%S') $*"
  print -r -- "$msg" >> "$LOG_FILE"
}

weekday=$(/bin/date +%u)
today=$(/bin/date +%F)
week_start=$(/bin/date -v-$((weekday - 1))d +%F)

typeset -A DAY_COLUMNS
DAY_COLUMNS=(1 "1" 2 "129" 3 "209" 4 "205" 5 "201")
column_id=${DAY_COLUMNS[$weekday]:-}
marker="$STATE_DIR/$today-${column_id}.done"

# ---------------------------------------------------------------------------
# SET MODE — invoked when user clicks a status in the dropdown.
# SwiftBar passes: --set <status>
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--set" ]]; then
  shift  # consume --set; remaining args form the status (may be multi-word)
  chosen_status="${*:?missing status}"

  if [[ -z "${MONDAY_TOKEN:-}" ]]; then
    log "MONDAY_TOKEN is not set in .env."
    exit 1
  fi
  token="$MONDAY_TOKEN"

  api_call() {
    /usr/bin/curl --silent --show-error \
      --request POST "https://api.monday.com/v2" \
      --header "Authorization: $token" \
      --header "Content-Type: application/json" \
      --data "$1"
  }

  query='query ($boardId: ID!) {
  boards(ids: [$boardId]) {
    items_page(limit: 500) {
      items { id column_values(ids: ["text_mm54pmq7", "date_mm58nve7"]) { id text value } }
    }
  }
}'
  query_payload=$("$JQ" -n --arg query "$query" --arg board "$BOARD_ID" \
    '{query: $query, variables: {boardId: $board}}')
  query_response=$(api_call "$query_payload")

  if print -r -- "$query_response" | "$JQ" -e '.errors | length > 0' >/dev/null; then
    log "Monday query failed: $(print -r -- "$query_response" | "$JQ" -c '.errors')"
    exit 1
  fi

  item_id=$(print -r -- "$query_response" | "$JQ" -r \
    --arg employee "$EMPLOYEE_ID" --arg week_start "$week_start" '
      .data.boards[0].items_page.items[]
      | select(any(.column_values[]?; .id == "text_mm54pmq7" and .text == $employee))
      | select(any(.column_values[]?; .id == "date_mm58nve7" and ((try (.value | fromjson | .date) catch "") == $week_start)))
      | .id' | /usr/bin/head -n 1)

  if [[ -z "$item_id" || "$item_id" == "null" ]]; then
    log "No row found for employee $EMPLOYEE_ID and week starting $week_start."
    exit 1
  fi

  mutation='mutation ($boardId: ID!, $itemId: ID!, $columnId: String!, $value: String!) {
  change_simple_column_value(board_id: $boardId, item_id: $itemId, column_id: $columnId, value: $value) { id }
}'
  mutation_payload=$("$JQ" -n \
    --arg query "$mutation" --arg board "$BOARD_ID" --arg item "$item_id" \
    --arg column "$column_id" --arg value "$chosen_status" \
    '{query: $query, variables: {boardId: $board, itemId: $item, columnId: $column, value: $value}}')
  mutation_response=$(api_call "$mutation_payload")

  if print -r -- "$mutation_response" | "$JQ" -e '.errors | length > 0' >/dev/null; then
    log "Monday update failed: $(print -r -- "$mutation_response" | "$JQ" -c '.errors')"
    exit 1
  fi

  print -r -- "$chosen_status" > "$marker"
  log "Set $today column $column_id to $chosen_status for item $item_id."

  # Audible confirmation (no notification permission required).
  afplay /System/Library/Sounds/Glass.aiff &

  # Tell SwiftBar to refresh the plugin immediately.
  open "swiftbar://refreshplugin?name=check-office-attendance"
  exit 0
fi

# ---------------------------------------------------------------------------
# DISPLAY MODE — normal hourly run, just render the menu bar output.
# ---------------------------------------------------------------------------

if (( weekday > 5 )); then
  echo "🏢"
  echo "---"
  echo "Weekend — no attendance update needed."
  exit 0
fi

# Build SwiftBar param string for a status value (handles multi-word values).
# Usage: status_params "WFH: Sickness"  →  param1=--set param2=WFH: param3=Sickness
status_params() {
  local sval="$1" i=2 word params="param1=--set"
  for word in ${=sval}; do
    params+=" param${i}=${word}"
    (( i++ ))
  done
  print -r -- "$params"
}

# Emit status menu items with submenu grouping (SwiftBar -- prefix = submenu).
# $1 = label prefix ("Set: " or "")
# $2 = status to exclude (current, or empty)
emit_status_items() {
  local prefix="$1" exclude="$2"

  # Group: Office (single)
  if [[ "$exclude" != "Office" ]]; then
    echo "${prefix}Office | bash=$SCRIPT_PATH $(status_params "Office") terminal=false refresh=true"
  fi

  # Group: WFH (submenu)
  local wfh_members=("WFH" "WFH: Sickness" "WFH: Unplanned Issues" "WFH: Weather Warning")
  local wfh_candidates=()
  for ws in "${wfh_members[@]}"; do
    [[ "$ws" != "$exclude" ]] && wfh_candidates+=("$ws")
  done
  if (( ${#wfh_candidates[@]} > 0 )); then
    echo "${prefix}WFH… | color=gray"
    for ws in "${wfh_candidates[@]}"; do
      echo "--${prefix}${ws} | bash=$SCRIPT_PATH $(status_params "$ws") terminal=false refresh=true"
    done
  fi

  # Group: Vacation (submenu)
  local vac_members=("Vacation" "LOA" "Bank Holiday" "Travel")
  local vac_candidates=()
  for vs in "${vac_members[@]}"; do
    [[ "$vs" != "$exclude" ]] && vac_candidates+=("$vs")
  done
  if (( ${#vac_candidates[@]} > 0 )); then
    echo "${prefix}Vacation… | color=gray"
    for vs in "${vac_candidates[@]}"; do
      echo "--${prefix}${vs} | bash=$SCRIPT_PATH $(status_params "$vs") terminal=false refresh=true"
    done
  fi

  # Group: Sick (single)
  if [[ "$exclude" != "Sick" ]]; then
    echo "${prefix}Sick | bash=$SCRIPT_PATH $(status_params "Sick") terminal=false refresh=true"
  fi
}

# Already logged today — show status with option to change.
if [[ -f "$marker" ]]; then
  done_status=$(cat "$marker")
  SCRIPT_PATH="${0:A}"
  echo "🏢 $done_status"
  echo "---"
  echo "✅ Attendance logged: $done_status ($today)"
  echo "---"
  echo "Change to:"
  emit_status_items "" "$done_status"
  exit 0
fi

# Detect office network.
current_ip=$(/usr/sbin/ipconfig getifaddr en0 2>/dev/null || true)
dns_domain=$(scutil --dns 2>/dev/null | /usr/bin/awk '/search domain\[0\]/ { print $NF; exit }')

# If a VPN tunnel is active (utun*/ppp* interface has an IP), we are working
# remotely — even if DNS search domains appear corporate.
# Filter for UP interfaces only — dormant system utun (e.g. iCloud Private
# Relay placeholders) have POINTOPOINT but lack the UP flag.
vpn_active=0
if /usr/sbin/ifconfig 2>/dev/null | /usr/bin/grep -E '^(utun|ppp)[0-9]+:' | /usr/bin/grep -qE 'flags=[0-9a-fx]+<[^>]*\bUP\b[^>]*POINTOPOINT'; then
  vpn_active=1
fi

on_office_network=0
if (( !vpn_active )); then
  if [[ -n "$OFFICE_IP_PREFIX" && "$current_ip" == ${OFFICE_IP_PREFIX}* ]]; then
    on_office_network=1
  fi
  if [[ -n "$OFFICE_DNS_DOMAIN" && "$dns_domain" == *"$OFFICE_DNS_DOMAIN"* ]]; then
    on_office_network=1
  fi
fi

if [[ ${FORCE_RUN:-0} != 1 ]] && (( !on_office_network )); then
  echo "🏢"
  echo "---"
  echo "Not on office network — no update."
  echo "IP: ${current_ip:-<none>}  DNS: ${dns_domain:-<none>}"
  log "Not on office network (IP: ${current_ip:-<none>}, DNS domain: ${dns_domain:-<none>}, VPN active: ${vpn_active}); no update."
  exit 0
fi

# Attendance not logged yet — show status options in the dropdown.
if (( on_office_network )); then
  default_status="Office"
  network_note="On office network"
else
  default_status="WFH"
  network_note="Working remotely"
fi

SCRIPT_PATH="${0:A}"

echo "🏢?"
echo "---"
echo "Log attendance for $today ($network_note):"
echo "---"
# Default status shown first and bolded.
echo "**Set: $default_status** | bash=$SCRIPT_PATH $(status_params "$default_status") terminal=false refresh=true"
echo "---"
emit_status_items "Set: " "$default_status"
