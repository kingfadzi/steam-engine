connection "gitlab" {
  plugin  = "theapsgroup/gitlab"
  token   = "glpat-xxxx"
  baseurl = "https://your-gitlab-server.com"
}

plugin "theapsgroup/gitlab" {
  limiter "gitlab_api_limit" {
    max_concurrency = 3
    bucket_size     = 30
    fill_rate       = 5      # 5 req/s = 300/min (under 600 limit)
  }
}
