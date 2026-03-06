# Universalize Skill Distribution — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the indeed-brightdata skill installable on Claude Code, Claude Desktop, Cursor, Codex, and OpenClaw with a single install script and proper Agent Skills standard compliance.

**Architecture:** Update SKILL.md frontmatter for cross-platform compatibility, add install.sh with symlink-based registration for 5 platforms, add .claude-plugin/ for marketplace discovery, add package.sh for Desktop ZIP builds. No changes to existing scripts.

**Tech Stack:** Bash, bats-core, zip, Make

**Working directory:** `/home/cownose/projects/indeed-brightdata-universalize-skill-distribution`

---

### Task 1: Update SKILL.md Frontmatter

**Files:**
- Modify: `SKILL.md:1-12` (frontmatter only)
- Test: `tests/test_skill_frontmatter.bats` (new)

**Step 1: Write the failing test**

```bash
# tests/test_skill_frontmatter.bats
#!/usr/bin/env bats

@test "SKILL.md has name field" {
  head -15 "$BATS_TEST_DIRNAME/../SKILL.md" | grep -q "^name: indeed-brightdata"
}

@test "SKILL.md has allowed-tools field" {
  head -15 "$BATS_TEST_DIRNAME/../SKILL.md" | grep -q "^allowed-tools:"
}

@test "SKILL.md has allowed-tools including Bash" {
  head -15 "$BATS_TEST_DIRNAME/../SKILL.md" | grep "allowed-tools:" | grep -q "Bash"
}

@test "SKILL.md has version field" {
  head -15 "$BATS_TEST_DIRNAME/../SKILL.md" | grep -q "^version:"
}

@test "SKILL.md has license field" {
  head -15 "$BATS_TEST_DIRNAME/../SKILL.md" | grep -q "^license:"
}

@test "SKILL.md preserves OpenClaw metadata" {
  head -15 "$BATS_TEST_DIRNAME/../SKILL.md" | grep -q "metadata:"
}
```

**Step 2: Run test to verify it fails**

Run: `bats tests/test_skill_frontmatter.bats`
Expected: FAIL on allowed-tools, version, license (name and metadata already exist)

**Step 3: Update SKILL.md frontmatter**

Add `allowed-tools`, `version`, `license` fields to the YAML frontmatter block (lines 1-12). Keep existing `name`, `description`, `metadata` intact. The frontmatter should be:

```yaml
---
name: indeed-brightdata
description: >
  Search and scrape Indeed job listings and company information using Bright Data's
  Web Scraper API. Use when the user asks to find jobs on Indeed, search for job
  postings by keyword or location, look up company information from Indeed, collect
  job listing details from Indeed URLs, discover companies by industry, or perform
  any Indeed-related recruiting research. Requires BRIGHTDATA_API_KEY env var.
  Supports: job search by keyword/location/URL, company lookup by URL/keyword/industry,
  batch collection with polling, and structured JSON output.
version: 1.0.0
license: MIT
allowed-tools: Bash
metadata: {"openclaw":{"requires":{"env":["BRIGHTDATA_API_KEY"],"bins":["curl","jq"]},"primaryEnv":"BRIGHTDATA_API_KEY"}}
---
```

**Step 4: Run test to verify it passes**

Run: `bats tests/test_skill_frontmatter.bats`
Expected: All 6 tests PASS

**Step 5: Commit**

```bash
git add SKILL.md tests/test_skill_frontmatter.bats
git commit -m "feat(skill): add Agent Skills standard frontmatter fields"
```

---

### Task 2: Create package.sh for Desktop ZIP

**Files:**
- Create: `scripts/package.sh`
- Test: `tests/test_package.bats` (new)

**Step 1: Write the failing test**

```bash
# tests/test_package.bats
#!/usr/bin/env bats

setup() {
  export TEST_TMPDIR="$(mktemp -d)"
  export PROJECT_ROOT="$BATS_TEST_DIRNAME/.."
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

@test "package.sh prints success message to stderr" {
  run "$PROJECT_ROOT/scripts/package.sh"
  [[ "$output" == *"Created indeed-brightdata.zip"* ]]
}
```

**Step 2: Run test to verify it fails**

Run: `bats tests/test_package.bats`
Expected: FAIL — package.sh does not exist

