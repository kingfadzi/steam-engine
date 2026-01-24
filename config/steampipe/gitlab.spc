# GitLab Plugin Configuration
# Credentials loaded from environment at runtime
#
# Required environment variables:
#   GITLAB_URL   - GitLab server URL (e.g., https://gitlab.company.com)
#   GITLAB_TOKEN - Personal Access Token with api scope
#
# Set these in /opt/wsl-secrets/steampipe.env or Windows environment

connection "gitlab" {
  plugin  = "theapsgroup/gitlab"
  baseurl = env("GITLAB_URL")
  token   = env("GITLAB_TOKEN")
}

plugin "theapsgroup/gitlab" {
  limiter "gitlab_api_limit" {
    max_concurrency = 3
    bucket_size     = 30
    fill_rate       = 5
  }
}
