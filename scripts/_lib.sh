#!/usr/bin/env bash
# scripts/_lib.sh — shared functions for Indeed Bright Data scripts
# Source this file: source "${SCRIPT_DIR}/_lib.sh"

readonly LIB_BASE_URL="https://api.brightdata.com/datasets/v3"
readonly LIB_JOBS_DATASET_ID="gd_l4dx9j9sscpvs7no2"
readonly LIB_CONFIG_DIR="${HOME}/.config/indeed-brightdata"
readonly LIB_DATASETS_FILE="${LIB_CONFIG_DIR}/datasets.json"

# Global set by make_api_request for callers to inspect
HTTP_CODE=""

# make_api_request <method> <endpoint> [payload]
# Makes an authenticated API request to Bright Data.
# Sets global HTTP_CODE. Outputs response body to stdout.
# Returns 0 always (caller checks HTTP_CODE via check_http_status).
make_api_request() {
  local method="$1"
  local endpoint="$2"
  local payload="${3:-}"
  local api_key="${BRIGHTDATA_API_KEY:?Set BRIGHTDATA_API_KEY}"

  local curl_args=(-s -w "\n%{http_code}" -H "Authorization: Bearer ${api_key}")

  if [[ "$method" == "POST" ]]; then
    curl_args+=(-X POST -H "Content-Type: application/json" -d "$payload")
  fi

  local response
  response=$(curl "${curl_args[@]}" "$endpoint")
  HTTP_CODE=$(echo "$response" | tail -1)
  local body
  body=$(echo "$response" | sed '$d')

  echo "$body"
  return 0
}

# check_http_status <http_code> <body> <action_description>
# Checks HTTP status code and prints error to stderr if not 200.
# Returns 0 on 200, 1 on any error.
check_http_status() {
  local http_code="$1"
  local body="$2"
  local action="$3"

  if [[ "$http_code" -eq 200 ]]; then
    return 0
  fi

  if [[ "$http_code" -eq 429 ]]; then
    echo "Error: rate limit exceeded (HTTP 429). Try again later." >&2
    return 1
  fi

  echo "Error: ${action} failed (HTTP ${http_code}): ${body}" >&2
  return 1
}

# get_dataset_id <type>
# Returns dataset ID for the given type ("jobs" or "company").
# Jobs: returns hardcoded ID. Company: reads from config file.
# Outputs dataset ID to stdout. Returns 1 if not found.
get_dataset_id() {
  local type="$1"

  if [[ "$type" == "jobs" ]]; then
    echo "$LIB_JOBS_DATASET_ID"
    return 0
  fi

  if [[ "$type" == "company" ]]; then
    if [[ -f "$LIB_DATASETS_FILE" ]]; then
      local id
      id=$(jq -r '.company // empty' "$LIB_DATASETS_FILE")
      if [[ -n "$id" ]]; then
        echo "$id"
        return 0
      fi
    fi
    echo "Error: company dataset ID not configured." >&2
    echo "Run indeed_list_datasets.sh --save to discover and store dataset IDs." >&2
    return 1
  fi

  echo "Error: unknown dataset type: ${type}" >&2
  return 1
}

# extract_snapshot_id <json_body>
# Extracts snapshot_id from a /trigger response.
# Outputs snapshot_id to stdout. Returns 1 if not found.
extract_snapshot_id() {
  local body="$1"
  local snapshot_id
  snapshot_id=$(echo "$body" | jq -r '.snapshot_id // empty')
  if [[ -z "$snapshot_id" ]]; then
    echo "Error: no snapshot_id in response: ${body}" >&2
    return 1
  fi
  echo "$snapshot_id"
}
