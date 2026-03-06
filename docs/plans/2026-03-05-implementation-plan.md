# Shared Library + Testing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract 3 shared functions into `scripts/_lib.sh`, update all 8 scripts to use them, and add bats-core tests.

**Architecture:** A single sourced library (`_lib.sh`) provides `make_api_request`, `check_http_status`, and `get_dataset_id`. All scripts source it and replace inline curl/error/dataset patterns. Tests use bats-core with a mock curl stub.

**Tech Stack:** Bash, bats-core (installed via npm/git), jq, curl

---

### Task 1: Install bats-core

**Files:**
- None (system install)

**Step 1: Install bats-core and helpers**

```bash
sudo npm install -g bats
```

If npm not available:
```bash
git clone https://github.com/bats-core/bats-core.git /tmp/bats-core
sudo /tmp/bats-core/install.sh /usr/local
rm -rf /tmp/bats-core
```

**Step 2: Verify installation**

Run: `bats --version`
Expected: `Bats 1.x.x`

---

### Task 2: Create test helpers (mock curl)

**Files:**
- Create: `tests/helpers/setup.bash`

**Step 1: Create test helpers directory and setup file**

```bash
#!/usr/bin/env bash
# tests/helpers/setup.bash — shared test setup for bats tests

export BRIGHTDATA_API_KEY="test-api-key-do-not-use"
export SCRIPT_DIR="${BATS_TEST_DIRNAME}/../scripts"

# Temp dir for test artifacts
setup() {
  export TEST_TMPDIR="$(mktemp -d)"
  export CONFIG_DIR="$TEST_TMPDIR/config"
  mkdir -p "$CONFIG_DIR"
  export HOME="$TEST_TMPDIR"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# Mock curl: reads from MOCK_CURL_RESPONSE and MOCK_CURL_HTTP_CODE
# Usage: set MOCK_CURL_RESPONSE and MOCK_CURL_HTTP_CODE before calling scripts
create_curl_mock() {
  local mock_path="$TEST_TMPDIR/bin"
  mkdir -p "$mock_path"
  cat > "$mock_path/curl" <<'MOCK'
#!/usr/bin/env bash
# Mock curl that returns configured responses
# Checks if -w flag is present (for http_code extraction pattern)
has_write_out=false
for arg in "$@"; do
  if [[ "$arg" == *"%{http_code}"* ]]; then
    has_write_out=true
    break
  fi
done

if [[ "$has_write_out" == true ]]; then
  echo "${MOCK_CURL_RESPONSE:-{}}"
  echo "${MOCK_CURL_HTTP_CODE:-200}"
else
  echo "${MOCK_CURL_RESPONSE:-{}}"
fi
MOCK
  chmod +x "$mock_path/curl"
  export PATH="$mock_path:$PATH"
}

# Helper: create a datasets.json config file
create_datasets_config() {
  local jobs_id="${1:-gd_l4dx9j9sscpvs7no2}"
  local company_id="${2:-gd_test_company_id}"
  mkdir -p "$HOME/.config/indeed-brightdata"
  cat > "$HOME/.config/indeed-brightdata/datasets.json" <<EOF
{"jobs": "$jobs_id", "company": "$company_id"}
EOF
}
```

**Step 2: Verify file created**

Run: `ls -la tests/helpers/setup.bash`
Expected: File exists

---

### Task 3: Create `scripts/_lib.sh` with 3 shared functions

**Files:**
- Create: `scripts/_lib.sh`

**Step 1: Write the shared library**

```bash
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
# Returns 0 on success (HTTP 200), 1 on error.
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
```

Note: I added `extract_snapshot_id` as a 4th function since it was duplicated 5 times and is tightly coupled with the API request flow.

**Step 2: Verify file created and is sourceable**

Run: `bash -n scripts/_lib.sh && echo "Syntax OK"`
Expected: `Syntax OK`

**Step 3: Commit**

```bash
git add scripts/_lib.sh tests/helpers/setup.bash
git commit -m "feat: add shared library (_lib.sh) and test helpers"
```

---

### Task 4: Write tests for `_lib.sh`

**Files:**
- Create: `tests/test_lib.bats`

**Step 1: Write the test file**

