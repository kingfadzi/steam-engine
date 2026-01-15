connection "bitbucket" {
  plugin = "bitbucket"

  # Set via BITBUCKET_USERNAME and BITBUCKET_PASSWORD env vars
  # or uncomment below
  # username = "your-username"
  # password = "your-app-password"

  # For self-hosted Bitbucket Server:
  # base_url = "https://bitbucket.example.com/rest/api/1.0"
}

plugin "bitbucket" {
  limiter "bitbucket_api_limit" {
    max_concurrency = 3
    bucket_size     = 30
    fill_rate       = 5
  }
}
