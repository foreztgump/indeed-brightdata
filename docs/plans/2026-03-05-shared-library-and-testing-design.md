# Design: Shared Library Extraction + Testing Strategy

**Date:** 2026-03-05
**Status:** Approved
**Scope:** Phase 1 architecture refinement

## Context

All 8 scripts share duplicated patterns for API requests (~10 locations), HTTP error handling (~8 locations), and dataset ID retrieval (~3 locations). Only 1 of 8 scripts handles HTTP 429 rate limiting. No tests exist yet.

## Decision

**Option 2**: Extract 3 critical shared functions into `scripts/_lib.sh`. Test the shared library and poller thoroughly, with light smoke tests for individual scripts.

## Shared Library (`scripts/_lib.sh`)

### `make_api_request <method> <endpoint> [payload]`
- Wraps curl with Authorization header and Content-Type
- Supports GET (no payload) and POST (with payload)
- Sets global `HTTP_CODE` with response status
- Outputs response body to stdout
- Replaces ~10 inline curl blocks

### `check_http_status <http_code> <body> <action_description>`
- Returns 0 on 200, 1 on error
- Special 429 handling: "Error: rate limit exceeded (HTTP 429). Try again later."
- Consistent error format for all other codes
- Replaces ~8 inline status checks

### `get_dataset_id <type>`
- `jobs`: returns hardcoded `gd_l4dx9j9sscpvs7no2`
- `company`: reads from `~/.config/indeed-brightdata/datasets.json`
- Clear error message if company ID not configured
- Replaces 3 identical `get_company_dataset_id()` functions

## Script Updates

All 8 scripts updated to:
1. `source "${SCRIPT_DIR}/_lib.sh"` near top
2. Replace inline curl+parsing with `make_api_request`
3. Replace inline status checks with `check_http_status`
4. Company scripts: replace `get_company_dataset_id()` with `get_dataset_id company`

## Testing Strategy

### `tests/test_lib.bats` (~15 tests)
- make_api_request: successful GET, successful POST, missing API key
- check_http_status: 200, 401, 429, 500, unknown codes
- get_dataset_id: jobs returns hardcoded, company from config, company missing config
- curl mocked via stub function

### `tests/test_poll_and_fetch.bats` (~6 tests)
- Ready on first poll
- Running → ready transition
- Timeout exceeded
- Failed snapshot status
- Invalid snapshot ID

### `tests/test_scripts_smoke.bats` (~8 tests)
- Each script exits 0 with --help
- Each script exits non-zero with no args

### `tests/helpers/` — Test infrastructure
- `setup.bash`: common setup, mock curl, temp dirs
- Mock curl function returning configurable responses

## File Changes

```
NEW:      scripts/_lib.sh
NEW:      tests/test_lib.bats
NEW:      tests/test_poll_and_fetch.bats
NEW:      tests/test_scripts_smoke.bats
NEW:      tests/helpers/setup.bash
MODIFIED: scripts/indeed_jobs_by_url.sh
MODIFIED: scripts/indeed_jobs_by_keyword.sh
MODIFIED: scripts/indeed_jobs_by_company.sh
MODIFIED: scripts/indeed_company_by_url.sh
MODIFIED: scripts/indeed_company_by_keyword.sh
MODIFIED: scripts/indeed_company_by_industry.sh
MODIFIED: scripts/indeed_poll_and_fetch.sh
MODIFIED: scripts/indeed_list_datasets.sh
```
