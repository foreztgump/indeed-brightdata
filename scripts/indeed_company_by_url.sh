#!/usr/bin/env bash
# Usage: indeed_company_by_url.sh <url> [url2 ...] [--limit N]
# Collect company info from Indeed company URLs (sync).
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly API_KEY="${BRIGHTDATA_API_KEY:?Set BRIGHTDATA_API_KEY}"
readonly BASE_URL="https://api.brightdata.com/datasets/v3"
readonly CONFIG_DIR="${HOME}/.config/indeed-brightdata"
readonly DATASETS_FILE="${CONFIG_DIR}/datasets.json"
readonly MAX_SYNC_URLS=5

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_company_by_url.sh <url> [url2 ...] [OPTIONS]

Collect company information from Indeed company page URLs.

Arguments:
  url                  One or more Indeed company URLs (e.g., https://www.indeed.com/cmp/Google)

Options:
  --limit N            Max results per URL
  --help               Show this help message

Output:
  JSON array to stdout

Note:
  Requires company dataset ID. Run indeed_list_datasets.sh first if not configured.
EOF
  exit 0
}

get_company_dataset_id() {
  if [[ -f "$DATASETS_FILE" ]]; then
    local id
    id=$(jq -r '.company // empty' "$DATASETS_FILE")
    if [[ -n "$id" ]]; then
      echo "$id"
      return 0
    fi
  fi
  echo "Error: company dataset ID not configured." >&2
  echo "Run indeed_list_datasets.sh to discover and store dataset IDs." >&2
  return 1
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

main() {
  parse_args "$@"

  local dataset_id
  dataset_id=$(get_company_dataset_id) || exit 1

  local payload
  payload=$(build_payload)

  local endpoint
  if [[ ${#URLS[@]} -le $MAX_SYNC_URLS ]]; then
    endpoint="${BASE_URL}/scrape?dataset_id=${dataset_id}"
  else
    endpoint="${BASE_URL}/trigger?dataset_id=${dataset_id}"
  fi
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
    echo "Error: request failed (HTTP ${http_code}): ${body}" >&2
    return 1
  fi

  # If async, poll for results
  if [[ ${#URLS[@]} -gt $MAX_SYNC_URLS ]]; then
    local snapshot_id
    snapshot_id=$(echo "$body" | jq -r '.snapshot_id // empty')
    if [[ -z "$snapshot_id" ]]; then
      echo "Error: no snapshot_id in response: ${body}" >&2
      return 1
    fi
    "${SCRIPT_DIR}/indeed_poll_and_fetch.sh" "$snapshot_id"
  else
    echo "$body"
  fi
}

main "$@"