```bash
#!/usr/bin/env bats
# tests/test_lib.bats — tests for scripts/_lib.sh shared functions

load helpers/setup

setup() {
  export TEST_TMPDIR="$(mktemp -d)"
  export CONFIG_DIR="$TEST_TMPDIR/config"
  mkdir -p "$CONFIG_DIR"
  export HOME="$TEST_TMPDIR"
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
  [[ "$HTTP_CODE" == "200" ]]
  [[ "$body" == '{"status":"ready"}' ]]
}

@test "make_api_request POST passes payload and returns body" {
  export MOCK_CURL_RESPONSE='[{"job_title":"Engineer"}]'
  export MOCK_CURL_HTTP_CODE="200"
  local body
  body=$(make_api_request POST "https://example.com/scrape" '[{"url":"x"}]')
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
  mkdir -p "$HOME/.config/indeed-brightdata"
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
```

**Step 2: Run tests to verify they fail (lib not yet sourced properly with mock)**

Run: `bats tests/test_lib.bats`
Expected: Tests should pass since _lib.sh exists. If bats not installed yet, install first (Task 1).

**Step 3: Commit**

```bash
git add tests/test_lib.bats
git commit -m "test: add comprehensive tests for _lib.sh shared functions"
```

---

### Task 5: Write tests for poll_and_fetch

**Files:**
- Create: `tests/test_poll_and_fetch.bats`

**Step 1: Write the test file**

```bash
#!/usr/bin/env bats
# tests/test_poll_and_fetch.bats — tests for indeed_poll_and_fetch.sh

load helpers/setup

setup() {
  export TEST_TMPDIR="$(mktemp -d)"
  export HOME="$TEST_TMPDIR"
  mkdir -p "$TEST_TMPDIR/bin"

  # We need a stateful curl mock for polling tests
  export MOCK_CALL_COUNT_FILE="$TEST_TMPDIR/call_count"
  echo "0" > "$MOCK_CALL_COUNT_FILE"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# Helper: create a curl mock that returns different responses per call
create_stateful_curl_mock() {
  local mock_path="$TEST_TMPDIR/bin"
  # $1 = responses file (one JSON+code per line pair)
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
  # Call 1: progress returns ready, Call 2: snapshot returns data
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
  # Call 1: running, Call 2: ready, Call 3: fetch data
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
  # Always returns running
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
```

**Step 2: Commit**

```bash
git add tests/test_poll_and_fetch.bats
git commit -m "test: add poll_and_fetch tests with stateful curl mock"
```

---

### Task 6: Write smoke tests for all scripts

**Files:**
- Create: `tests/test_scripts_smoke.bats`

**Step 1: Write the smoke test file**

```bash
#!/usr/bin/env bats
# tests/test_scripts_smoke.bats — smoke tests for all 8 scripts

load helpers/setup

# --help tests (should exit 0 and show usage)

@test "indeed_jobs_by_url.sh --help exits 0" {
  run "$SCRIPT_DIR/indeed_jobs_by_url.sh" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "indeed_jobs_by_keyword.sh --help exits 0" {
  run "$SCRIPT_DIR/indeed_jobs_by_keyword.sh" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "indeed_jobs_by_company.sh --help exits 0" {
  run "$SCRIPT_DIR/indeed_jobs_by_company.sh" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "indeed_company_by_url.sh --help exits 0" {
  run "$SCRIPT_DIR/indeed_company_by_url.sh" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "indeed_company_by_keyword.sh --help exits 0" {
  run "$SCRIPT_DIR/indeed_company_by_keyword.sh" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "indeed_company_by_industry.sh --help exits 0" {
  run "$SCRIPT_DIR/indeed_company_by_industry.sh" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "indeed_poll_and_fetch.sh --help exits 0" {
  run "$SCRIPT_DIR/indeed_poll_and_fetch.sh" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "indeed_list_datasets.sh --help exits 0" {
  run "$SCRIPT_DIR/indeed_list_datasets.sh" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
}

# Missing args tests (should exit non-zero)

@test "indeed_jobs_by_url.sh with no args exits non-zero" {
  run "$SCRIPT_DIR/indeed_jobs_by_url.sh"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"required"* ]]
}

@test "indeed_jobs_by_keyword.sh with no args exits non-zero" {
  run "$SCRIPT_DIR/indeed_jobs_by_keyword.sh"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"required"* ]]
}

@test "indeed_jobs_by_company.sh with no args exits non-zero" {
  run "$SCRIPT_DIR/indeed_jobs_by_company.sh"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"required"* ]]
}

@test "indeed_company_by_url.sh with no args exits non-zero" {
  run "$SCRIPT_DIR/indeed_company_by_url.sh"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"required"* ]]
}

@test "indeed_company_by_keyword.sh with no args exits non-zero" {
  run "$SCRIPT_DIR/indeed_company_by_keyword.sh"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"required"* ]]
}

@test "indeed_company_by_industry.sh with no args exits non-zero" {
  run "$SCRIPT_DIR/indeed_company_by_industry.sh"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"required"* ]]
}

@test "indeed_poll_and_fetch.sh with no args exits non-zero" {
  run "$SCRIPT_DIR/indeed_poll_and_fetch.sh"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"required"* ]]
}
```

