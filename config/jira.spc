connection "jira" {
  plugin               = "jira@1.1.0"
  base_url             = "http://your-jira-server:8080"
  personal_access_token = "your-pat"
}

plugin "jira" {
  limiter "jira_api_limit" {
    max_concurrency = 2
    bucket_size     = 20
    fill_rate       = 3      # Conservative for Jira DC
  }
}
