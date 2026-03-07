## 1. Shared Library Extensions

- [x] 1.1 Add `save_history`, `check_history_cache`, `cleanup_old_entries` functions to `_lib.sh`
- [x] 1.2 Add `LIB_HISTORY_FILE` and `LIB_RESULTS_DIR` constants to `_lib.sh`
- [x] 1.3 Add `save_result_file` helper that writes JSON to `results/<snapshot_id>.json`

## 2. Default Limits and Date Filters

- [x] 2.1 Set default `limit_per_input=25` in `indeed_jobs_by_keyword.sh` when `--limit-per-input` not specified
- [x] 2.2 Set default `limit_per_input=25` in `indeed_company_by_keyword.sh` when `--limit-per-input` not specified
- [x] 2.3 Set default `limit_per_input=25` in `indeed_company_by_industry.sh` when `--limit-per-input` not specified
- [x] 2.4 Add default `date_posted="Last 7 days"` and `--all-time` flag to `indeed_jobs_by_keyword.sh`

## 3. Keyword Expansions Reference

- [x] 3.1 Create `references/keyword-expansions.json` with 10 initial category entries

## 4. Smart Search Script

- [x] 4.1 Create `scripts/indeed_smart_search.sh` with argument parsing (keyword, country, location, --limit, --date-posted, --no-expand, --all-time, --force, --help)
- [x] 4.2 Implement keyword expansion lookup with case-insensitive matching and suffix fallback
- [x] 4.3 Implement cache check via `check_history_cache` before triggering
- [x] 4.4 Implement parallel trigger of keyword searches via `indeed_jobs_by_keyword.sh --no-wait`
- [x] 4.5 Implement unified polling loop for all snapshot IDs (20s interval, 600s timeout)
- [x] 4.6 Implement result collection, dedup by jobid, filter expired, sort by date, cap at 20
- [x] 4.7 Implement metadata wrapper output (`meta` + `results` JSON structure)
- [x] 4.8 Implement automatic date expansion ("Last 7 days" → "Last 30 days") when results < 5
- [x] 4.9 Save completed results to history and result files; save timed-out snapshots to pending

## 5. Result Formatting Script

- [x] 5.1 Create `scripts/indeed_format_results.sh` with argument parsing (--type, --top, --format, --help, file arg or stdin)
- [x] 5.2 Implement `--type jobs --format summary` with emoji-prefixed fields and box-drawing separators
- [x] 5.3 Implement `--type companies --format summary` with formatted company entries
- [x] 5.4 Implement `--format csv` with RFC 4180 compliant output and proper quoting
- [x] 5.5 Implement HTML tag stripping, null-to-N/A conversion, and 200-char description truncation
- [x] 5.6 Implement Telegram-safe chunking with `---SPLIT---` markers at 3500 char boundaries

## 6. Check Pending Enhancements

- [x] 6.1 Add auto-cleanup of history entries > 7 days and stale pending entries > 24 hours at start of `indeed_check_pending.sh`
- [x] 6.2 Change output to structured JSON (`completed`, `still_pending`, `failed` arrays)
- [x] 6.3 Save fetched results to `results/<snapshot_id>.json` via `save_result_file`

## 7. Documentation

- [x] 7.1 Rewrite SKILL.md with workflow decision tree, behavior rules, and smart search as primary entry point
- [x] 7.2 Update README.md with new scripts and smart search usage examples

## 8. Tests

- [x] 8.1 Write bats tests for `_lib.sh` history/cache functions (save, check, cleanup)
- [x] 8.2 Write bats tests for `indeed_format_results.sh` (summary, csv, chunking, null handling)
- [x] 8.3 Write bats tests for `indeed_smart_search.sh` (expansion, cache hit, metadata output)
- [x] 8.4 Write bats tests for `indeed_check_pending.sh` structured output
