#!/usr/bin/env bats

setup() {
  export TEST_TMPDIR="$(mktemp -d)"
  export HOME="$TEST_TMPDIR"
  export BRIGHTDATA_API_KEY="test-key"
  export PROJECT_ROOT
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$PROJECT_ROOT/scripts/_lib.sh"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "save_pending creates pending.json when missing" {
  save_pending "s_abc123" "test query" "jobs" "test.sh"
  [[ -f "$LIB_PENDING_FILE" ]]
  local count
  count=$(jq 'length' "$LIB_PENDING_FILE")
  [[ "$count" -eq 1 ]]
}

@test "save_pending appends to existing pending.json" {
  save_pending "s_first" "first query" "jobs" "test.sh"
  save_pending "s_second" "second query" "company" "test2.sh"
  local count
  count=$(jq 'length' "$LIB_PENDING_FILE")
  [[ "$count" -eq 2 ]]
}

@test "save_pending skips duplicate snapshot_id" {
  save_pending "s_abc123" "test query" "jobs" "test.sh"
  save_pending "s_abc123" "test query again" "jobs" "test.sh"
  local count
  count=$(jq 'length' "$LIB_PENDING_FILE")
  [[ "$count" -eq 1 ]]
}

@test "save_pending stores correct fields" {
  save_pending "s_abc123" "nurse jobs in Ohio" "jobs" "indeed_jobs_by_keyword.sh"
  local sid
  sid=$(jq -r '.[0].snapshot_id' "$LIB_PENDING_FILE")
  [[ "$sid" == "s_abc123" ]]
  local desc
  desc=$(jq -r '.[0].description' "$LIB_PENDING_FILE")
  [[ "$desc" == "nurse jobs in Ohio" ]]
  local dtype
  dtype=$(jq -r '.[0].dataset_type' "$LIB_PENDING_FILE")
  [[ "$dtype" == "jobs" ]]
  local scr
  scr=$(jq -r '.[0].script' "$LIB_PENDING_FILE")
  [[ "$scr" == "indeed_jobs_by_keyword.sh" ]]
}

@test "save_pending sets triggered_at timestamp" {
  save_pending "s_abc123" "test" "jobs" "test.sh"
  local ts
  ts=$(jq -r '.[0].triggered_at' "$LIB_PENDING_FILE")
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "load_pending returns empty array when file missing" {
  local result
  result=$(load_pending)
  [[ "$result" == "[]" ]]
}

@test "load_pending returns file contents" {
  save_pending "s_abc123" "test" "jobs" "test.sh"
  local result
  result=$(load_pending)
  local count
  count=$(echo "$result" | jq 'length')
  [[ "$count" -eq 1 ]]
}

@test "remove_pending removes entry by snapshot_id" {
  save_pending "s_first" "first" "jobs" "test.sh"
  save_pending "s_second" "second" "company" "test.sh"
  remove_pending "s_first"
  local count
  count=$(jq 'length' "$LIB_PENDING_FILE")
  [[ "$count" -eq 1 ]]
  local remaining
  remaining=$(jq -r '.[0].snapshot_id' "$LIB_PENDING_FILE")
  [[ "$remaining" == "s_second" ]]
}

@test "remove_pending is no-op when file missing" {
  run remove_pending "s_nonexistent"
  [[ "$status" -eq 0 ]]
}