**Step 2: Commit**

```bash
git add tests/test_scripts_smoke.bats
git commit -m "test: add smoke tests for --help and missing args across all scripts"
```

---

### Task 7: Update `indeed_poll_and_fetch.sh` to use `_lib.sh`

**Files:**
- Modify: `scripts/indeed_poll_and_fetch.sh`

**Step 1: Rewrite to use shared library**

Replace the entire file with:

```bash
#!/usr/bin/env bash
# Usage: indeed_poll_and_fetch.sh <snapshot_id> [--timeout SECONDS] [--interval SECONDS]
# Polls Bright Data async job status until ready, then fetches results.
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lib.sh"

readonly DEFAULT_TIMEOUT=300
readonly DEFAULT_INTERVAL=10

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_poll_and_fetch.sh <snapshot_id> [OPTIONS]

Poll a Bright Data async snapshot until ready, then fetch results.

Arguments:
  snapshot_id          The snapshot ID returned by a /trigger call

Options:
  --timeout SECONDS    Max time to wait (default: 300)
  --interval SECONDS   Poll interval (default: 10)
  --help               Show this help message

Output:
  JSON array to stdout
EOF
  exit 0
}

parse_args() {
  SNAPSHOT_ID=""
  TIMEOUT="$DEFAULT_TIMEOUT"
  INTERVAL="$DEFAULT_INTERVAL"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) show_help ;;
      --timeout) TIMEOUT="$2"; shift 2 ;;
      --interval) INTERVAL="$2"; shift 2 ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *) SNAPSHOT_ID="$1"; shift ;;
    esac
  done

  if [[ -z "$SNAPSHOT_ID" ]]; then
    echo "Error: snapshot_id is required" >&2
    echo "Run with --help for usage" >&2
    exit 1
  fi
}

poll_status() {
  local body
  body=$(make_api_request GET "${LIB_BASE_URL}/progress/${SNAPSHOT_ID}")
  check_http_status "$HTTP_CODE" "$body" "progress check" || return 1
  echo "$body" | jq -r '.status // "unknown"'
}

fetch_snapshot() {
  local body
  body=$(make_api_request GET "${LIB_BASE_URL}/snapshot/${SNAPSHOT_ID}?format=json")
  check_http_status "$HTTP_CODE" "$body" "snapshot fetch" || return 1
  echo "$body"
}

main() {
  parse_args "$@"

  local elapsed=0
  echo "Polling snapshot ${SNAPSHOT_ID}..." >&2

  while [[ "$elapsed" -lt "$TIMEOUT" ]]; do
    local status
    status=$(poll_status) || exit 1

    case "$status" in
      ready)
        echo "Snapshot ready. Fetching results..." >&2
        fetch_snapshot
        return 0
        ;;
      failed)
        echo "Error: snapshot ${SNAPSHOT_ID} failed" >&2
        return 1
        ;;
      *)
        echo "Status: ${status} (${elapsed}s/${TIMEOUT}s)" >&2
        sleep "$INTERVAL"
        elapsed=$((elapsed + INTERVAL))
        ;;
    esac
  done

  echo "Error: timed out after ${TIMEOUT}s waiting for snapshot ${SNAPSHOT_ID}" >&2
  return 1
}

main "$@"
```

**Step 2: Run poll_and_fetch tests**

Run: `bats tests/test_poll_and_fetch.bats`
Expected: All 6 tests pass

