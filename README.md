# indeed-brightdata

OpenClaw skill for searching and scraping Indeed job listings and company information using Bright Data's Web Scraper API.

## What It Does

- Search Indeed for jobs by keyword, location, and filters
- Collect detailed job listing data from Indeed URLs
- Look up company information, ratings, and reviews
- Discover companies by industry and state
- All output as structured JSON for agent consumption

## Prerequisites

- `curl` and `jq` installed
- A [Bright Data](https://brightdata.com) account with Indeed scraper access
- `BRIGHTDATA_API_KEY` environment variable set

## Setup

```bash
# Set your API key
export BRIGHTDATA_API_KEY="your-api-key-here"

# Discover and save dataset IDs (required for company endpoints)
scripts/indeed_list_datasets.sh --save
```

## Usage

### Job Search by Keyword

```bash
scripts/indeed_jobs_by_keyword.sh "software engineer" US "Austin, TX"
scripts/indeed_jobs_by_keyword.sh "nurse" US "Ohio" --date-posted "Last 24 hours" --limit 20
```

### Job Details by URL

```bash
scripts/indeed_jobs_by_url.sh "https://www.indeed.com/viewjob?jk=abc123"
```

### Company Lookup

```bash
scripts/indeed_company_by_url.sh "https://www.indeed.com/cmp/Google"
scripts/indeed_company_by_keyword.sh "Tesla"
scripts/indeed_company_by_industry.sh "Technology" "Texas"
```

### Jobs from Company Page

```bash
scripts/indeed_jobs_by_company.sh "https://www.indeed.com/cmp/Google/jobs"
```

## Scripts

| Script | Purpose |
|--------|---------|
| `indeed_jobs_by_url.sh` | Collect job details from Indeed URLs |
| `indeed_jobs_by_keyword.sh` | Search jobs by keyword/location |
| `indeed_jobs_by_company.sh` | Discover jobs from a company page |
| `indeed_company_by_url.sh` | Collect company info from URLs |
| `indeed_company_by_keyword.sh` | Search companies by keyword |
| `indeed_company_by_industry.sh` | Discover companies by industry/state |
| `indeed_poll_and_fetch.sh` | Poll async results and fetch data |
| `indeed_list_datasets.sh` | List/save available dataset IDs |

All scripts support `--help` for detailed usage.

## OpenClaw Integration

Add to your OpenClaw config:

```bash
openclaw config set skills.entries.indeed-brightdata.env.BRIGHTDATA_API_KEY "your-api-key"
```

## License

MIT
