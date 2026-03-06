#!/usr/bin/env bats

@test "SKILL.md has name field" {
  head -20 "$BATS_TEST_DIRNAME/../SKILL.md" | grep -q "^name: indeed-brightdata"
}

@test "SKILL.md has allowed-tools field with Bash" {
  head -20 "$BATS_TEST_DIRNAME/../SKILL.md" | grep "allowed-tools:" | grep -q "Bash"
}

@test "SKILL.md has version field" {
  head -20 "$BATS_TEST_DIRNAME/../SKILL.md" | grep -q "^version:"
}

@test "SKILL.md has license field" {
  head -20 "$BATS_TEST_DIRNAME/../SKILL.md" | grep -q "^license:"
}

@test "SKILL.md preserves OpenClaw metadata" {
  head -20 "$BATS_TEST_DIRNAME/../SKILL.md" | grep -q "metadata:"
}
