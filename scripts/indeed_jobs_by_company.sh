#!/usr/bin/env bash
# Usage: indeed_jobs_by_company.sh <company_jobs_url> [--limit N]
# Discover jobs from a company's Indeed jobs page (async).
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lib.sh"

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_jobs_by_company.sh <company_jobs_url> [OPTIONS]

Discover job listings from a company's Indeed jobs page.

Arguments:
  company_jobs_url     Indeed company jobs URL (e.g., https://www.indeed.com/cmp/Google/jobs)

Options:
  --limit N            Max results to return
  --help               Show this help message

Output:
  JSON array to stdout
EOF
  exit 0
}

parse_args() {
  URL=""
  LIMIT=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) show_help ;;
      --limit) LIMIT="$2"; shift 2 ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *) URL="$1"; shift ;;
    esac
  done

  if [[ -z "$URL" ]]; then
    echo "Error: company jobs URL is required" >&2
    echo "Run with --help for usage" >&2
    exit 1
  fi
}

main() {
  parse_args "$@"

  local dataset_id
  dataset_id=$(get_dataset_id jobs)

  local payload
  payload=$(jq -n --arg u "$URL" '[{url: $u}]')

  local endpoint="${LIB_BASE_URL}/trigger?dataset_id=${dataset_id}&type=discover_new&discover_by=url"
  if [[ -n "$LIMIT" ]]; then
    endpoint="${endpoint}&limit_multiple_results=${LIMIT}"
  fi

  local body
  body=$(make_api_request POST "$endpoint" "$payload")
  _read_http_code
  check_http_status "$HTTP_CODE" "$body" "trigger" || return 1

  local snapshot_id
  snapshot_id=$(extract_snapshot_id "$body") || return 1

  echo "Discovering jobs from company page..." >&2
  "${SCRIPT_DIR}/indeed_poll_and_fetch.sh" "$snapshot_id"
}

main "$@"
