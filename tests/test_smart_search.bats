#!/usr/bin/env bats

load helpers/setup

# Helper: generate a JSON array of N non-expired jobs with unique IDs
# Usage: generate_jobs 5
generate_jobs() {
  local count="$1"
  local jobs="["
  for ((i=1; i<=count; i++)); do
    local day
    day=$(printf "%02d" $((i % 28 + 1)))
    [[ $i -gt 1 ]] && jobs+=","
    jobs+="{\"jobid\":\"j${i}\",\"title\":\"Job ${i}\",\"is_expired\":false,\"date_posted_parsed\":\"2026-03-${day}\"}"
  done
  jobs+="]"
  echo "$jobs"
}

setup() {
  export TEST_TMPDIR="$(mktemp -d)"
  export HOME="$TEST_TMPDIR"
  export BRIGHTDATA_API_KEY="test-key"
  export PROJECT_ROOT
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  create_datasets_config

  # Create mock indeed_jobs_by_keyword.sh that records calls and returns snapshot IDs
  MOCK_KEYWORD_DIR="$TEST_TMPDIR/keyword_calls"
  mkdir -p "$MOCK_KEYWORD_DIR"
  export MOCK_KEYWORD_DIR

  # Create a wrapper scripts dir with our mock
  MOCK_SCRIPTS_DIR="$TEST_TMPDIR/mock_scripts"
  mkdir -p "$MOCK_SCRIPTS_DIR"
  export MOCK_SCRIPTS_DIR

  # Copy _lib.sh to mock scripts dir
  cp "$PROJECT_ROOT/scripts/_lib.sh" "$MOCK_SCRIPTS_DIR/"

  # Create a mock indeed_jobs_by_keyword.sh
  cat > "$MOCK_SCRIPTS_DIR/indeed_jobs_by_keyword.sh" <<'MOCK_KW'
#!/usr/bin/env bash
# Mock keyword script: records calls and returns snapshot IDs
set -euo pipefail

CALL_INDEX_FILE="${MOCK_KEYWORD_DIR}/call_index"
if [[ ! -f "$CALL_INDEX_FILE" ]]; then
  echo "0" > "$CALL_INDEX_FILE"
fi
INDEX=$(cat "$CALL_INDEX_FILE")
NEXT=$((INDEX + 1))
echo "$NEXT" > "$CALL_INDEX_FILE"

# Record the call arguments
echo "$*" > "${MOCK_KEYWORD_DIR}/call_${INDEX}"

# Output a pending response with unique snapshot ID
jq -n --arg sid "s_test_${INDEX}" --arg desc "test search ${INDEX}" \
  '{"status":"pending","snapshot_id":$sid,"description":$desc}'
MOCK_KW
  chmod +x "$MOCK_SCRIPTS_DIR/indeed_jobs_by_keyword.sh"

  # Copy the real smart search script to mock scripts dir
  cp "$PROJECT_ROOT/scripts/indeed_smart_search.sh" "$MOCK_SCRIPTS_DIR/indeed_smart_search.sh"
  chmod +x "$MOCK_SCRIPTS_DIR/indeed_smart_search.sh"

  # Copy references so keyword expansion works
  mkdir -p "$MOCK_SCRIPTS_DIR/../references"
  cp "$PROJECT_ROOT/references/keyword-expansions.json" "$MOCK_SCRIPTS_DIR/../references/"

  # Create default mock curl
  create_curl_mock
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# Helper: extract JSON object from mixed bats output (stdout+stderr merged).
# Finds the block from the first line that is just "{" to the matching "}" at depth 0.
extract_json() {
  echo "$1" | awk '
    /^\{$/ && !started { started=1; depth=0 }
    started { print; for(i=1;i<=length($0);i++) { c=substr($0,i,1); if(c=="{") depth++; if(c=="}") depth-- }; if(depth==0 && started) exit }
  '
}

# --- Help ---

@test "indeed_smart_search.sh shows help with --help" {
  run "$PROJECT_ROOT/scripts/indeed_smart_search.sh" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"keyword"* ]]
  [[ "$output" == *"--no-expand"* ]]
  [[ "$output" == *"--force"* ]]
  [[ "$output" == *"--all-time"* ]]
}

# --- Argument parsing ---

@test "indeed_smart_search.sh fails without required args" {
  run "$PROJECT_ROOT/scripts/indeed_smart_search.sh"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"required"* ]]
}

@test "indeed_smart_search.sh fails with only one arg" {
  run "$PROJECT_ROOT/scripts/indeed_smart_search.sh" "cybersecurity"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"required"* ]]
}

@test "indeed_smart_search.sh fails with unknown option" {
  run "$PROJECT_ROOT/scripts/indeed_smart_search.sh" "cyber" US "Remote" --bogus
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"Unknown option"* ]]
}