**Step 3: Commit**

```bash
git add scripts/indeed_poll_and_fetch.sh
git commit -m "refactor: update poll_and_fetch to use _lib.sh"
```

---

### Task 8: Update `indeed_jobs_by_url.sh` to use `_lib.sh`

**Files:**
- Modify: `scripts/indeed_jobs_by_url.sh`

**Step 1: Rewrite to use shared library**

```bash
#!/usr/bin/env bash
# Usage: indeed_jobs_by_url.sh <url> [url2 ...] [--limit N]
# Collect job listing details from Indeed job URLs (sync).
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lib.sh"

readonly MAX_SYNC_URLS=5

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_jobs_by_url.sh <url> [url2 ...] [OPTIONS]

Collect detailed job listing data from Indeed job URLs.

Arguments:
  url                  One or more Indeed job URLs (e.g., https://www.indeed.com/viewjob?jk=abc123)

Options:
  --limit N            Max results per URL
  --help               Show this help message

Output:
  JSON array to stdout

Examples:
  indeed_jobs_by_url.sh "https://www.indeed.com/viewjob?jk=abc123"
  indeed_jobs_by_url.sh url1 url2 url3
EOF
  exit 0
}

parse_args() {
  URLS=()
  LIMIT=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) show_help ;;
      --limit) LIMIT="$2"; shift 2 ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *) URLS+=("$1"); shift ;;
    esac
  done

  if [[ ${#URLS[@]} -eq 0 ]]; then
    echo "Error: at least one URL is required" >&2
    echo "Run with --help for usage" >&2
    exit 1
  fi
}

build_payload() {
  local payload="[]"
  for url in "${URLS[@]}"; do
    payload=$(echo "$payload" | jq --arg u "$url" '. + [{"url": $u}]')
  done
  echo "$payload"
}

main() {
  parse_args "$@"

  local dataset_id
  dataset_id=$(get_dataset_id jobs)

  local payload
  payload=$(build_payload)

  local endpoint
  if [[ ${#URLS[@]} -le $MAX_SYNC_URLS ]]; then
    endpoint="${LIB_BASE_URL}/scrape?dataset_id=${dataset_id}"
  else
    endpoint="${LIB_BASE_URL}/trigger?dataset_id=${dataset_id}"
  fi
  if [[ -n "$LIMIT" ]]; then
    endpoint="${endpoint}&limit_per_input=${LIMIT}"
  fi

  local body
  body=$(make_api_request POST "$endpoint" "$payload")
  check_http_status "$HTTP_CODE" "$body" "scrape" || exit 1

  # If async (>5 URLs), extract snapshot and poll
  if [[ ${#URLS[@]} -gt $MAX_SYNC_URLS ]]; then
    local snapshot_id
    snapshot_id=$(extract_snapshot_id "$body") || exit 1
    echo "Triggered async job: ${snapshot_id}" >&2
    "${SCRIPT_DIR}/indeed_poll_and_fetch.sh" "$snapshot_id"
  else
    echo "$body"
  fi
}

main "$@"
```

**Step 2: Run smoke tests**

Run: `bats tests/test_scripts_smoke.bats`
Expected: indeed_jobs_by_url.sh tests pass

**Step 3: Commit**

```bash
git add scripts/indeed_jobs_by_url.sh
git commit -m "refactor: update jobs_by_url to use _lib.sh"
```

---

### Task 9: Update `indeed_jobs_by_keyword.sh` to use `_lib.sh`

**Files:**
- Modify: `scripts/indeed_jobs_by_keyword.sh`

**Step 1: Rewrite to use shared library**

