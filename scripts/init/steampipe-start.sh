#!/bin/bash
#
# Steampipe service start wrapper
# Creates secrets symlink and sources environment before starting
#
set -e

SECRETS_DIR="/opt/wsl-secrets"
WIN_SECRETS="${WIN_MOUNT:-/mnt/c/devhome/projects/steamengine}/secrets"

# Create symlink to Windows secrets, or create directory if Windows folder missing
if [ ! -e "$SECRETS_DIR" ]; then
    if [ -d "$WIN_SECRETS" ]; then
        ln -sf "$WIN_SECRETS" "$SECRETS_DIR"
    else
        mkdir -p "$SECRETS_DIR"
        echo "WARNING: Windows secrets dir not found: $WIN_SECRETS"
        echo "Created empty: $SECRETS_DIR"
    fi
fi

# Source environment file if exists
if [ -f "$SECRETS_DIR/steampipe.env" ]; then
    set -a
    source "$SECRETS_DIR/steampipe.env"
    set +a
fi

# Export steampipe environment variables
export STEAMPIPE_INSTALL_DIR="${STEAMPIPE_INSTALL_DIR:-/opt/steampipe}"
export STEAMPIPE_MOD_LOCATION="${STEAMPIPE_MOD_LOCATION:-/opt/steampipe}"

# Start steampipe
exec /opt/steampipe/steampipe/steampipe service start --foreground
