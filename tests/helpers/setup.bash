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
create_curl_mock() {
  local mock_path="$TEST_TMPDIR/bin"
  mkdir -p "$mock_path"
  cat > "$mock_path/curl" <<'MOCK'
#!/usr/bin/env bash
# Mock curl that returns configured responses
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
