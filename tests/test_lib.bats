#!/usr/bin/env bats

load helpers/setup

setup() {
  export TEST_TMPDIR="$(mktemp -d)"
  export HOME="$TEST_TMPDIR"
  mkdir -p "$HOME/.config/indeed-brightdata"
  create_curl_mock
  source "$SCRIPT_DIR/_lib.sh"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# --- make_api_request ---

@test "make_api_request GET sets HTTP_CODE and returns body" {
  export MOCK_CURL_RESPONSE='{"status":"ready"}'
  export MOCK_CURL_HTTP_CODE="200"
  local body
  body=$(make_api_request GET "https://example.com/test")
  _read_http_code
  [[ "$HTTP_CODE" == "200" ]]
  [[ "$body" == '{"status":"ready"}' ]]
}

@test "make_api_request POST passes payload and returns body" {
  export MOCK_CURL_RESPONSE='[{"job_title":"Engineer"}]'
  export MOCK_CURL_HTTP_CODE="200"
  local body
  body=$(make_api_request POST "https://example.com/scrape" '[{"url":"x"}]')
  _read_http_code
  [[ "$HTTP_CODE" == "200" ]]
  [[ "$body" == '[{"job_title":"Engineer"}]' ]]
}

@test "make_api_request fails when BRIGHTDATA_API_KEY unset" {
  unset BRIGHTDATA_API_KEY
  run make_api_request GET "https://example.com/test"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"BRIGHTDATA_API_KEY"* ]]
}

# --- check_http_status ---

@test "check_http_status returns 0 on 200" {
  run check_http_status 200 '{"ok":true}' "test action"
  [[ "$status" -eq 0 ]]
}

@test "check_http_status returns 1 on 401 with error message" {
  run check_http_status 401 '{"error":"unauthorized"}' "scrape"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"scrape failed (HTTP 401)"* ]]
}

@test "check_http_status returns 1 on 429 with rate limit message" {
  run check_http_status 429 '{"error":"too many"}' "trigger"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"rate limit exceeded (HTTP 429)"* ]]
}

@test "check_http_status returns 1 on 500 with server error" {
  run check_http_status 500 '{"error":"internal"}' "fetch"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"fetch failed (HTTP 500)"* ]]
}

@test "check_http_status returns 1 on 404" {
  run check_http_status 404 '{"error":"not found"}' "progress check"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"progress check failed (HTTP 404)"* ]]
}

# --- get_dataset_id ---

@test "get_dataset_id jobs returns hardcoded ID" {
  local id
  id=$(get_dataset_id jobs)
  [[ "$id" == "gd_l4dx9j9sscpvs7no2" ]]
}

@test "get_dataset_id company reads from config file" {
  create_datasets_config "gd_l4dx9j9sscpvs7no2" "gd_test_company_123"
  local id
  id=$(get_dataset_id company)
  [[ "$id" == "gd_test_company_123" ]]
}

@test "get_dataset_id company fails when config missing" {
  run get_dataset_id company
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"company dataset ID not configured"* ]]
}

@test "get_dataset_id company fails when config has empty company" {
  echo '{"jobs":"x","company":""}' > "$HOME/.config/indeed-brightdata/datasets.json"
  run get_dataset_id company
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"company dataset ID not configured"* ]]
}

@test "get_dataset_id unknown type fails" {
  run get_dataset_id unknown
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"unknown dataset type"* ]]
}

# --- extract_snapshot_id ---

@test "extract_snapshot_id returns ID from valid response" {
  local id
  id=$(extract_snapshot_id '{"snapshot_id":"snap_abc123"}')
  [[ "$id" == "snap_abc123" ]]
}

@test "extract_snapshot_id fails on missing snapshot_id" {
  run extract_snapshot_id '{"error":"bad request"}'
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"no snapshot_id in response"* ]]
}