```bash
#!/usr/bin/env bash
# Usage: indeed_jobs_by_keyword.sh <keyword> <country> <location> [OPTIONS]
# Discover jobs by keyword search (async).
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lib.sh"

readonly DEFAULT_DOMAIN="indeed.com"

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_jobs_by_keyword.sh <keyword> <country> <location> [OPTIONS]

Discover job listings by keyword search on Indeed.

Arguments:
  keyword              Search keyword (e.g., "software engineer")
  country              Country code (e.g., US, GB, CA)
  location             Location string (e.g., "Austin, TX")

Options:
  --domain DOMAIN      Indeed domain (default: indeed.com)
  --date-posted VAL    Filter: "Last 24 hours", "Last 3 days", "Last 7 days", "Last 14 days"
  --pay RANGE          Filter by pay range
  --radius MILES       Location radius in miles
  --limit N            Max results to return
  --help               Show this help message

Output:
  JSON array to stdout

Examples:
  indeed_jobs_by_keyword.sh "nurse" US "Ohio"
  indeed_jobs_by_keyword.sh "software engineer" US "Austin, TX" --date-posted "Last 7 days"
  indeed_jobs_by_keyword.sh "warehouse" US "Dallas, TX" --limit 20
EOF
  exit 0
}

parse_args() {
  KEYWORD=""
  COUNTRY=""
  LOCATION=""
  DOMAIN="$DEFAULT_DOMAIN"
  DATE_POSTED=""
  PAY=""
  RADIUS=""
  LIMIT=""

  local positional=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) show_help ;;
      --domain) DOMAIN="$2"; shift 2 ;;
      --date-posted) DATE_POSTED="$2"; shift 2 ;;
      --pay) PAY="$2"; shift 2 ;;
      --radius) RADIUS="$2"; shift 2 ;;
      --limit) LIMIT="$2"; shift 2 ;;
      -*)
        echo "Unknown option: $1" >&2; exit 1 ;;
      *)
        case $positional in
          0) KEYWORD="$1" ;;
          1) COUNTRY="$1" ;;
          2) LOCATION="$1" ;;
          *) echo "Error: unexpected argument: $1" >&2; exit 1 ;;
        esac
        positional=$((positional + 1))
        shift
        ;;
    esac
  done

  if [[ -z "$KEYWORD" || -z "$COUNTRY" || -z "$LOCATION" ]]; then
    echo "Error: keyword, country, and location are required" >&2
    echo "Run with --help for usage" >&2
    exit 1
  fi
}

build_payload() {
  local payload
  payload=$(jq -n \
    --arg kw "$KEYWORD" \
    --arg co "$COUNTRY" \
    --arg dom "$DOMAIN" \
    --arg loc "$LOCATION" \
    '[{keyword_search: $kw, country: $co, domain: $dom, location: $loc}]')

  if [[ -n "$DATE_POSTED" ]]; then
    payload=$(echo "$payload" | jq --arg v "$DATE_POSTED" '.[0].date_posted = $v')
  fi
  if [[ -n "$PAY" ]]; then
    payload=$(echo "$payload" | jq --arg v "$PAY" '.[0].pay = $v')
  fi
  if [[ -n "$RADIUS" ]]; then
    payload=$(echo "$payload" | jq --arg v "$RADIUS" '.[0].location_radius = $v')
  fi

  echo "$payload"
}

main() {
  parse_args "$@"

  local dataset_id
  dataset_id=$(get_dataset_id jobs)

  local payload
  payload=$(build_payload)

  local endpoint="${LIB_BASE_URL}/trigger?dataset_id=${dataset_id}&type=discover_new&discover_by=keyword"
  if [[ -n "$LIMIT" ]]; then
    endpoint="${endpoint}&limit_multiple_results=${LIMIT}"
  fi

  local body
  body=$(make_api_request POST "$endpoint" "$payload")
  check_http_status "$HTTP_CODE" "$body" "trigger" || exit 1

  local snapshot_id
  snapshot_id=$(extract_snapshot_id "$body") || exit 1

  echo "Searching Indeed for \"${KEYWORD}\" in ${LOCATION}, ${COUNTRY}..." >&2
  "${SCRIPT_DIR}/indeed_poll_and_fetch.sh" "$snapshot_id"
}

main "$@"
```

**Step 2: Run smoke tests**

Run: `bats tests/test_scripts_smoke.bats`
Expected: indeed_jobs_by_keyword.sh tests pass

**Step 3: Commit**

```bash
git add scripts/indeed_jobs_by_keyword.sh
git commit -m "refactor: update jobs_by_keyword to use _lib.sh"
```

---

### Task 10: Update `indeed_jobs_by_company.sh` to use `_lib.sh`

**Files:**
- Modify: `scripts/indeed_jobs_by_company.sh`

**Step 1: Rewrite to use shared library**

