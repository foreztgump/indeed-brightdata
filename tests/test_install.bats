#!/usr/bin/env bats

setup() {
  export TEST_TMPDIR="$(mktemp -d)"
  export HOME="$TEST_TMPDIR"
  export PROJECT_ROOT
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export BRIGHTDATA_API_KEY="test-key"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "install.sh --help exits 0" {
  run "$PROJECT_ROOT/install.sh" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "install.sh checks for curl dependency" {
  # Create a bin dir with symlinks to essential tools but NOT curl/jq
  local mock_bin="$TEST_TMPDIR/restricted_bin"
  mkdir -p "$mock_bin"
  for bin in bash dirname mkdir ln rm readlink cat env; do
    local real_path
    real_path="$(command -v "$bin" 2>/dev/null || true)"
    if [[ -n "$real_path" ]]; then
      ln -sf "$real_path" "$mock_bin/$bin"
    fi
  done
  PATH="$mock_bin" run "$PROJECT_ROOT/install.sh" --platform claude-code
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"curl"* || "$output" == *"jq"* ]]
}

@test "install.sh creates Claude Code symlink" {
  run "$PROJECT_ROOT/install.sh" --platform claude-code
  [[ "$status" -eq 0 ]]
  [[ -L "$HOME/.claude/skills/indeed-brightdata" ]]
}

@test "install.sh creates Cursor symlink" {
  run "$PROJECT_ROOT/install.sh" --platform cursor
  [[ "$status" -eq 0 ]]
  [[ -L "$HOME/.cursor/skills/indeed-brightdata" ]]
}

@test "install.sh creates Codex symlink" {
  run "$PROJECT_ROOT/install.sh" --platform codex
  [[ "$status" -eq 0 ]]
  [[ -L "$HOME/.codex/skills/indeed-brightdata" ]]
}

@test "install.sh warns on existing installation" {
  mkdir -p "$HOME/.claude/skills/indeed-brightdata"
  run "$PROJECT_ROOT/install.sh" --platform claude-code
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"already exists"* ]]
}

@test "install.sh --force overwrites existing installation" {
  mkdir -p "$HOME/.claude/skills/indeed-brightdata"
  run "$PROJECT_ROOT/install.sh" --platform claude-code --force
  [[ "$status" -eq 0 ]]
  [[ -L "$HOME/.claude/skills/indeed-brightdata" ]]
}

@test "install.sh --all installs for multiple platforms" {
  run "$PROJECT_ROOT/install.sh" --all
  [[ "$status" -eq 0 ]]
  [[ -L "$HOME/.claude/skills/indeed-brightdata" ]]
  [[ -L "$HOME/.cursor/skills/indeed-brightdata" ]]
  [[ -L "$HOME/.codex/skills/indeed-brightdata" ]]
}

@test "install.sh prints OpenClaw instructions" {
  run "$PROJECT_ROOT/install.sh" --platform openclaw
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"openclaw config set"* ]]
}

@test "install.sh detects existing API key" {
  export BRIGHTDATA_API_KEY="my-key"
  run "$PROJECT_ROOT/install.sh" --platform claude-code
  [[ "$output" == *"API key detected"* ]]
}

@test "install.sh rejects unknown platform" {
  run "$PROJECT_ROOT/install.sh" --platform nonexistent
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"unknown platform"* ]]
}

@test "install.sh claude-desktop builds ZIP" {
  run "$PROJECT_ROOT/install.sh" --platform claude-desktop
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Upload"* ]]
  rm -f "$PROJECT_ROOT/indeed-brightdata.zip"
}

@test "install.sh warns when API key is not set" {
  unset BRIGHTDATA_API_KEY
  run "$PROJECT_ROOT/install.sh" --platform claude-code
  [[ "$output" == *"BRIGHTDATA_API_KEY is not set"* ]]
}

@test "install.sh --all includes claude-desktop ZIP" {
  run "$PROJECT_ROOT/install.sh" --all
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Upload"* ]]
  rm -f "$PROJECT_ROOT/indeed-brightdata.zip"
}
