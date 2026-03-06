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
│   ├── Job URL (/viewjob?) → indeed_jobs_by_url.sh
│   ├── Company jobs URL (/cmp/*/jobs) → indeed_jobs_by_company.sh
│   └── Company page URL (/cmp/*) → indeed_company_by_url.sh
├── Asking about jobs?
│   └── Has keyword/location → indeed_jobs_by_keyword.sh
├── Asking about companies?
│   ├── Has keyword → indeed_company_by_keyword.sh
│   └── Has industry + state → indeed_company_by_industry.sh
└── "List available scrapers" → indeed_list_datasets.sh
```

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
| `indeed_list_datasets.sh` | List available Indeed dataset IDs | `indeed_list_datasets.sh` |

## Sync vs Async

- **Sync** (`/scrape`): Use for collect-by-URL with ≤5 URLs. Returns data inline.
- **Async** (`/trigger` + poll): Used automatically by discovery scripts (keyword, industry). Returns `snapshot_id`, then `indeed_poll_and_fetch.sh` polls until ready.

Discovery scripts handle async automatically — you don't need to call `indeed_poll_and_fetch.sh` manually unless you want to check a previous snapshot.

## Output Handling

All scripts output JSON to stdout. Parse with `jq`:

```bash
# Get top 5 job titles and companies
scripts/indeed_jobs_by_keyword.sh "engineer" US "Austin" | jq '.[0:5] | .[] | {title: .job_title, company: .company_name, salary: .salary_formatted}'
```

Summarize results for the user: title, company, salary, location, and apply link. Offer to show full details for specific listings.

## Options

Most scripts support these flags:
- `--limit N` — Max results to return
- `--help` — Show usage information

Job keyword search also supports:
- `--domain DOMAIN` — Indeed domain (default: indeed.com)
- `--date-posted "Last 24 hours"` — Filter by recency
- `--pay RANGE` — Filter by pay range
- `--radius MILES` — Location radius

## Full API Reference

See `references/api-reference.md` for complete parameter documentation, response schemas, country/domain mappings, and all endpoint details.
