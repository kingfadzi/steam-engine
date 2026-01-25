#!/bin/bash
#
# Steampipe service start wrapper
# Creates secrets symlink and sources environment before starting
#
set -e

SECRETS_DIR="/opt/wsl-secrets"
WIN_SECRETS="${WIN_MOUNT:-/mnt/c/devhome/projects/steamengine}/secrets"

# Create symlink to Windows secrets if not exists
if [ ! -e "$SECRETS_DIR" ] && [ -d "$WIN_SECRETS" ]; then
    ln -sf "$WIN_SECRETS" "$SECRETS_DIR"
fi

# Source environment file if exists
if [ -f "$SECRETS_DIR/steampipe.env" ]; then
    set -a
    source "$SECRETS_DIR/steampipe.env"
    set +a
fi

# Start steampipe
exec /opt/steampipe/steampipe/steampipe service start --foreground