# --- Keyword expansion (unit tests — no polling needed) ---

@test "expand_keywords returns known keyword expansions" {
  run bash -c '
    export HOME="'"$TEST_TMPDIR"'"
    export BRIGHTDATA_API_KEY="test-key"
    source "'"$MOCK_SCRIPTS_DIR"'/_lib.sh"
    SCRIPT_DIR="'"$MOCK_SCRIPTS_DIR"'"
    NO_EXPAND=false
    MAX_KEYWORDS=5
    source <(sed -n "/^expand_keywords/,/^}/p" "'"$MOCK_SCRIPTS_DIR"'/indeed_smart_search.sh")
    expand_keywords "cybersecurity"
  '
  [[ "$status" -eq 0 ]]
  local line_count
  line_count=$(echo "$output" | wc -l)
  [[ "$line_count" -ge 2 ]]
  [[ "$output" == *"cybersecurity"* ]]
  [[ "$output" == *"security"* ]]
}

@test "expand_keywords with --no-expand returns only original" {
  run bash -c '
    export HOME="'"$TEST_TMPDIR"'"
    export BRIGHTDATA_API_KEY="test-key"
    source "'"$MOCK_SCRIPTS_DIR"'/_lib.sh"
    SCRIPT_DIR="'"$MOCK_SCRIPTS_DIR"'"
    NO_EXPAND=true
    MAX_KEYWORDS=5
    source <(sed -n "/^expand_keywords/,/^}/p" "'"$MOCK_SCRIPTS_DIR"'/indeed_smart_search.sh")
    expand_keywords "cybersecurity"
  '
  [[ "$status" -eq 0 ]]
  local line_count
  line_count=$(echo "$output" | wc -l)
  [[ "$line_count" -eq 1 ]]
  [[ "$output" == "cybersecurity" ]]
}

@test "expand_keywords uses fallback for unknown keyword" {
  run bash -c '
    export HOME="'"$TEST_TMPDIR"'"
    export BRIGHTDATA_API_KEY="test-key"
    source "'"$MOCK_SCRIPTS_DIR"'/_lib.sh"
    SCRIPT_DIR="'"$MOCK_SCRIPTS_DIR"'"
    NO_EXPAND=false
    MAX_KEYWORDS=5
    source <(sed -n "/^expand_keywords/,/^}/p" "'"$MOCK_SCRIPTS_DIR"'/indeed_smart_search.sh")
    expand_keywords "zookeeper"
  '
  [[ "$status" -eq 0 ]]
  local line_count
  line_count=$(echo "$output" | wc -l)
  [[ "$line_count" -ge 2 ]]
  [[ "$output" == *"zookeeper"* ]]
  [[ "$output" == *"zookeeper analyst"* ]]
  [[ "$output" == *"zookeeper engineer"* ]]
}

@test "expand_keywords caps at MAX_KEYWORDS" {
  run bash -c '
    export HOME="'"$TEST_TMPDIR"'"
    export BRIGHTDATA_API_KEY="test-key"
    source "'"$MOCK_SCRIPTS_DIR"'/_lib.sh"
    SCRIPT_DIR="'"$MOCK_SCRIPTS_DIR"'"
    NO_EXPAND=false
    MAX_KEYWORDS=3
    source <(sed -n "/^expand_keywords/,/^}/p" "'"$MOCK_SCRIPTS_DIR"'/indeed_smart_search.sh")
    expand_keywords "cybersecurity"
  '
  [[ "$status" -eq 0 ]]
  local line_count
  line_count=$(echo "$output" | wc -l)
  [[ "$line_count" -le 3 ]]
}

# --- Integration with mock keyword script ---
# Note: Integration tests use >= 5 results to avoid triggering the
# "too few results" date expansion codepath, which would need extra mock responses.

@test "smart search with --no-expand triggers single keyword search" {
  local jobs
  jobs=$(generate_jobs 6)
  create_curl_sequence_mock \
    '{"status":"ready"}' \
    "$jobs"

  run "$MOCK_SCRIPTS_DIR/indeed_smart_search.sh" "cybersecurity" US "Remote" --no-expand --force
  [[ "$status" -eq 0 ]]

  # Should have triggered exactly 1 search (no expansion)
  local call_count
  call_count=$(cat "$MOCK_KEYWORD_DIR/call_index")
  [[ "$call_count" -eq 1 ]]

  # Verify the keyword used
  local call_args
  call_args=$(cat "$MOCK_KEYWORD_DIR/call_0")
  [[ "$call_args" == *"cybersecurity"* ]]
  [[ "$call_args" == *"--no-wait"* ]]
  [[ "$call_args" == *"--limit-per-input"* ]]
}

