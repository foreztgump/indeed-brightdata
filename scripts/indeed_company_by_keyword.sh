#!/usr/bin/env bash
# Usage: indeed_company_by_keyword.sh <keyword> [--limit N]
# Discover companies by keyword search (async).
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lib.sh"

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_company_by_keyword.sh <keyword> [OPTIONS]

Discover companies on Indeed by keyword search.

Arguments:
  keyword              Company search keyword (e.g., "Tesla", "healthcare")

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

parse_args() {
  KEYWORD=""
  LIMIT=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) show_help ;;
      --limit) LIMIT="$2"; shift 2 ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *) KEYWORD="$1"; shift ;;
    esac
  done

  if [[ -z "$KEYWORD" ]]; then
    echo "Error: keyword is required" >&2
    echo "Run with --help for usage" >&2
    exit 1
  fi
}

main() {
  parse_args "$@"

  local dataset_id
  dataset_id=$(get_dataset_id company) || exit 1

  local payload
  payload=$(jq -n --arg kw "$KEYWORD" '[{keyword: $kw}]')

  local endpoint="${LIB_BASE_URL}/trigger?dataset_id=${dataset_id}&type=discover_new&discover_by=keyword"
  if [[ -n "$LIMIT" ]]; then
    endpoint="${endpoint}&limit_multiple_results=${LIMIT}"
  fi

  local body
  body=$(make_api_request POST "$endpoint" "$payload")
  _read_http_code
  check_http_status "$HTTP_CODE" "$body" "trigger" || return 1

  local snapshot_id
  snapshot_id=$(extract_snapshot_id "$body") || return 1

  echo "Searching Indeed companies for \"${KEYWORD}\"..." >&2
  "${SCRIPT_DIR}/indeed_poll_and_fetch.sh" "$snapshot_id"
}

main "$@"
