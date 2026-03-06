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

@test "plugin.json version matches SKILL.md version" {
  local skill_version
  local plugin_version
  skill_version=$(grep "^version:" "$BATS_TEST_DIRNAME/../SKILL.md" | awk '{print $2}')
  plugin_version=$(jq -r '.version' "$BATS_TEST_DIRNAME/../.claude-plugin/plugin.json")
  [[ "$skill_version" == "$plugin_version" ]]
}
