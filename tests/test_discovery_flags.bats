#!/usr/bin/env bats

load helpers/setup

setup() {
  export TEST_TMPDIR="$(mktemp -d)"
  export HOME="$TEST_TMPDIR"
  export BRIGHTDATA_API_KEY="test-key"
  export PROJECT_ROOT
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  create_datasets_config
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "indeed_jobs_by_keyword.sh --no-wait triggers and saves pending" {
  export MOCK_CURL_RESPONSE='{"snapshot_id":"s_test_nowait"}'
  create_curl_mock

  run "$PROJECT_ROOT/scripts/indeed_jobs_by_keyword.sh" "nurse" US "Ohio" --no-wait
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"pending"* ]]
  [[ "$output" == *"s_test_nowait"* ]]

  [[ -f "$HOME/.config/indeed-brightdata/pending.json" ]]
  local sid
  sid=$(jq -r '.[0].snapshot_id' "$HOME/.config/indeed-brightdata/pending.json")
  [[ "$sid" == "s_test_nowait" ]]
}

@test "indeed_company_by_keyword.sh --no-wait triggers and saves pending" {
  export MOCK_CURL_RESPONSE='{"snapshot_id":"s_company_nowait"}'
  create_curl_mock

  run "$PROJECT_ROOT/scripts/indeed_company_by_keyword.sh" "Google" --no-wait
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"pending"* ]]
  [[ "$output" == *"s_company_nowait"* ]]
}

@test "indeed_company_by_industry.sh --no-wait triggers and saves pending" {
  export MOCK_CURL_RESPONSE='{"snapshot_id":"s_industry_nowait"}'
  create_curl_mock

  run "$PROJECT_ROOT/scripts/indeed_company_by_industry.sh" "Technology" "Texas" --no-wait
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"pending"* ]]
}

@test "indeed_jobs_by_company.sh --no-wait triggers and saves pending" {
  export MOCK_CURL_RESPONSE='{"snapshot_id":"s_bycmp_nowait"}'
  create_curl_mock

  run "$PROJECT_ROOT/scripts/indeed_jobs_by_company.sh" "https://www.indeed.com/cmp/Google/jobs" --no-wait
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"pending"* ]]
}

@test "indeed_jobs_by_keyword.sh --limit-per-input is accepted" {
  export MOCK_CURL_RESPONSE='{"snapshot_id":"s_lpi_test"}'
  create_curl_mock

  run "$PROJECT_ROOT/scripts/indeed_jobs_by_keyword.sh" "nurse" US "Ohio" --limit-per-input 10 --no-wait
  [[ "$status" -eq 0 ]]
}

@test "indeed_poll_and_fetch.sh graceful timeout saves to pending" {
  export MOCK_CURL_RESPONSE='{"status":"running"}'
  create_curl_mock

  run "$PROJECT_ROOT/scripts/indeed_poll_and_fetch.sh" "s_timeout_test" \
    --timeout 1 --interval 1 \
    --description "test query" --dataset-type "jobs"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"Still processing"* ]]
  [[ "$output" == *"pending"* ]]

  [[ -f "$HOME/.config/indeed-brightdata/pending.json" ]]
  local sid
  sid=$(jq -r '.[0].snapshot_id' "$HOME/.config/indeed-brightdata/pending.json")
  [[ "$sid" == "s_timeout_test" ]]
}

@test "indeed_poll_and_fetch.sh timeout without description exits 1" {
  export MOCK_CURL_RESPONSE='{"status":"running"}'
  create_curl_mock

  run "$PROJECT_ROOT/scripts/indeed_poll_and_fetch.sh" "s_noargs_test" \
    --timeout 1 --interval 1
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"timed out"* ]]
}
