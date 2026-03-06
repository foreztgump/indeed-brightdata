#!/usr/bin/env bats

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

@test "indeed_check_pending.sh --help exits 0" {
  run "$SCRIPT_DIR/indeed_check_pending.sh" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
}
