#!/usr/bin/env bats

setup() {
  export TEST_TMPDIR="$(mktemp -d)"
  export PROJECT_ROOT
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
  rm -f "$PROJECT_ROOT/indeed-brightdata.zip"
}

@test "package.sh --help exits 0" {
  run "$PROJECT_ROOT/scripts/package.sh" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "package.sh creates indeed-brightdata.zip" {
  run "$PROJECT_ROOT/scripts/package.sh"
  [[ "$status" -eq 0 ]]
  [[ -f "$PROJECT_ROOT/indeed-brightdata.zip" ]]
}

@test "package.sh ZIP contains SKILL.md at correct path" {
  "$PROJECT_ROOT/scripts/package.sh"
  run unzip -l "$PROJECT_ROOT/indeed-brightdata.zip"
  [[ "$output" == *"indeed-brightdata/SKILL.md"* ]]
}

@test "package.sh ZIP contains scripts directory" {
  "$PROJECT_ROOT/scripts/package.sh"
  run unzip -l "$PROJECT_ROOT/indeed-brightdata.zip"
  [[ "$output" == *"indeed-brightdata/scripts/"* ]]
}

@test "package.sh ZIP excludes .git directory" {
  "$PROJECT_ROOT/scripts/package.sh"
  run unzip -l "$PROJECT_ROOT/indeed-brightdata.zip"
  [[ "$output" != *".git/"* ]]
}

@test "package.sh ZIP excludes tests directory" {
  "$PROJECT_ROOT/scripts/package.sh"
  run unzip -l "$PROJECT_ROOT/indeed-brightdata.zip"
  [[ "$output" != *"tests/"* ]]
}

@test "package.sh prints success message" {
  run "$PROJECT_ROOT/scripts/package.sh"
  [[ "$output" == *"Created indeed-brightdata.zip"* ]]
}