```bash
#!/usr/bin/env bash
# Usage: indeed_jobs_by_company.sh <company_jobs_url> [--limit N]
# Discover jobs from a company's Indeed jobs page (async).
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lib.sh"

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_jobs_by_company.sh <company_jobs_url> [OPTIONS]

Discover job listings from a company's Indeed jobs page.

Arguments:
  company_jobs_url     Indeed company jobs URL (e.g., https://www.indeed.com/cmp/Google/jobs)

Options:
  --limit N            Max results to return
  --help               Show this help message

Output:
  JSON array to stdout
EOF
  exit 0
}

parse_args() {
  URL=""
  LIMIT=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) show_help ;;
      --limit) LIMIT="$2"; shift 2 ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *) URL="$1"; shift ;;
    esac
  done

  if [[ -z "$URL" ]]; then
    echo "Error: company jobs URL is required" >&2
    echo "Run with --help for usage" >&2
    exit 1
  fi
}

main() {
  parse_args "$@"

  local dataset_id
  dataset_id=$(get_dataset_id jobs)

  local payload
  payload=$(jq -n --arg u "$URL" '[{url: $u}]')

  local endpoint="${LIB_BASE_URL}/trigger?dataset_id=${dataset_id}&type=discover_new&discover_by=url"
  if [[ -n "$LIMIT" ]]; then
    endpoint="${endpoint}&limit_multiple_results=${LIMIT}"
  fi

  local body
  body=$(make_api_request POST "$endpoint" "$payload")
  check_http_status "$HTTP_CODE" "$body" "trigger" || exit 1

  local snapshot_id
  snapshot_id=$(extract_snapshot_id "$body") || exit 1

  echo "Discovering jobs from company page..." >&2
  "${SCRIPT_DIR}/indeed_poll_and_fetch.sh" "$snapshot_id"
}

main "$@"
```

**Step 2: Commit**

```bash
git add scripts/indeed_jobs_by_company.sh
git commit -m "refactor: update jobs_by_company to use _lib.sh"
```

---

### Task 11: Update all 3 company scripts to use `_lib.sh`

**Files:**
- Modify: `scripts/indeed_company_by_url.sh`
- Modify: `scripts/indeed_company_by_keyword.sh`
- Modify: `scripts/indeed_company_by_industry.sh`

**Step 1: Rewrite `indeed_company_by_url.sh`**

```bash
#!/usr/bin/env bash
# Usage: indeed_company_by_url.sh <url> [url2 ...] [--limit N]
# Collect company info from Indeed company URLs (sync).
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lib.sh"

readonly MAX_SYNC_URLS=5

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_company_by_url.sh <url> [url2 ...] [OPTIONS]

Collect company information from Indeed company page URLs.

Arguments:
  url                  One or more Indeed company URLs (e.g., https://www.indeed.com/cmp/Google)

Options:
  --limit N            Max results per URL
  --help               Show this help message

Output:
  JSON array to stdout

Note:
  Requires company dataset ID. Run indeed_list_datasets.sh --save first if not configured.
EOF
  exit 0
}

parse_args() {
  URLS=()
  LIMIT=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) show_help ;;
      --limit) LIMIT="$2"; shift 2 ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *) URLS+=("$1"); shift ;;
    esac
  done

  if [[ ${#URLS[@]} -eq 0 ]]; then
    echo "Error: at least one URL is required" >&2
    echo "Run with --help for usage" >&2
    exit 1
  fi
}

build_payload() {
  local payload="[]"
  for url in "${URLS[@]}"; do
    payload=$(echo "$payload" | jq --arg u "$url" '. + [{"url": $u}]')
  done
  echo "$payload"
}

main() {
  parse_args "$@"

  local dataset_id
  dataset_id=$(get_dataset_id company) || exit 1

  local payload
  payload=$(build_payload)

  local endpoint
  if [[ ${#URLS[@]} -le $MAX_SYNC_URLS ]]; then
    endpoint="${LIB_BASE_URL}/scrape?dataset_id=${dataset_id}"
  else
    endpoint="${LIB_BASE_URL}/trigger?dataset_id=${dataset_id}"
  fi
  if [[ -n "$LIMIT" ]]; then
    endpoint="${endpoint}&limit_per_input=${LIMIT}"
  fi

  local body
  body=$(make_api_request POST "$endpoint" "$payload")
  check_http_status "$HTTP_CODE" "$body" "request" || exit 1

  if [[ ${#URLS[@]} -gt $MAX_SYNC_URLS ]]; then
    local snapshot_id
    snapshot_id=$(extract_snapshot_id "$body") || exit 1
    "${SCRIPT_DIR}/indeed_poll_and_fetch.sh" "$snapshot_id"
  else
    echo "$body"
  fi
}

main "$@"
```

