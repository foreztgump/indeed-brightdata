#!/usr/bin/env bash
# Usage: indeed_jobs_by_company.sh <company_jobs_url> [--limit N]
# Discover jobs from a company's Indeed jobs page (async).
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly API_KEY="${BRIGHTDATA_API_KEY:?Set BRIGHTDATA_API_KEY}"
readonly DATASET_ID="gd_l4dx9j9sscpvs7no2"
readonly BASE_URL="https://api.brightdata.com/datasets/v3"

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

  local payload
  payload=$(jq -n --arg u "$URL" '[{url: $u}]')

  local endpoint="${BASE_URL}/trigger?dataset_id=${DATASET_ID}&type=discover_new&discover_by=url"
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

  echo "Discovering jobs from company page..." >&2
  "${SCRIPT_DIR}/indeed_poll_and_fetch.sh" "$snapshot_id"
}

main "$@"
