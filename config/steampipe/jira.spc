# Jira Plugin Configuration
# Credentials loaded from environment at runtime
#
# Required environment variables:
#   JIRA_URL   - Jira server URL (e.g., https://jira.company.com)
#   JIRA_PERSONAL_ACCESS_TOKEN - Personal Access Token (for DC/Server)
#
# Set these in /opt/wsl-secrets/steampipe.env or Windows environment

connection "jira" {
  plugin                = "turbot/jira"
  base_url              = env("JIRA_URL")
  personal_access_token = env("JIRA_PERSONAL_ACCESS_TOKEN")
}

plugin "turbot/jira" {
  limiter "jira_api_limit" {
    max_concurrency = 1
    bucket_size     = 5
    fill_rate       = 1
  }
}
