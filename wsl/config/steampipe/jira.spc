# Jira Plugin Configuration
# Credentials loaded from environment at runtime
#
# Required environment variables:
#   JIRA_URL   - Jira server URL (e.g., https://jira.company.com)
#   JIRA_TOKEN - Personal Access Token
#
# Set these in /opt/wsl-secrets/steampipe.env or Windows environment

connection "jira" {
  plugin                = "jira@1.1.0"
  base_url              = env("JIRA_URL")
  personal_access_token = env("JIRA_TOKEN")
}

plugin "jira" {
  limiter "jira_api_limit" {
    max_concurrency = 2
    bucket_size     = 20
    fill_rate       = 3
  }
}