@test "smart search expands known keyword and triggers multiple searches" {
  # cybersecurity expands to 5 keywords — need 2 curl calls per snapshot (progress + fetch)
  local jobs
  jobs=$(generate_jobs 6)
  create_curl_sequence_mock \
    '{"status":"ready"}' "$jobs" \
    '{"status":"ready"}' "$jobs" \
    '{"status":"ready"}' "$jobs" \
    '{"status":"ready"}' "$jobs" \
    '{"status":"ready"}' "$jobs"

  run "$MOCK_SCRIPTS_DIR/indeed_smart_search.sh" "cybersecurity" US "Remote" --force
  [[ "$status" -eq 0 ]]

  local call_count
  call_count=$(cat "$MOCK_KEYWORD_DIR/call_index")
  [[ "$call_count" -ge 2 ]]
  [[ "$call_count" -le 5 ]]
}

@test "smart search outputs metadata envelope" {
  local jobs
  jobs=$(generate_jobs 6)
  create_curl_sequence_mock \
    '{"status":"ready"}' \
    "$jobs"

  run "$MOCK_SCRIPTS_DIR/indeed_smart_search.sh" "cybersecurity" US "Remote" --no-expand --force
  [[ "$status" -eq 0 ]]

  # Parse JSON output (bats run merges stdout+stderr; extract the JSON object)
  local json_output
  json_output=$(extract_json "$output" | jq -e '.')

  echo "$json_output" | jq -e '.meta.query == "cybersecurity"'
  echo "$json_output" | jq -e '.meta.location == "Remote"'
  echo "$json_output" | jq -e '.meta.country == "US"'
  echo "$json_output" | jq -e '.meta.date_filter == "Last 7 days"'
  echo "$json_output" | jq -e '.meta.keywords_used | length >= 1'
  echo "$json_output" | jq -e '.meta.total_raw >= 0'
  echo "$json_output" | jq -e '.meta.after_filter >= 0'
  echo "$json_output" | jq -e '.results | type == "array"'
}

@test "smart search --force bypasses cache" {
  # Create a cached result
  mkdir -p "$HOME/.config/indeed-brightdata/results"
  local cached_content='{"meta":{"query":"cybersecurity","location":"Remote","country":"US","date_filter":"Last 7 days","expanded_to":null,"keywords_used":["cybersecurity"],"total_raw":1,"after_filter":1},"results":[{"jobid":"cached_job","title":"Cached"}]}'
  echo "$cached_content" > "$HOME/.config/indeed-brightdata/results/smart_cached.json"

  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local result_path="$HOME/.config/indeed-brightdata/results/smart_cached.json"
  jq -n --arg ts "$ts" --arg rf "$result_path" \
    '[{"timestamp": $ts, "type": "smart_search", "params": {"keyword": "cybersecurity", "country": "US", "location": "Remote", "date_posted": "Last 7 days"}, "snapshot_id": "smart_cached", "result_count": 1, "result_file": $rf}]' \
    > "$HOME/.config/indeed-brightdata/history.json"

  # Without --force, should return cached
  run "$MOCK_SCRIPTS_DIR/indeed_smart_search.sh" "cybersecurity" US "Remote" --no-expand
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"cached_job"* ]]

  # Reset call index for fresh mock tracking
  echo "0" > "$MOCK_KEYWORD_DIR/call_index"

  # With --force, should trigger fresh search
  local jobs
  jobs=$(generate_jobs 6)
  create_curl_sequence_mock \
    '{"status":"ready"}' \
    "$jobs"

  run "$MOCK_SCRIPTS_DIR/indeed_smart_search.sh" "cybersecurity" US "Remote" --no-expand --force
  [[ "$status" -eq 0 ]]

  # The mock keyword script should have been called
  local call_count
  call_count=$(cat "$MOCK_KEYWORD_DIR/call_index")
  [[ "$call_count" -ge 1 ]]
}

@test "smart search postprocess deduplicates by jobid" {
  # 3 unique + 2 duplicates = 5 total raw, 3 after dedup (>= MIN_RESULTS_THRESHOLD raw)
  create_curl_sequence_mock \
    '{"status":"ready"}' \
    '[{"jobid":"j1","title":"Analyst V1","is_expired":false,"date_posted_parsed":"2026-03-05"},{"jobid":"j1","title":"Analyst V2","is_expired":false,"date_posted_parsed":"2026-03-04"},{"jobid":"j2","title":"Engineer","is_expired":false,"date_posted_parsed":"2026-03-03"},{"jobid":"j3","title":"Manager","is_expired":false,"date_posted_parsed":"2026-03-02"},{"jobid":"j4","title":"Lead","is_expired":false,"date_posted_parsed":"2026-03-01"},{"jobid":"j5","title":"Director","is_expired":false,"date_posted_parsed":"2026-02-28"}]'

  run "$MOCK_SCRIPTS_DIR/indeed_smart_search.sh" "cybersecurity" US "Remote" --no-expand --force
  [[ "$status" -eq 0 ]]

  local json_output
  json_output=$(extract_json "$output" | jq -e '.')

  # Should have 5 unique jobids (j1 deduplicated from 2 to 1)
  local result_count
  result_count=$(echo "$json_output" | jq '.results | length')
  [[ "$result_count" -eq 5 ]]
}