**Step 2: Rewrite `indeed_company_by_keyword.sh`**

```bash
#!/usr/bin/env bash
# Usage: indeed_company_by_keyword.sh <keyword> [--limit N]
# Discover companies by keyword search (async).
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lib.sh"

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_company_by_keyword.sh <keyword> [OPTIONS]

Discover companies on Indeed by keyword search.

Arguments:
  keyword              Company search keyword (e.g., "Tesla", "healthcare")

Options:
  --limit N            Max results to return
  --help               Show this help message

Output:
  JSON array to stdout

Note:
  Requires company dataset ID. Run indeed_list_datasets.sh --save first if not configured.
EOF
  exit 0
}

parse_args() {
  KEYWORD=""
  LIMIT=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) show_help ;;
      --limit) LIMIT="$2"; shift 2 ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *) KEYWORD="$1"; shift ;;
    esac
  done

  if [[ -z "$KEYWORD" ]]; then
    echo "Error: keyword is required" >&2
    echo "Run with --help for usage" >&2
    exit 1
  fi
}

main() {
  parse_args "$@"

  local dataset_id
  dataset_id=$(get_dataset_id company) || exit 1

  local payload
  payload=$(jq -n --arg kw "$KEYWORD" '[{keyword: $kw}]')

  local endpoint="${LIB_BASE_URL}/trigger?dataset_id=${dataset_id}&type=discover_new&discover_by=keyword"
  if [[ -n "$LIMIT" ]]; then
    endpoint="${endpoint}&limit_multiple_results=${LIMIT}"
  fi

  local body
  body=$(make_api_request POST "$endpoint" "$payload")
  check_http_status "$HTTP_CODE" "$body" "trigger" || exit 1

  local snapshot_id
  snapshot_id=$(extract_snapshot_id "$body") || exit 1

  echo "Searching Indeed companies for \"${KEYWORD}\"..." >&2
  "${SCRIPT_DIR}/indeed_poll_and_fetch.sh" "$snapshot_id"
}

main "$@"
```

**Step 3: Rewrite `indeed_company_by_industry.sh`**

```bash
#!/usr/bin/env bash
# Usage: indeed_company_by_industry.sh <industry> <state> [--limit N]
# Discover companies by industry and state (async).
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lib.sh"

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_company_by_industry.sh <industry> <state> [OPTIONS]

Discover companies on Indeed by industry and state.

Arguments:
  industry             Industry category (e.g., "Technology", "Healthcare")
  state                US state (e.g., "Texas", "California")

Options:
  --limit N            Max results to return
  --help               Show this help message

Output:
  JSON array to stdout

Note:
  Requires company dataset ID. Run indeed_list_datasets.sh --save first if not configured.
EOF
  exit 0
}

parse_args() {
  INDUSTRY=""
  STATE=""
  LIMIT=""

  local positional=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) show_help ;;
      --limit) LIMIT="$2"; shift 2 ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *)
        case $positional in
          0) INDUSTRY="$1" ;;
          1) STATE="$1" ;;
          *) echo "Error: unexpected argument: $1" >&2; exit 1 ;;
        esac
        positional=$((positional + 1))
        shift
        ;;
    esac
  done

  if [[ -z "$INDUSTRY" || -z "$STATE" ]]; then
    echo "Error: industry and state are required" >&2
    echo "Run with --help for usage" >&2
    exit 1
  fi
}

main() {
  parse_args "$@"

  local dataset_id
  dataset_id=$(get_dataset_id company) || exit 1

  local payload
  payload=$(jq -n --arg ind "$INDUSTRY" --arg st "$STATE" \
    '[{industry: $ind, state: $st}]')

  local endpoint="${LIB_BASE_URL}/trigger?dataset_id=${dataset_id}&type=discover_new&discover_by=industry_and_state"
  if [[ -n "$LIMIT" ]]; then
    endpoint="${endpoint}&limit_multiple_results=${LIMIT}"
  fi

  local body
  body=$(make_api_request POST "$endpoint" "$payload")
  check_http_status "$HTTP_CODE" "$body" "trigger" || exit 1

  local snapshot_id
  snapshot_id=$(extract_snapshot_id "$body") || exit 1

  echo "Searching Indeed for ${INDUSTRY} companies in ${STATE}..." >&2
  "${SCRIPT_DIR}/indeed_poll_and_fetch.sh" "$snapshot_id"
}

main "$@"
```

