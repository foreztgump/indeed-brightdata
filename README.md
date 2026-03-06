# indeed-brightdata

Search and scrape Indeed job listings and company information using Bright Data's Web Scraper API. Works with Claude Code, Claude Desktop, Cursor, Codex, OpenClaw, and any agent supporting the [Agent Skills](https://agentskills.io) standard.

## Compatibility

| Platform | Install Method | Auto-Update |
|----------|---------------|-------------|
| Claude Code | Symlink or Plugin Marketplace | Yes (git pull) |
| Claude Desktop | ZIP upload | No (re-package) |
| Cursor | Symlink | Yes (git pull) |
| Codex | Symlink | Yes (git pull) |
| OpenClaw | Symlink | Yes (git pull) |

## Quick Start

```bash
git clone https://github.com/foreztgump/indeed-brightdata.git
cd indeed-brightdata
./install.sh --platform claude-code
```

## Prerequisites

- `curl` and `jq` installed
- Bash 4.0+
- A [Bright Data](https://brightdata.com) account with Indeed scraper access
- `BRIGHTDATA_API_KEY` environment variable set

## Installation

### Claude Code (Recommended)

**Option A --- Install script:**

```bash
git clone https://github.com/foreztgump/indeed-brightdata.git
cd indeed-brightdata
./install.sh --platform claude-code
```

**Option B --- Plugin marketplace:**

```bash
/plugin marketplace add foreztgump/indeed-brightdata
```

### Claude Desktop

```bash
git clone https://github.com/foreztgump/indeed-brightdata.git
cd indeed-brightdata
make package
```

Then upload `indeed-brightdata.zip` via **Settings > Features > Skills > Upload skill** in Claude Desktop.

### Cursor

```bash
git clone https://github.com/foreztgump/indeed-brightdata.git
cd indeed-brightdata
./install.sh --platform cursor
```

### Codex

```bash
git clone https://github.com/foreztgump/indeed-brightdata.git
cd indeed-brightdata
./install.sh --platform codex
```

### OpenClaw

```bash
git clone https://github.com/foreztgump/indeed-brightdata.git
cd indeed-brightdata
./install.sh --platform openclaw
```

This creates a symlink at `~/.openclaw/skills/indeed-brightdata`.

### All Platforms at Once

```bash
./install.sh --all
```

### Universal CLI (Community)

If you use the [add-skill](https://add-skill.org) CLI:

```bash
npx add-skill foreztgump/indeed-brightdata
```

## Usage

### Job Search by Keyword

```bash
scripts/indeed_jobs_by_keyword.sh "software engineer" US "Austin, TX"
scripts/indeed_jobs_by_keyword.sh "nurse" US "Ohio" --date-posted "Last 24 hours" --limit 20

# Fire-and-forget (returns immediately, check later):
scripts/indeed_jobs_by_keyword.sh "nurse" US "Ohio" --no-wait
scripts/indeed_check_pending.sh
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
| `indeed_check_pending.sh` | Check/fetch completed pending searches |
| `indeed_list_datasets.sh` | List/save available dataset IDs |

All scripts support `--help` for detailed usage.

## Development

```bash
make test      # Run all tests
make package   # Build ZIP for Claude Desktop
make help      # Show all targets
```

## License

MIT
