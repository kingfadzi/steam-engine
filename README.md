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

## Notes

- Jira PAT only supports: `jira_board`, `jira_issue`, `jira_sprint`, `jira_backlog_issue`
- Uses `network_mode: host` for access to internal servers
- Based on AlmaLinux 9
