#!/usr/bin/env bash
# scripts/_lib.sh — shared functions for Indeed Bright Data scripts
# Source this file: source "${SCRIPT_DIR}/_lib.sh"

# shellcheck disable=SC2034
readonly LIB_BASE_URL="https://api.brightdata.com/datasets/v3"
readonly LIB_JOBS_DATASET_ID="gd_l4dx9j9sscpvs7no2"
readonly LIB_CONFIG_DIR="${HOME}/.config/indeed-brightdata"
readonly LIB_DATASETS_FILE="${LIB_CONFIG_DIR}/datasets.json"
readonly LIB_PENDING_FILE="${LIB_CONFIG_DIR}/pending.json"

# Global set by make_api_request for callers to inspect
HTTP_CODE=""

# File used to persist HTTP_CODE across subshells (single-threaded only —
# concurrent calls within the same script will clobber this file)
_LIB_HTTP_CODE_FILE="$(mktemp "${TMPDIR:-/tmp}/.brightdata_http_code_XXXXXX")"
trap 'rm -f "$_LIB_HTTP_CODE_FILE"' EXIT

# make_api_request <method> <endpoint> [payload]
# Makes an authenticated API request to Bright Data.
# Sets global HTTP_CODE (also written to file for subshell access).
# Outputs response body to stdout.
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
  if ! response=$(curl "${curl_args[@]}" "$endpoint"); then
    echo "Error: network request failed" >&2
    HTTP_CODE="000"
    echo "$HTTP_CODE" > "$_LIB_HTTP_CODE_FILE"
    echo ""
    return 0
  fi
  HTTP_CODE=$(echo "$response" | tail -1)
  echo "$HTTP_CODE" > "$_LIB_HTTP_CODE_FILE"
  local body
  body=$(echo "$response" | sed '$d')

  echo "$body"
  return 0
}

# _read_http_code — read HTTP_CODE from file (use after subshell calls)
_read_http_code() {
  if [[ -f "$_LIB_HTTP_CODE_FILE" ]]; then
    HTTP_CODE=$(cat "$_LIB_HTTP_CODE_FILE")
  fi
}

# check_http_status <http_code> <body> <action_description>
# Checks HTTP status code and prints error to stderr if not 200.
# Returns 0 on 200, 1 on any error.
check_http_status() {
  local http_code="$1"
  local body="$2"
  local action="$3"

  if ! [[ "$http_code" =~ ^[0-9]+$ ]]; then
    echo "Error: ${action} failed (invalid HTTP response)" >&2
    return 1
  fi

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
  if ! snapshot_id=$(echo "$body" | jq -r '.snapshot_id // empty' 2>/dev/null); then
    echo "Error: invalid JSON response: ${body:0:200}" >&2
    return 1
  fi
  if [[ -z "$snapshot_id" ]]; then
    echo "Error: no snapshot_id in response: ${body}" >&2
    return 1
  fi
  echo "$snapshot_id"
}

# _validate_snapshot_id <snapshot_id>
# Validates snapshot_id matches expected format. Returns 1 if invalid.
_validate_snapshot_id() {
  local snapshot_id="$1"
  if [[ ! "$snapshot_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: invalid snapshot_id: ${snapshot_id}" >&2
    return 1
  fi
}

# save_pending <snapshot_id> <description> <dataset_type> <script_name>
# Appends a pending snapshot entry to pending.json. Atomic write via temp+mv.
# Creates the file and config dir if they don't exist.
# Skips if snapshot_id is already in pending.
save_pending() {
  local snapshot_id="$1"
  local description="$2"
  local dataset_type="$3"
  local script_name="$4"

  _validate_snapshot_id "$snapshot_id" || return 1

  mkdir -p "$LIB_CONFIG_DIR"

  local existing="[]"
  if [[ -f "$LIB_PENDING_FILE" ]]; then
    existing=$(jq '.' "$LIB_PENDING_FILE" 2>/dev/null || echo "[]")
  fi

  # Skip duplicate
  if echo "$existing" | jq -e --arg id "$snapshot_id" 'any(.[]; .snapshot_id == $id)' >/dev/null 2>&1; then
    return 0
  fi

  local tmp_file
  tmp_file=$(mktemp "${LIB_CONFIG_DIR}/.pending_XXXXXX")

  local triggered_at
  triggered_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if ! echo "$existing" | jq --arg sid "$snapshot_id" \
    --arg desc "$description" \
    --arg dtype "$dataset_type" \
    --arg scr "$script_name" \
    --arg ts "$triggered_at" \
    '. + [{"snapshot_id": $sid, "description": $desc, "dataset_type": $dtype, "triggered_at": $ts, "script": $scr}]' \
    > "$tmp_file"; then
    rm -f "$tmp_file"
    echo "Error: failed to update pending file" >&2
    return 1
  fi

  mv -f "$tmp_file" "$LIB_PENDING_FILE"
}

# load_pending
# Outputs pending.json contents to stdout. Returns empty array if file missing or invalid.
load_pending() {
  if [[ -f "$LIB_PENDING_FILE" ]]; then
    jq '.' "$LIB_PENDING_FILE" 2>/dev/null || echo "[]"
  else
    echo "[]"
  fi
}

# remove_pending <snapshot_id>
# Removes a pending entry by snapshot_id. Atomic write.
remove_pending() {
  local snapshot_id="$1"

  _validate_snapshot_id "$snapshot_id" || return 1

  if [[ ! -f "$LIB_PENDING_FILE" ]]; then
    return 0
  fi

  local tmp_file
  tmp_file=$(mktemp "${LIB_CONFIG_DIR}/.pending_XXXXXX")

  if ! jq --arg id "$snapshot_id" '[.[] | select(.snapshot_id != $id)]' \
    "$LIB_PENDING_FILE" > "$tmp_file"; then
    rm -f "$tmp_file"
    echo "Error: failed to update pending file" >&2
    return 1
  fi

  mv -f "$tmp_file" "$LIB_PENDING_FILE"
}
