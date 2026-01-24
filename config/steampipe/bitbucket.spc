# Bitbucket Plugin Configuration
# Credentials loaded from environment at runtime
#
# Required environment variables:
#   BITBUCKET_URL      - Bitbucket server URL (optional, for Server/DC)
#   BITBUCKET_USERNAME - Username
#   BITBUCKET_PASSWORD - App password (not account password)
#
# Set these in /opt/wsl-secrets/steampipe.env or Windows environment

connection "bitbucket" {
  plugin   = "bitbucket"
  base_url = env("BITBUCKET_URL")
  username = env("BITBUCKET_USERNAME")
  password = env("BITBUCKET_PASSWORD")
}

plugin "bitbucket" {
  limiter "bitbucket_api_limit" {
    max_concurrency = 3
    bucket_size     = 30
    fill_rate       = 5
  }
}
