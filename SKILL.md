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
version: 2.0.0
license: MIT
allowed-tools: Bash
metadata: {"openclaw":{"requires":{"env":["BRIGHTDATA_API_KEY"],"bins":["curl","jq"]},"primaryEnv":"BRIGHTDATA_API_KEY"}}
---

# Indeed Bright Data Skill

Search Indeed for job listings and company info via Bright Data's Web Scraper API. Returns structured JSON that agents can summarize, filter, or forward to users.

## Prerequisites

- `BRIGHTDATA_API_KEY` environment variable must be set
- `curl` and `jq` must be available

## Quick Start

User says: "Find me cybersecurity jobs in New York"
```bash
scripts/indeed_jobs_by_keyword.sh "cybersecurity" US "New York, NY"
```

User says: "Get details on this job: https://www.indeed.com/viewjob?jk=abc123"
```bash
scripts/indeed_jobs_by_url.sh "https://www.indeed.com/viewjob?jk=abc123"
```

## Workflow Decision Tree

```
User request arrives
├── Contains an Indeed URL?
│   ├── Job URL (/viewjob?) → indeed_jobs_by_url.sh [SYNC — fast, seconds]
│   ├── Company jobs URL (/cmp/*/jobs) → indeed_jobs_by_company.sh [ASYNC — minutes]
│   └── Company page URL (/cmp/*) → indeed_company_by_url.sh [SYNC — fast, seconds]
├── Asking about jobs?
│   └── Has keyword/location → indeed_jobs_by_keyword.sh [ASYNC — minutes]
├── Asking about companies?
│   ├── Has keyword → indeed_company_by_keyword.sh [ASYNC — minutes]
│   └── Has industry + state → indeed_company_by_industry.sh [ASYNC — minutes]
├── Check pending results → indeed_check_pending.sh
└── "List available scrapers" → indeed_list_datasets.sh
```

**IMPORTANT:** Always prefer sync (URL-based) scripts when the user provides a URL — they return in seconds. Async discovery scripts (keyword, industry) take 2–8 minutes. On messaging platforms, use `--no-wait` so the user isn't left waiting.

## Scripts Reference

| Script | Purpose | Example |
|--------|---------|---------|
| `indeed_jobs_by_url.sh` | Collect job details by URL(s) | `indeed_jobs_by_url.sh "https://indeed.com/viewjob?jk=abc"` |
| `indeed_jobs_by_keyword.sh` | Discover jobs by keyword search | `indeed_jobs_by_keyword.sh "nurse" US "Ohio"` |
| `indeed_jobs_by_company.sh` | Discover jobs from company page | `indeed_jobs_by_company.sh "https://indeed.com/cmp/Google/jobs"` |
| `indeed_company_by_url.sh` | Collect company info by URL | `indeed_company_by_url.sh "https://indeed.com/cmp/Google"` |
| `indeed_company_by_keyword.sh` | Discover companies by keyword | `indeed_company_by_keyword.sh "Tesla"` |
| `indeed_company_by_industry.sh` | Discover companies by industry/state | `indeed_company_by_industry.sh "Technology" "Texas"` |
| `indeed_poll_and_fetch.sh` | Poll async job and fetch results | `indeed_poll_and_fetch.sh <snapshot_id>` |
| `indeed_check_pending.sh` | Check/fetch completed pending searches | `indeed_check_pending.sh` |
| `indeed_list_datasets.sh` | List available Indeed dataset IDs | `indeed_list_datasets.sh` |

## Sync vs Async

- **Sync** (`/scrape`): Use for collect-by-URL with ≤5 URLs. Returns data in seconds. Always prefer this when the user provides a URL.
- **Async** (`/trigger` + poll): Used by discovery scripts (keyword, industry). Takes 2–8 minutes.

### Fire-and-Forget Mode (Recommended for messaging platforms)

Discovery scripts support `--no-wait` to trigger a search and return immediately:

```bash
scripts/indeed_jobs_by_keyword.sh "nurse" US "Ohio" --no-wait
# Returns: {"status":"pending","snapshot_id":"s_abc123","description":"nurse jobs in Ohio, US"}
```

Tell the user: "I've kicked off a search for nurse jobs in Ohio — I'll check back for results shortly."

Later, check for completed results:
```bash
scripts/indeed_check_pending.sh
```

### Exit Codes

| Code | Meaning | Agent should... |
|------|---------|-----------------|
| 0 | Success — results on stdout | Summarize results for user |
| 1 | Error — something failed | Report the error |
| 2 | Deferred — still processing, saved to pending | Tell user "results are still processing, I'll follow up" |

When a script exits with code 2, the snapshot has been saved to `~/.config/indeed-brightdata/pending.json`. Run `indeed_check_pending.sh` on your next opportunity to retrieve results.

## Output Handling

All scripts output JSON to stdout. **Never dump raw JSON at the user.** Summarize results in a readable format.

### Job Results — Show these fields:
- **Title** (job_title)
- **Company** (company_name)
- **Location** (location)
- **Salary** (salary_formatted) — if available
- **Link** (url or apply_link)

### Company Results — Show these fields:
- **Name** (name)
- **Rating** (overall rating) — if available
- **Industry** (industry)
- **HQ** (headquarters)
- **Open Jobs** (jobs_count)

### Formatting Rules:
- Show **max 5 results** in the initial summary
- End with "Want to see more?" if there are additional results
- Use a clean list or table format
- Include direct links so the user can click through

## Options

All discovery scripts support:
- `--limit N` — Max total results to return
- `--limit-per-input N` — Max results per input (reduces processing time)
- `--no-wait` — Fire-and-forget mode (trigger and exit immediately)
- `--help` — Show usage information

Job keyword search also supports:
- `--domain DOMAIN` — Indeed domain (default: indeed.com)
- `--date-posted "Last 24 hours"` — Filter by recency
- `--pay RANGE` — Filter by pay range
- `--radius MILES` — Location radius

**Tip:** Use `--limit-per-input 10` to speed up discovery queries. Fewer results = faster Bright Data processing.

## Full API Reference

See `references/api-reference.md` for complete parameter documentation, response schemas, country/domain mappings, and all endpoint details.
