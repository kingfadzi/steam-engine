# Steampipe Configuration Templates

These are **template files** for configuring Steampipe plugins. They are NOT used at runtime.

## Setup Instructions

1. Copy templates to the config directory:
   ```bash
   mkdir -p /opt/steampipe/config
   cp *.spc /opt/steampipe/config/
   ```

2. Edit each file with your credentials:
   ```bash
   vi /opt/steampipe/config/jira.spc
   vi /opt/steampipe/config/gitlab.spc
   vi /opt/steampipe/config/bitbucket.spc
   ```

3. Secure the files (if running as steampipe user):
   ```bash
   sudo chown -R steampipe:steampipe /opt/steampipe/config
   sudo chmod 640 /opt/steampipe/config/*.spc
   ```

## Plugin Configuration

### Jira (jira.spc)

For Jira Data Center / Server:

```hcl
connection "jira" {
  plugin                = "jira@1.1.0"
  base_url              = "http://your-jira-server:8080"
  personal_access_token = "your-personal-access-token"
}
```

**Required fields:**
- `base_url`: Your Jira server URL
- `personal_access_token`: PAT generated from Jira profile settings

**Note:** Plugin version 1.1.0 is required for Jira Data Center. Version 2.x uses Cloud API only.

### GitLab (gitlab.spc)

For GitLab self-hosted or GitLab.com:

```hcl
connection "gitlab" {
  plugin  = "theapsgroup/gitlab"
  token   = "glpat-xxxxxxxxxxxxxxxxxxxx"
  baseurl = "https://your-gitlab-server.com"
}
```

**Required fields:**
- `token`: Personal access token with `api` scope
- `baseurl`: Your GitLab server URL (omit for GitLab.com)

### Bitbucket (bitbucket.spc)

For Bitbucket Cloud or Server:

```hcl
connection "bitbucket" {
  plugin   = "bitbucket"
  username = "your-username"
  password = "your-app-password"

  # For Bitbucket Server (uncomment):
  # base_url = "https://bitbucket.example.com/rest/api/1.0"
}
```

**Required fields:**
- `username`: Your Bitbucket username
- `password`: App password (not your account password)

**Alternative:** Set via environment variables:
- `BITBUCKET_USERNAME`
- `BITBUCKET_PASSWORD`

## Rate Limiting

Each config file includes rate limiter settings to prevent API throttling:

```hcl
plugin "jira" {
  limiter "jira_api_limit" {
    max_concurrency = 2    # Max parallel requests
    bucket_size     = 20   # Token bucket size
    fill_rate       = 3    # Tokens per second
  }
}
```

Adjust these values based on your server capacity and API limits.

## Environment Variables

Set `STEAMPIPE_CONFIG_PATH` in `steampipe.env` to point to your config directory:

```bash
STEAMPIPE_CONFIG_PATH=/etc/steampipe
```

This allows you to keep credentials separate from the application bundle.
