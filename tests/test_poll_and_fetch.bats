#!/usr/bin/env bats

load helpers/setup

setup() {
  export TEST_TMPDIR="$(mktemp -d)"
  export HOME="$TEST_TMPDIR"
  mkdir -p "$TEST_TMPDIR/bin"
  export MOCK_CALL_COUNT_FILE="$TEST_TMPDIR/call_count"
  echo "0" > "$MOCK_CALL_COUNT_FILE"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# Helper: create a curl mock that returns different responses per call
create_stateful_curl_mock() {
  local mock_path="$TEST_TMPDIR/bin"
  local responses_file="$1"
  cat > "$mock_path/curl" <<MOCK
#!/usr/bin/env bash
count=\$(cat "$MOCK_CALL_COUNT_FILE")
count=\$((count + 1))
echo "\$count" > "$MOCK_CALL_COUNT_FILE"
response_line=\$(sed -n "\${count}p" "$responses_file")
body=\$(echo "\$response_line" | cut -d'|' -f1)
code=\$(echo "\$response_line" | cut -d'|' -f2)
echo "\$body"
echo "\${code:-200}"
MOCK
  chmod +x "$mock_path/curl"
  export PATH="$mock_path:$PATH"
}

@test "poll_and_fetch shows help with --help" {
  run "$SCRIPT_DIR/indeed_poll_and_fetch.sh" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Poll a Bright Data async snapshot"* ]]
}

@test "poll_and_fetch fails with no arguments" {
  run "$SCRIPT_DIR/indeed_poll_and_fetch.sh"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"snapshot_id is required"* ]]
}

@test "poll_and_fetch succeeds when snapshot ready immediately" {
  cat > "$TEST_TMPDIR/responses.txt" <<'EOF'
{"status":"ready"}|200
[{"job_title":"Engineer"}]|200
EOF
  create_stateful_curl_mock "$TEST_TMPDIR/responses.txt"

  run "$SCRIPT_DIR/indeed_poll_and_fetch.sh" "snap_123" --timeout 10 --interval 1
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Engineer"* ]]
}

@test "poll_and_fetch polls running then fetches when ready" {
  cat > "$TEST_TMPDIR/responses.txt" <<'EOF'
{"status":"running"}|200
{"status":"ready"}|200
[{"job_title":"Nurse"}]|200
EOF
  create_stateful_curl_mock "$TEST_TMPDIR/responses.txt"

  run "$SCRIPT_DIR/indeed_poll_and_fetch.sh" "snap_456" --timeout 10 --interval 1
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Nurse"* ]]
}

@test "poll_and_fetch fails on snapshot failure status" {
  cat > "$TEST_TMPDIR/responses.txt" <<'EOF'
{"status":"failed"}|200
EOF
  create_stateful_curl_mock "$TEST_TMPDIR/responses.txt"

  run "$SCRIPT_DIR/indeed_poll_and_fetch.sh" "snap_789" --timeout 10 --interval 1
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"failed"* ]]
}

@test "poll_and_fetch times out after max wait" {
  cat > "$TEST_TMPDIR/responses.txt" <<'EOF'
{"status":"running"}|200
{"status":"running"}|200
{"status":"running"}|200
{"status":"running"}|200
{"status":"running"}|200
EOF
  create_stateful_curl_mock "$TEST_TMPDIR/responses.txt"

  run "$SCRIPT_DIR/indeed_poll_and_fetch.sh" "snap_timeout" --timeout 3 --interval 1
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"timed out"* ]]
}
