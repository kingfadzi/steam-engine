#!/bin/bash
#
# Steampipe service start
#
set -e

SECRETS="/opt/wsl-secrets/steampipe.env"

# Check secrets
if [ ! -f "$SECRETS" ]; then
    echo "ERROR: Secrets not configured: $SECRETS"
    echo ""
    echo "Create secrets file:"
    echo "  cp /opt/steampipe/config/steampipe.env.example /mnt/c/.../secrets/steampipe.env"
    echo "  # Edit with your credentials"
    echo "  wsl --shutdown && wsl -d steam-engine"
    exit 1
fi

# Source secrets
set -a
source "$SECRETS"
set +a

# Environment
export STEAMPIPE_INSTALL_DIR=/opt/steampipe
export HOME=/opt/steampipe

# Start
exec /opt/steampipe/steampipe/steampipe service start --foreground
