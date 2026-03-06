#!/usr/bin/env bash
# Usage: indeed_poll_and_fetch.sh <snapshot_id> [--timeout SECONDS] [--interval SECONDS]
# Polls Bright Data async job status until ready, then fetches results.
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly API_KEY="${BRIGHTDATA_API_KEY:?Set BRIGHTDATA_API_KEY}"
readonly BASE_URL="https://api.brightdata.com/datasets/v3"
readonly DEFAULT_TIMEOUT=300
readonly DEFAULT_INTERVAL=10

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_poll_and_fetch.sh <snapshot_id> [OPTIONS]

Poll a Bright Data async snapshot until ready, then fetch results.

Arguments:
  snapshot_id          The snapshot ID returned by a /trigger call

Options:
  --timeout SECONDS    Max time to wait (default: 300)
  --interval SECONDS   Poll interval (default: 10)
  --help               Show this help message

Output:
  JSON array to stdout
EOF
  exit 0
}

parse_args() {
  SNAPSHOT_ID=""
  TIMEOUT="$DEFAULT_TIMEOUT"
  INTERVAL="$DEFAULT_INTERVAL"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) show_help ;;
      --timeout) TIMEOUT="$2"; shift 2 ;;
      --interval) INTERVAL="$2"; shift 2 ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *) SNAPSHOT_ID="$1"; shift ;;
    esac
  done

  if [[ -z "$SNAPSHOT_ID" ]]; then
    echo "Error: snapshot_id is required" >&2
    echo "Run with --help for usage" >&2
    exit 1
  fi
}

poll_status() {
  local response http_code body
  response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${API_KEY}" \
    "${BASE_URL}/progress/${SNAPSHOT_ID}")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ne 200 ]]; then
    echo "Error: progress check failed (HTTP ${http_code}): ${body}" >&2
    return 1
  fi

  echo "$body" | jq -r '.status // "unknown"'
}

fetch_snapshot() {
  local response http_code body
  response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${API_KEY}" \
    "${BASE_URL}/snapshot/${SNAPSHOT_ID}?format=json")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ne 200 ]]; then
    echo "Error: snapshot fetch failed (HTTP ${http_code}): ${body}" >&2
    return 1
  fi

  echo "$body"
}

main() {
  parse_args "$@"

  local elapsed=0
  echo "Polling snapshot ${SNAPSHOT_ID}..." >&2

  while [[ "$elapsed" -lt "$TIMEOUT" ]]; do
    local status
    status=$(poll_status) || exit 1

    case "$status" in
      ready)
        echo "Snapshot ready. Fetching results..." >&2
        fetch_snapshot
        return 0
        ;;
      failed)
        echo "Error: snapshot ${SNAPSHOT_ID} failed" >&2
        return 1
        ;;
      *)
        echo "Status: ${status} (${elapsed}s/${TIMEOUT}s)" >&2
        sleep "$INTERVAL"
        elapsed=$((elapsed + INTERVAL))
        ;;
    esac
  done

  echo "Error: timed out after ${TIMEOUT}s waiting for snapshot ${SNAPSHOT_ID}" >&2
  return 1
}

main "$@"
