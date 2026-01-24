#!/bin/bash
# Load secrets from Windows mount
#
# Secrets directory: /opt/wsl-secrets/
# This should be symlinked to Windows: C:\devhome\projects\steamengine\secrets\
#
# Expected files:
#   steampipe.env - Jira/GitLab/Bitbucket credentials
#   gateway.env   - DW connection settings

SECRETS_DIR="/opt/wsl-secrets"
WIN_SECRETS="${WIN_MOUNT:-/mnt/c/devhome/projects/steamengine}/secrets"

# Create symlink to Windows secrets if not exists
if [ ! -d "$SECRETS_DIR" ] && [ -d "$WIN_SECRETS" ]; then
    sudo ln -sf "$WIN_SECRETS" "$SECRETS_DIR" 2>/dev/null || true
fi

# Load steampipe secrets
if [ -f "$SECRETS_DIR/steampipe.env" ]; then
    set -a
    source "$SECRETS_DIR/steampipe.env"
    set +a
fi

# Load gateway secrets
if [ -f "$SECRETS_DIR/gateway.env" ]; then
    set -a
    source "$SECRETS_DIR/gateway.env"
    set +a
fi
