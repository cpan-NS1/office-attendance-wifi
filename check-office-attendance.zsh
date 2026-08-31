#!/bin/zsh
# Marks the current workday as Office only while connected to the configured network.
set -euo pipefail

SCRIPT_DIR=${0:A:h}
if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  print -u2 "Missing .env file. Copy .env.example to .env and fill in your values."
  exit 1
fi
source "$SCRIPT_DIR/.env"
JQ=$(command -v jq)

log() {
  local msg="$(/bin/date '+%Y-%m-%d %H:%M:%S') $*"
  print -r -- "$msg" >> "$LOG_FILE"
  print -r -- "$msg"
}

mkdir -p "$STATE_DIR"

weekday=$(/bin/date +%u)
if (( weekday > 5 )); then
  log "Weekend; no attendance update needed."
  exit 0
fi

typeset -A DAY_COLUMNS
DAY_COLUMNS=(1 "1" 2 "129" 3 "209" 4 "205" 5 "201")
column_id=${DAY_COLUMNS[$weekday]}
today=$(/bin/date +%F)
week_start=$(/bin/date -v-$((weekday - 1))d +%F)
marker="$STATE_DIR/$today-$column_id.done"

if [[ -f "$marker" ]]; then
  log "Already updated $today."
  exit 0
fi

if [[ ${FORCE_RUN:-0} != 1 ]]; then
  # macOS 12+ redacts SSID from all shell-accessible APIs (entitlement required).
  # Instead, detect the office network by IP address prefix and DNS search domain.
  current_ip=$(/usr/sbin/ipconfig getifaddr en0 2>/dev/null || true)
  dns_domain=$(scutil --dns 2>/dev/null | /usr/bin/awk '/search domain\[0\]/ { print $NF; exit }')

  on_office_network=0
  if [[ -n "$OFFICE_IP_PREFIX" && "$current_ip" == ${OFFICE_IP_PREFIX}* ]]; then
    on_office_network=1
  fi
  if [[ -n "$OFFICE_DNS_DOMAIN" && "$dns_domain" == *"$OFFICE_DNS_DOMAIN"* ]]; then
    on_office_network=1
  fi

  if (( !on_office_network )); then
    log "Not on office network (IP: ${current_ip:-<none>}, DNS domain: ${dns_domain:-<none>}); no update."
    exit 0
  fi
fi

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

# Find precisely the one row for this employee and the week containing today.
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

if [[ ${DRY_RUN:-0} == 1 ]]; then
  log "Dry run: would set $today column $column_id to Office for item $item_id."
  if [[ -n "${TERMINAL_NOTIFIER:-}" && -x "$TERMINAL_NOTIFIER" ]]; then
    "$TERMINAL_NOTIFIER" -message "Dry run: would mark as Office for today" -title "Attendance Check-in" -sound default 2>/dev/null || true
  fi
  exit 0
fi

mutation='mutation ($boardId: ID!, $itemId: ID!, $columnId: String!, $value: String!) {
  change_simple_column_value(board_id: $boardId, item_id: $itemId, column_id: $columnId, value: $value) { id }
}'
mutation_payload=$(/opt/homebrew/bin/jq -n \
  --arg query "$mutation" --arg board "$BOARD_ID" --arg item "$item_id" \
  --arg column "$column_id" --arg value "Office" \
  '{query: $query, variables: {boardId: $board, itemId: $item, columnId: $column, value: $value}}')
mutation_response=$(api_call "$mutation_payload")

if print -r -- "$mutation_response" | "$JQ" -e '.errors | length > 0' >/dev/null; then
  log "Monday update failed: $(print -r -- "$mutation_response" | "$JQ" -c '.errors')"
  exit 1
fi

print -r -- "$item_id" > "$marker"
log "Set $today column $column_id to Office for item $item_id."
if [[ -n "${TERMINAL_NOTIFIER:-}" && -x "$TERMINAL_NOTIFIER" ]]; then
  "$TERMINAL_NOTIFIER" -message "Marked as Office for today" -title "Attendance Check-in" -sound default 2>/dev/null || true
fi
