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

@test "indeed_check_pending.sh --help exits 0" {
  run "$PROJECT_ROOT/scripts/indeed_check_pending.sh" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "indeed_check_pending.sh with no pending exits 0" {
  run "$PROJECT_ROOT/scripts/indeed_check_pending.sh"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"No pending"* ]]
}

@test "indeed_check_pending.sh fetches ready snapshot" {
  source "$PROJECT_ROOT/scripts/_lib.sh"
  save_pending "s_ready123" "test query" "jobs" "test.sh"

  create_curl_sequence_mock '{"status":"ready"}' '[{"job_title":"Engineer"}]'

  run "$PROJECT_ROOT/scripts/indeed_check_pending.sh"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Engineer"* ]]

  local count
  count=$(jq 'length' "$HOME/.config/indeed-brightdata/pending.json")
  [[ "$count" -eq 0 ]]
}

@test "indeed_check_pending.sh exits 2 when all still running" {
  source "$PROJECT_ROOT/scripts/_lib.sh"
  save_pending "s_running123" "test query" "jobs" "test.sh"

  export MOCK_CURL_RESPONSE='{"status":"running"}'
  create_curl_mock

  run "$PROJECT_ROOT/scripts/indeed_check_pending.sh"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"Still running"* ]]

  local count
  count=$(jq 'length' "$HOME/.config/indeed-brightdata/pending.json")
  [[ "$count" -eq 1 ]]
}

@test "indeed_check_pending.sh removes failed snapshots" {
  source "$PROJECT_ROOT/scripts/_lib.sh"
  save_pending "s_failed123" "test query" "jobs" "test.sh"

  export MOCK_CURL_RESPONSE='{"status":"failed"}'
  create_curl_mock

  run "$PROJECT_ROOT/scripts/indeed_check_pending.sh"
  [[ "$status" -eq 1 ]]

  local count
  count=$(jq 'length' "$HOME/.config/indeed-brightdata/pending.json")
  [[ "$count" -eq 0 ]]
}
