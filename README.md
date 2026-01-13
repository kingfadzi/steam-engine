# Steam Engine - Steampipe Docker

Steampipe SQL query engine with GitLab, Jira, and Bitbucket plugins.

## Quick Start

```bash
# Configure credentials
cp .env.example .env
# Edit config/*.spc files with your credentials

# Build and run
docker compose up -d

# Query
docker compose exec steampipe steampipe query "select * from jira_board"
```

## Connect via PostgreSQL

```bash
psql -h localhost -p 9193 -U steampipe -d steampipe
```

## Configuration

Edit files in `config/`:

| File | Purpose |
|------|---------|
| `jira.spc` | Jira DC/Server (PAT auth) |
| `gitlab.spc` | GitLab (token auth) |
| `bitbucket.spc` | Bitbucket (app password) |

### Example: jira.spc
```hcl
connection "jira" {
  plugin                = "jira"
  base_url              = "http://your-jira:8080"
  personal_access_token = "your-pat-token"
}
```

### Example: gitlab.spc
```hcl
connection "gitlab" {
  plugin  = "theapsgroup/gitlab"
  token   = "glpat-xxxx"
  baseurl = "https://your-gitlab.com"
}
```

## Air-Gapped Deployment

```bash
# 1. On connected machine: download artifacts
scripts/download.sh

# 2. Copy to target server
scripts/stage_artifacts.sh <host> <base_path> <user>
# Default: mars /apps/data/steam-engine fadzi

# 3. Build offline (optional, for local testing)
scripts/build.sh
```

## CI/CD Pipeline

GitLab pipeline deploys to target server automatically.

**Pre-requisites (once before first deployment):**

1. Stage artifacts:
```bash
scripts/stage_artifacts.sh
```

2. Configure credentials on server:
```bash
ssh mars "vi /apps/data/steam-engine/shared/config/jira.spc"
ssh mars "vi /apps/data/steam-engine/shared/config/gitlab.spc"
ssh mars "vi /apps/data/steam-engine/shared/config/bitbucket.spc"
```

Both `shared/artifacts/` and `shared/config/` persist across releases.

## Notes

- Jira PAT only supports: `jira_board`, `jira_issue`, `jira_sprint`, `jira_backlog_issue`
- Uses `network_mode: host` for access to internal servers
- Based on AlmaLinux 9
- Offline build uses `Dockerfile.offline` with pre-downloaded artifacts
