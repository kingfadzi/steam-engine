#!/bin/bash
# Load steam-engine secrets from Windows mount (for interactive shells)
#
# Secrets are mounted via fstab at boot:
#   /mnt/c/devhome/projects/steamengine/secrets -> /opt/wsl-secrets
#
# Expected files:
#   steampipe.env - Jira/GitLab/Bitbucket credentials
#   gateway.env   - DW connection settings (optional)

SECRETS_DIR="/opt/wsl-secrets"

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
