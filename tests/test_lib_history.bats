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

# --- save_result_file ---

@test "save_result_file creates results dir and writes valid JSON" {
  save_result_file "snap_abc123" '[{"title":"Engineer"}]'
  [[ -f "$LIB_RESULTS_DIR/snap_abc123.json" ]]
  local content
  content=$(cat "$LIB_RESULTS_DIR/snap_abc123.json")
  echo "$content" | jq -e '.[0].title == "Engineer"'
}

@test "save_result_file rejects invalid JSON" {
  run save_result_file "snap_abc123" "not valid json {"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"invalid JSON"* ]]
  [[ ! -f "$LIB_RESULTS_DIR/snap_abc123.json" ]]
}

@test "save_result_file rejects invalid snapshot_id" {
  run save_result_file "../evil" '{"ok":true}'
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"invalid snapshot_id"* ]]
}

# --- save_history ---

@test "save_history creates history file with entry" {
  save_history "jobs" '{"keyword":"nurse","country":"US","location":"Ohio"}' \
    "snap_001" 10 "/tmp/results/snap_001.json"

  [[ -f "$LIB_HISTORY_FILE" ]]
  local count
  count=$(jq 'length' "$LIB_HISTORY_FILE")
  [[ "$count" -eq 1 ]]

  local type
  type=$(jq -r '.[0].type' "$LIB_HISTORY_FILE")
  [[ "$type" == "jobs" ]]

  local kw
  kw=$(jq -r '.[0].params.keyword' "$LIB_HISTORY_FILE")
  [[ "$kw" == "nurse" ]]
}

@test "save_history appends to existing history" {
  save_history "jobs" '{"keyword":"nurse"}' "snap_001" 10 "/tmp/r1.json"
  save_history "jobs" '{"keyword":"doctor"}' "snap_002" 5 "/tmp/r2.json"

  local count
  count=$(jq 'length' "$LIB_HISTORY_FILE")
  [[ "$count" -eq 2 ]]
}

# --- check_history_cache ---

@test "check_history_cache returns result file on cache hit" {
  # Create a result file
  mkdir -p "$LIB_RESULTS_DIR"
  echo '[{"title":"Job"}]' > "$LIB_RESULTS_DIR/snap_hit.json"

  # Create history entry with current timestamp
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local result_path="${LIB_RESULTS_DIR}/snap_hit.json"

  jq -n --arg ts "$ts" --arg rf "$result_path" \
    '[{"timestamp": $ts, "type": "jobs", "params": {"keyword": "nurse", "country": "US", "location": "Ohio"}, "snapshot_id": "snap_hit", "result_count": 5, "result_file": $rf}]' \
    > "$LIB_HISTORY_FILE"

  run check_history_cache "nurse" "US" "Ohio"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "$result_path" ]]
}

@test "check_history_cache returns 1 on cache miss (different keyword)" {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  mkdir -p "$LIB_RESULTS_DIR"
  echo '[]' > "$LIB_RESULTS_DIR/snap_miss.json"

  jq -n --arg ts "$ts" --arg rf "$LIB_RESULTS_DIR/snap_miss.json" \
    '[{"timestamp": $ts, "type": "jobs", "params": {"keyword": "nurse", "country": "US", "location": "Ohio"}, "snapshot_id": "snap_miss", "result_count": 5, "result_file": $rf}]' \
    > "$LIB_HISTORY_FILE"

  run check_history_cache "doctor" "US" "Ohio"
  [[ "$status" -eq 1 ]]
}

@test "check_history_cache returns 1 when history file missing" {
  rm -f "$LIB_HISTORY_FILE"
  run check_history_cache "nurse" "US" "Ohio"
  [[ "$status" -eq 1 ]]
}

@test "check_history_cache returns 1 when result file missing" {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq -n --arg ts "$ts" \
    '[{"timestamp": $ts, "type": "jobs", "params": {"keyword": "nurse", "country": "US", "location": "Ohio"}, "snapshot_id": "snap_gone", "result_count": 5, "result_file": "/tmp/nonexistent_file.json"}]' \
    > "$LIB_HISTORY_FILE"

  run check_history_cache "nurse" "US" "Ohio"
  [[ "$status" -eq 1 ]]
}

@test "check_history_cache returns 1 for expired cache entry" {
  # Create a timestamp older than 6 hours
  local old_ts
  old_ts=$(date -u -d "7 hours ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
           date -u -v-7H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)

  mkdir -p "$LIB_RESULTS_DIR"
  echo '[]' > "$LIB_RESULTS_DIR/snap_old.json"

  jq -n --arg ts "$old_ts" --arg rf "$LIB_RESULTS_DIR/snap_old.json" \
    '[{"timestamp": $ts, "type": "jobs", "params": {"keyword": "nurse", "country": "US", "location": "Ohio"}, "snapshot_id": "snap_old", "result_count": 5, "result_file": $rf}]' \
    > "$LIB_HISTORY_FILE"

  run check_history_cache "nurse" "US" "Ohio"
  [[ "$status" -eq 1 ]]
}