@test "smart search filters expired jobs" {
  # 5 active + 1 expired = 6 raw, 5 after filter (>= threshold)
  create_curl_sequence_mock \
    '{"status":"ready"}' \
    '[{"jobid":"j1","title":"Active 1","is_expired":false,"date_posted_parsed":"2026-03-05"},{"jobid":"j2","title":"Active 2","is_expired":false,"date_posted_parsed":"2026-03-04"},{"jobid":"j3","title":"Active 3","is_expired":false,"date_posted_parsed":"2026-03-03"},{"jobid":"j4","title":"Active 4","is_expired":false,"date_posted_parsed":"2026-03-02"},{"jobid":"j5","title":"Active 5","is_expired":false,"date_posted_parsed":"2026-03-01"},{"jobid":"j6","title":"Expired","is_expired":true,"date_posted_parsed":"2026-02-28"}]'

  run "$MOCK_SCRIPTS_DIR/indeed_smart_search.sh" "cybersecurity" US "Remote" --no-expand --force
  [[ "$status" -eq 0 ]]

  local json_output
  json_output=$(extract_json "$output" | jq -e '.')

  local result_count
  result_count=$(echo "$json_output" | jq '.results | length')
  [[ "$result_count" -eq 5 ]]

  # Verify no expired jobs in results
  local expired_count
  expired_count=$(echo "$json_output" | jq '[.results[] | select(.is_expired == true)] | length')
  [[ "$expired_count" -eq 0 ]]
}

@test "smart search --all-time passes correct date filter" {
  # --all-time skips the date expansion logic entirely
  local jobs
  jobs=$(generate_jobs 2)
  create_curl_sequence_mock \
    '{"status":"ready"}' \
    "$jobs"

  run "$MOCK_SCRIPTS_DIR/indeed_smart_search.sh" "cybersecurity" US "Remote" --no-expand --force --all-time
  [[ "$status" -eq 0 ]]

  local json_output
  json_output=$(extract_json "$output" | jq -e '.')
  echo "$json_output" | jq -e '.meta.date_filter == "all time"'

  # Verify --all-time was passed to keyword script
  local call_args
  call_args=$(cat "$MOCK_KEYWORD_DIR/call_0")
  [[ "$call_args" == *"--all-time"* ]]
}

@test "smart search saves history after completion" {
  local jobs
  jobs=$(generate_jobs 6)
  create_curl_sequence_mock \
    '{"status":"ready"}' \
    "$jobs"

  run "$MOCK_SCRIPTS_DIR/indeed_smart_search.sh" "cybersecurity" US "Remote" --no-expand --force
  [[ "$status" -eq 0 ]]

  # Check history was saved
  [[ -f "$HOME/.config/indeed-brightdata/history.json" ]]
  local history_type
  history_type=$(jq -r '.[-1].type' "$HOME/.config/indeed-brightdata/history.json")
  [[ "$history_type" == "smart_search" ]]

  local history_kw
  history_kw=$(jq -r '.[-1].params.keyword' "$HOME/.config/indeed-brightdata/history.json")
  [[ "$history_kw" == "cybersecurity" ]]
}

@test "smart search --limit caps output results" {
  local jobs
  jobs=$(generate_jobs 8)
  create_curl_sequence_mock \
    '{"status":"ready"}' \
    "$jobs"

  run "$MOCK_SCRIPTS_DIR/indeed_smart_search.sh" "cybersecurity" US "Remote" --no-expand --force --limit 3
  [[ "$status" -eq 0 ]]

  local json_output
  json_output=$(extract_json "$output" | jq -e '.')

  local result_count
  result_count=$(echo "$json_output" | jq '.results | length')
  [[ "$result_count" -eq 3 ]]
}

@test "smart search saves result file to disk" {
  local jobs
  jobs=$(generate_jobs 6)
  create_curl_sequence_mock \
    '{"status":"ready"}' \
    "$jobs"

  run "$MOCK_SCRIPTS_DIR/indeed_smart_search.sh" "cybersecurity" US "Remote" --no-expand --force
  [[ "$status" -eq 0 ]]

  # A result file should exist in the results dir
  local result_files
  result_files=$(ls "$HOME/.config/indeed-brightdata/results"/smart_*.json 2>/dev/null | wc -l)
  [[ "$result_files" -ge 1 ]]
}
