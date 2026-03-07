#!/usr/bin/env bats

setup() {
  export PROJECT_ROOT
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$PROJECT_ROOT/scripts/indeed_format_results.sh"
  FIXTURES="$PROJECT_ROOT/tests/fixtures"
}

@test "shows help with --help" {
  run "$SCRIPT" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Format"* ]]
}

@test "formats jobs summary from file" {
  run "$SCRIPT" "$FIXTURES/sample_jobs.json"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Security Engineer"* ]]
  [[ "$output" == *"Acme Corp"* ]]
  [[ "$output" == *'$120,000 - $150,000 a year'* ]]
}

@test "shows Not listed for null salary" {
  run "$SCRIPT" "$FIXTURES/sample_jobs.json"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"SOC Analyst"* ]]
  [[ "$output" == *"Not listed"* ]]
}

@test "shows See listing for null qualifications" {
  run "$SCRIPT" "$FIXTURES/sample_jobs.json"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"See listing"* ]]
}

@test "respects --top N" {
  run "$SCRIPT" --top 1 "$FIXTURES/sample_jobs.json"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Security Engineer"* ]]
  [[ "$output" != *"SOC Analyst"* ]]
}

@test "formats jobs CSV with headers" {
  run "$SCRIPT" --format csv "$FIXTURES/sample_jobs.json"
  [[ "$status" -eq 0 ]]
  local first_line
  first_line=$(echo "$output" | head -1)
  [[ "$first_line" == "job_title,company_name,location,salary,date_posted,url" ]]
}

@test "CSV escapes commas in fields" {
  run "$SCRIPT" --format csv "$FIXTURES/sample_jobs.json"
  [[ "$status" -eq 0 ]]
  # The salary "$120,000 - $150,000 a year" contains commas and must be quoted
  [[ "$output" == *'"$120,000 - $150,000 a year"'* ]]
  # Location "Austin, TX" contains a comma and must be quoted
  [[ "$output" == *'"Austin, TX"'* ]]
}

@test "formats companies summary" {
  run "$SCRIPT" --type companies "$FIXTURES/sample_companies.json"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Google"* ]]
  [[ "$output" == *"4.3"* ]]
  [[ "$output" == *"3500 open positions"* ]]
}

@test "companies summary shows N/A for missing fields" {
  run "$SCRIPT" --type companies "$FIXTURES/sample_companies.json"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Size N/A"* ]]
  [[ "$output" == *"HQ N/A"* ]]
}

@test "reads from stdin" {
  run bash -c "cat '$FIXTURES/sample_jobs.json' | '$SCRIPT'"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Security Engineer"* ]]
}

@test "unwraps meta envelope" {
  local wrapped
  wrapped=$(jq -n --slurpfile jobs "$FIXTURES/sample_jobs.json" '{"meta":{"request_id":"abc123"},"results":$jobs[0]}')
  run bash -c "echo '$wrapped' | '$SCRIPT'"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Security Engineer"* ]]
  [[ "$output" == *"SOC Analyst"* ]]
}