**Step 3: Create scripts/package.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PACKAGE_NAME="indeed-brightdata"
readonly OUTPUT_FILE="${PROJECT_ROOT}/${PACKAGE_NAME}.zip"

show_help() {
  cat >&2 <<EOF
Usage: $(basename "$0") [OPTIONS]

Build a ZIP package of the indeed-brightdata skill for Claude Desktop upload.

Options:
  --help    Show this help message

Output:
  Creates ${PACKAGE_NAME}.zip in the project root.
  Upload via Claude Desktop: Settings > Features > Skills > Upload skill
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

# Build ZIP from project root, excluding dev files
cd "$PROJECT_ROOT"
rm -f "$OUTPUT_FILE"

zip -r "$OUTPUT_FILE" \
  SKILL.md \
  scripts/ \
  references/ \
  LICENSE \
  --exclude "scripts/package.sh" \
  -x "*.swp" "*.swo" \
  2>/dev/null

# Rename contents to be inside indeed-brightdata/ directory
# zip doesn't support prefix directly, so we use a temp dir
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$TEMP_DIR/$PACKAGE_NAME"
cp SKILL.md "$TEMP_DIR/$PACKAGE_NAME/"
cp LICENSE "$TEMP_DIR/$PACKAGE_NAME/"
cp -r scripts "$TEMP_DIR/$PACKAGE_NAME/"
cp -r references "$TEMP_DIR/$PACKAGE_NAME/"
# Remove dev scripts from package
rm -f "$TEMP_DIR/$PACKAGE_NAME/scripts/package.sh"

rm -f "$OUTPUT_FILE"
cd "$TEMP_DIR"
zip -r "$OUTPUT_FILE" "$PACKAGE_NAME/" 2>/dev/null

FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
echo "Created ${PACKAGE_NAME}.zip (${FILE_SIZE})" >&2
```

**Step 4: Make executable and run tests**

Run: `chmod +x scripts/package.sh && bats tests/test_package.bats`
Expected: All 7 tests PASS

**Step 5: Commit**

```bash
git add scripts/package.sh tests/test_package.bats
git commit -m "feat(packaging): add package.sh for Claude Desktop ZIP builds"
```

---

### Task 3: Create install.sh

**Files:**
- Create: `install.sh`
- Test: `tests/test_install.bats` (new)

**Step 1: Write the failing tests**

```bash
# tests/test_install.bats
#!/usr/bin/env bats

setup() {
  export TEST_TMPDIR="$(mktemp -d)"
  export HOME="$TEST_TMPDIR"
  export PROJECT_ROOT="$BATS_TEST_DIRNAME/.."
  # Ensure BRIGHTDATA_API_KEY is set so the prompt is skipped
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
  # Create a PATH without curl
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/jq" <<'EOF'
#!/bin/bash
echo "mock jq"
EOF
  chmod +x "$TEST_TMPDIR/bin/jq"

  PATH="$TEST_TMPDIR/bin" run "$PROJECT_ROOT/install.sh" --platform claude-code
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"curl"* ]]
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
```

**Step 2: Run test to verify it fails**

Run: `bats tests/test_install.bats`
Expected: FAIL — install.sh does not exist

**Step 3: Create install.sh**

The script should:
- Start with `set -euo pipefail`
- Define constants: `SKILL_NAME="indeed-brightdata"`, platform directories
- Implement `show_help()`, `check_deps()`, `check_api_key()`, `install_symlink()`, `install_openclaw()`, `install_desktop()`
- Parse args: `--help`, `--platform <name>`, `--all`, `--force`
- Interactive mode (no args): show menu with numbered options
- Each `install_symlink()` call: create parent dir, check existing, create symlink
- `check_deps()`: verify curl, jq, bash version >= 4
- All user messages to stderr, consistent with project conventions
- Keep functions under 40 lines per CODE_PRINCIPLES.md

The full implementation is ~120 lines. Key function signatures:
- `check_deps()` — exits 1 if missing
- `check_api_key()` — prompts if unset, skips if set
- `install_symlink(platform_name, target_dir)` — creates `$target_dir/$SKILL_NAME` → `$PROJECT_ROOT`
- `install_openclaw()` — prints config command
- `install_desktop()` — runs package.sh, prints upload instructions
- `show_menu()` — interactive numbered platform picker
- `main()` — parses args, dispatches

**Step 4: Make executable and run tests**

Run: `chmod +x install.sh && bats tests/test_install.bats`
Expected: All 10 tests PASS

**Step 5: Commit**

```bash
git add install.sh tests/test_install.bats
git commit -m "feat(install): add multi-platform install script"
```

---

### Task 4: Create Claude Code Plugin Manifest

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `skills/indeed-brightdata/SKILL.md` (symlink)

**Step 1: Create .claude-plugin/plugin.json**

```json
{
  "name": "indeed-brightdata",
  "version": "1.0.0",
  "description": "Search and scrape Indeed job listings and company information using Bright Data's Web Scraper API",
  "author": "foreztgump",
  "license": "MIT",
  "keywords": ["indeed", "jobs", "brightdata", "recruiting", "scraping"]
}
```

**Step 2: Create skills/ symlink structure**

```bash
mkdir -p skills/indeed-brightdata
cd skills/indeed-brightdata
ln -s ../../SKILL.md SKILL.md
ln -s ../../scripts scripts
ln -s ../../references references
```

**Step 3: Verify structure**

Run: `ls -la skills/indeed-brightdata/ && cat .claude-plugin/plugin.json | jq .`
Expected: Symlinks resolve correctly, plugin.json is valid JSON

**Step 4: Commit**

```bash
git add .claude-plugin/plugin.json skills/
git commit -m "feat(plugin): add Claude Code plugin marketplace support"
```

---

### Task 5: Create Makefile

**Files:**
- Create: `Makefile`

**Step 1: Create Makefile**

```makefile
.PHONY: install test package help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Install skill for your AI agent platform
	./install.sh