**Step 4: Run all tests**

Run: `bats tests/`
Expected: All tests pass

**Step 5: Commit**

```bash
git add scripts/indeed_company_by_url.sh scripts/indeed_company_by_keyword.sh scripts/indeed_company_by_industry.sh
git commit -m "refactor: update all company scripts to use _lib.sh"
```

---

### Task 12: Update `indeed_list_datasets.sh` to use `_lib.sh`

**Files:**
- Modify: `scripts/indeed_list_datasets.sh`

**Step 1: Rewrite to use shared library**

```bash
#!/usr/bin/env bash
# Usage: indeed_list_datasets.sh [--save]
# List available Bright Data dataset IDs and optionally save company ID to config.
# Env: BRIGHTDATA_API_KEY (required)
# Output: JSON to stdout

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lib.sh"

readonly LIST_URL="https://api.brightdata.com/datasets/list"

show_help() {
  cat >&2 <<'EOF'
Usage: indeed_list_datasets.sh [OPTIONS]

List available Bright Data Indeed dataset IDs.
Filters for Indeed-related datasets and displays them.

Options:
  --save               Save discovered dataset IDs to config file
  --help               Show this help message

Output:
  JSON object with jobs and company dataset IDs

Config:
  Saved to ~/.config/indeed-brightdata/datasets.json
EOF
  exit 0
}

parse_args() {
  SAVE=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) show_help ;;
      --save) SAVE=true; shift ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
  done
}

fetch_datasets() {
  local body
  body=$(make_api_request GET "$LIST_URL")
  check_http_status "$HTTP_CODE" "$body" "list datasets" || return 1
  echo "$body"
}

filter_indeed_datasets() {
  local all_datasets="$1"
  echo "$all_datasets" | jq '[.[] | select(.name // "" | test("indeed"; "i"))]'
}

save_config() {
  local datasets="$1"
  mkdir -p "$LIB_CONFIG_DIR"

  local company_id
  company_id=$(echo "$datasets" | jq -r \
    --arg jobs_id "$LIB_JOBS_DATASET_ID" \
    '[.[] | select(.id != $jobs_id)] | .[0].id // empty')

  local config
  config=$(jq -n \
    --arg jobs "$LIB_JOBS_DATASET_ID" \
    --arg company "$company_id" \
    '{jobs: $jobs, company: $company}')

  echo "$config" > "$LIB_DATASETS_FILE"
  echo "Saved dataset IDs to ${LIB_DATASETS_FILE}" >&2
  echo "  Jobs: ${LIB_JOBS_DATASET_ID}" >&2
  echo "  Company: ${company_id:-not found}" >&2
}

main() {
  parse_args "$@"

  local all_datasets indeed_datasets
  all_datasets=$(fetch_datasets) || exit 1
  indeed_datasets=$(filter_indeed_datasets "$all_datasets")

  if [[ "$SAVE" == true ]]; then
    save_config "$indeed_datasets"
  fi

  echo "$indeed_datasets"
}

main "$@"
```

**Step 2: Run all tests**

Run: `bats tests/`
Expected: All tests pass

**Step 3: Commit**

```bash
git add scripts/indeed_list_datasets.sh
git commit -m "refactor: update list_datasets to use _lib.sh"
```

---

### Task 13: Run full test suite and push

**Step 1: Run all tests**

Run: `bats tests/`
Expected: All ~29 tests pass (15 lib + 6 poller + 8 smoke help + 7 smoke no-args - 1 list_datasets has no "required" in no-args output... adjust if needed)

**Step 2: Run shellcheck on all scripts**

Run: `shellcheck scripts/*.sh`
Expected: No errors (warnings OK)

**Step 3: Push to GitHub**

```bash
git push origin main
```
