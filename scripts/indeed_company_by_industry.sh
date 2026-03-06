#!/usr/bin/env bash
# Usage: indeed_company_by_industry.sh <industry> <state> [--limit N]
# Discover companies by industry and state (async).
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly API_KEY="${BRIGHTDATA_API_KEY:?Set BRIGHTDATA_API_KEY}"
readonly BASE_URL="https://api.brightdata.com/datasets/v3"
readonly CONFIG_DIR="${HOME}/.config/indeed-brightdata"
readonly DATASETS_FILE="${CONFIG_DIR}/datasets.json"

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_company_by_industry.sh <industry> <state> [OPTIONS]

Discover companies on Indeed by industry and state.

Arguments:
  industry             Industry category (e.g., "Technology", "Healthcare")
  state                US state (e.g., "Texas", "California")

Options:
  --limit N            Max results to return
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
  INDUSTRY=""
  STATE=""
  LIMIT=""

  local positional=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) show_help ;;
      --limit) LIMIT="$2"; shift 2 ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *)
        case $positional in
          0) INDUSTRY="$1" ;;
          1) STATE="$1" ;;
          *) echo "Error: unexpected argument: $1" >&2; exit 1 ;;
        esac
        positional=$((positional + 1))
        shift
        ;;
    esac
  done

  if [[ -z "$INDUSTRY" || -z "$STATE" ]]; then
    echo "Error: industry and state are required" >&2
    echo "Run with --help for usage" >&2
    exit 1
  fi
}

main() {
  parse_args "$@"

  local dataset_id
  dataset_id=$(get_company_dataset_id) || exit 1

  local payload
  payload=$(jq -n --arg ind "$INDUSTRY" --arg st "$STATE" \
    '[{industry: $ind, state: $st}]')

  local endpoint="${BASE_URL}/trigger?dataset_id=${dataset_id}&type=discover_new&discover_by=industry_and_state"
  if [[ -n "$LIMIT" ]]; then
    endpoint="${endpoint}&limit_multiple_results=${LIMIT}"
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

  echo "Searching Indeed for ${INDUSTRY} companies in ${STATE}..." >&2
  "${SCRIPT_DIR}/indeed_poll_and_fetch.sh" "$snapshot_id"
}

main "$@"
