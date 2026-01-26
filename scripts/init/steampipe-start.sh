#!/bin/bash
#
# Steampipe service start wrapper
# Sources environment and starts steampipe
#
set -e

SECRETS_DIR="/opt/wsl-secrets"
RUNTIME_DIR="/run/steampipe"

# Source environment file
if [ -f "$SECRETS_DIR/steampipe.env" ]; then
    set -a
    source "$SECRETS_DIR/steampipe.env"
    set +a
fi

# Ensure runtime environment
export STEAMPIPE_INSTALL_DIR="$RUNTIME_DIR"
export STEAMPIPE_MOD_LOCATION="$RUNTIME_DIR"
export HOME="${HOME:-/opt/steampipe}"

# Start steampipe from tmpfs
exec "$RUNTIME_DIR/steampipe/steampipe" service start --foreground
