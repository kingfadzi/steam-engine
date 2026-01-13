connection "jira" {
  plugin = "jira@1.1.0"  # Pin to 1.1.0 for Jira DC (2.x uses Cloud v3 API)

  # Jira Data Center / Server base URL
  base_url = "http://your-jira-server:8080"

  # Jira DC authentication using Personal Access Token (PAT)
  personal_access_token = "your-pat-token"
}
