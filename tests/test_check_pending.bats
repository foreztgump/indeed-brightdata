#!/usr/bin/env bats

load helpers/setup

setup() {
  export TEST_TMPDIR="$(mktemp -d)"
  export HOME="$TEST_TMPDIR"
  export BRIGHTDATA_API_KEY="test-key"
  export PROJECT_ROOT
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# Helper: extract the structured JSON object from mixed bats output.
# bats `run` merges stdout and stderr, so we grep for the JSON object.
extract_json() {
  local output="$1"
  echo "$output" | grep -v '^Checking\|^Fetching\|^Still running\|^Summary\|^No pending\|^Error:\|^Warning:'
}

@test "indeed_check_pending.sh --help exits 0" {
  run "$PROJECT_ROOT/scripts/indeed_check_pending.sh" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Structured JSON"* ]]
}

@test "indeed_check_pending.sh with no pending outputs empty structured JSON" {
  create_curl_mock
  run "$PROJECT_ROOT/scripts/indeed_check_pending.sh"
  [[ "$status" -eq 0 ]]

  local json
  json=$(extract_json "$output")
  echo "$json" | jq -e '.completed == []'
  echo "$json" | jq -e '.still_pending == []'
  echo "$json" | jq -e '.failed == []'
}

@test "indeed_check_pending.sh fetches ready snapshot with structured output" {
  source "$PROJECT_ROOT/scripts/_lib.sh"
  save_pending "s_ready123" "nurse jobs in Ohio, US" "jobs" "test.sh"

  create_curl_sequence_mock '{"status":"ready"}' '[{"job_title":"Engineer"},{"job_title":"Analyst"}]'

  run "$PROJECT_ROOT/scripts/indeed_check_pending.sh"
  [[ "$status" -eq 0 ]]

  local json
  json=$(extract_json "$output")

  # Verify completed array
  echo "$json" | jq -e '.completed | length == 1'
  echo "$json" | jq -e '.completed[0].snapshot_id == "s_ready123"'
  echo "$json" | jq -e '.completed[0].query_description == "nurse jobs in Ohio, US"'
  echo "$json" | jq -e '.completed[0].result_count == 2'
  echo "$json" | jq -e '.completed[0].result_file | endswith("s_ready123.json")'

  # Other arrays should be empty
  echo "$json" | jq -e '.still_pending == []'
  echo "$json" | jq -e '.failed == []'

  # Pending should be cleared
  local pending_count
  pending_count=$(jq 'length' "$HOME/.config/indeed-brightdata/pending.json")
  [[ "$pending_count" -eq 0 ]]
}

@test "indeed_check_pending.sh saves result file to disk" {
  source "$PROJECT_ROOT/scripts/_lib.sh"
  save_pending "s_disk123" "test query" "jobs" "test.sh"

  create_curl_sequence_mock '{"status":"ready"}' '[{"job_title":"SavedJob"}]'

  run "$PROJECT_ROOT/scripts/indeed_check_pending.sh"
  [[ "$status" -eq 0 ]]

  # Verify the result file was written to disk
  [[ -f "$HOME/.config/indeed-brightdata/results/s_disk123.json" ]]
  local saved_content
  saved_content=$(cat "$HOME/.config/indeed-brightdata/results/s_disk123.json")
  echo "$saved_content" | jq -e '.[0].job_title == "SavedJob"'
}

@test "indeed_check_pending.sh exits 2 with still_pending when all running" {
  source "$PROJECT_ROOT/scripts/_lib.sh"
  save_pending "s_running123" "cybersecurity jobs in Remote, US" "jobs" "test.sh"

  export MOCK_CURL_RESPONSE='{"status":"running"}'
  create_curl_mock

  run "$PROJECT_ROOT/scripts/indeed_check_pending.sh"
  [[ "$status" -eq 2 ]]

  local json
  json=$(extract_json "$output")

  # Verify still_pending array
  echo "$json" | jq -e '.still_pending | length == 1'
  echo "$json" | jq -e '.still_pending[0].snapshot_id == "s_running123"'
  echo "$json" | jq -e '.still_pending[0].query_description == "cybersecurity jobs in Remote, US"'

  # Other arrays empty
  echo "$json" | jq -e '.completed == []'
  echo "$json" | jq -e '.failed == []'

  # Pending should still have the entry
  local pending_count
  pending_count=$(jq 'length' "$HOME/.config/indeed-brightdata/pending.json")
  [[ "$pending_count" -eq 1 ]]
}

@test "indeed_check_pending.sh reports failed snapshots in failed array" {
  source "$PROJECT_ROOT/scripts/_lib.sh"
  save_pending "s_failed123" "data science jobs" "jobs" "test.sh"

  export MOCK_CURL_RESPONSE='{"status":"failed","reason":"quota exceeded"}'
  create_curl_mock

  run "$PROJECT_ROOT/scripts/indeed_check_pending.sh"
  [[ "$status" -eq 1 ]]

  local json
  json=$(extract_json "$output")

  # Verify failed array
  echo "$json" | jq -e '.failed | length == 1'
  echo "$json" | jq -e '.failed[0].snapshot_id == "s_failed123"'
  echo "$json" | jq -e '.failed[0].query_description == "data science jobs"'
  echo "$json" | jq -e '.failed[0].reason == "quota exceeded"'

  # Other arrays empty
  echo "$json" | jq -e '.completed == []'
  echo "$json" | jq -e '.still_pending == []'

  # Pending should be cleared (failed entries are removed)
  local pending_count
  pending_count=$(jq 'length' "$HOME/.config/indeed-brightdata/pending.json")
  [[ "$pending_count" -eq 0 ]]
}

@test "indeed_check_pending.sh uses default reason when none provided" {
  source "$PROJECT_ROOT/scripts/_lib.sh"
  save_pending "s_failed_no_reason" "test query" "jobs" "test.sh"

  export MOCK_CURL_RESPONSE='{"status":"failed"}'
  create_curl_mock

  run "$PROJECT_ROOT/scripts/indeed_check_pending.sh"
  [[ "$status" -eq 1 ]]

  local json
  json=$(extract_json "$output")
  echo "$json" | jq -e '.failed[0].reason == "snapshot failed"'
}

@test "indeed_check_pending.sh handles non-array results with result_count 0" {
  source "$PROJECT_ROOT/scripts/_lib.sh"
  save_pending "s_obj123" "test query" "jobs" "test.sh"

  create_curl_sequence_mock '{"status":"ready"}' '{"message":"no results"}'

  run "$PROJECT_ROOT/scripts/indeed_check_pending.sh"
  [[ "$status" -eq 0 ]]

  local json
  json=$(extract_json "$output")
  echo "$json" | jq -e '.completed[0].result_count == 0'
}

@test "indeed_check_pending.sh calls cleanup_old_entries at start" {
  source "$PROJECT_ROOT/scripts/_lib.sh"

  # Create a stale pending entry (>24h old) that cleanup should remove
  mkdir -p "$HOME/.config/indeed-brightdata"
  local old_ts
  old_ts=$(date -u -d "25 hours ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
           date -u -v-25H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)

  jq -n --arg ts "$old_ts" \
    '[{"snapshot_id":"s_stale","description":"stale query","dataset_type":"jobs","triggered_at":$ts,"script":"test.sh"}]' \
    > "$HOME/.config/indeed-brightdata/pending.json"

  create_curl_mock

  run "$PROJECT_ROOT/scripts/indeed_check_pending.sh"
  # After cleanup removes the stale entry, there are no pending entries, so exit 0
  [[ "$status" -eq 0 ]]

  local json
  json=$(extract_json "$output")
  echo "$json" | jq -e '.completed == []'
  echo "$json" | jq -e '.still_pending == []'
  echo "$json" | jq -e '.failed == []'
}
