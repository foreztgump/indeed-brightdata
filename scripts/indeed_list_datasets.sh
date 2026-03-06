#!/usr/bin/env bash
# Usage: indeed_list_datasets.sh [--save]
# List available Bright Data dataset IDs and optionally save company ID to config.
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly API_KEY="${BRIGHTDATA_API_KEY:?Set BRIGHTDATA_API_KEY}"
readonly LIST_URL="https://api.brightdata.com/datasets/list"
readonly CONFIG_DIR="${HOME}/.config/indeed-brightdata"
readonly DATASETS_FILE="${CONFIG_DIR}/datasets.json"
readonly KNOWN_JOBS_ID="gd_l4dx9j9sscpvs7no2"

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_list_datasets.sh [OPTIONS]

List available Bright Data Indeed dataset IDs.
Filters for Indeed-related datasets and displays them.

Options:
  --save               Save discovered dataset IDs to config file
  --help               Show this help message

Output:
  JSON object with jobs and company dataset IDs

Config:
  Saved to ~/.config/indeed-brightdata/datasets.json
EOF
  exit 0
}

parse_args() {
  SAVE=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) show_help ;;
      --save) SAVE=true; shift ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
  done
}

fetch_datasets() {
  local response http_code body
  response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${API_KEY}" \
    "$LIST_URL")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ne 200 ]]; then
    echo "Error: failed to list datasets (HTTP ${http_code}): ${body}" >&2
    return 1
  fi

  echo "$body"
}

filter_indeed_datasets() {
  local all_datasets="$1"
  # Filter for Indeed-related datasets by name/description
  echo "$all_datasets" | jq '[.[] | select(.name // "" | test("indeed"; "i"))]'
}

save_config() {
  local datasets="$1"
  mkdir -p "$CONFIG_DIR"

  # Extract company dataset ID (not the known jobs one)
  local company_id
  company_id=$(echo "$datasets" | jq -r \
    --arg jobs_id "$KNOWN_JOBS_ID" \
    '[.[] | select(.id != $jobs_id)] | .[0].id // empty')

  local config
  config=$(jq -n \
    --arg jobs "$KNOWN_JOBS_ID" \
    --arg company "$company_id" \
    '{jobs: $jobs, company: $company}')

  echo "$config" > "$DATASETS_FILE"
  echo "Saved dataset IDs to ${DATASETS_FILE}" >&2
  echo "  Jobs: ${KNOWN_JOBS_ID}" >&2
  echo "  Company: ${company_id:-not found}" >&2
}

main() {
  parse_args "$@"

  local all_datasets indeed_datasets
  all_datasets=$(fetch_datasets) || exit 1
  indeed_datasets=$(filter_indeed_datasets "$all_datasets")

  if [[ "$SAVE" == true ]]; then
    save_config "$indeed_datasets"
  fi

  echo "$indeed_datasets"
}

main "$@"
