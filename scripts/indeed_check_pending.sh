#!/usr/bin/env bash
# Usage: indeed_check_pending.sh [--help]
# Checks all pending snapshots, fetches completed ones, removes them from pending.
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON results to stdout for each completed snapshot
# Exit: 0 if any results fetched, 1 on error, 2 if all still running

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
source "${SCRIPT_DIR}/_lib.sh"

readonly STALE_THRESHOLD_HOURS=24

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_check_pending.sh [OPTIONS]

Check all pending Indeed snapshots. Fetches completed results and removes
them from the pending queue.

Options:
  --help               Show this help message

Exit Codes:
  0    At least one snapshot fetched successfully
  1    Error occurred
  2    All snapshots still running (none ready)

Output:
  JSON results to stdout for each completed snapshot
EOF
  exit 0
}

check_stale() {
  local triggered_at="$1"
  local description="$2"
  local now_epoch
  now_epoch=$(date -u +%s)
  local entry_epoch
  entry_epoch=$(date -u -d "$triggered_at" +%s 2>/dev/null || echo "0")
  local age_hours=$(( (now_epoch - entry_epoch) / 3600 ))

  if [[ "$age_hours" -ge "$STALE_THRESHOLD_HOURS" ]]; then
    echo "Warning: stale pending entry (${age_hours}h old): ${description}" >&2
  fi
}

main() {
  if [[ "${1:-}" == "--help" ]]; then
    show_help
  fi

  local pending
  pending=$(load_pending)

  local count
  count=$(echo "$pending" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    echo "No pending snapshots." >&2
    exit 0
  fi

  echo "Checking ${count} pending snapshot(s)..." >&2

  local fetched=0
  local still_running=0
  local errors=0

  for i in $(seq 0 $((count - 1))); do
    local entry
    entry=$(echo "$pending" | jq ".[$i]")
    local snapshot_id
    snapshot_id=$(echo "$entry" | jq -r '.snapshot_id')
    local description
    description=$(echo "$entry" | jq -r '.description')
    local triggered_at
    triggered_at=$(echo "$entry" | jq -r '.triggered_at')

    if ! _validate_snapshot_id "$snapshot_id"; then
      echo "Error: skipping invalid snapshot_id in pending entry: ${description}" >&2
      remove_pending "$snapshot_id" 2>/dev/null
      errors=$((errors + 1))
      continue
    fi

    check_stale "$triggered_at" "$description"

    local body
    body=$(make_api_request GET "${LIB_BASE_URL}/progress/${snapshot_id}")
    _read_http_code
    if ! check_http_status "$HTTP_CODE" "$body" "progress check for ${snapshot_id}"; then
      errors=$((errors + 1))
      continue
    fi

    local status
    status=$(echo "$body" | jq -r '.status // "unknown"')

    case "$status" in
      ready)
        echo "Fetching results for: ${description}" >&2
        local results
        results=$(make_api_request GET "${LIB_BASE_URL}/snapshot/${snapshot_id}?format=json")
        _read_http_code
        if check_http_status "$HTTP_CODE" "$results" "snapshot fetch for ${snapshot_id}"; then
          echo "$results"
          remove_pending "$snapshot_id"
          fetched=$((fetched + 1))
        else
          errors=$((errors + 1))
        fi
        ;;
      failed)
        echo "Error: snapshot ${snapshot_id} failed (${description})" >&2
        remove_pending "$snapshot_id"
        errors=$((errors + 1))
        ;;
      *)
        echo "Still running: ${description} (snapshot ${snapshot_id})" >&2
        still_running=$((still_running + 1))
        ;;
    esac
  done

  echo "Summary: ${fetched} fetched, ${still_running} still running, ${errors} errors" >&2

  if [[ "$fetched" -gt 0 ]]; then
    exit 0
  elif [[ "$errors" -gt 0 ]]; then
    exit 1
  else
    exit 2
  fi
}

main "$@"
