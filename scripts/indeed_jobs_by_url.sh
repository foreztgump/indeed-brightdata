#!/usr/bin/env bash
# Usage: indeed_jobs_by_url.sh <url> [url2 ...] [--limit N]
# Collect job listing details from Indeed job URLs (sync).
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly API_KEY="${BRIGHTDATA_API_KEY:?Set BRIGHTDATA_API_KEY}"
readonly DATASET_ID="gd_l4dx9j9sscpvs7no2"
readonly BASE_URL="https://api.brightdata.com/datasets/v3"
readonly MAX_SYNC_URLS=5

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_jobs_by_url.sh <url> [url2 ...] [OPTIONS]

Collect detailed job listing data from Indeed job URLs.

Arguments:
  url                  One or more Indeed job URLs (e.g., https://www.indeed.com/viewjob?jk=abc123)

Options:
  --limit N            Max results per URL
  --help               Show this help message

Output:
  JSON array to stdout

Examples:
  indeed_jobs_by_url.sh "https://www.indeed.com/viewjob?jk=abc123"
  indeed_jobs_by_url.sh url1 url2 url3
EOF
  exit 0
}

parse_args() {
  URLS=()
  LIMIT=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) show_help ;;
      --limit) LIMIT="$2"; shift 2 ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *) URLS+=("$1"); shift ;;
    esac
  done

  if [[ ${#URLS[@]} -eq 0 ]]; then
    echo "Error: at least one URL is required" >&2
    echo "Run with --help for usage" >&2
    exit 1
  fi
}

build_payload() {
  local payload="[]"
  for url in "${URLS[@]}"; do
    payload=$(echo "$payload" | jq --arg u "$url" '. + [{"url": $u}]')
  done
  echo "$payload"
}

scrape_sync() {
  local payload="$1"
  local endpoint="${BASE_URL}/scrape?dataset_id=${DATASET_ID}"
  if [[ -n "$LIMIT" ]]; then
    endpoint="${endpoint}&limit_per_input=${LIMIT}"
  fi

  local response http_code body
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$endpoint")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ne 200 ]]; then
    echo "Error: scrape failed (HTTP ${http_code}): ${body}" >&2
    return 1
  fi

  echo "$body"
}

trigger_async() {
  local payload="$1"
  local endpoint="${BASE_URL}/trigger?dataset_id=${DATASET_ID}"
  if [[ -n "$LIMIT" ]]; then
    endpoint="${endpoint}&limit_per_input=${LIMIT}"
  fi

  local response http_code body
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$endpoint")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ne 200 ]]; then
    echo "Error: trigger failed (HTTP ${http_code}): ${body}" >&2
    return 1
  fi

  local snapshot_id
  snapshot_id=$(echo "$body" | jq -r '.snapshot_id // empty')
  if [[ -z "$snapshot_id" ]]; then
    echo "Error: no snapshot_id in response: ${body}" >&2
    return 1
  fi

  echo "Triggered async job: ${snapshot_id}" >&2
  "${SCRIPT_DIR}/indeed_poll_and_fetch.sh" "$snapshot_id"
}

main() {
  parse_args "$@"

  local payload
  payload=$(build_payload)

  if [[ ${#URLS[@]} -le $MAX_SYNC_URLS ]]; then
    scrape_sync "$payload"
  else
    trigger_async "$payload"
  fi
}

main "$@"
