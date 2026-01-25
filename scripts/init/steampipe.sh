#!/bin/bash
#
# Steampipe initialization script
# Run before steampipe service starts
#
set -e

INSTALL_DIR="${STEAMPIPE_INSTALL_DIR:-/opt/steampipe}"
CONFIG_DIR="$INSTALL_DIR/config"
SECRETS_DIR="/opt/wsl-secrets"
WIN_SECRETS="${WIN_MOUNT:-/mnt/c/devhome/projects/steamengine}/secrets"

echo "Initializing Steampipe..."

# Create symlink to Windows secrets if not exists
if [ ! -e "$SECRETS_DIR" ] && [ -d "$WIN_SECRETS" ]; then
    echo "Creating secrets symlink: $SECRETS_DIR -> $WIN_SECRETS"
    ln -sf "$WIN_SECRETS" "$SECRETS_DIR"
fi

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

# Check for required environment variables
check_env() {
    local var="$1"
    if [ -z "${!var:-}" ]; then
        echo "WARNING: $var not set"
        return 1
    fi
    return 0
}

# Validate at least one data source is configured
echo "Checking data source configuration..."

HAS_SOURCE=false

if check_env "JIRA_URL" && check_env "JIRA_TOKEN"; then
    echo "  Jira: configured"
    HAS_SOURCE=true
else
    echo "  Jira: not configured (JIRA_URL, JIRA_TOKEN)"
fi

if check_env "GITLAB_URL" && check_env "GITLAB_TOKEN"; then
    echo "  GitLab: configured"
    HAS_SOURCE=true
else
    echo "  GitLab: not configured (GITLAB_URL, GITLAB_TOKEN)"
fi

if check_env "BITBUCKET_USERNAME" && check_env "BITBUCKET_PASSWORD"; then
    echo "  Bitbucket: configured"
    HAS_SOURCE=true
else
    echo "  Bitbucket: not configured (BITBUCKET_USERNAME, BITBUCKET_PASSWORD)"
fi

if [ "$HAS_SOURCE" = false ]; then
    echo ""
    echo "WARNING: No data sources configured!"
    echo "Set environment variables in /opt/wsl-secrets/steampipe.env"
fi

echo "Steampipe initialization complete."