test: ## Run all bats tests
	bats tests/

package: ## Build ZIP for Claude Desktop upload
	./scripts/package.sh
```

**Step 2: Verify targets**

Run: `make help`
Expected: Three targets listed with descriptions

Run: `make test`
Expected: All existing tests pass, plus new tests from Tasks 1-3

**Step 3: Commit**

```bash
git add Makefile
git commit -m "feat: add Makefile with install, test, package targets"
```

---

### Task 6: Update .gitignore

**Files:**
- Modify: `.gitignore`

**Step 1: Update .gitignore**

Add these entries:
```
# Build artifacts
indeed-brightdata.zip
```

Remove `.claude/` from gitignore (we need `.claude-plugin/` tracked). Replace with more specific ignores:
```
# Private config (keep .claude-plugin/ tracked)
.claude/settings/
.claude/skills/
```

**Step 2: Verify**

Run: `git status` — `.claude-plugin/plugin.json` should be trackable, `indeed-brightdata.zip` should be ignored

**Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: update gitignore for plugin manifest and build artifacts"
```

---

### Task 7: Rewrite README.md

**Files:**
- Modify: `README.md` (full rewrite)

**Step 1: Rewrite README.md**

Structure:
1. **Title + one-liner** — "Indeed job search and company data via Bright Data — works with Claude, Cursor, Codex, and more"
2. **Compatibility matrix** — table of platforms with install method
3. **Quick Start** — fastest path: `git clone` + `./install.sh`
4. **Prerequisites** — curl, jq, BRIGHTDATA_API_KEY
5. **Installation** — subsections per platform:
   - Claude Code (symlink or `/plugin marketplace add`)
   - Claude Desktop (ZIP upload)
   - Cursor / Codex (symlink)
   - OpenClaw (config command)
   - Universal CLI (`npx add-skill`)
6. **Usage** — keep existing script examples
7. **Scripts reference** — keep existing table
8. **Development** — `make test`, `make package`
9. **License** — MIT

**Step 2: Review**

Read through for accuracy and completeness.

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for multi-platform installation"
```

---

### Task 8: Run Full Test Suite

**Step 1: Run all tests**

Run: `bats tests/`
Expected: All tests pass (existing 36 + new tests from Tasks 1-3)

**Step 2: Run shellcheck on new scripts**

Run: `shellcheck install.sh scripts/package.sh`
Expected: No errors

**Step 3: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: address test/lint issues"
```
