#!/bin/bash
# Validate secrets mount and postgres binaries before steampipe service starts
# Called as ExecStartPre in steampipe.service

set -e

SECRETS_DIR="/opt/wsl-secrets"
SECRETS_FILE="$SECRETS_DIR/steampipe.env"
PG_BIN="/opt/steampipe/db/14.19.0/postgres/bin"

echo "=== Steampipe Pre-Start Validation ==="

# Check if steampipe is installed (bundle must be installed post-import)
if [ ! -x "/opt/steampipe/steampipe/steampipe" ]; then
    echo ""
    echo "ERROR: Steampipe not installed!"
    echo ""
    echo "Run the installer:"
    echo "  install-steampipe.sh"
    echo ""
    echo "Or with custom bundle path:"
    echo "  install-steampipe.sh /mnt/c/path/to/steampipe-bundle.tgz"
    exit 1
fi

# Validate secrets mount
if [ ! -d "$SECRETS_DIR" ]; then
    echo "ERROR: Secrets directory missing: $SECRETS_DIR"
    exit 1
fi

if [ -z "$(ls -A $SECRETS_DIR 2>/dev/null)" ]; then
    echo ""
    echo "ERROR: Secrets directory is empty!"
    echo ""
    echo "The Windows secrets mount failed. To fix:"
    echo ""
    echo "1. Create the secrets directory on Windows (PowerShell):"
    echo "   mkdir C:\\devhome\\projects\\steamengine\\secrets"
    echo ""
    echo "2. Copy the example file and configure:"
    echo "   cp /opt/steampipe/config/steampipe.env.example C:\\devhome\\projects\\steamengine\\secrets\\steampipe.env"
    echo "   # Or from WSL:"
    echo "   cp /opt/steampipe/config/steampipe.env.example /mnt/c/devhome/projects/steamengine/secrets/steampipe.env"
    echo ""
    echo "3. Edit steampipe.env with your credentials"
    echo ""
    echo "4. Restart WSL:"
    echo "   wsl --shutdown"
    echo "   wsl -d steam-engine"
    echo ""
    echo "Current fstab entry:"
    grep wsl-secrets /etc/fstab 2>/dev/null || echo "  (none found)"
    exit 1
fi

# Validate steampipe.env exists
if [ ! -f "$SECRETS_FILE" ]; then
    echo ""
    echo "ERROR: steampipe.env not found!"
    echo ""
    echo "Copy the example and configure:"
    echo "  cp /opt/steampipe/config/steampipe.env.example $SECRETS_FILE"
    echo ""
    echo "Then edit with your credentials (JIRA_URL, JIRA_TOKEN, etc.)"
    echo ""
    echo "Files in secrets directory:"
    ls -la "$SECRETS_DIR" 2>/dev/null
    exit 1
fi

# Validate postgres binaries exist
if [ ! -x "$PG_BIN/postgres" ]; then
    echo "ERROR: Postgres binary missing: $PG_BIN/postgres"
    echo "STEAMPIPE_INSTALL_DIR=${STEAMPIPE_INSTALL_DIR:-not set}"
    echo ""
    echo "Directory listing:"
    ls -la /opt/steampipe/db/ 2>/dev/null || echo "  No /opt/steampipe/db directory found"
    ls -la /opt/steampipe/db/14.19.0/ 2>/dev/null || echo "  No /opt/steampipe/db/14.19.0 directory found"
    ls -la /opt/steampipe/db/14.19.0/postgres/ 2>/dev/null || echo "  No postgres directory found"
    exit 1
fi

# Validate steampipe binary
if [ ! -x "/opt/steampipe/steampipe/steampipe" ]; then
    echo "ERROR: Steampipe binary missing or not executable"
    ls -la /opt/steampipe/steampipe/ 2>/dev/null || echo "  No steampipe directory found"
    exit 1
fi

echo "Validation passed"
echo "  Secrets: $SECRETS_FILE"
echo "  Postgres: $PG_BIN/postgres"
echo "  Steampipe: /opt/steampipe/steampipe/steampipe"
