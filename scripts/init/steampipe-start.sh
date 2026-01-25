#!/bin/bash
#
# Steampipe service start wrapper
# Creates secrets symlink and sources environment before starting
#
set -e

SECRETS_DIR="/opt/wsl-secrets"

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
